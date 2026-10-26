-- toolName = TNS|Crossy Road|TNE
---------------------------------------------------------------
-- Crossy Road for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Hop:   flick right stick up / down / left / right
--        (let it return to centre before the next hop)
-- Roads: dodge the cars. Rivers: ride the logs, water kills.
-- Don't fall behind the screen. Score = furthest row.
-- Start: ENTER, SA or SD.  Exit: RTN / EXIT
---------------------------------------------------------------

local T = 8              -- tile size (px)
local COLS = 16
local LOOP = 160         -- lane objects wrap around a 160 px loop
local OFF = 16           -- loop x 0 is screen x -16
local KEEP = 10          -- rows generated above the camera

local state, lanes, lowRow, topRow, cam, camSpeed
local px, prow, score, best, lastTime, armed, hopT, lastKind

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

-- kind: 0 grass, 1 road, 2 river
local function newLane(r)
  local ln = { kind = 0, v = 0, objs = {}, trees = {} }
  local d = math.min(1, r / 120)
  if r > 2 then
    local p = math.random()
    if p < 0.28 or lastKind == 3 then
      ln.kind = 0
    elseif p < 0.66 then
      ln.kind = 1
    else
      ln.kind = 2
    end
  end
  local dir = (math.random(2) == 1) and 1 or -1
  if ln.kind == 0 then
    if r > 2 then
      for i = 1, math.random(0, 3) do
        local c = math.random(0, COLS - 1)
        if c ~= 7 and c ~= 8 then ln.trees[c] = true end
      end
    end
  elseif ln.kind == 1 then
    ln.v = dir * (13 + 22 * d + math.random(0, 9))
    local n = math.random(2, 3)
    local truck = math.random() < 0.35
    for i = 1, n do
      local w = truck and 15 or 8
      ln.objs[#ln.objs + 1] = { x = (i - 1) * LOOP / n + math.random(0, 12), w = w }
    end
  else
    ln.v = dir * (9 + 12 * d + math.random(0, 6))
    local n = 3
    for i = 1, n do
      local w = math.random(22, 32) - math.floor(8 * d)
      ln.objs[#ln.objs + 1] = { x = (i - 1) * LOOP / n + math.random(0, 6), w = w }
    end
  end
  -- never more than two rivers in a row, they get too hard
  if ln.kind == 2 and lastKind == 2 then lastKind = 3 else lastKind = ln.kind end
  return ln
end

local function reset()
  lanes = {}
  lastKind = 0
  lowRow, topRow = 0, -1
  cam, camSpeed = 0, 0
  prow, px = 0, 7 * T
  score = 0
  hopT = 0
end

local function init()
  math.randomseed(getTime())
  best = 0
  state = "title"
  armed = true
  lastTime = getTime()
  reset()
end

local function genLanes()
  local want = math.floor(cam) + KEEP
  while topRow < want do
    topRow = topRow + 1
    lanes[topRow] = newLane(topRow)
  end
  local low = math.floor(cam) - 2
  while lowRow < low do
    lanes[lowRow] = nil
    lowRow = lowRow + 1
  end
end

-- does screen interval [a, b) overlap lane object o (drawn twice for the wrap)?
local function overlaps(o, a, b)
  local sx = o.x - OFF
  if a < sx + o.w and b > sx then return true end
  sx = sx - LOOP
  return a < sx + o.w and b > sx
end

local function die()
  state = "over"
  if score > best then best = score end
  playTone(300, 300, 0, PLAY_NOW)
end

local function blocked(row, x)
  local ln = lanes[row]
  if not ln or ln.kind ~= 0 then return false end
  local c = math.floor((x + 4) / T)
  return ln.trees[c] == true
end

-- stick flick: returns dx, dy once per flick (dy +1 = forward)
local function readFlick()
  local ax, ay = getValue("ail"), getValue("ele")
  if math.abs(ax) < 300 and math.abs(ay) < 300 then
    armed = true
    return 0, 0
  end
  if not armed then return 0, 0 end
  if math.abs(ay) >= math.abs(ax) then
    if ay > 600 then armed = false return 0, 1 end
    if ay < -600 then armed = false return 0, -1 end
  else
    if ax > 600 then armed = false return 1, 0 end
    if ax < -600 then armed = false return -1, 0 end
  end
  return 0, 0
end

local function hop(dx, dy)
  local nrow = prow + dy
  if nrow < 0 then return end
  -- snap to the tile grid, then step
  local nx = math.floor((px + 4) / T) * T + dx * T
  if nx < 0 or nx > (COLS - 1) * T then return end
  if blocked(nrow, nx) then return end
  prow, px = nrow, nx
  hopT = 0.1
  playTone(1200 + dy * 200, 20, 0, PLAY_NOW)
  if prow > score then score = prow end
end

local function update(dt)
  local dx, dy = readFlick()
  if dx ~= 0 or dy ~= 0 then hop(dx, dy) end
  if hopT > 0 then hopT = hopT - dt end

  -- camera creeps forward and catches up with a player far ahead
  camSpeed = 0.18 + math.min(0.3, score / 300)
  cam = cam + camSpeed * dt
  if prow - cam > 4 then cam = cam + (prow - cam - 4) * 3 * dt end
  genLanes()

  for r = lowRow, topRow do
    local ln = lanes[r]
    if ln and ln.kind ~= 0 then
      for _, o in ipairs(ln.objs) do
        o.x = o.x + ln.v * dt
        if o.x >= LOOP then o.x = o.x - LOOP end
        if o.x < 0 then o.x = o.x + LOOP end
      end
    end
  end

  if prow - cam < -0.5 then die() return end
  local ln = lanes[prow]
  if not ln then return end
  if ln.kind == 1 then
    for _, o in ipairs(ln.objs) do
      if overlaps(o, px + 1, px + 7) then
        die()
        return
      end
    end
  elseif ln.kind == 2 and hopT <= 0 then
    local onLog = false
    for _, o in ipairs(ln.objs) do
      if overlaps(o, px + 2, px + 6) then onLog = true end
    end
    if not onLog then die() return end
    px = px + ln.v * dt
    if px < -3 or px > (COLS - 1) * T + 3 then die() return end
  end
end

-- filled rect clipped to the screen
local function box(x, y, w, h, flags)
  x = math.floor(x)
  if x < 0 then w = w + x x = 0 end
  if x + w > LCD_W then w = LCD_W - x end
  if w > 0 and y >= 0 and y + h <= LCD_H then
    lcd.drawFilledRectangle(x, y, w, h, flags or 0)
  end
end

local function hbox(x, y, w, h)
  x = math.floor(x)
  if x < 0 or x + w > LCD_W or y < 0 or y + h > LCD_H then
    box(x, y, w, h)
    box(x + 1, y + 1, w - 2, h - 2, ERASE)
  else
    lcd.drawRectangle(x, y, w, h)
  end
end

local function draw()
  lcd.clear()
  local base = math.floor(cam)
  for r = base - 1, base + 8 do
    local ln = lanes[r]
    local y = math.floor(LCD_H - T - (r - cam) * T + 0.5)
    if ln and y > -T and y < LCD_H then
      if ln.kind == 0 then
        for c = 0, COLS - 1 do
          if ln.trees[c] and y >= 0 and y + 7 <= LCD_H then
            lcd.drawFilledRectangle(c * T + 2, y + 1, 4, 4)
            lcd.drawFilledRectangle(c * T + 3, y + 5, 2, 2)
          end
        end
      elseif ln.kind == 1 then
        local up = lanes[r + 1]
        if up and up.kind == 1 and y >= 0 then
          lcd.drawLine(0, y, LCD_W - 1, y, DOTTED, FORCE)
        end
        for _, o in ipairs(ln.objs) do
          for k = 0, 1 do
            local sx = o.x - OFF - k * LOOP
            if sx < LCD_W and sx + o.w > 0 then
              box(sx, y + 1, o.w, 6)
              box(sx + (ln.v > 0 and o.w - 3 or 1), y + 2, 2, 4, ERASE)
            end
          end
        end
      else
        if y >= 0 and y + 6 < LCD_H then
          lcd.drawLine(0, y + 2, LCD_W - 1, y + 2, DOTTED, FORCE)
          lcd.drawLine(1, y + 5, LCD_W - 1, y + 5, DOTTED, FORCE)
        end
        for _, o in ipairs(ln.objs) do
          for k = 0, 1 do
            local sx = o.x - OFF - k * LOOP
            if sx < LCD_W and sx + o.w > 0 then
              box(sx, y + 1, o.w, 6, ERASE)
              hbox(sx, y + 1, o.w, 6)
            end
          end
        end
      end
    end
  end
  -- the chicken
  local y = math.floor(LCD_H - T - (prow - cam) * T + 0.5) + 1
  if hopT > 0 then y = y - 1 end
  local x = math.floor(px) + 1
  if y >= 0 and y + 6 <= LCD_H and x >= 0 and x + 6 <= LCD_W then
    lcd.drawFilledRectangle(x, y, 6, 6, ERASE)
    lcd.drawFilledRectangle(x + 1, y + 1, 4, 5)
    lcd.drawPoint(x + 2, y)
    lcd.drawPoint(x + 3, y)
    lcd.drawFilledRectangle(x + 3, y + 2, 1, 1, ERASE)
  end
  lcd.drawNumber(LCD_W - 2, 1, score, RIGHT + INVERS)
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
    genLanes()
    draw()
    lcd.drawText(LCD_W / 2 - 34, 10, "CROSSY ROAD", MIDSIZE + INVERS)
    lcd.drawText(4, 30, "Flick right stick", SMLSIZE + INVERS)
    lcd.drawText(4, 40, "ENTER / SA to start", SMLSIZE + INVERS)
    if press then
      reset()
      genLanes()
      armed = false
      state = "play"
    end
  elseif state == "play" then
    update(dt)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 10, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 30, "Row " .. score .. "  Best " .. best, SMLSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 30, 42, "ENTER to retry", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      genLanes()
      armed = false
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
