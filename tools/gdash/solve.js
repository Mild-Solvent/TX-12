// Geometry Dash level solver and physics cross-check.
// usage: node solve.js <Game-GeometryDash.lua> <GAMES dir containing GDASH/> [levels csv]
//   e.g. node solve.js ../../My_TX-12/SCRIPTS/GAMES/Game-GeometryDash.lua ../../My_TX-12/SCRIPTS/GAMES 1,2,3
// For each level GDASH/L<n>.lua:
//  1. searches a winning input with the editor's solver (editors/geodash-editor.html,
//     <script id="gd-core">): breadth-first over 20 ms steps, inputs are SA hold
//     intervals (taps and holds), then measures each press window (and each
//     release window for holds) by shifting it +-1..5 steps;
//  2. replays the input through the editor's JS physics and through the game's own
//     Lua step() (via tools/gdash/hooks.lua) and compares x, y, vy, gravity, mode,
//     size, dual, second icon y, dead, won after EVERY step (must be identical);
//  3. replays it through the real game loop run() with 20 ms frames and SA
//     pressed/released via getValue("sa"), starting from the level picker; the
//     level must be completed on the same step.
// env: MINGAP (5) min steps between presses, MINHOLD (1) min hold steps,
//      MINREL (3) min steps released before the next press, CAP (3000)
//      states kept per step, NOWIN=1 skip windows, STRICTWIN=1 measure windows with MINGAP/MINREL
//      between presses (default: a shifted press only needs 1 released step / 2 steps from the last press), HOLDS=<dir> writes L<n>.holds
//      ("0"/"1" per step, for memplay.lua), EDITOR=<path> editor html.
const fs = require("fs"), path = require("path"), vm = require("vm");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const game = path.resolve(process.argv[2]), gdir = path.resolve(process.argv[3]);
const lvls = (process.argv[4] || "").split(",").filter(Boolean).map(Number);
const editor = process.env.EDITOR || path.join(__dirname, "../../editors/geodash-editor.html");
const html = fs.readFileSync(editor, "utf8");
const core = /<script id="gd-core">([\s\S]*?)<\/script>/.exec(html)[1];
const ctx = { module: { exports: {} } };
vm.runInNewContext(core, ctx);
const GD = ctx.module.exports;
const opts = { minGap: +(process.env.MINGAP || 5), minHold: +(process.env.MINHOLD || 1), minRelease: +(process.env.MINREL || 3), cap: +(process.env.CAP || 3000), noWindows: !!process.env.NOWIN, strictWindows: !!process.env.STRICTWIN };

// ---- Lua side: the real game under fengari, table library removed like on the radio
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
lua.lua_register(L, to_luastring("__readfile"), (L) => {
  try { lua.lua_pushstring(L, to_luastring(fs.readFileSync(lua.lua_tojsstring(L, 1), "latin1"), true)); } catch (e) { lua.lua_pushnil(L); }
  return 1;
});
function luaDo(code) {
  if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK) return "LOAD " + lua.lua_tojsstring(L, -1);
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { const e = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return "ERROR " + e; }
  return null;
}
function luaGet(name) { lua.lua_getglobal(L, to_luastring(name)); const s = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return s; }
const GDIR = gdir.replace(/\\/g, "/") + "/";
let err = luaDo(`
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID = 0x55, 1, 2, 4, 0xff
PLAY_NOW = 1
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
__t, __sw = 0, 0
function getTime() return __t end
function getValue(n) if n == "sa" then return __sw end return 0 end
function playTone() end
collectgarbage = function() return 0 end  -- fengari has no lua_gc
lcd = setmetatable({}, { __index = function() return function() end end })
local GD = ${JSON.stringify(GDIR)}
local function real(p) return GD .. string.gsub(p, "^/SCRIPTS/GAMES/", "") end
local written = {}
io = {
  open = function(p, m)
    if m and string.sub(m, 1, 1) == "w" then written[p] = ""; return { p = p, w = true } end
    local d = written[p] or __readfile(real(p))
    if not d then return nil end
    return { d = d, pos = 1 }
  end,
  read = function(f, n) if not f.d then return "" end local s = string.sub(f.d, f.pos, f.pos + (n or 1) - 1); f.pos = f.pos + #s; return s end,
  write = function(f, ...) if f.w then for _, v in ipairs({...}) do written[f.p] = written[f.p] .. tostring(v) end end end,
  close = function() end,
}
function loadScript(p) return loadfile(real(p)) end
dofile(${JSON.stringify(path.join(__dirname, "hooks.lua").replace(/\\/g, "/"))})
table = nil
GAMEFILE = ${JSON.stringify(game.replace(/\\/g, "/"))}
-- step the game's own physics with a hold string; one line per step
function LOCK(lv, bits)
  local g = assert(loadfile(GAMEFILE))()
  g.init()
  GD_UP(g.run, "loadLevel")(lv)
  local step, p = GD_UP(g.run, "step"), GD_UP(g.run, "newP")()
  local out, prev = {}, false
  for k = 1, #bits do
    local h = string.sub(bits, k, k) == "1"
    step(p, h and not prev, h)
    prev = h
    out[#out + 1] = string.format("%.17g %.17g %.17g %d %d %d %d %.17g %d %d", p.x, p.y, p.vy, p.g, p.m,
      p.mi and 1 or 0, p.du and 1 or 0, p.y2, p.dead and 1 or 0, p.won and 1 or 0)
    if p.dead or p.won then break end
  end
  local s = ""
  for i = 1, #out do s = s .. out[i] .. "\\n" end
  RESULT = s
end
-- play through run(): picker -> level lv -> SA from the hold string, 20 ms frames
function PLAY(lv, bits)
  local g = assert(loadfile(GAMEFILE))()
  __t, __sw = 1000, 0
  g.init()
  local function st() return GD_UP(g.run, "state") end
  __t = __t + 2; g.run(0)
  for i = 2, lv do __t = __t + 2; g.run(EVT_VIRTUAL_NEXT) end
  __t = __t + 2; g.run(EVT_VIRTUAL_ENTER)
  RESULT = "not started (" .. tostring(st()) .. ")"
  if st() ~= "play" then return end
  for k = 1, #bits + 50 do
    __sw = (string.sub(bits, k, k) == "1") and 1024 or 0
    __t = __t + 2
    g.run(0)
    local s = st()
    if s == "win" then RESULT = "win at step " .. k; return end
    if s ~= "play" then RESULT = s .. " at step " .. k; return end
  end
  RESULT = "still playing"
end
`);
if (err) { console.log(err); process.exit(1); }

