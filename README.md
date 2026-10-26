# TX12 SD card

`TX-12/` is the untouched SD card backup (EdgeTX 2.8.0). `My_TX-12/` is the live card with the games added.

## Update the radio

1. Radio on, plug in USB, choose **USB Storage (SD)**.
2. Delete everything on the SD card.
3. Drag the **contents** of `My_TX-12/` onto the SD card.
4. Eject, unplug, play.

Wiping first matters: copying over the top keeps the old game files in `SCRIPTS/TOOLS` and they show up in the Tools menu again.

## Games

Long press **SYS**, open **Tools**, pick **Games**. Scroll to a game and press ENTER. **RTN** goes back to the list.

Games live in `SCRIPTS/GAMES/`; the launcher is `SCRIPTS/TOOLS/Games.lua`. To add a game, drop its `.lua` file into `SCRIPTS/GAMES/`.

| Game | Controls |
|------|----------|
| Pac-Man | Right stick steers |
| Pinball | SA = left flipper, SD = right flipper, ENTER launches |
| Flappy | ENTER or flick right stick up to flap |
| 2048 | Flick right stick to slide tiles, ENTER for a new game |
| Invaders | Aileron moves, ENTER or right stick up fires |
| Snake, Pong, Breakout, Asteroids, X-Tris, Simulator | Came with the original card |

More games: https://github.com/EdgeTX/lua-scripts (pick ones made for 128x64 B&W screens).
