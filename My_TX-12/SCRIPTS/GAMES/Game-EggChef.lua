-- toolName = TNS|Egg Chef|TNE
---------------------------------------------------------------
-- Egg Chef for 128x64 B&W EdgeTX radios (TX12)
--
-- Four hens lay eggs that roll down four chutes. Hold the chef's
-- pan under the end of a chute before its egg drops off.
-- 3 broken eggs end the game; every 100 caught mends one.
--
-- Controls: pick a switch layout on the title screen with the
-- wheel (it is saved). Switch up = left / high chute.
--   SE side SF hi/lo  SE picks left/right, SF picks high/low
--   SE left SF right  SE = left chutes, SF = right chutes
--   SA side SB hi/lo  SA picks left/right, SB picks high/low
-- The right stick works in every layout (ail = side, ele = high/low).
-- ENTER: start   RTN: exit
---------------------------------------------------------------

-- Switch layouts. To use other switches, change a line or add one.
-- axes:  a = side switch (up = left), b = height switch (up = high)
-- sides: a = left chutes, b = right chutes (up = high, down = low)
-- A switch in its middle position leaves the pan where it is.
local MODES = {
  { kind = "axes", a = "se", b = "sf", name = "SE side SF hi/lo" },
  { kind = "sides", a = "se", b = "sf", name = "SE left SF right" },
  { kind = "axes", a = "sa", b = "sb", name = "SA side SB hi/lo" },
}

local PATH = "/SCRIPTS/GAMES/eggchef.dat"
local STEPS = 5      -- egg positions on a chute
local MAX_MISS = 3

local hen, chef      -- sprites as flat run lists {x, y, len, ...}
local lane = {}      -- lane[i] = chute (1..4) of the egg at step i, 0 = none
local last = {}      -- last position seen per switch
local state, mode, best, score, misses
local side, row      -- pan: side 0 = left 1 = right, row 0 = high 1 = low
local acc, catchT, missT, missSide, lastTime

