-- Doodle Jump sprites, loaded once by Game-DoodleJump.lua
local PW, PH = 6, 6

local function doodle(x, y, face, fly, flyK, shield, shoes)
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
  if fly > 0 and y > 2 then
    if flyK == 3 then lcd.drawLine(x, y - 2, x + 5, y - 2, SOLID, FORCE)
    else lcd.drawLine(x - 1, y + 1, x - 1, y + 6, SOLID, FORCE) end
  end
  if shield and y > 1 then lcd.drawRectangle(x - 2, y - 2, PW + 4, PH + 3) end
  if shoes > 0 then lcd.drawLine(x, y + PH, x + 5, y + PH, SOLID, FORCE) end
end

-- k: 1 monster, 2 bat, 3 UFO, 4 black hole, 9 coin
local function mob(m, t)
  local x, y = math.floor(m.x), math.floor(m.y)
  if y < 1 or y >= LCD_H - 6 then return end
  if m.k == 9 then
    lcd.drawRectangle(x + 2, y, 3, 4)
  elseif m.k == 1 then
    y = y + math.floor(math.sin(m.ph) * 1.5 + 0.5)
    lcd.drawRectangle(x, y, 8, 5)
    lcd.drawPoint(x + 2, y + 1); lcd.drawPoint(x + 5, y + 1)
    lcd.drawPoint(x + 1, y + 5); lcd.drawPoint(x + 6, y + 5)
    lcd.drawPoint(x + 3, y - 1); lcd.drawPoint(x + 4, y - 1)
  elseif m.k == 2 then
    local f = (math.floor(m.ph) % 2) * 2
    lcd.drawLine(x, y + f, x + 3, y + 2, SOLID, FORCE)
    lcd.drawLine(x + 4, y + 2, x + 7, y + f, SOLID, FORCE)
    lcd.drawPoint(x + 3, y + 3); lcd.drawPoint(x + 4, y + 3)
  elseif m.k == 3 then
    lcd.drawRectangle(x + 2, y, 4, 2)
    lcd.drawLine(x, y + 2, x + 7, y + 2, SOLID, FORCE)
    lcd.drawLine(x + 1, y + 3, x + 6, y + 3, DOTTED, FORCE)
    if m.hp > 1 then lcd.drawPoint(x + 3, y + 5) end
  else
    lcd.drawFilledRectangle(x + 3, y + 2, 2, 2, FORCE)
    local o = math.floor(t * 4) % 2
    lcd.drawRectangle(x + o, y + o - 1, 8 - 2 * o, 8 - 2 * o)
  end
end

-- kind 0 normal, 1 moving, 2 crumbles, 3 vanishes, 4 TNT
local function plat(p, t)
  local x, y, w, k = math.floor(p.x), math.floor(p.y), p.w, p.kind
  if y < 0 or y >= LCD_H - 2 then return end
  if k == 0 then
    lcd.drawFilledRectangle(x, y, w, 2, FORCE)
  elseif k == 1 then
    lcd.drawRectangle(x, y, w, 3)
  elseif k == 2 then
    lcd.drawLine(x, y, x + w - 1, y, DOTTED, FORCE)
    lcd.drawLine(x + 1, y + 1, x + w - 2, y + 1, DOTTED, FORCE)
  elseif k == 3 then
    lcd.drawLine(x, y, x + w - 1, y, SOLID, FORCE)
    lcd.drawLine(x + 1, y + 2, x + w - 2, y + 2, DOTTED, FORCE)
  elseif p.t > 1 or math.floor(t * 8) % 2 == 0 then
    lcd.drawRectangle(x, y, w, 3)
    lcd.drawLine(x + 2, y + 1, x + w - 3, y + 1, DOTTED, FORCE)
  end
  local it = p.item
  if it and y > 8 then
    local ix = x + math.floor(w / 2) - 2
    if it == 1 then lcd.drawRectangle(ix + 1, y - 3, 3, 3)
    elseif it >= 2 and it <= 5 then lcd.drawText(ix, y - 7, string.sub("SPJO", it - 1, it - 1), SMLSIZE) end
  end
end

-- "ZONE n NAME" banner
local function banner(z)
  local n = "CHAOS"
  if z == 1 then n = "MEADOW" elseif z == 2 then n = "WINDY"
  elseif z == 3 then n = "SPOOKY" elseif z == 4 then n = "SPACE" end
  lcd.drawText(LCD_W / 2 - 40, 12, "ZONE " .. z .. " " .. n, SMLSIZE + INVERS)
end

-- title / game-over text
local function screen(title, score, zone, best)
  if title then
    lcd.drawText(LCD_W / 2 - 36, 4, "DOODLE JUMP", MIDSIZE + INVERS)
    lcd.drawText(8, 22, "Stick L/R steer", SMLSIZE)
    lcd.drawText(8, 30, "SA/SD shoot up", SMLSIZE)
    lcd.drawText(8, 38, "Stomp monsters!", SMLSIZE)
  else
    lcd.drawText(LCD_W / 2 - 28, 4, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(8, 26, "Score " .. score .. " Zone " .. zone, SMLSIZE)
  end
  lcd.drawText(8, 48, "Best " .. best .. "  ENTER play", SMLSIZE + INVERS)
end

return { doodle = doodle, mob = mob, plat = plat, screen = screen, banner = banner }
