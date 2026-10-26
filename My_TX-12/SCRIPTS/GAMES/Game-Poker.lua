-- toolName = TNS|Poker|TNE
---------------------------------------------------------------
-- Video Poker, Jacks or Better, for 128x64 B&W EdgeTX radios
--
-- Bet 1-5: wheel or right stick, ENTER / SD deals
-- Cards:   wheel or stick left/right picks a card,
--          SA (or stick up) holds it, SD / ENTER draws
-- Exit:    RTN / EXIT
---------------------------------------------------------------

local CW, CH, CY = 22, 27, 9
local START_CREDITS = 100
local RANKS = "A23456789TJQK"
-- 5x5 suit glyphs: hearts, diamonds, clubs, spades (25 chars each)
local GLYPHS = ".X.X." .. "XXXXX" .. "XXXXX" .. ".XXX." .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. ".XXX." .. "..X.." ..
               ".XXX." .. ".XXX." .. "XXXXX" .. "XX.XX" .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. "..X.." .. ".XXX."

local deck, pos, hand, held, cnt, vals
local state, credits, bet, cursor, result, win, armed

local function shuffle()
  for i = 1, 52 do deck[i] = i - 1 end
  for i = 52, 2, -1 do
    local j = math.random(1, i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  pos = 1
end

local function nextCard()
  local c = deck[pos] or 0
  pos = pos + 1
  return c
end

-- 9 royal flush, 8 straight flush, 7 four of a kind, 6 full house,
-- 5 flush, 4 straight, 3 three of a kind, 2 two pair, 1 jacks or better
local function evalHand(h)
  for r = 1, 13 do cnt[r] = 0 end
  local flush = true
  local s1 = math.floor((h[1] or 0) / 13)
  for i = 1, 5 do
    local c = h[i] or 0
    local r = c % 13 + 1
    cnt[r] = cnt[r] + 1
    if math.floor(c / 13) ~= s1 then flush = false end
    if r == 1 then r = 14 end
    vals[i] = r
  end
  -- insertion sort, ace high
  for i = 2, 5 do
    local v = vals[i]
    local j = i - 1
    while j >= 1 and vals[j] > v do
      vals[j + 1] = vals[j]
      j = j - 1
    end
    vals[j + 1] = v
  end
  local np, trips, quads, high = 0, 0, 0, false
  for r = 1, 13 do
    local n = cnt[r]
    if n == 4 then
      quads = quads + 1
    elseif n == 3 then
      trips = trips + 1
    elseif n == 2 then
      np = np + 1
      if r == 1 or r >= 11 then high = true end
    end
  end
  local straight = false
  if np == 0 and trips == 0 and quads == 0 then
    if vals[5] - vals[1] == 4 then
      straight = true
    elseif vals[5] == 14 and vals[4] == 5 then
      straight = true -- A-2-3-4-5
    end
  end
  if straight and flush then
    if vals[1] == 10 then return 9 end
    return 8
  end
  if quads > 0 then return 7 end
  if trips > 0 and np > 0 then return 6 end
  if flush then return 5 end
  if straight then return 4 end
  if trips > 0 then return 3 end
  if np == 2 then return 2 end
  if high then return 1 end
  return 0
end

local function handName(k)
  if k == 9 then return "ROYAL FLUSH"
  elseif k == 8 then return "STRAIGHT FLUSH"
  elseif k == 7 then return "FOUR OF A KIND"
  elseif k == 6 then return "FULL HOUSE"
  elseif k == 5 then return "FLUSH"
  elseif k == 4 then return "STRAIGHT"
  elseif k == 3 then return "THREE OF A KIND"
  elseif k == 2 then return "TWO PAIR"
  elseif k == 1 then return "JACKS OR BETTER"
  end
  return "No win"
end

local function shortName(k)
  if k == 9 then return "Royal"
  elseif k == 8 then return "StrFl"
  elseif k == 7 then return "4Kind"
  elseif k == 6 then return "FullH"
  elseif k == 5 then return "Flush"
  elseif k == 4 then return "Strt"
  elseif k == 3 then return "3Kind"
  elseif k == 2 then return "2Pair"
  end
  return "Jacks"
end

-- payout for the whole bet
local function payout(k, b)
  if k == 9 then
    if b >= 5 then return 4000 end
    return 250 * b
  elseif k == 8 then return 50 * b
  elseif k == 7 then return 25 * b
  elseif k == 6 then return 9 * b
  elseif k == 5 then return 6 * b
  elseif k == 4 then return 4 * b
  elseif k == 3 then return 3 * b
  elseif k == 2 then return 2 * b
  elseif k == 1 then return b
  end
  return 0
end

local function init()
  math.randomseed(getTime())
  deck, cnt, vals = {}, {}, {}
  hand = { 0, 0, 0, 0, 0 }
  held = { false, false, false, false, false }
  shuffle()
  for i = 1, 5 do hand[i] = nextCard() end
  credits, bet, cursor = START_CREDITS, 1, 1
  result, win = -1, 0
  state = "title"
  armed = true
end

-- "sa" / "sd" once per press, else nil. Works for buttons and toggles:
-- a switch left in a new position for 0.5 s counts as its new rest.
local swLast, swRest, swSince = {}, {}, {}
local function switchPress()
  local now = getTime()
  local pressed = nil
  for i = 1, 2 do
    local n = (i == 1) and "sa" or "sd"
    local v = getValue(n) or 0
    if swLast[n] == nil then
      swLast[n], swRest[n], swSince[n] = v, v, now
    elseif v ~= swLast[n] then
      if v ~= swRest[n] and pressed == nil then pressed = n end
      swLast[n], swSince[n] = v, now
    elseif v ~= swRest[n] and now - swSince[n] > 50 then
      swRest[n] = v
    end
  end
  return pressed
end

-- "l" "r" "u" "d" once per right stick flick, nil otherwise
local function readFlick()
  local ail = getValue("ail") or 0
  local ele = getValue("ele") or 0
  if math.abs(ail) < 300 and math.abs(ele) < 300 then
    armed = true
    return nil
  end
  if not armed then return nil end
  if math.abs(ail) > 600 and math.abs(ail) >= math.abs(ele) then
    armed = false
    return (ail > 0) and "r" or "l"
  elseif math.abs(ele) > 600 then
    armed = false
    return (ele > 0) and "u" or "d"
  end
  return nil
end

local function deal()
  shuffle()
  credits = credits - bet
  for i = 1, 5 do
    hand[i] = nextCard()
    held[i] = false
  end
  cursor = 1
  result = evalHand(hand)  -- shown as a hint while holding
  state = "hold"
  playTone(1500, 30, 0, PLAY_NOW)
end

local function drawNew()
  for i = 1, 5 do
    if not held[i] then hand[i] = nextCard() end
  end
  result = evalHand(hand)
  win = payout(result, bet)
  credits = credits + win
  state = "result"
  if win > 0 then
    playTone(2400, 200, 0, PLAY_NOW)
  else
    playTone(400, 200, 0, PLAY_NOW)
  end
end

local function drawSuit(x, y, s, k)
  if s < 1 or s > 4 then return end
  local base = (s - 1) * 25
  for r = 0, 4 do
    for c = 0, 4 do
      local i = base + r * 5 + c + 1
      if string.sub(GLYPHS, i, i) == "X" then
        lcd.drawFilledRectangle(x + c * k, y + r * k, k, k)
      end
    end
  end
end

local function drawCard(i)
  local x = 3 + (i - 1) * 25
  local c = hand[i] or 0
  local r = c % 13 + 1
  local t = string.sub(RANKS, r, r)
  if r == 10 then t = "10" end
  lcd.drawRectangle(x, CY, CW, CH)
  lcd.drawText(x + 2, CY + 2, t, MIDSIZE)
  local s = math.floor(c / 13) + 1
  if r ~= 10 then drawSuit(x + 15, CY + 3, s, 1) end
  drawSuit(x + 6, CY + 15, s, 2)
  if state == "hold" or state == "result" then
    if held[i] then lcd.drawText(x + 1, CY + CH + 1, "HOLD", SMLSIZE + INVERS) end
  end
  if state == "hold" and i == cursor then
    lcd.drawRectangle(x - 1, CY - 1, CW + 2, CH + 2)
    lcd.drawFilledRectangle(x, CY + CH + 9, CW, 2)
  end
end

local function drawHeader()
  lcd.drawText(1, 0, "Credits " .. credits, SMLSIZE)
  lcd.drawText(LCD_W - 1, 0, "Bet " .. bet, SMLSIZE + RIGHT)
end

local function drawPaytable()
  for k = 9, 1, -1 do
    local idx = 9 - k
    local col = math.floor(idx / 5)
    local row = idx % 5
    local x = 2 + col * 64
    local y = 9 + row * 8
    lcd.drawText(x, y, shortName(k), SMLSIZE)
    lcd.drawText(x + 60, y, tostring(payout(k, bet)), SMLSIZE + RIGHT)
  end
  lcd.drawLine(0, 49, LCD_W - 1, 49, SOLID, FORCE)
  lcd.drawText(1, 52, "+/- bet  ENTER deal", SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local sw = switchPress()
  local fl = readFlick()
  local enter = (event == EVT_VIRTUAL_ENTER)
  local nxt = (event == EVT_VIRTUAL_NEXT)
  local prv = (event == EVT_VIRTUAL_PREV)

  lcd.clear()
  if state == "title" then
    lcd.drawText(LCD_W / 2 - 22, 2, "POKER", MIDSIZE + INVERS)
    lcd.drawText(2, 18, "Jacks or Better", SMLSIZE)
    lcd.drawText(2, 28, "Wheel/stick: card", SMLSIZE)
    lcd.drawText(2, 37, "SA hold   SD draw", SMLSIZE)
    lcd.drawText(2, 52, "ENTER to start", SMLSIZE + BLINK)
    if enter or sw then state = "bet" end
  elseif state == "bet" then
    local maxb = math.min(5, credits)
    if nxt or fl == "r" or fl == "u" then bet = bet + 1 end
    if prv or fl == "l" or fl == "d" then bet = bet - 1 end
    if bet > maxb then bet = maxb end
    if bet < 1 then bet = 1 end
    if enter or sw == "sd" then
      deal()
    else
      drawHeader()
      drawPaytable()
    end
  elseif state == "hold" then
    if nxt or fl == "r" then cursor = cursor % 5 + 1 end
    if prv or fl == "l" then cursor = (cursor + 3) % 5 + 1 end
    if sw == "sa" or fl == "u" then
      held[cursor] = not held[cursor]
      playTone(held[cursor] and 2000 or 1000, 20, 0, PLAY_NOW)
    elseif sw == "sd" or enter then
      drawNew()
    end
  elseif state == "result" then
    if enter or sw then
      if credits < 1 then
        state = "over"
      else
        state = "bet"
      end
    end
  else
    lcd.drawText(LCD_W / 2 - 40, 10, "OUT OF CREDITS", SMLSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 30, "ENTER to restart", SMLSIZE)
    if enter then
      credits, bet = START_CREDITS, 1
      state = "bet"
    end
  end

  if state == "hold" or state == "result" then
    drawHeader()
    for i = 1, 5 do drawCard(i) end
    if state == "hold" then
      if result > 0 then
        lcd.drawText(1, 48, handName(result), SMLSIZE)
      else
        lcd.drawText(1, 48, "Pick cards to hold", SMLSIZE)
      end
      lcd.drawText(1, 56, "SA hold  SD draw", SMLSIZE)
    else
      if win > 0 then
        lcd.drawText(1, 48, handName(result) .. " +" .. win, SMLSIZE + INVERS)
      else
        lcd.drawText(1, 48, "No win", SMLSIZE)
      end
      lcd.drawText(1, 56, "ENTER: next hand", SMLSIZE)
    end
  end
  return 0
end

return { init = init, run = run }
