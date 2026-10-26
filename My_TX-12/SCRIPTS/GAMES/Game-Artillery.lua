-- toolName = TNS|Artillery|TNE
---------------------------------------------------------------
-- Artillery (Scorched Earth) for 128x64 B&W EdgeTX radios
--
-- Aim:   right stick left/right = angle, up/down = power
--        (left stick left/right also turns, wheel = power +-1)
-- Fire:  SA or SD, or ENTER (wheel press)
-- Wind:  arrow at the top. Craters change the ground.
-- Beat the enemy tank to win a round; you heal a bit after.
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local GRAV = 60       -- px/s^2
local VSCALE = 1.1    -- shell speed px/s per power point
local BLAST = 7       -- crater radius
local TOP = 18        -- highest the terrain may reach
local MAXTRAIL = 90

local state, ground, trailX, trailY, trailN, lastTX, lastTY
local px, ex, pHP, eHP, pAng, pPow
local eAng, ePow, eLo, eHi, eShots
local wind, round, best, lastTime
local sx, sy, svx, svy, flyT, shooter, boomX, boomY, boomT, waitT

-- terrain height (y of the surface) at screen column x, always valid
local function gnd(x)
  x = math.floor(x)
  if x < 0 then x = 0 elseif x > LCD_W - 1 then x = LCD_W - 1 end
  local v = ground[x + 1]
  if v == nil then return LCD_H - 1 end
  return v
end

-- the highest surface under a tank's 7 px body
local function tankY(tx)
  local y = gnd(tx)
  for dx = -3, 3 do
    local g = gnd(tx + dx)
    if g < y then y = g end
  end
  return y
end

local function flatten(tx)
  local h = gnd(tx)
  for x = tx - 4, tx + 4 do
    if x >= 0 and x < LCD_W then ground[x + 1] = h end
  end
end

local function makeTerrain()
  local a1, a2, a3 = math.random(5, 11), math.random(3, 6), math.random(1, 2)
  local f1 = math.random() * 0.03 + 0.02
  local f2 = math.random() * 0.06 + 0.06
  local f3 = math.random() * 0.10 + 0.15
  local p1, p2, p3 = math.random() * 6.28, math.random() * 6.28, math.random() * 6.28
  local base = math.random(42, 48)
  local hx, hh = math.random(45, 85), math.random(0, 16)
  for x = 1, LCD_W do
    local h = base + a1 * math.sin(x * f1 + p1) + a2 * math.sin(x * f2 + p2)
      + a3 * math.sin(x * f3 + p3)
    local d = (x - hx) / 16
    if d > -1 and d < 1 then h = h - hh * (1 - d * d) end
    ground[x] = h
  end
  for pass = 1, 3 do
    local prev = ground[1]
    for x = 2, LCD_W - 1 do
      local cur = ground[x]
      ground[x] = (prev + cur + ground[x + 1]) / 3
      prev = cur
    end
  end
  for x = 1, LCD_W do
    local h = math.floor(ground[x] + 0.5)
    if h < TOP then h = TOP elseif h > LCD_H - 6 then h = LCD_H - 6 end
    ground[x] = h
  end
  -- flat pads for the tanks
  flatten(px)
  flatten(ex)
end

local function newRound()
  px = math.random(8, 20)
  ex = math.random(106, 119)
  makeTerrain()
  eHP = 100
  pHP = math.min(100, pHP + 30)
  wind = math.random(-12, 12)
  eAng = math.random(45, 62)
  local d = ex - px
  local ideal = math.sqrt(d * GRAV / math.sin(2 * eAng * math.pi / 180)) / VSCALE
  local miss = math.max(6, 25 - round * 3)
  if math.random(2) == 1 then miss = -miss end
  ePow = ideal * (1 + miss / 100)
  eLo, eHi, eShots = nil, nil, 0
  trailN = 0
  state = "aim"
end

local function newGame()
  round = 0
  pHP = 100
  pAng, pPow = 45, 60
  newRound()
end

local function init()
  math.randomseed(getTime())
  ground, trailX, trailY = {}, {}, {}
  for i = 1, MAXTRAIL do trailX[i], trailY[i] = 0, 0 end
  best = 0
  lastTime = getTime()
  newGame()
  state = "title"
end

-- true once per press of switch SA or SD. Works for buttons and toggles:
-- a switch left in a new position for 0.5 s counts as its new rest.
local SWITCHES = { "sa", "sd" }
local swLast, swRest, swSince = {}, {}, {}
local function switchPress()
  local now = getTime()
  local pressed = false
  for _, n in ipairs(SWITCHES) do
    local v = getValue(n)
    if swLast[n] == nil then
      swLast[n], swRest[n], swSince[n] = v, v, now
    elseif v ~= swLast[n] then
      if v ~= swRest[n] then pressed = true end
      swLast[n], swSince[n] = v, now
    elseif v ~= swRest[n] and now - swSince[n] > 50 then
      swRest[n] = v
    end
  end
  return pressed
