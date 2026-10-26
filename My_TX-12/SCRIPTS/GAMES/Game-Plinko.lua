-- toolName = TNS|Plinko|TNE
---------------------------------------------------------------
-- Plinko for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Aim:   right stick left/right (or wheel)
-- Drop:  SA or SD, ENTER (wheel press)
-- 5 balls per round, 10 credits per ball, slots pay credits
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local SLOT_W, NSLOT = 11, 9
local BW = SLOT_W * NSLOT   -- board width, HUD to the right
local HALF = math.floor(BW / 2)
local PEG_ROWS = 8
local PEG_Y0, PEG_DY = 12, 5
local SLOT_Y = 54
local GRAVITY = 150         -- px/s^2
local MAX_VY = 70
local STEP = 0.02           -- physics sub-step, s
local BALLS = 5
local COST = 10
local START_CREDITS = 100
local PAYS = "02051000200010050502" -- 2 digits per slot

local state, credits, best, dropX, dropped, roundWin, balls, cooldown
local flashSlot, flashT, popText, popX, popT, lastTime

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local function slotPay(s)
  if s < 1 or s > NSLOT then return 0 end
  return tonumber(string.sub(PAYS, s * 2 - 1, s * 2)) or 0
end

local function newRound()
  dropped, roundWin = 0, 0
  balls = {}
  cooldown = 0
end

local function init()
  math.randomseed(getTime())
  credits, best = START_CREDITS, START_CREDITS
  dropX = BW / 2
  flashSlot, flashT, popT = 0, 0, 0
  popText, popX = "", 0
  state = "title"
  lastTime = getTime()
  newRound()
end

-- "sa" / "sd" once per press, else nil. Works for buttons and toggles:
-- a switch left in a new position for 0.5 s counts as its new rest.
local swLast, swRest, swSince = {}, {}, {}
local function switchPress()
  local now = getTime()
  local pressed = nil
  for i = 1, 2 do
    local n = (i == 1) and "sa" or "sd"
    local v = getValue(n) or 0
    if swLast[n] == nil then
      swLast[n], swRest[n], swSince[n] = v, v, now
    elseif v ~= swLast[n] then
      if v ~= swRest[n] and pressed == nil then pressed = n end
      swLast[n], swSince[n] = v, now
    elseif v ~= swRest[n] and now - swSince[n] > 50 then
      swRest[n] = v
    end
  end
  return pressed
end

local function pegX(row, k)
  if row % 2 == 0 then return 5.5 + SLOT_W * k end
  return SLOT_W * (k + 1)
end

