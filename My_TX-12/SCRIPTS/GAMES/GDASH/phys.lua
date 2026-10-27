-- Geometry Dash physics, one fixed 20 ms step. Loaded only while playing:
--   tile, step, music, endX, newPlayer, rows = loadScript(this)()(levelTable)
--   step(p, press, hold): press = new press this step (SA/SD down-edge or ENTER),
--                         hold = SA/SD held this step (a press counts as held)
-- editors/geodash-editor.html has a line-by-line JavaScript copy: change both.
-- Tile table: tools/gdash/levels.txt (header) and editors/README.md. A level has
-- 6 to 20 rows; flying modes use the whole field. Rows stay run-length coded in
-- memory ("c*N" = c repeated byte(N)-32 times), see window() below.
-- RAM: numbers are inline and locals reuse short names (every named constant and
-- distinct name costs heap). The editor keeps the names: GY 58 ground, DT 0.02,
-- BUF 0.12 press buffer, GC 800 gravity, JV 180 jump, PADV 250 yellow pad, GU 520 /
-- UV 135 ufo gravity / flap, SHU 700 / SHD 600 ship accel, FM 150 ship+swing max,
-- GB 700 / BV 60 ball, RJV 130 / RT 0.16 robot rise, SWG 600 swing gravity.
-- Row r (0 = ground) spans y = 50 - 8r .. 58 - 8r; ceiling CY = 58 - 8N; the dual
-- icon mirrors y as CY + 58 - size - y.

return function(lv)
-- N rows, ceiling CY (world y, negative for levels taller than one screen)
local N = 6
while N < 20 and type(lv[N + 1]) == "string" do N = N + 1 end
local CY = 58 - 8 * N
-- Rows stay run-length coded in memory, so a long level costs only its file
-- size; a window of 64 columns per row is decoded when needed. For row r:
-- W[r] coded row, W[r+N] decoded window, W[r+2N] its first column,
-- W[r+3N] / W[r+4N] scan cursor: byte position of a token that starts at that column.
local W, n = {}, 0
for r = 1, N do
  local s, c, i = lv[r], 0, 1
  if type(s) ~= "string" then s = "" end
  for k = 1, #s do
    if not string.byte(s, i) then break end
    if string.byte(s, i + 1) == 42 then c, i = c + (string.byte(s, i + 2) or 33) - 32, i + 3
    else c, i = c + 1, i + 1 end
  end
  W[r], W[r + N], W[r + 2 * N], W[r + 3 * N], W[r + 4 * N], lv[r] = s, "", -999, 1, 0, nil
  if c > n then n = c end
end
local endX = n * 8 + 16

-- decode row r's window starting at column w
-- (s coded row, i byte position at column c, a / b first token in the window and its column)
local function window(r, w)
  if w < 0 then w = 0 end
  local s, d, e = W[r], r + 3 * N, r + 4 * N
  if w < W[e] then W[d], W[e] = 1, 0 end
  local i, c, a, b = W[d], W[e], nil, 0
  for k = 1, #s do
    if not string.byte(s, i) or c >= w + 64 then break end
    local n, j = 1, i + 1
    if string.byte(s, j) == 42 then n, j = (string.byte(s, j + 1) or 33) - 32, j + 2 end
    if c + n <= w then W[d], W[e] = j, c + n
    elseif not a then a, b = i, c end
    i, c = j, c + n
  end
  W[r + N], W[r + 2 * N] = "", w
  if a then
    -- expand "c*N" runs with a plain loop: a gsub callback can't be paused
    -- by EdgeTX ("attempt to yield across a C-call boundary")
    local o, j = "", a
    while j < i do
      if string.byte(s, j + 1) == 42 then
        o, j = o .. string.rep(string.sub(s, j, j), (string.byte(s, j + 2) or 33) - 32), j + 3
      else
        o, j = o .. string.sub(s, j, j), j + 1
      end
    end
    W[r + N] = string.sub(o, w - b + 1, w - b + 64)
  end
