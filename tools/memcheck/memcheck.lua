-- Lua heap usage of a TX12 game, measured with stock Lua 5.2.
-- usage: lua52/src/lua memcheck.lua <GAMES dir> <Game-X.lua> [frames] [seed]
--
-- Runs the game with random sticks, switches and wheel/ENTER events and
-- reports, in KB above the harness baseline:
--   init   live heap right after init()
--   live   highest live heap (measured after a full GC every 25 frames)
--   peak   highest heap seen after any frame, garbage included
-- "live" is what has to fit on the radio; "peak" shows how much garbage a
-- game makes between collections. EdgeTX keeps some tables in flash, so
-- the radio uses a little less than this.

local gdir, file = arg[1], arg[2]
local frames, seed = tonumber(arg[3] or 3000), tonumber(arg[4] or 1)
if not gdir or not file then print("usage: memcheck.lua <GAMES dir> <Game-X.lua> [frames] [seed]") os.exit(1) end
gdir = string.gsub(gdir, "/?$", "/")

-- EdgeTX API stubs ---------------------------------------------------------
LCD_W, LCD_H = 128, 64
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, BLINK, RIGHT, CENTER, BOLD = 0x100, 0x200, 0x400, 1, 2, 4, 8, 16
DOTTED, FORCE, ERASE, GREY_DEFAULT, SOLID, PREC1, PREC2, LEFT = 0x55, 1, 2, 4, 0xff, 32, 64, 0
PLAY_NOW, PLAY_BACKGROUND = 1, 2
EVT_VIRTUAL_EXIT, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1, 2, 3, 4
EVT_VIRTUAL_ENTER_LONG, EVT_VIRTUAL_MENU, EVT_VIRTUAL_INC, EVT_VIRTUAL_DEC = 5, 6, 7, 8
EVT_ENTER_BREAK, EVT_EXIT_BREAK, EVT_ROT_LEFT, EVT_ROT_RIGHT = 2, 1, 4, 3
EVT_PLUS_FIRST, EVT_MINUS_FIRST, EVT_PLUS_BREAK, EVT_MINUS_BREAK = 9, 10, 11, 12
EVT_PLUS_REPT, EVT_MINUS_REPT, EVT_MENU_BREAK, EVT_PAGE_BREAK = 13, 14, 15, 16

local t, stick = 0, {}
function getTime() return t end
function getValue(n) return stick[n] or 0 end
function getDateTime() return { year = 2026, mon = 1, day = 1, hour = 12, min = math.floor(t / 6000) % 60, sec = math.floor(t / 100) % 60 } end
function playTone() end
function playFile() end
function playNumber() end
function playHaptic() end
function killEvents() end
local noop = function() end
lcd = setmetatable({}, { __index = function() return noop end })

local function path(p) return gdir .. string.gsub(p, "^/SCRIPTS/GAMES/", "") end
local written = {}
local realio = io
io = {
  open = function(p, m)
    if m and string.sub(m, 1, 1) == "w" then written[p] = ""; return { p = p, w = true } end
    if written[p] then return { data = written[p], pos = 1 } end
    local h = realio.open(path(p), "rb")
    if not h then return nil end
    return { h = h }
  end,
  read = function(f, n)
    if f.h then return f.h:read(n or 1) or "" end
    local s = string.sub(f.data, f.pos, f.pos + (n or 1) - 1); f.pos = f.pos + #s; return s
  end,
  write = function(f, ...) if f.w then for _, v in ipairs({...}) do written[f.p] = written[f.p] .. tostring(v) end end end,
  close = function(f) if f.h then f.h:close() end end,
}
function loadScript(p) return loadfile(path(p)) end
function dir() return function() return nil end end

-- run ------------------------------------------------------------------------
local function kb() return collectgarbage("count") end
local function full() collectgarbage("collect"); collectgarbage("collect"); return kb() end

math.randomseed(seed)
local rnd = math.random
local evs = { 0, 0, 0, 0, 0, 0, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, 0 }
local sticks = { "ail", "ele", "thr", "rud" }

local base = full()
local chunk, err = loadfile(gdir .. file)
if not chunk then print(file .. ": LOAD ERROR " .. tostring(err)) os.exit(1) end
local g = chunk()
if g.init then g.init() end
local initLive = full() - base
local live, peak = initLive, initLive
local status = "ok"
for f = 1, frames do
  t = t + 5
  for _, s in ipairs(sticks) do stick[s] = rnd(-1024, 1024) end
  if f % 6 == 0 then stick.sa = (rnd(0, 1) == 1) and 1024 or -1024 end
  if f % 7 == 0 then stick.sd = (rnd(0, 1) == 1) and 1024 or -1024 end
  local ok, r = pcall(g.run, evs[rnd(#evs)])
  if not ok then status = "ERROR " .. tostring(r); break end
  if r ~= 0 and r ~= nil then
    -- the game asked to exit: start it again so menus and play both get covered
    g = chunk(); if g.init then g.init() end
  end
  local k = kb() - base
  if k > peak then peak = k end
  if f % 25 == 0 then
    local l = full() - base
    if l > live then live = l end
  end
end
print(string.format("%-24s init %5.1f KB  live %5.1f KB  peak %5.1f KB  %s", file, initLive, live, peak, status))