end

local function fire(who, ang, pow)
  shooter = who
  local a = ang * math.pi / 180
  local v = pow * VSCALE
  local dir, tx = 1, px
  if who == 2 then dir, tx = -1, ex end
  local ty = tankY(tx) - 5
  sx = tx + dir * math.cos(a) * 5
  sy = ty - math.sin(a) * 5
  svx = dir * math.cos(a) * v
  svy = -math.sin(a) * v
  flyT = 0
  trailN = 0
  lastTX, lastTY = sx, sy
  state = "fly"
  playTone(500, 80, 0, PLAY_NOW)
end

-- enemy aim: bracket the power between a too-short and a too-long shot
local function aiLearn(landX)
  local err -- > 0: landed beyond the player (too long)
  if landX == nil then
    if sx < 0 then err = 40 else err = -40 end
  else
    err = px - landX
  end
  eShots = eShots + 1
  if math.abs(err) <= 3 then return end
  if err > 0 then eHi = ePow else eLo = ePow end
  if eLo and eHi then
    if eHi - eLo < 1 then
      eLo, eHi = nil, nil
      ePow = ePow - err * 0.1
    else
      ePow = (eLo + eHi) / 2
    end
  else
    local step = err * 0.3
    if step > 20 then step = 20 elseif step < -20 then step = -20 end
    ePow = ePow - step
  end
  if ePow < 10 then ePow = 10 elseif ePow > 100 then ePow = 100 end
end

local function damage(tx, x, y)
  local dx, dy = tx - x, tankY(tx) - 2 - y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < BLAST + 5 then
    return math.floor(45 * (1 - d / (BLAST + 6))) + 5
  end
  return 0
end

local function explode(x, y)
  boomX, boomY, boomT = math.floor(x), math.floor(y), 0
  pHP = math.max(0, pHP - damage(px, x, y))
  eHP = math.max(0, eHP - damage(ex, x, y))
  for dx = -BLAST, BLAST do
    local cx = boomX + dx
    if cx >= 0 and cx < LCD_W then
      local bottom = math.floor(y + math.sqrt(BLAST * BLAST - dx * dx))
      if bottom > LCD_H - 1 then bottom = LCD_H - 1 end
      local g = ground[cx + 1]
      if g ~= nil and g < bottom then ground[cx + 1] = bottom end
    end
  end
  if shooter == 2 then aiLearn(x) end
  state = "boom"
  playTone(150, 250, 0, PLAY_NOW)
end

local function hitTank(tx, x, y)
  local ty = tankY(tx)
  return x >= tx - 4 and x <= tx + 4 and y >= ty - 5 and y <= ty
end

local function flyStep(dt)
  flyT = flyT + dt
  local sp = math.max(math.abs(svx), math.abs(svy))
  local steps = math.floor(sp * dt / 1.5) + 1
  local h = dt / steps
  for i = 1, steps do
    svx = svx + wind * h
    svy = svy + GRAV * h
    sx = sx + svx * h
    sy = sy + svy * h
    if sx < -2 or sx > LCD_W + 1 or sy > LCD_H or flyT > 12 then
      boomX, boomT, state = nil, 0, "boom"
      if shooter == 2 then aiLearn(nil) end
      return
    end
    if hitTank(px, sx, sy) or hitTank(ex, sx, sy) or sy >= gnd(sx) then
      explode(sx, sy)
      return
    end
  end
  local dx, dy = sx - lastTX, sy - lastTY
  if dx * dx + dy * dy >= 9 and trailN < MAXTRAIL then
    trailN = trailN + 1
    trailX[trailN], trailY[trailN] = sx, sy
    lastTX, lastTY = sx, sy
  end
end

local function plot(x, y)
  if x >= 0 and x < LCD_W and y >= 0 and y < LCD_H then lcd.drawPoint(x, y) end
end

-- midpoint circle outline
local function circle(cx, cy, r)
  local x, y, d = r, 0, 1 - r
  while x >= y do
    plot(cx + x, cy + y); plot(cx - x, cy + y); plot(cx + x, cy - y); plot(cx - x, cy - y)
    plot(cx + y, cy + x); plot(cx - y, cy + x); plot(cx + y, cy - x); plot(cx - y, cy - x)
    y = y + 1
    if d < 0 then
      d = d + 2 * y + 1
    else
      x = x - 1
      d = d + 2 * (y - x) + 1
    end
  end
end

