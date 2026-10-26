-- Geometry Dash physics (one fixed 20 ms step), used by Game-GeometryDash.lua.
-- Loaded per level: tile, step, music = loadScript(this)()(rows, endX)
-- Tiles: # block, = slab, ^ v spikes, o jump orb, q gravity orb, p jump pad,
-- portals (whole column): G/g gravity up/down, U ufo, C cube, 1-4 speed.
local GY, CY, S, DT = 58, 10, 7, 0.02
local GC, JV, PADV = 800, 180, 250  -- cube gravity, jump, pad launch (px/s)
local GU, UV = 520, 135             -- ufo gravity, ufo flap
local BUF = 0.12                    -- s a press is remembered
local NOTES = "C C#D D#E F F#G G#A A#B "

return function(rows, endX)
-- tile byte at column c, row r (0 = bottom row); 46 = "." empty
local function tile(c, r)
  if c < 0 or r < 0 or r > 5 or not rows then return 46 end
  local s = rows[r + 1]
  if not s then return 46 end
  return string.byte(s, c + 1) or 46
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

-- one fixed physics step; press = a jump press arrived this step
local function step(p, press)
  if press then p.buf = BUF elseif p.buf > 0 then p.buf = p.buf - DT end
  -- portals: anywhere in the column under the cube's centre
  local cc = math.floor((p.x + 3) / 8)
  for r = 0, 5 do
    local t = tile(cc, r)
    if t == 71 then p.g = -1
    elseif t == 103 then p.g = 1
    elseif t == 85 then p.ufo = true
    elseif t == 67 then p.ufo = false
    elseif t >= 49 and t <= 52 then p.spd = 50 + 20 * (t - 48)
    end
  end
  local g = p.g
  if p.buf > 0 then
    if p.ufo then p.vy = -UV * g; p.buf = 0; p.gr = false
    elseif p.gr then p.vy = -JV * g; p.buf = 0; p.gr = false end
  end
  -- orbs (need a press) and pads (touch)
  local c0, c1 = math.floor((p.x - 4) / 8), math.floor((p.x + S + 3) / 8)
  local r0, r1 = rowOf(p.y + S + 3), rowOf(p.y - 4)
  for c = c0, c1 do
    for r = r0, r1 do
      local t = tile(c, r)
      local key = c * 8 + r
      if (t == 111 or t == 113) and p.buf > 0 and key ~= p.orb
        and hit(p.x - 4, p.y - 4, S + 8, S + 8, c * 8, rowTop(r), 8, 8) then
        p.orb = key; p.buf = 0; p.gr = false
        if t == 111 then p.vy = -JV * g else p.g = -g; g = -g; p.vy = 60 * g end
      elseif t == 112 and key ~= p.pad and hit(p.x, p.y, S, S, c * 8, rowTop(r), 8, 8) then
        p.pad = key; p.vy = -PADV * g; p.gr = false
      end
    end
  end
  p.x = p.x + p.spd * DT
  local gg = GC
  if p.ufo then gg = GU end
  p.vy = p.vy + gg * g * DT
  if p.vy > 350 then p.vy = 350 elseif p.vy < -350 then p.vy = -350 end
  local py = p.y
  p.y = p.y + p.vy * DT
  p.gr = false
  -- land on / bump into solid tiles
  c0, c1 = math.floor((p.x + 1) / 8), math.floor((p.x + S - 2) / 8)
  r0, r1 = rowOf(p.y + S - 1), rowOf(p.y)
  for c = c0, c1 do
    for r = r0, r1 do
      local top, bot = solid(tile(c, r), r)
      if top and p.y < bot and p.y + S > top then
        if p.vy * g >= 0 then
          if g > 0 and py + S <= top + 3 then p.y = top - S; p.vy = 0; p.gr = true
          elseif g < 0 and py >= bot - 3 then p.y = bot; p.vy = 0; p.gr = true end
        else
          if g > 0 and py >= bot - 3 then p.y = bot; p.vy = 0
          elseif g < 0 and py + S <= top + 3 then p.y = top - S; p.vy = 0 end
        end
      end
    end
  end
  if p.y + S >= GY then
    p.y = GY - S; p.vy = 0
    if g > 0 then p.gr = true end
  elseif p.y <= CY then
    p.y = CY; p.vy = 0
    if g < 0 then p.gr = true end
  end
  if p.gr then p.ang = 0 else p.ang = p.ang + 9 * DT end
  -- crash into block sides and spikes
  c0, c1 = math.floor(p.x / 8), math.floor((p.x + S - 1) / 8)
  r0, r1 = rowOf(p.y + S - 1), rowOf(p.y)
  for c = c0, c1 do
    for r = r0, r1 do
      local t = tile(c, r)
      local top, bot = solid(t, r)
      local tp = rowTop(r)
      if (top and hit(p.x, p.y + 1, S, S - 2, c * 8, top, 8, bot - top))
        or (t == 94 and hit(p.x + 1, p.y + 1, S - 2, S - 2, c * 8 + 2, tp + 3, 4, 5))
        or (t == 118 and hit(p.x + 1, p.y + 1, S - 2, S - 2, c * 8 + 2, tp, 4, 5)) then
        p.dead = true
        return
      end
    end
  end
  if p.x >= endX then p.won = true end
end

-- level tune (rows.m, unit rows.u s), looped; music(t) with t = seconds
-- since the attempt started queues each note when its time comes, t < 0 restarts
local mel, U, mPos, mT = rows.m, tonumber(rows.u) or 0.1, 1, 0
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

return tile, step, music
end
