-- toolName = TNS|Battleship|TNE
---------------------------------------------------------------
-- Battleship for 128x64 B&W EdgeTX radios
-- Menu: 1 player vs AI, or 2 players hot-seat (pass the radio)
-- Setup: SD = shuffle fleet, SA/ENTER = ready
-- Aim:   flick right stick (hold repeats) or scroll wheel
-- Fire:  SA or ENTER     SD: switch target / own fleet view
-- Grid:  small square = not shot, X = miss, black = hit,
--        big hollow square = your ship      Exit: RTN
---------------------------------------------------------------

local N, P, OX, OY, PX = 10, 6, 2, 2, 65
local SHIPS = 5

-- side 1 = player 1, side 2 = player 2 or the AI
-- ships: ship index (0 = water); shots: 0 none, 1 miss, 2 hit
local ship1, shot1, ship2, shot2
local hits1, hits2 = {}, {}
local state, mode, sel, turn, view, handTo, handP
local curR, curC, c1r, c1c, c2r, c2c, lastR, lastC
local msgA, msgB, msgT, waitT, shots1, wins, losses, sc1, sc2
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

-- no lookup tables for sides / directions (nil lookups on the radio)
local function shipsOf(s) if s == 2 then return ship2 end return ship1 end
local function shotsOf(s) if s == 2 then return shot2 end return shot1 end
local function hitsOf(s) if s == 2 then return hits2 end return hits1 end

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

local function tryPlace(g)
  clearGrid(g)
  for i = 1, SHIPS do
    local len, ok, tries = shipLen(i), false, 0
    while not ok and tries < 300 do
      tries = tries + 1
      local dr, dc = 0, 1
      if math.random(2) == 1 then dr, dc = 1, 0 end
      local r = math.random(N - dr * (len - 1))
      local c = math.random(N - dc * (len - 1))
      ok = true
      for k = 0, len - 1 do
        if cell(g, r + dr * k, c + dc * k) ~= 0 then ok = false end
      end
      if ok then
        for k = 0, len - 1 do g[r + dr * k][c + dc * k] = i end
      end
    end
    if not ok then return false end
  end
  return true
end

local function placeRandom(g)
  for t = 1, 20 do
    if tryPlace(g) then return end
  end
  clearGrid(g)  -- fallback, never expected
  for i = 1, SHIPS do
    for k = 1, shipLen(i) do g[i * 2 - 1][k] = i end
  end
end

local function setMsg(a, b)
  msgA, msgB, msgT = a, b or "", 0
end

local function newGame()
  clearGrid(shot1)
  clearGrid(shot2)
  placeRandom(ship1)
  placeRandom(ship2)
  for i = 1, SHIPS do hits1[i], hits2[i] = 0, 0 end
  c1r, c1c, c2r, c2c = 5, 5, 5, 5
  shots1, lastR, lastC = 0, nil, nil
  turn, view, state = 1, "f", "setup"
  setMsg("SD shuffle", "SA ready")
end

local function init()
  math.randomseed(getTime())
  ship1, shot1, ship2, shot2 = newGrid(), newGrid(), newGrid(), newGrid()
  wins, losses, sc1, sc2 = 0, 0, 0, 0
  armed, holdT, blinkT = true, 0, 0
  mode, sel = 1, 1
  lastTime = getTime()
  state = "menu"
  newGame()
  state = "menu"
end

local function sunkCount(hits)
  local n = 0
  for i = 1, SHIPS do
    if hits[i] >= shipLen(i) then n = n + 1 end
  end
  return n
end

-- fire at (r, c) on a side; returns "miss", "hit" or "sunk", ship index
local function fire(side, r, c)
  local ships, shotsG, hits = shipsOf(side), shotsOf(side), hitsOf(side)
  lastR, lastC = r, c
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

local function report(who, res, s)
  if res == "miss" then
    setMsg(who .. " missed")
    playTone(600, 40, 0, PLAY_NOW)
  elseif res == "hit" then
    setMsg(who .. " HIT", shipName(s))
    playTone(2000, 80, 0, PLAY_NOW)
  else
    setMsg(who .. " sank", shipName(s))
    playTone(2500, 200, 0, PLAY_NOW)
  end
end

local function gameOver(w)
  state, view = "over", "t"
  if mode == 1 then
    if w == 1 then
      wins = wins + 1
      setMsg("WON in " .. shots1, "ENTER=menu")
    else
      losses = losses + 1
      view = "f"
      setMsg("YOU LOST", "ENTER=menu")
    end
  else
    turn = w
    if w == 1 then sc1 = sc1 + 1 else sc2 = sc2 + 1 end
    setMsg("P" .. w .. " WINS!", "ENTER=menu")
  end
end

