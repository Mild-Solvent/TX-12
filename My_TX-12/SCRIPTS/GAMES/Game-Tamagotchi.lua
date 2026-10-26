-- toolName = TNS|Tamagotchi|TNE
---------------------------------------------------------------
-- Virtual pet for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
--
-- Wheel: pick Feed / Play / Sleep, ENTER: do it
-- SA: feed   SD: play          Exit: RTN / EXIT (saves)
-- Food, Joy and Energy drop in real time, also while closed
-- (needs the radio clock). Saved in /SCRIPTS/GAMES/pet.dat
---------------------------------------------------------------

local PATH = "/SCRIPTS/GAMES/pet.dat"
local SAVE_EVERY = 30       -- s
local MAX_AWAY = 7 * 86400  -- s of offline time counted at most
local DIE_AFTER = 24        -- h starving before the pet dies
local HATCH = 10            -- s an egg takes to hatch

-- pet: food, joy, energy 0..100; age s; starve h; asleep, alive 0/1
local food, joy, energy, age, starve, asleep, alive
local sel, msg, msgT, saveT, animT, lastTime, haveClock

local function daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe
end

-- seconds since 2020-01-01 from the radio clock, nil if no usable clock
local function clockNow()
  if getDateTime == nil then return nil end
  local ok, t = pcall(getDateTime)
  if not ok or type(t) ~= "table" then return nil end
  local y, mo, d = t.year, t.mon, t.day
  if y == nil or mo == nil or d == nil or y < 2020 then return nil end
  local days = daysFromCivil(y, mo, d) - daysFromCivil(2020, 1, 1)
  return days * 86400 + (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

local function newPet()
  food, joy, energy = 80, 80, 80
  age, starve, asleep, alive = 0, 0, 0, 1
end

local function clamp(v)
  if v < 0 then return 0 end
  if v > 100 then return 100 end
  return v
end

-- advance the pet by sec seconds
local function tick(sec)
  age = age + sec
  if alive == 0 or age < HATCH then return end
  local h = sec / 3600
  if asleep == 1 then
    food = food - 3 * h
    joy = joy - 2 * h
    energy = energy + 15 * h
    if energy >= 100 then asleep = 0 end
  else
    food = food - 6 * h
    joy = joy - 5 * h
    energy = energy - 4 * h
    if energy <= 0 then asleep = 1 end   -- passes out
  end
  food, joy, energy = clamp(food), clamp(joy), clamp(energy)
  if food <= 0 then
    starve = starve + h
    if starve >= DIE_AFTER then alive = 0 end
  elseif starve > 0 then
    starve = starve - h
    if starve < 0 then starve = 0 end
  end
end

local function save()
  local t = clockNow() or 0
  local s = "1 " .. math.floor(food * 100) .. " " .. math.floor(joy * 100) .. " " ..
    math.floor(energy * 100) .. " " .. math.floor(age) .. " " ..
    math.floor(starve * 100) .. " " .. asleep .. " " .. alive .. " " .. math.floor(t) .. "\n"
  pcall(function()
    local f = io.open(PATH, "w")
    if f then
      io.write(f, s)
      io.close(f)
    end
  end)
  saveT = 0
end

local function load()
  local data
  pcall(function()
    local f = io.open(PATH, "r")
    if f then
      data = io.read(f, 200)
      io.close(f)
    end
  end)
  newPet()
  if type(data) ~= "string" then return end
  local v = {}
  for n in string.gmatch(data, "%-?%d+") do v[#v + 1] = tonumber(n) end
  if #v < 9 or v[1] ~= 1 then return end
  food, joy, energy = clamp(v[2] / 100), clamp(v[3] / 100), clamp(v[4] / 100)
  age, starve = v[5], v[6] / 100
  asleep = (v[7] == 1) and 1 or 0
  alive = (v[8] == 0) and 0 or 1
  local now = clockNow()
  if now and v[9] > 0 then
    local away = now - v[9]
    if away < 0 then away = 0 end
    if away > MAX_AWAY then away = MAX_AWAY end
    while away > 0 do            -- 10 min steps so starving is counted right
      local s = away
      if s > 600 then s = 600 end
      tick(s)
      away = away - s
    end
  end
end

local function init()
  haveClock = clockNow() ~= nil
  load()
  sel, msg, msgT, saveT, animT = 1, "", 0, 0, 0
  lastTime = getTime()
  if not haveClock then msg = "No clock: no aging" ; msgT = 4 end
  save()
end

local function say(s)
  msg, msgT = s, 2.5
end

local function act(a)
  if alive == 0 then return end
  if age < HATCH then say("It's still an egg") return end
  if a == 3 then
    asleep = 1 - asleep
    say((asleep == 1) and "Good night" or "Good morning!")
    playTone(600, 80, 0, PLAY_NOW)
  elseif asleep == 1 then
    say("Shh... sleeping")
    return
  elseif a == 1 then
    if food >= 95 then say("Not hungry") return end
    food = clamp(food + 25)
    say("Yum!")
    playTone(1500, 60, 0, PLAY_NOW)
  else
    if energy < 10 then say("Too tired") return end
    joy = clamp(joy + 20)
    energy = clamp(energy - 8)
    food = clamp(food - 4)
    say("Wheee!")
    playTone(2000, 40, 0, PLAY_NOW)
    playTone(2600, 40, 60, 0)
  end
  save()
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

local function line(x1, y1, x2, y2)
  lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
end

local function mood()
  if alive == 0 then return "R.I.P." end
  if age < HATCH then return "Egg" end
  if asleep == 1 then return "Sleeping" end
  if food < 30 then return "Hungry" end
  if energy < 25 then return "Sleepy" end
  if joy < 30 then return "Bored" end
  return "Happy"
end

local function drawEgg(frame)
  local x, y = 54 + frame, 20
  line(x + 6, y, x + 13, y)
  line(x + 6, y, x + 2, y + 6)
  line(x + 13, y, x + 17, y + 6)
  line(x + 2, y + 6, x + 2, y + 16)
  line(x + 17, y + 6, x + 17, y + 16)
  line(x + 2, y + 16, x + 6, y + 21)
  line(x + 17, y + 16, x + 13, y + 21)
  line(x + 6, y + 21, x + 13, y + 21)
  line(x + 5, y + 10, x + 8, y + 8)
  line(x + 8, y + 8, x + 11, y + 11)
  line(x + 11, y + 11, x + 14, y + 9)
end

local function drawPet(m, frame)
  local x, y = 51, 19 + frame
  -- body with ears
  line(x + 2, y + 3, x + 23, y + 3)
  line(x + 1, y + 4, x + 1, y + 18)
  line(x + 24, y + 4, x + 24, y + 18)
  line(x + 2, y + 19, x + 23, y + 19)
  line(x + 3, y + 2, x + 5, y)
  line(x + 5, y, x + 7, y + 2)
  line(x + 18, y + 2, x + 20, y)
  line(x + 20, y, x + 22, y + 2)
  -- feet, stepping
  local f = (frame == 0) and 1 or 0
  lcd.drawFilledRectangle(x + 5, y + 20, 4, 2 - f)
  lcd.drawFilledRectangle(x + 16, y + 20, 4, 1 + f)
  -- eyes
  if m == "R.I.P." then
    line(x + 6, y + 7, x + 9, y + 10); line(x + 9, y + 7, x + 6, y + 10)
    line(x + 16, y + 7, x + 19, y + 10); line(x + 19, y + 7, x + 16, y + 10)
  elseif m == "Sleeping" or m == "Sleepy" then
    line(x + 6, y + 9, x + 9, y + 9)
    line(x + 16, y + 9, x + 19, y + 9)
  else
    lcd.drawFilledRectangle(x + 7, y + 7, 2, 3)
    lcd.drawFilledRectangle(x + 17, y + 7, 2, 3)
  end
  -- mouth
  if m == "Happy" then
    line(x + 9, y + 13, x + 11, y + 15)
    line(x + 12, y + 15, x + 13, y + 15)
    line(x + 14, y + 15, x + 16, y + 13)
  elseif m == "Hungry" then
    lcd.drawRectangle(x + 10, y + 13, 5, 4)
  elseif m == "Bored" or m == "R.I.P." then
    line(x + 9, y + 15, x + 11, y + 13)
    line(x + 12, y + 13, x + 13, y + 13)
    line(x + 14, y + 13, x + 16, y + 15)
  else
    line(x + 10, y + 14, x + 15, y + 14)
  end
  if m == "Sleeping" then
    lcd.drawText(x + 27, y - 4 + frame * 2, "z", SMLSIZE)
    lcd.drawText(x + 32, y - 9 + frame * 2, "Z", SMLSIZE)
  end
end

local function bar(x, label, v)
  lcd.drawText(x, 0, label, SMLSIZE)
  lcd.drawRectangle(x + 7, 1, 32, 6)
  local w = math.floor(v * 30 / 100)
  if w > 0 then lcd.drawFilledRectangle(x + 8, 2, w, 4) end
end

local function draw()
  lcd.clear()
  bar(0, "F", food)
  bar(43, "J", joy)
  bar(86, "E", energy)
  local m = mood()
  local frame = ((animT % 1) < 0.5) and 0 or 1
  if m == "Sleeping" then frame = ((animT % 2) < 1) and 0 or 1 end
  lcd.drawText(1, 10, m, SMLSIZE)
  local days = math.floor(age / 86400)
  local agetxt = (days > 0) and (days .. "d") or (math.floor(age / 3600) .. "h")
  lcd.drawText(LCD_W - 1, 10, "Age " .. agetxt, SMLSIZE + RIGHT)
  if m == "Egg" then drawEgg(frame) else drawPet(m, frame) end
  if msgT > 0 then lcd.drawText(64, 46, msg, SMLSIZE + CENTER) end
  if alive == 0 then
    lcd.drawText(64, 56, "ENTER: new egg", SMLSIZE + CENTER + INVERS)
    return
  end
  for i = 1, 3 do
    local t = "Feed"
    if i == 2 then t = "Play" elseif i == 3 then t = (asleep == 1) and "Wake" or "Sleep" end
    local x = (i - 1) * 43
    lcd.drawText(x + 21, 56, t, SMLSIZE + CENTER + ((i == sel) and INVERS or 0))
  end
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    save()
    return 2
  end

  local now = getTime()
  local real = (now - lastTime) / 100   -- pet ages in real time
  lastTime = now
  if real < 0 then real = 0 end
  if real > 60 then real = 60 end
  local dt = real
  if dt > 0.08 then dt = 0.08 end
  animT = animT + dt
  if msgT > 0 then msgT = msgT - dt end

  local wasEgg = age < HATCH
  tick(real)
  if wasEgg and age >= HATCH and alive == 1 then
    say("It hatched!")
    playTone(2000, 100, 0, PLAY_NOW)
    playTone(3000, 150, 120, 0)
    save()
  end

  local sw = switchPress()
  if alive == 0 then
    if event == EVT_VIRTUAL_ENTER then
      newPet()
      say("A new egg!")
      save()
    end
  else
    if event == EVT_VIRTUAL_NEXT then sel = (sel % 3) + 1 end
    if event == EVT_VIRTUAL_PREV then sel = ((sel + 1) % 3) + 1 end
    if event == EVT_VIRTUAL_ENTER then act(sel) end
    if sw == "sa" then act(1) elseif sw == "sd" then act(2) end
  end

  saveT = saveT + real
  if saveT >= SAVE_EVERY then save() end

  draw()
  return 0
end

return { init = init, run = run }
