-- toolName = TNS|Racer|TNE
---------------------------------------------------------------
-- Micro racer for 128x64 B&W EdgeTX radios (TX12)
-- 1 player vs 3 AI, or 2 players (+ optional AI), 3 or 5 laps.
-- P1: right stick (ail steer, ele up gas / down brake) + SA
-- P2: left stick (rud steer, thr up gas / down brake) + SD
-- A lap counts only after passing every checkpoint in order.
-- Exit: RTN / EXIT
---------------------------------------------------------------

local HW = 6          -- half track width (px)
local VMAX = 34       -- top speed on track (px/s)
local VOFF = 11       -- top speed off track
local NG = 8          -- checkpoints per lap (gate 1 = finish line)
local GW = 12         -- checkpoint half width (px)

local wx, wy, ux, uy, len, cum, fac, ax, ay, bx, by, tx, ty, gw, gc
local N, L
local state, timer, raceT, lastTime, ui
local hum, ai, order, lastFinish
-- settings + records, shared with RACER/ui.lua
local cfg = { nPl = 1, nAI = 2, laps = 3, cur = 1, flick = true }

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

local function loadMod(name)
  local chunk = loadScript("/SCRIPTS/GAMES/RACER/" .. name .. ".lua")
  if not chunk then error("copy folder GAMES/RACER to the SD card") end
  return chunk()
end

local function buildTrack()
  local T = loadMod("track")(HW, NG)
  wx, wy, ux, uy, len, cum, fac = T.wx, T.wy, T.ux, T.uy, T.len, T.cum, T.fac
  ax, ay, bx, by, tx, ty, gw, gc = T.ax, T.ay, T.bx, T.by, T.tx, T.ty, T.gw, T.gc
  N, L = T.N, T.L
end

-- put car c at arc position c.s, sideways offset c.off
local function placeAt(c)
  local sm = c.s % L
  local seg = c.seg
  for _ = 1, N do
    if sm >= cum[seg] and sm < cum[seg] + len[seg] then break end
    seg = seg % N + 1
  end
  c.seg = seg
  local t = sm - cum[seg]
  c.x = wx[seg] + ux[seg] * t - uy[seg] * c.off
  c.y = wy[seg] + uy[seg] * t + ux[seg] * c.off
end

-- grid slots 1..4 behind the line, two abreast
local function slot(k, c)
  c.s = -7 - 8 * math.floor((k - 1) / 2)
  c.off = (k % 2 == 1) and 3 or -3
  c.seg = 1
  placeAt(c)
  return c
end

local function reset()
  ai, hum = {}, {}
  local na = cfg.nAI
  if cfg.nPl == 1 then na = 3 end
  for k = 1, na do
    local sl = k
    if cfg.nPl == 1 and k == 3 then sl = 4 end
    local c = slot(sl, { done = false })
    c.mul = 0.80 + 0.055 * (k + 3 - na)
    c.base = c.mul
    ai[k] = c
  end
  for k = 1, cfg.nPl do
    hum[k] = slot(2 + k, { id = k, a = math.pi, v = 0, lap = -1, nx = 1,
      lapStart = 0, wrong = 0, done = false })
  end
  raceT, order, lastFinish = 0, 0, nil
  if RACER_TEST then RACER_TEST.h, RACER_TEST.ai = hum, ai end
end

local function init()
  math.randomseed(getTime())
  buildTrack()
  state = "menu"
  lastTime = getTime()
  reset()
end

-- nearest centreline segment to (x, y): seg, t (0..1), squared distance
local function nearest(x, y, i0, full)
  local bd, bi, bt = 1e9, i0, 0
  local k0, k1 = i0 - 2, i0 + 2
  if full then k0, k1 = 1, N end
  for k = k0, k1 do
    local i = (k - 1) % N + 1
    local t = ((x - wx[i]) * ux[i] + (y - wy[i]) * uy[i]) / len[i]
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local dx = x - (wx[i] + ux[i] * len[i] * t)
    local dy = y - (wy[i] + uy[i] * len[i] * t)
    local d = dx * dx + dy * dy
    if d < bd then bd, bi, bt = d, i, t end
  end
  return bi, bt, bd
