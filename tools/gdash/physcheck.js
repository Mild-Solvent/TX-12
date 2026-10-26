// Mechanic checks for GDASH/phys.lua + GDASH/draw.lua and the editor's JS copy.
// usage: node physcheck.js <GDASH dir> [editor html]
// Every scenario runs through BOTH physics (Lua under fengari, JS from the editor)
// and must give identical states; then each expectation is checked. Also checks
// that every icon is drawn mirrored (upside down) under flipped gravity.
const fs = require("fs"), path = require("path"), vm = require("vm");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const gd = path.resolve(process.argv[2]).replace(/\\/g, "/");
const editor = process.argv[3] || path.join(__dirname, "../../editors/geodash-editor.html");
const core = /<script id="gd-core">([\s\S]*?)<\/script>/.exec(fs.readFileSync(editor, "utf8"))[1];
const ctx = { module: { exports: {} } }; vm.runInNewContext(core, ctx); const GD = ctx.module.exports;
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
function luaDo(code) {
  if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
  lua.lua_getglobal(L, to_luastring("OUT")); const s = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return s;
}
luaDo(`playTone = function() end
SOLID, FORCE, DOTTED, SMLSIZE, RIGHT, LCD_W, LCD_H = 0xff, 1, 0x55, 0x100, 4, 128, 64
LINES = {}
lcd = setmetatable({ drawLine = function(a, b, c, d) LINES[#LINES + 1] = a .. "," .. b .. "," .. c .. "," .. d end }, { __index = function() return function() end end })
PHYS = loadfile(${JSON.stringify(gd + "/phys.lua")})()
DRAW = loadfile(${JSON.stringify(gd + "/draw.lua")})()
OUT = ""`);
const FIELDS = ["x", "y", "vy", "g", "m", "mi", "du", "y2", "vy2", "g2", "gr", "da", "rt", "orb", "pad", "dead", "won"];
// run rows with a hold string ("1" held) for n steps in both physics; returns the JS states
function both(rows, holds, n, init) {
  const Lv = GD.makeLevel(rows), p = Lv.newPlayer(); Object.assign(p, init || {});
  const js = [];
  let prev = false;
  for (let k = 0; k < n; k++) { const h = holds[k] === "1"; Lv.step(p, h && !prev, h); prev = h; js.push(FIELDS.map(f => +p[f])); if (p.dead || p.won) break; }
  const out = luaDo(`
local rows = ${"{" + rows.map(r => JSON.stringify(r)).join(",") + "}"}
local tile, step, music, endX, newP = PHYS(rows)
local p = newP()
${Object.keys(init || {}).map(k => "p." + k + " = " + JSON.stringify(init[k])).join("\n")}
local holds, s, prev = ${JSON.stringify(holds)}, "", false
for k = 1, ${n} do
  local h = string.sub(holds, k, k) == "1"
  step(p, h and not prev, h); prev = h
  local t = {}
  for f in string.gmatch(${JSON.stringify(FIELDS.join(" "))}, "%S+") do
    local v = p[f]
    if v == true then v = 1 elseif v == false then v = 0 end
    t[#t + 1] = string.format("%.17g", v)
  end
  local line = ""
  for i = 1, #t do line = line .. t[i] .. " " end
  s = s .. line .. "\\n"
  if p.dead or p.won then break end
end
OUT = s`).trim().split("\n").map(l => l.trim().split(" ").map(Number));
  if (out.length !== js.length) throw new Error("Lua ran " + out.length + " steps, JS " + js.length);
  for (let k = 0; k < js.length; k++) for (let i = 0; i < FIELDS.length; i++)
    if (Math.abs(out[k][i] - js[k][i]) > 1e-9) throw new Error("step " + (k + 1) + " " + FIELDS[i] + ": Lua " + out[k][i] + " JS " + js[k][i]);
  return js.map(a => { const o = {}; FIELDS.forEach((f, i) => o[f] = a[i]); return o; });
}
const E = ".".repeat(60);
const flat = (extra) => { const r = [E, "", "", "", "", ""]; for (const [row, s] of extra || []) r[row] = s.padEnd(row ? 0 : 60, "."); return r; };
const at = (c, ch) => ".".repeat(c) + ch;
let fails = 0;
function check(name, ok, info) { console.log((ok ? "ok   " : "FAIL ") + name + (info ? "  (" + info + ")" : "")); if (!ok) fails++; }
const Z = n => "0".repeat(n), O = n => "1".repeat(n);

