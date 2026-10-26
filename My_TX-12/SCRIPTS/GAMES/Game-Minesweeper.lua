-- toolName = TNS|Minesweeper|TNE
-- Minesweeper for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
-- Menu: wheel/stick up-down pick, stick left-right or ENTER change,
--   ENTER on Start or SA plays. Move: right stick or wheel.
-- Reveal: ENTER/SA (on a flagged-out number: opens neighbours)
-- Flag: SD. Big boards scroll. Best times: /SCRIPTS/GAMES/mines.dat

local PATH = "/SCRIPTS/GAMES/mines.dat"
local MAXC, MAXR = 24, 14

-- grid: one flat number per cell, g[(r-1)*COLS+c] = k + 16*s
-- k: 0..8 mines around, 9 = mine; s: 0 hidden, 1 open, 2 flag
local g = {}
local COLS, ROWS, MINES, CELL, OX, OY, VC, VR, offR, offC
local size, level, cw, ch, msel     -- menu choices
local best = {}                     -- best[(size-1)*3+level], 0 = none
local state, curR, curC, flags, opened, placed, boomR, boomC
local elapsed, lastTime, armed, holdT, blinkT
local stk = {}                      -- explicit flood-fill stack

-- names cut from constant strings (no lookup tables)
local SIZES = "Small 10x6 Medium 16x8Large 24x14 Custom     "
local LEVELS = "Easy  NormalHard  "

local function loadBest()
  for i = 1, 9 do best[i] = 0 end
  local data
  pcall(function()
    local f = io.open(PATH, "r")
    if f then
      data = io.read(f, 100)
      io.close(f)
    end
  end)
  if type(data) ~= "string" then return end
  local i = 0
  for n in string.gmatch(data, "%d+") do
    i = i + 1
    if i <= 9 then best[i] = tonumber(n) or 0 end
  end
end

local function saveBest()
  local s = ""
  for i = 1, 9 do s = s .. (best[i] or 0) .. " " end
  pcall(function()
    local f = io.open(PATH, "w")
    if f then
      io.write(f, s .. "\n")
      io.close(f)
    end
  end)
end

-- board dimensions and mine count from the menu choices
local function setup()
  if size == 1 then COLS, ROWS = 10, 6
  elseif size == 2 then COLS, ROWS = 16, 8
  elseif size == 3 then COLS, ROWS = 24, 14
  else COLS, ROWS = cw, ch end
  local dens = 0.12
  if level == 2 then dens = 0.16 elseif level == 3 then dens = 0.21 end
  MINES = math.floor(COLS * ROWS * dens + 0.5)
  if MINES < 1 then MINES = 1 end
  if MINES > COLS * ROWS - 9 then MINES = COLS * ROWS - 9 end
  if COLS <= 13 and ROWS <= 6 then CELL = 9 else CELL = 7 end
  VC = math.floor(124 / CELL)
  if VC > COLS then VC = COLS end
  VR = math.floor(56 / CELL)
  if VR > ROWS then VR = ROWS end
  OX = math.floor((LCD_W - VC * CELL) / 2)
  OY = 8
end

local function init()
  math.randomseed(getTime())
  size, level, cw, ch, msel = 2, 2, 12, 8, 1
  loadBest()
  armed, holdT, blinkT = true, 0, 0
  lastTime = getTime()
  state = "title"
end

local function reset()
  setup()
  for i = 1, COLS * ROWS do g[i] = 0 end
  for i = COLS * ROWS + 1, #g do g[i] = nil end
  curR, curC = math.floor((ROWS + 1) / 2), math.floor((COLS + 1) / 2)
  offR, offC = 0, 0
  flags, opened, placed, elapsed = 0, 0, false, 0
  boomR, boomC = 0, 0
end

local function idx(r, c)
  return (r - 1) * COLS + c
end

-- cell value, nil off the board
local function val(r, c)
  if r < 1 or r > ROWS or c < 1 or c > COLS then return nil end
  return g[idx(r, c)] or 0
end

local function kindOf(r, c)
  return (val(r, c) or 0) % 16
end

local function stateOf(r, c)
  local v = val(r, c)
  if v == nil then return -1 end
  return math.floor(v / 16)
end

local function setState(r, c, s)
  local i = idx(r, c)
  g[i] = ((g[i] or 0) % 16) + 16 * s
end

local function isMine(r, c)
  return kindOf(r, c) == 9
end

local function safeZone(r, c, sr, sc)
  return math.abs(r - sr) <= 1 and math.abs(c - sc) <= 1
end

