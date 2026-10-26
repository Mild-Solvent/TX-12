-- Donkey Kong hazards, loaded by Game-DonkeyKong.lua
-- kinds: 1 barrel, 2 pie (rides a conveyor), 3 spring, 4 fireball
-- Returns a constructor; gy / floorBelow / bx come from the game.
return function(gy, floorBelow, bx)
  local FALL_G = 200
  local MAXHZ = 10      -- hard cap on hazards alive at once
  local S, fl, ld, rv
  local level, hz, spawnT, fireT = 1, {}, 1, 3
  local H = { armT = 0 }

  -- EdgeTX on B&W radios has no table library
  local function removeAt(t, i)
    for j = i, #t - 1 do t[j] = t[j + 1] end
    t[#t] = nil
  end

  function H.reset(s, lv)
    S, fl, ld, rv, level = s, s.fl or {}, s.ld or {}, s.rv or {}, lv
    hz, spawnT, fireT, H.armT = {}, 1.0, 3.0, 0
  end

  function H.count() return #hz end

  local function fireCount()
    local n = 0
    for i = 1, #hz do if hz[i] and hz[i].k == 4 then n = n + 1 end end
    return n
  end

  local function add(k, x, g, y)
    if #hz >= MAXHZ then return end
    if k == 4 and fireCount() >= math.min(4, 1 + math.floor(level / 3)) then return end
    local vx = 0
    if k == 4 then vx = (math.random(2) == 1) and 14 or -14 end
    if k == 3 then vx = math.min(60, 30 + level * 3) end
    hz[#hz + 1] = { k = k, x = x, y = y or gy(g, x), g = g, m = 0, vx = vx, vy = 0,
      lo = g, t = 0, sc = false }
  end

  local function spawn(dt)
    local kind = S.hz
    local fast = math.min(1.2, (level - 1) * 0.12)
    spawnT = spawnT - dt
    fireT = fireT - dt
    if H.armT > 0 then H.armT = H.armT - dt end
    if spawnT <= 0 then
      spawnT = math.max(0.9, 2.4 - fast) + math.random() * 1.4
      if kind == "b" then
        add(1, S.tx or 18, S.tf or 1); H.armT = 0.3
      elseif kind == "s" then
        add(3, S.kx + 16, nil, S.sy); H.armT = 0.3
      elseif kind == "p" then
        local g = (math.random(2) == 1) and 2 or 3
        local f = fl[g]
        if f and f.cv then add(2, (f.cv > 0) and f.x0 or f.x1, g) end
      end
    end
    if fireT <= 0 and (kind == "p" or kind == "f") then
      fireT = math.max(2.5, 6 - fast * 2) + math.random() * 3
      local f = fl[1]
      if f then add(4, (math.random(2) == 1) and f.x0 + 4 or f.x1 - 4, 1) end
    end
  end

  -- move one hazard; true = remove it
  local function move(o, dt)
    if o.k == 3 then
      if o.m == 0 then
        o.t = o.t + dt
        o.x = o.x + o.vx * dt
        o.y = S.sy - math.abs(math.sin(o.t * 7)) * 8
        if o.x >= S.drop then o.m = 1; o.vy = 20 end
      else
        o.vy = o.vy + FALL_G * dt
        o.y = o.y + o.vy * dt
      end
      return o.y > LCD_H + 8
    end
    if o.m == 1 then          -- falling off a floor end
      o.vy = o.vy + FALL_G * dt
      o.y = o.y + o.vy * dt
      local f = o.lo and fl[o.lo]
      if f and o.x >= f.x0 and o.x <= f.x1 and o.y >= gy(o.lo, o.x) then
        o.g = o.lo; o.m = 0; o.y = gy(o.g, o.x)
      end
      return o.y > LCD_H + 8
    end
    if o.m == 2 then          -- on a ladder towards floor o.lo
      local ty = gy(o.lo, o.x)
      if o.y < ty then
        o.y = o.y + 30 * dt
        if o.y >= ty then o.g = o.lo; o.m = 0; o.y = ty end
      else
        o.y = o.y - 20 * dt
        if o.y <= ty then o.g = o.lo; o.m = 0; o.y = ty end
      end
      return false
    end
    local f = fl[o.g]
    if not f then return true end
    local v = o.vx
    if o.k == 1 then
      v = math.min(70, 30 + (level - 1) * 5)
      if f.y0 > f.y1 then v = -v end
    elseif o.k == 2 then
      v = f.cv or 0
    end
    local nx = o.x + v * dt
    -- ladders: barrels may roll down, fire may climb either way
    if o.k == 1 or o.k == 4 then
      local chance = (o.k == 1) and math.min(0.6, 0.2 + level * 0.06) or 0.35
      for i = 1, #ld do
        local l = ld[i]
        if l and o.m == 0 and (o.x - l.x) * (nx - l.x) < 0 and math.random() < chance then
          if l.hi == o.g then
            o.m = 2; o.lo = l.lo; nx = l.x
          elseif o.k == 4 and l.lo == o.g then
            o.m = 2; o.lo = l.hi; nx = l.x
          end
        end
      end
    end
    if o.k == 4 then          -- fire turns back at a pulled rivet
      for i = 1, #rv do
        local r = rv[i]
        if r and not r.on and r.f == o.g and (o.x - r.x) * (nx - r.x) <= 0 then
          o.vx = -o.vx; nx = o.x
        end
      end
    end
    o.x = nx
    if o.m ~= 0 then return false end
    if o.x < f.x0 or o.x > f.x1 then
      if o.k == 4 then
        o.vx = -o.vx
        o.x = math.max(f.x0, math.min(f.x1, o.x))
      elseif o.k == 1 then
        if S.oil and o.g == 1 then
          add(4, 6, 1)        -- barrel into the oil drum: fire
          return true
        end
        o.lo = floorBelow(o.x, o.y)
        if not o.lo then return true end
        o.m = 1; o.vy = 0
        return false
      else
        return true
      end
    end
    o.y = gy(o.g, o.x)
    return false
  end

  -- returns points scored, and true if the player was hit
  function H.update(dt, px, py, pg, air, ph)
    spawn(dt)
    for i = #hz, 1, -1 do
      local o = hz[i]
      if o and move(o, dt) then removeAt(hz, i) end
    end
    local pts = 0
    for i = 1, #hz do
      local o = hz[i]
      if o then
        if air and o.m == 0 and o.k ~= 3 and o.g == pg and not o.sc
            and math.abs(o.x - px) < 3 then
          o.sc = true
          pts = pts + 100
        end
        if math.abs(o.x - px) < 4 and o.y > py - ph + 1 and o.y < py + 3 then
          return pts, true
        end
      end
    end
    return pts, false
  end

  function H.draw()
    for i = 1, #hz do
      local o = hz[i]
      local x, y = math.floor(o.x), math.floor(o.y)
      if x >= 3 and x <= LCD_W - 4 and y >= 6 and y <= LCD_H then
        if o.k == 1 then
          lcd.drawRectangle(x - 2, y - 4, 4, 4, FORCE)
          bx(x - 1 + math.floor(x / 2) % 2, y - 3 + math.floor(x / 2) % 2, 1, 1)
        elseif o.k == 2 then
          bx(x - 2, y - 3, 5, 3)
          bx(x - 1, y - 4, 3, 1)
        elseif o.k == 3 then
          bx(x - 2, y - 4, 5, 1)
          bx(x - 1, y - 3, 1, 1)
          bx(x + 1, y - 2, 1, 1)
          bx(x - 2, y - 1, 5, 1)
        else
          bx(x - 1, y - 3, 3, 3)
          bx(x + (math.floor(o.x / 3) % 3) - 1, y - 5, 1, 2)
        end
      end
    end
  end

  return H
end
