-- toolName = TNS|Doodle Jump|TNE
-- Doodle Jump, 128x64 B&W. Stick L/R steer (screen wraps), SA/SD shoot.
-- Every next platform is within 80% of a full-speed jump. Sprites: DOODLE/gfx.lua

local PW, PH = 6, 6
local V = 118           -- bounce speed px/s -> ~25 px high
local SPRING = 180
local G = 280           -- gravity px/s^2
local MOVE = 95         -- sideways px/s at full stick
local TOPLINE = 24
local ZLEN = 500        -- climb per zone
local SAFE_H = math.floor(0.8 * V * V / (2 * G))  -- 80% of max height
local PATH = "/SCRIPTS/GAMES/doodle.dat"

local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

-- sideways px you can cover while rising dy and falling back onto it,
-- at 80% stick, chasing a target that runs away at vt px/s
local function reach(dy, vt)
  local d = V * V - 2 * G * dy
  if d < 0 then return -1 end
  return (0.8 * MOVE - vt) * (V + math.sqrt(d)) / G
end

-- horizontal distance across the wrapping screen
local function wdist(a, b)
  local d = math.abs(a - b) % LCD_W
  if d > LCD_W / 2 then d = LCD_W - d end
  return d
end

local state, px, py, vy, face, plats, mobs, buls, climbed, score, bonus
local best, bestC, lastTime, zone, banner, cLo, cHi, cW, cY, foeCd
local fly, flyK, shoes, shield, inv, flash, gfx
local swLast, swRest, swSince = {}, {}, {}

local function swOne(n, now)
  local v = getValue(n)
  if swLast[n] == nil then
    swLast[n], swRest[n], swSince[n] = v, v, now
  elseif v ~= swLast[n] then
    swLast[n], swSince[n] = v, now
    return v ~= swRest[n]
  elseif v ~= swRest[n] and now - swSince[n] > 50 then
    swRest[n] = v
  end
  return false
end

local function switchPress()
  local now = getTime()
  local a = swOne("sa", now)
  local d = swOne("sd", now)
  return a or d
end

-- kind 0 normal, 1 moving, 2 crumbles, 3 vanishes after 1 bounce, 4 TNT
-- item 1 spring, 2 spring shoes, 3 propeller, 4 jetpack, 5 shield
-- a moving platform swings between lo and hi at vx
local function addPlat(x, y, w, kind, item, chain, lo, hi, vx)
  plats[#plats + 1] = { x = x, y = y, w = w, kind = kind, vx = vx or 0, item = item,
    chain = chain, t = 2.5, lo = lo or x, hi = hi or x }
end

-- worst edge gap between platform A anywhere in [alo,ahi] and B in [blo,bhi]
local function worst(alo, ahi, aw, blo, bhi, bw)
  local d1 = blo + bw / 2 - ahi - aw / 2
  local d2 = bhi + bw / 2 - alo - aw / 2
  local g = math.max(wdist(d1, 0), wdist(d2, 0))
  if math.floor((d2 - 64) / 128) ~= math.floor((d1 - 64) / 128) then g = 64 end
  return g - (aw + bw) / 2
end