-- mines go anywhere except the first cell and its neighbours
local function placeMines(sr, sc)
  local n, tries = 0, 0
  while n < MINES and tries < 4000 do
    tries = tries + 1
    local r, c = math.random(ROWS), math.random(COLS)
    if not isMine(r, c) and not safeZone(r, c, sr, sc) then
      g[idx(r, c)] = 9
      n = n + 1
    end
  end
  -- unlucky: fill the rest in order (bounded scan)
  for r = 1, ROWS do
    for c = 1, COLS do
      if n < MINES and not isMine(r, c) and not safeZone(r, c, sr, sc) then
        g[idx(r, c)] = 9
        n = n + 1
      end
    end
  end
  MINES = n
  for r = 1, ROWS do
    for c = 1, COLS do
      if not isMine(r, c) then
        local k = 0
        for dr = -1, 1 do
          for dc = -1, 1 do
            if isMine(r + dr, c + dc) then k = k + 1 end
          end
        end
        g[idx(r, c)] = k
      end
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
    if t < 1 then t = 1 end
    if size <= 3 then
      local i = (size - 1) * 3 + level
      if (best[i] or 0) == 0 or t < best[i] then
        best[i] = t
        saveBest()
      end
    end
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
  stk[1] = idx(r, c)
  setState(r, c, 1)
  opened = opened + 1
  local guard = 0
  while sp > 0 and guard < 4000 do
    guard = guard + 1
    local i = stk[sp]
    sp = sp - 1
    local cr = math.floor((i - 1) / COLS) + 1
    local cc = i - (cr - 1) * COLS
    if kindOf(cr, cc) == 0 then
      for dr = -1, 1 do
        for dc = -1, 1 do
          local nr, nc = cr + dr, cc + dc
          if stateOf(nr, nc) == 0 and not isMine(nr, nc) then
            setState(nr, nc, 1)
            opened = opened + 1
            sp = sp + 1
            stk[sp] = idx(nr, nc)
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
  if k ~= kindOf(r, c) or k == 0 then return end
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
    setState(curR, curC, 2)
    flags = flags + 1
    playTone(2000, 20, 0, PLAY_NOW)
  elseif s == 2 then
    setState(curR, curC, 0)
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

-- keep the cursor inside the visible window
local function follow()
  if curC - offC < 1 then offC = curC - 1 end
  if curC - offC > VC then offC = curC - VC end
  if curR - offR < 1 then offR = curR - 1 end
  if curR - offR > VR then offR = curR - VR end
  if offC < 0 then offC = 0 end
  if offR < 0 then offR = 0 end
  if offC > COLS - VC then offC = COLS - VC end
  if offR > ROWS - VR then offR = ROWS - VR end
end

local function moveCursor(dr, dc)
  curR = curR + dr
  curC = curC + dc
  if curC > COLS then curC = 1; curR = curR + ((dr == 0) and 1 or 0) end
  if curC < 1 then curC = COLS; curR = curR - ((dr == 0) and 1 or 0) end
  if curR > ROWS then curR = 1 end
  if curR < 1 then curR = ROWS end
  follow()
end

local function drawCell(r, c, cursorOn)
  local x = OX + (c - offC - 1) * CELL
  local y = OY + (r - offR - 1) * CELL
  local S = CELL - 1
  local tx, ty = math.floor((CELL - 5) / 2), math.floor((CELL - 7) / 2)
  local v = g[(r - 1) * COLS + c] or 0
  local s, k = math.floor(v / 16), v % 16
  local showMine = (state ~= "play") and k == 9 and s ~= 2
  if cursorOn then
    if s == 1 then
      lcd.drawFilledRectangle(x, y, S, S, FORCE)
      if k > 0 then lcd.drawText(x + tx, y + ty, tostring(k), SMLSIZE + INVERS) end
    else
      lcd.drawRectangle(x, y, S, S)
    end
    return
  end
  if s == 1 then
    if k > 0 then lcd.drawText(x + tx, y + ty, tostring(k), SMLSIZE) end
  elseif showMine then
    if r == boomR and c == boomC then
      lcd.drawFilledRectangle(x, y, S, S, FORCE)
      lcd.drawText(x + tx, y + ty, "*", SMLSIZE + INVERS)
    else
      lcd.drawText(x + tx, y + ty, "*", SMLSIZE)
    end
  elseif s == 2 then
    local m = math.floor(S / 2) - 1
    lcd.drawRectangle(x, y, S, S)
    lcd.drawFilledRectangle(x + m, y + m, 2, 2, FORCE)
    if state ~= "play" and k ~= 9 then
      lcd.drawLine(x, y, x + S - 1, y + S - 1, SOLID, FORCE)
    end
  else
    lcd.drawFilledRectangle(x, y, S, S, FORCE)
  end
