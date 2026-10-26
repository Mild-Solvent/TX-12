-- Racer menu and results screens, loaded by Game-Racer.lua only
-- while not racing (keeps the main script small)
local M = {}

-- c: shared settings table { cur, flick, nPl, nAI, laps }
-- returns true when the race should start
function M.menu(c, event, press, drawCar)
  local e = getValue("ele")
  local mv = 0
  if event == EVT_VIRTUAL_NEXT then mv = 1 elseif event == EVT_VIRTUAL_PREV then mv = -1 end
  if c.flick and e < -600 then mv, c.flick = 1, false
  elseif c.flick and e > 600 then mv, c.flick = -1, false
  elseif math.abs(e) < 300 then c.flick = true end
  local cur = (c.cur + mv - 1) % 4 + 1
  if c.nPl == 1 and cur == 2 then cur = cur + mv end
  if cur < 1 then cur = 4 elseif cur > 4 then cur = 1 end
  c.cur = cur
  if event == EVT_VIRTUAL_ENTER then
    if cur == 1 then c.nPl = 3 - c.nPl
    elseif cur == 2 then c.nAI = 2 - c.nAI
    elseif cur == 3 then c.laps = 8 - c.laps
    else press = true end
  end
  if press then return true end
  lcd.clear()
  lcd.drawText(1, 1, " RACER ", SMLSIZE + INVERS)
  lcd.drawText(46, 1, "wheel+ENTER", SMLSIZE)
  local na = c.nPl == 1 and "3" or tostring(c.nAI)
  lcd.drawText(8, 11, "Players  " .. c.nPl, SMLSIZE + (cur == 1 and INVERS or 0))
  lcd.drawText(8, 19, "AI cars  " .. na, SMLSIZE + (cur == 2 and INVERS or 0))
  lcd.drawText(8, 27, "Laps     " .. c.laps, SMLSIZE + (cur == 3 and INVERS or 0))
  lcd.drawText(8, 35, "START", SMLSIZE + (cur == 4 and INVERS or 0))
  drawCar(76, 15, 1)
  lcd.drawText(80, 11, "P1", SMLSIZE)
  if c.nPl == 2 then
    drawCar(97, 15, 2)
    lcd.drawText(101, 11, "P2", SMLSIZE)
    lcd.drawText(1, 46, "P1 R stk+SA P2 L stk", SMLSIZE)
    lcd.drawText(1, 55, "L up=gas mid=coast dn=brk", SMLSIZE)
  else
    lcd.drawText(1, 46, "R stk: steer, up=gas", SMLSIZE)
    lcd.drawText(1, 55, "down=brake   SA=start", SMLSIZE)
  end
  return false
end

-- results box over the track
function M.over(c, hum, raceT, fmt, ordinal, drawCar)
  lcd.drawFilledRectangle(4, 6, 120, 52, ERASE)
  lcd.drawRectangle(4, 6, 120, 52)
  if c.nPl == 1 then
    local h = hum[1]
    lcd.drawText(10, 9, ordinal(h.place or 4) .. " PLACE", MIDSIZE)
    local t = h.time or raceT
    lcd.drawText(10, 24, "Time " .. fmt(t) .. " rec " .. fmt(c.best or t), SMLSIZE)
    local lb = h.lapBest and fmt(h.lapBest) or "-"
    local rb = c.bestLap and fmt(c.bestLap) or "-"
    lcd.drawText(10, 33, "Lap " .. lb .. " rec " .. rb, SMLSIZE)
  else
    local w = "NO WINNER"
    local a, b = hum[1], hum[2]
    if a and b then
      if not a.dnf and (b.dnf or a.place < b.place) then w = "P1 WINS!"
      elseif not b.dnf then w = "P2 WINS!" end
    end
    lcd.drawText(10, 9, w, MIDSIZE)
    for k, h in ipairs(hum) do
      local y = 16 + 9 * k
      drawCar(12, y + 3, k)
      local s = "P" .. k .. " DNF"
      if not h.dnf then
        s = "P" .. k .. " " .. ordinal(h.place or 1) .. " " .. fmt(h.time or raceT)
      end
      if h.lapBest then s = s .. " lap " .. fmt(h.lapBest) end
      lcd.drawText(17, y, s, SMLSIZE)
    end
  end
  lcd.drawText(10, 46, "ENTER=retry SA=menu", SMLSIZE)
end

return M
