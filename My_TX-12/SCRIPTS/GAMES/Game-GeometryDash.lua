-- toolName = TNS|Geometry Dash|TNE
---------------------------------------------------------------
-- Geometry Dash for 128x64 B&W EdgeTX radios (TX12, Zorro, X7)
-- Levels: /SCRIPTS/GAMES/GDASH/L<n>.lua (first line "-- @Name|Difficulty").
-- Only what the current screen needs is in memory: GDASH/pick.lua for the
-- picker, GDASH/phys.lua + GDASH/draw.lua + the level while playing.
-- Best % and attempts saved in /SCRIPTS/GAMES/gdash.dat.
--
-- Picker: wheel or right stick left/right = level,
--         stick up/down = normal / practice, left stick left/right = controls,
--         ENTER/SA/SD = play
-- Play:   SA or SD (read as held, for ship/wave/robot/dash orbs) or ENTER (tap only).
--         With THR stick controls the throttle works too: up past the middle = held
--         (jump), the ship and wave follow it in proportion, UFO flaps faster the
--         higher it is, swing flips on every up/down move. SA/SD held overrides it.
-- Practice: wheel = place checkpoint, wheel back = remove one
-- RTN:    back to picker, RTN in picker = quit
---------------------------------------------------------------

local GD = "/SCRIPTS/GAMES/GDASH/"
-- player fields kept in a practice checkpoint (one short string each, to save memory)
local KEYS = "x y vy g m mi du spd pc buf gr orb pad rt da y2 vy2 g2 gr2 buf2 orb2 pad2 rt2 da2"
local NLEV = 0
local best, tries = {}, {}
local tile, step, music, endX, newP, nr, draw, pick, mt
local state, lv, prac, P, acc, pend, lastTime, deadT, cps, msg
local ip = 0  -- controls: 0 SA/SD, 1 THR stick (GDASH/phys.lua reads the stick)

local function save()
  local s = "v2\n"  -- save version; see GDASH/pick.lua
  for i = 1, NLEV do s = s .. (best[i] or 0) .. " " .. (tries[i] or 0) .. "\n" end
  s = s .. "i" .. (ip or 0) .. "\n"
  local ok, f = pcall(io.open, "/SCRIPTS/GAMES/gdash.dat", "w")
  if ok and f then
    pcall(io.write, f, s)
    pcall(io.close, f)
  end
end

local function toPick()
  tile, step, music, draw, newP, cps = nil, nil, nil, nil, nil, {}
  collectgarbage()
  local c = loadScript(GD .. "pick.lua")
  c = c and c()
  if c then NLEV, pick, ip = c(best, tries) end
  state = "pick"
end

-- load level i, its physics and drawing; the level table is dropped after decoding
local function loadLevel(i)
  pick = nil
  collectgarbage()
  local c = loadScript(GD .. "L" .. i .. ".lua")
  local rows = c and c()
  c = nil
  if type(rows) ~= "table" then rows = {} end
  c = loadScript(GD .. "phys.lua")
  c = c and c()
  if c then tile, step, music, endX, newP, nr = c(rows) end
  rows, c = nil, nil
  collectgarbage()
  c = loadScript(GD .. "draw.lua")
  c = c and c()
  if c and tile then draw = c(tile, endX, nr) end
  c = nil
  collectgarbage()
end

local function pct()
  local v = math.floor(P.x * 100 / endX)
  if v > 100 then v = 100 elseif v < 0 then v = 0 end
  return v
end

