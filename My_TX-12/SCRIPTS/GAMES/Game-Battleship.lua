-- toolName = TNS|Battleship|TNE
---------------------------------------------------------------
-- Battleship vs the radio, for 128x64 B&W EdgeTX radios
--
-- Left grid: your fleet. Right grid: enemy waters.
-- Setup: ENTER or SA = start, SD = shuffle your ships
-- Aim:   flick right stick (hold to repeat) or scroll wheel
-- Fire:  SA, SD or ENTER        Exit: RTN / EXIT
-- Fleet: 5, 4, 3, 3, 2. Bars at the right = enemy ships afloat
---------------------------------------------------------------

local N = 10
local P = 5                 -- cell pitch in px
local OX1, OX2, OY = 1, 62, 13
local SHIPS = 5

-- grids per side: ship index (0 = water) and shots (0 none, 1 miss, 2 hit)
local pShip, pShot, eShip, eShot
local pHits, eHits = {}, {}  -- hits taken per ship
local state, curR, curC, msg, aiT, shots, wins, losses
local lastTime, armed, holdT, blinkT
local candR, candC = {}, {}

local function shipLen(i)
  if i == 1 then return 5 elseif i == 2 then return 4
  elseif i == 5 then return 2 end
  return 3
end

local function shipName(i)
  if i == 1 then return "Carrier" elseif i == 2 then return "Battleship"
  elseif i == 3 then return "Cruiser" elseif i == 4 then return "Submarine" end
  return "Destroyer"
end

-- direction 1..4 -> dr, dc (no lookup tables)
local function dirVec(d)
  if d == 1 then return -1, 0 elseif d == 2 then return 1, 0
  elseif d == 3 then return 0, -1 end
  return 0, 1
end

local function cell(g, r, c)
  local row = g[r]
  if row == nil then return -1 end
  return row[c] or -1
end

local function newGrid()
  local g = {}
  for r = 1, N do
    g[r] = {}
    for c = 1, N do g[r][c] = 0 end
  end
  return g
end

local function clearGrid(g)
  for r = 1, N do
    for c = 1, N do g[r][c] = 0 end
  end
end

local function placeRandom(g)
  clearGrid(g)
  for i = 1, SHIPS do
    local len = shipLen(i)
    local ok = false
    while not ok do
      local horiz = math.random(2) == 1
      local dr, dc = 0, 1
      if not horiz then dr, dc = 1, 0 end
      local r = math.random(N - dr * (len - 1))
      local c = math.random(N - dc * (len - 1))
      ok = true
      for k = 0, len - 1 do
        if g[r + dr * k][c + dc * k] ~= 0 then ok = false end
      end
      if ok then
        for k = 0, len - 1 do g[r + dr * k][c + dc * k] = i end
      end
    end
  end
end

local function reset()
  clearGrid(pShot)
  clearGrid(eShot)
  placeRandom(pShip)
  placeRandom(eShip)
  for i = 1, SHIPS do pHits[i], eHits[i] = 0, 0 end
  curR, curC = 5, 5
  shots = 0
  msg = "SD shuffle, SA start"
end

local function init()
  math.randomseed(getTime())
  pShip, pShot, eShip, eShot = newGrid(), newGrid(), newGrid(), newGrid()
  wins, losses = 0, 0
  armed, holdT, blinkT = true, 0, 0
  lastTime = getTime()
  state = "title"
  reset()
end

local function fleetSunk(hits)
  for i = 1, SHIPS do
    if hits[i] < shipLen(i) then return false end
  end
  return true
end

-- fire at (r, c) on a side; returns "miss", "hit" or "sunk", ship index
local function fire(ships, shotsG, hits, r, c)
  local s = cell(ships, r, c)
  if s > 0 then
    shotsG[r][c] = 2
    hits[s] = hits[s] + 1
    if hits[s] >= shipLen(s) then return "sunk", s end
    return "hit", s
  end
  shotsG[r][c] = 1
  return "miss", 0
end

-- AI: hit cells of ships still afloat
local function openHit(r, c)
  if cell(pShot, r, c) ~= 2 then return false end
  local s = pShip[r][c]
  return pHits[s] < shipLen(s)
