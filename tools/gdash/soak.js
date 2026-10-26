// node solve.js <game.lua> <dir containing GDASH/> [levels csv]
// BFS over press times on the 20 ms physics grid; then replays the found
// press list through the real run() (ENTER events) and measures each press window.
const fs = require("fs");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const game = process.argv[2], gdir = process.argv[3];
const GRID = +(process.env.GRID || 1), CAP = +(process.env.CAP || 3000);
const prelude = `
table = nil
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID = 0x55, 1, 2, 4, 0xff
PLAY_NOW = 1
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
__t = 0
function getTime() return __t end
function getValue(n) return 0 end
function playTone() end
collectgarbage = function() return 0 end
lcd = setmetatable({}, { __index = function() return function() end end })
__files = {}
local H = {}
io = { open = function(p, m) if m == "w" then local h = {p = p, buf = ""}; return h end
         if __files[p] then return {p = p, rd = __files[p]} end return nil end,
       read = function(h, n) return h.rd end,
       write = function(h, s) h.buf = h.buf .. s end,
       close = function(h) if h.buf then __files[h.p] = h.buf end end }
local GD = ${JSON.stringify(gdir + "/")}
function loadScript(p) return loadfile(GD .. string.gsub(p, "^/SCRIPTS/GAMES/", "")) end
`;
const luaSrc = `
-- random-input soak: counts states visited, checks the save file round-trips
local g = assert(loadfile(${JSON.stringify(game)}))()
local tones, bad = 0, 0
playTone = function(f, d, p, fl) tones = tones + 1; if type(f) ~= 'number' or f < 100 or f > 8000 or d <= 0 or f ~= math.floor(f) then bad = bad + 1 end end
g.init()
local seen, frames = {}, 0
math.randomseed(${+(process.env.SEED||1)})
local sw = 0
getValue = function(n)
  if n == "sa" or n == "sd" then return sw end
  return math.random(-1024, 1024)
end
local evs = { 0, 0, 0, 0, 0, 0, 0, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, 0, 0, 0, EVT_VIRTUAL_EXIT }
for f = 1, 30000 do
  __t = __t + math.random(1, 8)
  if math.random(10) == 1 then sw = (sw == 0) and 1024 or 0 end
  local e = evs[math.random(#evs)]
  if e == EVT_VIRTUAL_EXIT and g.sim.state() == "pick" then e = 0 end
  local r = g.run(e)
  local st = g.sim.state()
  seen[st] = (seen[st] or 0) + 1
end
local s = ""
for k, v in pairs(seen) do s = s .. k .. "=" .. v .. " " end
print("states: " .. s .. " tones=" .. tones .. " badTones=" .. bad)
for k, v in pairs(__files) do print(k .. ": " .. string.gsub(v, "%s+", " ")) end
-- reload: picker must read the saved values back
local g2 = assert(loadfile(${JSON.stringify(game)}))()
g2.init()
for lv = 1, 8 do
  g.sim.load(lv); g.sim.music(-1)
  local n0, b0 = tones, bad
  for t = 0, 3000 do g.sim.music(t * 0.02) end
  print("L" .. lv .. " music: " .. (tones - n0) .. " notes in 60 s, bad " .. (bad - b0))
end
print("reload ok, exit returns " .. tostring(g2.run(EVT_VIRTUAL_EXIT)))
`;
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(prelude)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { console.log("prelude", lua.lua_tojsstring(L, -1)); process.exit(1); }
// keep table.unpack for the solver output only (the game ran its checks with table=nil)
if (lauxlib.luaL_loadstring(L, to_luastring(luaSrc)) !== lua.LUA_OK) { console.log("LOAD", lua.lua_tojsstring(L, -1)); process.exit(1); }
lua.lua_getglobal(L, to_luastring("debug")); lua.lua_getfield(L, -1, to_luastring("traceback")); lua.lua_remove(L, -2); lua.lua_insert(L, -2);
if (lua.lua_pcall(L, 0, 0, -2) !== lua.LUA_OK) console.log("ERROR", lua.lua_tojsstring(L, -1));
