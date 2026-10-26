-- toolName = TNS|Tower Defense|TNE
---------------------------------------------------------------
-- Tower Defense (single lane) for 128x64 B&W EdgeTX radios
-- Cursor: right stick   Wheel: tower type
-- SA: build   SD: upgrade   hold ENTER: sell
-- BUILD phase: ENTER starts the next wave.
-- WAVE phase: building still allowed (ENTER = build too).
-- Towers: GUN cheap/fast, CAN splash, ICE slows, SNP long range
-- Creeps: normal, runner, armored tank, swarm, boss every 5
---------------------------------------------------------------

local T, GC, GR, TOP = 8, 16, 7, 8
local floor, abs = math.floor, math.abs
local fill, rect, line, text   -- lcd functions, set in init()
local SAVE = "/SCRIPTS/GAMES/towerdef.dat"

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local state, phase, grid, towers, enemies, queue, qi, pathX, pathY, segLen, pathLen
local money, lives, wave, best, spawnT, lastTime, preview
local cx, cy, armed, holdT, msg, msgT, sel, longT

-- "sa" / "sd" once per press; a position held 0.5 s becomes the new rest
local swLast, swRest, swSince = {}, {}, {}
local function swCheck(n, now)
  local v = getValue(n)
  if swLast[n] == nil then
    swLast[n], swRest[n], swSince[n] = v, v, now
  elseif v ~= swLast[n] then
    swLast[n], swSince[n] = v, now
    if v ~= swRest[n] then return true end
  elseif v ~= swRest[n] and now - swSince[n] > 50 then
    swRest[n] = v
  end
  return false
end
local function switchPress()
  local now = getTime()
  local a = swCheck("sa", now)
  local d = swCheck("sd", now)
  if a then return "sa" end
  if d then return "sd" end
  return nil
end

-- tower types 1..4 ------------------------------------------------
local function tName(ty) return string.sub("GUNCANICESNP", ty * 3 - 2, ty * 3) end
local function tCost(ty)
  if ty == 2 then return 30 elseif ty == 3 then return 25 elseif ty == 4 then return 40 end
  return 15
end
-- range, reload, damage
local function tStats(ty, l)
  if ty == 2 then return 17, 1.5 - l * 0.15, 1 + l end
  if ty == 3 then return 14 + l * 2, 1.0, (l >= 3) and 1 or 0 end
  if ty == 4 then return 34 + l * 6, 1.8 - l * 0.2, 2 + l * 2 end
  return 17 + l, 0.55 - l * 0.08, 1 + floor(l / 2)
end
local function upCost(t)
  if t.lvl >= 3 then return nil end
  local c = tCost(t.ty)
  return c + floor((t.lvl - 1) * c / 2)
end

local function cell(c, r)
  if c < 0 or c >= GC or r < 0 or r >= GR then return nil end
  return r * GC + c + 1
end

-- serpentine road: rows 1, 3 and 5, entering left, leaving right
local function buildPath()
  pathX = { -4, 116, 116, 12, 12, 132 }
  pathY = { 20, 20, 36, 36, 52, 52 }
  segLen, pathLen, grid = {}, 0, {}
  for i = 1, GC * GR do grid[i] = 0 end
  for i = 1, #pathX - 1 do
    local dx, dy = pathX[i + 1] - pathX[i], pathY[i + 1] - pathY[i]
    local d = abs(dx) + abs(dy)
    segLen[i] = d
    pathLen = pathLen + d
    for s = 0, d, 4 do
      local k = cell(floor((pathX[i] + dx * s / d) / T), floor((pathY[i] + dy * s / d - TOP) / T))
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

-- wave mix: normal, runner, tank, swarm, boss
local function mix(w)
  local n, f, t, s, b = 3 + w, 0, 0, 0, 0
  if w >= 2 then f = floor(w / 2) + 1 end
  if w >= 3 then t = floor(w / 3) end
  if w % 5 == 0 then
    b = floor(w / 5); n = floor(n / 2)
  elseif w >= 4 and w % 2 == 0 then
    s = 4 + w
  end
  return n, f, t, s, b
