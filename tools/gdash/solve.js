// node solve.js <game.lua> <dir containing GDASH/> [levels csv]
// BFS over press times on the 20 ms physics grid; then replays the found
// press list through the real run() (ENTER events) and measures each press window.
const fs = require("fs");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const game = process.argv[2], gdir = process.argv[3], lvls = process.argv[4] || "1,2,3,4,5,6,7,8";
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
local OFF, NOWIN = ${+(process.env.OFF || 0)}, ${process.env.NOWIN ? 'true' : 'false'}
local MINGAP = ${+(process.env.MINGAP || 5)}
local GAME, GRID, CAP = ${JSON.stringify(game)}, ${GRID}, ${CAP}
local g = assert(loadfile(GAME))()
g.init()
local sim = g.sim
local function clone(a) local b = {} for k, v in pairs(a) do b[k] = v end return b end
local function key(p)
  return string.format("%.1f|%.1f|%d|%s|%d|%d|%.2f|%s", p.y, p.vy, p.g, tostring(p.ufo), p.orb, p.pad, p.buf > 0 and p.buf or 0, tostring(p.gr)) .. "|" .. math.min(p._since or 99, MINGAP)
end
local function solve(lv)
  sim.load(lv)
  local front = { { p = sim.new() } }
  local step, lastx, peak = 0, 0, 0
  while step < 30000 do
    step = step + 1
    local nxt, seen = {}, {}
    for _, s in ipairs(front) do
      for pi = 0, 1 do
        local press = pi == 1
        if not press or ((step + OFF) % GRID == 0 and s.p.buf <= 0 and (s.p._since or 99) >= MINGAP) then
          local p = clone(s.p)
          sim.step(p, press)
          if press then p._since = 1 else p._since = (s.p._since or 99) + 1 end
          local h = s.h
          if press then h = { s = step, n = s.h, x = s.p.x } end
          if p.won then return h, step, peak end
          if not p.dead then
            lastx = p.x
            local k = key(p)
            if not seen[k] then seen[k] = true; nxt[#nxt + 1] = { p = p, h = h } end
          end
        end
      end
    end
    if #nxt > peak then peak = #nxt end
    if #nxt == 0 then return nil, "STUCK at column " .. math.floor(lastx / 8) .. " (x=" .. math.floor(lastx) .. ")", peak end
    if #nxt > CAP then for i = CAP + 1, #nxt do nxt[i] = nil end end
    front = nxt
  end
  return nil, "timeout", peak
end
-- BFS from state p: can some input sequence stay alive for 'hor' steps (or win)?
local function survive(p0, hor)
  local front = { p0 }
  for st = 1, hor do
    local nxt, seen = {}, {}
    for _, s in ipairs(front) do
      for pi = 0, 1 do
        if pi == 0 or (s.buf <= 0 and (s._since or 99) >= MINGAP) then
          local p = clone(s)
          sim.step(p, pi == 1)
          if pi == 1 then p._since = 1 else p._since = (s._since or 99) + 1 end
          if p.won then return true end
          if not p.dead then
            local k = key(p)
            if not seen[k] then seen[k] = true; nxt[#nxt + 1] = p end
          end
        end
      end
    end
    if #nxt == 0 then return false end
    if #nxt > 80 then for i = 81, #nxt do nxt[i] = nil end end
    front = nxt
  end
  return true
end
-- press list with press j moved to s1: alive and still able to go on for 3 s?
local function shiftOk(lv, presses, j, s1)
  sim.load(lv)
  local p = sim.new()
  local set = {}
  for i = 1, j - 1 do set[presses[i]] = true end
  set[s1] = true
  for k = 1, s1 do
    sim.step(p, set[k] == true)
    if p.dead then return false end
    if p.won then return true end
  end
  p._since = 1
  return survive(p, 100)
end
local function replay(lv, set, n)
  local g2 = assert(loadfile(GAME))()
  __t = 1000
  g2.init(); g2.run(0)
  for i = 2, lv do __t = __t + 1; g2.run(EVT_VIRTUAL_NEXT) end
  __t = __t + 1; g2.run(EVT_VIRTUAL_ENTER)
  for k = 1, n + 50 do
    __t = __t + 2
    local e = 0
    if set[k] then e = EVT_VIRTUAL_ENTER end
    g2.run(e)
    if g2.sim.state() == "win" then g2.run(EVT_VIRTUAL_EXIT); return true end
    if g2.sim.state() ~= "play" then return false end
  end
  return false
end
local out = {}
for lvs in string.gmatch(${JSON.stringify(lvls)}, "%d+") do
  local lv = tonumber(lvs)
  local h, n, peak = solve(lv)
  if not h and type(n) == "string" then
    out[#out + 1] = "L" .. lv .. " UNSOLVABLE: " .. n .. " peakStates=" .. peak
  else
    local list, set = {}, {}
    local XS = {}
    while h do list[#list + 1] = h.s; set[h.s] = true; XS[h.s] = h.x; h = h.n end
    local presses = {}
    for i = #list, 1, -1 do presses[#presses + 1] = list[i] end
    local rp = replay(lv, set, n)
    print("L" .. lv .. " solved, " .. #presses .. " presses, replay " .. tostring(rp))
    -- window of each press: contiguous shifts that still win
    local minW, minAt, sumW, W = 999, -1, 0, {}
    for j = 1, NOWIN and 0 or #presses do
      local s0 = presses[j]
      local lo, hi = 0, 0
      for dir = -1, 1, 2 do
        for d = 1, 5 do
          local s1 = s0 + dir * d
          if s1 < 1 or (j > 1 and s1 - presses[j - 1] < MINGAP) or (presses[j + 1] and presses[j + 1] - s1 < MINGAP) then break end
          local ok = shiftOk(lv, presses, j, s1)
          if not ok then break end
          if dir < 0 then lo = d else hi = d end
        end
      end
      local w = lo + hi + 1
      sumW = sumW + w
      W[j] = w
      if w < minW then minW, minAt = w, s0 end
    end
    out[#out + 1] = string.format("L%d SOLVED (presses >=" .. MINGAP * 20 .. "ms apart) %d steps (%.1fs), %d presses, replay-through-run()=%s, press window min %d steps (=%dms, at %.1fs) avg %.1f steps, peakStates=%d",
      lv, n, n * 0.02, #presses, tostring(rp), minW, minW * 20, minAt * 0.02, sumW / math.max(1, #presses), peak)
    local ps = ""
    for j = 1, #presses do ps = ps .. presses[j] .. "(c" .. math.floor(XS[presses[j]] / 8) .. "):" .. (W[j] or "-") .. " " end
    out[#out + 1] = "   presses(step): " .. ps
  end
  for i = 1, #out do print(out[i]) end
  out = {}
end
local s = ""
for k, v in pairs(__files) do s = s .. k .. " => " .. string.gsub(v, "%s", " ") end
print("save file: " .. s)
`;
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(prelude)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { console.log("prelude", lua.lua_tojsstring(L, -1)); process.exit(1); }
// keep table.unpack for the solver output only (the game ran its checks with table=nil)
if (lauxlib.luaL_loadstring(L, to_luastring(luaSrc)) !== lua.LUA_OK) { console.log("LOAD", lua.lua_tojsstring(L, -1)); process.exit(1); }
lua.lua_getglobal(L, to_luastring("debug")); lua.lua_getfield(L, -1, to_luastring("traceback")); lua.lua_remove(L, -2); lua.lua_insert(L, -2);
if (lua.lua_pcall(L, 0, 0, -2) !== lua.LUA_OK) console.log("ERROR", lua.lua_tojsstring(L, -1));
