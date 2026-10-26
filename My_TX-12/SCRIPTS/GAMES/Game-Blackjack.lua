-- toolName = TNS|Blackjack|TNE
---------------------------------------------------------------
-- Blackjack (21), 1-4 players hot-seat, 128x64 B&W EdgeTX
-- Menu: wheel/stick moves, ENTER picks (players 1-4, rules)
-- Bet:  wheel or stick, ENTER (or SA / SD) confirms
-- Play: SA (stick right) Hit, SD (stick left) Stand, stick up Double
-- Rules text: /SCRIPTS/GAMES/BLACKJACK/rules.lua (loaded on demand)
---------------------------------------------------------------

local CW, CH = 14, 16
local AREA_W = 86
local DEALER_Y, PLAYER_Y = 0, 18
local START_BANK = 100
local MIN_BET, MAX_BET, BET_STEP = 5, 100, 5
local RANKS = "A23456789TJQK"
local RULES = "/SCRIPTS/GAMES/BLACKJACK/rules.lua"
-- 5x5 suit glyphs: hearts, diamonds, clubs, spades (25 chars each)
local GLYPHS = ".X.X." .. "XXXXX" .. "XXXXX" .. ".XXX." .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. ".XXX." .. "..X.." ..
               ".XXX." .. ".XXX." .. "XXXXX" .. "XX.XX" .. "..X.." ..
               "..X.." .. ".XXX." .. "XXXXX" .. "..X.." .. ".XXX."

local deck, pos, dealer
local np, cur, bank, bet, stake, hands, res, out
local state, msg, hideHole, timer, lastTime, armed, menu
local rules, rback

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

local function totalText(h)
  if #h == 0 then return "-" end
  local v, soft = handValue(h)
  if soft and v < 21 then return "s" .. v end
  return tostring(v)
end

local function name(p)
  if np == 1 then return "You" end
  return "P" .. p
end

local function init()
  math.randomseed(getTime())
  deck = {}
  shuffle()
  dealer = {}
  np, cur, menu = 1, 1, 1
  bank, bet, stake, hands, res, out = {}, {}, {}, {}, {}, {}
  for p = 1, 4 do
    bank[p], bet[p], stake[p], hands[p], res[p], out[p] = START_BANK, 10, 10, {}, "", false
  end
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

-- next player after p still in the game, nil if none
local function nextIn(p)
  for q = p + 1, np do
    if not out[q] then return q end
  end
  return nil
end

local function maxBet(p)
  return math.min(MAX_BET, bank[p] or 0)
end

local function changeBet(d)
  local b = (bet[cur] or MIN_BET) + d * BET_STEP
  if b > maxBet(cur) then b = maxBet(cur) end
  if b < MIN_BET then b = MIN_BET end
  bet[cur] = b
end

-- settle player p; sets res[p] (non-empty = settled)
local function finish(p, r, text)
  local s = stake[p] or 0
  if r == "bj" then
    local w = math.floor(s * 3 / 2)
    bank[p] = bank[p] + s + w
    res[p] = "BJ +" .. w
    playTone(2600, 200, 0, PLAY_NOW)
  elseif r == "win" then
    bank[p] = bank[p] + s * 2
    res[p] = text .. " +" .. s
    playTone(2200, 150, 0, PLAY_NOW)
  elseif r == "push" then
    bank[p] = bank[p] + s
    res[p] = "Push"
    playTone(1200, 80, 0, PLAY_NOW)
  else
    res[p] = text .. " -" .. s
    playTone(300, 250, 0, PLAY_NOW)
  end
end

local function toResult()
  hideHole = false
  state = "result"
  if np == 1 then
    msg = res[1] or ""
    if msg == "Push" then msg = "Push - bet back" end
    if string.sub(msg, 1, 2) == "BJ" then msg = "BLACKJACK!" .. string.sub(msg, 3) end
  else
    msg = "Round over"
  end
end