local function startRun()
  for k, v in pairs(newP()) do P[k] = v end
  local s = cps[#cps]
  if prac and s then
    local it = string.gmatch(s, "%S+")
    for k in string.gmatch(KEYS, "%S+") do
      local v = it()
      if v == "T" then v = true elseif v == "F" then v = false else v = tonumber(v) end
      P[k] = v
    end
  end
  acc, pend, mt = 0, false, 0
  music(-1)
  state = "play"
end

local function init()
  lv, prac, P = 1, false, {}
  toPick()
  lastTime = getTime()
end

-- SA/SD read as held/released every frame; edge = released->held this frame.
-- In the picker a position kept 0.4 s becomes the rest position (toggles work).
-- (short names: every distinct name costs radio RAM)
local swR, swH, swT = {}, {}, {}  -- per switch: rest position, held, time of last change
local function readSw(n)
  local v, t = getValue(n) or 0, getTime()
  if swR[n] == nil then swR[n], swH[n], swT[n] = v, false, t end
  local h = math.abs(v - swR[n]) > 400
  local e = h and not swH[n]
  if h ~= swH[n] then swT[n] = t end
  swH[n] = h
  if h and state == "pick" and t - swT[n] > 40 then swR[n], swH[n] = v, false end
  return h, e
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    save()
    if state == "pick" then return 2 end
    toPick()
    return 0
  end
  -- t = 10 ms ticks since the last frame, h = SA/SD held, j = new press (SA/SD/ENTER)
  local n = getTime()
  local t = n - lastTime
  lastTime = n
  if t > 8 then t = 8 elseif t < 0 then t = 0 end
  local h, j = readSw("sa")
  local a, b = readSw("sd")
  h, j = h or a, j or b or event == EVT_VIRTUAL_ENTER
  local st  -- throttle stick, unless SA/SD is held
  if ip == 1 and not h then st = getValue("thr") or 0 end

  if state == "pick" then
    if not pick then
      lcd.clear()
      lcd.drawText(2, 20, "GDASH/pick.lua missing", SMLSIZE)
      return 0
    end
    lv, prac, ip = pick(event, lv, prac, msg, ip)
    if j and NLEV > 0 and not msg then
      loadLevel(lv)
      if draw then startRun() else msg = "GDASH/phys/draw missing"; toPick() end
    end
    return 0
  end
  local s = "A" .. (tries[lv] or 0) + 1  -- HUD text, top left
  if prac then s = "PRAC" .. #cps end
  if state == "play" then
    if prac and event == EVT_VIRTUAL_NEXT and #cps < 15 then
      local c = ""
      for k in string.gmatch(KEYS, "%S+") do
        local v = P[k]
        if v == true then v = "T" elseif v == false then v = "F" else v = string.format("%.7g", v) end
        c = c .. v .. " "
      end
      cps[#cps + 1] = c
    elseif prac and event == EVT_VIRTUAL_PREV and #cps > 0 then
      cps[#cps] = nil
    end
    pend = pend or j
    acc = acc + t
    while acc >= 2 and state == "play" do
      acc = acc - 2
      step(P, pend, h or pend, st)
      mt = mt + 0.02
      pend = false
      if P.dead or P.won then
        tries[lv] = (tries[lv] or 0) + 1
        a = pct()
        if P.won then a = 100 end
        if not prac and a > (best[lv] or 0) then best[lv] = a; save()
        elseif P.won then save() end
        if P.won then state = "win"; playTone(2600, 300, 0, PLAY_NOW)
        else state, deadT = "dead", 0; playTone(250, 300, 0, PLAY_NOW) end
      end
    end
    if state == "play" then
      music(mt)
      draw(P, nil, false, s, pct(), (tries[lv] or 0) + 1)
      return 0
    end
  end
  if state == "dead" then
    deadT = deadT + t / 100
    draw(P, deadT, false, s, pct(), tries[lv] or 0)
    if deadT > 0.8 then startRun() end
  else
    draw(P, nil, true, s, pct(), tries[lv] or 0)
    lcd.drawText(14, 16, "LEVEL COMPLETE!", MIDSIZE + INVERS)
    if prac then lcd.drawText(14, 32, "Practice run", SMLSIZE)
    else lcd.drawText(14, 32, "Attempts: " .. (tries[lv] or 0), SMLSIZE) end
    lcd.drawText(14, 42, "ENTER = levels", SMLSIZE)
    if event == EVT_VIRTUAL_ENTER then save(); toPick() end
  end
  return 0
end

-- the tools (tools/gdash) reach step, newP, loadLevel, music and state
-- through debug.getupvalue(run, ...), so the game carries no test hooks
return { init = init, run = run }
