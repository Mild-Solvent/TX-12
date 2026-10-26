-- Donkey Kong stage layouts, loaded on demand by Game-DonkeyKong.lua
-- stage(kind) returns a fresh table; kind 1..4.
-- Floors: x0,y0 .. x1,y1 is the walking surface (y grows downwards).
--   cv = conveyor speed (px/s), lv/ylo/yhi = lift moving between ylo..yhi
-- Ladders: x, lo (floor at the bottom), hi (floor at the top)
-- Rivets: x, f (floor); walk across one to pull it out
-- kx, ky: Kong's top-left; gf, gx: girl's floor / x; sf, sx: start
-- hz: hazard kind  b = barrels, p = pies + fire, s = springs, f = fire
local function F(x0, y0, x1, y1)
  return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end
local function L(x, lo, hi)
  return { x = x, lo = lo, hi = hi }
end

return function(kind)
  local s
  if kind == 2 then
    s = { name = "PIE FACTORY", hint = "Belts carry you!", hz = "p",
      fl = { F(0, 62, 127, 62), F(0, 48, 127, 48), F(0, 34, 127, 34),
             F(8, 20, 100, 20) },
      ld = { L(20, 1, 2), L(108, 1, 2), L(64, 2, 3), L(40, 3, 4), L(96, 3, 4) },
      kx = 10, ky = 11, gf = 4, gx = 90, sf = 1, sx = 8 }
    s.fl[2].cv = 14
    s.fl[3].cv = -14
  elseif kind == 3 then
    s = { name = "ELEVATORS", hint = "Ride the lifts", hz = "s",
      fl = { F(0, 62, 26, 62), F(28, 60, 40, 60), F(42, 40, 72, 40),
             F(74, 20, 86, 20), F(88, 50, 127, 50), F(88, 18, 127, 18),
             F(0, 16, 36, 16) },
      ld = { L(120, 5, 6) },
      kx = 4, ky = 7, gf = 6, gx = 112, sf = 1, sx = 8,
      sy = 16, drop = 58 }
    local a, b = s.fl[2], s.fl[4]
    a.lv, a.ylo, a.yhi = -12, 22, 62
    b.lv, b.ylo, b.yhi = 14, 18, 58
  elseif kind == 4 then
    s = { name = "RIVETS", hint = "Pull all 6 rivets!", hz = "f",
      fl = { F(0, 62, 127, 62), F(8, 48, 119, 48), F(14, 34, 113, 34),
             F(20, 20, 107, 20), F(78, 11, 98, 11) },
      ld = { L(14, 1, 2), L(64, 1, 2), L(114, 1, 2), L(22, 2, 3), L(64, 2, 3),
             L(106, 2, 3), L(26, 3, 4), L(102, 3, 4) },
      rv = { { x = 30, f = 2 }, { x = 98, f = 2 }, { x = 34, f = 3 },
             { x = 94, f = 3 }, { x = 40, f = 4 }, { x = 88, f = 4 } },
      kx = 58, ky = 11, gf = 5, gx = 88, sf = 1, sx = 8 }
    for i = 1, #s.rv do s.rv[i].on = true end
  else
    s = { name = "GIRDERS", hint = "Reach the girl", hz = "b", oil = true,
      fl = { F(0, 62, 127, 59), F(0, 45, 115, 48), F(12, 34, 127, 31),
             F(0, 17, 112, 20) },
      ld = { L(96, 1, 2), L(26, 1, 2), L(20, 2, 3), L(64, 2, 3), L(104, 3, 4),
             L(44, 3, 4) },
      kx = 2, ky = 8, gf = 4, gx = 78, sf = 1, sx = 14, tf = 4, tx = 18 }
  end
  s.rv = s.rv or {}
  return s
end
