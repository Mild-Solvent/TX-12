# TX12 SD card

`TX-12/` is the untouched SD card backup (EdgeTX 2.8.0). `My_TX-12/` is the live card with the games added.

## Update the radio

1. Radio on, plug in USB, choose **USB Storage (SD)**.
2. Delete everything on the SD card.
3. Drag the **contents** of `My_TX-12/` onto the SD card.
4. Eject, unplug, play.

Wiping first matters: copying over the top keeps the old game files in `SCRIPTS/TOOLS` and they show up in the Tools menu again. It also clears the radio's compiled `.luac` copies, which otherwise keep running an old version of a changed game.

## Games

Long press **SYS**, open **Tools**, pick **Games**. Scroll to a game and press ENTER. **RTN** goes back to the list.

Games live in `SCRIPTS/GAMES/`; the launcher is `SCRIPTS/TOOLS/Games.lua`. To add a game, drop its `.lua` file into `SCRIPTS/GAMES/`.

| Game | Controls |
|------|----------|
| Pac-Man | Right stick steers |
| Pinball | SA = left flipper, SD = right flipper, ENTER launches |
| Flappy | SA, SD or ENTER flaps (stick up too). Every 7 pipes: faster, tighter gaps swinging top to bottom |
| 2048 | Flick right stick to slide tiles, ENTER for a new game |
| Invaders | Either stick left/right moves, SA, SD or ENTER fires |
| Snake, Pong, Breakout, Asteroids, X-Tris, Simulator | Came with the original card |

More games: https://github.com/EdgeTX/lua-scripts (pick ones made for 128x64 B&W screens).

Writing or fixing a game? Read [GAME_DEV_GUIDELINES.md](GAME_DEV_GUIDELINES.md) first: radio memory, the missing `table` library, input, timing and how to test with `tools/tx12sim`.
