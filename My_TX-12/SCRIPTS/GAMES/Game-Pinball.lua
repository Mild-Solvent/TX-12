-- toolName = TNS|Pinball|TNE
---------------------------------------------------------------
-- Pinball for 128x64 B&W EdgeTX radios (TX12)
--
-- Left flipper:  SA button      Right flipper: SD button
-- Launch ball:   ENTER (wheel press) or any flipper
-- Exit:          RTN / EXIT
---------------------------------------------------------------

local TL, TR = 34, 94        -- table left / right x
local GRAVITY = 70
local MAX_SPEED = 160
local BALL_R = 1.6
local FLIP_LEN = 10
local FLIP_REST = 0.45       -- radians below horizontal
local FLIP_UP = -0.45
local FLIP_SPEED = 22        -- rad/s
local SUBSTEPS = 6

local walls = {
  { TL, 64, TL, 8 }, { TL, 8, TL + 8, 0 }, { TL + 8, 0, TR - 8, 0 },
  { TR - 8, 0, TR, 8 }, { TR, 8, TR, 64 },
  { TL, 42, 52, 55 }, { TR, 42, 76, 55 },          -- bottom guides
  { TL + 6, 26, TL + 10, 34 }, { TR - 6, 26, TR - 10, 34 },  -- side kickers
}

local bumpers = {
  { x = 51, y = 15, r = 4, flash = 0 },
  { x = 77, y = 15, r = 4, flash = 0 },
  { x = 64, y = 27, r = 4, flash = 0 },
}

local flippers = {
  { px = 52, py = 55, dir = 1, a = FLIP_REST, w = 0, sw = "sa" },
  { px = 76, py = 55, dir = -1, a = FLIP_REST, w = 0, sw = "sd" },
}

local state, ball, score, best, balls, lastTime

local function newGame()
  score, balls = 0, 3
  ball = nil
  state = "ready"
end

local function init()
  math.randomseed(getTime())
  best = 0
  lastTime = getTime()
  newGame()
end

local function launch()
  ball = { x = 64 + math.random(-6, 6), y = 6, vx = math.random(-30, 30), vy = 10 }
  state = "play"
  playTone(1200, 60, 0, PLAY_NOW)
end

local function pressed(sw)
  return getValue(sw) > 0
end

local function flipTip(f)
  return f.px + f.dir * FLIP_LEN * math.cos(f.a), f.py + FLIP_LEN * math.sin(f.a)
end

-- Push the ball out of a segment and bounce. svx/svy = surface velocity.
local function collideSegment(x1, y1, x2, y2, bounce, svx, svy)
  local dx, dy = x2 - x1, y2 - y1
  local len2 = dx * dx + dy * dy
  local t = ((ball.x - x1) * dx + (ball.y - y1) * dy) / len2
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local cx, cy = x1 + t * dx, y1 + t * dy
  local nx, ny = ball.x - cx, ball.y - cy
  local dist = math.sqrt(nx * nx + ny * ny)
  if dist >= BALL_R or dist == 0 then return false, t end
  nx, ny = nx / dist, ny / dist
  ball.x = cx + nx * BALL_R
  ball.y = cy + ny * BALL_R
  local rvx, rvy = ball.vx - svx, ball.vy - svy
  local vn = rvx * nx + rvy * ny
  if vn < 0 then
    rvx = rvx - (1 + bounce) * vn * nx
    rvy = rvy - (1 + bounce) * vn * ny
    ball.vx, ball.vy = rvx + svx, rvy + svy
  end
  return true, t
end

local function updateFlippers(dt)
  for _, f in ipairs(flippers) do
    local target = pressed(f.sw) and FLIP_UP or FLIP_REST
    local old = f.a
    if f.a > target then
      f.a = math.max(target, f.a - FLIP_SPEED * dt)
    elseif f.a < target then
      f.a = math.min(target, f.a + FLIP_SPEED * dt)
    end
    f.w = (f.a - old) / dt
  end
end

