-- toolName = TNS|Pac-Man|TNE
---------------------------------------------------------------
-- Pac-Man for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Move:  right stick (aileron / elevator)
-- Start: ENTER (wheel press)     Exit: RTN / EXIT
---------------------------------------------------------------

local T = 4                  -- tile size in pixels
local MW, MH = 28, 16        -- maze size in tiles

-- Left half of the maze; the right half is mirrored.
-- # wall, . dot, o power pellet, - ghost door, space empty
local HALF = {
  "##############",
  "#o.....##.....",
  "#.###.##.####.",
  "#.............",
  "#.###.#.#####-",
  "#.....#.#     ",
  "   ...#.#     ",
  "#.....#.######",
  "#.###.........",
  "#.###.####.##.",
  "#o..#......#..",
  "###.#.####.#.#",
  "#.....##......",
  "#.#######.###.",
  "#.............",
  "##############",
}

-- Directions: 1 right, 2 left, 3 up, 4 down. Plain ifs instead of lookup
-- tables: on the TX12, direction table lookups kept coming back nil.
local function vec(dir)
  if dir == 1 then return 1, 0
  elseif dir == 3 then return 0, -1
  elseif dir == 4 then return 0, 1 end
  return -1, 0
end

local function opposite(dir)
  if dir == 1 then return 2 elseif dir == 3 then return 4
  elseif dir == 4 then return 3 end
  return 1
end

local maze, dotsLeft
local pac, ghosts, wantDir
local state, score, best, lives, level, frightTime, stateTime, lastTime, anim

local function cell(c, r)
  c = (c - 1) % MW + 1
  local row = maze[r]
  if not row then return "#" end
  return row[c]
end

local function buildMaze()
  maze, dotsLeft = {}, 0
  for r = 1, MH do
    local row = {}
    local line = HALF[r]
    for c = 1, 14 do
      local ch = string.sub(line, c, c)
      row[c] = ch
      row[MW + 1 - c] = ch
    end
    for c = 1, MW do
      if row[c] == "." or row[c] == "o" then dotsLeft = dotsLeft + 1 end
    end
    maze[r] = row
  end
end

local function walkable(c, r, ghost)
  local ch = cell(c, r)
  if ch == "#" then return false end
  if ch == "-" then return ghost and ghost.leaving end
  return true
end

local function newActor(c, r, dir, speed)
  return { c = c, r = r, dir = dir, t = 0, speed = speed }
end

local function resetActors()
  pac = newActor(14, 15, 2, 7.5)
  wantDir = 2
  ghosts = {}
  local starts = { {13, 6}, {15, 6}, {12, 7}, {16, 7} }
  for i = 1, 4 do
    local g = newActor(starts[i][1], starts[i][2], 3, 5.5 + level * 0.4)
    g.release = (i - 1) * 3
    g.leaving = false
    g.home = true
    g.id = i
    ghosts[i] = g
  end
  frightTime = 0
  stateTime = 0
end

local function newLevel()
  buildMaze()
  resetActors()
end

local function newGame()
  score, lives, level = 0, 3, 1
  newLevel()
end

local function init()
  math.randomseed(getTime())
  best = 0
  anim = 0
  state = "title"
  lastTime = getTime()
  newGame()
end

local function readStick()
  local ail = getValue("ail")
  local ele = getValue("ele")
  if math.abs(ail) > math.abs(ele) then
    if ail > 400 then return 1 elseif ail < -400 then return 2 end
  else
    if ele > 400 then return 3 elseif ele < -400 then return 4 end
  end
  return nil
end

local function pixelPos(a)
  local dx, dy = vec(a.dir)
  local x = (a.c - 1 + dx * a.t) * T
  local y = (a.r - 1 + dy * a.t) * T
  if x < -T then x = x + MW * T elseif x > (MW - 1) * T then x = x - MW * T end
  return x, y
end

local function eatAt(c, r)
  c = (c - 1) % MW + 1
  local row = maze[r]
  if not row then return end
  local ch = row[c]
  if ch == "." then
    row[c] = " "
    score = score + 10
    dotsLeft = dotsLeft - 1
    if anim % 2 == 0 then playTone(900, 15, 0, PLAY_NOW) end
  elseif ch == "o" then
    row[c] = " "
    score = score + 50
    dotsLeft = dotsLeft - 1
    frightTime = math.max(2, 7 - level)
    for _, g in ipairs(ghosts) do
      g.ate = false
      if not g.home and not g.leaving then g.dir = opposite(g.dir) ; g.t = 1 - g.t end
    end
    playTone(600, 120, 0, PLAY_NOW)
  end
