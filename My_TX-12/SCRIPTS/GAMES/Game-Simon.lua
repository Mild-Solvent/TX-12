-- toolName = TNS|Simon|TNE
---------------------------------------------------------------
-- Simon / Copycat for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Watch the arrows light up, then repeat them with right stick
-- flicks (back to centre between moves). One more each round.
-- Start / retry: ENTER, SA or SD      Exit: RTN / EXIT
---------------------------------------------------------------

local S = 9                -- arrow head size in px
local ON_T, OFF_T = 0.5, 0.15

local seq = {}
local state, idx, timer, lit, litT, score, best
local lastTime, armed

local function init()
  math.randomseed(getTime())
  best = 0
  score = 0
  armed = true
  lit, litT = 0, 0
  lastTime = getTime()
  state = "title"
end

local function freq(d)
  if d == 1 then return 1320 elseif d == 2 then return 660
  elseif d == 3 then return 880 end
  return 1100
end

local function line(x1, y1, x2, y2)
  lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
end

-- d: 1 up, 2 down, 3 left, 4 right
local function arrow(d, on)
  local cx, cy, ax, ay
  if d == 1 then cx, cy, ax, ay = 64, 19, 0, -1
  elseif d == 2 then cx, cy, ax, ay = 64, 51, 0, 1
  elseif d == 3 then cx, cy, ax, ay = 36, 35, -1, 0
  else cx, cy, ax, ay = 92, 35, 1, 0 end
  local px, py = ay, ax
  local tx, ty = cx + ax * S, cy + ay * S
  local ex, ey = cx - ax * 6, cy - ay * 6
  if on then
    for i = 0, S do
      local qx, qy = tx - ax * i, ty - ay * i
      line(qx - px * i, qy - py * i, qx + px * i, qy + py * i)
    end
    for i = 1, 6 do
      local qx, qy = cx - ax * i, cy - ay * i
      line(qx - px * 2, qy - py * 2, qx + px * 2, qy + py * 2)
    end
  else
    local bx1, by1 = cx - px * S, cy - py * S
    local bx2, by2 = cx + px * S, cy + py * S
    line(tx, ty, bx1, by1)
    line(tx, ty, bx2, by2)
    line(bx1, by1, bx2, by2)
    line(cx - ax - px * 2, cy - ay - py * 2, ex - px * 2, ey - py * 2)
    line(cx - ax + px * 2, cy - ay + py * 2, ex + px * 2, ey + py * 2)
    line(ex - px * 2, ey - py * 2, ex + px * 2, ey + py * 2)
  end
end

local function stepTime()
  local t = ON_T - #seq * 0.02
  if t < 0.2 then t = 0.2 end
  return t
end

local function startShow()
  seq[#seq + 1] = math.random(4)
  state = "show"
  idx = 0
  timer = 0.6
  lit = 0
end

local function newGame()
  for i = #seq, 1, -1 do seq[i] = nil end
  score = 0
  startShow()
end

-- "sa" / "sd" once per press (buttons and toggles)
local swLast, swRest, swSince = {}, {}, {}
local function swCheck(n, now)
  local v = getValue(n)
  if swLast[n] == nil then
    swLast[n], swRest[n], swSince[n] = v, v, now
  elseif v ~= swLast[n] then
    swLast[n], swSince[n] = v, now
    if v ~= swRest[n] then return true end
  elseif v ~= swRest[n] and now - swSince[n] > 50 then
    swRest[n] = v
  end
  return false
end
local function switchPress()
  local now = getTime()
  local a = swCheck("sa", now)
  local d = swCheck("sd", now)
  if a then return "sa" end
  if d then return "sd" end
  return nil
end

-- direction 1..4 once per flick; stick must return to centre
local function readStick()
  local h, v = getValue("ail"), getValue("ele")
  local ah, av = math.abs(h), math.abs(v)
  if ah < 300 and av < 300 then
    armed = true
    return 0
  end
  if not armed then return 0 end
  if ah > 600 and ah >= av then
    armed = false
    return (h > 0) and 4 or 3
  elseif av > 600 then
    armed = false
    return (v > 0) and 1 or 2
  end
  return 0
end

local function draw(center, over)
  lcd.clear()
  for d = 1, 4 do arrow(d, d == lit) end
  if over then
    lcd.drawText(1, 0, "ENTER=retry", SMLSIZE)
  else
    lcd.drawText(1, 0, "Round " .. #seq, SMLSIZE)
  end
  lcd.drawText(LCD_W - 1, 0, "Best " .. best, SMLSIZE + RIGHT)
  if center then lcd.drawText(64, 32, center, SMLSIZE + CENTER) end
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
  local start = event == EVT_VIRTUAL_ENTER or sw ~= nil
  local d = readStick()   -- every frame, so re-arming is always tracked

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 22, 4, "SIMON", MIDSIZE + INVERS)
    lcd.drawText(2, 22, "Watch the arrows,", SMLSIZE)
    lcd.drawText(2, 31, "repeat: flick stick", SMLSIZE)
    lcd.drawText(2, 42, "Best " .. best, SMLSIZE)
    lcd.drawText(2, 54, "ENTER to start", SMLSIZE + BLINK)
    if start then newGame() end
    return 0
  end

  if state == "show" then
    timer = timer - dt
    if timer <= 0 then
      if lit ~= 0 then
        lit = 0
        timer = OFF_T
      else
        idx = idx + 1
        if idx > #seq then
          state = "input"
          idx = 1
          litT = 0
        else
          lit = seq[idx]
          timer = stepTime()
          playTone(freq(lit), math.floor(timer * 1000), 0, PLAY_NOW)
        end
      end
    end
    draw("Watch")
  elseif state == "input" then
    if litT > 0 then
      litT = litT - dt
      if litT <= 0 then lit = 0 end
    end
    if d ~= 0 then
      lit, litT = d, 0.25
      if d == seq[idx] then
        playTone(freq(d), 150, 0, PLAY_NOW)
        idx = idx + 1
        if idx > #seq then
          score = #seq
          if score > best then best = score end
          state = "good"
          timer = 0.8
        end
      else
        state = "over"
        timer = 0
        playTone(150, 600, 0, PLAY_NOW)
      end
    end
    draw((idx <= #seq) and (idx .. "/" .. #seq) or "")
  elseif state == "good" then
    timer = timer - dt
    if timer < 0.5 then lit = 0 end
    if timer <= 0 then startShow() end
    draw("Good!")
  else
    timer = timer + dt
    -- blink the arrow that was expected
    lit = 0
    if (timer % 0.5) < 0.3 then lit = seq[idx] or 0 end
    draw(nil, true)
    lcd.drawText(64, 29, "WRONG", SMLSIZE + CENTER + INVERS)
    lcd.drawText(64, 37, "Sc " .. score, SMLSIZE + CENTER)
    if timer > 0.8 and start then newGame() end
  end
  return 0
end

return { init = init, run = run }