local function drawTank(tx, ang, dir, hp)
  local ty = tankY(tx)
  lcd.drawFilledRectangle(tx - 3, ty - 3, 7, 3)
  lcd.drawFilledRectangle(tx - 1, ty - 5, 3, 2)
  local a = ang * math.pi / 180
  lcd.drawLine(tx, ty - 5, math.floor(tx + dir * math.cos(a) * 5 + 0.5),
    math.floor(ty - 5 - math.sin(a) * 5 + 0.5), SOLID, FORCE)
  lcd.drawRectangle(tx - 7, ty - 10, 15, 3)
  local w = math.floor(hp * 13 / 100)
  if w > 0 then lcd.drawLine(tx - 6, ty - 9, tx - 7 + w, ty - 9, SOLID, FORCE) end
end

local function draw()
  lcd.clear()
  for x = 0, LCD_W - 1 do
    lcd.drawLine(x, gnd(x), x, LCD_H - 1, SOLID, FORCE)
  end
  drawTank(px, pAng, 1, pHP)
  drawTank(ex, eAng, -1, eHP)
  for i = 1, trailN do
    plot(math.floor(trailX[i]), math.floor(trailY[i]))
  end
  if state == "fly" then
    lcd.drawFilledRectangle(math.floor(sx), math.floor(sy), 2, 2)
  elseif state == "boom" and boomX then
    local r = math.floor(boomT / 0.4 * BLAST) + 1
    if r > BLAST + 2 then r = BLAST + 2 end
    circle(boomX, boomY, r)
  end
  -- HUD: angle/power, wind arrow, round
  lcd.drawText(0, 0, "A" .. math.floor(pAng) .. " P" .. math.floor(pPow), SMLSIZE)
  lcd.drawText(50, 0, "W", SMLSIZE)
  local s = 1
  if wind < 0 then s = -1 end
  local l = math.floor(math.abs(wind)) + 2
  local a = math.floor(72 - s * l / 2)
  local b = a + s * l
  lcd.drawLine(a, 3, b, 3, SOLID, FORCE)
  lcd.drawLine(b, 3, b - s * 2, 1, SOLID, FORCE)
  lcd.drawLine(b, 3, b - s * 2, 5, SOLID, FORCE)
  lcd.drawText(LCD_W - 1, 0, "R" .. (round + 1), SMLSIZE + RIGHT)
end

local function aim(dt, event)
  local turn = getValue("ail")
  local rud = getValue("rud")
  if math.abs(rud) > math.abs(turn) then turn = rud end
  local pw = getValue("ele")
  if math.abs(turn) > 300 then pAng = pAng + turn / 1024 * 45 * dt end
  if math.abs(pw) > 300 then pPow = pPow + pw / 1024 * 40 * dt end
  if event == EVT_VIRTUAL_NEXT then pPow = pPow + 1 end
  if event == EVT_VIRTUAL_PREV then pPow = pPow - 1 end
  if pAng < 5 then pAng = 5 elseif pAng > 85 then pAng = 85 end
  if pPow < 10 then pPow = 10 elseif pPow > 100 then pPow = 100 end
end

local function afterBoom()
  if pHP <= 0 then
    if round > best then best = round end
    state = "over"
    playTone(200, 500, 0, PLAY_NOW)
  elseif eHP <= 0 then
    round = round + 1
    waitT = 0
    state = "won"
    playTone(2500, 200, 0, PLAY_NOW)
  elseif shooter == 1 then
    waitT = 0
    state = "ai"
  else
    state = "aim"
  end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local press = (event == EVT_VIRTUAL_ENTER) or switchPress()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 34, 12, "ARTILLERY", MIDSIZE + INVERS)
    lcd.drawText(4, 28, "Stick: angle / power", SMLSIZE)
    lcd.drawText(4, 37, "SA/SD/ENTER: fire", SMLSIZE)
    if press then
      newGame()
    end
  elseif state == "aim" then
    aim(dt, event)
    draw()
    if press then fire(1, pAng, pPow) end
  elseif state == "fly" then
    flyStep(dt)
    draw()
  elseif state == "boom" then
    boomT = boomT + dt
    draw()
    if boomT > 0.5 then afterBoom() end
  elseif state == "ai" then
    waitT = waitT + dt
    draw()
    lcd.drawText(LCD_W / 2 - 26, 9, "Enemy aims", SMLSIZE)
    if waitT > 0.9 then
      local noise = math.max(1, 10 - 2 * eShots - round) * (math.random() - 0.5)
      fire(2, eAng, math.max(10, math.min(100, ePow + noise)))
    end
  elseif state == "won" then
    waitT = waitT + dt
    draw()
    lcd.drawText(LCD_W / 2 - 30, 14, "ROUND WON", MIDSIZE + INVERS)
    if waitT > 2 or (waitT > 0.5 and press) then newRound() end
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 8, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 40, 26, "Rounds " .. round .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 36, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
    end
  end
  return 0
end

return { init = init, run = run }