end

local function tile(c, r)
  if c < 0 or r < 0 or r >= N then return 46 end
  r = r + 1
  local i = c - W[r + 2 * N]
  if i < 0 or i >= 64 then window(r, c - 20); i = c - W[r + 2 * N] end
  return string.byte(W[r + N], i + 1) or 46
end
-- row of a y coordinate, clamped to 0..N-1
local function rowOf(y)
  local r = math.floor((57 - y) / 8)
  if r < 0 then r = 0 elseif r >= N then r = N - 1 end
  return r
end
-- solid part of a tile: "#" block, "=" slab (top half); returns top, bottom
local function solid(t, r)
  local a = 50 - 8 * r
  if t == 35 then return a, a + 8 end
  if t == 61 then return a, a + 4 end
  return nil
end
-- slope surface: height above the tile's bottom at x offset l (0..8), and its gradient
local function slope(t, l)
  if t == 47 then return l, 1 elseif t == 96 then return 8 - l, -1
  elseif t == 40 then return l / 2, 0.5 elseif t == 41 then return 4 + l / 2, 0.5
  elseif t == 91 then return 8 - l / 2, -0.5 elseif t == 93 then return 4 - l / 2, -0.5 end
  return nil
end
-- boxes overlap: one at (a, b) size c x d, the other at (e, f) size g x h
local function hit(a, b, c, d, e, f, g, h)
  return a < e + g and e < a + c and b < f + h and f < b + d
end
local function size(p) if p.mi then return 5 end return 7 end

