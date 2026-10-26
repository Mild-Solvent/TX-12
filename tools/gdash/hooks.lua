-- Test hooks for Game-GeometryDash.lua (used by memplay.lua, solve.js, soak.js).
-- The game has no test API; the tools read its locals through the debug library:
--   GD_UP(g.run, "step")  -> current value of the game's local "step"
-- Names searched breadth-first through the upvalues of run and the functions it reaches.
-- Values change when the game loads a level, so look them up again after a load.
function GD_UP(f, name)
  local queue, seen, qi = { f }, { [f] = true }, 1
  while queue[qi] and qi < 200 do
    local fn = queue[qi]
    qi = qi + 1
    local i = 1
    while i < 100 do
      local n, v = debug.getupvalue(fn, i)
      if not n then break end
      if n == name then return v end
      if type(v) == "function" and not seen[v] then seen[v] = true; queue[#queue + 1] = v end
      i = i + 1
    end
  end
  return nil
end
