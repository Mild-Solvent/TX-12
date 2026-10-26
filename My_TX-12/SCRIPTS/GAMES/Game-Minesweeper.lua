-- toolName = TNS|Minesweeper|TNE
---------------------------------------------------------------
-- Minesweeper for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Move:   flick right stick (hold to repeat) or scroll wheel
-- Reveal: ENTER or SA      Flag: SD
-- Reveal on a number with all its flags set opens neighbours
-- First reveal is always safe. Exit: RTN / EXIT
---------------------------------------------------------------

local COLS, ROWS = 16, 8
local CELL = 7
local OX, OY = 8, 8
local MINES = 18

local mine, adj, st         -- st: 0 hidden, 1 open, 2 flag
local state, curR, curC, flags, opened, placed, boomR, boomC
local elapsed, best, lastTime, armed, holdT, blinkT
local stR, stC = {}, {}     -- explicit flood-fill stack

local function init()
  math.randomseed(getTime())
  mine, adj, st = {}, {}, {}
  for r = 1, ROWS do
    mine[r], adj[r], st[r] = {}, {}, {}
  end
  best = 0
  armed, holdT, blinkT = true, 0, 0
  lastTime = getTime()
  state = "title"
end

local function reset()
  for r = 1, ROWS do
    for c = 1, COLS do
      mine[r][c] = false
      adj[r][c] = 0
      st[r][c] = 0
    end
  end
  curR, curC = 4, 8
  flags, opened, placed, elapsed = 0, 0, false, 0
  boomR, boomC = 0, 0
end

local function inside(r, c)
  return r >= 1 and r <= ROWS and c >= 1 and c <= COLS
end

local function isMine(r, c)
  local row = mine[r]
  return row ~= nil and row[c] == true
end

local function stateOf(r, c)
  local row = st[r]
  if row == nil then return -1 end
  return row[c] or -1
end

-- mines go anywhere except the first cell and its neighbours
local function placeMines(sr, sc)
  local n = 0
  while n < MINES do
    local r, c = math.random(ROWS), math.random(COLS)
    if not mine[r][c] and (math.abs(r - sr) > 1 or math.abs(c - sc) > 1) then
      mine[r][c] = true
      n = n + 1
    end
  end
  for r = 1, ROWS do
    for c = 1, COLS do
      local k = 0
      for dr = -1, 1 do
        for dc = -1, 1 do
          if isMine(r + dr, c + dc) then k = k + 1 end
        end
      end
      adj[r][c] = k
    end
  end
  placed = true
end

local function lose(r, c)
  boomR, boomC = r, c
  state = "over"
  playTone(200, 500, 0, PLAY_NOW)
end

local function checkWin()
  if opened == ROWS * COLS - MINES then
    state = "won"
    local t = math.floor(elapsed)
    if best == 0 or t < best then best = t end
    playTone(1500, 80, 0, PLAY_NOW)
    playTone(2500, 200, 100, 0)
  end
end

-- open a cell; zeros spread through an explicit stack, no recursion
local function reveal(r, c)
  if stateOf(r, c) ~= 0 then return end
  if not placed then placeMines(r, c) end
  if isMine(r, c) then
    lose(r, c)
    return
  end
  local sp = 1
  stR[1], stC[1] = r, c
  st[r][c] = 1
  opened = opened + 1
  while sp > 0 do
    local cr, cc = stR[sp], stC[sp]
    sp = sp - 1
    if adj[cr][cc] == 0 then
      for dr = -1, 1 do
        for dc = -1, 1 do
          local nr, nc = cr + dr, cc + dc
          if stateOf(nr, nc) == 0 and not isMine(nr, nc) then
            st[nr][nc] = 1
            opened = opened + 1
            sp = sp + 1
            stR[sp], stC[sp] = nr, nc
          end
        end
      end
    end
  end
  checkWin()
end

-- on an open number: if enough flags around, open the rest
local function chord(r, c)
  local k = 0
  for dr = -1, 1 do
    for dc = -1, 1 do
      if stateOf(r + dr, c + dc) == 2 then k = k + 1 end
    end
  end
  if k ~= adj[r][c] or k == 0 then return end
  for dr = -1, 1 do
    for dc = -1, 1 do
      if state == "play" and stateOf(r + dr, c + dc) == 0 then
        reveal(r + dr, c + dc)
      end
    end
  end
end

local function open()
  local s = stateOf(curR, curC)
  if s == 0 then
    reveal(curR, curC)
    if state == "play" then playTone(1200, 20, 0, PLAY_NOW) end
  elseif s == 1 then
    chord(curR, curC)
  end
