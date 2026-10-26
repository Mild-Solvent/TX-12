-- toolName = TNS|Blackjack|TNE
---------------------------------------------------------------
-- Blackjack (21) for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Bet:   wheel or right stick, ENTER (or SA / SD) deals
-- Play:  SA = Hit, SD = Stand, flick stick up = Double down
--        (stick right = Hit, stick left = Stand work too)
-- Dealer stands on 17, Blackjack pays 3:2
-- Exit:  RTN / EXIT
---------------------------------------------------------------

local CW, CH = 14, 18     -- card size
local AREA_W = 94         -- width for a row of cards
local DEALER_Y, PLAYER_Y = 1, 22
local START_BANK = 100
local MIN_BET, MAX_BET, BET_STEP = 5, 100, 5
local RANKS = "A23456789TJQK"
-- 5x5 suit glyphs: hearts, diamonds, clubs, spades (25 chars each)
local GLYPHS = ".X.X." .. "XXXXX" .. "XXXXX" .. ".XXX." .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. ".XXX." .. "..X.." ..
               ".XXX." .. ".XXX." .. "XXXXX" .. "XX.XX" .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. "..X.." .. ".XXX."

local deck, pos, player, dealer
local state, bank, bet, stake, msg, hideHole, timer, lastTime, armed

