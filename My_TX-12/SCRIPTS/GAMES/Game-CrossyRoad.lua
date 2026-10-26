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
local px, prow, score, best, lastTime, armed, hopT, lastKind, cause

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
  -- capped loops: at most 16 lanes made / dropped per frame
  local want = math.floor(cam) + KEEP
  for i = 1, 16 do
    if topRow >= want then break end
    topRow = topRow + 1
    lanes[topRow] = newLane(topRow)
  end
  local low = math.floor(cam) - 2
  for i = 1, 16 do
    if lowRow >= low then break end
    lanes[lowRow] = nil
    lowRow = lowRow + 1
  end
end

-- Drawing and collision share these, so a hit is exactly what you see.
-- screen y of the top of lane r
local function laneY(r)
  return math.floor(LCD_H - T - (r - cam) * T + 0.5)
end
-- screen x of a lane object's left edge (k = 1: its wrapped copy)
local function objX(o, k)
  return math.floor(o.x) - OFF - k * LOOP
end
-- left column of the drawn chicken (6 px wide)
local function chickX()
  return math.floor(px) + 1
end

-- does screen column range [a, b) overlap the drawn object o?
local function overlaps(o, a, b)
  for k = 0, 1 do
    local sx = objX(o, k)
    if a < sx + o.w and b > sx then return true end
  end
  return false
end

local function die(why)
  state = "over"
  cause = why
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

  if prow - cam < -0.5 then die("Too slow!") return end
  local ln = lanes[prow]
  if not ln then return end
  -- the chicken is drawn 6 px wide at chickX(); its outer column on each
  -- side is forgiven, so a hit needs at least 2 drawn pixels of overlap
  local cx = chickX()
  if ln.kind == 1 then
    for _, o in ipairs(ln.objs) do
      if overlaps(o, cx + 1, cx + 5) then
        die("Hit by a car")
        return
      end
    end
  elseif ln.kind == 2 and hopT <= 0 then
    local onLog = false
    for _, o in ipairs(ln.objs) do
      if overlaps(o, cx + 1, cx + 5) then onLog = true end
    end
    if not onLog then die("Splash!") return end
    px = px + ln.v * dt
    if px < -3 or px > (COLS - 1) * T + 3 then die("Swept away") return end
  end
end

-- filled rect clipped to the screen; solid black unless ERASE is given,
-- never XOR, so overlapping shapes cannot invert each other
local function box(x, y, w, h, flags)
  x, y = math.floor(x), math.floor(y)
  if x < 0 then w = w + x x = 0 end
  if y < 0 then h = h + y y = 0 end
  if x + w > LCD_W then w = LCD_W - x end
  if y + h > LCD_H then h = LCD_H - y end
  if w > 0 and h > 0 then
    lcd.drawFilledRectangle(x, y, w, h, flags or FORCE)
  end
end

local function draw()
  lcd.clear()
  local base = math.floor(cam)
  for r = base - 1, base + 8 do
    local ln = lanes[r]
    local y = laneY(r)
    if ln and y > -T and y < LCD_H then
      if ln.kind == 0 then
        for c = 0, COLS - 1 do
          if ln.trees[c] then
            box(c * T + 2, y + 1, 4, 4)
            box(c * T + 3, y + 5, 2, 2)
          end
        end
      elseif ln.kind == 1 then
        local up = lanes[r + 1]
        if up and up.kind == 1 and y >= 0 then
          lcd.drawLine(0, y, LCD_W - 1, y, DOTTED, FORCE)
        end
        for _, o in ipairs(ln.objs) do
          for k = 0, 1 do
            local sx = objX(o, k)
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
            local sx = objX(o, k)
            if sx < LCD_W and sx + o.w > 0 then
              -- white log with a black outline, all FORCE / ERASE
              box(sx, y + 1, o.w, 6, ERASE)
              box(sx, y + 1, o.w, 1)
              box(sx, y + 6, o.w, 1)
              box(sx, y + 1, 1, 6)
              box(sx + o.w - 1, y + 1, 1, 6)
            end
          end
        end
      end
    end
  end
  -- the chicken: 6 px wide (same columns the hit test uses), comb, eye
  local y = laneY(prow) + 1
  if hopT > 0 then y = y - 1 end
  local x = chickX()
  box(x, y + 1, 6, 5)
  box(x + 2, y, 2, 1)
  box(x + 4, y + 2, 1, 1, ERASE)
  box(LCD_W - 22, 0, 22, 9, ERASE)
  lcd.drawNumber(LCD_W - 2, 1, score, RIGHT)
end

-- white panel with a black frame for messages, so text never inverts
local function panel(y, h)
  box(4, y, LCD_W - 8, h, ERASE)
  box(4, y, LCD_W - 8, 1)
  box(4, y + h - 1, LCD_W - 8, 1)
  box(4, y, 1, h)
  box(LCD_W - 5, y, 1, h)
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
    panel(6, 44)
    lcd.drawText(18, 9, "CROSSY ROAD", MIDSIZE)
    lcd.drawText(9, 26, "Flick right stick", SMLSIZE)
    lcd.drawText(9, 37, "ENTER/SA to start", SMLSIZE)
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
    -- keep the panel off the chicken's lane so the crash stays visible
    local py = (laneY(prow) <= 28) and 37 or 1
    panel(py, 26)
    lcd.drawText(9, py + 2, cause or "GAME OVER", SMLSIZE)
    lcd.drawText(9, py + 10, "Row " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(9, py + 18, "ENTER to retry", SMLSIZE)
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
