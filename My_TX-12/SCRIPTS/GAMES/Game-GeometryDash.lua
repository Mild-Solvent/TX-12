-- toolName = TNS|Geometry Dash|TNE
---------------------------------------------------------------
-- Geometry Dash for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
-- Hand-made levels in /SCRIPTS/GAMES/GDASH/L<n>.lua, best % and
-- attempts saved in /SCRIPTS/GAMES/gdash.dat.
--
-- Picker: wheel or right stick left/right = level,
--         stick up/down = normal / practice, ENTER/SA/SD = play
-- Jump:   SA or SD or ENTER. Orbs: press while touching one.
-- Each level has its own looping tune (beeper), restarts every attempt.
-- Practice: wheel = place checkpoint, wheel back = remove one
-- RTN:    back to picker, RTN in picker = quit
---------------------------------------------------------------

local DIR = "/SCRIPTS/GAMES/GDASH/L"
local SAVE = "/SCRIPTS/GAMES/gdash.dat"
local NLEV = 8
local INFO = "First Step|Easy|Back Beat|Easy|Pad Jumper|Normal|Orbit|Normal|"
  .. "Flip Side|Hard|Saucer|Harder|Overdrive|Insane|Dash Demon|Demon|"

local GY, CY, S, PX = 58, 10, 7, 28 -- ground y, ceiling y, cube size, screen x

local rows, len, endX, tile, step, music, mt
local best, tries = {}, {}
local state, lv, prac, P, acc, pend, lastTime, deadT, cps
local stx, sty = 0, 0

local function info(i)
  local k = 0
  for n, d in string.gmatch(INFO, "([^|]*)|([^|]*)|") do
    k = k + 1
    if k == i then return n, d end
  end
  return "?", "?"
end

local function loadSave()
  for i = 1, NLEV do best[i] = 0; tries[i] = 0 end
  local ok, f = pcall(io.open, SAVE, "r")
  if ok and f then
    local ok2, s = pcall(io.read, f, 256)
    pcall(io.close, f)
    if ok2 and type(s) == "string" then
      local i = 0
      for b, a in string.gmatch(s, "(%d+) (%d+)") do
        i = i + 1
        if i <= NLEV then best[i] = tonumber(b) or 0; tries[i] = tonumber(a) or 0 end
      end
    end
  end
end

local function save()
  local s = ""
  for i = 1, NLEV do s = s .. (best[i] or 0) .. " " .. (tries[i] or 0) .. "\n" end
  local ok, f = pcall(io.open, SAVE, "w")
  if ok and f then
    pcall(io.write, f, s)
    pcall(io.close, f)
  end
end

local function loadLevel(i)
  rows = nil
  collectgarbage()
  local chunk = loadScript(DIR .. i .. ".lua")
  rows = chunk and chunk()
  if type(rows) ~= "table" then rows = { "" } end
  len = 0
  for r = 1, 6 do
    local s = rows[r]
    if s and #s > len then len = #s end
  end
  endX = len * 8 + 16
  local mk = loadScript("/SCRIPTS/GAMES/GDASH/phys.lua")
  mk = mk and mk()
  if mk then tile, step, music = mk(rows, endX) end
end

local function rowTop(r) return GY - 8 * r - 8 end

local function newPlayer()
  return { x = 0, y = GY - S, vy = 0, g = 1, ufo = false, spd = 90, buf = 0,
           gr = true, orb = -1, pad = -1, dead = false, won = false, ang = 0 }
end

local function copy(a, b)
  for k, v in pairs(a) do b[k] = v end
  return b
end

local function pct()
  local v = math.floor(P.x * 100 / endX)
  if v > 100 then v = 100 elseif v < 0 then v = 0 end
  return v
end

