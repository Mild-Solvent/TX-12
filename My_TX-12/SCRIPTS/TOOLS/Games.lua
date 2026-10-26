-- toolName = TNS|Games|TNE
---------------------------------------------------------------
-- Games launcher: one "Games" entry in the Tools menu that lists
-- every game in /SCRIPTS/GAMES/ and runs the one you pick.
--
-- Scroll wheel: choose    ENTER: play    RTN: back / exit
-- To add a game, drop its .lua file into /SCRIPTS/GAMES/
---------------------------------------------------------------

local DIR = "/SCRIPTS/GAMES/"
local ROWS = 6

local KNOWN = {
  "Game-2048.lua", "Game-Artillery.lua", "Game-Asteroids.lua",
  "Game-Battleship.lua", "Game-Blackjack.lua", "Game-Breakout.lua",
  "Game-CrossyRoad.lua", "Game-Dino.lua", "Game-DonkeyKong.lua",
  "Game-DoodleJump.lua", "Game-Flappy.lua", "Game-GeometryDash.lua",
  "Game-Invaders.lua", "Game-Minesweeper.lua", "Game-PacMan.lua",
  "Game-Pinball.lua", "Game-Plinko.lua", "Game-Poker.lua", "Game-Pong.lua",
  "Game-Racer.lua", "Game-Rhythm.lua", "Game-Simon.lua",
  "Game-Simulator.lua", "Game-Snake.lua", "Game-Tamagotchi.lua",
  "Game-TowerDefense.lua", "Game-X-Tris.lua",
}

local games, sel, top, game, err
local peak, lastPeak, lastName  -- Lua heap in KB while a game runs

local function prettyName(file)
  local name = string.gsub(file, "%.lua$", "")
  name = string.gsub(name, "^Game%-", "")
  return name
end

local function scan()
  games = {}
  -- dir() finds nothing when the path ends in "/"
  local ok = pcall(function()
    for file in dir(string.sub(DIR, 1, -2)) do
      if string.match(string.lower(file), "%.lua$") then
        games[#games + 1] = { file = file, name = prettyName(file) }
      end
    end
  end)
  if #games == 0 then
    -- fall back to the bundled games if the folder can't be listed
    for _, file in ipairs(KNOWN) do
      local f = io.open(DIR .. file, "r")
      if f then
        io.close(f)
        games[#games + 1] = { file = file, name = prettyName(file) }
      end
    end
  end
  if not ok and #games == 0 then err = "Cannot read " .. DIR end
  -- insertion sort: EdgeTX on B&W radios has no table library
  for i = 2, #games do
    local g, j = games[i], i - 1
    while j >= 1 and games[j].name > g.name do
      games[j + 1] = games[j]
      j = j - 1
    end
    games[j + 1] = g
  end
end

local function init()
  sel, top = 1, 1
  scan()
end

local function stopGame()
  if game then lastPeak, lastName = peak, game.name end
  game = nil
  collectgarbage()
end

local function startGame(entry)
  local ok, result = pcall(function()
    -- "d" keeps line numbers in error messages
    local chunk = loadScript(DIR .. entry.file, "Td") or loadScript(DIR .. entry.file)
    if not chunk then error("load failed") end
    local g = chunk()
    if g.init then g.init() end
    return g
  end)
  if ok and result and result.run then
    game = result
    game.name = entry.name
    peak = collectgarbage("count")
    err = nil
  else
    err = entry.name .. ": " .. string.gsub(tostring(result), DIR, "")
    stopGame()
  end
end

local function drawError()
  lcd.clear()
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(2, 1, "ERROR", SMLSIZE + INVERS)
  local y, i = 11, 1
  while i <= #err and y < LCD_H - 8 do
    lcd.drawText(1, y, string.sub(err, i, i + 20), SMLSIZE)
    i, y = i + 21, y + 8
  end
  lcd.drawText(LCD_W - 1, LCD_H - 7, "any key", SMLSIZE + INVERS + RIGHT)
end

local function drawMenu()
  if err then return drawError() end
  lcd.clear()
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(2, 1, "GAMES", SMLSIZE + INVERS)
  local info
  if lastPeak then
    info = lastName .. " peak " .. math.floor(lastPeak) .. "K"
  else
    info = math.floor(collectgarbage("count")) .. "K used"
    if getAvailableMemory then
      info = info .. " " .. math.floor(getAvailableMemory() / 1024) .. "K free"
    end
  end
  lcd.drawText(LCD_W - 2, 1, info, SMLSIZE + INVERS + RIGHT)
  if #games == 0 then
    lcd.drawText(2, 20, "No games in", SMLSIZE)
    lcd.drawText(2, 30, DIR, SMLSIZE)
    return
  end
  for i = 0, ROWS - 1 do
    local idx = top + i
    local g = games[idx]
    if not g then break end
    local y = 11 + i * 9
    lcd.drawText(4, y, g.name, (idx == sel) and (SMLSIZE + INVERS) or SMLSIZE)
  end
  if top > 1 then lcd.drawText(LCD_W - 6, 11, "^", SMLSIZE) end
  if top + ROWS - 1 < #games then lcd.drawText(LCD_W - 6, 56, "v", SMLSIZE) end
end

local function run(event)
  if game then
    if event == EVT_VIRTUAL_EXIT then
      stopGame()
      return 0
    end
    local ok, result = pcall(game.run, event)
    local kb = collectgarbage("count")
    if game and kb > peak then peak = kb end
    if not ok then
      err = (string.gsub(tostring(result), DIR, ""))
      stopGame()
    elseif result ~= 0 then
      stopGame()
    end
    return 0
  end

  if err and event ~= 0 then
    err = nil
  elseif event == EVT_VIRTUAL_EXIT then
    return 2
  elseif event == EVT_VIRTUAL_NEXT and #games > 0 then
    sel = sel % #games + 1
  elseif event == EVT_VIRTUAL_PREV and #games > 0 then
    sel = (sel - 2) % #games + 1
  elseif event == EVT_VIRTUAL_ENTER and games[sel] then
    startGame(games[sel])
    if game then return 0 end
  end
  if sel < top then top = sel end
  if sel > top + ROWS - 1 then top = sel - ROWS + 1 end
  drawMenu()
  return 0
end

return { init = init, run = run }
