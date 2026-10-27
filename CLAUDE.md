# CLAUDE.md — TX-12

Lua games and tools for a RadioMaster TX12 (EdgeTX, 128x64 B&W). Read
[GAME_DEV_GUIDELINES.md](GAME_DEV_GUIDELINES.md) before writing or fixing a game.

## Repo layout

- `TX-12/` is the untouched backup of the original SD card. Never modify it.
- `My_TX-12/` is the live card copy. Games live in `My_TX-12/SCRIPTS/GAMES`,
  the launcher is `My_TX-12/SCRIPTS/TOOLS/Games.lua`.
- `tools/` holds test harnesses (`tx12sim`, `memcheck`, `edgetx-sim`, `gdash`),
  `editors/` holds the browser level/song editors.

## Keeping the repo tidy

1. `main` is the single source of truth. What is on the SD card should come from `main`.
2. One branch and one PR per task, branched from the latest `main`. Never stack a
   branch or PR on another branch.
3. Before merging, run the tests below. Claude may merge its own PRs into `main`
   once they pass, then deletes the branch right away.
4. After anything merges, every open branch rebases onto `main` before more work.
5. Notes and findings go into `GAME_DEV_GUIDELINES.md` or `docs/`. No loose
   session notes in the repo root.
6. Never commit secrets, and never rewrite `main`'s history.

## Tests before merge

```sh
# needs: apt-get install lua5.2; npm i fengari (in tools/tx12sim)
cd tools/tx12sim && node run.js ../../My_TX-12/SCRIPTS/GAMES 1500
cd tools/memcheck && lua5.2 memcheck.lua ../../My_TX-12/SCRIPTS/GAMES Game-X.lua 1500
```

- Every game's memcheck `live` must stay below Asteroids (about 70 KB); Geometry
  Dash aims for 65 or less. `Game-MemTest` is exempt (it fills memory on purpose).
- Geometry Dash level or physics changes: also run `tools/gdash/solve.js`.
- Before a game goes on the card, run it in `tools/edgetx-sim` (`cBoundaryHits` must be 0).
- Known, pre-existing tx12sim results on the original card games: Breakout reports
  `ERROR 0` and Snake exits at frame 540. These are not regressions.
