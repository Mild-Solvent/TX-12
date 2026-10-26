-- toolName = TNS|Donkey Kong|TNE
---------------------------------------------------------------
-- Donkey Kong for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
-- Walk: either stick L/R. Climb: right stick up/down at a ladder
-- Jump: SA / SD / ENTER. Title: wheel picks the start stage.
-- 4 stages rotate (layouts in GAMES/DKONG/stages.lua):
-- Girders (barrels, oil fire), Pie Factory (conveyors, pies,
-- fire), Elevators (lifts, springs), Rivets (boss: pull all
-- rivets and Kong falls). Every loop is faster. Exit: RTN
---------------------------------------------------------------

local PH = 6       -- player 5x6, px is its centre, py its feet
local WALK, CLIMB = 32, 20
local JUMP_V, JUMP_G = 66, 240  -- ~9 px high, ~0.55 s
local DEAD = 350

local S, fl, ld, rv   -- current stage, its floors, ladders, rivets
local state, px, py, pg, ladder, air, jumpH, jumpV, H
local lives, score, best, level, timer, lastTime, walkT
local kongDY, startLv, loadErr

-- filled rect clipped to the screen; solid (FORCE) unless flags given
local function bx(x, y, w, h, f)
  x, y = math.floor(x), math.floor(y)
  if x < 0 then w = w + x x = 0 end
  if y < 0 then h = h + y y = 0 end
  if x + w > LCD_W then w = LCD_W - x end
  if y + h > LCD_H then h = LCD_H - y end
  if w > 0 and h > 0 then lcd.drawFilledRectangle(x, y, w, h, f or FORCE) end
end

-- surface y of floor i at x
local function gy(i, x)
  local f = fl and fl[i]
  if not f then return 70 end
  if f.x1 == f.x0 then return f.y0 end
  return f.y0 + (x - f.x0) * (f.y1 - f.y0) / (f.x1 - f.x0)
end

-- nearest floor under (x, y), or nil
local function floorBelow(x, y)
  local best_, by = nil, 999
  for i = 1, #fl do
    local f = fl[i]
    if f and x >= f.x0 and x <= f.x1 then
      local fy = gy(i, x)
      if fy > y + 0.5 and fy < by then best_, by = i, fy end
    end
  end
  return best_
end

local function load(name)
  local chunk = loadScript("/SCRIPTS/GAMES/DKONG/" .. name)
  return chunk and chunk()
end

local function loadStage()
  S, fl, ld, rv = nil, {}, {}, {}
  pcall(collectgarbage)  -- (fengari sim lacks it)
  if not H then
    local mk = load("haz.lua")
    if type(mk) == "function" then H = mk(gy, floorBelow, bx) end
    if not H then loadErr = true return end
  end
  local mk = load("stages.lua")
  if type(mk) == "function" then S = mk((level - 1) % 4 + 1) end
  mk = nil
  pcall(collectgarbage)  -- (fengari sim lacks it)
  if not S then loadErr = true return end
  fl, ld, rv = S.fl or {}, S.ld or {}, S.rv or {}
end

local function resetRound()
  pg, px = S and S.sf or 1, S and S.sx or 8
  ladder, air, jumpH, jumpV = nil, false, 0, 0
  py = gy(pg, px)
  walkT, kongDY = 0, 0
  if H and S then H.reset(S, level) end
end

local function startStage()
  loadStage()
  resetRound()
  state, timer = "card", 2.2
end

local function newGame()
  lives, score, level = 3, 0, startLv
  startStage()
end

local function init()
  math.randomseed(getTime())
  best, startLv = 0, 1
  state = "title"
  lastTime = getTime()
end

-- true once per press of switch SA or SD. Works for buttons and toggles:
-- a switch left in a new position for 0.5 s counts as its new rest.
local SWITCHES = { "sa", "sd" }
local swLast, swRest, swSince = {}, {}, {}
local function switchPress()
  local now = getTime()
  local pressed = false
  for _, n in ipairs(SWITCHES) do
    local v = getValue(n)
    if swLast[n] == nil then
      swLast[n], swRest[n], swSince[n] = v, v, now
    elseif v ~= swLast[n] then
      if v ~= swRest[n] then pressed = true end
      swLast[n], swSince[n] = v, now
    elseif v ~= swRest[n] and now - swSince[n] > 50 then
      swRest[n] = v
    end
  end
  return pressed
