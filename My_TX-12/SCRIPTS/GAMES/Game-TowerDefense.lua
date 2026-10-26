-- toolName = TNS|Tower Defense|TNE
---------------------------------------------------------------
-- Tower Defense (single lane) for 128x64 B&W EdgeTX radios
--
-- Cursor: right stick (flick, or hold to repeat)
-- Build:  SA / SD / ENTER on an empty tile ($15)
-- Upgrade: same on a tower ($20, then $30)
-- Creeps follow the dotted road; each one that gets out
-- costs a life. Waves grow bigger, tougher and faster.
-- Exit:   RTN / EXIT
---------------------------------------------------------------

local T = 8                -- tile size
local GC, GR = 16, 7       -- grid below the 8 px status line
local TOP = 8
local COST, UP2, UP3 = 15, 20, 30

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, grid, towers, enemies, pathX, pathY, segLen, pathLen
local money, lives, wave, best, toSpawn, spawnT, breakT, lastTime
local cx, cy, armed, holdT, msgT

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

local function cell(c, r)
  if c < 0 or c >= GC or r < 0 or r >= GR then return nil end
  return r * GC + c + 1
end

-- serpentine road: rows 1, 3 and 5, entering left, leaving right
local function buildPath()
  pathX = { -4, 116, 116, 12, 12, 132 }
  pathY = { 20, 20, 36, 36, 52, 52 }
  segLen = {}
  pathLen = 0
  grid = {}
  for i = 1, GC * GR do grid[i] = 0 end
  for i = 1, #pathX - 1 do
    local dx, dy = pathX[i + 1] - pathX[i], pathY[i + 1] - pathY[i]
    local d = math.abs(dx) + math.abs(dy)   -- segments are straight
    segLen[i] = d
    pathLen = pathLen + d
    for s = 0, d, 4 do
      local x = pathX[i] + dx * s / d
      local y = pathY[i] + dy * s / d
      local k = cell(math.floor(x / T), math.floor((y - TOP) / T))
      if k then grid[k] = 1 end
    end
  end
end

local function placeEnemy(e)
  local d = e.d
  for i = 1, #segLen do
    local sl = segLen[i]
    if d <= sl or i == #segLen then
      local f = d / sl
      e.x = pathX[i] + (pathX[i + 1] - pathX[i]) * f
      e.y = pathY[i] + (pathY[i + 1] - pathY[i]) * f
      return
    end
    d = d - sl
  end
end

local function reset()
  towers, enemies = {}, {}
  money, lives, wave = 40, 10, 0
  toSpawn, spawnT, breakT = 0, 0, 3
  cx, cy = 7, 2
  msgT = 0
  for i = 1, GC * GR do
    if grid[i] ~= 1 then grid[i] = 0 end
  end
end

local function init()
  math.randomseed(getTime())
  buildPath()
  best = 0
  state = "title"
  armed, holdT = true, 0
  lastTime = getTime()
  reset()
end

local function towerAt(c, r)
  for _, t in ipairs(towers) do
    if t.c == c and t.r == r then return t end
  end
  return nil
end

local function towerStats(t)
  if t.lvl >= 3 then return 25, 0.4, 2 end
  if t.lvl == 2 then return 22, 0.5, 1 end
  return 18, 0.7, 1
end

local function upCost(t)
  if t.lvl == 1 then return UP2 end
  if t.lvl == 2 then return UP3 end
  return nil
end

local function build()
  local k = cell(cx, cy)
  if not k then return end
  if grid[k] == 0 then
    if money >= COST then
      money = money - COST
      grid[k] = 2
      towers[#towers + 1] = { c = cx, r = cy, x = cx * T + 4, y = TOP + cy * T + 4,
                              lvl = 1, cd = 0, fx = 0, fy = 0, flash = 0 }
      playTone(1500, 40, 0, PLAY_NOW)
      return
    end
  elseif grid[k] == 2 then
    local t = towerAt(cx, cy)
    local c = t and upCost(t)
    if c and money >= c then
      money = money - c
      t.lvl = t.lvl + 1
      playTone(2200, 60, 0, PLAY_NOW)
      return
    end
  end
  playTone(200, 60, 0, PLAY_NOW)
end

-- cursor: flick the right stick, hold it to repeat
local function moveCursor(dt)
  local ax, ay = getValue("ail"), getValue("ele")
  if math.abs(ax) < 300 and math.abs(ay) < 300 then
    armed = true
    return
  end
  local go = false
  if armed then
    go, armed, holdT = true, false, 0.35
  else
    holdT = holdT - dt
    if holdT <= 0 then go, holdT = true, 0.12 end
  end
  if not go then return end
  if math.abs(ay) >= math.abs(ax) then
    if ay > 600 and cy > 0 then cy = cy - 1 end
    if ay < -600 and cy < GR - 1 then cy = cy + 1 end
  else
    if ax > 600 and cx < GC - 1 then cx = cx + 1 end
    if ax < -600 and cx > 0 then cx = cx - 1 end
  end
end

local function startWave()
  wave = wave + 1
  toSpawn = 4 + 2 * wave
  spawnT = 0
  msgT = 1.5
end