-- after the dealer has drawn: settle everyone still standing
local function settleAll()
  local dv = handValue(dealer)
  for p = 1, np do
    if not out[p] and res[p] == "" then
      local pv = handValue(hands[p])
      if dv > 21 or pv > dv then
        finish(p, "win", "Win")
      elseif pv == dv then
        finish(p, "push")
      else
        finish(p, "lose", "Lose")
      end
    end
  end
  toResult()
end

local function toDealer()
  hideHole = false
  local need = false
  for p = 1, np do
    if not out[p] and res[p] == "" then need = true end
  end
  if not need then
    toResult()
    return
  end
  state = "dealer"
  timer = 0.6
  msg = "Dealer plays..."
end

local function playMsg()
  if np == 1 then
    msg = "Hit or Stand?"
  else
    msg = name(cur) .. ": Hit or Stand?"
  end
end

-- current player is finished: next player or dealer
local function advance()
  local q = cur
  local found = nil
  for i = 1, np do
    q = nextIn(q)
    if q == nil then break end
    if res[q] == "" then found = q break end
  end
  if found then
    cur = found
    state = "play"
    playMsg()
  else
    toDealer()
  end
end

-- end of cur's turn: pause in multiplayer so everyone sees it
local function endTurn(text)
  if np > 1 then
    msg = name(cur) .. ": " .. text
    state = "turnend"
    timer = 1.5
  else
    advance()
  end
end

local function deal()
  if pos + (np + 1) * 5 > 52 then shuffle() end
  dealer = {}
  for p = 1, np do
    hands[p] = {}
    res[p] = ""
    if not out[p] then
      stake[p] = bet[p]
      bank[p] = bank[p] - stake[p]
    end
  end
  for k = 1, 2 do
    for p = 1, np do
      if not out[p] then take(hands[p]) end
    end
    take(dealer)
  end
  hideHole = true
  local dbj = handValue(dealer) == 21
  for p = 1, np do
    if not out[p] then
      local pv = handValue(hands[p])
      if pv == 21 and dbj then
        finish(p, "push")
      elseif pv == 21 then
        finish(p, "bj")
      elseif dbj then
        finish(p, "lose", "Lose")
      end
    end
  end
  if dbj then
    toResult()
    return
  end
  cur = 0
  advance()
end

local function hit()
  local h = hands[cur]
  take(h)
  playTone(1500, 20, 0, PLAY_NOW)
  local pv = handValue(h)
  if pv > 21 then
    finish(cur, "lose", "Bust")
    endTurn("Bust!")
  elseif pv == 21 then
    endTurn("21!")
  else
    playMsg()
  end
end

local function canDouble()
  return #hands[cur] == 2 and bank[cur] >= stake[cur]
end

local function double()
  if not canDouble() then return end
  bank[cur] = bank[cur] - stake[cur]
  stake[cur] = stake[cur] * 2
  take(hands[cur])
  playTone(1800, 40, 0, PLAY_NOW)
  if handValue(hands[cur]) > 21 then
    finish(cur, "lose", "Bust")
    endTurn("Bust!")
  else
    endTurn("Doubled " .. handValue(hands[cur]))
  end
end

local function dealerStep(dt)
  timer = timer - dt
  if timer > 0 then return end
  if handValue(dealer) < 17 then
    take(dealer)
    playTone(1300, 20, 0, PLAY_NOW)
    timer = 0.5
    return
  end
  settleAll()
end

-- after a round: who is broke, who bets first
local function nextRound()
  local first = nil
  for p = np, 1, -1 do
    if bank[p] < MIN_BET then out[p] = true end
    if not out[p] then
      first = p
      if bet[p] > maxBet(p) then bet[p] = maxBet(p) end
      if bet[p] < MIN_BET then bet[p] = MIN_BET end
    end
  end
  if first == nil then
    state = "over"
    playTone(200, 400, 0, PLAY_NOW)
  else
    cur = first
    state = "bet"
  end
