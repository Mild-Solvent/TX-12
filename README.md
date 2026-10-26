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

Games live in `SCRIPTS/GAMES/`; the launcher is `SCRIPTS/TOOLS/Games.lua`. To add a game, drop its `.lua` file into `SCRIPTS/GAMES/`. Some games keep data in a folder next to them (`GDASH/`, `RHYTHM/`, `DKONG/`, `DOODLE/`, `RACER/`, `PET/`, `POKER/`, `BLACKJACK/`); copy those too. Saves (`*.dat`) are written there by the games.

| Game | Controls |
|------|----------|
| Pac-Man | Right stick steers |
| Pinball | SA = left flipper, SD = right flipper, ENTER launches |
| Flappy | SA, SD or ENTER flaps (stick up too). Every 7 pipes: faster, tighter gaps swinging top to bottom |
| 2048 | Flick right stick to slide tiles, ENTER for a new game |
| Invaders | Either stick left/right moves, SA, SD or ENTER fires |
| Donkey Kong | Either stick walks, stick up/down climbs, SA/SD/ENTER jumps. 4 rotating stages (girders, pie factory, elevators, rivets = Kong boss); wheel on title picks start stage |
| Doodle Jump | Either stick steers, SA/SD shoots up. Zones, enemies, power-ups (spring shoes, propeller, jetpack, shield) |
| Dino | SA, SD, ENTER or stick up jumps |
| Geometry Dash | SA/SD/ENTER jumps. 8 levels Easy to Demon with music, level picker, best % saved, practice mode (wheel = checkpoints) |
| Crossy Road | Flick right stick to hop (centre it between hops) |
| Racer | Menu: 1P vs AI or 2P, 3/5 laps. P1 right stick (ail steer, ele gas/brake), P2 left stick (rud steer, throttle up = gas). Laps count only through all checkpoints |
| Tower Defense | Right stick cursor, wheel picks tower type, SA builds, SD upgrades, long ENTER sells, ENTER starts the wave |
| Minesweeper | Menu: size and difficulty. Stick/wheel move, ENTER/SA reveals, SD flags |
| Battleship | Menu: 1P vs AI or 2P hot-seat. Stick/wheel aims, SA/ENTER fires, SD switches target / my fleet view |
| Simon | Repeat the arrow sequence with right-stick flicks |
| Tamagotchi | Wheel + ENTER menu, SA feeds, SD plays mini-games (raise Joy). Set the radio date (Radio Setup) for real-time ageing |
| Blackjack | Menu: 1-4 players, rules. Wheel/stick bets, SA hits, SD stands, stick up doubles; controls always shown |
| Poker | Rules screen (scroll with wheel) on first start and from the menu. Stick/wheel picks a card, SA holds, SD/ENTER draws |
| Plinko | Right stick aims, SA/SD/ENTER drops |
| Artillery | Menu: 1P vs AI or 2P hot-seat. Right stick: angle / power, SA/SD/ENTER fires |
| Rhythm | Pick a song (5, Easy to Expert). Right stick aims, SA/SD taps; hold SA/SD on hold and slider notes |
| Snake, Pong, Breakout, Asteroids, X-Tris, Simulator | Came with the original card |

More games: https://github.com/EdgeTX/lua-scripts (pick ones made for 128x64 B&W screens).

Writing or fixing a game? Read [GAME_DEV_GUIDELINES.md](GAME_DEV_GUIDELINES.md) first: radio memory, the missing `table` library, input, timing and how to test with `tools/tx12sim`.
