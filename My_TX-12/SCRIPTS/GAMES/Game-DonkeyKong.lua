-- toolName = TNS|Donkey Kong|TNE
---------------------------------------------------------------
-- Donkey Kong for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Walk:  either stick left/right
-- Climb: right stick up/down while standing at a ladder
-- Jump:  SA or SD, or ENTER (wheel press)
-- Reach the girl on the top girder. Each level: faster barrels.
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local PH = 6       -- player 5x6, px is its centre
local WALK, CLIMB = 32, 20
local JUMP_V, JUMP_G = 66, 240  -- ~9 px high, ~0.55 s
local FALL_G = 200
local GOAL_X = 78
local DEAD = 350

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

-- girders 1 (bottom) .. 4 (top). Plain ifs, no lookup tables.
local function gy(g, x)
  if g == 1 then return 62 - x * 3 / 127
  elseif g == 2 then return 45 + x * 3 / 115
  elseif g == 3 then return 34 - (x - 12) * 3 / 115
  end
  return 17 + x * 3 / 112
end
local function gx0(g) if g == 3 then return 12 end return 0 end
local function gx1(g)
  if g == 2 then return 115 elseif g == 4 then return 112 end
  return 127
end
-- barrels roll downhill
local function gdir(g) if g == 1 or g == 3 then return -1 end return 1 end

local state, px, py, pg, ladder, air, jumpH, jumpV, ladders, barrels
local lives, score, best, level, throwT, armT, timer, lastTime, walkT

local function resetRound()
  px, pg, ladder, air, jumpH, jumpV = 8, 1, nil, false, 0, 0
  py = gy(1, px)
  barrels = {}
  throwT = 1.0
  armT = 0
  walkT = 0
end

local function newGame()
  lives, score, level = 3, 0, 1
  resetRound()
end

local function init()
  math.randomseed(getTime())
  best = 0
  -- ladder from girder lo up to lo + 1
  ladders = { { x = 96, lo = 1 }, { x = 26, lo = 1 }, { x = 20, lo = 2 },
    { x = 64, lo = 2 }, { x = 104, lo = 3 }, { x = 44, lo = 3 } }
  state = "title"
  lastTime = getTime()
  newGame()
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

local function loseLife()
  lives = lives - 1
  playTone(250, 500, -4, PLAY_NOW)
  state = "dead"
  timer = 1.2
end

local function movePlayer(dt, jump)
  local sx = getValue("ail")
  local r = getValue("rud")
  if math.abs(r) > math.abs(sx) then sx = r end
  local sy = getValue("ele")

  if ladder then
    local l = ladder
    if math.abs(sy) > DEAD then
      py = py - sy / math.abs(sy) * CLIMB * dt; walkT = walkT + dt
    end
    if py <= gy(l.lo + 1, l.x) then
      pg = l.lo + 1; ladder = nil
    elseif py >= gy(l.lo, l.x) then
      pg = l.lo; ladder = nil
    end
    if ladder then return end
  end

  if air then
    jumpH = jumpH + jumpV * dt
    jumpV = jumpV - JUMP_G * dt
    if jumpH <= 0 then jumpH = 0; air = false end
  end
  if math.abs(sx) > DEAD then
    px = px + sx / math.abs(sx) * WALK * dt; walkT = walkT + dt
  end
  if px < gx0(pg) + 2 then px = gx0(pg) + 2 end
  if px > gx1(pg) - 2 then px = gx1(pg) - 2 end

  if not air then
    if sy > DEAD or sy < -DEAD then
      for i = 1, #ladders do
        local l = ladders[i]
        if l and math.abs(px - l.x) <= 3 then
          if sy > DEAD and l.lo == pg then
            ladder = l; px = l.x; py = gy(pg, px) - 1
            return
          elseif sy < -DEAD and l.lo + 1 == pg then
            ladder = l; px = l.x; py = gy(pg, px) + 1
            return
          end
        end
      end
    end
    if jump then
      air = true
      jumpV = JUMP_V
      playTone(1200, 30, 0, PLAY_NOW)
    end
  end
  py = gy(pg, px) - jumpH
end

local function moveBarrels(dt)
  local speed = math.min(70, 30 + (level - 1) * 6)
  local chance = math.min(0.6, 0.2 + level * 0.06)
  for i = #barrels, 1, -1 do
    local b = barrels[i]
    local gone = false
    if b.m == 0 then
      local nx = b.x + gdir(b.g) * speed * dt
      if b.g > 1 then
        for k = 1, #ladders do
          local l = ladders[k]
          if l and l.lo + 1 == b.g and b.m == 0
              and (b.x - l.x) * (nx - l.x) < 0 and math.random() < chance then
            b.m = 2; nx = l.x; b.lo = l.lo
          end
        end
      end
      b.x = nx
      if b.m == 0 then
        if b.x < gx0(b.g) or b.x > gx1(b.g) then
          if b.g == 1 then
            gone = b.x < -4
          else
            b.m = 1; b.vy = 0; b.lo = b.g - 1
          end
        else
          b.y = gy(b.g, b.x)
        end
      end
    else
      if b.m == 1 then
        b.x = b.x + gdir(b.g) * speed * 0.3 * dt
        b.vy = b.vy + FALL_G * dt
        b.y = b.y + b.vy * dt
      else
        b.y = b.y + 35 * dt
      end
      if b.y >= gy(b.lo, b.x) then
        b.g = b.lo; b.m = 0; b.y = gy(b.g, b.x)
      end
    end
    if gone then
      removeAt(barrels, i)
    else
      -- jumped over a barrel on the same girder
      if air and b.m == 0 and b.g == pg and not b.sc and math.abs(b.x - px) < 3 then
        b.sc = true
        score = score + 100
        playTone(2000, 30, 0, PLAY_NOW)
      end
      if math.abs(b.x - px) < 4 and b.y > py - PH + 1 and b.y < py + 3 then
        loseLife()
        return
      end
    end
  end