end

local function newGame()
  for p = 1, 4 do
    bank[p], bet[p], stake[p], hands[p], res[p] = START_BANK, 10, 10, {}, ""
    out[p] = p > np
  end
  dealer = {}
  shuffle()
  cur = 1
  state = "bet"
end

-- rules.lua returns a viewer function(event, dt) -> true when done
local function openRules()
  local ok, chunk = pcall(loadScript, RULES)
  local f = nil
  if ok and chunk then ok, f = pcall(chunk) end
  if type(f) ~= "function" then
    f = function(e)
      lcd.drawText(0, 0, "Missing " .. RULES, SMLSIZE)
      return e == EVT_VIRTUAL_ENTER
    end
  end
  rules, rback = f, state
  state = "rules"
end

local function closeRules()
  rules = nil
  collectgarbage()
  state = rback or "title"
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
  drawSuit(x + 5, y + 9, math.floor(c / 13) + 1)
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

local function dealerText()
  if #dealer == 0 then return "" end
  if hideHole then
    local r = (dealer[1] or 0) % 13 + 1
    local v = r
    if r == 1 then v = 11 elseif r > 10 then v = 10 end
    return "D " .. v .. "+?"
  end
  return "D " .. handValue(dealer)
end

-- dealer + the active player's cards; others as totals on the right
local function drawTable()
  local h = hands[cur] or {}
  drawHand(dealer, DEALER_Y, hideHole)
  drawHand(h, PLAYER_Y, false)
  lcd.drawLine(AREA_W + 2, 0, AREA_W + 2, 34, SOLID, FORCE)
  local x = AREA_W + 5
  lcd.drawText(x, 0, dealerText(), SMLSIZE)
  local row = 1
  for p = 1, np do
    if p ~= cur and row <= 3 then
      local t = "out"
      if not out[p] then t = totalText(hands[p] or {}) end
      lcd.drawText(x, row * 9, "P" .. p .. " " .. t, SMLSIZE)
      row = row + 1
    end
  end
  lcd.drawLine(0, 35, LCD_W - 1, 35, SOLID, FORCE)
  lcd.drawText(1, 37, name(cur) .. " " .. totalText(h), SMLSIZE)
  lcd.drawText(LCD_W - 1, 37, "Bk" .. (bank[cur] or 0) .. " Bet" .. (stake[cur] or 0), SMLSIZE + RIGHT)
end

-- multiplayer dealer/result view: dealer cards + one line per player
local function drawSummary()
  drawHand(dealer, DEALER_Y, hideHole)
  lcd.drawText(AREA_W + 5, 0, dealerText(), SMLSIZE)
  for p = 1, np do
    local y = 11 + p * 8
    local t = "P" .. p .. " "
    if out[p] then
      t = t .. "out"
    else
      t = t .. totalText(hands[p] or {}) .. " " .. (res[p] or "")
    end
    lcd.drawText(1, y, t, SMLSIZE)
    lcd.drawText(LCD_W - 1, y, tostring(bank[p] or 0), SMLSIZE + RIGHT)
  end
end

