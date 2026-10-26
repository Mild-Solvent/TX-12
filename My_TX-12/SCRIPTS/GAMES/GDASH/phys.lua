-- Geometry Dash physics, one fixed 20 ms step. Loaded only while playing:
--   tile, step, music, endX, newPlayer = loadScript(this)()(levelTable)
--   step(p, press, hold): press = new press this step (SA/SD down-edge or ENTER),
--                         hold = SA/SD held this step (a press counts as held)
-- editors/geodash-editor.html has a line-by-line JavaScript copy: change both.
--
-- TILES (one byte per cell, rows bottom to top, "." = empty)
--  #  block (solid 8x8)          =  slab (solid top half)
--  ^  spike                      v  hanging spike
--  orbs, press while touching (reach 4 px around the icon), each once per touch:
--  o  yellow: jump 180           i  pink: small jump 140      r  red: big jump 230
--  q  blue: gravity flip         e  green: flip + jump 180    b  black: slam down 300
--  a  green dash: dash straight while held      h  pink dash: flip, then dash
--  pads, touch:
--  p  yellow 250   k  pink 180   f  red 300   u  blue: gravity flip   w  spider: teleport + flip
--  portals: fire once when the icon's centre enters the column, any row
--  C cube  U ufo  S ship  B ball  W wave  R robot  X spider  Z swing
--  G gravity up  g gravity down  m mini  n normal size  D dual  d single
--  0 1 2 3 4  speed 50 70 90 110 130 px/s
--  T  teleport: icon jumps to the row of the "t" in the same column
--  t  teleport exit (marker only)
-- Flying modes (ufo, ship, wave, swing) use the whole 6-row field: ground to ceiling.
-- Level rows may be run-length coded: "c*N" = char c repeated byte(N)-32 times
-- (plain rows load too); they stay coded in memory, see window() below.
local GY, CY, DT, BUF = 58, 10, 0.02, 0.12
local GC, JV, PADV = 800, 180, 250  -- cube/robot/spider gravity, jump, yellow pad
local GU, UV = 520, 135             -- ufo gravity, flap
local SHU, SHD, FM = 700, 600, 150  -- ship accel held/released, ship+swing max speed
local GB, BV = 700, 60              -- ball gravity, flip push
local RJV, RT = 130, 0.16           -- robot rise speed while held, max rise time
local SWG = 600                     -- swing gravity
local NOTES = "C C#D D#E F F#G G#A A#B "

return function(lv)
-- Rows stay run-length coded in memory, so a long level costs only its file
-- size; a window of 128 columns per row is decoded when needed. For row r:
-- W[r] coded row, W[r+6] decoded window, W[r+12] its first column,
-- W[r+18] / W[r+24] scan cursor: byte position of a token that starts at that column.
local W, len = {}, 0
for r = 1, 6 do
  local s, n, p = lv[r], 0, 1
  if type(s) ~= "string" then s = "" end
  for it = 1, #s do
    if not string.byte(s, p) then break end
    if string.byte(s, p + 1) == 42 then n, p = n + (string.byte(s, p + 2) or 33) - 32, p + 3
    else n, p = n + 1, p + 1 end
  end
  W[r], W[r + 6], W[r + 12], W[r + 18], W[r + 24], lv[r] = s, "", -999, 1, 0, nil
  if n > len then len = n end
end
local endX = len * 8 + 16

local function window(r, w)
  if w < 0 then w = 0 end
  local e = W[r]
  if w < W[r + 24] then W[r + 18], W[r + 24] = 1, 0 end
  local pos, col, p1, c1 = W[r + 18], W[r + 24], nil, 0
  for it = 1, #e do
    if not string.byte(e, pos) or col >= w + 128 then break end
    local n, np = 1, pos + 1
    if string.byte(e, np) == 42 then n, np = (string.byte(e, np + 1) or 33) - 32, np + 2 end
    if col + n <= w then W[r + 18], W[r + 24] = np, col + n
    elseif not p1 then p1, c1 = pos, col end
    pos, col = np, col + n
  end
  W[r + 6], W[r + 12] = "", w
  if p1 then
    local s = string.gsub(string.sub(e, p1, pos - 1), "(.)%*(.)", function(c, k) return string.rep(c, string.byte(k) - 32) end)
    W[r + 6] = string.sub(s, w - c1 + 1, w - c1 + 128)
  end