end

local function loseLife()
  lives = lives - 1
  playTone(250, 500, -4, PLAY_NOW)
  state = "dead"
  timer = 1.2
end

local function rivetsLeft()
  local n = 0
  for i = 1, #rv do if rv[i] and rv[i].on then n = n + 1 end end
  return n
end

local function movePlayer(dt, jump)
  local sx = getValue("ail")
  local r = getValue("rud")
  if math.abs(r) > math.abs(sx) then sx = r end
  local sy = getValue("ele")

  if ladder then
    local l = ladder
    if math.abs(sy) > DEAD then
      py = py - sy / math.abs(sy) * CLIMB * dt; walkT = walkT + dt
    end
    if py <= gy(l.hi, l.x) then
      pg = l.hi; ladder = nil
    elseif py >= gy(l.lo, l.x) then
      pg = l.lo; ladder = nil
    end
    if ladder then return end
  end

  if air then
    jumpH = jumpH + jumpV * dt
    jumpV = jumpV - JUMP_G * dt
    if jumpH <= 0 then jumpH = 0; air = false end
  end
  local f = fl[pg]
  if not f then return end
  local nx = px
  if f.cv and not air then nx = nx + f.cv * dt end
  if math.abs(sx) > DEAD then
    nx = nx + sx / math.abs(sx) * WALK * dt; walkT = walkT + dt
  end
  for i = 1, #rv do
    local v = rv[i]
    if v and v.f == pg then
      if v.on then
        -- walking (not jumping) across a rivet pulls it out
        if not air and (px - v.x) * (nx - v.x) < 0 then
          v.on = false
          score = score + 100
          playTone(1800, 60, 0, PLAY_NOW)
        end
      elseif not air then
        -- a pulled rivet leaves a gap: jump it
        if px <= v.x - 3 and nx > v.x - 3 then nx = v.x - 3 end
        if px >= v.x + 3 and nx < v.x + 3 then nx = v.x + 3 end
        if nx > v.x - 3 and nx < v.x + 3 then
          nx = (nx < v.x) and v.x - 3 or v.x + 3
        end
      end
    end
  end
  px = nx
  -- floor ends: step onto a neighbouring floor (or lift) at the same height
  local lo, hi = f.x0 + 2, f.x1 - 2
  if px > hi or px < lo then
    local moved = false
    if not air then
      for j = 1, #fl do
        local g = fl[j]
        if g and j ~= pg then
          local ex, gx = f.x1, g.x0
          if px < lo then ex, gx = f.x0, g.x1 end
          if math.abs(gx - ex) <= 6 and math.abs(gy(j, gx) - gy(pg, ex)) <= 3 then
            pg = j; moved = true
            if px < lo then px = math.min(px, g.x1 - 2) else px = math.max(px, g.x0 + 2) end
            break
          end
        end
      end
    end
    if not moved then
      if px > hi then px = hi else px = lo end
    end
  end
  if px < 2 then px = 2 end
  if px > LCD_W - 3 then px = LCD_W - 3 end

  if not air then
    if sy > DEAD or sy < -DEAD then
      for i = 1, #ld do
        local l = ld[i]
        if l and math.abs(px - l.x) <= 3 then
          if sy > DEAD and l.lo == pg then
            ladder = l; px = l.x; py = gy(pg, px) - 1
            return
          elseif sy < -DEAD and l.hi == pg then
            ladder = l; px = l.x; py = gy(pg, px) + 1
            return
          end
        end
      end
    end
    if jump then
      air = true
      jumpV = JUMP_V
      playTone(1200, 30, 0, PLAY_NOW)
    end
  end
  py = gy(pg, px) - jumpH
end

