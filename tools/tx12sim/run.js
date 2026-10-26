// Runs EdgeTX B&W Lua games under fengari with a stubbed radio API.
// usage: node run.js <dir with game .lua files> [frames]
// env: SEEDS=n runs each game n times, TICK=t advances getTime() t ticks per frame
// Reports draws at negative coordinates (suspected to reset the radio). SA/SD are pressed at random.
const fs = require("fs");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const dir = process.argv[2];
const frames = +(process.argv[3] || 3000);
const seeds = +(process.env.SEEDS || 1), tick = +(process.env.TICK || 3);

const prelude = `
table = nil
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID, PREC1, PREC2, LEFT = 0x55, 1, 2, 4, 0xff, 32, 64, 0
PLAY_NOW, PLAY_BACKGROUND = 1, 2
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
EVT_VIRTUAL_ENTER_LONG, EVT_VIRTUAL_MENU, EVT_VIRTUAL_INC, EVT_VIRTUAL_DEC = 5, 6, 7, 8
EVT_ENTER_BREAK, EVT_EXIT_BREAK, EVT_ROT_LEFT, EVT_ROT_RIGHT = 2, 1, 4, 3
EVT_PLUS_FIRST, EVT_MINUS_FIRST, EVT_PLUS_BREAK, EVT_MINUS_BREAK = 9, 10, 11, 12
EVT_PLUS_REPT, EVT_MINUS_REPT, EVT_MENU_BREAK, EVT_PAGE_BREAK = 13, 14, 15, 16
__t = 0
function getTime() return __t end
function getValue(n) return __stick[n] or 0 end
__stick = {}
function playTone() end
function playFile() end
function playNumber() end
function playHaptic() end
function killEvents() end
function model() end
local function chk(...) for i = 1, select("#", ...) do local v = select(i, ...)
  if type(v) ~= "number" and type(v) ~= "string" and v ~= nil then error("bad lcd arg " .. i .. ": " .. type(v), 2) end end end
-- off-screen draws: negative coordinates are the suspected cause of a radio
-- reset (Dino), so they are counted separately from right/bottom overruns
__neg, __over, __firstNeg = 0, 0, nil
local function bounds(name, x, y, x2, y2)
  if type(x) ~= "number" or type(y) ~= "number" then return end
  x2, y2 = x2 or x, y2 or y
  if x < 0 or y < 0 or x2 < 0 or y2 < 0 then
    __neg = __neg + 1
    __firstNeg = __firstNeg or (name .. "(" .. x .. "," .. y .. ")")
  elseif x2 > LCD_W - 1 or y2 > LCD_H - 1 then
    __over = __over + 1
  end
end
local function rect(name) return function(x, y, w, h, ...)
  chk(x, y, w, h, ...)
  if type(w) == "number" and type(h) == "number" then bounds(name, x, y, x + w - 1, y + h - 1) end
end end
lcd = setmetatable({
  drawPoint = function(x, y, ...) chk(x, y, ...); bounds("drawPoint", x, y) end,
  drawLine = function(x1, y1, x2, y2, ...) chk(x1, y1, x2, y2, ...); bounds("drawLine", math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)) end,
  drawRectangle = rect("drawRectangle"),
  drawFilledRectangle = rect("drawFilledRectangle"),
  drawText = function(x, y, ...) chk(x, y, ...); bounds("drawText", x, y) end,
  drawNumber = function(x, y, ...) chk(x, y, ...); bounds("drawNumber", x, y) end,
}, { __index = function(_, k) return chk end })
do local cg = collectgarbage; collectgarbage = function(...) local ok, r = pcall(cg, ...); return ok and r or 0 end end  -- fengari lacks lua_gc
function getDateTime() return { year = 2026, mon = 1, day = 1, hour = 12, min = math.floor(__t / 6000) % 60, sec = math.floor(__t / 100) % 60 } end
`;

function run(file, seed) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const src = prelude + `__seed = ${seed}

    local io_ = io
    io = { open = function(p, m) return nil end, read = function() return nil end,
           write = function() end, close = function() end }
    local GDIR = ${JSON.stringify(dir.replace(/\\/g, "/") + "/")}
    function loadScript(p)
      local f = GDIR .. string.gsub(p, "^/SCRIPTS/GAMES/", "")
      return loadfile(f)
    end
    function dir(p) return coroutine.wrap(function() end) end
    local g = assert(loadfile(GDIR .. ${JSON.stringify(file)}))()
    if g.init then g.init() end
    local evs = { 0, 0, 0, EVT_VIRTUAL_ENTER, 0, 0, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, 0, 0 }
    local sticks = { "ail", "ele", "thr", "rud", "sa", "sd" }
    math.randomseed(__seed)
    for f = 1, ${frames} do
      __t = __t + ${tick}
      for _, s in ipairs(sticks) do __stick[s] = math.random(-1024, 1024) end
      local e = evs[math.random(#evs)]
      local r = g.run(e)
      if r ~= 0 and r ~= nil then return "exit " .. tostring(r) .. " at frame " .. f end
    end
    if __neg > 0 then return "ok, " .. __neg .. " draws at negative x/y (first " .. __firstNeg .. "), " .. __over .. " past right/bottom" end
    return "ok"
  `;
  if (lauxlib.luaL_loadstring(L, to_luastring(src)) !== lua.LUA_OK)
    return "LOAD " + lua.lua_tojsstring(L, -1);
  lua.lua_getglobal(L, to_luastring("debug")); lua.lua_getfield(L, -1, to_luastring("traceback")); lua.lua_remove(L, -2); lua.lua_insert(L, -2);
  if (lua.lua_pcall(L, 0, 1, -2) !== lua.LUA_OK) return "ERROR " + lua.lua_tojsstring(L, -1);
  return lua.lua_tojsstring(L, -1);
}

for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".lua")).sort())
  for (let sd = 1; sd <= seeds; sd++) { const r = run(f, sd); if (seeds === 1 || r !== "ok" && !r.startsWith("exit")) console.log(f.padEnd(22), "seed", sd, r); }
