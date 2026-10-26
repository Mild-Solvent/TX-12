-- Poker rules: text + scroll viewer, loaded on demand by
-- Game-Poker.lua and dropped again when the player leaves.
-- Returns function(event, dt) -> true when the viewer should close.
-- Lines starting with # are headings. Keep lines <= 20 chars.
local L = {
  "#JACKS OR BETTER",
  "Video poker: you",
  "play alone against",
  "a paytable, there",
  "are no opponents.",
  "Start: 100 credits.",
  "#A HAND, STEP BY STEP",
  "1 BET 1-5 credits:",
  "  wheel or stick",
  "  up/down. ENTER (or",
  "  SD) deals 5 cards.",
  "2 HOLD the cards you",
  "  want to keep:",
  "  wheel / stick left",
  "  -right moves the",
  "  cursor, SA (or",
  "  stick up) toggles",
  "  HOLD on that card.",
  "3 DRAW: SD or ENTER.",
  "  Each card NOT",
  "  held is replaced,",
  "  only once.",
  "4 PAY: the final 5",
  "  cards are paid by",
  "  the paytable. No",
  "  pair of jacks or",
  "  better = bet lost.",
  "#HAND RANKING",
  "Best first. Win =",
  "bet x number shown.",
  "Suits: h d c s",
  "#ROYAL FLUSH     x250",
  "A K Q J 10, all one",
  "suit:",
  "Ah Kh Qh Jh 10h",
  "Bet 5 pays 4000!",
  "#STRAIGHT FLUSH   x50",
  "5 in a row, one suit",
  "5s 6s 7s 8s 9s",
  "#FOUR OF A KIND   x25",
  "4 cards same rank",
  "9 9 9 9 + any card",
  "#FULL HOUSE        x9",
  "3 of a kind + a pair",
  "K K K + 4 4",
  "#FLUSH             x6",
  "5 cards same suit,",
  "any order:",
  "2d 6d 9d Jd Kd",
  "#STRAIGHT          x4",
  "5 in a row, any suit",
  "6 7 8 9 10",
  "A-2-3-4-5 counts,",
  "A can be low or high",
  "#THREE OF A KIND   x3",
  "3 cards same rank",
  "7 7 7 + 2 others",
  "#TWO PAIR          x2",
  "8 8 + 3 3 + any",
  "#JACKS OR BETTER   x1",
  "One pair of J, Q, K",
  "or A: Q Q 2 5 9",
  "Pays x1 = bet back.",
  "10 10 or lower pair",
  "pays nothing.",
  "#TIPS",
  "Hold any paid hand.",
  "Hold a high pair.",
  "Hold 4 to a flush or",
  "a straight, draw 1.",
  "Else hold high cards",
  "(J Q K A), draw the",
  "rest.",
  "The hint above the",
  "buttons names your",
  "hand while holding.",
  "#CONTROLS",
  "Wheel/stick: bet,",
  "  pick card",
  "SA / stick up: HOLD",
  "SD / ENTER: deal,",
  "  draw",
  "Bet screen SA: rules",
  "RTN: leave the game",
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