local function bossDown()
  score = score + 5000
  state, timer = "boss", 3.0
  playTone(400, 900, -3, PLAY_NOW)
end

local function update(dt, jump)
  movePlayer(dt, jump)
  for i = 1, #fl do
    local f = fl[i]
    if f and f.lv then
      f.y0 = f.y0 + f.lv * dt
      if f.y0 < f.ylo then f.y0 = f.ylo; f.lv = -f.lv end
      if f.y0 > f.yhi then f.y0 = f.yhi; f.lv = -f.lv end
      f.y1 = f.y0
    end
  end
  if not ladder then py = gy(pg, px) - jumpH end

  local pts, hit = H.update(dt, px, py, pg, air, PH)
  if pts > 0 then
    score = score + pts
    playTone(2000, 30, 0, PLAY_NOW)
  end
  if hit then loseLife() return end
  -- touching Kong
  if math.abs(px - (S.kx + 6)) < 7 and py > S.ky and py - PH < S.ky + 9 then
    loseLife()
    return
  end

  if #rv > 0 then
    if rivetsLeft() == 0 then bossDown() end
  elseif pg == S.gf and not ladder and math.abs(px - S.gx) < 5 then
    score = score + 500 + level * 100
    state = "clear"
    timer = 1.5
    playTone(2600, 300, 0, PLAY_NOW)
  end
end

local function drawPlayer()
  local x, y = math.floor(px), math.floor(py)
  bx(x - 1, y - 6, 3, 2)
  bx(x - 2, y - 4, 5, 3)
  local a = (ladder or math.floor(walkT * 8) % 2 == 0) and 2 or 1
  bx(x - a, y - 1, 1, 1)
  bx(x + a, y - 1, 1, 1)
end

-- solid line, skipped unless both ends are on screen
local function hline(x0, y0, x1, y1)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  if math.min(x0, x1, y0, y1) < 0 or math.max(x0, x1) >= LCD_W or math.max(y0, y1) >= LCD_H then return end
  lcd.drawLine(x0, y0, x1, y1, SOLID, FORCE)
end

local function draw()
  lcd.clear()
  local ph = math.floor(getTime() / 8) % 4
  for i = 1, #fl do
    local f = fl[i]
    if f then
      if f.lv then
        hline((f.x0 + f.x1) / 2, 9, (f.x0 + f.x1) / 2, f.y0 - 1)
        bx(f.x0, f.y0, f.x1 - f.x0 + 1, 2)
      else
        hline(f.x0, f.y0, f.x1, f.y1)
        hline(f.x0, f.y0 + 2, f.x1, f.y1 + 2)
        if f.cv then
          local d = (f.cv > 0) and ph or (3 - ph)
          for x = f.x0 + d, f.x1, 4 do bx(x, f.y0 + 1, 1, 1) end
        end
      end
    end
  end
  for i = 1, #rv do
    local r = rv[i]
    if r then
      local y = math.floor(gy(r.f, r.x))
      if r.on then bx(r.x - 1, y - 1, 3, 5) else bx(r.x - 2, y, 5, 3, ERASE) end
    end
  end
  for i = 1, #ld do
    local l = ld[i]
    if l then
      local top = math.floor(gy(l.hi, l.x)) + 3
      local bot = math.floor(gy(l.lo, l.x)) - 1
      hline(l.x - 2, top, l.x - 2, bot)
      hline(l.x + 2, top, l.x + 2, bot)
      for y = top + 1, bot, 3 do hline(l.x - 1, y, l.x + 1, y) end
    end
  end
  if S.oil then
    bx(1, 56, 7, 1)
    lcd.drawRectangle(2, 57, 5, 4, FORCE)
    if ph % 2 == 0 then bx(3, 54, 1, 2) else bx(5, 54, 1, 2) end
  end
  -- Kong
  local kx, ky = S.kx, S.ky + math.floor(kongDY)
  if ky < LCD_H - 9 then
    bx(kx + 2, ky, 5, 3)
    bx(kx, ky + 3, 10, 6)
    if H.armT > 0 then hline(kx + 10, ky + 3, kx + 12, ky) else hline(kx + 10, ky + 4, kx + 11, ky + 8) end
  end
  -- the girl
  local gxx, sy = S.gx, math.floor(gy(S.gf, S.gx))
  lcd.drawRectangle(gxx - 1, sy - 10, 3, 3, FORCE)
  bx(gxx - 2, sy - 6, 5, 4)
  hline(gxx - 3, sy - 2, gxx + 3, sy - 2)

  H.draw()
  if state ~= "dead" or math.floor(timer * 8) % 2 == 0 then drawPlayer() end

  lcd.drawText(1, 0, "L" .. level, SMLSIZE)
  for i = 1, lives do bx(14 + i * 5, 2, 3, 3) end
  lcd.drawNumber(LCD_W - 1, 0, score, RIGHT + SMLSIZE)