end

local function draw()
  lcd.clear()
  local blinkOn = state == "play" and (blinkT % 0.6) < 0.4
  for r = offR + 1, offR + VR do
    for c = offC + 1, offC + VC do
      drawCell(r, c, blinkOn and r == curR and c == curC)
    end
  end
  -- scroll marks: where the window sits on a big board
  if state == "play" then
    if COLS > VC then
      local x = math.floor(offC * (LCD_W - 16) / (COLS - VC))
      lcd.drawLine(x, 7, x + 15, 7, SOLID, FORCE)
    end
    if ROWS > VR and OX >= 2 then
      local y = OY + math.floor(offR * (VR * CELL - 12) / (ROWS - VR))
      lcd.drawLine(0, y, 0, y + 11, SOLID, FORCE)
    end
    lcd.drawText(1, 0, "Mines " .. (MINES - flags), SMLSIZE)
    lcd.drawText(LCD_W - 1, 0, "T " .. math.floor(elapsed), SMLSIZE + RIGHT)
  elseif (blinkT % 3) >= 2 then
    lcd.drawText(1, 0, "SD = back to menu", SMLSIZE + INVERS)
  elseif state == "won" then
    lcd.drawText(1, 0, "CLEAR " .. math.floor(elapsed) .. "s ENTER=new", SMLSIZE + INVERS)
  else
    lcd.drawText(1, 0, "BOOM!  ENTER=retry", SMLSIZE + INVERS)
  end
end

-- menu lines: 1 size, 2 level, (3 width, 4 height if custom), last start
local function menuLines()
  if size == 4 then return 5 end
  return 3
end

local function menuChange(line, d)
  if line == 1 then
    size = size + d
    if size > 4 then size = 1 elseif size < 1 then size = 4 end
  elseif line == 2 then
    level = level + d
    if level > 3 then level = 1 elseif level < 1 then level = 3 end
  elseif size == 4 and line == 3 then
    cw = cw + d
    if cw > MAXC then cw = 6 elseif cw < 6 then cw = MAXC end
  elseif size == 4 and line == 4 then
    ch = ch + d
    if ch > MAXR then ch = 4 elseif ch < 4 then ch = MAXR end
  end
end

local function title(event, sw, dt)
  local n = menuLines()
  if msel > n then msel = n end
  if event == EVT_VIRTUAL_NEXT then msel = (msel % n) + 1 end
  if event == EVT_VIRTUAL_PREV then msel = ((msel + n - 2) % n) + 1 end
  local dr, dc = readStick(dt)
  if dr ~= 0 then msel = ((msel - 1 + dr + n) % n) + 1 end
  if dc ~= 0 then menuChange(msel, dc) end
  local go = sw ~= nil
  if event == EVT_VIRTUAL_ENTER then
    if msel == menuLines() then go = true else menuChange(msel, 1) end
  end
  if go then
    reset()
    state = "play"
    return
  end
  setup()
  n = menuLines()
  lcd.clear()
  lcd.drawText(LCD_W / 2 - 40, 0, "MINESWEEPER", MIDSIZE + INVERS)
  local y = 14
  for i = 1, n do
    local t
    if i == 1 then t = "Size  " .. string.sub(SIZES, size * 11 - 10, size * 11)
    elseif i == 2 then t = "Level " .. string.sub(LEVELS, level * 6 - 5, level * 6) .. " (" .. MINES .. ")"
    elseif i == n then t = "Start"
    elseif i == 3 then t = "Width  " .. cw
    else t = "Height " .. ch end
    lcd.drawText(4, y, t, SMLSIZE + ((i == msel) and INVERS or 0))
    y = y + 8
  end
  local b = 0
  if size <= 3 then b = best[(size - 1) * 3 + level] or 0 end
  local bt = (b > 0) and ("Best " .. b .. "s") or "Best -"
  if size == 4 then bt = "" end
  lcd.drawText(LCD_W - 1, 56, bt, SMLSIZE + RIGHT)
  lcd.drawText(1, 56, "SA=start", SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt < 0 then dt = 0 end
  if dt > 0.08 then dt = 0.08 end
  blinkT = blinkT + dt

  local sw = switchPress()

  if state == "title" then
    title(event, sw, dt)
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
  elseif sw == "sd" then
    state = "title"
    armed = false
    return 0
  end

  draw()
  return 0
end

return { init = init, run = run }