-- sprites are drawn facing right; '#' = black pixel
local function parse(rows)
  local r = {}
  for y = 1, #rows do
    local s = rows[y]
    local x = 1
    while x <= #s do
      if string.sub(s, x, x) == "#" then
        local e = x
        while e < #s and string.sub(s, e + 1, e + 1) == "#" do e = e + 1 end
        r[#r + 1] = x - 1
        r[#r + 1] = y - 1
        r[#r + 1] = e - x + 1
        x = e + 1
      else
        x = x + 1
      end
    end
  end
  return r
end

local function sprite(r, ox, oy, w, flip)
  for i = 1, #r, 3 do
    local x, n = r[i], r[i + 2]
    if flip then x = w - x - n end
    x = ox + x
    lcd.drawLine(x, oy + r[i + 1], x + n - 1, oy + r[i + 1], SOLID, FORCE)
  end
end

-- everything is laid out for the left side and mirrored for the right
local function mx(s, x)
  if s == 0 then return x end
  return 127 - x
end

local function load()
  pcall(function()
    local f = io.open(PATH, "r")
    if f then
      local s = io.read(f, 20)
      io.close(f)
      local m, b = string.match(s or "", "(%d+) (%d+)")
      if m then
        mode, best = tonumber(m), tonumber(b)
      end
    end
  end)
  if mode < 1 or mode > #MODES then mode = 1 end
end

local function save()
  pcall(function()
    local f = io.open(PATH, "w")
    if f then
      io.write(f, mode .. " " .. best)
      io.close(f)
    end
  end)
end

local function init()
  math.randomseed(getTime())
  hen = parse({
    "......##..",
    ".....####.",
    "#....#.###",
    "##...####.",
    "#########.",
    ".#######..",
    "..#####...",
    "...#.#....",
  })
  chef = parse({
    "....###......",
    "..##...##....",
    ".#.......#...",
    ".#.......#...",
    "..#.....#....",
    "..#######....",
    "..#......#...",
    "..#...#..#...",
    "..#.......##.",
    "..#..####.#..",
    "...#.....#...",
    "....#####....",
    "..#########..",
    ".#.........#.",
    ".#..#####..#.",
    ".#..#...#..#.",
    ".#..#...#..#.",
    ".#..#...#..#.",
    ".#..#####..#.",
    ".#.........#.",
    "..#########..",
    "...#.....#...",
    "...#.....#...",
    "...#.....#...",
    "...##....##..",
    "...###...###.",
  })
  mode, best = 1, 0
  load()
  side, row, score, misses = 0, 1, 0, 0
  for i = 1, STEPS do lane[i] = 0 end
  catchT, missT, missSide = 0, 0, 0
  state = "title"
  lastTime = getTime()
end

-- -1 / 0 / 1 when the switch moved to up / middle / down, nil if it didn't move
local function swMove(n)
  local v = getValue(n)
  local p = 0
  if v < -300 then p = -1 elseif v > 300 then p = 1 end
  if p ~= last[n] then
    last[n] = p
    return p
  end
  return nil
end

local function readInput()
  local m = MODES[mode]
  local a, b = swMove(m.a), swMove(m.b)
  if m.kind == "axes" then
    if a == -1 then side = 0 elseif a == 1 then side = 1 end
    if b == -1 then row = 0 elseif b == 1 then row = 1 end
  else
    if a == -1 or a == 1 then side, row = 0, (a + 1) / 2 end
    if b == -1 or b == 1 then side, row = 1, (b + 1) / 2 end
  end
  local ail, ele = getValue("ail"), getValue("ele")
  if ail < -500 then side = 0 elseif ail > 500 then side = 1 end
  if ele > 500 then row = 0 elseif ele < -500 then row = 1 end
end

local function period()
  return math.max(0.35, 0.75 - score * 0.004)
end

local function start()
  save()
  score, misses, acc, catchT = 0, 0, 0, 0
  for i = 1, STEPS do lane[i] = 0 end
  for k in pairs(last) do last[k] = nil end  -- take the switches as they are now
  readInput()
  state = "play"
end

local function miss(c)
  misses = misses + 1
  missSide = (c > 2) and 1 or 0
  for i = 1, STEPS do lane[i] = 0 end
  missT = 1.2
  state = "miss"
  playTone(200, 400, 0, PLAY_NOW)
end

-- one game step: every egg rolls on, the last one drops off its chute
local function tick()
  local c = lane[STEPS]
  for i = STEPS, 2, -1 do lane[i] = lane[i - 1] end
  lane[1] = 0
  if c > 0 then
    if c == side * 2 + row + 1 then
      score = score + 1
      catchT = 0.25
      if score % 100 == 0 and misses > 0 then
        misses = misses - 1
        playTone(2500, 200, 0, PLAY_NOW)
      else
        playTone(1800, 40, 0, PLAY_NOW)
      end
    else
      miss(c)
      return
    end
  end
  -- one egg per step, so two eggs never drop at the same time
  local n = 0
  for i = 2, STEPS do
    if lane[i] > 0 then n = n + 1 end
  end
  local cap = math.min(4, 1 + math.floor(score / 8))
  if n < cap and (n == 0 or math.random(10) <= 6) then
    lane[1] = math.random(4)
  end
  if n > 0 or lane[1] > 0 then playTone(1000, 10, 0, PLAY_NOW) end
end

local function egg(cx, top)
  lcd.drawLine(cx - 1, top, cx, top, SOLID, FORCE)
  lcd.drawFilledRectangle(cx - 2, top + 1, 4, 2, FORCE)
  lcd.drawLine(cx - 1, top + 3, cx, top + 3, SOLID, FORCE)
end

local function drawScene()
  lcd.clear()
  lcd.drawLine(0, 63, 127, 63, SOLID, FORCE)
  for s = 0, 1 do
    for r = 0, 1 do
      local y0 = 13 + r * 22
      sprite(hen, mx(s, 0) - 9 * s, y0 - 8, 10, s == 1)
      lcd.drawLine(mx(s, 0), y0, mx(s, 9), y0, SOLID, FORCE)
      lcd.drawLine(mx(s, 10), y0, mx(s, 46), y0 + 12, SOLID, FORCE)
    end
  end
  -- eggs on the chutes
  for i = 1, STEPS do
    local c = lane[i]
    if c > 0 then
      local s, r = 0, 0
      if c > 2 then s = 1 end
      if c == 2 or c == 4 then r = 1 end
      local cx = 14 + math.floor((i - 1) * 7.5)
      local bottom = 13 + r * 22 + math.floor((cx - 10) / 3) - 1
      egg(mx(s, cx), bottom - 3)
    end
  end
  -- chef, arms and pan
  local py = 28 + row * 22
  sprite(chef, 57, 37, 14, side == 0)
  lcd.drawLine(mx(side, 59), 50, mx(side, 51), py + 1, SOLID, FORCE)
  lcd.drawLine(mx(side, 69), 50, mx(side, 71), 56, SOLID, FORCE)
  lcd.drawLine(mx(side, 43), py + 2, mx(side, 50), py + 2, SOLID, FORCE)
  lcd.drawPoint(mx(side, 42), py + 1)
  lcd.drawPoint(mx(side, 51), py + 1)
  if catchT > 0 then egg(mx(side, 47), py - 2) end
  -- broken egg under the chute it fell from
  if state == "miss" then
    local s = missSide
    lcd.drawLine(mx(s, 37), 62, mx(s, 47), 62, SOLID, FORCE)
    lcd.drawLine(mx(s, 39), 61, mx(s, 45), 61, SOLID, FORCE)
    lcd.drawPoint(mx(s, 36), 60)
    lcd.drawPoint(mx(s, 40), 59)
    lcd.drawPoint(mx(s, 44), 59)
    lcd.drawPoint(mx(s, 48), 60)
  end
  -- score and broken eggs
  local t = tostring(score)
  lcd.drawText(64 - 3 * #t, 1, t, SMLSIZE)
  for i = 1, misses do egg(58 + (i - 1) * 6, 11) end
end

local function box(y, h)
  lcd.drawFilledRectangle(4, y, 120, h, ERASE)
  lcd.drawRectangle(4, y, 120, h, SOLID)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then return 2 end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.1 then dt = 0.1 end

  if state == "title" then
    if event == EVT_VIRTUAL_NEXT then
      mode = mode % #MODES + 1
    elseif event == EVT_VIRTUAL_PREV then
      mode = (mode - 2) % #MODES + 1
    elseif event == EVT_VIRTUAL_ENTER then
      start()
    end
    if state == "title" then
      drawScene()
      box(14, 40)
      lcd.drawText(38, 17, "EGG CHEF", MIDSIZE)
      lcd.drawText(7, 31, "<", SMLSIZE)
      lcd.drawText(16, 31, MODES[mode].name, SMLSIZE)
      lcd.drawText(117, 31, ">", SMLSIZE)
      lcd.drawText(10, 42, "ENTER play  Best " .. best, SMLSIZE)
      return 0
    end
  end

  if state == "play" then
    readInput()
    acc = acc + dt
    if acc >= period() then
      acc = acc - period()
      tick()
    end
    if catchT > 0 then catchT = catchT - dt end
    drawScene()
  elseif state == "miss" then
    readInput()
    drawScene()
    missT = missT - dt
    if missT <= 0 then
      acc = 0
      if misses >= MAX_MISS then
        if score > best then best = score end
        save()
        state = "over"
      else
        state = "play"
      end
    end
  else
    drawScene()
    box(14, 40)
    lcd.drawText(34, 17, "GAME OVER", MIDSIZE)
    lcd.drawText(10, 31, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(10, 42, "ENTER menu  RTN exit", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then state = "title" end
  end
  return 0
end

return { init = init, run = run }
