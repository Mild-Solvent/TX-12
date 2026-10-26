-- toolName = TNS|MemTest|TNE
---------------------------------------------------------------
-- Memory Test for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Shows how much RAM Lua scripts (our games) really get on this
-- radio. The test fills memory 1 KB at a time until the radio
-- refuses, then frees it all again. Nothing is changed on the
-- radio; the result is kept in /SCRIPTS/GAMES/MEMTEST.txt.
-- Start test: ENTER, SA or SD      Exit: RTN / EXIT
---------------------------------------------------------------

local FILE = "/SCRIPTS/GAMES/MEMTEST.txt"
local CHUNK = 1000         -- bytes per block
local PER_FRAME = 2        -- blocks added per frame
local SAFE_FREE = 8        -- KB the radio keeps when it reports free RAM
local CAP = 400            -- KB, stop anyway (the radio has ~192 KB in total)

local state, chunks, n, base, peak, why, saved
local frames, t0, frameMs, armed, lastSave

local function freeKB()
  if getAvailableMemory then
    local ok, v = pcall(getAvailableMemory)
    if ok and v then return math.floor(v / 1024) end
  end
end

local function heap()
  return collectgarbage("count")
end

local function readSaved()
  local f = io.open(FILE, "r")
  if not f then return nil end
  local s = io.read(f, 200)
  io.close(f)
  return s
end

local function save(text)
  local f = io.open(FILE, "w")
  if f then
    io.write(f, text)
    io.close(f)
  end
end

local function pressed(event)
  local sw = getValue("sa") > 0 or getValue("sd") > 0
  local hit = event == EVT_VIRTUAL_ENTER or (sw and armed)
  armed = not sw
  return hit
end

local function init()
  state = "info"
  saved = readSaved()
  frames, t0, frameMs = 0, getTime(), nil
  armed = false
end

local function startTest()
  collectgarbage()
  collectgarbage()
  chunks, n = {}, 0
  base = heap()
  peak = base
  why = nil
  lastSave = 0
  save("running... reached +0 KB")
  state = "fill"
end

local function finish(reason)
  why = reason
  chunks = nil
  collectgarbage()
  collectgarbage()
  local got = math.floor(peak - base)
  saved = "+" .. got .. " KB  (" .. reason .. ")"
  save(saved)
  state = "result"
end

local function grow()
  n = n + 1
  chunks[n] = string.rep("#", CHUNK) .. n
end

local function fill()
  for _ = 1, PER_FRAME do
    local ok = pcall(grow)
    if not ok then return finish("radio limit") end
    local kb = heap()
    if kb > peak then peak = kb end
    local free = freeKB()
    if free and free <= SAFE_FREE then return finish("safety stop") end
    if peak - base >= CAP then return finish("cap") end
  end
  -- write progress now and then, so a hard stop still leaves a record
  if peak - base - lastSave >= 8 then
    lastSave = peak - base
    pcall(save, "stopped at +" .. math.floor(lastSave) .. " KB")
  end
end

local function header(title)
  lcd.clear()
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(2, 1, title, SMLSIZE + INVERS)
end

local function drawInfo()
  header("MEMORY TEST")
  lcd.drawText(2, 12, "Lua using now: " .. math.floor(heap()) .. " KB", SMLSIZE)
  local free = freeKB()
  lcd.drawText(2, 21, "Radio free: " .. (free and (free .. " KB") or "n/a"), SMLSIZE)
  lcd.drawText(2, 30, "Frame: " .. (frameMs and (frameMs .. " ms") or "..."), SMLSIZE)
  lcd.drawText(2, 39, "Last: " .. (saved or "never run"), SMLSIZE)
  lcd.drawText(LCD_W / 2, 55, "ENTER / SA / SD: test", SMLSIZE + INVERS + CENTER)
end

local function drawFill()
  header("FILLING...")
  local got = math.floor(peak - base)
  lcd.drawText(LCD_W / 2, 16, "+" .. got .. " KB", DBLSIZE + CENTER)
  local free = freeKB()
  if free then lcd.drawText(LCD_W / 2, 36, "radio free " .. free .. " KB", SMLSIZE + CENTER) end
  lcd.drawRectangle(4, 46, LCD_W - 8, 8)
  local w = math.min(LCD_W - 10, math.floor((LCD_W - 10) * got / 160))
  if w > 0 then lcd.drawFilledRectangle(5, 47, w, 6) end
  lcd.drawText(LCD_W / 2, 56, "RTN: stop", SMLSIZE + CENTER)
end

local function drawResult()
  header("RESULT")
  local got = math.floor(peak - base)
  lcd.drawText(LCD_W / 2, 12, "Games get about", SMLSIZE + CENTER)
  lcd.drawText(LCD_W / 2, 22, got .. " KB", DBLSIZE + CENTER)
  lcd.drawText(LCD_W / 2, 41, "stop: " .. why .. ", all freed", SMLSIZE + CENTER)
  lcd.drawText(LCD_W / 2, 55, "ENTER: again  RTN: back", SMLSIZE + INVERS + CENTER)
end

local function run(event)
  if state == "fill" then
    if event == EVT_VIRTUAL_EXIT then
      finish("stopped by you")
      return 0
    end
    fill()
    if state == "fill" then drawFill() else drawResult() end
    return 0
  end

  if event == EVT_VIRTUAL_EXIT then return 1 end

  -- average time between frames, measured on the info screen
  frames = frames + 1
  if frames == 20 then
    frameMs = math.floor((getTime() - t0) * 10 / 20)
    frames, t0 = 0, getTime()
  end

  if pressed(event) then
    startTest()
    drawFill()
    return 0
  end
  if state == "result" then drawResult() else drawInfo() end
  return 0
end

return { init = init, run = run }