end

local function msg(y, h)
  bx(10, y, LCD_W - 20, h, ERASE)
  lcd.drawRectangle(10, y, LCD_W - 20, h, FORCE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return 2
  end

  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now
  if dt > 0.08 then dt = 0.08 end

  local jump = (event == EVT_VIRTUAL_ENTER) or switchPress()

  if loadErr then
    lcd.clear()
    lcd.drawText(2, 20, "Missing file:", SMLSIZE)
    lcd.drawText(2, 30, "GAMES/DKONG/*.lua", SMLSIZE)
    return 0
  end

  if state == "title" then
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 36, 2, "DONKEY KONG", MIDSIZE + INVERS)
    lcd.drawText(4, 20, "Stick: walk + ladders", SMLSIZE)
    lcd.drawText(4, 29, "Jump: SA/SD/ENTER", SMLSIZE)
    lcd.drawText(4, 40, "Wheel: start stage " .. startLv, SMLSIZE)
    lcd.drawText(4, 50, "ENTER to play", SMLSIZE)
    if event == EVT_VIRTUAL_NEXT then startLv = startLv % 4 + 1 end
    if event == EVT_VIRTUAL_PREV then startLv = (startLv + 2) % 4 + 1 end
    if event == EVT_VIRTUAL_ENTER then newGame() end
  elseif state == "card" then
    timer = timer - dt
    lcd.clear()
    lcd.drawText(LCD_W / 2 - 30, 6, "STAGE " .. level, MIDSIZE)
    lcd.drawText(LCD_W / 2 - 33, 26, S.name, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 45, 38, S.hint, SMLSIZE)
    if level > 4 then
      lcd.drawText(LCD_W / 2 - 33, 50, "Loop " .. (math.floor((level - 1) / 4) + 1) .. " - faster", SMLSIZE)
    end
    if timer <= 0 then state = "play" end
  elseif state == "play" then
    update(dt, jump)
    draw()
  elseif state == "dead" or state == "clear" or state == "boss" then
    timer = timer - dt
    if state == "boss" then kongDY = math.min(60, kongDY + 30 * dt) end
    draw()
    if state == "clear" then
      msg(22, 13)
      lcd.drawText(LCD_W / 2 - 26, 25, "STAGE CLEAR", SMLSIZE)
    elseif state == "boss" then
      msg(20, 20)
      lcd.drawText(LCD_W / 2 - 34, 23, "KONG DEFEATED!", SMLSIZE)
      lcd.drawText(LCD_W / 2 - 24, 31, "+5000 bonus", SMLSIZE)
    end
    if timer <= 0 then
      if state ~= "dead" then
        level = level + 1
        startStage()
      elseif lives > 0 then
        resetRound()
        state = "play"
      else
        if score > best then best = score end
        state = "over"
      end
    end
  else
    draw()
    msg(12, 40)
    lcd.drawText(LCD_W / 2 - 28, 15, "GAME OVER", MIDSIZE)
    lcd.drawText(LCD_W / 2 - 36, 32, "Score " .. score .. "  Best " .. best, SMLSIZE)
    lcd.drawText(LCD_W / 2 - 30, 42, "ENTER to retry", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then newGame() end
  end
  return 0
end

return { init = init, run = run }