local function hint(t)
  lcd.drawText(1, 56, t, SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    if state == "rules" then
      closeRules()
      event = 0
    else
      return 2
    end
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local sw = switchPress()
  local fl = readFlick()
  local enter = (event == EVT_VIRTUAL_ENTER)

  lcd.clear()
  if state == "rules" then
    local ok, done = pcall(rules, event, dt)
    if ok and not done then return 0 end
    closeRules()
    lcd.clear()
    enter, sw = false, nil
  end

  if state == "title" then
    if event == EVT_VIRTUAL_NEXT or fl == "d" then menu = menu % 3 + 1 end
    if event == EVT_VIRTUAL_PREV or fl == "u" then menu = (menu + 1) % 3 + 1 end
    if menu == 2 then
      if fl == "r" and np < 4 then np = np + 1 end
      if fl == "l" and np > 1 then np = np - 1 end
    end
    if enter or sw then
      if menu == 1 then
        newGame()
        event, enter, sw, fl = 0, false, nil, nil
      elseif menu == 2 then
        np = np % 4 + 1
      else
        openRules()
        return 0
      end
    end
  end
  if state == "title" then
    lcd.drawText(LCD_W / 2 - 34, 1, "BLACKJACK", MIDSIZE + INVERS)
    for i = 1, 3 do
      local t = "Start game"
      if i == 2 then t = "Players: " .. np .. "  <>"
      elseif i == 3 then t = "Rules" end
      local f = SMLSIZE
      if i == menu then f = f + INVERS end
      lcd.drawText(20, 10 + i * 10, t, f)
    end
    hint("Whl/stk move ENT ok")
  end

  if state == "bet" then
    if event == EVT_VIRTUAL_NEXT or fl == "r" or fl == "u" then changeBet(1) end
    if event == EVT_VIRTUAL_PREV or fl == "l" or fl == "d" then changeBet(-1) end
    if enter or sw then
      local q = nextIn(cur)
      if q then
        cur = q
        playTone(1500, 20, 0, PLAY_NOW)
      else
        deal()
      end
    end
  elseif state == "play" then
    if sw == "sa" or fl == "r" then
      hit()
    elseif sw == "sd" or fl == "l" then
      endTurn("Stand " .. handValue(hands[cur]))
    elseif fl == "u" then
      double()
    end
  elseif state == "turnend" then
    timer = timer - dt
    if timer <= 0 or enter or sw then advance() end
  elseif state == "dealer" then
    dealerStep(dt)
  elseif state == "result" then
    if enter or sw then nextRound() end
  elseif state == "over" then
    if enter or sw then state = "title" end
  end

  -- draw the (possibly new) state
  if state == "bet" then
    local t = "BET " .. (bet[cur] or 0)
    if np > 1 then t = name(cur) .. " " .. t end
    lcd.drawText(2, 2, t, MIDSIZE)
    lcd.drawText(2, 20, "Bank " .. (bank[cur] or 0) .. "  Max " .. maxBet(cur), SMLSIZE)
    if np > 1 then
      local s = ""
      for p = 1, np do
        local b = out[p] and "--" or tostring(bank[p] or 0)
        s = s .. p .. ":" .. b .. " "
      end
      lcd.drawText(2, 32, s, SMLSIZE)
    end
    lcd.drawLine(0, 53, LCD_W - 1, 53, SOLID, FORCE)
    if nextIn(cur) then hint("Whl/stk bet ENT next") else hint("Whl/stk bet ENT deal") end
  elseif state == "play" or state == "turnend" or (np == 1 and (state == "dealer" or state == "result")) then
    drawTable()
    local f = SMLSIZE
    if state == "result" or state == "turnend" then f = f + INVERS end
    lcd.drawText(1, 46, msg, f)
    if state == "play" then
      local h = "SA Hit  SD Stand"
      if canDouble() then h = "SA Hit SD Stand ^Dbl" end
      hint(h)
    elseif state == "turnend" then
      hint("ENT: next player")
    elseif state == "result" then
      hint("ENT/SA/SD: next hand")
    else
      hint("Dealer draws to 17")
    end
  elseif state == "dealer" or state == "result" then
    drawSummary()
    if state == "result" then
      hint("ENT/SA/SD: next round")
    else
      hint("Dealer plays...")
    end
  elseif state == "over" then
    local t = "BROKE!"
    if np > 1 then t = "ALL BROKE!" end
    lcd.drawText(LCD_W / 2 - 30, 10, t, MIDSIZE + INVERS)
    lcd.drawText(LCD_W / 2 - 36, 32, "Game over", SMLSIZE)
    hint("ENTER: back to menu")
  end
  return 0
end

return { init = init, run = run }
