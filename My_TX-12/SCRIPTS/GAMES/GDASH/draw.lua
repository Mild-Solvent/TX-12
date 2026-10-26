-- Geometry Dash drawing, loaded with phys.lua only while playing:
--   draw = loadScript(this)()(tile, endX, rows)
--   draw(P, deadT or nil, still, hudLeft, pct, attempt)
-- Shapes are strings of 8 lines "x1y1x2y2" (digits): tiles on their 8x8 cell,
-- icons on a 7x7 grid (scaled for mini, flipped upside down with gravity).
-- Levels taller than 6 rows scroll: world y + oy = screen y.
local GY, PX = 58, 28
-- tile shapes in the order of TS: orbs, pads, teleport exit, spikes, slopes
local TS = "oirqebahpkfuwt^v/`()[]"
local SH = "11616166661616113333333333333333" .. "22525255552525222522252225222522"
  .. "11616166661616113343344434443444" .. "22522353245425552555255525552555"
  .. "11616166661616112255255225522552" .. "11611262136314641565166616661666"
  .. "11616166661616112353425344534453" .. "11616166661616112353425344532224"
  .. "16661767176717671767176717671767" .. "27572757275727572757275727572757"
  .. "15651666176717671767176717671767" .. "15651767151765676567656765676567"
  .. "17672537554755475547554755475547" .. "10176067334333433343334333433343"
  .. "07313167175717571757175717571757" .. "00363660105010501050105010501050"
  .. "07707077077707700770077007700770" .. "00770007077700770077007700770077"
  .. "07747477077707740774077407740774" .. "03700307707707770370037003700370"
  .. "00730007737707770073007300730073" .. "04770407077704770477047704770477"
-- icons, two animation frames per mode: cube ufo ship ball wave robot spider swing
local IC = "00606066660606002242234324442444" .. "30636336360303302343323432343234"
  .. "03636366660606032040202340434043" .. "03636366660606032040202340434043"
  .. "06660206026510201121112111211121" .. "06660206026510201121112111211121"
  .. "20404063634646262603032011551155" .. "20404063634646262603032015511551"
  .. "03606036360336033603360336033603" .. "03606036360336033603360336033603"
  .. "10505053531313103141241644564456" .. "10505053531313103141242644464446"
  .. "10501151125212062326434652665266" .. "10501151125212062326434652665266"
  .. "00600666303234362242234324442444" .. "00600666303234362242234324442444"
  .. "00663036066003636666000030366006"   -- explosion (drawn scaled)

return function(tile, endX, N)
local TX, TY = {}, {}  -- wave trails: world points, 1-8 main icon, 9-16 dual icon
N = N or 6
local cam, oy, lx = 0, 0, 0

local function shape(S, i, x, y, k, fl)
  for j = i, i + 28, 4 do
    local a, b, c, d = string.byte(S, j, j + 3)
    a, b = math.floor((a - 48) * k + 0.5), math.floor((b - 48) * k + 0.5)
    c, d = math.floor((c - 48) * k + 0.5), math.floor((d - 48) * k + 0.5)
    if fl then b, d = fl - b, fl - d end
    lcd.drawLine(x + a, y + b, x + c, y + d, SOLID, FORCE)
  end
end

-- one icon (o = 0 main, 8 dual); the wave leaves a short zig-zag trail
local function icon(P, y, g, vy, gr, still, o)
  local m, s, f = P.m, 7, 0
  if P.mi then s = 5 end
  local fl = nil
  if g < 0 then fl = s - 1 end
  y = math.floor(y)
  if m == 4 then
    for i = o + 8, o + 2, -1 do TX[i], TY[i] = TX[i - 1], TY[i - 1] end
    TX[o + 1], TY[o + 1] = P.x, y + math.floor(s / 2)
    for i = o + 1, o + 7 do
      if TX[i + 1] and TX[i + 1] - cam >= 0 then
        lcd.drawLine(math.floor(TX[i] - cam), TY[i] + oy, math.floor(TX[i + 1] - cam), TY[i + 1] + oy, SOLID, FORCE)
      end
    end
    fl = nil
    if vy > 0 then fl = s - 1 end
  else
    for i = o + 1, o + 8 do TX[i] = nil end
    if (m == 0 and not still and not gr) or m == 3 or m == 5 then f = math.floor(P.x / 12) % 2 end
  end
  shape(IC, (m * 2 + f) * 32 + 1, PX, y + oy, (s - 1) / 6, fl)