local function step(dt)
  updateFlippers(dt)
  ball.vy = ball.vy + GRAVITY * dt
  local sp = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
  if sp > MAX_SPEED then
    ball.vx, ball.vy = ball.vx / sp * MAX_SPEED, ball.vy / sp * MAX_SPEED
  end
  ball.x = ball.x + ball.vx * dt
  ball.y = ball.y + ball.vy * dt

  for i, w in ipairs(walls) do
    if collideSegment(w[1], w[2], w[3], w[4], 0.5, 0, 0) and i >= 8 then
      -- side kickers give a little push
      ball.vx = ball.vx * 1.3
      score = score + 10
    end
  end

  for _, f in ipairs(flippers) do
    local tx, ty = flipTip(f)
    local hit, t = collideSegment(f.px, f.py, tx, ty, 0.3, 0, 0)
    if hit and f.w < 0 then
      -- a rising flipper kicks along its top normal, harder near the tip
      local r = t * FLIP_LEN
      local nx, ny = math.sin(f.a) * f.dir, -math.cos(f.a)
      local kick = -f.w * r
      if kick > 0 then
        ball.vx = ball.vx + nx * kick
        ball.vy = ball.vy + ny * kick
      end
    end
  end

  for _, b in ipairs(bumpers) do
    local dx, dy = ball.x - b.x, ball.y - b.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < b.r + BALL_R and d > 0 then
      dx, dy = dx / d, dy / d
      ball.x = b.x + dx * (b.r + BALL_R)
      ball.y = b.y + dy * (b.r + BALL_R)
      ball.vx, ball.vy = dx * 75, dy * 75
      b.flash = 0.15
      score = score + 100
      playTone(1800, 25, 0, PLAY_NOW)
    end
  end
end

local function update(dt)
  for _ = 1, SUBSTEPS do
    step(dt / SUBSTEPS)
  end
  for _, b in ipairs(bumpers) do
    if b.flash > 0 then b.flash = b.flash - dt end
  end
  if ball.y > LCD_H + 3 or ball.x < TL - 4 or ball.x > TR + 4 then
    balls = balls - 1
    ball = nil
    playTone(300, 300, 0, PLAY_NOW)
    if balls <= 0 then
      if score > best then best = score end
      state = "over"
    else
      state = "ready"
    end
  end
end

local function line(x1, y1, x2, y2)
  lcd.drawLine(math.floor(x1 + 0.5), math.floor(y1 + 0.5), math.floor(x2 + 0.5), math.floor(y2 + 0.5), SOLID, FORCE)
end

local function draw()
  lcd.clear()
  for _, w in ipairs(walls) do
    line(w[1], w[2], w[3], w[4])
  end
  for _, b in ipairs(bumpers) do
    local x, y, r = b.x, b.y, b.r
    if b.flash > 0 then
      lcd.drawFilledRectangle(x - r + 1, y - r + 1, 2 * r - 1, 2 * r - 1)
    else
      line(x - r, y, x, y - r)
      line(x, y - r, x + r, y)
      line(x + r, y, x, y + r)
      line(x, y + r, x - r, y)
      lcd.drawPoint(x, y)
    end
  end
  for _, f in ipairs(flippers) do
    local tx, ty = flipTip(f)
    line(f.px, f.py, tx, ty)
    line(f.px, f.py + 1, tx, ty + 1)
  end
  if ball then
    lcd.drawFilledRectangle(math.floor(ball.x) - 1, math.floor(ball.y) - 1, 3, 3)
  end

  lcd.drawText(1, 1, "PIN", SMLSIZE)
  lcd.drawText(1, 9, "BALL", SMLSIZE)
  lcd.drawText(1, 22, "Score", SMLSIZE)
  lcd.drawNumber(1, 30, score, SMLSIZE)
  lcd.drawText(1, 42, "Best", SMLSIZE)
  lcd.drawNumber(1, 50, best, SMLSIZE)
  for i = 1, balls do
    lcd.drawFilledRectangle(TR + 4 + (i - 1) * 6, 2, 4, 4)
  end
  lcd.drawText(TR + 4, 40, "SA  SD", SMLSIZE)
  lcd.drawText(TR + 4, 50, "flip", SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.05 then dt = 0.05 end
  if dt <= 0 then dt = 0.01 end

  if state == "play" then
    update(dt)
    draw()
  elseif state == "ready" then
    updateFlippers(dt)
    draw()
    lcd.drawText(TL + 6, 36, "ENTER", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER or pressed("sa") or pressed("sd") then
      launch()
    end
  else
    draw()
    lcd.drawText(TL + 4, 30, "GAME OVER", SMLSIZE + INVERS)
    lcd.drawText(TL + 4, 40, "ENTER", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
    end
  end
  return 0
end

return { init = init, run = run }
