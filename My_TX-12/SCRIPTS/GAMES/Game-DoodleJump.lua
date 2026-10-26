-- toolName = TNS|Doodle Jump|TNE
---------------------------------------------------------------
-- Doodle Jump for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Steer: either stick left/right; the screen wraps sideways
-- You bounce by yourself. Boxed platforms move, dotted ones
-- crumble, springs launch you high. Don't fall off the bottom.
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local PW, PH = 6, 6
local BOUNCE = 118      -- px/s  -> ~25 px high
local SPRING = 175      -- px/s  -> ~55 px high
local GRAVITY = 280     -- px/s^2
local MOVE = 95         -- px/s at full stick
local TOPLINE = 24      -- camera keeps the player below this line
local MAX_GAP = 21      -- must stay below the bounce height

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, px, py, vy, face, plats, topY, climbed, score, best, lastTime

-- kind 0 normal, 1 moving, 2 crumbling
local function addPlat(x, y, w, kind, spring)
  local vx = 0
  if kind == 1 then
    vx = math.random(18, 34)
    if math.random() < 0.5 then vx = -vx end
  end
  plats[#plats + 1] = { x = x, y = y, w = w, kind = kind, vx = vx, spring = spring }
end

-- fill the space above the screen with platforms, harder the higher you are
local function generate()
  while topY > -6 do
    local gapMin = math.min(14, 7 + math.floor(climbed / 250))
    local gapMax = math.min(MAX_GAP, 13 + math.floor(climbed / 150))
    topY = topY - math.random(gapMin, gapMax)
    local w = math.max(10, 18 - math.floor(climbed / 300))
    local kind = 0
    if math.random() < math.min(0.4, climbed / 2500) then kind = 1 end
    local spring = kind == 0 and climbed > 100 and math.random() < 0.06
    addPlat(math.random(0, LCD_W - w), topY, w, kind, spring)
    if climbed > 150 and math.random() < 0.2 then
      -- crumbling decoy between steps; never needed to climb
      addPlat(math.random(0, LCD_W - 14), topY + math.random(4, 8), 14, 2, false)
    end
  end
end

local function reset()
  px = LCD_W / 2 - PW / 2
  py = LCD_H - 10 - PH
  vy = -BOUNCE
  face = 1
  climbed = 0
  score = 0
  plats = {}
  addPlat(LCD_W / 2 - 15, LCD_H - 8, 30, 0, false)
  topY = LCD_H - 8
  generate()
end

local function init()
  math.randomseed(getTime())
  best = 0
  state = "title"
  lastTime = getTime()
  reset()
end

local function overlapX(x, p)
  return x + PW - 1 > p.x and x + 1 < p.x + p.w
end

local function update(dt)
  local s = getValue("ail")
  local r = getValue("rud")
  if math.abs(r) > math.abs(s) then s = r end
  if math.abs(s) > 120 then
    px = px + s / 1024 * MOVE * dt
    if s > 0 then face = 1 else face = -1 end
  end
  if px < 0 then px = px + LCD_W end
  if px >= LCD_W then px = px - LCD_W end

  local prevBot = py + PH
  vy = vy + GRAVITY * dt
  py = py + vy * dt
  local bot = py + PH

  for i = #plats, 1, -1 do
    local p = plats[i]
    if p.kind == 1 then
      p.x = p.x + p.vx * dt
      if p.x < 0 then p.x = 0; p.vx = -p.vx end
      if p.x > LCD_W - p.w then p.x = LCD_W - p.w; p.vx = -p.vx end
    end
    if vy > 0 and prevBot <= p.y + 1 and bot >= p.y
        and (overlapX(px, p) or overlapX(px - LCD_W, p)) then
      if p.kind == 2 then
        removeAt(plats, i)
        playTone(300, 40, 0, PLAY_NOW)
      else
        py = p.y - PH
        if p.spring then
          vy = -SPRING
          playTone(2400, 80, 0, PLAY_NOW)
        else
          vy = -BOUNCE
          playTone(1100, 20, 0, PLAY_NOW)
        end
      end
    end
  end

  -- camera: scroll the world down when the player climbs high
  if py < TOPLINE then
    local shift = TOPLINE - py
    py = TOPLINE
    climbed = climbed + shift
    topY = topY + shift
    for i = #plats, 1, -1 do
      local p = plats[i]
      p.y = p.y + shift
      if p.y > LCD_H + 2 then removeAt(plats, i) end
    end
    generate()
    score = math.floor(climbed / 2)
  end

  if py > LCD_H then
    state = "over"
    if score > best then best = score end
    playTone(400, 400, -6, PLAY_NOW)
  end
end

local function drawDoodle(x, y)
  lcd.drawRectangle(x, y, PW, PH - 2)
  if face > 0 then
    lcd.drawPoint(x + 3, y + 1)
    lcd.drawLine(x + PW, y + 2, x + PW + 1, y + 2, SOLID, FORCE)
  else
    lcd.drawPoint(x + 2, y + 1)
    lcd.drawLine(x - 2, y + 2, x - 1, y + 2, SOLID, FORCE)
  end
  lcd.drawPoint(x + 1, y + PH - 1)
  lcd.drawPoint(x + 4, y + PH - 1)
end

local function draw()
  lcd.clear()
  for _, p in ipairs(plats) do
    local x, y = math.floor(p.x), math.floor(p.y)
    if y >= -2 and y < LCD_H then
      if p.kind == 0 then
        lcd.drawFilledRectangle(x, y, p.w, 2)
        if p.spring then
          lcd.drawRectangle(x + 3, y - 3, 3, 3)
        end
      elseif p.kind == 1 then
        lcd.drawRectangle(x, y, p.w, 3)
      else
        lcd.drawLine(x, y, x + p.w - 1, y, DOTTED, FORCE)
        lcd.drawLine(x + 1, y + 1, x + p.w - 2, y + 1, DOTTED, FORCE)
      end
    end
  end
  local x, y = math.floor(px), math.floor(py)
  drawDoodle(x, y)
  if x + PW > LCD_W then drawDoodle(x - LCD_W, y) end
  lcd.drawNumber(LCD_W - 1, 0, score, RIGHT + SMLSIZE + INVERS)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 36, 12, "DOODLE JUMP", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 46, 30, "Stick L/R to steer", SMLSIZE)
    lcd.drawText(LCD_W / 2 - 34, 40, "ENTER to start", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "play"
    end
  elseif state == "play" then
    update(dt)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 12, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 30, "Height " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 40, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
