-- toolName = TNS|Geometry Dash|TNE
---------------------------------------------------------------
-- Geometry Dash for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Jump:  SA or SD, or ENTER (wheel press)
-- Jump over spikes, land on blocks. Each level is a bit
-- faster and denser. A press just before landing still counts.
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local GROUND = LCD_H - 6
local PX = 20
local S = 7             -- player square
local JUMP_V = 165      -- px/s
local GRAVITY = 620     -- px/s^2 -> ~22 px high, ~0.53 s in the air
local SPIKE = 7
local LEVEL_LEN = 1600  -- px per level
local BUFFER = 0.15     -- s a press is remembered while airborne

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, py, vy, onGround, angle, obs, level, speed, levelDist, dist
local score, best, lastTime, buf, nextX, msgT

-- kind 1 = spike (base = height it sits on), kind 2 = block from the ground
local function add(x, kind, w, h, base)
  obs[#obs + 1] = { x = x, kind = kind, w = w, h = h, base = base }
end

local function setLevel(l)
  level = l
  speed = math.min(110, 72 + (l - 1) * 6)
  levelDist = 0
  msgT = 1.2
end

local function reset()
  py = GROUND - S
  vy = 0
  onGround = true
  angle = 0
  buf = 0
  obs = {}
  dist = 0
  score = 0
  nextX = LCD_W + 30
  setLevel(1)
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

-- adds one pattern at nextX and moves nextX past it plus a gap
local function pattern()
  local x = nextX
  local maxP = 3
  if level >= 2 then maxP = 5 end
  if level >= 3 then maxP = 6 end
  local p = math.random(maxP)
  local w
  if p == 1 then
    add(x, 1, SPIKE, SPIKE, 0); w = SPIKE
  elseif p == 2 then
    add(x, 1, SPIKE, SPIKE, 0); add(x + SPIKE, 1, SPIKE, SPIKE, 0); w = 2 * SPIKE
  elseif p == 3 then
    w = 8 * math.random(2, 4)
    add(x, 2, w, 8, 0)
  elseif p == 4 then
    add(x, 1, SPIKE, SPIKE, 0); add(x + SPIKE, 1, SPIKE, SPIKE, 0)
    add(x + 2 * SPIKE, 1, SPIKE, SPIKE, 0); w = 3 * SPIKE
  elseif p == 5 then
    add(x, 2, 14, 8, 0); add(x + 14, 2, 14, 16, 0); w = 28
  else
    add(x, 2, 48, 8, 0); add(x + 20, 1, SPIKE, SPIKE, 8); w = 48
  end
  -- gap shrinks with level but always leaves room to land and jump again
  local minGap = math.max(0.55, 0.85 - level * 0.05) * speed
  local gap = minGap + math.random() * math.max(12, speed * (1.1 - level * 0.12))
  nextX = x + w + math.floor(gap)
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function die()
  state = "over"
  if score > best then best = score end
  playTone(250, 350, 0, PLAY_NOW)
end

local function update(dt, jump)
  if jump then buf = BUFFER else buf = buf - dt end
  if onGround and buf > 0 then
    vy = -JUMP_V
    onGround = false
    buf = 0
    playTone(1300, 25, 0, PLAY_NOW)
  end

  local dx = speed * dt
  dist = dist + dx
  levelDist = levelDist + dx
  nextX = nextX - dx
  score = math.floor(dist / 10)
  if msgT > 0 then msgT = msgT - dt end

  local prevBot = py + S
  vy = vy + GRAVITY * dt
  py = py + vy * dt

  for i = #obs, 1, -1 do
    local o = obs[i]
    o.x = o.x - dx
    if o.x + o.w < 0 then removeAt(obs, i) end
  end
  if levelDist < LEVEL_LEN then
    while nextX < LCD_W + 10 do pattern() end
  elseif #obs == 0 then
    setLevel(level + 1)
    nextX = LCD_W + 20
    playTone(2600, 150, 0, PLAY_NOW)
  end

  -- find the floor under the square: ground or a block top we were above
  local floor = GROUND
  for _, o in ipairs(obs) do
    if o.kind == 2 and o.x < PX + S and o.x + o.w > PX then
      local top = GROUND - o.h
      if prevBot <= top + 1 and top < floor then floor = top end
    end
  end
  if py + S >= floor then
    py = floor - S
    vy = 0
    if not onGround then angle = 0 end
    onGround = true
  else
    onGround = false
  end
  if not onGround then angle = angle + 9 * dt end

  -- crashes
  for _, o in ipairs(obs) do
    if o.kind == 2 then
      if overlap(PX, py, S, S - 1, o.x, GROUND - o.h + 1, o.w, o.h) then
        die(); return
      end
    else
      local top = GROUND - o.base - o.h
      if overlap(PX + 1, py + 1, S - 2, S - 2, o.x + 2, top + 3, o.w - 4, o.h - 3) then
        die(); return
      end
    end
  end
end

local function drawPlayer()
  local y = math.floor(py)
  if onGround or state ~= "play" then
    lcd.drawRectangle(PX, y, S, S)
    lcd.drawFilledRectangle(PX + 2, y + 2, 3, 3)
  else
    local c, s = math.cos(angle) * 4.5, math.sin(angle) * 4.5
    local cx, cy = PX + 3.5, py + 3.5
    local x1, y1 = math.floor(cx + c), math.floor(cy + s)
    local x2, y2 = math.floor(cx - s), math.floor(cy + c)
    local x3, y3 = math.floor(cx - c), math.floor(cy - s)
    local x4, y4 = math.floor(cx + s), math.floor(cy - c)
    lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
    lcd.drawLine(x2, y2, x3, y3, SOLID, FORCE)
    lcd.drawLine(x3, y3, x4, y4, SOLID, FORCE)
    lcd.drawLine(x4, y4, x1, y1, SOLID, FORCE)
    lcd.drawFilledRectangle(math.floor(cx) - 1, math.floor(cy) - 1, 2, 2)
  end
end

local function draw()
  lcd.clear()
  lcd.drawLine(0, GROUND, LCD_W - 1, GROUND, SOLID, FORCE)
  local off = math.floor(dist) % 16
  for i = 0, 8 do
    local gx = i * 16 - off
    lcd.drawLine(gx, GROUND + 1, gx + 3, LCD_H - 1, SOLID, FORCE)
  end
  for _, o in ipairs(obs) do
    local x = math.floor(o.x)
    if x < LCD_W and x + o.w > 0 then
      if o.kind == 2 then
        lcd.drawRectangle(x, GROUND - o.h, o.w, o.h + 1)
        lcd.drawLine(x, GROUND - o.h, x + o.w - 1, GROUND, DOTTED, FORCE)
      else
        local b = GROUND - o.base
        lcd.drawLine(x, b, x + 3, b - SPIKE + 1, SOLID, FORCE)
        lcd.drawLine(x + 3, b - SPIKE + 1, x + 6, b, SOLID, FORCE)
        lcd.drawLine(x + 2, b - 2, x + 4, b - 2, SOLID, FORCE)
      end
    end
  end
  drawPlayer()
  -- level progress bar
  local w = math.floor(math.min(1, levelDist / LEVEL_LEN) * 60)
  lcd.drawRectangle(34, 1, 62, 4)
  lcd.drawFilledRectangle(35, 2, w, 2)
  lcd.drawText(1, 0, "L" .. level, SMLSIZE)
  lcd.drawNumber(LCD_W - 1, 0, score, RIGHT + SMLSIZE)
  if state == "play" and msgT > 0 then
    lcd.drawText(LCD_W / 2 - 20, 18, "LEVEL " .. level, SMLSIZE + INVERS)
  end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local jump = (event == EVT_VIRTUAL_ENTER) or switchPress()

  if state == "title" then
    draw()
    lcd.drawText(LCD_W / 2 - 42, 12, "GEOMETRY DASH", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 46, 30, "Jump: SA/SD/ENTER", SMLSIZE)
    if jump then
      reset()
      state = "play"
    end
  elseif state == "play" then
    update(dt, jump)
    draw()
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 12, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 40, 28, "Level " .. level .. " Score " .. score, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 40, 37, "Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 46, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "title"
    end
  end
  return 0
end

return { init = init, run = run }
