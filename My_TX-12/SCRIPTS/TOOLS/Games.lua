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

local games, sel, top, game, err

local function prettyName(file)
  local name = string.gsub(file, "%.lua$", "")
  name = string.gsub(name, "^Game%-", "")
  return name
end

local function scan()
  games = {}
  local ok = pcall(function()
    for file in dir(DIR) do
      if string.match(file, "%.lua$") then
        games[#games + 1] = { file = file, name = prettyName(file) }
      end
    end
  end)
  if not ok then err = "Cannot read " .. DIR end
  table.sort(games, function(a, b) return a.name < b.name end)
end

local function init()
  sel, top = 1, 1
  scan()
end

local function stopGame()
  game = nil
  collectgarbage()
end

local function startGame(entry)
  local ok, result = pcall(function()
    local chunk = loadScript(DIR .. entry.file)
    if not chunk then error("load failed") end
    local g = chunk()
    if g.init then g.init() end
    return g
  end)
  if ok and result and result.run then
    game = result
    err = nil
  else
    err = entry.name .. ": " .. tostring(result)
    stopGame()
  end
end

local function drawMenu()
  lcd.clear()
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(2, 1, "GAMES", SMLSIZE + INVERS)
  lcd.drawText(LCD_W - 2, 1, #games .. " games", SMLSIZE + INVERS + RIGHT)
  if err then
    lcd.drawText(2, 54, err, SMLSIZE + BLINK)
  end
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
    if not ok then
      err = tostring(result)
      stopGame()
    elseif result ~= 0 then
      stopGame()
    end
    return 0
  end

  if event == EVT_VIRTUAL_EXIT then
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