end

local function toggleFlag()
  local s = stateOf(curR, curC)
  if s == 0 then
    st[curR][curC] = 2
    flags = flags + 1
    playTone(2000, 20, 0, PLAY_NOW)
  elseif s == 2 then
    st[curR][curC] = 0
    flags = flags - 1
    playTone(900, 20, 0, PLAY_NOW)
  end
end

-- "sa" / "sd" once per press, nil otherwise. Works for buttons and
-- toggles: a switch left in a new position for 0.5 s is its new rest.
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
  curR = curR + dr
  curC = curC + dc
  if curC > COLS then curC = 1; curR = curR + ((dr == 0) and 1 or 0) end
  if curC < 1 then curC = COLS; curR = curR - ((dr == 0) and 1 or 0) end
  if curR > ROWS then curR = 1 end
  if curR < 1 then curR = ROWS end
end

local function drawCell(r, c, cursorOn)
  local x = OX + (c - 1) * CELL
  local y = OY + (r - 1) * CELL
  local s = st[r][c]
  local showMine = (state ~= "play") and mine[r][c] and s ~= 2
  if cursorOn then
    if s == 1 then
      lcd.drawFilledRectangle(x, y, 6, 6)
      if adj[r][c] > 0 then lcd.drawText(x + 1, y, tostring(adj[r][c]), SMLSIZE + INVERS) end
    else
      lcd.drawRectangle(x, y, 6, 6)
    end
    return
  end
  if s == 1 then
    if adj[r][c] > 0 then lcd.drawText(x + 1, y, tostring(adj[r][c]), SMLSIZE) end
  elseif showMine then
    if r == boomR and c == boomC then
      lcd.drawFilledRectangle(x, y, 6, 6)
      lcd.drawText(x + 1, y, "*", SMLSIZE + INVERS)
    else
      lcd.drawText(x + 1, y, "*", SMLSIZE)
    end
  elseif s == 2 then
    lcd.drawRectangle(x, y, 6, 6)
    lcd.drawFilledRectangle(x + 2, y + 2, 2, 2)
    if state ~= "play" and not mine[r][c] then
      lcd.drawLine(x, y, x + 5, y + 5, SOLID, FORCE)
    end
  else
    lcd.drawFilledRectangle(x, y, 6, 6)
  end
end

local function draw()
  lcd.clear()
  local blinkOn = state == "play" and (blinkT % 0.6) < 0.4
  for r = 1, ROWS do
    for c = 1, COLS do
      drawCell(r, c, blinkOn and r == curR and c == curC)
    end
  end
  if state == "play" then
    lcd.drawText(1, 0, "Mines " .. (MINES - flags), SMLSIZE)
    lcd.drawText(LCD_W - 1, 0, "T " .. math.floor(elapsed), SMLSIZE + RIGHT)
  elseif state == "won" then
    lcd.drawText(1, 0, "CLEAR " .. math.floor(elapsed) .. "s  ENTER=new", SMLSIZE + INVERS)
  else
    lcd.drawText(1, 0, "BOOM!  ENTER=retry", SMLSIZE + INVERS)
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
  blinkT = blinkT + dt

  local sw = switchPress()

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 40, 4, "MINESWEEPER", MIDSIZE + INVERS)
    lcd.drawText(2, 24, "Stick/wheel: move", SMLSIZE)
    lcd.drawText(2, 33, "ENTER/SA open SD flag", SMLSIZE)
    lcd.drawText(2, 42, MINES .. " mines  Best " .. best .. "s", SMLSIZE)
    lcd.drawText(2, 54, "ENTER to start", SMLSIZE + BLINK)
    if event == EVT_VIRTUAL_ENTER or sw then
      reset()
      state = "play"
    end
    return 0
  end

  if state == "play" then
    if placed then elapsed = elapsed + dt end
    local dr, dc = readStick(dt)
    if dr ~= 0 or dc ~= 0 then
      moveCursor(dr, dc)
      blinkT = 0
    end
    if event == EVT_VIRTUAL_NEXT then moveCursor(0, 1); blinkT = 0 end
    if event == EVT_VIRTUAL_PREV then moveCursor(0, -1); blinkT = 0 end
    if event == EVT_VIRTUAL_ENTER or sw == "sa" then
      open()
    elseif sw == "sd" then
      toggleFlag()
    end
  elseif event == EVT_VIRTUAL_ENTER then
    reset()
    state = "play"
  end

  draw()
  return 0
end

return { init = init, run = run }