end

local function fmt(t)
  local d = math.floor(t * 10 + 0.5)
  return string.format("%d.%d", math.floor(d / 10), d % 10)
end

-- position of (x, y) relative to checkpoint g: along track, sideways
local function gateRel(g, x, y)
  local i = gw[g] or 1
  local dx, dy = x - wx[i], y - wy[i]
  return dx * tx[i] + dy * ty[i], dy * tx[i] - dx * ty[i]
end

local function finishCar(c)
  c.done = true
  order = order + 1
  c.place = order
  c.time = raceT
  lastFinish = raceT
end

-- checkpoint logic: only the next gate (forward) or the last one
-- passed (backward) can change progress; gate 1 is the finish line
local function gates(h, ox, oy)
  local g = h.nx
  local a0 = gateRel(g, ox, oy)
  local a1, lat = gateRel(g, h.x, h.y)
  if a0 < 0 and a1 >= 0 and math.abs(lat) <= GW then
    h.nx = g % NG + 1
    if g == 1 then
      h.lap = h.lap + 1
      if h.lap >= 1 then
        local lt = raceT - h.lapStart
        if not h.lapBest or lt < h.lapBest then h.lapBest = lt end
        playTone(1800, 80, 0, PLAY_NOW)
      end
      h.lapStart = raceT
      if h.lap >= cfg.laps and not h.done then finishCar(h) end
    end
    return
  end
  local p = g - 1
  if p < 1 then p = NG end
  a0 = gateRel(p, ox, oy)
  a1, lat = gateRel(p, h.x, h.y)
  if a0 >= 0 and a1 < 0 and math.abs(lat) <= GW then
    h.nx = p
    if p == 1 then h.lap = h.lap - 1 end
  end
end

local function stickInput(h)
  local st, gas, brk
  if h.id == 2 then
    st = getValue("rud")
    local t = getValue("thr")
    gas = (t - 100) / 800
    brk = t < -600
  else
    st = getValue("ail")
    local e = getValue("ele")
    gas = (e - 300) / 600
    brk = e < -300
    if cfg.nPl == 1 then
      local r = getValue("rud")
      if math.abs(r) > math.abs(st) then st = r end
      local t = (getValue("thr") + 1024) / 2048
      if t > gas then gas = t end
    end
  end
  if math.abs(st) < 80 then st = 0 end
  if gas < 0.05 then gas = 0 elseif gas > 1 then gas = 1 end
  return st, gas, brk
end

local function bump(h, c, dt)
  local dx, dy = h.x - c.x, h.y - c.y
  local dd = dx * dx + dy * dy
  if dd < 12 and dd > 0.01 then
    local s = math.sqrt(dd)
    h.x = h.x + dx / s * (3.5 - s) * 0.5
    h.y = h.y + dy / s * (3.5 - s) * 0.5
    h.v = h.v * (1 - math.min(1, 3 * dt))
  end
end

