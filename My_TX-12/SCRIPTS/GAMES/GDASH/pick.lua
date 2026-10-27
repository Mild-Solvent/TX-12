-- Geometry Dash level picker, loaded only while the picker is shown (dropped while playing).
--   nlev, pick = loadScript(this)()(best, tries)  counts the levels, reads gdash.dat into best/tries
--   lv, prac, ip = pick(event, lv, prac, msg, ip) draws one frame (ip: 0 SA/SD, 1 THR stick)
local stx, sty, str, hl, nm, df, ip = 0, 0, 0, -1, "", "", 0

return function(best, tries)
-- levels are counted on the card: L1, L2, ... until one is missing (max 99)
local n = 0
for i = 1, 99 do
  local ok, f = pcall(io.open, "/SCRIPTS/GAMES/GDASH/L" .. i .. ".lua", "r")
  if not ok or not f then break end
  pcall(io.close, f)
  n, best[i], tries[i] = i, 0, 0
end
local ok, f = pcall(io.open, "/SCRIPTS/GAMES/gdash.dat", "r")
if ok and f then
  local ok2, s = pcall(io.read, f, 1200)
  pcall(io.close, f)
  if ok2 and type(s) == "string" then
    -- "v2" first line = saved since the long levels came in; an older file's
    -- L1-L8 results belong to the old short levels, so they start again from 0
    local i, o = 0, string.sub(s, 1, 3) ~= "v2\n"
    for b, a in string.gmatch(s, "(%d+) (%d+)") do
      i = i + 1
      if i <= n and not (o and i <= 8) then best[i] = tonumber(b) or 0; tries[i] = tonumber(a) or 0 end
    end
    ip = tonumber(string.match(s, "\ni(%d)")) or 0
  end
end

return n, function(event, lv, prac, msg, ip)
  local ax, ay, az = getValue("ail"), getValue("ele"), getValue("rud")
  local mv = 0
  if event == EVT_VIRTUAL_NEXT then mv = 1 elseif event == EVT_VIRTUAL_PREV then mv = -1 end
  if stx == 0 and ax > 600 then mv, stx = 1, 1 elseif stx == 0 and ax < -600 then mv, stx = -1, 1
  elseif ax > -300 and ax < 300 then stx = 0 end
  if sty == 0 and (ay > 600 or ay < -600) then prac, sty = not prac, 1
  elseif ay > -300 and ay < 300 then sty = 0 end
  lcd.clear()
  lcd.drawText(1, 0, "GEOMETRY DASH", SMLSIZE + INVERS)
  if n == 0 or msg then
    lcd.drawText(2, 20, msg or "No levels found in", SMLSIZE)
    if not msg then lcd.drawText(2, 30, "/SCRIPTS/GAMES/GDASH/", SMLSIZE) end
    return lv, prac, ip
  end
  lv = lv + mv
  if lv < 1 then lv = n elseif lv > n then lv = 1 end
  -- name and difficulty: first line of the level file, "-- @Name|Difficulty"
  if hl ~= lv then
    hl, nm, df = lv, "Level " .. lv, "?"
    local ok, f = pcall(io.open, "/SCRIPTS/GAMES/GDASH/L" .. lv .. ".lua", "r")
    if ok and f then
      local ok2, s = pcall(io.read, f, 80)
      pcall(io.close, f)
      local a, d = string.match(ok2 and type(s) == "string" and s or "", "^%-%- @([^|%c]*)|([^%c]*)")
      if a and a ~= "" then nm = a end
      if d and d ~= "" then df = d end
    end
  end
  local b = best[lv] or 0
  lcd.drawText(LCD_W - 1, 0, "<" .. lv .. "/" .. n .. ">", SMLSIZE + RIGHT)
  lcd.drawText(2, 10, nm, MIDSIZE)
  lcd.drawText(2, 24, df, SMLSIZE)
  if b >= 100 then lcd.drawText(LCD_W - 1, 24, "COMPLETE", SMLSIZE + INVERS + RIGHT) end
  lcd.drawText(2, 33, "Best " .. b .. "%", SMLSIZE)
  lcd.drawText(LCD_W - 1, 33, "Tries " .. (tries[lv] or 0), SMLSIZE + RIGHT)
  lcd.drawRectangle(2, 42, 124, 4)
  if b > 0 then lcd.drawFilledRectangle(3, 43, math.floor(b * 122 / 100), 2, FORCE) end
  if prac then lcd.drawText(2, 48, "PRACTICE (stick up/dn)", SMLSIZE)
  else lcd.drawText(2, 48, "NORMAL (stick up/dn)", SMLSIZE) end
  lcd.drawText(2, 56, "L stick up or SA/SD", SMLSIZE)
  return lv, prac, ip
end, ip
end
