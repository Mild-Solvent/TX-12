-- Geometry Dash level tune player, loaded by phys.lua (kept out of it so each file
-- compiles on the radio in less RAM):  music = loadScript(this)()(lv.m, lv.u)
-- music(t) with t = seconds since the attempt started queues each note when its
-- time comes, t < 0 restarts; the tune loops.
-- Token: note letter, optional #, octave digit, length digit (units of u s); R<n> = rest.
-- editors/geodash-editor.html has a JavaScript copy (tok / makeMusic): change both.
return function(mel, u)
-- i = byte position of the next token, e = its start time
local i, e = 1, 0
u = tonumber(u) or 0.1
if type(mel) ~= "string" then mel = nil end
-- token at byte position j: next position, frequency (0 = rest), length
local function tok(j)
  local a, b, w = string.find(mel, "(%S+)", j)
  if not a then return nil end
  if string.sub(w, 1, 1) == "R" then return b + 1, 0, tonumber(string.sub(w, 2, 2)) or 1 end
  local c, o, d = string.match(w, "^(%u#?)(%d)(%d)$")
  if not c then return b + 1, 0, 1 end
  if string.len(c) == 1 then c = c .. " " end
  a = string.find("C C#D D#E F F#G G#A A#B ", c, 1, true) or 19
  a = 12 * (tonumber(o) + 1) + (a - 1) / 2  -- MIDI note
  return b + 1, 440 * 2 ^ ((a - 69) / 12), tonumber(d) or 1
end
local function music(t)
  if not mel then return end
  if t < 0 then i, e = 1, 0; return end
  for k = 1, 4 do
    if e > t then break end
    local j, f, n = tok(i)
    if not j then j, f, n = tok(1) end
    if not j then mel = nil; return end
    n = n * u
    if f > 0 and t - e < 0.1 then playTone(math.floor(f), math.floor(n * 1000) - 20, 0, 0) end
    i, e = j, e + n
  end
end

return music
end
