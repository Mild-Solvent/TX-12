// Random-input soak test of Game-GeometryDash.lua under fengari (Lua 5.3, no table library).
// usage: node soak.js <Game-GeometryDash.lua> <GAMES dir containing GDASH/> [frames]
// SA is held/released at random (holds of 1-40 frames), wheel/ENTER/RTN at random,
// frames of 1-8 ticks. Counts the states visited, checks every tone, that the save
// file round-trips, and plays each level's tune for 60 s. Real level files are read
// through the io mock (the game counts L1, L2, ... with io.open). env SEED (1).
const fs = require("fs"), path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const game = path.resolve(process.argv[2]), gdir = path.resolve(process.argv[3]).replace(/\\/g, "/") + "/";
const frames = +(process.argv[4] || 30000);
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
lua.lua_register(L, to_luastring("__readfile"), (L) => {
  try { lua.lua_pushstring(L, to_luastring(fs.readFileSync(lua.lua_tojsstring(L, 1), "latin1"), true)); } catch (e) { lua.lua_pushnil(L); }
  return 1;
});
const src = `
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID = 0x55, 1, 2, 4, 0xff
PLAY_NOW = 1
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
__t = 0
function getTime() return __t end
collectgarbage = function() return 0 end  -- fengari has no lua_gc
local neg, firstNeg = 0, nil
local function chk(name, x, y)
  if type(x) ~= "number" or type(y) ~= "number" then error("bad lcd coords in " .. name, 2) end
  if x < 0 or y < 0 then neg = neg + 1; firstNeg = firstNeg or (name .. "(" .. x .. "," .. y .. ")") end
end
lcd = setmetatable({ drawLine = function(a, b, c, d) chk("drawLine", math.min(a, c), math.min(b, d)) end,
  drawRectangle = function(x, y) chk("drawRectangle", x, y) end, drawFilledRectangle = function(x, y) chk("drawFilledRectangle", x, y) end,
  drawPoint = function(x, y) chk("drawPoint", x, y) end, drawText = function(x, y) chk("drawText", x, y) end },
  { __index = function() return function() end end })
local GD = ${JSON.stringify(gdir)}
local function real(p) return GD .. string.gsub(p, "^/SCRIPTS/GAMES/", "") end
written = {}
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
local tones, bad = 0, 0
playTone = function(f, d) tones = tones + 1; if type(f) ~= "number" or f < 100 or f > 8000 or d <= 0 or f ~= math.floor(f) then bad = bad + 1 end end
local sw, swLeft = 0, 0
getValue = function(n)
  if n == "sa" then return sw end
  return math.random(-1024, 1024)
end
local g = assert(loadfile(${JSON.stringify(game.replace(/\\/g, "/"))}))()
g.init()
math.randomseed(${+(process.env.SEED || 1)})
local seen, modes, evs = {}, {}, { 0, 0, 0, 0, 0, 0, 0, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, 0, 0, 0, EVT_VIRTUAL_EXIT }
for f = 1, ${frames} do
  __t = __t + math.random(1, 8)
  if swLeft <= 0 then sw = (sw == 0) and 1024 or 0; swLeft = math.random(1, 40) end
  swLeft = swLeft - 1
  local e = evs[math.random(#evs)]
  local st = GD_UP(g.run, "state")
  if e == EVT_VIRTUAL_EXIT and (st == "pick" or math.random(4) > 1) then e = 0 end
  local r = g.run(e)
  if r ~= 0 then error("run returned " .. tostring(r)) end
  st = GD_UP(g.run, "state")
  seen[st] = (seen[st] or 0) + 1
  local P = GD_UP(g.run, "P")
  if st == "play" and P and P.m then local k = (P.mi and "mini " or "") .. P.m .. (P.du and " dual" or ""); modes[k] = (modes[k] or 0) + 1 end
end
local s = ""
for k, v in pairs(seen) do s = s .. k .. "=" .. v .. " " end
local ms = ""
for k, v in pairs(modes) do ms = ms .. "[" .. k .. "]=" .. v .. " " end
print("states: " .. s .. "tones=" .. tones .. " badTones=" .. bad .. " negativeDraws=" .. neg .. (firstNeg and (" first " .. firstNeg) or ""))
print("frames per mode (0 cube 1 ufo 2 ship 3 ball 4 wave 5 robot 6 spider 7 swing): " .. ms)
for k, v in pairs(written) do print(k .. ": " .. string.gsub(v, "%s+", " ")) end
-- a fresh copy must read the saved values back (picker shows them)
local g2 = assert(loadfile(${JSON.stringify(game.replace(/\\/g, "/"))}))()
g2.init()
local b1, b2 = GD_UP(g.run, "best"), GD_UP(g2.run, "best")
local same = true
for i = 1, GD_UP(g.run, "NLEV") do if b1[i] ~= b2[i] then same = false end end
print("save round-trip " .. (same and "ok" or "MISMATCH") .. ", levels " .. GD_UP(g2.run, "NLEV"))
for lv = 1, GD_UP(g2.run, "NLEV") do
  GD_UP(g2.run, "loadLevel")(lv)
  local music = GD_UP(g2.run, "music")
  music(-1)
  local n0, b0 = tones, bad
  for t = 0, 3000 do music(t * 0.02) end
  print("L" .. lv .. " music: " .. (tones - n0) .. " notes in 60 s, bad " .. (bad - b0))
end
`;
if (lauxlib.luaL_loadstring(L, to_luastring(src)) !== lua.LUA_OK) { console.log("LOAD", lua.lua_tojsstring(L, -1)); process.exit(1); }
lua.lua_getglobal(L, to_luastring("debug")); lua.lua_getfield(L, -1, to_luastring("traceback")); lua.lua_remove(L, -2); lua.lua_insert(L, -2);
if (lua.lua_pcall(L, 0, 0, -2) !== lua.LUA_OK) { console.log("ERROR", lua.lua_tojsstring(L, -1)); process.exit(1); }
