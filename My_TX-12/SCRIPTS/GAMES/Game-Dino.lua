-- toolName = TNS|Dino Runner|TNE
---------------------------------------------------------------
-- Dino Runner (offline dinosaur) for 128x64 B&W EdgeTX radios
--
-- Jump:  SA or SD, ENTER (wheel press), or flick right stick up
-- Cacti, then birds: low ones must be jumped, high ones
-- fly over you if you stay on the ground. Ever faster.
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local GROUND = LCD_H - 6
local DX = 12
local DW, DH = 8, 10
local JUMP_V = 150      -- px/s
local GRAVITY = 520     -- px/s^2  -> ~21 px high, ~0.58 s in the air
local SPEED0 = 55       -- px/s
local ACCEL = 1.4       -- px/s gained per second
local MAX_SPEED = 135
local BIRD_DIST = 2400  -- px run before birds appear

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, dinoY, dinoVY, obs, speed, dist, score, best, lastTime
local stickArmed, nextGap, legT, milestone

local function reset()
  dinoY = 0          -- height above ground
  dinoVY = 0
  speed = SPEED0
  dist = 0
  score = 0
  milestone = 100
  legT = 0
  obs = {}
  nextGap = 40
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

-- true once per stick flick (stick must return to center before next jump)
local function stickJump()
  local ele = getValue("ele")
  if ele > 600 and stickArmed then
    stickArmed = false
    return true
  elseif ele < 300 then
    stickArmed = true
  end
  return false
end

local function spawn()
  local o
  if dist > BIRD_DIST and math.random() < 0.3 then
    -- bird: top is its height above ground of its upper edge
    local high = math.random() < 0.4
    o = { x = LCD_W + 2, w = 9, h = 5, bird = true, top = high and 22 or 11 }
  else
    local n = 1
    if dist > 600 and math.random() < 0.4 then n = 2 end
    if dist > 1500 and math.random() < 0.25 then n = 3 end
    local h = math.random(8, 10 + math.min(3, math.floor(dist / 800)))
    o = { x = LCD_W + 2, w = n * 4 - 1, h = h, bird = false, top = h }
  end
  obs[#obs + 1] = o
  -- gap to the next obstacle: enough to land and jump again
  nextGap = math.floor(speed * (0.75 + math.random() * 0.9)) + 12 + o.w
end

local function hits(o)
  local ox = o.x
  if DX + DW - 2 <= ox or DX + 1 >= ox + o.w then return false end
  -- vertical, all as heights above ground
  local dBot, dTop = dinoY, dinoY + DH - 1
  local oTop, oBot = o.top, o.top - o.h
  return dBot < oTop - 1 and dTop > oBot + 1
end

local function update(dt, jump)
  if jump and dinoY <= 0 then
    dinoVY = JUMP_V
    playTone(1200, 30, 0, PLAY_NOW)
  end
  if dinoVY ~= 0 or dinoY > 0 then
    dinoVY = dinoVY - GRAVITY * dt
    dinoY = dinoY + dinoVY * dt
    if dinoY <= 0 then
      dinoY = 0
      dinoVY = 0
    end
  end

  speed = math.min(MAX_SPEED, speed + ACCEL * dt)
  local dx = speed * dt
  dist = dist + dx
  score = math.floor(dist / 8)
  if score >= milestone then
    milestone = milestone + 100
    playTone(2600, 60, 0, PLAY_NOW)
  end
  legT = legT + dt

  local last = nil
  for i = #obs, 1, -1 do
    local o = obs[i]
    o.x = o.x - dx
    if o.x + o.w < 0 then
      removeAt(obs, i)
    else
      if last == nil or o.x > last.x then last = o end
      if hits(o) then state = "over" end
    end
  end
  if last == nil or last.x + last.w < LCD_W - nextGap then
    spawn()
  end

  if state == "over" then
    if score > best then best = score end
    playTone(300, 300, 0, PLAY_NOW)
  end
end

local function drawDino()
  local y = math.floor(GROUND - dinoY - DH)
  lcd.drawFilledRectangle(DX + 3, y, 5, 3)          -- head
  lcd.drawFilledRectangle(DX + 1, y + 3, 5, 4)      -- body
  lcd.drawPoint(DX, y + 4)                          -- tail
  lcd.drawPoint(DX + 6, y + 4)                      -- arm
  if dinoY > 0 or math.floor(legT * 10) % 2 == 0 then
    lcd.drawLine(DX + 2, y + 7, DX + 2, y + 9, SOLID, FORCE)
    lcd.drawLine(DX + 4, y + 7, DX + 4, y + 8, SOLID, FORCE)
  else
    lcd.drawLine(DX + 2, y + 7, DX + 2, y + 8, SOLID, FORCE)
    lcd.drawLine(DX + 4, y + 7, DX + 4, y + 9, SOLID, FORCE)
  end
end

local function drawObs(o)
  local x = math.floor(o.x)
  if o.bird then
    local y = GROUND - o.top
    lcd.drawFilledRectangle(x + 2, y + 2, 6, 2)
    lcd.drawPoint(x, y + 2)
    lcd.drawPoint(x + 1, y + 2)
    if math.floor(legT * 6) % 2 == 0 then
      lcd.drawLine(x + 4, y, x + 5, y + 1, SOLID, FORCE)
    else
      lcd.drawLine(x + 4, y + 4, x + 5, y + 3, SOLID, FORCE)
    end
  else
    local n = math.floor((o.w + 1) / 4)
    for k = 0, n - 1 do
      local cx = x + k * 4
      lcd.drawFilledRectangle(cx, GROUND - o.h, 3, o.h)
    end
    if o.h > 8 then
      lcd.drawPoint(x - 1, GROUND - o.h + 3)
      lcd.drawPoint(x + o.w, GROUND - o.h + 4)
    end
  end
end

local function draw()
  lcd.clear()
  lcd.drawLine(0, GROUND, LCD_W - 1, GROUND, SOLID, FORCE)
  -- pebbles scroll with the ground
  local off = math.floor(dist) % 32
  for i = 0, 4 do
    lcd.drawPoint(i * 32 + 7 - off, GROUND + 2)
    lcd.drawPoint(i * 32 + 22 - off, GROUND + 4)
  end
  for _, o in ipairs(obs) do drawObs(o) end
  drawDino()
  lcd.drawNumber(LCD_W - 2, 1, score, RIGHT)
  if best > 0 then lcd.drawText(1, 1, "HI " .. best, SMLSIZE) end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local jump = (event == EVT_VIRTUAL_ENTER) or switchPress() or stickJump()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 34, 12, "DINO RUNNER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 46, 30, "Jump: SA/SD/ENTER", SMLSIZE)
    if jump then
      reset()
      state = "play"
      update(0, true)
    end
  elseif state == "play" then
    update(dt, jump)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 12, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 34, 30, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 40, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "title"
    end
  end
  return 0
end

return { init = init, run = run }