function levelList() {
  if (lvls.length) return lvls;
  const out = [];
  for (let i = 1; i < 100 && fs.existsSync(path.join(gdir, "GDASH", "L" + i + ".lua")); i++) out.push(i);
  return out;
}
let fails = 0;
for (const lv of levelList()) {
  const text = fs.readFileSync(path.join(gdir, "GDASH", "L" + lv + ".lua"), "latin1");
  const P = GD.parseLevel(text);
  const t0 = Date.now();
  const res = GD.solveLevel(P.rows, opts);
  const head = "L" + lv + " " + JSON.stringify(P.name) + " (" + (P.compact ? "compact" : "plain") + ", " + text.length + " B)";
  if (!res.ok) { console.log(head + " UNSOLVABLE: " + res.text + " peakStates=" + res.peak); fails++; continue; }
  const rp = GD.replay(P.rows, res.presses);
  const bits = Array.from(GD.holdBits(res.presses, rp.steps)).slice(1, rp.steps + 1).join("");
  if (process.env.HOLDS) { fs.mkdirSync(process.env.HOLDS, { recursive: true }); fs.writeFileSync(path.join(process.env.HOLDS, "L" + lv + ".holds"), bits); }
  // lockstep: JS physics vs the game's Lua physics
  err = luaDo(`LOCK(${lv}, ${JSON.stringify(bits)})`);
  let lock = "ok";
  if (err) lock = err;
  else {
    const ll = luaGet("RESULT").trim().split("\n");
    if (ll.length !== rp.full.length) lock = "length differs: Lua " + ll.length + " steps, JS " + rp.full.length;
    for (let k = 0; k < ll.length && lock === "ok"; k++) {
      const a = ll[k].split(" ").map(Number), b = rp.full[k];
      for (let i = 0; i < b.length; i++) if (Math.abs(a[i] - b[i]) > 1e-9) { lock = "differs at step " + (k + 1) + " field " + i + ": Lua " + a[i] + " JS " + b[i]; break; }
    }
  }
  err = luaDo(`PLAY(${lv}, ${JSON.stringify(bits)})`);
  const play = err || luaGet("RESULT");
  const playOk = play === "win at step " + rp.steps;
  if (lock !== "ok" || !playOk || !rp.won) fails++;
  console.log(head + " " + res.text + ", peakStates=" + res.peak + ", " + ((Date.now() - t0) / 1000).toFixed(1) + "s");
  console.log("   JS replay " + (rp.won ? "win" : "FAIL") + " at step " + rp.steps + " | Lua step() lockstep " + lock + " | game run() " + play + (playOk ? " (same step)" : " MISMATCH"));
  console.log("   used (portals, orbs, pads activated; dash = steps dashing): " + Object.keys(rp.used).sort().map(k => k + "x" + rp.used[k]).join(" "));
  console.log("   presses step(col)[window" + (res.presses.some(p => p.rw) ? "/release window" : "") + "] hold length: " +
    res.presses.map(p => p.s + "(c" + p.col + ")[" + (p.w || "-") + (p.rw ? "/" + p.rw : "") + "]" + (p.e - p.s > 1 ? "h" + (p.e - p.s) : "")).join(" "));
}
console.log(fails ? fails + " level(s) FAILED" : "all levels OK");
process.exit(fails ? 1 : 0);
