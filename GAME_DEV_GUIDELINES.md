# Writing games for the TX12 (EdgeTX, 128x64 B&W)

Everything here was learned by getting the games in `My_TX-12/SCRIPTS/GAMES/`
running on a real RadioMaster TX12 MKII. Read it before writing or porting a game.

## The hardware

| | |
|---|---|
| Screen | 128 x 64 px, monochrome. `LCD_W`, `LCD_H` |
| MCU | TX12 MKII: STM32F407. The original TX12 used an STM32F207 |
| RAM | EdgeTX's Lua docs put the TX12 among the radios with "extremely small RAM": 128–192 KB for the *whole* firmware, Lua gets what is left |
| Lua | Lua 5.2, trimmed down for EdgeTX (see below) |

How much the Lua heap can actually take is best measured on the radio.
The launcher shows it in its header:

- In the menu: `NN K used` (heap now) and, if the firmware has
  `getAvailableMemory()`, `NN K free`.
- After you leave a game: `<game> peak NN K`, the most heap that game used.

Keep a game's peak well below the free figure. If a game dies with
`not enough memory`, it is too big; see "Memory" below.

## Lua on the radio is not desktop Lua

- **No `table` library.** `table.sort`, `table.insert`, `table.remove`,
  `table.concat` all fail with `attempt to index global 'table'`. Write the
  loop yourself. Each game that needs it carries a local helper:

  ```lua
  -- EdgeTX on B&W radios has no table library
  local function removeAt(t, i)
    for j = i, #t - 1 do t[j] = t[j + 1] end
    t[#t] = nil
  end
  ```

  Append with `t[#t + 1] = v`. Sort with a short insertion sort (see `Games.lua`).