end

local function makePreview(w)
  local n, f, t, s, b = mix(w)
  local p = n .. "nrm"
  if f > 0 then p = p .. " " .. f .. "run" end
  if t > 0 then p = p .. " " .. t .. "tnk" end
  if s > 0 then p = p .. " " .. s .. "swm" end
  if b > 0 then p = p .. " " .. b .. "BOSS" end
  preview = p
end

local function say(s, t) msg, msgT = s, t end

local function reset()
  towers, enemies, queue = {}, {}, {}
  money, lives, wave, qi = 60, 10, 0, 1
  spawnT, msgT, longT = 0, 0, 0
  cx, cy = 7, 2
  phase = "build"
  for i = 1, GC * GR do
    if grid[i] ~= 1 then grid[i] = 0 end
  end
  makePreview(1)
end

local function init()
  fill, rect, line, text = lcd.drawFilledRectangle, lcd.drawRectangle, lcd.drawLine, lcd.drawText
  math.randomseed(getTime())
  buildPath()
  best = 0
  pcall(function()
    local f = io.open(SAVE, "r")
    if f then
      best = tonumber(io.read(f, 8)) or 0
      io.close(f)
    end
  end)
  state, sel = "title", 1
  armed, holdT = true, 0
  lastTime = getTime()
  reset()
end

local function saveBest()
  pcall(function()
    local f = io.open(SAVE, "w")
    if f then io.write(f, tostring(best)); io.close(f) end
  end)
end

local function towerAt(c, r)
  for i, t in ipairs(towers) do
    if t.c == c and t.r == r then return t, i end
  end
  return nil
end

local function buildHere()
  local k = cell(cx, cy)
  local c = tCost(sel)
  if k and grid[k] == 0 and money >= c then
    money = money - c
    grid[k] = 2
    towers[#towers + 1] = { c = cx, r = cy, x = cx * T + 4, y = TOP + cy * T + 4, ty = sel,
                            lvl = 1, spent = c, cd = 0, fx = 0, fy = 0, flash = 0 }
    playTone(1500, 40, 0, PLAY_NOW)
  else
    playTone(200, 60, 0, PLAY_NOW)
  end
end

local function upgradeHere()
  local t = towerAt(cx, cy)
  local c = t and upCost(t)
  if c and money >= c then
    money = money - c
    t.lvl = t.lvl + 1
    t.spent = t.spent + c
    playTone(2200, 60, 0, PLAY_NOW)
  else
    playTone(200, 60, 0, PLAY_NOW)
  end
end

local function sellHere()
  local t, i = towerAt(cx, cy)
  if not t then return end
  money = money + floor(t.spent / 2)
  local k = cell(t.c, t.r)
  if k then grid[k] = 0 end
  removeAt(towers, i)
  playTone(700, 80, 0, PLAY_NOW)
end

-- cursor: flick the right stick, hold it to repeat
local function moveCursor(dt)
  local ax, ay = getValue("ail"), getValue("ele")
  if abs(ax) < 300 and abs(ay) < 300 then
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
  if abs(ay) >= abs(ax) then
    if ay > 600 and cy > 0 then cy = cy - 1 end
    if ay < -600 and cy < GR - 1 then cy = cy + 1 end
  else
    if ax > 600 and cx < GC - 1 then cx = cx + 1 end
    if ax < -600 and cx > 0 then cx = cx - 1 end
  end
end