end

local function arrive(a)
  local dx, dy = vec(a.dir)
  a.c = (a.c - 1 + dx) % MW + 1
  a.r = a.r + dy
  a.t = 0
end

local function movePac(dt)
  -- instant reverse
  if wantDir == opposite(pac.dir) and pac.t > 0 then
    arrive(pac)
    pac.dir = wantDir
    pac.t = 0
  end
  if pac.t == 0 then
    local wx, wy = vec(wantDir)
    if walkable(pac.c + wx, pac.r + wy) then
      pac.dir = wantDir
    end
    local dx, dy = vec(pac.dir)
    if not walkable(pac.c + dx, pac.r + dy) then
      return
    end
  end
  pac.t = pac.t + pac.speed * dt
  if pac.t >= 1 then
    arrive(pac)
    eatAt(pac.c, pac.r)
  end
end

local function ghostTarget(g)
  if g.leaving then return 14, 4 end
  if g.id == 1 then return pac.c, pac.r end
  if g.id == 2 then
    local dx, dy = vec(pac.dir)
    return pac.c + dx * 4, pac.r + dy * 4
  end
  if g.id == 3 then return MW + 1 - pac.c, pac.r end
  -- shy ghost: chase when far, wander to a corner when close
  if math.abs(g.c - pac.c) + math.abs(g.r - pac.r) > 8 then return pac.c, pac.r end
  return 2, MH - 1
end