local function startRun()
  if prac and cps[1] then copy(cps[#cps], P) else copy(newPlayer(), P) end
  acc, pend, mt = 0, false, 0
  if music then music(-1) end
  state = "play"
end

local function init()
  loadSave()
  state, lv, prac = "pick", 1, false
  P, cps = newPlayer(), {}
  lastTime = getTime()
end

-- true once per press of switch SA or SD (buttons or toggles)
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

local function die()
  state, deadT = "dead", 0
  playTone(250, 300, 0, PLAY_NOW)
  tries[lv] = (tries[lv] or 0) + 1
  if not prac and pct() > (best[lv] or 0) then
    best[lv] = pct()
    save()
  end
end

local function drawTile(t, sx, r)
  local top = rowTop(r)
  local b = top + 8
  if t == 35 or t == 61 then
    local h = 8
    if t == 61 then h = 4 end
    local x0, x1 = sx, sx + 8
    if x0 < 0 then x0 = 0 end
    if x1 > LCD_W then x1 = LCD_W end
    if x1 - x0 > 1 then lcd.drawRectangle(x0, top, x1 - x0, h) end
    if t == 35 and sx >= 0 and sx <= LCD_W - 8 then lcd.drawPoint(sx + 3, top + 3) end
  elseif sx < 0 or sx > LCD_W - 8 then
    return
  elseif t == 94 then
    lcd.drawLine(sx, b - 1, sx + 3, b - 7, SOLID, FORCE)
    lcd.drawLine(sx + 3, b - 7, sx + 6, b - 1, SOLID, FORCE)
    lcd.drawLine(sx + 1, b - 1, sx + 5, b - 1, SOLID, FORCE)
  elseif t == 118 then
    lcd.drawLine(sx, top, sx + 3, top + 6, SOLID, FORCE)
    lcd.drawLine(sx + 3, top + 6, sx + 6, top, SOLID, FORCE)
    lcd.drawLine(sx + 1, top, sx + 5, top, SOLID, FORCE)
  elseif t == 111 then
    lcd.drawRectangle(sx + 1, top + 1, 6, 6)
    lcd.drawPoint(sx + 3, top + 3)
  elseif t == 113 then
    lcd.drawFilledRectangle(sx + 2, top + 2, 4, 4, FORCE)
  elseif t == 112 then
    lcd.drawFilledRectangle(sx + 1, b - 2, 6, 2, FORCE)
  elseif t == 71 or t == 103 or t == 85 or t == 67 or (t >= 49 and t <= 52) then
    lcd.drawRectangle(sx + 1, CY, 5, GY - CY)
    lcd.drawText(sx + 1, top + 1, string.char(t), SMLSIZE)
  end
end

local function drawPlayer()
  local y = math.floor(P.y)
  if P.ufo then
    lcd.drawRectangle(PX, y + 3, S, 4)
    lcd.drawRectangle(PX + 2, y, 3, 4)
  elseif P.gr or state ~= "play" then
    lcd.drawRectangle(PX, y, S, S)
    lcd.drawFilledRectangle(PX + 2, y + 2, 3, 3, FORCE)
  else
    local c, s = math.cos(P.ang) * 4.5, math.sin(P.ang) * 4.5
    local cx, cy = PX + 3.5, P.y + 3.5
    local x1, y1 = math.floor(cx + c), math.floor(cy + s)
    local x2, y2 = math.floor(cx - s), math.floor(cy + c)
    local x3, y3 = math.floor(cx - c), math.floor(cy - s)
    local x4, y4 = math.floor(cx + s), math.floor(cy - c)
    lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
    lcd.drawLine(x2, y2, x3, y3, SOLID, FORCE)
    lcd.drawLine(x3, y3, x4, y4, SOLID, FORCE)
    lcd.drawLine(x4, y4, x1, y1, SOLID, FORCE)
  end
end

local function drawWorld()
  lcd.clear()
  local cam = math.floor(P.x) - PX
  lcd.drawLine(0, GY, LCD_W - 1, GY, SOLID, FORCE)
  lcd.drawLine(0, CY - 1, LCD_W - 1, CY - 1, DOTTED, FORCE)
  local off = cam % 16
  for i = 0, 8 do
    local gx = i * 16 - off
    if gx >= 0 and gx + 3 < LCD_W then lcd.drawLine(gx, GY + 1, gx + 3, LCD_H - 1, SOLID, FORCE) end
  end
  local c0 = math.floor(cam / 8)
  for c = c0, c0 + 16 do
    for r = 0, 5 do
      local t = tile(c, r)
      if t ~= 46 then drawTile(t, c * 8 - cam, r) end
    end
  end
  local ex = endX - cam
  if ex >= 0 and ex < LCD_W then lcd.drawLine(ex, CY, ex, GY - 1, DOTTED, FORCE) end
  local ax = 40 - cam
  if ax > 0 and ax < LCD_W - 60 then lcd.drawText(ax, 24, "Attempt " .. (tries[lv] or 0) + 1, SMLSIZE) end
  if state == "dead" then
    local cx, cy, d = PX + 3, math.floor(P.y) + 3, math.floor(deadT * 40) + 2
    if cy - d < 0 then d = cy end
    lcd.drawLine(cx - d, cy, cx + d, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - d, cx, cy + d, SOLID, FORCE)
    lcd.drawLine(cx - d, cy - d, cx + d, cy + d, SOLID, FORCE)
    lcd.drawLine(cx - d, cy + d, cx + d, cy - d, SOLID, FORCE)
  else
    drawPlayer()
  end
  -- HUD: mode, progress bar, percent
  if prac then lcd.drawText(1, 1, "PRAC" .. #cps, SMLSIZE) else lcd.drawText(1, 1, "A" .. (tries[lv] or 0) + 1, SMLSIZE) end
  lcd.drawRectangle(32, 2, 62, 5)
  local w = math.floor(pct() * 60 / 100)
  if w > 0 then lcd.drawFilledRectangle(33, 3, w, 3, FORCE) end
  lcd.drawText(LCD_W - 1, 1, pct() .. "%", SMLSIZE + RIGHT)
end

local function drawPick()
  lcd.clear()
  local n, d = info(lv)
  lcd.drawText(1, 0, "GEOMETRY DASH", SMLSIZE + INVERS)
  lcd.drawText(LCD_W - 1, 0, "<" .. lv .. "/" .. NLEV .. ">", SMLSIZE + RIGHT)
  lcd.drawText(2, 10, n, MIDSIZE)
  lcd.drawText(2, 24, d, SMLSIZE)
  if (best[lv] or 0) >= 100 then lcd.drawText(LCD_W - 1, 24, "COMPLETE", SMLSIZE + INVERS + RIGHT) end
  lcd.drawText(2, 33, "Best " .. (best[lv] or 0) .. "%", SMLSIZE)
  lcd.drawText(LCD_W - 1, 33, "Tries " .. (tries[lv] or 0), SMLSIZE + RIGHT)
  lcd.drawRectangle(2, 42, 124, 4)
  local w = math.floor((best[lv] or 0) * 122 / 100)
  if w > 0 then lcd.drawFilledRectangle(3, 43, w, 2, FORCE) end
  if prac then lcd.drawText(2, 48, "PRACTICE (stick up/dn)", SMLSIZE)
  else lcd.drawText(2, 48, "NORMAL (stick up/dn)", SMLSIZE) end
  lcd.drawText(2, 56, "ENTER/SA/SD play", SMLSIZE)
end

local function leavePlay()
  save()
  rows, tile, step, music = nil, nil, nil, nil
  collectgarbage()
  state = "pick"
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    if state == "pick" then save(); return 2 end
    leavePlay()
    return 0
  end
  local now = getTime()
  local ticks = now - lastTime
  lastTime = now
  if ticks > 8 then ticks = 8 elseif ticks < 0 then ticks = 0 end
  local jump = switchPress() or event == EVT_VIRTUAL_ENTER

  if state == "pick" then
    local ax, ay = getValue("ail"), getValue("ele")
    local mv = 0
    if event == EVT_VIRTUAL_NEXT then mv = 1 elseif event == EVT_VIRTUAL_PREV then mv = -1 end
    if stx == 0 and ax > 600 then mv, stx = 1, 1 elseif stx == 0 and ax < -600 then mv, stx = -1, 1
    elseif ax > -300 and ax < 300 then stx = 0 end
    if sty == 0 and (ay > 600 or ay < -600) then prac, sty = not prac, 1
    elseif ay > -300 and ay < 300 then sty = 0 end
    lv = lv + mv
    if lv < 1 then lv = NLEV elseif lv > NLEV then lv = 1 end
    drawPick()
    if jump then
      loadLevel(lv)
      cps = {}
      if step then startRun() end
    end
  elseif state == "play" then
    if prac and event == EVT_VIRTUAL_NEXT and P.gr and #cps < 30 then
      cps[#cps + 1] = copy(P, {})
    elseif prac and event == EVT_VIRTUAL_PREV and #cps > 0 then
      cps[#cps] = nil
    end
    pend = pend or jump
    acc = acc + ticks
    while acc >= 2 do
      acc = acc - 2
      step(P, pend)
      mt = mt + 0.02
      pend = false
      if P.dead then die(); break end
      if P.won then
        state = "win"
        tries[lv] = (tries[lv] or 0) + 1
        if not prac then best[lv] = 100 end
        save()
        playTone(2600, 300, 0, PLAY_NOW)
        break
      end
    end
    if state == "play" and music then music(mt) end
    drawWorld()
  elseif state == "dead" then
    deadT = deadT + ticks / 100
    drawWorld()
    if deadT > 0.8 then startRun() end
  else
    drawWorld()
    lcd.drawText(14, 16, "LEVEL COMPLETE!", MIDSIZE + INVERS)
    if prac then lcd.drawText(14, 32, "Practice run", SMLSIZE)
    else lcd.drawText(14, 32, "Attempts: " .. (tries[lv] or 0), SMLSIZE) end
    lcd.drawText(14, 42, "ENTER = levels", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then leavePlay() end
  end
  return 0
end

return { init = init, run = run,
  sim = { step = function(p, b) step(p, b) end, music = function(t) music(t) end, load = loadLevel, new = newPlayer, state = function() return state end } }