end

local function tile(c, r)
  if c < 0 or r < 0 or r > 5 then return 46 end
  r = r + 1
  local i = c - W[r + 12]
  if i < 0 or i >= 128 then window(r, c - 20); i = c - W[r + 12] end
  return string.byte(W[r + 6], i + 1) or 46
end
local function rowTop(r) return GY - 8 * r - 8 end
local function rowOf(y)
  local r = math.floor((GY - 1 - y) / 8)
  if r < 0 then r = 0 elseif r > 5 then r = 5 end
  return r
end
-- solid part of a tile: "#" block, "=" slab (top half)
local function solid(t, r)
  local top = rowTop(r)
  if t == 35 then return top, top + 8 end
  if t == 61 then return top, top + 4 end
  return nil
end
local function hit(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end
local function size(p) if p.mi then return 5 end return 7 end

local function newPlayer()
  return { x = 0, y = GY - 7, vy = 0, g = 1, m = 0, mi = false, du = false, spd = 90, pc = -1,
    buf = 0, gr = true, orb = -1, pad = -1, rt = 0, da = false,
    y2 = 0, vy2 = 0, g2 = -1, gr2 = false, buf2 = 0, orb2 = -1, pad2 = -1, rt2 = 0, da2 = false,
    dead = false, won = false }
end

-- dual: the second icon's fields live in *2 and are swapped in to step it
local function swap(p)
  for a, b in string.gmatch("y y2 vy vy2 g g2 gr gr2 buf buf2 orb orb2 pad pad2 rt rt2 da da2", "(%S+) (%S+)") do
    p[a], p[b] = p[b], p[a]
  end
end

-- spider: jump to the nearest surface the other way, flip gravity
local function spider(p, s)
  local g, c0, c1 = p.g, math.floor((p.x + 1) / 8), math.floor((p.x + s - 2) / 8)
  local ny = CY
  if g < 0 then ny = GY - s end
  for c = c0, c1 do
    for r = 0, 5 do
      local top, bot = solid(tile(c, r), r)
      if top then
        if g > 0 and bot <= p.y + 1 and bot > ny then ny = bot
        elseif g < 0 and top >= p.y + s - 1 and top - s < ny then ny = top - s end
      end
    end
  end
  p.y, p.g, p.vy, p.gr = ny, -g, 0, false
end

local function portals(p, cc)
  local tp, er = false, nil
  for r = 0, 5 do
    local t = tile(cc, r)
    if t == 71 or t == 103 then
      p.g = 1
      if t == 71 then p.g = -1 end
      p.g2 = -p.g
    elseif t >= 48 and t <= 52 then p.spd = 50 + 20 * (t - 48)
    elseif t == 109 or t == 110 then
      local mi = t == 109
      if mi ~= p.mi then
        local d = 2
        if not mi then d = -2 end
        if p.g > 0 then p.y = p.y + d end
        if p.g2 > 0 then p.y2 = p.y2 + d end
        p.mi = mi
      end
    elseif t == 68 then
      if not p.du then
        p.du, p.y2, p.vy2, p.g2, p.gr2, p.buf2 = true, CY + GY - size(p) - p.y, -p.vy, -p.g, p.gr, p.buf
        p.orb2, p.pad2, p.rt2, p.da2 = -1, -1, 0, false
      end
    elseif t == 100 then p.du = false
    elseif t == 84 then tp = true
    elseif t == 116 then er = r
    elseif t > 64 then
      local i = string.find("CUSBWRXZ", string.char(t), 1, true)
      if i then p.m, p.rt, p.da, p.rt2, p.da2 = i - 1, 0, false, 0, false end
    end
  end
  if tp and er then
    p.y = rowTop(er)
    if p.g > 0 then p.y = p.y + 8 - size(p) end
    p.y2 = CY + GY - size(p) - p.y
  end
end

-- input, orbs and pads (before the icon moves)
local function pre(p, hold)
  local s, m, g, k = size(p), p.m, p.g, 1
  if p.mi then k = 0.8 end
  local b = p.buf > 0
  if m == 1 or m == 7 then
    if b then
      p.buf, p.gr, b = 0, false, false
      if m == 1 then p.vy = -UV * k * g else p.g = -g; g = -g end
    end
  elseif m == 0 or m == 3 or m == 5 or m == 6 then
    if p.gr and (b or (hold and m ~= 6)) then
      p.buf, p.gr, b = 0, false, false
      if m == 3 then p.g = -g; g = -g; p.vy = BV * g
      elseif m == 6 then spider(p, s); g = p.g
      elseif m == 5 then p.vy = -RJV * k * g; p.rt = RT
      else p.vy = -JV * k * g end
    end
  end
  local c0, c1 = math.floor((p.x - 4) / 8), math.floor((p.x + s + 3) / 8)
  local r0, r1 = rowOf(p.y + s + 3), rowOf(p.y - 4)
  for c = c0, c1 do
    for r = r0, r1 do
      local t = tile(c, r)
      if t > 96 then
        local key, ch = c * 8 + r, string.char(t)
        local o, d = string.find("oirqebah", ch, 1, true), string.find("pkfuw", ch, 1, true)
        if m == 4 then  -- the wave ignores jump orbs and jump pads
          if o == 1 or o == 2 or o == 3 or o == 6 then o = nil end
          if d and d < 4 then d = nil end
        end
        if o and b and key ~= p.orb and hit(p.x - 4, p.y - 4, s + 8, s + 8, c * 8, rowTop(r), 8, 8) then
          p.orb, p.buf, p.gr, p.rt, b = key, 0, false, 0, false
          if o == 4 or o == 5 or o == 8 then p.g = -g; g = -g end
          if o >= 7 then p.da = true; p.vy = 0
          elseif o == 4 then p.vy = 60 * g
          else
            local v = JV
            if o == 2 then v = 140 elseif o == 3 then v = 230 elseif o == 6 then v = -300 end
            p.vy = -v * k * g
          end
        elseif d and key ~= p.pad and hit(p.x, p.y, s, s, c * 8, rowTop(r), 8, 8) then
          p.pad, p.gr, p.rt = key, false, 0
          if d == 5 then spider(p, s); g = p.g
          elseif d == 4 then p.g = -g; g = -g; p.vy = 120 * g
          else
            local v = PADV
            if d == 2 then v = 180 elseif d == 3 then v = 300 end
            p.vy = -v * k * g
          end
        end
      end
    end
  end
end

-- speed, movement, landing, death (after x has moved)
local function post(p, hold)
  local s, m, g, k = size(p), p.m, p.g, 1
  if p.mi then k = 0.8 end
  if p.da and not hold then p.da = false end
  if p.da then p.vy = 0
  elseif m == 4 then
    local w = p.spd
    if p.mi then w = w * 2 end
    if hold then p.vy = -w * g else p.vy = w * g end
  elseif m == 2 or m == 7 then
    local a = SHD
    if m == 7 then a = SWG elseif hold then a = -SHU end
    if p.mi then a = a * 1.25 end
    p.vy = p.vy + a * g * DT
    if p.vy > FM then p.vy = FM elseif p.vy < -FM then p.vy = -FM end
  elseif m == 5 and p.rt > 0 and hold then
    p.vy = -RJV * k * g; p.rt = p.rt - DT
  else
    p.rt = 0
    local gg = GC
    if m == 1 then gg = GU elseif m == 3 then gg = GB end
    p.vy = p.vy + gg * g * DT
  end
  if p.vy > 350 then p.vy = 350 elseif p.vy < -350 then p.vy = -350 end
  local py = p.y
  p.y = p.y + p.vy * DT
  p.gr = false
  -- land on / bump into solid tiles
  local c0, c1 = math.floor((p.x + 1) / 8), math.floor((p.x + s - 2) / 8)
  local r0, r1 = rowOf(p.y + s - 1), rowOf(p.y - 1)
  for c = c0, c1 do
    for r = r0, r1 do
      local top, bot = solid(tile(c, r), r)
      if top and p.y < bot and p.y + s > top then
        if p.vy * g >= 0 then
          if g > 0 and py + s <= top + 3 then p.y = top - s; p.vy = 0; p.gr = true
          elseif g < 0 and py >= bot - 3 then p.y = bot; p.vy = 0; p.gr = true end
        else
          if g > 0 and py >= bot - 3 then p.y = bot; p.vy = 0
          elseif g < 0 and py + s <= top + 3 then p.y = top - s; p.vy = 0 end
        end
      end
    end
  end
  if p.y + s >= GY then
    p.y = GY - s; p.vy = 0
    if g > 0 then p.gr = true end
  elseif p.y <= CY then
    p.y = CY; p.vy = 0
    if g < 0 then p.gr = true end
  end
  -- crash into block sides and spikes
  c0, c1 = math.floor(p.x / 8), math.floor((p.x + s - 1) / 8)
  r0, r1 = rowOf(p.y + s - 1), rowOf(p.y)
  for c = c0, c1 do
    for r = r0, r1 do
      local t = tile(c, r)
      local top, bot = solid(t, r)
      local tp = rowTop(r)
      if (top and hit(p.x, p.y + 1, s, s - 2, c * 8, top, 8, bot - top))
        or (t == 94 and hit(p.x + 1, p.y + 1, s - 2, s - 2, c * 8 + 2, tp + 3, 4, 5))
        or (t == 118 and hit(p.x + 1, p.y + 1, s - 2, s - 2, c * 8 + 2, tp, 4, 5)) then
        p.dead = true
        return
      end
    end
  end
end

local function step(p, press, hold)
  hold = hold or press
  if press then p.buf = BUF; p.buf2 = BUF
  else
    if p.buf > 0 then p.buf = p.buf - DT end
    if p.buf2 > 0 then p.buf2 = p.buf2 - DT end
  end
  local cc = math.floor((p.x + 3) / 8)
  if cc ~= p.pc then p.pc = cc; portals(p, cc) end
  pre(p, hold)
  if p.du then swap(p); pre(p, hold); swap(p) end
  p.x = p.x + p.spd * DT
  post(p, hold)
  if p.du and not p.dead then swap(p); post(p, hold); swap(p) end
  if p.x >= endX and not p.dead then p.won = true end
end

-- level tune (lv.m, unit lv.u s), looped; music(t) with t = seconds
-- since the attempt started queues each note when its time comes, t < 0 restarts
local mel, U, mPos, mT = lv.m, tonumber(lv.u) or 0.1, 1, 0
if type(mel) ~= "string" then mel = nil end
local function tok(pos)
  local a, e, w = string.find(mel, "(%S+)", pos)
  if not a then return nil end
  if string.sub(w, 1, 1) == "R" then return e + 1, 0, tonumber(string.sub(w, 2, 2)) or 1 end
  local nm, oc, ln = string.match(w, "^(%u#?)(%d)(%d)$")
  if not nm then return e + 1, 0, 1 end
  if string.len(nm) == 1 then nm = nm .. " " end
  local i = string.find(NOTES, nm, 1, true) or 19
  local midi = 12 * (tonumber(oc) + 1) + (i - 1) / 2
  return e + 1, 440 * 2 ^ ((midi - 69) / 12), tonumber(ln) or 1
end
local function music(t)
  if not mel then return end
  if t < 0 then mPos, mT = 1, 0; return end
  for k = 1, 4 do
    if mT > t then break end
    local np, f, ln = tok(mPos)
    if not np then np, f, ln = tok(1) end
    if not np then mel = nil; return end
    local d = ln * U
    if f > 0 and t - mT < 0.1 then playTone(math.floor(f), math.floor(d * 1000) - 20, 0, 0) end
    mPos, mT = np, mT + d
  end
end

return tile, step, music, endX, newPlayer
end
