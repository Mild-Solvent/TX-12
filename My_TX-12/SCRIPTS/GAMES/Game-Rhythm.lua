-- toolName = TNS|Rhythm|TNE
-- Osu!-style rhythm game. Wheel+ENTER picks a song (GAMES/RHYTHM/s<n>.lua).
-- R-stick aims. SA/SD (or ENTER) when the ring meets the circle.
-- Hold (dot): keep SA/SD down until it closes. Slider: hold, follow the ball.

-- circle radius, hit radius (cursor centre), slider follow radius, ring start
local R, HR, FOLLOW, RING = 7, 11, 13, 21
local W300, W100, W50 = 0.10, 0.18, 0.26  -- timing windows (s, either side)
local DATA = "/SCRIPTS/GAMES/RHYTHM/s"
local SAVE = "/SCRIPTS/GAMES/rhythm.dat"
local NSONG = 0
local top = 1  -- first song row shown in the picker
local NOTES = "C C#D D#E F F#G G#A A#B "

local state, sel, names, diffs, bestS, bestA, dirty, msg
local mel, U, AP, songT, songLen, total, lastTime, dtF
local mPos, mT, cPos, cT, act, seed, px, py, lastNT
local score, combo, maxCombo, c300, c100, c50, cMiss, cx, cy
local fbKind, fbX, fbY, fbT, newBest, held, acc

local function grade(acc)
  local k = 5
  if acc >= 950 then k = 1 elseif acc >= 900 then k = 2 elseif acc >= 800 then k = 3 elseif acc >= 700 then k = 4 end
  return string.sub("SABCD", k, k)
end

-- Level/song files are counted on the card (1, 2, 3, ... until one is
-- missing, max 99). Each file's first line names it: "-- @Name|Difficulty".
local function fileHeader(path)
  local ok, f = pcall(io.open, path, "r")
  if not ok or not f then return nil end
  local ok2, s = pcall(io.read, f, 80)
  pcall(io.close, f)
  if not ok2 or type(s) ~= "string" then return "", "" end
  local n, d = string.match(s, "^%-%- @([^|%c]*)|([^%c]*)")
  return n or "", d or ""
end

local function loadBest()
  local ok, f = pcall(io.open, SAVE, "r")
  if not ok or not f then return end
  local ok2, s = pcall(io.read, f, 1200)
  pcall(io.close, f)
  if not ok2 or type(s) ~= "string" then return end
  local i = 1
  for a, b in string.gmatch(s, "(%d+),(%d+)") do
    if i <= NSONG then bestS[i], bestA[i] = tonumber(a) or 0, tonumber(b) or 0 end
    i = i + 1
  end
end

local function saveBest()
  if not dirty then return end
  local s = ""
  for i = 1, NSONG do s = s .. (bestS[i] or 0) .. "," .. (bestA[i] or 0) .. "\n" end
  local ok, f = pcall(io.open, SAVE, "w")
  if ok and f then
    pcall(io.write, f, s)
    pcall(io.close, f)
    dirty = false
  end
end

local function init()
  names, diffs, bestS, bestA = {}, {}, {}, {}
  NSONG = 0
  for i = 1, 99 do
    local n, d = fileHeader(DATA .. i .. ".lua")
    if not n then break end
    NSONG = i
    names[i] = (n ~= "" and n) or ("Song " .. i)
    diffs[i], bestS[i], bestA[i] = d, 0, 0
  end
  dirty = false
  loadBest()
  sel, state, msg = 1, "pick", nil
  lastTime = getTime()
  cx, cy = LCD_W / 2, LCD_H / 2
end

-- SA/SD held state and press edges. Rest = first reading; in the menus a
-- switch left in a new position for 4 s becomes its new rest (toggles).
local swRest, swHeld, swSince = {}, {}, {}
local function readSw(n)
  local v = getValue(n) or 0
  local now = getTime()
  if swRest[n] == nil then swRest[n], swHeld[n], swSince[n] = v, false, now end
  local h = math.abs(v - swRest[n]) > 400
  local edge = h and not swHeld[n]
  if h ~= swHeld[n] then swSince[n] = now end
  swHeld[n] = h
  if h and state ~= "play" and now - swSince[n] > 400 then
    swRest[n], swHeld[n] = v, false
  end
  return h, edge
end

-- next melody token from pos: newPos, freq (0 = rest), length units, mark
local function nextTok(pos)
  local s, e, w = string.find(mel, "(%S+)", pos)
  if not s then return nil end
  if string.sub(w, 1, 1) == "R" then return e + 1, 0, tonumber(string.sub(w, 2, 2)) or 1, "x" end
  local nm, oc, ln, mk = string.match(w, "^(%u#?)(%d)(%d)(%l?)$")
  if not nm then return e + 1, 0, 1, "x" end
  if string.len(nm) == 1 then nm = nm .. " " end
  local i = string.find(NOTES, nm, 1, true) or 19
  local midi = 12 * (tonumber(oc) + 1) + (i - 1) / 2
  return e + 1, 440 * 2 ^ ((midi - 69) / 12), tonumber(ln) or 1, mk
