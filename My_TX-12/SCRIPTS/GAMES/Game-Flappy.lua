-- toolName = TNS|Flappy|TNE
---------------------------------------------------------------
-- Flappy bird for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Flap:  SA or SD, ENTER (wheel press), or flick right stick up
-- Every 7 pipes: faster, narrower gaps, gaps swing top <-> bottom
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local GROUND = LCD_H - 4
local BIRD_X = 24
local BIRD_S = 4
local GRAVITY = 220     -- px/s^2
local FLAP_VY = -62     -- px/s
local PIPE_W = 9
local PIPE_GAP = 24     -- level 0; shrinks 1 px per level
local MIN_GAP = 17
local PIPE_SPACING = 52 -- px; grows with speed so a pipe is ~1 s away
local PIPE_SPEED = 38   -- px/s at level 0
local SPEED_STEP = 7    -- px/s faster per level
local MAX_SPEED = 80
local LEVEL_PIPES = 7   -- pipes passed per level
local SWING_LEVELS = 4  -- level at which gaps alternate fully top/bottom

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, birdY, birdVY, pipes, score, best, lastTime, stickArmed
local level, speed

local function setLevel(l)
  level = l
  speed = math.min(MAX_SPEED, PIPE_SPEED + level * SPEED_STEP)
end

local function spacing()
  return math.max(PIPE_SPACING, speed)
end

-- the higher the level, the further a gap is pulled to the side
-- opposite the previous one, until it sits at the top or bottom edge
local function newPipe(x, prevTop)
  local gap = math.max(MIN_GAP, PIPE_GAP - level)
  local lo, hi = 6, GROUND - gap - 6
  local top = math.random(lo, hi)
  if prevTop and level > 0 then
    local far = (prevTop - lo < hi - prevTop) and hi or lo
    local pull = math.min(1, level / SWING_LEVELS)
    top = math.floor(top + (far - top) * pull + 0.5)
  end
  return { x = x, top = top, gap = gap, passed = false }
end

local function reset()
  birdY = LCD_H / 2 - 8
  birdVY = 0
  score = 0
  setLevel(0)
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
  return birdY < p.top or birdY + BIRD_S > p.top + p.gap
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

  local last = pipes[1]
  for _, p in ipairs(pipes) do
    p.x = p.x - speed * dt
    if p.x > last.x then last = p end
    if not p.passed and p.x + PIPE_W < BIRD_X then
      p.passed = true
      score = score + 1
      if score % LEVEL_PIPES == 0 then
        setLevel(level + 1)
        playTone(3000, 120, 0, PLAY_NOW)
      else
        playTone(2200, 40, 0, PLAY_NOW)
      end
    end
    if hits(p) then
      state = "over"
    end
  end
  if pipes[1].x + PIPE_W < 0 then
    removeAt(pipes, 1)
    pipes[#pipes + 1] = newPipe(last.x + spacing(), last.top)
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
      local w = PIPE_W  -- clip at the left edge: EdgeTX writes outside the screen at x < 0
      if x < 0 then w, x = w + x, 0 end
      lcd.drawFilledRectangle(x, 0, w, p.top)
      lcd.drawFilledRectangle(x, p.top + p.gap, w, GROUND - p.top - p.gap)
    end
  end
  lcd.drawLine(0, GROUND, LCD_W - 1, GROUND, SOLID, FORCE)
  lcd.drawFilledRectangle(BIRD_X, math.floor(birdY), BIRD_S, BIRD_S)
  lcd.drawNumber(LCD_W - 2, 1, score, RIGHT + INVERS)
  if level > 0 then lcd.drawText(1, 1, "L" .. (level + 1), SMLSIZE + INVERS) end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.1 then dt = 0.1 end

  local flap = (event == EVT_VIRTUAL_ENTER) or switchPress() or stickFlap()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 22, 14, "FLAPPY", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 40, 34, "SA / SD or ENTER", SMLSIZE)
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