local function updateHuman(h, dt)
  local st, gas, brk = stickInput(h)
  local grip = math.min(1, math.abs(h.v) / 12)
  if h.v < 0 then grip = -grip end
  h.a = h.a + st / 1024 * 3.4 * grip * dt
  h.v = h.v + 48 * gas * dt - h.v * 0.6 * dt
  if brk then
    h.v = h.v - 60 * dt
    if h.v < -10 then h.v = -10 end
  end

  local seg, t, d = nearest(h.x, h.y, h.seg, false)
  if d > 64 then seg, t, d = nearest(h.x, h.y, h.seg, true) end
  h.seg = seg
  local cap = VMAX
  if d > (HW + 1) * (HW + 1) then cap = VOFF end
  if h.v > cap then h.v = h.v - (h.v - cap) * math.min(1, 5 * dt) end

  local ox, oy = h.x, h.y
  h.x = h.x + math.cos(h.a) * h.v * dt
  h.y = h.y + math.sin(h.a) * h.v * dt
  if h.x < 2 then h.x, h.v = 2, h.v * 0.5 end
  if h.x > LCD_W - 3 then h.x, h.v = LCD_W - 3, h.v * 0.5 end
  if h.y < 2 then h.y, h.v = 2, h.v * 0.5 end
  if h.y > LCD_H - 3 then h.y, h.v = LCD_H - 3, h.v * 0.5 end
  for _, c in ipairs(ai) do bump(h, c, dt) end
  for _, o in ipairs(hum) do
    if o ~= h then bump(h, o, dt) end
  end

  if not h.done then gates(h, ox, oy) end

  -- wrong way: moving against the track direction
  local fw = (h.x - ox) * ux[seg] + (h.y - oy) * uy[seg]
  if fw < -2 * dt then h.wrong = h.wrong + dt
  elseif fw > 0 then h.wrong = 0 end

  -- progress for positions: laps, last gate passed, distance past it
  local lg = h.nx - 1
  if lg < 1 then lg = NG end
  local gap = (gc[h.nx] - gc[lg]) % L
  local along = (cum[seg] + t * len[seg] - gc[lg]) % L
  if along > (gap + L) / 2 then along = 0 elseif along > gap then along = gap end
  if not h.done then h.s = h.lap * L + gc[lg] + along end
end

local function position(h)
  if h.done then return h.place end
  local p = 1
  for _, c in ipairs(ai) do
    if c.done or c.s > h.s then p = p + 1 end
  end
  for _, c in ipairs(hum) do
    if c ~= h and (c.done or c.s > h.s) then p = p + 1 end
  end
  return p
end

local function finishRace()
  for _, h in ipairs(hum) do
    if not h.done then
      order = order + 1
      h.place, h.dnf = order, true
    end
    if h.lapBest and (not cfg.bestLap or h.lapBest < cfg.bestLap) then cfg.bestLap = h.lapBest end
  end
  local h = hum[1]
  if cfg.nPl == 1 and not h.dnf and (not cfg.best or h.time < cfg.best) then cfg.best = h.time end
  state = "over"
  local win = false
  for _, x in ipairs(hum) do
    if x.place == 1 then win = true end
  end
  playTone(win and 2400 or 900, 400, 0, PLAY_NOW)
end

local function update(dt)
  raceT = raceT + dt
  for _, c in ipairs(ai) do
    c.mul = c.mul + (math.random() - 0.5) * 0.1 * dt
    if c.mul < c.base - 0.04 then c.mul = c.base - 0.04 end
    if c.mul > c.base + 0.04 then c.mul = c.base + 0.04 end
    local f = fac[c.seg] or 1
    c.s = c.s + VMAX * c.mul * f * dt
    if not c.done and c.s >= cfg.laps * L then finishCar(c) end
    placeAt(c)
  end
  for _, h in ipairs(hum) do updateHuman(h, dt) end
  local allH, anyH, allAI = true, false, true
  for _, h in ipairs(hum) do
    if h.done then anyH = true else allH = false end
  end
  for _, c in ipairs(ai) do
    if not c.done then allAI = false end
  end
  if allH then finishRace()
  elseif lastFinish and (allAI or anyH) and raceT - lastFinish > 20 then
    finishRace()
  end
end

-- P1 filled box, P2 an X, AI outline box; humans get a nose dot
local function drawCar(x, y, kind, a)
  local cx, cy = math.floor(x + 0.5), math.floor(y + 0.5)
  if cx < 1 or cx > LCD_W - 2 or cy < 1 or cy > LCD_H - 2 then return end
  if kind == 1 then
    lcd.drawFilledRectangle(cx - 1, cy - 1, 3, 3, FORCE)
  elseif kind == 2 then
    lcd.drawPoint(cx, cy)
    lcd.drawPoint(cx - 1, cy - 1)
    lcd.drawPoint(cx + 1, cy - 1)
    lcd.drawPoint(cx - 1, cy + 1)
    lcd.drawPoint(cx + 1, cy + 1)
  else
    lcd.drawRectangle(cx - 1, cy - 1, 3, 3)
  end
  if a then
    local nx = math.floor(x + math.cos(a) * 2.6 + 0.5)
    local ny = math.floor(y + math.sin(a) * 2.6 + 0.5)
    if nx >= 0 and nx < LCD_W and ny >= 0 and ny < LCD_H then
      lcd.drawPoint(nx, ny)
    end
  end