-- mob k: 1 monster, 2 bat, 3 UFO (pulls), 4 black hole (pulls hard), 9 coin
local function addMob(k, x, y)
  local vx = 0
  if k == 2 then vx = 22 elseif k == 3 then vx = 12 end
  if math.random() < 0.5 then vx = -vx end
  mobs[#mobs + 1] = { k = k, x = x, y = y, vx = vx, hp = (k == 3) and 2 or 1, ph = math.random() * 6 }
end

-- free x for a mob: away from the last two chain platforms
local function mobX(cx1, cx2, gap)
  for t = 1, 8 do
    local x = math.random(0, LCD_W - 9)
    if wdist(x + 4, cx1) >= gap and wdist(x + 4, cx2) >= gap then return x end
  end
  return nil
end

local function generate()
  local n = 0
  while cY > -8 and n < 30 do
    n = n + 1
    local z = 1 + math.floor((climbed + LCD_H - cY) / ZLEN)
    local zz = math.min(z, 5)
    local dy = math.random(math.min(SAFE_H - 2, 6 + zz * 2 + math.floor(z / 4)), math.min(SAFE_H, 11 + zz * 2))
    local w = 20 - zz * 2
    local kind, r = 0, math.random()
    if zz >= 2 and r < 0.05 + zz * 0.05 then kind = 1
    elseif zz >= 3 and r < 0.45 then kind = 3 end
    local vx, lo, hi, ok = 0, 0, 0, false
    if kind == 1 then vx = math.random(12, 14 + zz * 3) end
    for t = 1, 10 do
      lo = math.random(0, LCD_W - w)
      hi = lo
      if kind == 1 then hi = math.min(LCD_W - w, lo + math.random(14, 30)) end
      if worst(cLo, cHi, cW, lo, hi, w) <= reach(dy, vx) then ok = true; break end
    end
    if not ok then
      -- fallback: a still platform right at the old one
      kind, vx, dy = 0, 0, math.min(dy, 12)
      lo = math.min(cLo, LCD_W - w); hi = lo
    end
    local x = lo
    if math.random() < 0.5 then vx = -vx end
    local pcx = (cLo + cHi + cW) / 2
    cY = cY - dy
    local item = nil
    if kind ~= 1 then
      r = math.random()
      if r < 0.07 then item = 1
      elseif r < 0.09 then item = 2
      elseif zz >= 2 and r < 0.11 then item = 3
      elseif zz >= 3 and r < 0.123 then item = 4
      elseif zz >= 2 and r < 0.14 then item = 5 end
    end
    addPlat(x, cY, w, kind, item, true, lo, hi, vx)
    cLo, cHi, cW = lo, hi, w
    -- extras that are never needed to climb
    if dy >= 9 and math.random() < 0.3 then
      local ek = 2
      if zz == 1 then ek = 0 elseif zz >= 3 and math.random() < 0.4 then ek = 4 end
      addPlat(math.random(0, LCD_W - 14), cY + math.random(3, dy - 4), 14, ek, nil, false)
    end
    if math.random() < 0.12 then addMob(9, math.random(2, LCD_W - 6), cY - 9) end
    foeCd = foeCd - 1
    if zz >= 2 and foeCd <= 0 and #mobs < 5 and math.random() < 0.06 + zz * 0.03 then
      local k = math.random(1, 2)
      if zz >= 4 then
        r = math.random()
        if r < 0.3 then k = 3 elseif r < 0.45 then k = 4 end
      end
      local mx = mobX((cLo + cHi + cW) / 2, pcx, (k == 4) and 36 or 20)
      if mx then
        addMob(k, mx, cY + math.floor(dy / 2) - 3)
        foeCd = 4 - math.floor(zz / 2)
      end
    end
  end
end

local function scroll(s)
  climbed = climbed + s
  cY = cY + s
  for i = #plats, 1, -1 do
    local p = plats[i]
    p.y = p.y + s
    if p.y > LCD_H + 2 then removeAt(plats, i) end
  end
  for i = #mobs, 1, -1 do
    local m = mobs[i]
    m.y = m.y + s
    if m.y > LCD_H + 4 then removeAt(mobs, i) end
  end
  for i = 1, #buls do buls[i].y = buls[i].y + s end
  generate()
  local z = 1 + math.floor(climbed / ZLEN)
  if z > zone then
    zone, banner = z, 2.5
    playTone(1500, 60, 0, PLAY_NOW)
  end
end

local function reset()
  px = LCD_W / 2 - PW / 2
  py = LCD_H - 10 - PH
  vy = -V
  face, climbed, score, bonus, zone, banner = 1, 0, 0, 0, 1, 2
  fly, flyK, shoes, shield, inv, flash, foeCd = 0, 0, 0, false, 0, 0, 3
  plats, mobs, buls = {}, {}, {}
  cLo, cW, cY = LCD_W / 2 - 15, 30, LCD_H - 8
  cHi = cLo
  addPlat(cLo, cY, 30, 0, nil, true)
  generate()
end

local function save()
  pcall(function()
    local f = io.open(PATH, "w")
    if f then
      io.write(f, best .. " " .. math.floor(bestC))
      io.close(f)
    end
  end)
end

local function init()
  math.randomseed(getTime())
  best, bestC = 0, 0
  pcall(function()
    local f = io.open(PATH, "r")
    if f then
      local s = io.read(f, 40)
      io.close(f)
      local a, b = string.match(s or "", "(%d+) (%d+)")
      if a then best, bestC = tonumber(a), tonumber(b) end
    end
  end)
  local ok, chunk = pcall(loadScript, "/SCRIPTS/GAMES/DOODLE/gfx.lua")
  gfx = ok and chunk and chunk()
  state = "title"
  lastTime = getTime()
  reset()
end

local function overlapX(x, p)
  return x + PW - 1 > p.x and x + 1 < p.x + p.w
end

local function hitBox(x, y, w, h)
  if py + PH <= y or py >= y + h then return false end
  for o = -1, 1 do
    local q = px + o * LCD_W
    if q + PW > x and q < x + w then return true end
  end
  return false
end

local function die()
  state = "over"
  score = math.floor(climbed / 2) + bonus
  if score > best then best = score end
  if climbed > bestC then bestC = climbed end
  save()
  playTone(400, 400, -6, PLAY_NOW)
end

local function hurt()
  if inv > 0 or fly > 0 then return false end
  if shield then
    shield, inv = false, 1.2
    playTone(600, 80, 0, PLAY_NOW)
    return false
  end
  die()
  return true
end

local function update(dt, fire)
  local s = getValue("ail")
  local r = getValue("rud")
  if math.abs(r) > math.abs(s) then s = r end
  if math.abs(s) > 120 then
    px = px + s / 1024 * MOVE * dt
    if s > 0 then face = 1 else face = -1 end
  end
  if inv > 0 then inv = inv - dt end
  if flash > 0 then flash = flash - dt end
  if banner > 0 then banner = banner - dt end

  if fire and #buls < 3 then
    buls[#buls + 1] = { x = px + 2, y = py - 3 }
    playTone(1800, 15, 0, PLAY_NOW)
  end

  local prevBot = py + PH
  if fly > 0 then
    fly = fly - dt
    if flyK == 4 then vy = -210 else vy = -140 end
    py = py + vy * dt
  else
    -- exact parabola: the jump is the same at any frame rate
    py = py + vy * dt + 0.5 * G * dt * dt
    vy = vy + G * dt
  end
  local bot = py + PH
  local land = nil

  for i = #plats, 1, -1 do
    local p = plats[i]
    if p.kind == 1 then
      p.x = p.x + p.vx * dt
      if p.x < p.lo then p.x = p.lo; p.vx = math.abs(p.vx) end
      if p.x > p.hi then p.x = p.hi; p.vx = -math.abs(p.vx) end
    end
    local gone = false
    if p.kind == 4 and p.y > 0 then
      p.t = p.t - dt
      if p.t <= 0 then
        gone = true
        flash = 0.15
        playTone(150, 200, 0, PLAY_NOW)
        if math.abs(p.x + p.w / 2 - px - PW / 2) < 16 and math.abs(p.y - bot) < 12 and fly <= 0 then
          vy = -SPRING -- the blast throws you up
        end
      end
    end
    if p.item and p.item > 1 and hitBox(p.x + p.w / 2 - 3, p.y - 8, 6, 8) then
      local it = p.item
      p.item = nil
      playTone(2000, 60, 10, PLAY_NOW)
      if it == 2 then shoes = 6
      elseif it == 5 then shield = true
      else fly, flyK = (it == 4) and 2.2 or 1.6, it end
    end
    if not gone and fly <= 0 and vy > 0 and prevBot <= p.y + 1 and bot >= p.y
        and (overlapX(px, p) or overlapX(px - LCD_W, p)) then
      if p.kind == 2 then
        gone = true
        playTone(300, 40, 0, PLAY_NOW)
      elseif not land or p.y < land.y then
        land = p -- a slow frame can cross two: take the highest
      end
    end
    if gone then removeAt(plats, i) end
  end
  if land then
    py = land.y - PH
    if land.item == 1 then
      vy = -SPRING
      playTone(2400, 80, 0, PLAY_NOW)
    elseif shoes > 0 then
      shoes = shoes - 1
      vy = -SPRING * 0.9
      playTone(2000, 30, 0, PLAY_NOW)
    else
      vy = -V
      playTone(1100, 20, 0, PLAY_NOW)
    end
    if land.kind == 3 then
      for i = #plats, 1, -1 do
        if plats[i] == land then removeAt(plats, i); break end
      end
    end
  end

  for i = #buls, 1, -1 do
    local b = buls[i]
    b.y = b.y - 200 * dt
    if b.y < -4 then removeAt(buls, i) end
  end

  for i = #mobs, 1, -1 do
    local m = mobs[i]
    m.ph = m.ph + dt * 4
    m.x = m.x + m.vx * dt
    if m.x < -8 then m.x = m.x + LCD_W elseif m.x > LCD_W then m.x = m.x - LCD_W end
    local kill = false
    if m.k == 3 or m.k == 4 then
      -- pull toward the centre (wrapped)
      local dx = (m.x + 4) - (px + PW / 2)
      if dx > LCD_W / 2 then dx = dx - LCD_W elseif dx < -LCD_W / 2 then dx = dx + LCD_W end
      local ddy = (m.y + 3) - (py + PH / 2)
      local rr = (m.k == 4) and 24 or 16
      if fly <= 0 and dx * dx + ddy * ddy < rr * rr then
        local f = (m.k == 4) and 70 or 40
        if dx > 0 then px = px + f * dt else px = px - f * dt end
        if ddy > 0 then vy = vy + f * 3 * dt else vy = vy - f * 3 * dt end
      end
    end
    local h = (m.k == 9) and 4 or 6
    if hitBox(m.x, m.y, 8, h) then
      if m.k == 9 then
        kill = true
        bonus = bonus + 25
        playTone(2600, 30, 0, PLAY_NOW)
      elseif fly > 0 and m.k ~= 4 then
        kill = true
      elseif m.k ~= 4 and vy > 0 and prevBot <= m.y + 3 then
        kill = true
        bonus = bonus + 50
        vy = -V * 1.1
        playTone(900, 60, 0, PLAY_NOW)
      elseif m.k == 4 and fly <= 0 then
        die()
        return
      elseif hurt() then
        return
      elseif inv > 1 then
        kill = true
      end
    end
    if not kill and m.k ~= 9 and m.k ~= 4 then
      for j = #buls, 1, -1 do
        local b = buls[j]
        if b.x >= m.x - 1 and b.x <= m.x + 8 and b.y <= m.y + 6 and b.y + 3 >= m.y then
          removeAt(buls, j)
          m.hp = m.hp - 1
          playTone(700, 30, 0, PLAY_NOW)
          if m.hp <= 0 then kill = true; bonus = bonus + 30 end
          break
        end
      end
    end
    if kill then removeAt(mobs, i) end
  end

  if px < 0 then px = px + LCD_W end
  if px >= LCD_W then px = px - LCD_W end

  if py < TOPLINE then
    local sh = TOPLINE - py
    py = TOPLINE
    scroll(sh)
  end
  score = math.floor(climbed / 2) + bonus

  if py > LCD_H then die() end
end

local function draw()
  lcd.clear()
  local t = getTime() / 100
  if not gfx then lcd.drawText(2, 20, "DOODLE/gfx.lua missing", SMLSIZE) return end
  if flash > 0 then return end
  local by = math.floor(TOPLINE - (bestC - climbed))
  if bestC > 0 and by >= 0 and by < LCD_H then
    lcd.drawLine(0, by, LCD_W - 1, by, DOTTED, FORCE)
    lcd.drawText(1, by - 7, "BEST", SMLSIZE)
  end
  for _, p in ipairs(plats) do gfx.plat(p, t) end
  for _, m in ipairs(mobs) do gfx.mob(m, t) end
  for _, b in ipairs(buls) do
    local y = math.floor(b.y)
    if y >= 0 and y < LCD_H - 3 then lcd.drawLine(math.floor(b.x), y, math.floor(b.x), y + 2, SOLID, FORCE) end
  end
  local x, y = math.floor(px), math.floor(py)
  if inv <= 0 or math.floor(t * 10) % 2 == 0 then
    gfx.doodle(x, y, face, fly, flyK, shield, shoes)
    if x + PW + 2 > LCD_W then gfx.doodle(x - LCD_W, y, face, fly, flyK, shield, shoes) end
  end
  lcd.drawNumber(LCD_W - 1, 0, score, RIGHT + SMLSIZE + INVERS)
  if banner > 0 then
    gfx.banner(zone)
  end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    if state == "play" then die() end
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end
  if dt < 0 then dt = 0 end
  local fire = switchPress()

  if state == "play" then
    update(dt, fire)
    draw()
  else
    draw()
    if gfx then gfx.screen(state == "title", score, zone, best) end
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run,
  -- test hook (bot/reachability tests); unused by the radio
  _t = function() return plats, mobs, scroll, px, py, vy, climbed, state end }
