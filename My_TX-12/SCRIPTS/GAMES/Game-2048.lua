-- toolName = TNS|2048|TNE
---------------------------------------------------------------
-- 2048 for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Slide: flick right stick (ail/ele) or left stick rudder
-- New game: ENTER (wheel press)   Exit: RTN / EXIT
---------------------------------------------------------------

local CELL_W, CELL_H = 16, 15
local OX, OY = 1, 2
local SIZE = 4

-- EdgeTX on B&W radios has no table library
local function removeAt(t, i)
  for j = i, #t - 1 do t[j] = t[j + 1] end
  t[#t] = nil
end

local grid, score, best, over, won, armed

local function emptyCells()
  local cells = {}
  for r = 1, SIZE do
    for c = 1, SIZE do
      if grid[r][c] == 0 then cells[#cells + 1] = { r, c } end
    end
  end
  return cells
end

local function spawn()
  local cells = emptyCells()
  if #cells == 0 then return end
  local cell = cells[math.random(#cells)]
  grid[cell[1]][cell[2]] = (math.random(10) == 1) and 4 or 2
end

local function newGame()
  grid = {}
  for r = 1, SIZE do
    grid[r] = { 0, 0, 0, 0 }
  end
  score, over, won = 0, false, false
  spawn()
  spawn()
end

local function init()
  math.randomseed(getTime())
  best = 0
  armed = true
  newGame()
end

-- Slide one line toward index 1, merging equal neighbours once.
local function slideLine(line)
  local out, gained = {}, 0
  for i = 1, SIZE do
    if line[i] ~= 0 then out[#out + 1] = line[i] end
  end
  local i = 1
  while i < #out do
    if out[i] == out[i + 1] then
      out[i] = out[i] * 2
      gained = gained + out[i]
      if out[i] == 2048 then won = true end
      removeAt(out, i + 1)
    end
    i = i + 1
  end
  for j = #out + 1, SIZE do out[j] = 0 end
  return out, gained
end

-- dr, dc: direction of movement
local function move(dr, dc)
  local moved = false
  for k = 1, SIZE do
    local line, coords = {}, {}
    for i = 1, SIZE do
      local r, c
      if dc ~= 0 then
        r = k
        c = (dc < 0) and i or (SIZE + 1 - i)
      else
        c = k
        r = (dr < 0) and i or (SIZE + 1 - i)
      end
      line[i] = grid[r][c]
      coords[i] = { r, c }
    end
    local out, gained = slideLine(line)
    score = score + gained
    for i = 1, SIZE do
      local rc = coords[i]
      if grid[rc[1]][rc[2]] ~= out[i] then moved = true end
      grid[rc[1]][rc[2]] = out[i]
    end
  end
  return moved
end

local function canMove()
  for r = 1, SIZE do
    for c = 1, SIZE do
      local v = grid[r][c]
      if v == 0 then return true end
      if c < SIZE and grid[r][c + 1] == v then return true end
      if r < SIZE and grid[r + 1][c] == v then return true end
    end
  end
  return false
end

-- Returns dr, dc once per stick flick; stick must return to center to re-arm.
local function readStick()
  local ail = getValue("ail")
  local ele = getValue("ele")
  local rud = getValue("rud")
  local h = ail
  if math.abs(rud) > math.abs(h) then h = rud end
  if math.abs(h) < 250 and math.abs(ele) < 250 then
    armed = true
    return nil
  end
  if not armed then return nil end
  if math.abs(h) > 600 and math.abs(h) >= math.abs(ele) then
    armed = false
    return 0, (h > 0) and 1 or -1
  elseif math.abs(ele) > 600 then
    armed = false
    return (ele > 0) and -1 or 1, 0
  end
  return nil
end

local function draw()
  lcd.clear()
  for r = 1, SIZE do
    for c = 1, SIZE do
      local x = OX + (c - 1) * CELL_W
      local y = OY + (r - 1) * CELL_H
      local v = grid[r][c]
      if v >= 128 then
        lcd.drawFilledRectangle(x, y, CELL_W - 1, CELL_H - 1)
      else
        lcd.drawRectangle(x, y, CELL_W - 1, CELL_H - 1)
      end
      if v > 0 then
        local flags = SMLSIZE + CENTER
        if v >= 128 then flags = flags + INVERS end
        lcd.drawText(x + CELL_W / 2, y + 4, tostring(v), flags)
      end
    end
  end
  local tx = OX + SIZE * CELL_W + 4
  lcd.drawText(tx, 2, "2048", MIDSIZE)
  lcd.drawText(tx, 20, "Score", SMLSIZE)
  lcd.drawNumber(tx + 26, 20, score, SMLSIZE)
  lcd.drawText(tx, 30, "Best", SMLSIZE)
  lcd.drawNumber(tx + 26, 30, best, SMLSIZE)
  if over then
    lcd.drawText(tx, 42, "GAME OVER", SMLSIZE + INVERS)
    lcd.drawText(tx, 52, "ENTER: new", SMLSIZE)
  elseif won then
    lcd.drawText(tx, 42, "YOU WIN!", SMLSIZE + INVERS)
    lcd.drawText(tx, 52, "keep going", SMLSIZE)
  else
    lcd.drawText(tx, 46, "Flick stick", SMLSIZE)
  end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end
  if event == EVT_VIRTUAL_ENTER and over then
    newGame()
  end

  local dr, dc = readStick()
  if dr and not over then
    if move(dr, dc) then
      spawn()
      playTone(1800, 20, 0, PLAY_NOW)
      if score > best then best = score end
      if not canMove() then
        over = true
        playTone(300, 300, 0, PLAY_NOW)
      end
    end
  end

  draw()
  return 0
end

return { init = init, run = run }