local function startWave()
  wave = wave + 1
  queue, qi, spawnT = {}, 1, 0
  local n, f, t, s, b = mix(wave)
  local m = math.max(n, f, t)
  local mid = math.ceil(m / 2)
  for i = 1, m do
    if i <= n then queue[#queue + 1] = 1 end
    if i <= f then queue[#queue + 1] = 2 end
    if i <= t then queue[#queue + 1] = 3 end
    if i == mid then for j = 1, s do queue[#queue + 1] = 4 end end
  end
  for i = 1, b do queue[#queue + 1] = 5 end
  phase = "wave"
  say(b > 0 and "BOSS WAVE " .. wave .. "!" or "WAVE " .. wave .. " - GO!", 1.5)
  playTone(1000, 150, 0, PLAY_NOW)
end

-- spawns kind k, returns the gap before the next one
local function spawnE(k)
  local h = 2 + wave + wave * wave / 9
  local v = math.min(24, 11 + wave * 0.6)
  local gap = math.max(0.5, 1.1 - wave * 0.04)
  if k == 2 then h, v, gap = h * 0.5, v * 1.7, 0.55
  elseif k == 3 then h, v, gap = h * 3, v * 0.6, 1.3
  elseif k == 4 then h, v, gap = h * 0.35, v * 1.1, 0.22
  elseif k == 5 then h, v, gap = h * 12, v * 0.5, 2.5 end
  h = math.max(1, floor(h))
  local e = { d = 0, hp = h, max = h, k = k, v = v * (0.93 + math.random() * 0.14),
              slow = 0, sf = 1, x = 0, y = 0 }
  placeEnemy(e)
  enemies[#enemies + 1] = e
  return gap
end

local function hurt(e, dmg, ty)
  if e.hp <= 0 then return end
  if ty == 1 and e.k == 3 then dmg = dmg * 0.5 end   -- tank armor vs gun
  e.hp = e.hp - dmg
  if e.hp <= 0 then
    local b = 2
    if e.k == 3 then b = 5 elseif e.k == 4 then b = 1 elseif e.k == 5 then b = 30 end
    money = money + b + floor(wave / 4)
    playTone(900, 25, 0, PLAY_NOW)
  end
end

local function fire(t)
  local rng, rate, dmg = tStats(t.ty, t.lvl)
  local r2 = rng * rng
  if t.ty == 3 then
    local any = false
    local f = 0.65 - 0.1 * t.lvl
    for _, e in ipairs(enemies) do
      local dx, dy = e.x - t.x, e.y - t.y
      if e.hp > 0 and dx * dx + dy * dy <= r2 then
        any = true
        local ff = f
        if e.k == 5 then ff = (f + 1) / 2 end
        if e.slow <= 0 or ff < e.sf then e.sf = ff end
        e.slow = 1.5
        if dmg > 0 then hurt(e, dmg, 3) end
      end
    end
    if any then t.cd, t.flash = rate, 0.1 end
    return
  end
  local tgt = nil
  for _, e in ipairs(enemies) do
    local dx, dy = e.x - t.x, e.y - t.y
    if e.hp > 0 and dx * dx + dy * dy <= r2 then
      if not tgt or (t.ty == 4 and e.hp > tgt.hp) or (t.ty ~= 4 and e.d > tgt.d) then tgt = e end
    end
  end
  if not tgt then return end
  t.cd = rate
  t.fx, t.fy, t.flash = tgt.x, tgt.y, 0.08
  if t.ty == 2 then
    local tx, ty = tgt.x, tgt.y
    for _, e in ipairs(enemies) do
      local dx, dy = e.x - tx, e.y - ty
      if dx * dx + dy * dy <= 81 then hurt(e, dmg, 2) end
    end
  else
    hurt(tgt, dmg, t.ty)
  end
end

local function update(dt)
  if msgT > 0 then msgT = msgT - dt end
  if longT > 0 then longT = longT - dt end
  for _, t in ipairs(towers) do
    if t.flash > 0 then t.flash = t.flash - dt end
  end
  if phase ~= "wave" then return end

  if qi <= #queue then
    spawnT = spawnT - dt
    if spawnT <= 0 then
      local k = queue[qi] or 1
      qi = qi + 1
      spawnT = spawnE(k)
    end
  end

  for _, e in ipairs(enemies) do
    local v = e.v
    if e.slow > 0 then
      e.slow = e.slow - dt
      v = v * e.sf
    end
    e.d = e.d + v * dt
    if e.d >= pathLen then
      e.hp, e.out = 0, true
    else
      placeEnemy(e)
    end
  end

  for _, t in ipairs(towers) do
    t.cd = t.cd - dt
    if t.cd <= 0 then fire(t) end
  end

  -- sweep dead and escaped creeps (nothing else is walking the list now)
  for i = #enemies, 1, -1 do
    local e = enemies[i]
    if e.hp <= 0 then
      if e.out then
        lives = lives - ((e.k == 5) and 5 or 1)
        playTone(300, 120, 0, PLAY_NOW)
      end
      removeAt(enemies, i)
    end
  end

  if lives <= 0 then
    lives, state = 0, "over"
    if wave - 1 > best then best = wave - 1; saveBest() end
    playTone(250, 500, 0, PLAY_NOW)
  elseif qi > #queue and #enemies == 0 then
    local b = 8 + 2 * wave
    money = money + b
    phase = "build"
    if wave > best then best = wave; saveBest() end
    makePreview(wave + 1)
    say("WAVE CLEAR! +$" .. b, 2)
    playTone(1800, 200, 0, PLAY_NOW)
  end
end

local function clampX(x)
  if x < 0 then return 0 end
  if x > LCD_W - 1 then return LCD_W - 1 end
  return x
end

local function drawTower(t)
  local x, y = t.c * T + 1, TOP + t.r * T
  local ty = t.ty
  if ty == 1 then
    rect(x, y + 1, 6, 6)
    fill(x + 2, y + 3, 2, 2, FORCE)
  elseif ty == 2 then
    fill(x, y + 1, 6, 6, FORCE)
    fill(x + 2, y + 3, 2, 2, ERASE)
  elseif ty == 3 then
    line(x, y + 1, x + 5, y + 6, SOLID, FORCE)
    line(x + 5, y + 1, x, y + 6, SOLID, FORCE)
  else
    line(x, y + 6, x + 5, y + 6, SOLID, FORCE)
    line(x, y + 6, x + 2, y + 1, SOLID, FORCE)
    line(x + 3, y + 1, x + 5, y + 6, SOLID, FORCE)
  end
  for i = 2, t.lvl do
    local px = x + (i - 2) * 3
    line(px, y + 7, px + 1, y + 7, SOLID, FORCE)
  end
  if t.flash > 0 then
    if ty == 3 then
      local r = tStats(3, t.lvl)
      local x0, y0 = math.max(0, t.x - r), math.max(TOP, t.y - r)
      local x1, y1 = math.min(LCD_W - 1, t.x + r), math.min(LCD_H - 1, t.y + r)
      rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
    else
      local fx, fy = floor(t.fx), floor(t.fy)
      if fx >= 0 and fx < LCD_W and fy >= TOP and fy < LCD_H then
        line(t.x, t.y, fx, fy, SOLID, FORCE)
        if ty == 2 and fx >= 3 and fx <= LCD_W - 4 then rect(fx - 3, fy - 3, 7, 7) end
      end
    end
  end
end

local function drawEnemy(e)
  local x, y = floor(e.x), floor(e.y)
  if x < 4 or x > LCD_W - 5 then return end
  local k = e.k
  if k == 2 then
    fill(x - 2, y - 1, 5, 2, FORCE)
  elseif k == 3 then
    rect(x - 3, y - 3, 6, 6)
    fill(x - 1, y - 1, 2, 2, FORCE)
  elseif k == 4 then
    fill(x - 1, y - 1, 2, 2, FORCE)
  elseif k == 5 then
    rect(x - 4, y - 4, 8, 8)
    fill(x - 2, y - 2, 4, 4, FORCE)
  else
    fill(x - 2, y - 2, 4, 4, FORCE)
  end
  if e.hp < e.max and k ~= 4 then
    local w = floor(6 * e.hp / e.max + 0.99)
    if w < 1 then w = 1 end
    local yb = y - 5
    if k == 5 then yb = y - 6 end
    line(x - 3, yb, x - 4 + w, yb, SOLID, FORCE)
  end
end

local function infoLine(n, i, s)
  -- box away from the cursor: bottom rows if cursor is high, else top
  local y = TOP + (i - 1) * 8
  if cy <= 3 then y = LCD_H - (n - i + 1) * 8 end
  fill(0, y, LCD_W, 8, FORCE)
  text(2, y + 1, s, SMLSIZE + INVERS)
end

local function draw()
  lcd.clear()
  for i = 1, #pathX - 1 do
    line(clampX(pathX[i]), pathY[i], clampX(pathX[i + 1]), pathY[i + 1], DOTTED, FORCE)
  end
  for _, t in ipairs(towers) do drawTower(t) end
  for _, e in ipairs(enemies) do drawEnemy(e) end
  rect(cx * T, TOP + cy * T, T, T)

  -- status: money, lives, wave, selected tower type + cost
  fill(0, 0, LCD_W, 7, FORCE)
  text(1, 0, "$" .. money, SMLSIZE + INVERS)
  text(34, 0, "H" .. lives, SMLSIZE + INVERS)
  local wn = wave
  if phase == "build" then wn = wave + 1 end
  text(56, 0, "W" .. wn, SMLSIZE + INVERS)
  text(LCD_W - 2, 0, "<" .. tName(sel) .. "$" .. tCost(sel) .. ">", SMLSIZE + INVERS + RIGHT)

  if state ~= "play" then return end
  local l1, l2, l3 = nil, nil, nil
  if msgT > 0 then l1 = msg elseif phase == "build" then l1 = "BUILD: ENTER=wave " .. (wave + 1) end
  if phase == "build" then l2 = preview end
  local t = towerAt(cx, cy)
  if t then
    local c = upCost(t)
    l3 = tName(t.ty) .. t.lvl .. (c and (" SD up$" .. c) or " MAX") .. " sell" .. floor(t.spent / 2)
  end
  local n = (l1 and 1 or 0) + (l2 and 1 or 0) + (l3 and 1 or 0)
  local i = 1
  if l1 then infoLine(n, i, l1); i = i + 1 end
  if l2 then infoLine(n, i, l2); i = i + 1 end
  if l3 then infoLine(n, i, l3) end
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

  if state == "title" then
    lcd.clear()
    text(14, 1, "TOWER DEFENSE", MIDSIZE)
    text(2, 16, "R stick: cursor", SMLSIZE)
    text(2, 24, "Wheel: tower type", SMLSIZE)
    text(2, 32, "SA build  SD upgrade", SMLSIZE)
    text(2, 40, "ENTER start wave", SMLSIZE)
    text(2, 48, "hold ENTER: sell", SMLSIZE)
    text(2, 56, "Best wave " .. best .. "   ENTER", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER or sw then
      reset()
      state = "play"
    end
  elseif state == "play" then
    moveCursor(dt)
    if event == EVT_VIRTUAL_NEXT then
      sel = sel + 1
      if sel > 4 then sel = 1 end
    elseif event == EVT_VIRTUAL_PREV then
      sel = sel - 1
      if sel < 1 then sel = 4 end
    elseif EVT_VIRTUAL_ENTER_LONG and event == EVT_VIRTUAL_ENTER_LONG then
      sellHere()
      longT = 1.5   -- swallow the ENTER that may follow the long press
      if killEvents then killEvents(event) end
    elseif event == EVT_VIRTUAL_ENTER then
      if longT > 0 then
        longT = 0
      elseif phase == "build" then
        startWave()
      else
        buildHere()
      end
    end
    if sw == "sa" then buildHere() elseif sw == "sd" then upgradeHere() end
    update(dt)
    draw()
  else
    draw()
    fill(10, 12, 108, 40, FORCE)
    text(36, 15, "GAME OVER", SMLSIZE + INVERS)
    text(16, 27, "Reached wave " .. wave .. " Best " .. best, SMLSIZE + INVERS)
    text(32, 39, "ENTER: retry", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER then
      reset()
      state = "play"
    end
  end
  return 0
end

return { init = init, run = run }
