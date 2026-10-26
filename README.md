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
| Donkey Kong | Either stick left/right walks, stick up/down climbs ladders, SA/SD/ENTER jumps |
| Doodle Jump | Either stick left/right steers, bouncing is automatic |
| Dino | SA, SD, ENTER or stick up jumps |
| Geometry Dash | SA, SD or ENTER jumps |
| Crossy Road | Flick right stick to hop (centre it between hops) |
| Racer | Right stick or rudder steers, throttle stick or right stick up = gas, down = brake. 3 laps vs 3 AI cars |
| Tower Defense | Right stick moves cursor, SA/SD/ENTER builds or upgrades a tower |
| Minesweeper | Stick flicks or wheel move, ENTER/SA reveals, SD flags |
| Battleship | SD reshuffles your fleet, SA/ENTER starts; stick or wheel aims, SA/SD/ENTER fires |
| Simon | Repeat the arrow sequence with right-stick flicks |
| Tamagotchi | Wheel + ENTER picks Feed/Play/Sleep, SA feeds, SD plays. The pet ages while the radio is off (saved in `SCRIPTS/GAMES/pet.dat`) |
| Blackjack | Wheel/stick sets bet, SA hits, SD stands, stick up doubles |
| Poker | Stick or wheel picks a card, SA holds, SD/ENTER draws |
| Plinko | Right stick aims, SA/SD/ENTER drops |
| Artillery | Right stick: left/right angle, up/down power (wheel fine-tunes), SA/SD/ENTER fires |
| Rhythm | Right stick moves the cursor, SA/SD/ENTER taps when the ring meets the circle |
| Snake, Pong, Breakout, Asteroids, X-Tris, Simulator | Came with the original card |

More games: https://github.com/EdgeTX/lua-scripts (pick ones made for 128x64 B&W screens).

Writing or fixing a game? Read [GAME_DEV_GUIDELINES.md](GAME_DEV_GUIDELINES.md) first: radio memory, the missing `table` library, input, timing and how to test with `tools/tx12sim`.