end

local function rnd(n)
  seed = (seed * 75 + 74) % 65537
  return seed % n
end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- spot at distance d from (ox, oy), away from the other notes on screen
local function place(ox, oy, d)
  local x, y
  for try = 1, 10 do
    local a = rnd(16) * 0.3927
    x = clamp(math.floor(ox + math.cos(a) * d + 0.5), R + 1, LCD_W - R - 2)
    y = clamp(math.floor(oy + math.sin(a) * d + 0.5), 9 + R, LCD_H - R - 3)
    local ok = (x - ox) * (x - ox) + (y - oy) * (y - oy) >= 196
    for i = 1, #act do
      local n = act[i]
      if (n.x - x) * (n.x - x) + (n.y - y) * (n.y - y) < 256 then ok = false end
      if n.k == 3 and (n.x2 - x) * (n.x2 - x) + (n.y2 - y) * (n.y2 - y) < 256 then ok = false end
    end
    if ok then break end
  end
  return x, y
end

local function addNote(t, d, mk)
  local k = 1
  if mk == "h" then k = 2 elseif mk == "s" then k = 3 end
  local x, y = place(px, py, clamp((t - lastNT) * 60, 18, 40))
  lastNT = t
  local n = { t = t, e = t, k = k, x = x, y = y, x2 = x, y2 = y, st = 0, g = 1, bad = 0 }
  if k > 1 then n.e = t + d - math.min(0.3, d * 0.25) end
  if k == 3 then
    n.x2, n.y2 = place(x, y, 26 + rnd(12))
    px, py = n.x2, n.y2
  else
    px, py = x, y
  end
  act[#act + 1] = n
end

local function startSong()
  local ok, chunk = pcall(loadScript, DATA .. sel .. ".lua")
  local d
  if ok and chunk then
    local ok2, r = pcall(chunk)
    if ok2 then d = r end
  end
  if type(d) ~= "table" or type(d.m) ~= "string" then msg = "song file missing"; return end
  mel, U, AP = d.m, d.u or 0.25, d.a or 1.4
  d = nil
  -- song length and note count (bounded by the string)
  songLen, total = 0, 0
  local p = 1
  for i = 1, 400 do
    local np, f, len, mk = nextTok(p)
    if not np then break end
    if f > 0 and mk ~= "x" then total = total + 1 end
    songLen = songLen + len * U
    p = np
  end
  act = {}
  seed = sel * 1013 + 7
  px, py, lastNT = LCD_W / 2, 36, -1
  mPos, mT, cPos, cT = 1, 0, 1, 0
  songT = -(AP + 1)
  score, combo, maxCombo, c300, c100, c50, cMiss = 0, 0, 0, 0, 0, 0, 0
  fbT, newBest, msg = 0, false, nil
  state = "play"
end

local function endSong()
  acc = 0
  if total > 0 then acc = math.floor((300 * c300 + 100 * c100 + 50 * c50) * 1000 / (300 * total)) end
  if score > (bestS[sel] or 0) then bestS[sel], dirty, newBest = score, true, true end
  if acc > (bestA[sel] or 0) then bestA[sel], dirty = acc, true end
  saveBest()
  mel, act = nil, {}
  collectgarbage()
  state = "done"
end

-- g: 1 = 300, 2 = 100, 3 = 50, 4 = miss
local function judge(g, x, y)
  fbKind, fbX, fbY, fbT = g, x, y, 0.4
  if g == 4 then
    cMiss, combo = cMiss + 1, 0
    return
  end
  local mult = 1 + math.floor(combo / 10)
  if mult > 4 then mult = 4 end
  combo = combo + 1
  if combo > maxCombo then maxCombo = combo end
  if g == 1 then c300, score = c300 + 1, score + 300 * mult
  elseif g == 2 then c100, score = c100 + 1, score + 100 * mult
  else c50, score = c50 + 1, score + 50 * mult end
end

-- press at time pt: judge the earliest unjudged note under the cursor
local function tap(pt)
  local hit
  for i = 1, #act do
    local n = act[i]
    if n.st == 0 and pt - n.t >= -W50 and pt - n.t <= W50 then
      local dx, dy = n.x - cx, n.y - cy
      if dx * dx + dy * dy <= HR * HR and (hit == nil or n.t < hit.t) then hit = n end
    end
  end
  if hit == nil then return end
  local a = math.abs(pt - hit.t)
  local g = 3
  if a <= W300 then g = 1 elseif a <= W100 then g = 2 end
  if hit.k == 1 then
    hit.st = 2
    judge(g, hit.x, hit.y)
  else
    hit.st, hit.g = 1, g
  end
end

local function ballPos(n)
  local f = (songT - n.t) / (n.e - n.t)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return n.x + (n.x2 - n.x) * f, n.y + (n.y2 - n.y) * f
end

local function update(press)
  cx = LCD_W / 2 + (getValue("ail") or 0) * 62 / 1024
  cy = 36 - (getValue("ele") or 0) * 27 / 1024
  if fbT > 0 then fbT = fbT - dtF end

  -- music: queue each tone when its start time comes
  for k = 1, 4 do
    if mPos == nil or mT > songT then break end
    local np, f, len, mk = nextTok(mPos)
    if not np then mPos = nil; break end
    local d = len * U
    if f > 0 and songT - mT < 0.1 then playTone(math.floor(f), math.floor(d * 1000) - 25, 0, 0) end
    mPos, mT = np, mT + d
  end
  -- chart: spawn notes one approach time ahead
  for k = 1, 4 do
    if cPos == nil or cT - AP > songT then break end
    local np, f, len, mk = nextTok(cPos)
    if not np then cPos = nil; break end
    if f > 0 and mk ~= "x" then addNote(cT, len * U, mk) end
    cPos, cT = np, cT + len * U
  end

  if press then tap(songT - dtF / 2) end

  for i = 1, #act do
    local n = act[i]
    if n.st == 0 then
      if songT > n.t + W50 then n.st = 2; judge(4, n.x, n.y) end
    elseif n.st == 1 then
      if n.k == 3 then
        local bx, by = ballPos(n)
        if not held or (bx - cx) * (bx - cx) + (by - cy) * (by - cy) > FOLLOW * FOLLOW then n.bad = n.bad + dtF end
        if songT >= n.e then
          local g = n.g
          if n.bad > 0.45 then g = 4 elseif n.bad > 0.2 and g < 2 then g = 2 end
          n.st = 2
          judge(g, n.x2, n.y2)
        end
      elseif songT >= n.e then
        n.st = 2
        judge(n.g, n.x, n.y)
      elseif not held then
        n.st = 2
        judge(4, n.x, n.y)
      end
    end
  end
  -- drop finished notes (separate pass, nothing else walks the list now)
  local j = 0
  for i = 1, #act do
    if act[i].st ~= 2 then j = j + 1; act[j] = act[i] end
  end
  for i = #act, j + 1, -1 do act[i] = nil end

  if cPos == nil and #act == 0 and songT > songLen + 0.5 then endSong() end
end

local function plot(x, y)
  if x >= 0 and x < LCD_W and y >= 0 and y < LCD_H then lcd.drawPoint(x, y) end
end

-- midpoint circle outline (no circle primitive on B&W radios)
local function circle(ox, oy, r)
  ox, oy = math.floor(ox + 0.5), math.floor(oy + 0.5)
  local x, y, d = r, 0, 1 - r
  for i = 1, 40 do
    if x < y then break end
    plot(ox + x, oy + y); plot(ox - x, oy + y); plot(ox + x, oy - y); plot(ox - x, oy - y)
    plot(ox + y, oy + x); plot(ox - y, oy + x); plot(ox + y, oy - x); plot(ox - y, oy - x)
    y = y + 1
    if d < 0 then
      d = d + 2 * y + 1
    else
      x = x - 1
      d = d + 2 * (y - x) + 1
    end
  end
end

local function draw()
  lcd.clear()
  for i = #act, 1, -1 do
    local n = act[i]
    if n.k == 3 then
      lcd.drawLine(n.x, n.y, n.x2, n.y2, DOTTED, 0)
      circle(n.x2, n.y2, 3)
    end
    if n.st == 0 then
      circle(n.x, n.y, R)
      local r = math.floor(R + (RING - R) * (n.t - songT) / AP + 0.5)
      if r < R + 1 then r = R + 1 end
      circle(n.x, n.y, r)
      if n.k == 2 then lcd.drawFilledRectangle(n.x - 1, n.y - 1, 3, 3, FORCE) else plot(n.x, n.y) end
    elseif n.k == 2 then
      circle(n.x, n.y, R)
      local r = math.floor((R - 1) * (n.e - songT) / (n.e - n.t) + 0.5)
      if r >= 1 then circle(n.x, n.y, r) end
    else
      local bx, by = ballPos(n)
      circle(bx, by, R - 2)
      if held then circle(bx, by, FOLLOW) end
    end
  end
  local x, y = math.floor(cx + 0.5), math.floor(cy + 0.5)
  lcd.drawLine(x - 3, y, x - 1, y, SOLID, FORCE)
  lcd.drawLine(x + 1, y, x + 3, y, SOLID, FORCE)
  lcd.drawLine(x, y - 3, x, y - 1, SOLID, FORCE)
  lcd.drawLine(x, y + 1, x, y + 3, SOLID, FORCE)
  if fbT > 0 then
    local s = "MISS"
    if fbKind == 1 then s = "300" elseif fbKind == 2 then s = "100" elseif fbKind == 3 then s = "50" end
    local fx = fbX - 8
    if fx < 0 then fx = 0 elseif fx > LCD_W - 24 then fx = LCD_W - 24 end
    local fy = fbY - R - 8
    if fy < 9 then fy = fbY + R + 2 end
    lcd.drawText(math.floor(fx), math.floor(fy), s, SMLSIZE)
  end
  lcd.drawText(0, 0, "" .. score, SMLSIZE)
  lcd.drawText(LCD_W - 1, 0, combo .. "x", SMLSIZE + RIGHT)
  if songT < 0 then
    lcd.drawText(28, 0, "Aim R-stick, hit SA/SD", SMLSIZE)
  end
  local w = 0
  if songLen > 0 and songT > 0 then w = math.floor(songT * LCD_W / songLen) end
  if w > LCD_W then w = LCD_W end
  if w > 0 then lcd.drawLine(0, LCD_H - 1, w - 1, LCD_H - 1, SOLID, FORCE) end
end

local function drawPick()
  lcd.clear()
  lcd.drawText(0, 0, "RHYTHM", SMLSIZE + INVERS)
  lcd.drawText(LCD_W - 1, 0, "ENTER/SA play", SMLSIZE + RIGHT)
  if sel < top then top = sel elseif sel > top + 4 then top = sel - 4 end
  for i = top, math.min(NSONG, top + 4) do
    local y = 9 + (i - top) * 8
    lcd.drawText(2, y, names[i] or "?", SMLSIZE + (i == sel and INVERS or 0))
    lcd.drawText(LCD_W - 1, y, diffs[i] or "", SMLSIZE + RIGHT)
  end
  if NSONG == 0 then lcd.drawText(2, 17, "No songs in RHYTHM/", SMLSIZE) end
  local s, a = bestS[sel] or 0, bestA[sel] or 0
  if msg then
    lcd.drawText(2, 50, msg, SMLSIZE)
  elseif s > 0 then
    lcd.drawText(2, 50, "Best " .. s .. "  " .. math.floor(a / 10) .. "." .. a % 10 .. "% " .. grade(a), SMLSIZE)
  else
    lcd.drawText(2, 50, "Not played yet", SMLSIZE)
  end
  lcd.drawText(2, 57, "Aim R-stick, hit SA/SD", SMLSIZE)
end

local function drawDone()
  lcd.clear()
  lcd.drawText(2, 0, names[sel] or "", SMLSIZE + INVERS)
  lcd.drawText(LCD_W - 12, 2, grade(acc), DBLSIZE)
  lcd.drawText(2, 10, "Score " .. score .. (newBest and " NEW BEST" or ""), SMLSIZE)
  lcd.drawText(2, 19, "Acc " .. math.floor(acc / 10) .. "." .. acc % 10 .. "%  combo " .. maxCombo, SMLSIZE)
  lcd.drawText(2, 28, "300:" .. c300 .. " 100:" .. c100 .. " 50:" .. c50, SMLSIZE)
  lcd.drawText(2, 37, "Miss:" .. cMiss .. " of " .. total, SMLSIZE)
  lcd.drawText(2, 52, "ENTER: song list", SMLSIZE)
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    saveBest()
    return 2
  end
  local now = getTime()
  local d = now - lastTime
  lastTime = now
  -- a stall longer than 0.25 s (radio busy) is treated as a pause
  if d > 25 or d < 0 then d = 8 end
  dtF = d / 100
  if dtF > 0.08 then dtF = 0.08 end

  local ha, ea = readSw("sa")
  local hd, ed = readSw("sd")
  held = ha or hd
  local press = ea or ed or event == EVT_VIRTUAL_ENTER

  if state == "play" then
    songT = songT + d / 100
    update(press)
    if state == "play" then draw() else drawDone() end
  elseif state == "pick" then
    if NSONG == 0 then
    elseif event == EVT_VIRTUAL_NEXT then sel = sel % NSONG + 1; msg = nil
    elseif event == EVT_VIRTUAL_PREV then sel = (sel + NSONG - 2) % NSONG + 1; msg = nil end
    if press then startSong() end
    if state == "pick" then drawPick() else draw() end
  else
    drawDone()
    if event == EVT_VIRTUAL_ENTER then state = "pick" end
  end
  return 0
end

return { init = init, run = run, dbg = function() return act, songT, state end }