local function spawn()
  local hp = 1 + math.floor(wave * 0.8 + wave * wave / 10)
  local v = math.min(26, 12 + wave * 0.8) + math.random() * 3 - 1.5
  local e = { d = 0, hp = hp, max = hp, v = v, x = 0, y = 0 }
  placeEnemy(e)
  enemies[#enemies + 1] = e
end

local function update(dt)
  -- waves
  if toSpawn == 0 and #enemies == 0 then
    breakT = breakT - dt
    if breakT <= 0 then startWave() end
  elseif toSpawn > 0 then
    spawnT = spawnT - dt
    if spawnT <= 0 then
      spawn()
      toSpawn = toSpawn - 1
      spawnT = math.max(0.45, 1.2 - wave * 0.06)
      if toSpawn == 0 then breakT = 4 end
    end
  end
  if msgT > 0 then msgT = msgT - dt end

  -- move creeps
  for _, e in ipairs(enemies) do
    e.d = e.d + e.v * dt
    if e.d >= pathLen then
      e.hp = 0
      e.out = true
    else
      placeEnemy(e)
    end
  end

  -- towers fire at the creep furthest along the road
  for _, t in ipairs(towers) do
    if t.flash > 0 then t.flash = t.flash - dt end
    t.cd = t.cd - dt
    if t.cd <= 0 then
      local rng, rate, dmg = towerStats(t)
      local tgt = nil
      for _, e in ipairs(enemies) do
        if e.hp > 0 then
          local dx, dy = e.x - t.x, e.y - t.y
          if dx * dx + dy * dy <= rng * rng and (not tgt or e.d > tgt.d) then
            tgt = e
          end
        end
      end
      if tgt then
        tgt.hp = tgt.hp - dmg
        t.cd = rate
        t.fx, t.fy, t.flash = tgt.x, tgt.y, 0.07
        if tgt.hp <= 0 then
          money = money + 2 + math.floor(wave / 3)
          playTone(900, 25, 0, PLAY_NOW)
        end
      end
    end
  end

  -- sweep dead and escaped creeps (nothing else is walking the list now)
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    if e.hp <= 0 then
      if e.out then
        lives = lives - 1
        playTone(300, 120, 0, PLAY_NOW)
      end
      removeAt(enemies, i)
    end
  end

  if toSpawn == 0 and #enemies == 0 and breakT == 4 then
    money = money + 5 + wave
    breakT = 3.99
  end

  if lives <= 0 then
    lives = 0
    state = "over"
    if wave > best then best = wave end
    playTone(250, 500, 0, PLAY_NOW)
  end
end

local function clampX(x)
  if x < 0 then return 0 end
  if x > LCD_W - 1 then return LCD_W - 1 end
  return x
end

local function draw()
  lcd.clear()
  -- road
  for i = 1, #pathX - 1 do
    lcd.drawLine(clampX(pathX[i]), pathY[i], clampX(pathX[i + 1]), pathY[i + 1], DOTTED, FORCE)
  end
  -- towers
  for _, t in ipairs(towers) do
    local x, y = t.c * T + 1, TOP + t.r * T + 1
    if t.lvl >= 3 then
      lcd.drawFilledRectangle(x, y, 6, 6)
      lcd.drawFilledRectangle(x + 2, y + 2, 2, 2, ERASE)
    else
      lcd.drawRectangle(x, y, 6, 6)
      if t.lvl == 2 then
        lcd.drawFilledRectangle(x + 1, y + 1, 4, 4)
      else
        lcd.drawFilledRectangle(x + 2, y + 2, 2, 2)
      end
    end
    if t.flash > 0 then
      local fx, fy = math.floor(t.fx), math.floor(t.fy)
      if fx >= 0 and fx < LCD_W and fy >= TOP and fy < LCD_H then
        lcd.drawLine(t.x, t.y, fx, fy, SOLID, FORCE)
      end
    end
  end
  -- creeps
  for _, e in ipairs(enemies) do
    local x, y = math.floor(e.x) - 2, math.floor(e.y) - 2
    if x >= 0 and x + 4 <= LCD_W then
      if e.hp * 2 > e.max then
        lcd.drawFilledRectangle(x, y, 4, 4)
      else
        lcd.drawRectangle(x, y, 4, 4)
      end
    end
  end
  -- cursor
  lcd.drawRectangle(cx * T, TOP + cy * T, T, T)
  -- status line
  lcd.drawFilledRectangle(0, 0, LCD_W, 7)
  lcd.drawText(1, 0, "$" .. money, SMLSIZE + INVERS)
  lcd.drawText(32, 0, "HP" .. lives, SMLSIZE + INVERS)
  lcd.drawText(60, 0, "W" .. wave, SMLSIZE + INVERS)
  local k = cell(cx, cy)
  local hint = ""
  if k and grid[k] == 0 then
    hint = "+" .. COST
  elseif k and grid[k] == 2 then
    local t = towerAt(cx, cy)
    local c = t and upCost(t)
    hint = c and ("^" .. c) or "max"
  end
  lcd.drawText(LCD_W - 2, 0, hint, SMLSIZE + INVERS + RIGHT)
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
    lcd.drawText(14, 14, "TOWER DEFENSE", MIDSIZE + INVERS)
    lcd.drawText(10, 32, "R stick: cursor", SMLSIZE + INVERS)
    lcd.drawText(10, 42, "SA/SD/ENTER: build", SMLSIZE + INVERS)
    if press then
      reset()
      state = "play"
    end
  elseif state == "play" then
    moveCursor(dt)
    if press then build() end
    update(dt)
    draw()
    if msgT > 0 then
      lcd.drawText(44, 26, "WAVE " .. wave, MIDSIZE + INVERS)
    end
  else
    draw()
    lcd.drawText(LCD_W / 2 - 28, 14, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 32, "Wave " .. wave .. "  Best " .. best, SMLSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 30, 42, "ENTER to retry", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