end

local function update(dt, jump)
  movePlayer(dt, jump)

  throwT = throwT - dt
  if armT > 0 then armT = armT - dt end
  if throwT <= 0 then
    local lo = math.max(0.9, 2.2 - level * 0.2)
    throwT = lo + math.random() * 1.4
    barrels[#barrels + 1] = { x = 16, y = gy(4, 16), g = 4, m = 0, vy = 0, lo = 3, sc = false }
    armT = 0.3
  end

  moveBarrels(dt)
  if state ~= "play" then return end

  if pg == 4 and not ladder and math.abs(px - GOAL_X) < 5 then
    score = score + 500 + level * 100
    state = "clear"
    timer = 1.5
    playTone(2600, 300, 0, PLAY_NOW)
  end
end

local function drawPlayer()
  local x, y = math.floor(px), math.floor(py)
  lcd.drawFilledRectangle(x - 1, y - 6, 3, 2)
  lcd.drawFilledRectangle(x - 2, y - 4, 5, 3)
  if ladder or math.floor(walkT * 8) % 2 == 0 then
    lcd.drawPoint(x - 2, y - 1)
    lcd.drawPoint(x + 2, y - 1)
  else
    lcd.drawPoint(x - 1, y - 1)
    lcd.drawPoint(x + 1, y - 1)
  end
end

local function draw()
  lcd.clear()
  for g = 1, 4 do
    local x0, x1 = gx0(g), gx1(g)
    local y0, y1 = math.floor(gy(g, x0)), math.floor(gy(g, x1))
    lcd.drawLine(x0, y0, x1, y1, SOLID, FORCE)
    lcd.drawLine(x0, y0 + 2, x1, y1 + 2, SOLID, FORCE)
  end
  for i = 1, #ladders do
    local l = ladders[i]
    if l then
      local top = math.floor(gy(l.lo + 1, l.x)) + 3
      local bot = math.floor(gy(l.lo, l.x)) - 1
      lcd.drawLine(l.x - 2, top, l.x - 2, bot, SOLID, FORCE)
      lcd.drawLine(l.x + 2, top, l.x + 2, bot, SOLID, FORCE)
      for y = top + 1, bot, 3 do
        lcd.drawLine(l.x - 1, y, l.x + 1, y, SOLID, FORCE)
      end
    end
  end
  -- Kong
  lcd.drawFilledRectangle(4, 8, 5, 3)
  lcd.drawFilledRectangle(2, 11, 10, 6)
  if armT > 0 then
    lcd.drawLine(12, 11, 14, 8, SOLID, FORCE)
  else
    lcd.drawLine(12, 12, 13, 16, SOLID, FORCE)
  end
  -- the girl
  local sy = math.floor(gy(4, GOAL_X))
  lcd.drawRectangle(GOAL_X - 1, sy - 10, 3, 3)
  lcd.drawFilledRectangle(GOAL_X - 2, sy - 6, 5, 5)
  lcd.drawLine(GOAL_X - 3, sy - 2, GOAL_X + 3, sy - 2, SOLID, FORCE)

  for _, b in ipairs(barrels) do
    local x, y = math.floor(b.x), math.floor(b.y)
    lcd.drawRectangle(x - 2, y - 4, 4, 4)
    lcd.drawPoint(x - 1 + math.floor(x / 2) % 2, y - 3 + math.floor(x / 2) % 2)
  end
  if state ~= "dead" or math.floor(timer * 8) % 2 == 0 then drawPlayer() end

  lcd.drawText(20, 0, "L" .. level, SMLSIZE)
  for i = 1, lives do
    lcd.drawFilledRectangle(36 + i * 5, 2, 3, 3)
  end
  lcd.drawNumber(LCD_W - 1, 0, score, RIGHT + SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local jump = (event == EVT_VIRTUAL_ENTER) or switchPress()

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 36, 8, "DONKEY KONG", MIDSIZE + INVERS)
    lcd.drawText(4, 26, "Stick: walk + ladders", SMLSIZE)
    lcd.drawText(4, 36, "Jump: SA/SD/ENTER", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "play"
    end
  elseif state == "play" then
    update(dt, jump)
    draw()
  elseif state == "dead" or state == "clear" then
    timer = timer - dt
    draw()
    if state == "clear" then
      lcd.drawText(LCD_W / 2 - 26, 26, "LEVEL CLEAR", SMLSIZE + INVERS)
    end
    if timer <= 0 then
      if state == "clear" then
        level = level + 1
        resetRound()
        state = "play"
      elseif lives > 0 then
        resetRound()
        state = "play"
      else
        if score > best then best = score end
        state = "over"
      end
    end
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 14, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 32, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 42, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
