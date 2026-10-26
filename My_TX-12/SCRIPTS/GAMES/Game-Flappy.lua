-- toolName = TNS|Flappy|TNE
---------------------------------------------------------------
-- Flappy bird for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Flap:  ENTER (wheel press) or flick right stick up
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local GROUND = LCD_H - 4
local BIRD_X = 24
local BIRD_S = 4
local GRAVITY = 220     -- px/s^2
local FLAP_VY = -62     -- px/s
local PIPE_W = 9
local PIPE_GAP = 24
local PIPE_SPACING = 52
local PIPE_SPEED = 38   -- px/s

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, birdY, birdVY, pipes, score, best, lastTime, stickArmed

local function newPipe(x)
  local top = math.random(6, GROUND - PIPE_GAP - 6)
  return { x = x, top = top, passed = false }
end

local function reset()
  birdY = LCD_H / 2 - 8
  birdVY = 0
  score = 0
  pipes = {}
  for i = 0, 2 do
    pipes[#pipes + 1] = newPipe(LCD_W + 20 + i * PIPE_SPACING)
  end
end

local function init()
  math.randomseed(getTime())
  best = 0
  state = "title"
  stickArmed = true
  lastTime = getTime()
  reset()
end

-- true once per stick flick (stick must return to center before next flap)
local function stickFlap()
  local ele = getValue("ele")
  if ele > 600 and stickArmed then
    stickArmed = false
    return true
  elseif ele < 300 then
    stickArmed = true
  end
  return false
end

local function hits(p)
  if BIRD_X + BIRD_S <= p.x or BIRD_X >= p.x + PIPE_W then
    return false
  end
  return birdY < p.top or birdY + BIRD_S > p.top + PIPE_GAP
end

local function update(dt, flap)
  if flap then
    birdVY = FLAP_VY
    playTone(1400, 30, 0, PLAY_NOW)
  end
  birdVY = birdVY + GRAVITY * dt
  birdY = birdY + birdVY * dt
  if birdY < 0 then
    birdY = 0
    birdVY = 0
  end

  local lastX = 0
  for _, p in ipairs(pipes) do
    p.x = p.x - PIPE_SPEED * dt
    if p.x > lastX then lastX = p.x end
    if not p.passed and p.x + PIPE_W < BIRD_X then
      p.passed = true
      score = score + 1
      playTone(2200, 40, 0, PLAY_NOW)
    end
    if hits(p) then
      state = "over"
    end
  end
  if pipes[1].x + PIPE_W < 0 then
    removeAt(pipes, 1)
    pipes[#pipes + 1] = newPipe(lastX + PIPE_SPACING)
  end

  if birdY + BIRD_S >= GROUND then
    birdY = GROUND - BIRD_S
    state = "over"
  end
  if state == "over" then
    if score > best then best = score end
    playTone(300, 300, 0, PLAY_NOW)
  end
end

local function draw()
  lcd.clear()
  for _, p in ipairs(pipes) do
    local x = math.floor(p.x)
    if x < LCD_W and x + PIPE_W > 0 then
      lcd.drawFilledRectangle(x, 0, PIPE_W, p.top)
      lcd.drawFilledRectangle(x, p.top + PIPE_GAP, PIPE_W, GROUND - p.top - PIPE_GAP)
    end
  end
  lcd.drawLine(0, GROUND, LCD_W - 1, GROUND, SOLID, FORCE)
  lcd.drawFilledRectangle(BIRD_X, math.floor(birdY), BIRD_S, BIRD_S)
  lcd.drawNumber(LCD_W - 2, 1, score, RIGHT + INVERS)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.1 then dt = 0.1 end

  local flap = (event == EVT_VIRTUAL_ENTER) or stickFlap()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 22, 14, "FLAPPY", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 40, 34, "ENTER or stick up", SMLSIZE)
    if flap then
      reset()
      state = "play"
      update(0, true)
    end
  elseif state == "play" then
    update(dt, flap)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 12, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 30, 32, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 44, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "title"
    end
  end
  return 0
end

return { init = init, run = run }