end

local function ordinal(p)
  if p == 1 then return "1st" elseif p == 2 then return "2nd"
  elseif p == 3 then return "3rd" end
  return p .. "th"
end

local function lapText(h)
  local lap = h.lap + 1
  if lap < 1 then lap = 1 end
  if lap > cfg.laps then lap = cfg.laps end
  return lap .. "/" .. cfg.laps
end

local function draw()
  lcd.clear()
  for i = 1, N do
    local j = i % N + 1
    lcd.drawLine(ax[i], ay[i], ax[j], ay[j], SOLID, FORCE)
    lcd.drawLine(bx[i], by[i], bx[j], by[j], SOLID, FORCE)
  end
  lcd.drawLine(ax[1], ay[1], bx[1], by[1], DOTTED, FORCE)
  -- next checkpoint of each racing human, dotted
  for _, h in ipairs(hum) do
    local i = gw[h.nx]
    if i and h.nx > 1 and not h.done then
      lcd.drawLine(ax[i], ay[i], bx[i], by[i], DOTTED, FORCE)
    end
  end
  for _, c in ipairs(ai) do drawCar(c.x, c.y, 0) end
  for _, h in ipairs(hum) do drawCar(h.x, h.y, h.id, h.a) end
  local blink = math.floor(getTime() / 25) % 2 == 0
  if cfg.nPl == 1 then
    local h = hum[1]
    if h.wrong > 0.4 and not h.done then
      if blink then lcd.drawText(40, 28, "WRONG WAY", SMLSIZE + INVERS) end
    else
      lcd.drawText(40, 28, "LAP " .. lapText(h), SMLSIZE)
    end
    lcd.drawText(40, 37, "P" .. position(h) .. "  " .. fmt(raceT), SMLSIZE)
  else
    for k, h in ipairs(hum) do
      local y = 18 + 8 * k
      drawCar(38, y + 3, k)
      if h.wrong > 0.4 and not h.done then
        if blink then lcd.drawText(42, y, "WRONG WAY", SMLSIZE + INVERS) end
      elseif h.done then
        lcd.drawText(42, y, "DONE " .. ordinal(h.place), SMLSIZE)
      else
        lcd.drawText(42, y, "L" .. lapText(h) .. " " .. ordinal(position(h)), SMLSIZE)
      end
    end
    lcd.drawText(42, 42, fmt(raceT), SMLSIZE)
  end
end

-- menu/results screens live in RACER/ui.lua, loaded only when needed
local function getUI()
  if not ui then ui = loadMod("ui") end
  return ui
end

local function startRace()
  reset()
  ui = nil -- drop the menu module while racing
  state = "count"
  timer = 3
  playTone(800, 120, 0, PLAY_NOW)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local sw = switchPress()

  if state == "menu" then
    if getUI().menu(cfg, event, sw, drawCar) then
      startRace()
    end
  elseif state == "count" then
    local before = math.ceil(timer)
    timer = timer - dt
    draw()
    if timer > 0 then
      lcd.drawText(92, 29, tostring(math.ceil(timer)), MIDSIZE + INVERS)
      if math.ceil(timer) ~= before then playTone(800, 120, 0, PLAY_NOW) end
    else
      state = "play"
      raceT = 0
      playTone(1600, 300, 0, PLAY_NOW)
    end
  elseif state == "play" then
    update(dt)
    draw()
    if raceT < 1 then lcd.drawText(88, 29, "GO!", MIDSIZE + INVERS) end
  else
    draw()
    getUI().over(cfg, hum, raceT, fmt, ordinal, drawCar)
    if event == EVT_VIRTUAL_ENTER then startRace()
    elseif sw then state = "menu" end
  end
  return 0
end

return { init = init, run = run }