local function shuffle()
  for i = 1, 52 do deck[i] = i - 1 end
  for i = 52, 2, -1 do
    local j = math.random(1, i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  pos = 1
end

local function take(h)
  if pos > 52 then shuffle() end
  h[#h + 1] = deck[pos] or 0
  pos = pos + 1
end

-- returns total, soft
local function handValue(h)
  local sum, aces = 0, 0
  for i = 1, #h do
    local r = (h[i] or 0) % 13 + 1
    if r == 1 then
      aces = aces + 1
      sum = sum + 1
    elseif r >= 10 then
      sum = sum + 10
    else
      sum = sum + r
    end
  end
  if aces > 0 and sum + 10 <= 21 then return sum + 10, true end
  return sum, false
end

local function init()
  math.randomseed(getTime())
  deck = {}
  shuffle()
  player, dealer = {}, {}
  bank, bet, stake = START_BANK, 10, 10
  state = "title"
  msg = ""
  hideHole = true
  timer = 0
  armed = true
  lastTime = getTime()
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

local function maxBet()
  return math.min(MAX_BET, bank)
end

local function changeBet(d)
  bet = bet + d * BET_STEP
  if bet > maxBet() then bet = maxBet() end
  if bet < MIN_BET then bet = MIN_BET end
end

local function finish(res, text)
  hideHole = false
  if res == "bj" then
    local w = math.floor(stake * 3 / 2)
    bank = bank + stake + w
    msg = "BLACKJACK! +" .. w
    playTone(2600, 200, 0, PLAY_NOW)
  elseif res == "win" then
    bank = bank + stake * 2
    msg = text .. " +" .. stake
    playTone(2200, 150, 0, PLAY_NOW)
  elseif res == "push" then
    bank = bank + stake
    msg = "Push - bet back"
    playTone(1200, 80, 0, PLAY_NOW)
  else
    msg = text .. " -" .. stake
    playTone(300, 250, 0, PLAY_NOW)
  end
  state = "result"
end

local function deal()
  if pos > 36 then shuffle() end
  stake = bet
  bank = bank - stake
  player, dealer = {}, {}
  take(player)
  take(dealer)
  take(player)
  take(dealer)
  hideHole = true
  local pv = handValue(player)
  local dv = handValue(dealer)
  if pv == 21 and dv == 21 then
    finish("push")
  elseif pv == 21 then
    finish("bj")
  elseif dv == 21 then
    finish("lose", "Dealer 21")
  else
    state = "play"
    msg = "Hit or Stand?"
  end
end

local function toDealer()
  hideHole = false
  state = "dealer"
  timer = 0.6
  msg = "Dealer plays..."
end

local function hit()
  take(player)
  playTone(1500, 20, 0, PLAY_NOW)
  local pv = handValue(player)
  if pv > 21 then
    finish("lose", "Bust!")
  elseif pv == 21 then
    toDealer()
  else
    msg = "Hit or Stand?"
  end
end

local function double()
  if #player ~= 2 or bank < stake then return end
  bank = bank - stake
  stake = stake * 2
  take(player)
  playTone(1800, 40, 0, PLAY_NOW)
  if handValue(player) > 21 then
    finish("lose", "Bust!")
  else
    toDealer()
  end
end

local function dealerStep(dt)
  timer = timer - dt
  if timer > 0 then return end
  local dv = handValue(dealer)
  if dv < 17 then
    take(dealer)
    playTone(1300, 20, 0, PLAY_NOW)
    timer = 0.5
    return
  end
  local pv = handValue(player)
  if dv > 21 then
    finish("win", "Dealer busts")
  elseif pv > dv then
    finish("win", "You win")
  elseif pv == dv then
    finish("push")
  else
    finish("lose", "Dealer wins")
  end
end

local function drawSuit(x, y, s)
  if s < 1 or s > 4 then return end
  local base = (s - 1) * 25
  for r = 0, 4 do
    for c = 0, 4 do
      local i = base + r * 5 + c + 1
      if string.sub(GLYPHS, i, i) == "X" then
        lcd.drawFilledRectangle(x + c, y + r, 1, 1)
      end
    end
  end
end

local function drawCard(x, y, c, hidden)
  lcd.drawFilledRectangle(x, y, CW, CH, ERASE)
  lcd.drawRectangle(x, y, CW, CH)
  if hidden then
    lcd.drawFilledRectangle(x + 2, y + 2, CW - 4, CH - 4)
    return
  end
  local r = c % 13 + 1
  local t = string.sub(RANKS, r, r)
  if r == 10 then t = "10" end
  lcd.drawText(x + 2, y + 2, t, SMLSIZE)
  drawSuit(x + 5, y + 11, math.floor(c / 13) + 1)
end

local function drawHand(h, y, hideSecond)
  local n = #h
  if n == 0 then return end
  local step = CW + 2
  if n > 1 and (n - 1) * step + CW > AREA_W then
    step = math.floor((AREA_W - CW) / (n - 1))
  end
  for i = 1, n do
    drawCard((i - 1) * step, y, h[i] or 0, hideSecond and i == 2)
  end
end

local function drawTable()
  lcd.clear()
  drawHand(dealer, DEALER_Y, hideHole)
  drawHand(player, PLAYER_Y, false)
  lcd.drawLine(AREA_W + 2, 0, AREA_W + 2, 40, SOLID, FORCE)
  lcd.drawText(AREA_W + 5, 1, "DLR", SMLSIZE)
  if #dealer > 0 then
    if hideHole then
      local r = (dealer[1] or 0) % 13 + 1
      local v = r
      if r == 1 then v = 11 elseif r > 10 then v = 10 end
      lcd.drawText(AREA_W + 5, 9, v .. "+?", SMLSIZE)
    else
      lcd.drawText(AREA_W + 5, 9, tostring(handValue(dealer)), SMLSIZE)
    end
  end
  lcd.drawText(AREA_W + 5, 22, "YOU", SMLSIZE)
  if #player > 0 then
    local pv, soft = handValue(player)
    local t = tostring(pv)
    if soft and pv < 21 then t = "s" .. pv end
    lcd.drawText(AREA_W + 5, 30, t, SMLSIZE)
  end
  lcd.drawLine(0, 41, LCD_W - 1, 41, SOLID, FORCE)
  lcd.drawText(1, 44, "Bank " .. bank, SMLSIZE)
  lcd.drawText(LCD_W - 1, 44, "Bet " .. stake, SMLSIZE + RIGHT)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local sw = switchPress()
  local fl = readFlick()
  local enter = (event == EVT_VIRTUAL_ENTER)

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 34, 4, "BLACKJACK", MIDSIZE + INVERS)
    lcd.drawText(4, 24, "SA Hit   SD Stand", SMLSIZE)
    lcd.drawText(4, 33, "Stick up: Double", SMLSIZE)
    lcd.drawText(4, 42, "Wheel/stick: bet", SMLSIZE)
    lcd.drawText(4, 54, "ENTER to start", SMLSIZE + BLINK)
    if enter or sw then state = "bet" end
  elseif state == "bet" then
    if event == EVT_VIRTUAL_NEXT or fl == "r" or fl == "u" then changeBet(1) end
    if event == EVT_VIRTUAL_PREV or fl == "l" or fl == "d" then changeBet(-1) end
    if enter or sw then
      deal()
      drawTable()
    else
      lcd.clear()
      lcd.drawText(LCD_W / 2 - 30, 6, "BET " .. bet, MIDSIZE)
      lcd.drawText(4, 24, "Wheel/stick: +/- " .. BET_STEP, SMLSIZE)
      lcd.drawText(4, 33, "ENTER deals", SMLSIZE)
      lcd.drawLine(0, 41, LCD_W - 1, 41, SOLID, FORCE)
      lcd.drawText(1, 44, "Bank " .. bank, SMLSIZE)
      lcd.drawText(LCD_W - 1, 44, "Max " .. maxBet(), SMLSIZE + RIGHT)
    end
  elseif state == "play" then
    if sw == "sa" or fl == "r" then
      hit()
    elseif sw == "sd" or fl == "l" then
      toDealer()
    elseif fl == "u" then
      double()
    end
    drawTable()
  elseif state == "dealer" then
    dealerStep(dt)
    drawTable()
  elseif state == "result" then
    if enter or sw then
      if bank < MIN_BET then
        state = "over"
        playTone(200, 400, 0, PLAY_NOW)
      else
        if bet > maxBet() then bet = maxBet() end
        state = "bet"
      end
    end
    drawTable()
  else
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 22, 10, "BROKE!", MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 30, 32, "Bank " .. bank, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 36, 44, "ENTER to restart", SMLSIZE)
    if enter then
      bank, bet, stake = START_BANK, 10, 10
      player, dealer = {}, {}
      shuffle()
      state = "bet"
    end
  end

  if state == "play" or state == "dealer" or state == "result" then
    local flags = SMLSIZE
    if state == "result" then flags = flags + INVERS end
    lcd.drawText(1, 54, msg, flags)
    if state == "play" then
      local h = "SA/SD"
      if #player == 2 and bank >= stake then h = "Up=Dbl" end
      lcd.drawText(LCD_W - 1, 54, h, SMLSIZE + RIGHT)
    end
  end
  return 0
end

return { init = init, run = run }
