# Level and song editors

Three tools that run in your browser. Double-click the `.html` file to open it: no install, no internet needed.
Keep the `radio/` folder next to `geodash-editor.html`: it holds the radio copy that the Radio tab and the
performance strip use (`tools/gdash/sync-editor.js` refreshes it from `My_TX-12` after a game change).
Your work is saved in the browser as a draft, but always **export** the file when you're done.

| Editor | Makes | Goes on the SD card at |
|---|---|---|
| `geodash-editor.html` | Geometry Dash levels `L<n>.lua` | `/SCRIPTS/GAMES/GDASH/` |
| `rhythm-editor.html` | Rhythm songs `s<n>.lua` | `/SCRIPTS/GAMES/RHYTHM/` |
| `audio-to-tune.html` | Turns an audio or MIDI file into a beeper melody: a ready Rhythm song, or a tune for a Geometry Dash level | (see below) |

## How the games find levels and songs

The games count the files on the card: `L1.lua`, `L2.lua`, `L3.lua` ... (or `s1.lua`, `s2.lua` ...) until one
is missing, up to 99. The first line of each file names it in the picker:

```lua
-- @My Level|Hard
```

So adding a level or song **never needs a change to the game**. Two rules:

- **Use the next free number.** There are 8 stock levels (`L1`–`L8`) and 5 stock songs (`s1`–`s5`), so your first
  new level is `L9.lua` and your first new song is `s6.lua`.
- **No gaps.** If you add `L10.lua` without `L9.lua`, the game stops counting at 8 and doesn't show L10.

## Add a Geometry Dash level

1. Open `geodash-editor.html` and press **New** (or open a stock level and change it).
2. Set **Name** and **Difficulty**. They show up in the level picker.
3. Paint the level. Pick a tile from the palette (or type its character), left-drag paints, right-drag erases.
   The **Help** tab explains every tile: blocks, slabs, spikes, orbs, pads and portals.
4. Write the music in the **Music** tab: a piano roll like FL Studio (left click adds a note, drag moves it, drag
   its right edge to resize, right click deletes, Shift/Ctrl-drag selects) and press Play to hear it. The buttons
   above the roll edit the selection: Draw / Select mode, cut, copy, paste (at the yellow cursor, set by clicking the
   roll), duplicate, delete, undo/redo, transpose, stretch / squeeze, reverse, legato, insert bar, remove time and
   play from the cursor. Keys: Ctrl+A/X/C/V/D, Del, arrows (Shift = octave).
5. Press **Play-test** to try it (Space or the mouse button = SA, held as long as you hold it; Enter = a tap), then
   **Check beatable**. The solver searches taps and holds, says whether the level can be finished and marks
   presses and releases that need very exact timing (red = under 60 ms, too tight for the radio).
6. Look at the coloured **performance strip** under the level. Every column is measured with the game's real
   drawing code: the number of screen drawing calls and Lua instructions one frame needs when that part is on
   screen. Green is as light as the easy stock levels, yellow as busy as the hardest ones (L6-L8), red is heavier
   than any stock level and can make the radio stutter: thin out those parts. Hover a column to see its numbers.
7. Press the **Radio (real code)** tab to play the level on a copy of the radio: the game's own `.lua` files, the
   TX12 screen pixel for pixel (same fonts), with the slow-LCD smear, and the radio's timing (20 frames a second).
   What you see there is what the radio shows. Space = SA, Enter, Esc = RTN, Q/A = left stick up/down.
8. **Download .lua** and name it with the next free number, e.g. `L9.lua`.
9. Copy it to the card (see below).

### Tiles

One character per 8x8 cell, 6 to 20 rows (6 = one radio screen; taller levels scroll up and down). The same table is at the top of `GDASH/phys.lua`, in
`tools/gdash/levels.txt` and in the editor's **Help** tab (with all the numbers).

