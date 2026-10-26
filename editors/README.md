# Level and song editors

Two editors that run in your browser. Double-click the `.html` file to open it: no install, no internet needed.
Your work is saved in the browser as a draft, but always **export** the file when you're done.

| Editor | Makes | Goes on the SD card at |
|---|---|---|
| `geodash-editor.html` | Geometry Dash levels `L<n>.lua` | `/SCRIPTS/GAMES/GDASH/` |
| `rhythm-editor.html` | Rhythm songs `s<n>.lua` | `/SCRIPTS/GAMES/RHYTHM/` |

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
4. Write the music in the **Music** tab and press Play to hear it.
5. Press **Play-test** to try it (Space jumps), then **Check beatable**. The solver says whether the level can be
   finished and marks presses that need very exact timing (red = under 60 ms, too tight for the radio).
6. **Download .lua** and name it with the next free number, e.g. `L9.lua`.
7. Copy it to the card (see below).

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

## Copy to the radio

1. Radio on, plug in USB, choose **USB Storage (SD)**.
2. Copy the file into `SCRIPTS/GAMES/GDASH/` (levels) or `SCRIPTS/GAMES/RHYTHM/` (songs).
3. If you **replaced** an existing file, delete the matching `.luac` next to it (e.g. `L3.luac`), so the radio
   doesn't keep running the old compiled copy.
4. Eject, unplug, open the game: the new level or song is at the end of the picker.

Best % (Geometry Dash) and best scores (Rhythm) are stored per number, so replacing `L3.lua` keeps L3's old best.

## Size

Keep a level or song file under about 8 KB; the radio has little memory. The editors show the file size and warn
when it gets large.
