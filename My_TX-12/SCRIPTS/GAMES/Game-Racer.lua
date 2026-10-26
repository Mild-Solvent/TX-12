-- toolName = TNS|Racer|TNE
---------------------------------------------------------------
-- Micro racer for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Steer:    right stick left/right (or rudder)
-- Throttle: left stick up (thr), or right stick up (ele)
-- Brake:    right stick down
-- 3 laps against 3 cars. Off the track you crawl.
-- Start: ENTER, SA or SD.  Exit: RTN / EXIT
---------------------------------------------------------------

local HW = 6          -- half track width (px)
local VMAX = 34       -- top speed on track (px/s)
local VOFF = 11       -- top speed off track
local LAPS = 3

local wx, wy, ux, uy, len, cum, fac, ax, ay, bx, by
local N, L
local state, timer, raceT, lastTime, best, bestLap
local plx, ply, pa, pv, pseg, plap, phalf, plocal, lapStart, lapBest
local place, lastFinish, ai

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

local function addPt(x, y)
  wx[#wx + 1] = x
  wy[#wy + 1] = y
end

-- stadium circuit, driven clockwise, with a chicane on the top straight
local function buildTrack()
  wx, wy = {}, {}
  addPt(64, 54) addPt(52, 54) addPt(40, 54) addPt(30, 54)
  for k = 1, 6 do
    local a = math.pi / 2 + k * math.pi / 6
    addPt(30 + 22 * math.cos(a), 32 + 22 * math.sin(a))
  end
  addPt(42, 10) addPt(50, 12) addPt(56, 17) addPt(64, 19)
  addPt(72, 17) addPt(78, 12) addPt(86, 10)
  for k = 0, 6 do
    local a = -math.pi / 2 + k * math.pi / 6
    addPt(98 + 22 * math.cos(a), 32 + 22 * math.sin(a))
  end
  addPt(88, 54) addPt(76, 54)
  N = #wx
  ux, uy, len, cum, fac = {}, {}, {}, {}, {}
  ax, ay, bx, by = {}, {}, {}, {}
  L = 0
  for i = 1, N do
    local j = i % N + 1
    local dx, dy = wx[j] - wx[i], wy[j] - wy[i]
    local d = math.sqrt(dx * dx + dy * dy)
    ux[i], uy[i], len[i], cum[i] = dx / d, dy / d, d, L
    L = L + d
  end
  for i = 1, N do
    local h = (i + N - 2) % N + 1
    local dx, dy = ux[h] + ux[i], uy[h] + uy[i]
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then d = 1 end
    local nx, ny = -dy / d, dx / d
    ax[i] = math.floor(wx[i] + nx * HW + 0.5)
    ay[i] = math.floor(wy[i] + ny * HW + 0.5)
    bx[i] = math.floor(wx[i] - nx * HW + 0.5)
    by[i] = math.floor(wy[i] - ny * HW + 0.5)
    -- AI slows for bends: compare this segment with the next
    local j = i % N + 1
    local dot = ux[i] * ux[j] + uy[i] * uy[j]
    fac[i] = math.max(0.7, 1 - (1 - dot) * 0.6)
  end
end

local function aiPlace(c)
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

local function reset()
  ai = {}
  for k = 1, 3 do
    local c = { s = -15, seg = 1, mul = 0.80 + 0.055 * k, off = -3, done = false }
    c.base = c.mul
    if k == 2 then c.s = -7 c.off = 3 end
    if k == 3 then c.s = -7 end
    aiPlace(c)
    ai[k] = c
  end
  -- player starts on the back row of the grid, behind the line
  plx, ply, pa, pv = 64 + 15, 54 - 3, math.pi, 0
  pseg, plap, phalf = N, -1, true
  plocal = L - 15
  lapStart, lapBest, raceT = 0, nil, 0
  place, lastFinish = 0, nil
end

local function init()
  math.randomseed(getTime())
  buildTrack()
  best, bestLap = nil, nil
  state = "title"
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

local function finishRace(p)
  place = p
  state = "over"
  if plap >= LAPS and (not best or raceT < best) then best = raceT end
  if lapBest and (not bestLap or lapBest < bestLap) then bestLap = lapBest end
  playTone(p == 1 and 2400 or 900, 400, 0, PLAY_NOW)
end

local function updatePlayer(dt)
  local st = getValue("ail")
  local rud = getValue("rud")
  if math.abs(rud) > math.abs(st) then st = rud end
  if math.abs(st) < 80 then st = 0 end
  local thr = (getValue("thr") + 1024) / 2048
  local ele = getValue("ele")
  if ele > 300 then thr = math.max(thr, math.min(1, (ele - 300) / 600)) end
  if thr < 0.05 then thr = 0 end

  local grip = math.min(1, math.abs(pv) / 12)
  if pv < 0 then grip = -grip end
  pa = pa + st / 1024 * 3.4 * grip * dt

  pv = pv + 48 * thr * dt - pv * 0.6 * dt
  if ele < -300 then
    pv = pv - 60 * dt
    if pv < -10 then pv = -10 end
  end

  local seg, t, d = nearest(plx, ply, pseg, false)
  if d > 64 then seg, t, d = nearest(plx, ply, pseg, true) end
  local cap = VMAX
  if d > (HW + 1) * (HW + 1) then cap = VOFF end
  if pv > cap then pv = pv - (pv - cap) * math.min(1, 5 * dt) end

  plx = plx + math.cos(pa) * pv * dt
  ply = ply + math.sin(pa) * pv * dt
  if plx < 2 then plx, pv = 2, pv * 0.5 end
  if plx > LCD_W - 3 then plx, pv = LCD_W - 3, pv * 0.5 end
  if ply < 2 then ply, pv = 2, pv * 0.5 end
  if ply > LCD_H - 3 then ply, pv = LCD_H - 3, pv * 0.5 end

  -- bump into other cars
  for _, c in ipairs(ai) do
    local dx, dy = plx - c.x, ply - c.y
    local dd = dx * dx + dy * dy
    if dd < 12 and dd > 0.01 then
      local s = math.sqrt(dd)
      plx = plx + dx / s * (3.5 - s) * 0.5
      ply = ply + dy / s * (3.5 - s) * 0.5
      pv = pv * (1 - math.min(1, 3 * dt))
    end
  end

  -- lap counting: crossing the line forward needs a visit to the far side
  pseg = seg
  local loc = cum[seg] + t * len[seg]
  if loc > L * 0.4 and loc < L * 0.6 then phalf = true end
  if plocal > L * 0.75 and loc < L * 0.25 then
    if phalf then
      plap = plap + 1
      phalf = false
      if plap >= 1 then
        local lt = raceT - lapStart
        if lt > 3 and (not lapBest or lt < lapBest) then lapBest = lt end
        playTone(1800, 80, 0, PLAY_NOW)
      end
      lapStart = raceT
    end
  elseif plocal < L * 0.25 and loc > L * 0.75 then
    plap = plap - 1
    phalf = true
  end
  plocal = loc
end

local function playerS()
  return plap * L + plocal
end

local function position()
  local p, ps = 1, playerS()
  for _, c in ipairs(ai) do
    if c.s > ps then p = p + 1 end
  end
  return p
end

local function update(dt)
  raceT = raceT + dt
  for _, c in ipairs(ai) do
    c.mul = c.mul + (math.random() - 0.5) * 0.1 * dt
    if c.mul < c.base - 0.04 then c.mul = c.base - 0.04 end
    if c.mul > c.base + 0.04 then c.mul = c.base + 0.04 end
    local f = fac[c.seg] or 1
    c.s = c.s + VMAX * c.mul * f * dt
    if not c.done and c.s >= LAPS * L then
      c.done = true
      lastFinish = raceT
    end
    aiPlace(c)
  end
  updatePlayer(dt)
  if plap >= LAPS then
    local p = 1
    for _, c in ipairs(ai) do
      if c.done then p = p + 1 end
    end
    finishRace(p)
  elseif lastFinish and raceT - lastFinish > 20 then
    local all = true
    for _, c in ipairs(ai) do
      if not c.done then all = false end
    end
    if all then finishRace(4) end
  end
end

local function drawCar(x, y, dx, dy, filled)
  local cx, cy = math.floor(x + 0.5), math.floor(y + 0.5)
  if cx < 1 or cx > LCD_W - 2 or cy < 1 or cy > LCD_H - 2 then return end
  if filled then
    lcd.drawFilledRectangle(cx - 1, cy - 1, 3, 3)
  else
    lcd.drawRectangle(cx - 1, cy - 1, 3, 3)
  end
  local nx = math.floor(x + dx * 2.6 + 0.5)
  local ny = math.floor(y + dy * 2.6 + 0.5)
  if nx >= 0 and nx < LCD_W and ny >= 0 and ny < LCD_H then
    lcd.drawPoint(nx, ny)
  end
end

local function draw()
  lcd.clear()
  for i = 1, N do
    local j = i % N + 1
    lcd.drawLine(ax[i], ay[i], ax[j], ay[j], SOLID, FORCE)
    lcd.drawLine(bx[i], by[i], bx[j], by[j], SOLID, FORCE)
  end
  lcd.drawLine(ax[1], ay[1], bx[1], by[1], DOTTED, FORCE)
  for _, c in ipairs(ai) do
    local s = c.seg
    drawCar(c.x, c.y, ux[s] or 0, uy[s] or 0, false)
  end
  drawCar(plx, ply, math.cos(pa), math.sin(pa), true)
  local lap = plap + 1
  if lap < 1 then lap = 1 end
  if lap > LAPS then lap = LAPS end
  lcd.drawText(40, 28, "LAP " .. lap .. "/" .. LAPS, SMLSIZE)
  lcd.drawText(40, 37, "P" .. position() .. "  " .. fmt(raceT), SMLSIZE)
end

local function ordinal(p)
  if p == 1 then return "1st" elseif p == 2 then return "2nd"
  elseif p == 3 then return "3rd" end
  return p .. "th"
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local press = (event == EVT_VIRTUAL_ENTER) or switchPress()

  if state == "title" then
    draw()
    lcd.drawText(36, 20, "RACER", MIDSIZE + INVERS)
    lcd.drawText(30, 33, "R stick steer", SMLSIZE)
    lcd.drawText(30, 41, "thr/ele gas", SMLSIZE)
    if press then
      reset()
      state = "count"
      timer = 3
      playTone(800, 120, 0, PLAY_NOW)
    end
  elseif state == "count" then
    local before = math.ceil(timer)
    timer = timer - dt
    draw()
    if timer > 0 then
      lcd.drawText(86, 29, tostring(math.ceil(timer)), MIDSIZE + INVERS)
      if math.ceil(timer) ~= before then playTone(800, 120, 0, PLAY_NOW) end
    else
      state = "play"
      raceT, lapStart = 0, 0
      playTone(1600, 300, 0, PLAY_NOW)
    end
  elseif state == "play" then
    update(dt)
    draw()
    if raceT < 1 then lcd.drawText(80, 29, "GO!", MIDSIZE + INVERS) end
  else
    draw()
    lcd.drawFilledRectangle(4, 6, 120, 52, ERASE)
    lcd.drawRectangle(4, 6, 120, 52)
    lcd.drawText(10, 9, ordinal(place) .. " PLACE", MIDSIZE)
    lcd.drawText(10, 24, "Time " .. fmt(raceT) .. " rec " .. fmt(best or raceT), SMLSIZE)
    local lb = lapBest and fmt(lapBest) or "-"
    local rb = bestLap and fmt(bestLap) or "-"
    lcd.drawText(10, 33, "Lap " .. lb .. " rec " .. rb, SMLSIZE)
    lcd.drawText(10, 46, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "count"
      timer = 3
      playTone(800, 120, 0, PLAY_NOW)
    end
  end
  return 0
end

return { init = init, run = run }