| Char | Tile | Char | Tile |
|---|---|---|---|
| `.` | empty | `#` | block (solid) |
| `=` | slab (solid top half) | `^` / `v` | spike / hanging spike |
| `o` | yellow orb: jump | `i` | pink orb: small jump |
| `r` | red orb: big jump | `q` | blue orb: gravity flip |
| `e` | green orb: flip + jump | `b` | black orb: slam down |
| `a` | green dash orb (hold = dash straight) | `h` | pink dash orb (flip, then dash) |
| `p` | yellow pad | `k` | pink pad (small) |
| `f` | red pad (big) | `u` | blue pad: gravity flip |
| `w` | spider pad: teleport to the surface above, flip | | |
| `C` | cube portal | `U` | UFO portal |
| `S` | ship portal (hold = up) | `B` | ball portal (press = flip) |
| `W` | wave portal (hold = up 45°) | `R` | robot portal (hold = higher jump) |
| `X` | spider portal (press = teleport) | `Z` | swing portal (press = flip, also in the air) |
| `G` / `g` | gravity up / down | `m` / `n` | mini / normal size |
| `D` / `d` | dual / single | `T` | teleport: to the row of the `t` in the same column |
| `t` | teleport exit | `0`-`4` | speed 50 / 70 / 90 / 110 / 130 px/s |
| `/` | slope up 45° | `` ` `` | slope down 45° |
| `(` `)` | gentle slope up (low, then high half) | `[` `]` | gentle slope down (high, then low half) |

Portals act on the whole column (any row) when the icon's centre enters it; several can share a column
(`D` + `W` = dual wave). Flying modes (UFO, ship, wave, swing) use the whole field, ground to the top row, as their corridor.
Slopes are solid under the diagonal: the icon slides along them and dies running into a high side.

### File format

`L<n>.lua` returns `{ "row1", ..., "row6" (up to "row20"), u = <seconds per note unit>, m = "<tune>" }`, ground row first, with
`-- @Name|Difficulty` as its first line. Rows are **run-length coded**: a run of 4 or more equal tiles is written
`c*N`, where `N` is a single character whose code minus 32 is the count (`.*D` = 36 dots, `^*$` = 4 spikes;
at most 94 per run). The game keeps the rows coded in memory and decodes only the columns around the icon, so a level costs about its file size in radio RAM. Plain rows (the old format) still load,
and the editor can export them (**plain rows** on the Export tab). A 90 s level is typically 3-4 KB.

## Add a Rhythm song

1. Open `rhythm-editor.html` and press **New** (or pick a built-in song to start from).
2. Set **Name**, **Difficulty**, **File s** (the number, e.g. 6) and the tempo (`u` seconds per unit or BPM).
3. Enter the melody in the piano roll: double-click to add a note, drag to move it or change its pitch, drag the
   right edge to make it longer. Or type note names into **Helpers**, e.g. `E4 8, D4 8h, C4 4s, R 2`.
4. Choose each note's type: **tap**, **hold** (`h`), **slider** (`s`) or **music only** (`x`, played but no circle).
5. Press **Play** to hear it. The **Play field** shows where the circles appear on the radio; **Play-test** lets
   you play it with the mouse (Z / X / Space = the SA / SD buttons).
6. Fix what the **Validator** reports (notes too close together, pitches the radio beeper can't play well).
7. **Export** gives `s<n>.lua`, e.g. `s6.lua`.
8. Copy it to the card (see below).

Circle positions aren't stored in the song file: the game places them itself, seeded by the file number, so the
same song gets a different layout as `s6` than as `s7`. The editor's preview shows the layout for the number you set.

## Turn a song into a tune (no composing)

1. Open `audio-to-tune.html` and drop in an audio file (mp3, wav, ogg, m4a, flac) or a MIDI file (`.mid`).
2. Drag over the waveform to pick the part you want; the radio can't hold a whole song, so 20-40 s works well.
3. **Convert.** Check the BPM (use x2 / half if it's twice too fast or slow) and press **A/B** to compare the
   original with the beeper version.
4. For **MIDI**, pick the melody track, or "highest note" across all tracks. MIDI converts almost exactly.
5. Export:
   - **Rhythm song:** set the name, difficulty, file number and chart density, then **Download s<n>.lua**. It's
     ready for the card, or open it in `rhythm-editor.html` to tidy it up.
   - **Geometry Dash tune:** copy `u` and the token string into the level editor's **Music** tab.

Full band recordings (vocals, drums, chords together) give a rough melody that usually needs some clean-up in the
Rhythm editor. Solo melodies and MIDI files come out clean.

## Copy to the radio

1. Radio on, plug in USB, choose **USB Storage (SD)**.
2. Copy the file into `SCRIPTS/GAMES/GDASH/` (levels) or `SCRIPTS/GAMES/RHYTHM/` (songs).
3. If you **replaced** an existing file, delete the matching `.luac` next to it (e.g. `L3.luac`), so the radio
   doesn't keep running the old compiled copy.
4. Eject, unplug, open the game: the new level or song is at the end of the picker.

Best % (Geometry Dash) and best scores (Rhythm) are stored per number, so replacing `L3.lua` keeps L3's old best.
(Exception: when the stock Geometry Dash levels became the long 60-90 s, 9-12 row versions, `gdash.dat` got a
version line `v2`; a save file without it has its L1-L8 results reset once, L9 and up are kept.)

The stock Geometry Dash levels are written in `tools/gdash/levels.txt` (the source; `node build.js levels.txt
<GDASH dir>` makes `L1.lua`-`L8.lua`). Each is built like a real Geometry Dash level: a cube intro, mode sections
behind portals (flights climb into the rows above one screen), a drop where the tune peaks, short breathers, and
its own tune that follows the parts.

## Size

Keep a level or song file under about 8 KB; the radio has little memory. The editors show the file size and warn
when it gets large. For Geometry Dash the radio keeps the level run-length coded while playing, so the
file size is what counts: keep a level under about 6 KB (a 90 s level is typically 3-4 KB); the editor warns above that.