end

return function(P, deadT, still, left, pct, att)
  lcd.clear()
  cam = math.floor(P.x) - PX
  -- vertical camera: keep the icon between screen y 18 and 42, eased, snapped on restart
  local t = oy
  if P.y + t < 18 then t = 18 - P.y elseif P.y + t > 42 then t = 42 - P.y end
  if t > 8 * N - 48 then t = 8 * N - 48 end
  if t < 0 then t = 0 end
  if P.x < lx or P.y + oy < 10 or P.y + oy > 52 then oy = t
  else oy = oy + (t - oy) / 3 end
  oy = math.floor(oy + 0.5)
  lx = P.x
  local m, gy, cy = P.m, GY + oy, GY - 8 * N + oy
  if gy < LCD_H then
    lcd.drawLine(0, gy, LCD_W - 1, gy, SOLID, FORCE)
    local off = cam % 16
    for i = 0, 8 do
      local gx = i * 16 - off
      if gx >= 0 and gx + 3 < LCD_W then lcd.drawLine(gx, gy + 1, gx + 3, LCD_H - 1, SOLID, FORCE) end
    end
  end
  -- flying modes show the ceiling as a solid line, like the real game's bounds
  if cy > 9 then
    local pat = DOTTED
    if m == 1 or m == 2 or m == 4 or m == 7 then pat = SOLID end
    lcd.drawLine(0, cy - 1, LCD_W - 1, cy - 1, pat, FORCE)
  end
  local y0, y1 = cy, gy
  if y0 < 9 then y0 = 9 end
  if y1 > LCD_H then y1 = LCD_H end
  local c0 = math.floor(cam / 8)
  for c = c0, c0 + 16 do
    local sx = c * 8 - cam
    for r = 0, N - 1 do
      local top = gy - 8 * r - 8
      local t = 46
      if top > 1 and top < LCD_H then t = tile(c, r) end
      if t == 35 or t == 61 then
        local h, x0, x1 = 8, sx, sx + 8
        if t == 61 then h = 4 end
        if top + h > LCD_H then h = LCD_H - top end
        if x0 < 0 then x0 = 0 end
        if x1 > LCD_W then x1 = LCD_W end
        if x1 - x0 > 1 then lcd.drawRectangle(x0, top, x1 - x0, h) end
        if t == 35 and sx >= 0 and sx <= LCD_W - 8 then lcd.drawPoint(sx + 3, top + 3) end
      elseif t ~= 46 and sx >= 0 and sx <= LCD_W - 8 then
        local ch = string.char(t)
        local i = string.find(TS, ch, 1, true)
        if i then shape(SH, i * 32 - 31, sx, top, 1, nil)
        elseif string.find("CUSBWRXZGg01234mnDdT", ch, 1, true) then
          if y1 - y0 > 1 then lcd.drawRectangle(sx + 1, y0, 5, y1 - y0) end
          lcd.drawText(sx + 1, top + 1, ch, SMLSIZE)
        end
      end
    end
  end
  local ex = endX - cam
  if ex >= 0 and ex < LCD_W then lcd.drawLine(ex, y0, ex, y1 - 1, DOTTED, FORCE) end
  local ax = 40 - cam
  if ax > 0 and ax < LCD_W - 60 then lcd.drawText(ax, 24, "Attempt " .. att, SMLSIZE) end
  if deadT then
    local d = math.floor(deadT * 40) + 2
    if d > 13 then d = 13 end
    shape(IC, 513, PX + 3 - d, math.floor(P.y) + oy + 3 - d, d / 3, nil)
    if P.du then shape(IC, 513, PX + 3 - d, math.floor(P.y2) + oy + 3 - d, d / 3, nil) end
  else
    icon(P, P.y, P.g, P.vy, P.gr, still, 0)
    if P.du then icon(P, P.y2, P.g2, P.vy2, P.gr2, still, 8) end
  end
  -- scrolled tiles may reach into the HUD strip
  if N > 6 then lcd.drawFilledRectangle(0, 0, LCD_W, 9, ERASE) end
  lcd.drawText(1, 1, left, SMLSIZE)
  lcd.drawRectangle(32, 2, 62, 5)
  local w = math.floor(pct * 60 / 100)
  if w > 0 then lcd.drawFilledRectangle(33, 3, w, 3, FORCE) end
  lcd.drawText(LCD_W - 1, 1, pct .. "%", SMLSIZE + RIGHT)
end
end
