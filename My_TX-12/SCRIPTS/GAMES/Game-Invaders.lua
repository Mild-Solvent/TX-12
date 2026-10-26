-- toolName = TNS|Invaders|TNE
---------------------------------------------------------------
-- Space Invaders for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Move:  aileron (right stick left/right)
-- Fire:  ENTER (wheel press) or right stick up
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local ROWS, COLS = 4, 8
local AW, AH = 7, 5          -- alien size
local SPX, SPY = 11, 8       -- alien spacing
local PW, PH = 9, 4          -- player size
local PY = LCD_H - PH - 1
local TOP = 9

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, aliens, alive, fleetX, fleetY, fleetDir, stepTimer
local px, shot, bombs, lives, score, best, wave, lastTime, frame

local function newWave()
  aliens = {}
  for r = 1, ROWS do
    aliens[r] = {}
    for c = 1, COLS do aliens[r][c] = true end
  end
  alive = ROWS * COLS
  fleetX, fleetY, fleetDir = 4, TOP + math.min(wave - 1, 4) * 2, 1
  stepTimer = 0
  shot, bombs = nil, {}
end

local function newGame()
  px = LCD_W / 2 - PW / 2
  lives, score, wave = 3, 0, 1
  newWave()
end

local function init()
  math.randomseed(getTime())
  best = 0
  frame = 0
  state = "title"
  lastTime = getTime()
  newGame()
end

local function alienPos(r, c)
  return fleetX + (c - 1) * SPX, fleetY + (r - 1) * SPY
end

-- Bounds of the living fleet in screen x.
local function fleetSpan()
  local minC, maxC = COLS, 1
  for r = 1, ROWS do
    for c = 1, COLS do
      if aliens[r][c] then
        if c < minC then minC = c end
        if c > maxC then maxC = c end
      end
    end
  end
  return fleetX + (minC - 1) * SPX, fleetX + (maxC - 1) * SPX + AW
end

local function lowestY()
  for r = ROWS, 1, -1 do
    for c = 1, COLS do
      if aliens[r][c] then
        local _, y = alienPos(r, c)
        return y + AH
      end
    end
  end
  return 0
end

local function stepFleet()
  local left, right = fleetSpan()
  if (fleetDir > 0 and right + 2 >= LCD_W) or (fleetDir < 0 and left - 2 <= 0) then
    fleetDir = -fleetDir
    fleetY = fleetY + 3
  else
    fleetX = fleetX + fleetDir * 2
  end
  frame = 1 - frame
  playTone(frame == 0 and 160 or 130, 25, 0, PLAY_NOW)
end

local function dropBomb()
  local c = math.random(COLS)
  for r = ROWS, 1, -1 do
    if aliens[r][c] then
      local x, y = alienPos(r, c)
      bombs[#bombs + 1] = { x = x + 3, y = y + AH }
      return
    end
  end
end

local function loseLife()
  lives = lives - 1
  bombs = {}
  playTone(250, 400, 0, PLAY_NOW)
  if lives <= 0 then
    if score > best then best = score end
    state = "over"
  end
end

local function update(dt, fire)
  local ail = getValue("ail")
  if math.abs(ail) > 100 then
    px = px + ail / 1024 * 70 * dt
  end
  if px < 0 then px = 0 end
  if px > LCD_W - PW then px = LCD_W - PW end

  if fire and not shot then
    shot = { x = math.floor(px) + 4, y = PY - 1 }
    playTone(1600, 30, 0, PLAY_NOW)
  end

  -- player shot
  if shot then
    shot.y = shot.y - 110 * dt
    if shot.y < 0 then
      shot = nil
    else
      for r = 1, ROWS do
        for c = 1, COLS do
          if shot and aliens[r][c] then
            local x, y = alienPos(r, c)
            if shot.x >= x and shot.x < x + AW and shot.y >= y and shot.y < y + AH then
              aliens[r][c] = false
              alive = alive - 1
              score = score + (ROWS - r + 1) * 10
              shot = nil
              playTone(900, 40, 0, PLAY_NOW)
            end
          end
        end
      end
    end
  end

  if alive == 0 then
    wave = wave + 1
    newWave()
    return
  end

  -- fleet gets faster as it shrinks
  stepTimer = stepTimer + dt
  local interval = 0.06 + 0.5 * alive / (ROWS * COLS) - (wave - 1) * 0.03
  if interval < 0.05 then interval = 0.05 end
  if stepTimer >= interval then
    stepTimer = 0
    stepFleet()
  end

  if math.random() < dt * (0.8 + wave * 0.3) and #bombs < 3 then
    dropBomb()
  end

  for i = #bombs, 1, -1 do
    local b = bombs[i]
    b.y = b.y + 45 * dt
    if b.y >= PY and b.y < PY + PH and b.x >= px and b.x < px + PW then
      removeAt(bombs, i)
      loseLife()
      if state ~= "play" then return end
    elseif b.y > LCD_H then
      removeAt(bombs, i)
    end
  end

  if lowestY() >= PY then
    lives = 1
    loseLife()
  end
end

local function drawAlien(x, y, r)
  if r == 1 then
    lcd.drawFilledRectangle(x + 2, y, 3, AH)
    lcd.drawFilledRectangle(x, y + 1, AW, 2)
  else
    lcd.drawFilledRectangle(x + 1, y, AW - 2, 3)
  end
  if frame == 0 then
    lcd.drawPoint(x, y + AH - 1)
    lcd.drawPoint(x + AW - 1, y + AH - 1)
  else
    lcd.drawPoint(x + 1, y + AH - 1)
    lcd.drawPoint(x + AW - 2, y + AH - 1)
  end
  lcd.drawPoint(x + 1, y + 3)
  lcd.drawPoint(x + AW - 2, y + 3)
end

local function draw()
  lcd.clear()
  lcd.drawText(1, 0, "SC " .. score, SMLSIZE)
  lcd.drawText(LCD_W / 2 - 8, 0, "W" .. wave, SMLSIZE)
  for i = 1, lives do
    lcd.drawFilledRectangle(LCD_W - i * 7, 1, 5, 3)
  end
  for r = 1, ROWS do
    for c = 1, COLS do
      if aliens[r][c] then
        local x, y = alienPos(r, c)
        drawAlien(math.floor(x), math.floor(y), r)
      end
    end
  end
  local x = math.floor(px)
  lcd.drawFilledRectangle(x, PY + 1, PW, PH - 1)
  lcd.drawFilledRectangle(x + 3, PY - 1, 3, 2)
  if shot then
    lcd.drawLine(shot.x, math.floor(shot.y), shot.x, math.floor(shot.y) + 2, SOLID, FORCE)
  end
  for _, b in ipairs(bombs) do
    lcd.drawLine(math.floor(b.x), math.floor(b.y), math.floor(b.x), math.floor(b.y) + 2, DOTTED, FORCE)
  end
end

local function stickFire()
  return getValue("ele") > 600
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.1 then dt = 0.1 end

  local fire = (event == EVT_VIRTUAL_ENTER) or stickFire()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 30, 22, "INVADERS", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 34, 40, "ENTER to start", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "play"
    end
  elseif state == "play" then
    update(dt, fire)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 18, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 32, 36, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 46, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