- `string`, `math`, `ipairs`/`pairs`, `collectgarbage` are there.
  `io.open/read/write/close` exist (EdgeTX's own versions, `io.read(f, n)`).
- **`dir()` needs a path without a trailing slash.** `dir("/SCRIPTS/GAMES/")`
  returns nothing; `dir("/SCRIPTS/GAMES")` lists the folder.
- Scripts are compiled on the radio the first time they run and cached as
  `.luac` next to the `.lua`. **Error messages from a cached `.luac` have no
  line numbers** (`?:0: attempt to index field '?'`). Load with debug info to
  get them back: `loadScript(path, "Td")` (`T` prefers the text file, `d` keeps
  line numbers). The launcher does this, falling back to a plain load.
- When you replace a `.lua` on the card, delete its old `.luac` too, so the
  radio can't keep running the stale compiled copy.

## Script shape

A game is a one-file "tool" script:

```lua
-- toolName = TNS|My Game|TNE
local function init() ... end
local function run(event)
  if event == EVT_VIRTUAL_EXIT then return 2 end  -- leave
  ...
  return 0                                         -- keep running
end
return { init = init, run = run }
```

- Put it in `SCRIPTS/GAMES/`; the launcher (`SCRIPTS/TOOLS/Games.lua`) lists
  every `.lua` file there. The launcher runs the game inside `pcall` and shows
  any error full-screen instead of crashing.
- Everything at file level should be `local`. Globals leak into other scripts
  and cost memory.

## Timing

`getTime()` counts 10 ms ticks. Compute a frame time and cap it, so a slow
frame (or the radio pausing the script) doesn't teleport things through walls:

```lua
local now = getTime()
local dt = (now - lastTime) / 100   -- seconds
lastTime = now
if dt > 0.08 then dt = 0.08 end
```

Move with `speed * dt`. Make sure nothing can move more than one tile per
frame at the capped `dt`.

## Input

| Want | Use |
|---|---|
| Wheel press / RTN | `event == EVT_VIRTUAL_ENTER`, `EVT_VIRTUAL_EXIT` |
| Wheel scroll | `EVT_VIRTUAL_NEXT`, `EVT_VIRTUAL_PREV` |
| Sticks | `getValue("ail")`, `"ele"`, `"thr"`, `"rud"`: -1024..1024 |
| Switches SA..SD | `getValue("sa")` etc.: -1024 / 0 / 1024 |

- Stick "flicks" need a dead zone and re-arm: fire once when past ~600,
  re-arm when back under ~300.
- SA / SD as fire or flap buttons: `switchPress()` in `Game-Flappy.lua` /
  `Game-Invaders.lua` fires once when a switch leaves its resting position and
  treats a position held for 0.5 s as the new rest. That makes it work for
  both spring-loaded buttons and ordinary toggles.
- "Either stick moves": take whichever of `ail` / `rud` is further from centre.

## Drawing

- `lcd.clear()` every frame, then draw everything.
- `SMLSIZE` text is about 6 px per character: ~21 characters per line, 8 px
  line height. Long strings run off the edge, so wrap them yourself.
- Coordinates must be numbers; `math.floor` positions you computed from `dt`.

## Memory

- Keep source small. Our games are 4–13 KB of `.lua`; compiling happens on the
  radio and needs extra RAM while it runs. Very large scripts can fail to
  compile on the radio even though they run in the simulator.
- Build tables once in `init()`, not every frame. Reuse tables instead of
  allocating new ones in `run()`.
- Large games can be split into modules loaded with `loadScript` on demand,
  so only the part in use is in memory.
- `collectgarbage()` after leaving a game frees its memory (the launcher does it).
- Sounds (`playFile`) and pictures (`lcd.drawPixmap`) are files on the card
  and don't count against the Lua heap, but a missing file fails silently.

## Bugs we hit, so you don't

| Symptom on the radio | Cause | Fix |
|---|---|---|
| `attempt to index global 'table'` | no table library | own helpers, see above |
| Launcher said "No games" | `dir()` with trailing `/` | drop the slash |
| `?:0: attempt to index field '?'` | stripped `.luac`, no line info | `loadScript(path, "Td")` |
| Invaders crashed when hit | `loseLife()` emptied the list the loop was walking | return after changing the list |
| Pac-Man `attempt to index local 'd'`, first in `drawPac`, then in `movePac` | `DIRS[pac.dir]` came back nil on the radio only, right after the same lookup had worked; never reproduced off the radio | all direction tables replaced by `vec(dir)` / `opposite(dir)` functions built from `if`s |

When the radio and the simulator disagree, believe the radio and code
defensively around table lookups.

## More lessons (second round of games)

- **Physics must not depend on frame rate.** Doodle Jump's jump was ~20 px at the radio's 80 ms frames but 25 px
  in tests, so the generator made gaps you couldn't reach. Integrate exactly (`y += vy*dt + G*dt*dt/2`) or use
  fixed sub-steps, and derive level limits from the same physics with a safety margin.
- **Hitbox = drawing.** Use the same function for "where is it drawn" and "where does it collide" (Crossy Road).
- **Filled shapes can invert each other.** Draw with `FORCE` (solid black) / `ERASE` (solid white) and don't
  overlap fills; the white "ghost" rectangles in Crossy Road came from this.
- **Edge-detected buttons can lose presses.** For timing games read SA/SD as held/released every frame and take
  the press as the released->held change (Rhythm); don't re-learn the rest position during play.
- **Data folders.** Levels, songs, rules text and rarely used code go in `GAMES/<NAME>/*.lua`, loaded with
  `loadScript` when needed and dropped afterwards. Show a clear message if the folder is missing.
- **Cap every loop.** "Retry until it fits" loops get an attempt limit and a fallback (Battleship placement).
- **Clock.** The TX12 MKII has a real-time clock, but if the date was never set `getDateTime()` reports year 2000.
  Treat years before 2020 as "no clock" and fall back to in-game time.
- **Off-screen drawing** (negative x/y) shows up in the original games too (Asteroids, Pong) and they run fine,
  so the firmware clips it. Still, clip where it's cheap. The simulator counts these draws.
- **Dino reset the radio once** (dropped to the main screen, battery read 0.5 V for a moment). Cause not proven;
  Dino now clips all drawing and caps its lists.

## Memory budget (measured)

`tools/memcheck/` runs a game in stock Lua 5.2 with random input and reports its heap. Build Lua once and run it
on Linux (the devbox):

```sh
cd tools/memcheck && sh build-lua.sh
lua52/src/lua memcheck.lua ../../My_TX-12/SCRIPTS/GAMES Game-Racer.lua 4000
```

`live` is the heap after a full garbage collection, the number that has to fit. It's measured on a 64-bit PC,
roughly twice what the 32-bit radio uses, so compare games with each other, not with the radio's free-memory
figure. Reference: **Asteroids, a stock game that runs fine on the TX12, measures 70 KB live.** Keep every game
below that, ideally under 60 KB, and keep the picker or menu of a game well under it.

### Radio calibration (measured on the TX12 MKII, 2026-10-26)

- A memory fill test on the radio reached about **100 KB of Lua heap** before EdgeTX ran low. That is the
  ceiling for one script, launcher included. `getAvailableMemory()` reported only 9 KB free at idle: it shows
  the slack in the current heap, not the real limit.
- memcheck overstates the radio by about **2-2.5x** (64-bit values and debug info vs. the radio's 32-bit,
  debug-stripped code). Asteroids at 70 on memcheck is roughly 30-35 KB on the radio.
- Rule: **every game stays below Asteroids on memcheck (under 70, aim for 65).**
- **No Lua callbacks inside C functions** (`string.gsub(s, pat, function ... end)`, a function passed to
  anything in C). EdgeTX pauses (yields) busy scripts, and Lua can't yield inside such a callback: the radio
  stops the game with "attempt to yield across a C-call boundary" (Geometry Dash, 2026-10-27). Use a plain loop.
  The simulators don't yield, so only the radio shows it.
- **Never compile scripts right after filling RAM** (e.g. a memory test): the heap is fragmented and
  compiling can fail inside EdgeTX itself, outside any pcall, and kill the script. Measure one game per fresh run.

## Testing before copying to the card

`tools/tx12sim/run.js` runs every game under [fengari](https://github.com/fengari-lua/fengari)
(Lua in JavaScript) with a stubbed EdgeTX API, random stick input and the
`table` library removed. It catches crashes and logic errors, not memory or
radio-only problems.

```sh
cd tools/tx12sim && npm install fengari@0.1.4
node run.js ../../My_TX-12/SCRIPTS/GAMES 3000              # each game, 3000 frames
SEEDS=50 TICK=8 node run.js ../../My_TX-12/SCRIPTS/GAMES   # 50 runs each, 80 ms frames
```

fengari is Lua 5.3, the radio is 5.2: Breakout reports `ERROR 0` there but
runs fine on the radio.

## Copying to the card

1. Radio on, plug in USB, choose **USB Storage (SD)**.
2. Copy `My_TX-12/SCRIPTS/GAMES/` and `My_TX-12/SCRIPTS/TOOLS/Games.lua`.
3. Delete the `.luac` of any game you changed.
4. Close any Explorer window showing the card, eject, unplug.

Sources: EdgeTX Lua reference, [loadScript](https://luadoc.edgetx.org/lua-api-reference/lua-scripts/loadscript)
and "saving memory" pages; RadioMaster TX12 MKII product pages (MCU).
