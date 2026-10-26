-- Tamagotchi mini-games, loaded on demand by Game-Tamagotchi.lua.
-- Returns { start(kind), step(event, sw, dt), draw() }.
-- step returns nil while playing, then 1 (won) or 0 (lost).
-- 1 Which way?   guess where the pet will look (5 rounds, 3 to win)
-- 2 Catch treats move with a stick, 15 s, catch 6 to win
-- 3 Stop the bar press near the middle, 3 tries, 2 hits to win

local kind, phase, ph, round, score, won
local a, b, c, d, armed, tleft

local function stick()
  local h, r = getValue("ail"), getValue("rud")
  if math.abs(r) > math.abs(h) then return r end
  return h
end

local function start(k)
  kind = k
  if kind ~= 2 and kind ~= 3 then kind = 1 end
  phase, ph, round, score, won = "play", 0, 1, 0, false
  armed, tleft = false, 15
  a, b, c, d = 64, 1, 0, 0
  if kind == 2 then b, c = math.random(10, 118), 10 end
  if kind == 3 then a, b = 0, 1 end
end

local function finish(w)
  won = w
  phase, ph = "end", 1.6
  if w then
    playTone(1500, 80, 0, PLAY_NOW)
    playTone(2500, 150, 100, 0)
  else
    playTone(500, 200, 0, PLAY_NOW)
  end
end

local function show(hit, t)
  phase, ph = "show", t
  if hit then
    score = score + 1
    playTone(2200, 50, 0, PLAY_NOW)
  else
    playTone(400, 80, 0, PLAY_NOW)
  end
end

-- after a shown result: next round or the end
local function nextRound(rounds, need)
  round = round + 1
  if round > rounds then finish(score >= need) else phase = "play" end
end

local function step(event, sw, dt)
  if phase == "end" then
    ph = ph - dt
    if ph <= 0 then return won and 1 or 0 end
    return nil
  end
  if phase == "show" then
    ph = ph - dt
    if ph <= 0 then
      if kind == 1 then nextRound(5, 3) else nextRound(3, 2) end
    end
    return nil
  end
  local s = stick()
  if kind == 1 then
    local g = 0
    if math.abs(s) < 300 then armed = true end
    if event == EVT_VIRTUAL_PREV or sw == "sa" then g = 1 end
    if event == EVT_VIRTUAL_NEXT or sw == "sd" then g = 2 end
    if g == 0 and armed and s < -600 then g = 1 end
    if g == 0 and armed and s > 600 then g = 2 end
    if g > 0 then
      armed = false
      a, b = g, math.random(2)
      show(a == b, 0.9)
    end
  elseif kind == 2 then
    tleft = tleft - dt
    if math.abs(s) > 100 then a = 64 + s * 56 / 1024 end
    if event == EVT_VIRTUAL_NEXT then a = a + 12 end
    if event == EVT_VIRTUAL_PREV then a = a - 12 end
    if a < 8 then a = 8 end
    if a > 120 then a = 120 end
    c = c + (25 + score * 3) * dt
    if c >= 50 then
      if math.abs(b - a) <= 9 then
        score = score + 1
        playTone(2200, 30, 0, PLAY_NOW)
      else
        playTone(400, 40, 0, PLAY_NOW)
      end
      b, c = math.random(10, 118), 10
    end
    if tleft <= 0 then finish(score >= 6) end
  else
    a = a + b * (70 + 30 * round) * dt
    if a >= 100 then a, b = 100, -1 end
    if a <= 0 then a, b = 0, 1 end
    if event == EVT_VIRTUAL_ENTER or sw then
      d = math.floor(math.abs(a - 50) + 0.5)
      show(d <= 8, 1.0)
    end
  end
  return nil
end

local function face(x, y, look)
  lcd.drawRectangle(x, y, 26, 20)
  local dx = 0
  if look == 1 then dx = -2 elseif look == 2 then dx = 2 end
  lcd.drawFilledRectangle(x + 7 + dx, y + 6, 2, 3, FORCE)
  lcd.drawFilledRectangle(x + 17 + dx, y + 6, 2, 3, FORCE)
  lcd.drawLine(x + 10, y + 14, x + 15, y + 14, SOLID, FORCE)
end

local function draw()
  if phase == "end" then
    lcd.drawText(64, 14, won and "You won!" or "Nice try!", MIDSIZE + CENTER)
    lcd.drawText(64, 34, "Score " .. score, SMLSIZE + CENTER)
    lcd.drawText(64, 46, won and "Joy +30" or "Joy +12", SMLSIZE + CENTER)
    return
  end
  if kind == 1 then
    lcd.drawText(1, 0, "Which way?", SMLSIZE + INVERS)
    lcd.drawText(127, 0, "Round " .. round .. "/5", SMLSIZE + RIGHT)
    if phase == "show" then
      face(51, 18, b)
      lcd.drawText(64, 42, (a == b) and "Yes! Got it" or "Nope!", SMLSIZE + CENTER)
    else
      face(51, 18, 0)
      lcd.drawText(64, 42, "Left or right?", SMLSIZE + CENTER)
    end
    lcd.drawText(1, 56, "<SA/wheel", SMLSIZE)
    lcd.drawText(127, 56, "wheel/SD>", SMLSIZE + RIGHT)
  elseif kind == 2 then
    local t = math.floor(tleft + 0.99)
    if t < 0 then t = 0 end
    lcd.drawText(1, 0, "Caught " .. score .. "/6", SMLSIZE)
    lcd.drawText(127, 0, t .. "s", SMLSIZE + RIGHT)
    lcd.drawFilledRectangle(math.floor(b) - 1, math.floor(c), 3, 3, FORCE)
    local x = math.floor(a)
    lcd.drawLine(x - 8, 52, x - 8, 57, SOLID, FORCE)
    lcd.drawLine(x + 8, 52, x + 8, 57, SOLID, FORCE)
    lcd.drawLine(x - 7, 58, x + 7, 58, SOLID, FORCE)
  else
    lcd.drawText(1, 0, "Stop the bar!", SMLSIZE + INVERS)
    lcd.drawText(127, 0, "Try " .. round .. "/3", SMLSIZE + RIGHT)
    lcd.drawRectangle(13, 30, 103, 8)
    lcd.drawLine(56, 25, 56, 42, SOLID, FORCE)
    lcd.drawLine(72, 25, 72, 42, SOLID, FORCE)
    lcd.drawFilledRectangle(13 + math.floor(a), 28, 3, 12, FORCE)
    if phase == "show" then
      local t = "Miss"
      if d <= 3 then t = "Perfect!" elseif d <= 8 then t = "Good!" end
      lcd.drawText(64, 46, t, SMLSIZE + CENTER)
    else
      lcd.drawText(64, 46, "Hits " .. score .. "/2", SMLSIZE + CENTER)
    end
    lcd.drawText(64, 56, "ENTER/SA/SD: stop", SMLSIZE + CENTER)
  end
end

return { start = start, step = step, draw = draw }
