# EdgeTX simulator for the TX12 MKII (headless)

The real EdgeTX **v2.8.0** firmware code for board **tx12mk2** (what's on father's radio),
built for a PC as a 32-bit program so Lua memory matches the radio's 32-bit chip. It boots
a copy of the SD card (radio settings, models, scripts) and is driven by a command file.
Unlike `tools/tx12sim` and `tools/memcheck`, this runs EdgeTX's own Lua, lcd, events and
script scheduling.

```
tools/edgetx-sim/build.sh                       # once, ~10 min: clones EdgeTX, patches, builds
cp -r My_TX-12 /tmp/card                        # the simulator writes .luac and saves into it
LUA_MEM_CAP=102400 tools/edgetx-sim/run.sh /tmp/card $PWD/tools/edgetx-sim/example.txt /tmp/out
```

Paths must be absolute (the firmware changes directory). Commands: see the top of
`simu_headless.cpp` (`press KEY`, `rot N` = scroll wheel, `sw A 1`, `stick N V`, `shot NAME`,
`fuzz MS SEED`, `wait MS`). The run is real time.

The `STATS` line at the end:
- `luaMemPeak`: highest Lua heap in bytes (same measure as `collectgarbage("count")`).
  `LUA_MEM_CAP=102400` makes allocations fail above 100 KB, what father's radio gives Lua
  (launcher after a fresh start: 12K used + 88K free). The sim counts about 3 KB more than
  the radio for the same screen, so it is slightly stricter.
- `cBoundaryHits`: Lua code that ran inside a C call (a `string.gsub` callback etc.). On the
  radio EdgeTX pauses busy scripts, and a pause there crashes with "attempt to yield across a
  C-call boundary" (GDASH/phys.lua:57, 2026-10-27). **Must be 0.** `CBOUNDARY` names the spot.
- `LCDOOB hits=N at file:line`: a drawing call that wrote outside the screen memory. EdgeTX 2.8
  on 128x64 does not clip `lcd.drawFilledRectangle` / `lcd.drawPoint` at negative x/y, nor
  `lcd.drawLine` ending at x = LCD_W or y = LCD_H; on the radio that silently overwrites other
  memory (stray pixels, crashes, resets). The sim skips the write and names the line. **Must be absent.**
- `maxCycleInstr`: most Lua instructions in one 50 ms script cycle (100-instruction steps).
  `LUA_BUDGET=N` forces a pause after N instructions, like a slow radio.

What the patch adds (`edgetx-v2.8.0.patch`): Lua heap accounting + cap in `l_alloc`, the
C-boundary and budget checks in `luaHook`, and the `simu-headless` build target.
Not modelled: real CPU speed (the PC is much faster) and the radio's free system RAM.