// UFO under flipped gravity: rises to the ceiling on its own, a flap pushes it down
{
  const s = both(flat([[0, at(2, "U")], [1, at(2, "G")]]), Z(40), 40);
  check("ufo, gravity up: falls up to the ceiling", s[39].y === 10 && s[39].gr === 1 && s[10].y < 51, "y " + s[10].y.toFixed(1) + " -> " + s[39].y);
  const f = both(flat([[0, at(2, "U")], [1, at(2, "G")]]), Z(40) + "1" + Z(9), 50);
  check("ufo, gravity up: a flap pushes it down", f[40].vy > 0 && f[45].y > f[40].y, "vy after flap " + f[40].vy.toFixed(1));
}
// cube: jump height ~20 px, holding jumps again on landing
{
  const s = both(flat(), "1" + Z(40), 41); const top = Math.min(...s.map(q => q.y));
  check("cube tap: jump ~20 px", Math.abs(51 - top - 20) < 2, (51 - top).toFixed(1) + " px");
  const h = both(flat(), O(60), 60); const lands = h.filter((q, i) => i && q.vy < 0 && h[i - 1].vy >= 0).length;
  check("cube hold: jumps again after landing", lands >= 2, lands + " jumps");
}
// ship: hold rises, release falls, capped at 150 px/s
{
  const s = both(flat([[0, at(1, "S")]]), O(40) + Z(40), 80);
  check("ship hold rises to the ceiling", s[39].y === 10, "y " + s[39].y);
  check("ship release falls back", s[79].y === 51 && s[60].vy <= 150, "vy max " + Math.max(...s.map(q => q.vy)));
}
// ball: press flips gravity, rolls on the ceiling
{
  const s = both(flat([[0, at(1, "B")]]), Z(3) + "1" + Z(30), 34);
  check("ball press flips gravity and reaches the ceiling", s[33].g === -1 && s[33].y === 10 && s[33].gr === 1);
}
// wave: 45 degrees up while held (vy = -speed), down when released; mini twice as steep
{
  const s = both(flat([[0, at(1, "W")]]), O(10) + Z(10), 20);
  check("wave up 45 deg while held", s[5].vy === -90 && Math.abs((s[4].y - s[5].y) - 1.8) < 1e-9);
  check("wave down when released", s[15].vy === 90);
  const m = both(flat([[0, at(1, "W")], [1, at(1, "m")]]), O(10), 10);
  check("mini wave twice as steep", m[5].vy === -180);
}
// robot: tap 13 px, full hold ~31 px
{
  const t = both(flat([[0, at(0, "R")]]), Z(2) + "1" + Z(40), 43), h = both(flat([[0, at(0, "R")]]), Z(2) + O(20) + Z(25), 45);
  const ht = 51 - Math.min(...t.map(q => q.y)), hh = 51 - Math.min(...h.map(q => q.y));
  check("robot: tap low, hold high", ht > 11 && ht < 15 && hh > 29 && hh < 33, "tap " + ht.toFixed(1) + " px, hold " + hh.toFixed(1) + " px");
}
// spider: press teleports to the ceiling (or under a block) instantly
{
  const s = both(flat([[0, at(1, "X")]]), Z(3) + "1" + Z(3), 7);
  check("spider press teleports to the ceiling", s[3].y === 10 && s[3].g === -1, "y " + s[3].y);
  const b = both(flat([[0, at(1, "X")], [3, "#".repeat(20)]]), Z(3) + "1" + Z(3), 7);
  check("spider teleports under a block above", b[3].y === 34 && b[3].g === -1 && b[6].y === 34, "y " + b[3].y + ", 3 steps later " + b[6].y);
}
// swing: every press flips gravity, also mid-air
{
  const s = both(flat([[0, at(0, "Z")]]), Z(2) + "1" + Z(8) + "1" + Z(20), 31);
  check("swing flips in the air", s[2].g === -1 && s[11].g === 1 && s[11].y < 51);
}
// orbs, pads, dash
{
  const yo = both(flat([[2, at(3, "o")]]), "1" + Z(10) + "1" + Z(30), 42);
  check("yellow orb: second jump in the air", yo[11].vy < -150 && yo[10].vy > -30 && yo[11].orb !== -1, "vy " + yo[10].vy.toFixed(0) + " -> " + yo[11].vy.toFixed(0));
  const da = both(flat([[1, at(2, "a")]]), "1" + Z(5) + O(25) + Z(20), 51);
  check("dash orb: straight line while held", da.some(q => q.da === 1) && da.filter(q => q.da === 1).every(q => q.vy === 0));
  const bl = both(flat([[0, at(2, "f")], [4, at(5, "b")]]), Z(18) + "1" + Z(20), 39);
  check("black orb slams down", bl.some(q => q.vy >= 299), "max vy " + Math.max(...bl.map(q => q.vy)));
  const sp = both(flat([[0, at(2, "w")]]), Z(10), 10);
  check("spider pad teleports to the ceiling", sp.some(q => q.y === 10 && q.g === -1));
}
// dual: second icon mirrored, same input
{
  const s = both(flat([[0, at(0, "D")]]), Z(3) + "1" + Z(10), 14);
  check("dual: mirror icon on the ceiling jumps down with the same press", s[2].du === 1 && s[2].y2 === 10 && s[5].y2 > 10 && s[5].y < 51);
}
// teleport
{
  const s = both(flat([[0, at(2, "T")], [4, at(2, "t")]]), Z(12), 12);
  check("teleport moves the icon to the t row", s[8].y < 20 && s[7].y === 51, "y " + s[7].y + " -> " + s[8].y.toFixed(1));
}
// speed 0
{
  const s = both(flat([[0, at(0, "0")]]), Z(3), 3);
  check("speed 0 = 50 px/s", Math.abs(s[2].x - 3) < 1e-9);
}
// slopes: ride up onto a block without a hop, down again, launch off a lone ramp
{
  const s = both(flat([[0, at(5, "/") + "#####`"]]), Z(150), 150);
  const top = Math.min(...s.map(q => q.y));
  check("slope up onto a block: no hop", !s[s.length - 1].dead && top === 43 && s.filter(q => q.y === 43).length > 20, "highest y " + top);
  check("slope down back to the ground", s[s.length - 1].y === 51 && s.slice(70, 85).every(q => q.gr === 1), "y " + s[s.length - 1].y);
  const l = both(flat([[0, at(5, "/")]]), Z(60), 60);
  const lt = Math.min(...l.map(q => q.y));
  check("lone up slope launches into the air", !l[l.length - 1].dead && lt < 41, "highest y " + lt.toFixed(1));
  const w = both(flat([[0, at(5, "`")]]), Z(40), 40);
  check("running into a down slope's high side kills", w[w.length - 1].dead === 1, "x " + w[w.length - 1].x.toFixed(1));
  const g = both(flat([[0, at(5, "()##][")]]), Z(150), 150);
  check("gentle ramp up and down", !g[g.length - 1].dead && Math.min(...g.map(q => q.y)) === 43, "highest y " + Math.min(...g.map(q => q.y)));
  const t = both(flat([[0, at(5, "/#####")], [1, at(6, "/####")]]), Z(150), 150);
  check("two-row ramp onto a block row 2", !t[t.length - 1].dead && Math.min(...t.map(q => q.y)) === 35, "highest y " + Math.min(...t.map(q => q.y)));
  const j = both(flat([[0, at(5, "/##########")]]), Z(23) + "1" + Z(40), 64);
  check("jump from a slope", j[23].vy < -150 && Math.min(...j.map(q => q.y)) < 30 && !j[j.length - 1].dead, "highest y " + Math.min(...j.map(q => q.y)).toFixed(1));
  const u = both(flat([[0, at(1, "G")], [5, at(5, "/////")]]), Z(60), 60);
  check("flipped gravity runs under a slope's flat bottom", !u[u.length - 1].dead && u.slice(40).every(q => q.y === 10), "y " + u[u.length - 1].y);
}
// taller levels: 10 rows, ceiling at 58 - 80 = -22
{
  const tall = [".".repeat(60), "", "", "", "", "", "", "", "", ""];
  const s = both([at(1, "S").padEnd(60, ".")].concat(tall.slice(1)), O(80), 80);
  check("10-row level: ship flies up to the higher ceiling", s[79].y === -22, "y " + s[79].y);
  const b = both([".".repeat(60), "", "", "", "", "", "", "", "", "#".repeat(30)], "1" + Z(5), 6);
  check("10-row level: blocks on row 10 are solid", b.length === 6 && b[5].y < 51);
  const res = luaDo(`
local d = DRAW(function() return 46 end, 1000, 10)
local P = { x = 100, y = -15, vy = 0, g = 1, m = 2, mi = false, gr = false, du = false }
local ys = {}
for k = 1, 12 do LINES = {}; d(P, nil, false, "", 0, 1) end
local lo, hi = 99, -99
for _, l in ipairs(LINES) do
  local a, b, c, e = string.match(l, "(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
  if tonumber(a) >= 28 and tonumber(c) <= 34 then lo = math.min(lo, tonumber(b), tonumber(e)); hi = math.max(hi, tonumber(b), tonumber(e)) end
end
OUT = lo .. " " .. hi`);
  const [lo, hi] = res.trim().split(" ").map(Number);
  check("10-row level: camera scrolls up with the icon (draw.lua)", lo >= 10 && hi <= 56, "icon drawn at screen y " + lo + ".." + hi);
}
// every icon is mirrored upside down under flipped gravity (draw.lua)
{
  const res = luaDo(`
local tile = function() return 46 end
local d = DRAW(tile, 1000)
local function shot(m, g, mi)
  LINES = {}
  local P = { x = 0, y = 30, vy = 0, g = g, m = m, mi = mi, gr = true, du = false }
  d(P, nil, true, "", 0, 1)
  local set = {}
  for _, l in ipairs(LINES) do
    local a, b, c, e = string.match(l, "(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
    a, b, c, e = tonumber(a), tonumber(b), tonumber(c), tonumber(e)
    if a >= 28 and a <= 34 and c >= 28 and c <= 34 and b >= 28 and b <= 38 and e >= 28 and e <= 38 then set[#set + 1] = {a, b, c, e} end
  end
  return set
end
local s = ""
for m = 0, 7 do
  for _, mi in ipairs({false, true}) do
    local size = mi and 5 or 7
    local up, down = shot(m, 1, mi), shot(m, -1, mi)
    local key = function(t, flip) local o = {} for _, q in ipairs(t) do local b, e = q[2], q[4]
      if flip then b, e = 30 + size - 1 - (b - 30), 30 + size - 1 - (e - 30) end
      o[#o + 1] = q[1] .. "," .. b .. "," .. q[3] .. "," .. e end
      local str = "" for i = 1, #o do for j = i + 1, #o do if o[j] < o[i] then o[i], o[j] = o[j], o[i] end end end
      for i = 1, #o do str = str .. o[i] .. ";" end return str end
    local same = key(up, true) == key(down, false)
    s = s .. m .. (mi and "m" or "") .. "=" .. (same and "1" or "0") .. "(" .. #up .. ") "
  end
end
OUT = s`);
  const bad = res.trim().split(" ").filter(x => x.includes("=0"));
  // the wave points along its motion, not its gravity: mode 4 is exempt
  check("every icon drawn upside down with gravity up (draw.lua)", bad.every(x => x.startsWith("4")), res.trim());
}
console.log(fails ? fails + " check(s) FAILED" : "all checks OK");
process.exit(fails ? 1 : 0);