local function chooseGhostDir(g)
  local best, bestD = nil, 1e9
  local tc, tr = ghostTarget(g)
  local options = {}
  for i = 1, 4 do
    local dx, dy = vec(i)
    if i ~= opposite(g.dir) and walkable(g.c + dx, g.r + dy, g) then
      options[#options + 1] = i
    end
  end
  if #options == 0 then
    g.dir = opposite(g.dir)
    return
  end
  if frightTime > 0 and not g.leaving then
    g.dir = options[math.random(#options)]
    return
  end
  for _, i in ipairs(options) do
    local dx, dy = vec(i)
    local dc, dr = g.c + dx - tc, g.r + dy - tr
    local dist = dc * dc + dr * dr
    if dist < bestD then best, bestD = i, dist end
  end
  if best then g.dir = best end
end

local function moveGhost(g, dt)
  if g.home then
    if stateTime >= g.release then
      g.home = false
      g.leaving = true
    else
      return
    end
  end
  if g.t == 0 then
    chooseGhostDir(g)
  end
  local speed = g.speed
  if frightTime > 0 then speed = speed * 0.55 end
  if g.r == 7 and (g.c <= 3 or g.c >= MW - 2) then speed = speed * 0.6 end  -- tunnel
  g.t = g.t + speed * dt
  if g.t >= 1 then
    arrive(g)
    if g.leaving and g.r <= 4 then g.leaving = false end
  end
end

local function sendHome(g)
  g.c, g.r, g.t, g.dir = 14, 6, 0, 3
  g.home = true
  g.leaving = false
  g.release = stateTime + 2
end

local function checkCollisions()
  local px, py = pixelPos(pac)
  for _, g in ipairs(ghosts) do
    local gx, gy = pixelPos(g)
    if math.abs(px - gx) < 3 and math.abs(py - gy) < 3 then
      if frightTime > 0 and not g.ate and not g.home then
        score = score + 200
        g.ate = true
        sendHome(g)
        playTone(1500, 80, 0, PLAY_NOW)
      elseif not g.home then
        lives = lives - 1
        playTone(200, 500, 0, PLAY_NOW)
        if lives <= 0 then
          if score > best then best = score end
          state = "over"
        else
          state = "dead"
        end
        stateTime = 0
        return
      end
    end
  end
end

local function update(dt)
  stateTime = stateTime + dt
  if frightTime > 0 then frightTime = math.max(0, frightTime - dt) end
  local w = readStick()
  if w then wantDir = w end
  movePac(dt)
  checkCollisions()
  if state ~= "play" then return end
  for _, g in ipairs(ghosts) do moveGhost(g, dt) end
  checkCollisions()
  if dotsLeft == 0 then
    level = level + 1
    playTone(2000, 300, 0, PLAY_NOW)
    newLevel()
    state = "ready"
    stateTime = 0
  end
end

local function drawMaze()
  for r = 1, MH do
    local row = maze[r]
    local y = (r - 1) * T
    for c = 1, MW do
      local ch = row[c]
      local x = (c - 1) * T
      if ch == "#" then
        lcd.drawFilledRectangle(x + 1, y + 1, 2, 2)
        if c < MW and row[c + 1] == "#" then lcd.drawFilledRectangle(x + 2, y + 1, 4, 2) end
        if r < MH and maze[r + 1][c] == "#" then lcd.drawFilledRectangle(x + 1, y + 2, 2, 4) end
      elseif ch == "-" then
        lcd.drawLine(x, y + 2, x + 3, y + 2, DOTTED, FORCE)
      elseif ch == "." then
        lcd.drawPoint(x + 2, y + 2)
      elseif ch == "o" and anim % 8 < 5 then
        lcd.drawFilledRectangle(x + 1, y + 1, 3, 3)
      end
    end
  end
end

local function drawPac()
  local x, y = pixelPos(pac)
  x, y = math.floor(x + 1.5), math.floor(y + 1.5)
  local open = (anim % 4) < 2
  local mx, my = vec(pac.dir)
  for dy = -1, 1 do
    for dx = -1, 1 do
      local mouth = open and (dx == mx and dy == my)
      if not mouth then lcd.drawPoint(x + dx, y + dy) end
    end
  end
  if open then
    lcd.drawPoint(x - mx - my, y - my - mx)
  end
end

local function drawGhost(g)
  local x, y = pixelPos(g)
  x, y = math.floor(x + 1), math.floor(y + 1)
  if frightTime > 0 and not g.home and not (frightTime < 1.5 and anim % 4 < 2) then
    lcd.drawPoint(x, y)
    lcd.drawPoint(x + 2, y)
    lcd.drawPoint(x + 1, y + 1)
    lcd.drawPoint(x, y + 2)
    lcd.drawPoint(x + 2, y + 2)
  else
    lcd.drawFilledRectangle(x, y, 3, 2)
    lcd.drawPoint(x, y + 2)
    lcd.drawPoint(x + 2, y + 2)
  end
end

local function draw()
  lcd.clear()
  drawMaze()
  for _, g in ipairs(ghosts) do drawGhost(g) end
  if state ~= "dead" or anim % 4 < 2 then drawPac() end
  local px = MW * T + 1
  lcd.drawText(px, 1, "SC", SMLSIZE)
  lcd.drawNumber(LCD_W, 9, score, SMLSIZE + RIGHT)
  lcd.drawText(px, 20, "HI", SMLSIZE)
  lcd.drawNumber(LCD_W, 28, best, SMLSIZE + RIGHT)
  lcd.drawText(px, 39, "L" .. level, SMLSIZE)
  for i = 1, lives do
    lcd.drawFilledRectangle(px + (i - 1) * 5, 56, 3, 3)
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
  anim = anim + 1

  if state == "play" then
    update(dt)
    draw()
  elseif state == "title" then
    draw()
    lcd.drawText(34, 26, " PAC-MAN ", MIDSIZE + INVERS)
    lcd.drawText(36, 44, "ENTER to start", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "ready"
      stateTime = 0
    end
  elseif state == "ready" then
    stateTime = stateTime + dt
    draw()
    lcd.drawText(44, 33, "READY!", SMLSIZE + INVERS)
    if stateTime > 1.5 then
      state = "play"
      stateTime = 0
    end
  elseif state == "dead" then
    stateTime = stateTime + dt
    draw()
    if stateTime > 1.5 then
      resetActors()
      state = "ready"
    end
  else
    draw()
    lcd.drawText(34, 26, "GAME OVER", MIDSIZE + INVERS)
    lcd.drawText(36, 44, "ENTER to retry", SMLSIZE + INVERS)
    if event == EVT_VIRTUAL_ENTER then
      newGame()
      state = "ready"
      stateTime = 0
    end
  end
  return 0
end

return { init = init, run = run }