local function newPlayer()
  return { x = 0, y = 51, vy = 0, g = 1, m = 0, mi = false, du = false, spd = 90, pc = -1,
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

-- spider: jump to the nearest surface the other way (a = its y), flip gravity
local function spider(p, s)
  local g, a = p.g, CY
  if g < 0 then a = 58 - s end
  for c = math.floor((p.x + 1) / 8), math.floor((p.x + s - 2) / 8) do
    for r = 0, N - 1 do
      local t, b = solid(tile(c, r), r)
      if t then
        if g > 0 and b <= p.y + 1 and b > a then a = b
        elseif g < 0 and t >= p.y + s - 1 and t - s < a then a = t - s end
      end
    end
  end
  p.y, p.g, p.vy, p.gr = a, -g, 0, false
end

-- portals in column c (a = teleport seen, b = row of its exit)
local function portals(p, c)
  local a, b = false, nil
  for r = 0, N - 1 do
    local t = tile(c, r)
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
        p.du, p.y2, p.vy2, p.g2, p.gr2, p.buf2 = true, CY + 58 - size(p) - p.y, -p.vy, -p.g, p.gr, p.buf
        p.orb2, p.pad2, p.rt2, p.da2 = -1, -1, 0, false
      end
    elseif t == 100 then p.du = false
    elseif t == 84 then a = true
    elseif t == 116 then b = r
    elseif t > 64 then
      local i = string.find("CUSBWRXZ", string.char(t), 1, true)
      if i then p.m, p.rt, p.da, p.rt2, p.da2 = i - 1, 0, false, 0, false end
    end
  end
  if a and b then
    p.y = 50 - 8 * b
    if p.g > 0 then p.y = p.y + 8 - size(p) end
    p.y2 = CY + 58 - size(p) - p.y
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
      if m == 1 then p.vy = -135 * k * g else p.g = -g; g = -g end
    end
  elseif m == 0 or m == 3 or m == 5 or m == 6 then
    if p.gr and (b or (hold and m ~= 6)) then
      p.buf, p.gr, b = 0, false, false
      if m == 3 then p.g = -g; g = -g; p.vy = 60 * g
      elseif m == 6 then spider(p, s); g = p.g
      elseif m == 5 then p.vy = -130 * k * g; p.rt = 0.16
      else p.vy = -180 * k * g end
    end
  end
  local r0, r1 = rowOf(p.y + s + 3), rowOf(p.y - 4)
  for c = math.floor((p.x - 4) / 8), math.floor((p.x + s + 3) / 8) do
    for r = r0, r1 do
      local t = tile(c, r)
      if t > 96 then
        local i, a = c * 8 + r, string.char(t)
        local o, d = string.find("oirqebah", a, 1, true), string.find("pkfuw", a, 1, true)
        if m == 4 then  -- the wave ignores jump orbs and jump pads
          if o == 1 or o == 2 or o == 3 or o == 6 then o = nil end
          if d and d < 4 then d = nil end
        end
        if o and b and i ~= p.orb and hit(p.x - 4, p.y - 4, s + 8, s + 8, c * 8, 50 - 8 * r, 8, 8) then
          p.orb, p.buf, p.gr, p.rt, b = i, 0, false, 0, false
          if o == 4 or o == 5 or o == 8 then p.g = -g; g = -g end
          if o >= 7 then p.da = true; p.vy = 0
          elseif o == 4 then p.vy = 60 * g
          else
            local v = 180
            if o == 2 then v = 140 elseif o == 3 then v = 230 elseif o == 6 then v = -300 end
            p.vy = -v * k * g
          end
        elseif d and i ~= p.pad and hit(p.x, p.y, s, s, c * 8, 50 - 8 * r, 8, 8) then
          p.pad, p.gr, p.rt = i, false, 0
          if d == 5 then spider(p, s); g = p.g
          elseif d == 4 then p.g = -g; g = -g; p.vy = 120 * g
          else
            local v = 250
            if d == 2 then v = 180 elseif d == 3 then v = 300 end
            p.vy = -v * k * g
          end
        end
      end
    end
  end
end

-- speed, movement, landing, death (after x has moved)
-- (q = was on the ground, y = y before the move)
local function post(p, hold)
  local s, m, g, k, q = size(p), p.m, p.g, 1, p.gr
  if p.mi then k = 0.8 end
  if p.da and not hold then p.da = false end
  if p.da then p.vy = 0
  elseif m == 4 then
    local w = p.spd
    if p.mi then w = w * 2 end
    if hold then p.vy = -w * g else p.vy = w * g end
  elseif m == 2 or m == 7 then
    local a = 600
    if m == 2 and hold then a = -700 end
    if p.mi then a = a * 1.25 end
    p.vy = p.vy + a * g * 0.02
    if p.vy > 150 then p.vy = 150 elseif p.vy < -150 then p.vy = -150 end
  elseif m == 5 and p.rt > 0 and hold then
    p.vy = -130 * k * g; p.rt = p.rt - 0.02
  else
    p.rt = 0
    local a = 800
    if m == 1 then a = 520 elseif m == 3 then a = 700 end
    p.vy = p.vy + a * g * 0.02
  end
  if p.vy > 350 then p.vy = 350 elseif p.vy < -350 then p.vy = -350 end
  local y = p.y
  p.y = p.y + p.vy * 0.02
  p.gr = false
  -- land on / bump into solid tiles (a = top, b = bottom; a slope's e: only its flat bottom counts)
  local r0, r1 = rowOf(p.y + s - 1), rowOf(p.y - 1)
  for c = math.floor((p.x + 1) / 8), math.floor((p.x + s - 2) / 8) do
    for r = r0, r1 do
      local t = tile(c, r)
      local a, b = solid(t, r)
      local e = slope(t, 0)
      if e then a, b = 50 - 8 * r, 58 - 8 * r end
      if a and p.y < b and p.y + s > a then
        if p.vy * g >= 0 then
          if g > 0 and not e and y + s <= a + 3 then p.y = a - s; p.vy = 0; p.gr = true
          elseif g < 0 and y >= b - 3 then p.y = b; p.vy = 0; p.gr = true end
        else
          if g > 0 and y >= b - 3 then p.y = b; p.vy = 0
          elseif g < 0 and not e and y + s <= a + 3 then p.y = a - s; p.vy = 0 end
        end
      end
    end
  end
  -- slopes (normal gravity): stand on the highest point of the diagonal under the
  -- feet, stick to it going down, leave an up slope into the air with its rise speed
  -- (not onto a block or another slope), crash into a high side.
  -- f feet, u / v x range, e surface y, d its gradient, n the tile after it
  if g > 0 then
    local f, u, v, e, d, n = p.y + s, p.x + 1, p.x + s - 1, nil, 0, 46
    for c = math.floor(u / 8), math.floor(v / 8) do
      for r = rowOf(f + 3), rowOf(f - 9) do
        local t = tile(c, r)
        local h, i = slope(t, 0)
        if h and p.y < 58 - 8 * r then
          local l = u - c * 8
          if i > 0 then l = v - c * 8 end
          if l < 0 then l = 0 elseif l > 8 then l = 8 end
          h = slope(t, l)
          h = 58 - 8 * r - h
          if not e or h < e then e, d, n = h, i, tile(c + 1, r) end
        end
      end
    end
    if e and (p.vy >= 0 or p.vy >= -p.spd * d) then  -- not when rising faster than the slope (a jump)
      local i = 0
      if q and p.vy >= 0 then i = 3 end
      if f >= e - i and y + s <= e + 3 + p.spd * 0.02 then
        if d > 0 and (n == 35 or n == 61 or slope(n, 0)) then d = 0 end
        p.y, p.vy, p.gr = e - s, -p.spd * d, true
      elseif f > e + 3 then p.dead = true; return end
    end
  end
  if p.y + s >= 58 then
    p.y = 58 - s; p.vy = 0
    if g > 0 then p.gr = true end
  elseif p.y <= CY then
    p.y = CY; p.vy = 0
    if g < 0 then p.gr = true end
  end
  -- crash into block sides and spikes (d = top of the cell)
  r0, r1 = rowOf(p.y + s - 1), rowOf(p.y)
  for c = math.floor(p.x / 8), math.floor((p.x + s - 1) / 8) do
    for r = r0, r1 do
      local t = tile(c, r)
      local a, b = solid(t, r)
      local d = 50 - 8 * r
      if (a and hit(p.x, p.y + 1, s, s - 2, c * 8, a, 8, b - a))
        or (t == 94 and hit(p.x + 1, p.y + 1, s - 2, s - 2, c * 8 + 2, d + 3, 4, 5))
        or (t == 118 and hit(p.x + 1, p.y + 1, s - 2, s - 2, c * 8 + 2, d, 4, 5)) then
        p.dead = true
        return
      end
    end
  end
end

local function step(p, press, hold)
  hold = hold or press
  if press then p.buf = 0.12; p.buf2 = 0.12
  else
    if p.buf > 0 then p.buf = p.buf - 0.02 end
    if p.buf2 > 0 then p.buf2 = p.buf2 - 0.02 end
  end
  local c = math.floor((p.x + 3) / 8)
  if c ~= p.pc then p.pc = c; portals(p, c) end
  pre(p, hold)
  if p.du then swap(p); pre(p, hold); swap(p) end
  p.x = p.x + p.spd * 0.02
  post(p, hold)
  if p.du and not p.dead then swap(p); post(p, hold); swap(p) end
  if p.x >= endX and not p.dead then p.won = true end
end

-- level tune: GDASH/music.lua (a separate file, so this one compiles in less RAM);
-- tools that load this file without loadScript get a silent tune
local c = loadScript and loadScript("/SCRIPTS/GAMES/GDASH/music.lua")
local music = c and c()(lv.m, lv.u) or function() end
c = nil

return tile, step, music, endX, newPlayer, N
end