-- AI: hit cells of ships still afloat
local function openHit(r, c)
  if cell(shot1, r, c) ~= 2 then return false end
  local s = ship1[r][c]
  return hits1[s] < shipLen(s)
end

local function addCand(r, c)
  if cell(shot1, r, c) == 0 then
    candR[#candR + 1], candC[#candC + 1] = r, c
  end
end

local function aiPick()
  for i = #candR, 1, -1 do candR[i], candC[i] = nil, nil end
  -- 1. extend a line of two or more open hits
  for r = 1, N do
    for c = 1, N do
      if openHit(r, c) then
        for d = 1, 4 do
          local dr, dc = dirVec(d)
          if openHit(r + dr, c + dc) then
            local k = 2
            while k <= N and openHit(r + dr * k, c + dc * k) do k = k + 1 end
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
  for pass = 1, 2 do
    if #candR == 0 then
      for r = 1, N do
        for c = 1, N do
          if pass == 2 or (r + c) % 2 == 0 then addCand(r, c) end
        end
      end
    end
  end
  if #candR == 0 then return nil end
  local i = math.random(#candR)
  return candR[i], candC[i]
end

local function aiTurn()
  local r, c = aiPick()
  if r == nil then return end
  local res, s = fire(1, r, c)
  report("AI", res, s)
  if sunkCount(hits1) == SHIPS then
    gameOver(2)
  else
    state, waitT = "aires", 1.4
  end
end

local function startTurn(p)
  turn, view = p, "t"
  if p == 1 then curR, curC = c1r, c1c else curR, curC = c2r, c2c end
  if mode == 2 and lastR then
    state, view, waitT = "peek", "f", 2  -- show where the foe shot
  else
    state = "play"
    if mode == 2 then setMsg("P" .. p .. " turn", "fire!") end
  end
end

local function playerFire()
  local tgt = 3 - turn
  if cell(shotsOf(tgt), curR, curC) ~= 0 then
    playTone(150, 40, 0, PLAY_NOW)
    return
  end
  if turn == 1 then shots1 = shots1 + 1 end
  local res, s = fire(tgt, curR, curC)
  local who = "You"
  if mode == 2 then who = "P" .. turn end
  report(who, res, s)
  if turn == 1 then c1r, c1c = curR, curC else c2r, c2c = curR, curC end
  if sunkCount(hitsOf(tgt)) == SHIPS then
    gameOver(turn)
  else
    state, waitT = "result", 1.2
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

-- one 10x10 board, 6 px cells (5 px mark + 1 px gap)
local function drawBoard(side, fleet, reveal)
  lcd.drawRectangle(OX - 1, OY - 1, N * P + 1, N * P + 1)
  local sg, gs = shipsOf(side), shotsOf(side)
  for r = 1, N do
    local y = OY + (r - 1) * P
    for c = 1, N do
      local x = OX + (c - 1) * P
      local sh = gs[r][c] or 0
      if sh == 2 then
        lcd.drawFilledRectangle(x, y, 5, 5, FORCE)
      elseif sh == 1 then
        lcd.drawLine(x, y, x + 4, y + 4, SOLID, FORCE)
        lcd.drawLine(x + 4, y, x, y + 4, SOLID, FORCE)
      elseif (sg[r][c] or 0) > 0 and (fleet or reveal) then
        lcd.drawRectangle(x, y, 5, 5)
      elseif fleet then
        lcd.drawPoint(x + 2, y + 2)
      else
        lcd.drawRectangle(x + 1, y + 1, 3, 3)
      end
    end
  end
end

local function frame(r, c)
  if r and c and (blinkT % 0.5) < 0.35 then
    lcd.drawRectangle(OX + (c - 1) * P - 1, OY + (r - 1) * P - 1, 7, 7)
  end
end

local function pad(s)
  if #s < 10 then return s .. string.rep(" ", 10 - #s) end
  return s
end

-- ships afloat as bars (sunk = flat line), with a label
local function fleetLine(y, label, hits)
  lcd.drawText(PX, y, label .. " " .. (SHIPS - sunkCount(hits)) .. "/5", SMLSIZE)
  local x = PX
  for i = 1, SHIPS do
    local w = shipLen(i) * 3
    if hits[i] < shipLen(i) then
      lcd.drawFilledRectangle(x, y + 8, w, 3, FORCE)
    else
      lcd.drawLine(x, y + 10, x + w - 1, y + 10, SOLID, FORCE)
    end
    x = x + w + 2
  end
end

local function draw()
  lcd.clear()
  local side, fleet = 3 - turn, view == "f"
  if fleet then side = turn end
  drawBoard(side, fleet, state == "over")
  if state == "play" and not fleet then frame(curR, curC)
  elseif state == "result" or state == "aires" or state == "peek" then
    frame(lastR, lastC)
  end
  -- right panel: view name, message bar, fleets, hint
  local t = "MY FLEET"
  if not fleet then t = "TARGET" end
  if mode == 2 then
    t = "P" .. turn .. " FLEET"
    if not fleet then t = "P" .. turn .. " TARGET" end
  end
  lcd.drawText(PX, 0, t, SMLSIZE)
  local f = INVERS
  if msgT < 0.9 and (msgT % 0.3) >= 0.15 then f = 0 end
  lcd.drawText(PX, 9, pad(msgA), SMLSIZE + f)
  lcd.drawText(PX, 18, pad(msgB), SMLSIZE + f)
  if state == "setup" then
    if mode == 1 then t = "W" .. wins .. " L" .. losses
    else t = "Score " .. sc1 .. ":" .. sc2 end
    lcd.drawText(PX, 30, t, SMLSIZE)
    return
  end
  fleetLine(29, "Enemy", hitsOf(3 - turn))
  fleetLine(42, "Yours", hitsOf(turn))
  if state == "play" or state == "over" then
    t = "SD:fleet"
    if fleet then t = "SD:target" end
    lcd.drawText(PX, 56, t, SMLSIZE)
  end
end

local function drawMenu()
  lcd.clear()
  lcd.drawText(LCD_W / 2 - 38, 1, "BATTLESHIP", MIDSIZE + INVERS)
  lcd.drawText(20, 17, " 1 PLAYER vs AI ", SMLSIZE + ((sel == 1) and INVERS or 0))
  lcd.drawText(20, 27, " 2 PLAYERS      ", SMLSIZE + ((sel == 2) and INVERS or 0))
  lcd.drawText(2, 39, "Aim: stick or wheel", SMLSIZE)
  lcd.drawText(2, 47, "Fire: SA or ENTER", SMLSIZE)
  lcd.drawText(2, 55, "SD: see your fleet", SMLSIZE)
end

local function drawHand()
  lcd.clear()
  lcd.drawText(LCD_W / 2 - 30, 4, "PLAYER " .. handP, MIDSIZE + INVERS)
  local t = "your turn"
  if handTo == "setup" then t = "place your fleet" end
  lcd.drawText(10, 24, t, SMLSIZE)
  lcd.drawText(10, 34, "Pass the radio,", SMLSIZE)
  lcd.drawText(10, 44, "then press ENTER", SMLSIZE + BLINK)
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
  msgT = msgT + dt

  local sw = switchPress()
  local ok = event == EVT_VIRTUAL_ENTER or sw == "sa"

  if state == "menu" then
    local dr = readStick(dt)
    if dr ~= 0 or event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
      sel = 3 - sel
    end
    if ok or sw then
      mode = sel
      newGame()
      draw()
    else
      drawMenu()
    end
    return 0
  elseif state == "hand" then
    if ok or sw then
      if handTo == "setup" then
        turn, view, state = handP, "f", "setup"
        setMsg("SD shuffle", "SA ready")
      else
        startTurn(handP)
      end
      draw()
    else
      drawHand()
    end
    return 0
  elseif state == "setup" then
    if sw == "sd" then
      placeRandom(shipsOf(turn))
      playTone(1000, 20, 0, PLAY_NOW)
    elseif ok then
      if mode == 1 then
        startTurn(1)
        setMsg("Your turn", "fire!")
      else
        state, handTo, handP = "hand", "setup", 2
        if turn == 2 then handTo, handP = "turn", 1 end
      end
    end
  elseif state == "play" then
    local dr, dc = readStick(dt)
    if event == EVT_VIRTUAL_NEXT then dc = 1 end
    if event == EVT_VIRTUAL_PREV then dc = -1 end
    if dr ~= 0 or dc ~= 0 then
      moveCursor(dr, dc)
      blinkT = 0
      view = "t"
    end
    if sw == "sd" then
      if view == "t" then view = "f" else view = "t" end
    elseif ok then
      if view == "f" then view = "t" else playerFire() end
    end
  elseif state == "result" then
    waitT = waitT - dt
    if waitT <= 0 or ok then
      if mode == 1 then
        state, waitT, view = "ai", 0.7, "f"
        setMsg("AI aims..")
      else
        state, handTo, handP = "hand", "turn", 3 - turn
      end
    end
  elseif state == "ai" then
    waitT = waitT - dt
    if waitT <= 0 then aiTurn() end
  elseif state == "aires" or state == "peek" then
    waitT = waitT - dt
    if waitT <= 0 or ok then
      state, view = "play", "t"
      if mode == 2 then setMsg("P" .. turn .. " turn", "fire!") end
    end
  elseif state == "over" then
    if sw == "sd" then
      if view == "t" then view = "f" else view = "t" end
    elseif ok then
      state = "menu"
    end
  end

  if state == "hand" then drawHand()
  elseif state == "menu" then drawMenu()
  else draw() end
  return 0
end

return { init = init, run = run }