end

local function addCand(r, c)
  if cell(pShot, r, c) == 0 then
    candR[#candR + 1], candC[#candC + 1] = r, c
  end
end

local function clearCand()
  for i = #candR, 1, -1 do candR[i], candC[i] = nil, nil end
end

local function aiPick()
  clearCand()
  -- 1. extend a line of two or more open hits
  for r = 1, N do
    for c = 1, N do
      if openHit(r, c) then
        for d = 1, 4 do
          local dr, dc = dirVec(d)
          if openHit(r + dr, c + dc) then
            local k = 2
            while openHit(r + dr * k, c + dc * k) do k = k + 1 end
            addCand(r + dr * k, c + dc * k)
            addCand(r - dr, c - dc)
          end
        end
      end
    end
  end
  -- 2. neighbours of any open hit
  if #candR == 0 then
    for r = 1, N do
      for c = 1, N do
        if openHit(r, c) then
          for d = 1, 4 do
            local dr, dc = dirVec(d)
            addCand(r + dr, c + dc)
          end
        end
      end
    end
  end
  -- 3. hunt on a checkerboard, then anywhere
  if #candR == 0 then
    for r = 1, N do
      for c = 1, N do
        if (r + c) % 2 == 0 then addCand(r, c) end
      end
    end
  end
  if #candR == 0 then
    for r = 1, N do
      for c = 1, N do addCand(r, c) end
    end
  end
  local i = math.random(#candR)
  return candR[i], candC[i]
end

local function aiTurn()
  local r, c = aiPick()
  if r == nil then return end
  local res, s = fire(pShip, pShot, pHits, r, c)
  if res == "miss" then
    msg = "AI missed. Your turn"
    playTone(500, 40, 0, PLAY_NOW)
  elseif res == "hit" then
    msg = "AI hit " .. shipName(s)
    playTone(300, 120, 0, PLAY_NOW)
  else
    msg = "AI sank " .. shipName(s)
    playTone(200, 300, 0, PLAY_NOW)
  end
  if fleetSunk(pHits) then
    state = "over"
    losses = losses + 1
    msg = "YOU LOST  ENTER=new"
  end
end

local function playerFire()
  if cell(eShot, curR, curC) ~= 0 then
    playTone(150, 40, 0, PLAY_NOW)
    return
  end
  shots = shots + 1
  local res, s = fire(eShip, eShot, eHits, curR, curC)
  if res == "miss" then
    msg = "You: miss"
    playTone(800, 40, 0, PLAY_NOW)
  elseif res == "hit" then
    msg = "You: HIT!"
    playTone(2000, 80, 0, PLAY_NOW)
  else
    msg = "You sank " .. shipName(s) .. "!"
    playTone(2500, 200, 0, PLAY_NOW)
  end
  if fleetSunk(eHits) then
    state = "over"
    wins = wins + 1
    msg = "WON in " .. shots .. "! ENTER=new"
  else
    state = "ai"
    aiT = 0.8
  end
end

-- "sa" / "sd" once per press, nil otherwise (buttons and toggles)
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

-- dr, dc once per flick (re-arm at centre); held stick repeats
local function readStick(dt)
  local h, v = getValue("ail"), getValue("ele")
  local ah, av = math.abs(h), math.abs(v)
  if ah < 300 and av < 300 then
    armed, holdT = true, 0
    return 0, 0
  end
  local dr, dc = 0, 0
  if ah > 600 and ah >= av then
    dc = (h > 0) and 1 or -1
  elseif av > 600 then
    dr = (v > 0) and -1 or 1
  end
  if dr == 0 and dc == 0 then return 0, 0 end
  if armed then
    armed, holdT = false, 0
    return dr, dc
  end
  holdT = holdT + dt
  if holdT > 0.45 then
    holdT = 0.33
    return dr, dc
  end
  return 0, 0
end

local function moveCursor(dr, dc)
  curR, curC = curR + dr, curC + dc
  if curC > N then curC = 1; if dr == 0 then curR = curR + 1 end end
  if curC < 1 then curC = N; if dr == 0 then curR = curR - 1 end end
  if curR > N then curR = 1 end
  if curR < 1 then curR = N end
end

local function drawGrid(ox, ships, shotsG, own)
  lcd.drawRectangle(ox - 1, OY - 1, N * P + 1, N * P + 1)
  for r = 1, N do
    for c = 1, N do
      local x = ox + (c - 1) * P
      local y = OY + (r - 1) * P
      local s, sh = ships[r][c], shotsG[r][c]
      if sh == 2 then
        if own then
          lcd.drawRectangle(x, y, 4, 4)
        else
          lcd.drawFilledRectangle(x, y, 4, 4)
        end
      elseif sh == 1 then
        lcd.drawPoint(x + 1, y + 1)
        lcd.drawPoint(x + 2, y + 2)
      elseif s > 0 and (own or state == "over") then
        if own then
          lcd.drawFilledRectangle(x, y, 4, 4)
        else
          lcd.drawRectangle(x, y, 4, 4)
        end
      end
      if r < N and c < N then lcd.drawPoint(x + 4, y + 4) end
    end
  end
end

local function draw()
  lcd.clear()
  drawGrid(OX1, pShip, pShot, true)
  if state == "setup" then
    lcd.drawText(OX2, OY + 2, "Your fleet", SMLSIZE)
    lcd.drawText(OX2, OY + 14, "SD: shuffle", SMLSIZE)
    lcd.drawText(OX2, OY + 24, "SA/ENTER:", SMLSIZE)
    lcd.drawText(OX2, OY + 33, "  battle!", SMLSIZE)
    lcd.drawText(OX2, OY + 44, "W" .. wins .. " L" .. losses, SMLSIZE)
  else
    drawGrid(OX2, eShip, eShot, false)
    if state == "play" and (blinkT % 0.6) < 0.45 then
      lcd.drawRectangle(OX2 + (curC - 1) * P - 1, OY + (curR - 1) * P - 1, 6, 6)
    end
    -- enemy ships still afloat, as bars
    local y = OY + 1
    for i = 1, SHIPS do
      if eHits[i] < shipLen(i) then
        lcd.drawFilledRectangle(LCD_W - 1 - shipLen(i) * 2, y, shipLen(i) * 2, 2)
      end
      y = y + 4
    end
  end
  lcd.drawText(1, 2, msg, SMLSIZE + ((state == "over") and INVERS or 0))
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end
  blinkT = blinkT + dt

  local sw = switchPress()

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 38, 4, "BATTLESHIP", MIDSIZE + INVERS)
    lcd.drawText(2, 24, "Stick/wheel: aim", SMLSIZE)
    lcd.drawText(2, 33, "SA/SD/ENTER: fire", SMLSIZE)
    lcd.drawText(2, 42, "Sink all 5 AI ships", SMLSIZE)
    lcd.drawText(2, 54, "ENTER to start", SMLSIZE + BLINK)
    if event == EVT_VIRTUAL_ENTER or sw then
      reset()
      state = "setup"
    end
    return 0
  end

  if state == "setup" then
    if sw == "sd" then
      placeRandom(pShip)
      playTone(1000, 20, 0, PLAY_NOW)
    elseif sw == "sa" or event == EVT_VIRTUAL_ENTER then
      state = "play"
      msg = "Your turn: fire!"
    end
  elseif state == "play" then
    local dr, dc = readStick(dt)
    if dr ~= 0 or dc ~= 0 then moveCursor(dr, dc); blinkT = 0 end
    if event == EVT_VIRTUAL_NEXT then moveCursor(0, 1); blinkT = 0 end
    if event == EVT_VIRTUAL_PREV then moveCursor(0, -1); blinkT = 0 end
    if sw or event == EVT_VIRTUAL_ENTER then playerFire() end
  elseif state == "ai" then
    aiT = aiT - dt
    if aiT <= 0 then
      aiTurn()
      if state == "ai" then state = "play" end
    end
  elseif event == EVT_VIRTUAL_ENTER then
    reset()
    state = "setup"
  end

  draw()
  return 0
end

return { init = init, run = run }
