-- toolName = TNS|Rhythm|TNE
---------------------------------------------------------------
-- Osu!-style rhythm tapper for 128x64 B&W EdgeTX radios
--
-- Aim:   right stick moves the cursor (stick position = place)
-- Hit:   SA or SD, or ENTER, when the shrinking ring meets the
--        circle and the cursor is inside it
-- Perfect 300 / Good 100, x combo multiplier (+1 per 10 hits)
-- Health runs out or 4 misses in a row: game over
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local R = 6            -- circle radius
local RING = 20        -- approach ring start radius
local PERFECT = 0.09   -- s either side of the beat
local GOOD = 0.2
local MAXNOTES = 3

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, notes, score, best, combo, maxCombo, hits, health, missRow
local cx, cy, spawnT, lastX, lastY, lastTime
local fbKind, fbX, fbY, fbT

local function approach()
  return math.max(0.6, 1.2 - hits * 0.012)
end

local function reset()
  notes = {}
  score, combo, maxCombo, hits = 0, 0, 0, 0
  health, missRow = 100, 0
  cx, cy = LCD_W / 2, LCD_H / 2
  lastX, lastY = LCD_W / 2, LCD_H / 2
  spawnT = 0.6
  fbT = 0
end

local function init()
  math.randomseed(getTime())
  best = 0
  state = "title"
  lastTime = getTime()
  reset()
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

local function plot(x, y)
  if x >= 0 and x < LCD_W and y >= 0 and y < LCD_H then lcd.drawPoint(x, y) end
end

-- midpoint circle outline (no circle primitive on B&W radios)
local function circle(ox, oy, r)
  local x, y, d = r, 0, 1 - r
  while x >= y do
    plot(ox + x, oy + y); plot(ox - x, oy + y); plot(ox + x, oy - y); plot(ox - x, oy - y)
    plot(ox + y, oy + x); plot(ox - y, oy + x); plot(ox + y, oy - x); plot(ox - y, oy - x)
    y = y + 1
    if d < 0 then
      d = d + 2 * y + 1
    else
      x = x - 1
      d = d + 2 * (y - x) + 1
    end
  end
end

