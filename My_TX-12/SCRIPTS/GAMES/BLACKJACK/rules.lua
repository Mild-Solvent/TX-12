-- Blackjack rules: text + scroll viewer, loaded on demand by
-- Game-Blackjack.lua and dropped again when the player leaves.
-- Returns function(event, dt) -> true when the viewer should close.
-- Lines starting with # are headings. Keep lines <= 20 chars.
local L = {
  "#BLACKJACK RULES",
  "Get closer to 21",
  "than the dealer",
  "without going over.",
  "Over 21 = bust, you",
  "lose at once.",
  "#CARD VALUES",
  "2-10 = face value",
  "J, Q, K = 10",
  "A = 1 or 11 (best)",
  "s17 = soft 17: an",
  "ace counts as 11.",
  "#A ROUND",
  "1 Each player bets",
  "  (wheel or stick,",
  "  ENTER confirms).",
  "2 Everyone gets 2",
  "  cards, the dealer",
  "  2 (one face down).",
  "3 Players act in",
  "  turn, P1 first.",
  "4 Dealer shows the",
  "  hidden card and",
  "  draws to 16,",
  "  stands on 17+.",
  "5 Higher total wins.",
  "#YOUR TURN",
  "SA / stick right:",
  "  HIT - take a card",
  "SD / stick left:",
  "  STAND - stop",
  "Stick up: DOUBLE -",
  "  bet x2, take one",
  "  card, then stop",
  "  (first 2 cards).",
  "#PAYOUTS",
  "Win: 1 to 1",
  "Blackjack (A + 10/J",
  "/Q/K as first two",
  "cards): 3 to 2",
  "Tie: push, bet back",
  "Dealer blackjack",
  "beats everyone",
  "except a player BJ.",
  "#PLAYERS 1-4",
  "Pick in the menu.",
  "Hot-seat: pass the",
  "radio. Each player",
  "has an own bank",
  "(starts at 100) and",
  "bet. Active hand is",
  "shown big, others",
  "as totals right.",
  "Bank under 5 = out.",
  "All out = game over.",
  "#CONTROLS",
  "Wheel / stick: bet",
  "ENTER/SA/SD: deal,",
  "  next hand",
  "RTN: leave game",
  "(here: close rules)",
}

local top, rep = 1, 0

return function(event, dt)
  if event == EVT_VIRTUAL_ENTER then return true end
  local n = #L
  local maxTop = math.max(1, n - 6)
  local ele = getValue("ele") or 0
  if event == EVT_VIRTUAL_NEXT then top = top + 1 end
  if event == EVT_VIRTUAL_PREV then top = top - 1 end
  if math.abs(ele) > 600 then
    rep = rep - (dt or 0)
    if rep <= 0 then
      if ele > 0 then top = top - 1 else top = top + 1 end
      rep = 0.15
    end
  else
    rep = 0
  end
  if top > maxTop then top = maxTop end
  if top < 1 then top = 1 end
  for i = 0, 6 do
    local s = L[top + i]
    if type(s) == "string" then
      if string.sub(s, 1, 1) == "#" then
        lcd.drawText(0, i * 8, string.sub(s, 2), SMLSIZE + INVERS)
      else
        lcd.drawText(0, i * 8, s, SMLSIZE)
      end
    end
  end
  if maxTop > 1 then
    local y = math.floor((top - 1) * 48 / (maxTop - 1))
    lcd.drawLine(126, 0, 126, 55, DOTTED, FORCE)
    lcd.drawFilledRectangle(125, y, 3, 7, FORCE)
  end
  lcd.drawText(0, 57, "Whl/stk move ENT back", SMLSIZE + INVERS)
  return false
end
