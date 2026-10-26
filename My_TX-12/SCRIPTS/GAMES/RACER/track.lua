-- Racer track: stadium circuit driven clockwise, chicane on the top
-- straight. Loaded once by Game-Racer.lua; returns a builder.
return function(HW, NG)
  local wx, wy = {}, {}
  local function P(x, y)
    wx[#wx + 1] = x
    wy[#wy + 1] = y
  end
  P(64, 54) P(52, 54) P(40, 54) P(30, 54)
  for k = 1, 6 do
    local a = math.pi / 2 + k * math.pi / 6
    P(30 + 22 * math.cos(a), 32 + 22 * math.sin(a))
  end
  P(42, 10) P(50, 12) P(56, 17) P(64, 19)
  P(72, 17) P(78, 12) P(86, 10)
  for k = 0, 6 do
    local a = -math.pi / 2 + k * math.pi / 6
    P(98 + 22 * math.cos(a), 32 + 22 * math.sin(a))
  end
  P(88, 54) P(76, 54)
  local N = #wx
  local T = { wx = wx, wy = wy, N = N, ux = {}, uy = {}, len = {}, cum = {},
    fac = {}, ax = {}, ay = {}, bx = {}, by = {}, tx = {}, ty = {}, gw = {}, gc = {} }
  local ux, uy, len, cum = T.ux, T.uy, T.len, T.cum
  local L = 0
  for i = 1, N do
    local j = i % N + 1
    local dx, dy = wx[j] - wx[i], wy[j] - wy[i]
    local d = math.sqrt(dx * dx + dy * dy)
    ux[i], uy[i], len[i], cum[i] = dx / d, dy / d, d, L
    L = L + d
  end
  T.L = L
  for i = 1, N do
    local h = (i + N - 2) % N + 1
    local dx, dy = ux[h] + ux[i], uy[h] + uy[i]
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then d = 1 end
    -- tx/ty: track direction at the waypoint; a/b: the two track edges
    T.tx[i], T.ty[i] = dx / d, dy / d
    local nx, ny = -dy / d, dx / d
    T.ax[i] = math.floor(wx[i] + nx * HW + 0.5)
    T.ay[i] = math.floor(wy[i] + ny * HW + 0.5)
    T.bx[i] = math.floor(wx[i] - nx * HW + 0.5)
    T.by[i] = math.floor(wy[i] - ny * HW + 0.5)
    -- AI slows for bends: compare this segment with the next
    local j = i % N + 1
    local dot = ux[i] * ux[j] + uy[i] * uy[j]
    T.fac[i] = math.max(0.7, 1 - (1 - dot) * 0.6)
  end
  -- checkpoints: the waypoints closest to NG even splits of the lap
  for g = 1, NG do
    local want, bi, bd = (g - 1) * L / NG, 1, 1e9
    for i = 1, N do
      local d = math.abs(cum[i] - want)
      if d < bd then bi, bd = i, d end
    end
    T.gw[g], T.gc[g] = bi, cum[bi]
  end
  return T
end
