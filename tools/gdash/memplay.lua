-- Heap of Game-GeometryDash.lua while playing one level, with stock Lua 5.2
-- (tools/memcheck/build-lua.sh builds it):
--   lua52/src/lua memplay.lua <GAMES dir> <level n> [holds file|-] [practice]
-- holds file: one character per 20 ms physics step, "1" = SA held, "0" = released
-- (solve.js writes one per level with HOLDS=<dir>). Without one SA is never pressed.
-- Runs the game through run() with 20 ms frames, takes a full GC every 10 frames
-- and reports the picker heap and the highest live heap while playing, in KB
-- above the harness baseline (same units as tools/memcheck/memcheck.lua).
-- With "practice" a checkpoint is placed every 2nd frame (up to the game's max).
-- STRIP=1: load GDASH/*.luac (compile them with "luac -s -o x.luac x.lua") instead
-- of the .lua, like the radio does for scripts loaded without debug info.
local gdir, lvn, hf, prac = arg[1], tonumber(arg[2] or 1), arg[3], arg[4] == "practice"
gdir = string.gsub(gdir, "/?$", "/")
dofile((string.gsub(arg[0], "[^/]*$", "")) .. "hooks.lua")
local strip = os.getenv("STRIP") == "1"
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID = 0x55, 1, 2, 4, 0xff
PLAY_NOW = 1
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
local t, sw, ele = 0, 0, 0
function getTime() return t end
function getValue(n) if n == "sa" then return sw elseif n == "ele" then return ele end return 0 end
function playTone() end
local noop = function() end
lcd = setmetatable({}, { __index = function() return noop end })
local function path(p) return gdir .. string.gsub(p, "^/SCRIPTS/GAMES/", "") end
local realio = io
io = {
  open = function(p, m)
    if m and string.sub(m, 1, 1) == "w" then return { w = true } end
    local h = realio.open(path(p), "rb")
    if not h then return nil end
    return { h = h }
  end,
  read = function(f, n) if f.h then return f.h:read(n or 1) or "" end return "" end,
  write = function() end,
  close = function(f) if f.h then f.h:close() end end,
}
function loadScript(p)
  if strip and string.find(p, "/GDASH/[a-z]+%.lua$") then
    local f = loadfile(path(p) .. "c")
    if f then return f end
  end
  return loadfile(path(p))
end
local holds = ""
if hf and hf ~= "" and hf ~= "-" then local h = realio.open(hf, "rb"); holds = h:read("*a"); h:close() end
local function full() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") end

local base = full()
local g = loadfile(gdir .. "Game-GeometryDash.lua")()
local function state() return GD_UP(g.run, "state") end
g.init()
t = t + 2; g.run(0)
for i = 2, lvn do t = t + 2; g.run(EVT_VIRTUAL_NEXT) end
if prac then ele = 1024; t = t + 2; g.run(0); ele = 0; t = t + 2; g.run(0) end
local pick = full() - base
t = t + 2; g.run(EVT_VIRTUAL_ENTER)
local live, at, f = 0, 0, 0
while state() ~= "pick" and f < 20000 do
  f = f + 1
  local c = string.sub(holds, f, f)
  sw = (c == "1") and 1024 or 0
  t = t + 2
  local e = 0
  if prac and f % 2 == 0 then e = EVT_VIRTUAL_NEXT end
  g.run(e)
  local st = state()
  if f % 10 == 0 or st ~= "play" then
    local k = full() - base
    if k > live then live, at = k, f end
  end
  if st == "win" or st == "dead" then break end
end
print(string.format("L%d picker live %.1f KB, play live max %.1f KB (frame %d), end state %s after %d frames (%.1f s)%s",
  lvn, pick, live, at, state(), f, f * 0.02, strip and " [stripped modules]" or ""))