local function spawn()
  local x, y
  for try = 1, 8 do
    x = math.floor(lastX + math.random(-45, 45))
    y = math.floor(lastY + math.random(-25, 25))
    if x < R + 2 then x = R + 2 elseif x > LCD_W - R - 3 then x = LCD_W - R - 3 end
    if y < 10 + R then y = 10 + R elseif y > LCD_H - 5 - R then y = LCD_H - 5 - R end
    local ok = true
    for _, n in ipairs(notes) do
      local dx, dy = n.x - x, n.y - y
      if dx * dx + dy * dy < 400 then ok = false end
    end
    if ok and (x - lastX) * (x - lastX) + (y - lastY) * (y - lastY) >= 144 then break end
  end
  lastX, lastY = x, y
  local T = approach()
  notes[#notes + 1] = { x = x, y = y, t = T, T = T }
end

-- kind: 1 perfect, 2 good, 3 miss
local function judge(kind, x, y)
  fbKind, fbX, fbY, fbT = kind, x, y, 0.5
  if kind == 3 then
    combo = 0
    missRow = missRow + 1
    health = health - 15
    playTone(300, 120, 0, PLAY_NOW)
  else
    local mult = 1 + math.floor(combo / 10)
    if mult > 4 then mult = 4 end
    combo = combo + 1
    if combo > maxCombo then maxCombo = combo end
    hits = hits + 1
    missRow = 0
    if kind == 1 then
      score = score + 300 * mult
      health = health + 5
      playTone(1800, 40, 0, PLAY_NOW)
    else
      score = score + 100 * mult
      health = health + 2
      playTone(1200, 40, 0, PLAY_NOW)
    end
    if health > 100 then health = 100 end
  end
  if health <= 0 or missRow >= 4 then
    if health < 0 then health = 0 end
    if score > best then best = score end
    state = "over"
    playTone(200, 500, 0, PLAY_NOW)
  end
end

local function tap()
  local hit, ht
  for i, n in ipairs(notes) do
    local dx, dy = n.x - cx, n.y - cy
    if dx * dx + dy * dy <= (R + 3) * (R + 3) and (ht == nil or n.t < ht) then
      hit, ht = i, n.t
    end
  end
  if hit == nil then
    health = health - 3
    playTone(600, 20, 0, PLAY_NOW)
    if health <= 0 then judge(3, math.floor(cx), math.floor(cy)) end
    return
  end
  local n = notes[hit]
  local x, y = n.x, n.y
  removeAt(notes, hit)
  local a = math.abs(ht)
  if a <= PERFECT then
    judge(1, x, y)
  elseif a <= GOOD then
    judge(2, x, y)
  else
    judge(3, x, y)
  end
end

local function update(dt, press)
  -- cursor follows the right stick position, slightly smoothed
  local tx = LCD_W / 2 + getValue("ail") * 62 / 1024
  local ty = LCD_H / 2 - getValue("ele") * 30 / 1024
  local k = math.min(1, dt * 18)
  cx = cx + (tx - cx) * k
  cy = cy + (ty - cy) * k

  if fbT > 0 then fbT = fbT - dt end

  spawnT = spawnT - dt
  if spawnT <= 0 then
    if #notes < MAXNOTES then spawn() end
    spawnT = math.max(0.35, approach() * 0.65)
  end

  for _, n in ipairs(notes) do n.t = n.t - dt end
  local first = notes[1]
  if first and first.t < -GOOD then
    removeAt(notes, 1)
    judge(3, first.x, first.y)
    return
  end
  if press then tap() end
end

local function draw()
  lcd.clear()
  for i = #notes, 1, -1 do
    local n = notes[i]
    circle(n.x, n.y, R)
    circle(n.x, n.y, 1)
    if n.t > 0 then
      circle(n.x, n.y, math.floor(R + (RING - R) * n.t / n.T + 0.5))
    else
      circle(n.x, n.y, R + 1)
    end
  end
  local x, y = math.floor(cx + 0.5), math.floor(cy + 0.5)
  lcd.drawLine(x - 3, y, x - 1, y, SOLID, FORCE)
  lcd.drawLine(x + 1, y, x + 3, y, SOLID, FORCE)
  lcd.drawLine(x, y - 3, x, y - 1, SOLID, FORCE)
  lcd.drawLine(x, y + 1, x, y + 3, SOLID, FORCE)
  if fbT > 0 then
    local s, w = "MISS", 24
    if fbKind == 1 then s, w = "PERFECT", 42 elseif fbKind == 2 then s, w = "GOOD", 24 end
    local fx = fbX - w / 2
    if fx < 0 then fx = 0 elseif fx > LCD_W - w then fx = LCD_W - w end
    local fy = fbY - R - 9
    if fy < 9 then fy = fbY + R + 2 end
    lcd.drawText(math.floor(fx), math.floor(fy), s, SMLSIZE)
  end
  lcd.drawText(0, 0, "" .. score, SMLSIZE)
  lcd.drawText(LCD_W - 1, 0, combo .. "x", SMLSIZE + RIGHT)
  local w = math.floor(health * LCD_W / 100)
  if w > 0 then lcd.drawFilledRectangle(0, LCD_H - 2, w, 2) end
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
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 24, 6, "RHYTHM", MIDSIZE + INVERS)
    lcd.drawText(4, 24, "R-stick: aim cursor", SMLSIZE)
    lcd.drawText(4, 33, "SA/SD/ENTER: hit when", SMLSIZE)
    lcd.drawText(4, 42, "ring meets circle", SMLSIZE)
    circle(110, 14, 6)
    circle(110, 14, 10)
    if press then
      reset()
      state = "play"
    end
  elseif state == "play" then
    update(dt, press)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 8, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 40, 24, "Score " .. score, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 40, 32, "Best  " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 40, 40, "Max combo " .. maxCombo, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 40, 50, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "title"
    end
  end
  return 0
end

return { init = init, run = run }