local function drop()
  if dropped >= BALLS or credits < COST or cooldown > 0 then return end
  credits = credits - COST
  dropped = dropped + 1
  cooldown = 0.3
  balls[#balls + 1] = { x = dropX + (math.random() - 0.5), y = 4, vx = 0, vy = 0 }
  playTone(900, 30, 0, PLAY_NOW)
end

local function land(b)
  local s = math.floor(b.x / SLOT_W) + 1
  if s < 1 then s = 1 elseif s > NSLOT then s = NSLOT end
  local p = slotPay(s)
  credits = credits + p
  roundWin = roundWin + p
  if credits > best then best = credits end
  flashSlot, flashT = s, 0.8
  popText = "+" .. p
  popX = (s - 1) * SLOT_W + SLOT_W / 2
  popT = 0.8
  if p >= 20 then
    playTone(3000, 300, 0, PLAY_NOW)
  elseif p > 0 then
    playTone(1800 + p * 40, 100, 0, PLAY_NOW)
  else
    playTone(250, 150, 0, PLAY_NOW)
  end
end

-- one physics sub-step for a ball; true when it reached a slot
local function stepBall(b, h)
  b.vy = b.vy + GRAVITY * h
  if b.vy > MAX_VY then b.vy = MAX_VY end
  b.vx = b.vx * (1 - 1.2 * h)
  b.x = b.x + b.vx * h
  b.y = b.y + b.vy * h
  if b.x < 2 then
    b.x = 2
    b.vx = math.abs(b.vx) * 0.6
  elseif b.x > BW - 2 then
    b.x = BW - 2
    b.vx = -math.abs(b.vx) * 0.6
  end
  local row = math.floor((b.y - PEG_Y0) / PEG_DY + 0.5)
  if row >= 0 and row < PEG_ROWS and b.vy > 0 then
    local py = PEG_Y0 + row * PEG_DY
    local k
    if row % 2 == 0 then
      k = math.floor(b.x / SLOT_W)
      if k > NSLOT - 1 then k = NSLOT - 1 end
    else
      k = math.floor(b.x / SLOT_W + 0.5) - 1
      if k > NSLOT - 2 then k = NSLOT - 2 end
    end
    if k < 0 then k = 0 end
    local px = pegX(row, k)
    local dx, dy = b.x - px, b.y - py
    if dy < 0.5 and dx * dx + dy * dy < 6.25 then
      local dir = math.random(0, 1) * 2 - 1
      b.vx = dir * (24 + math.random(0, 10))
      b.vy = -b.vy * 0.3
      b.y = py - 2.5
      b.x = px + dir
      playTone(2600 - row * 120, 8, 0, PLAY_NOW)
    end
  end
  if b.y >= SLOT_Y then
    land(b)
    return true
  end
  return false
end

local function update(dt, aim)
  dropX = dropX + aim * 70 * dt
  if dropX < 3 then dropX = 3 elseif dropX > BW - 3 then dropX = BW - 3 end
  if cooldown > 0 then cooldown = cooldown - dt end
  if flashT > 0 then flashT = flashT - dt end
  if popT > 0 then popT = popT - dt end
  local t = dt
  while t > 0.0001 do
    local h = math.min(STEP, t)
    t = t - h
    local i = 1
    while i <= #balls do
      if stepBall(balls[i], h) then
        removeAt(balls, i)
      else
        i = i + 1
      end
    end
  end
end

local function drawBall(x, y)
  x, y = math.floor(x), math.floor(y)
  lcd.drawFilledRectangle(x - 1, y, 3, 1)
  lcd.drawFilledRectangle(x, y - 1, 1, 3)
end

local function draw()
  lcd.clear()
  -- walls
  lcd.drawLine(0, 6, 0, LCD_H - 1, SOLID, FORCE)
  lcd.drawLine(BW, 0, BW, LCD_H - 1, SOLID, FORCE)
  -- pegs
  for row = 0, PEG_ROWS - 1 do
    local y = PEG_Y0 + row * PEG_DY
    local n = NSLOT
    if row % 2 == 1 then n = NSLOT - 1 end
    for k = 0, n - 1 do
      lcd.drawFilledRectangle(math.floor(pegX(row, k)), y, 2, 2)
    end
  end
  -- slots
  lcd.drawLine(0, LCD_H - 1, BW, LCD_H - 1, SOLID, FORCE)
  for s = 1, NSLOT do
    local x = (s - 1) * SLOT_W
    if s > 1 then lcd.drawLine(x, SLOT_Y, x, LCD_H - 1, SOLID, FORCE) end
    local flags = SMLSIZE
    if s == flashSlot and flashT > 0 and math.floor(flashT * 8) % 2 == 0 then
      lcd.drawFilledRectangle(x + 1, SLOT_Y, SLOT_W - 1, LCD_H - 1 - SLOT_Y)
      flags = flags + INVERS
    end
    lcd.drawText(x + 6, SLOT_Y + 2, tostring(slotPay(s)), flags + CENTER)
  end
  -- dropper
  if state == "play" and dropped < BALLS then
    local x = math.floor(dropX)
    lcd.drawLine(x - 3, 0, x + 3, 0, SOLID, FORCE)
    lcd.drawLine(x - 2, 1, x + 2, 1, SOLID, FORCE)
    if cooldown <= 0 then drawBall(x, 4) end
  end
  for i = 1, #balls do
    local b = balls[i]
    if b then drawBall(b.x, b.y) end
  end
  if popT > 0 then
    local y = math.floor(SLOT_Y - 10 - (0.8 - popT) * 15)
    lcd.drawText(math.floor(popX), y, popText, SMLSIZE + CENTER + INVERS)
  end
  -- HUD
  local hx = BW + 3
  lcd.drawText(hx, 0, "CRED", SMLSIZE)
  lcd.drawText(hx, 8, tostring(credits), SMLSIZE)
  lcd.drawText(hx, 19, "BALL", SMLSIZE)
  for i = 1, BALLS do
    local y = 29 + math.floor((i - 1) / 3) * 5
    local x = hx + 2 + ((i - 1) % 3) * 6
    if i > dropped then
      drawBall(x, y)
    else
      lcd.drawFilledRectangle(x, y, 1, 1)
    end
  end
  lcd.drawText(hx, 42, "WIN", SMLSIZE)
  lcd.drawText(hx, 50, tostring(roundWin), SMLSIZE)
end

local function banner(a, b)
  lcd.drawFilledRectangle(8, 18, BW - 16, 22, ERASE)
  lcd.drawRectangle(8, 18, BW - 16, 22)
  lcd.drawText(HALF, 21, a, SMLSIZE + CENTER)
  lcd.drawText(HALF, 30, b, SMLSIZE + CENTER)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local press = switchPress() or (event == EVT_VIRTUAL_ENTER)
  local aim = (getValue("ail") or 0) / 1024
  if math.abs(aim) < 0.08 then aim = 0 end
  if event == EVT_VIRTUAL_NEXT then dropX = dropX + 3 end
  if event == EVT_VIRTUAL_PREV then dropX = dropX - 3 end

  if state == "title" then
    update(dt, aim)
    draw()
    lcd.drawFilledRectangle(6, 14, BW - 12, 32, ERASE)
    lcd.drawRectangle(6, 14, BW - 12, 32)
    lcd.drawText(HALF, 16, "PLINKO", MIDSIZE + CENTER)
    lcd.drawText(HALF, 29, "Stick aims", SMLSIZE + CENTER)
    lcd.drawText(HALF, 37, "SA/SD drops", SMLSIZE + CENTER)
    if press then
      state = "play"
      newRound()
    end
  elseif state == "play" then
    if press then drop() end
    update(dt, aim)
    if #balls == 0 and (dropped >= BALLS or (credits < COST and dropped > 0)) then
      state = "round"
      playTone(roundWin >= COST * BALLS and 2800 or 900, 150, 0, PLAY_NOW)
    elseif #balls == 0 and credits < COST then
      state = "over"
    end
    draw()
  elseif state == "round" then
    update(dt, aim)
    draw()
    banner("Round won " .. roundWin, "ENTER: next round")
    if press then
      if credits < COST then
        state = "over"
      else
        newRound()
        state = "play"
      end
    end
  else
    update(dt, aim)
    draw()
    banner("OUT OF CREDITS", "Best " .. best .. "  ENTER")
    if event == EVT_VIRTUAL_ENTER then
      credits = START_CREDITS
      newRound()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
