// Headless EdgeTX simulator for test automation (TX12 MKII games project).
// Same firmware code as the FOX "simu" target; this file only replaces the GUI:
// it feeds keys / wheel / switches / sticks from a command file and saves the
// 128x64 screen as PBM images.
//
// usage: simu-headless <sdcard dir> <commands file> [out dir]
// commands (one per line, # comments):
//   wait MS                 let the radio run
//   press KEY [MS]          press and release (EXIT ENTER PAGEUP PAGEDN SYS MDL TELE)
//   long KEY                hold 1.2 s
//   key KEY 0|1             hold / release
//   rot N                   scroll wheel N steps (negative = back)
//   sw S POS                switch A..F, POS -1 up / 0 mid / 1 down
//   stick N V               raw stick N (0..3) to V (-1024..1024)
//   shot NAME               save screen to <out>/NAME.pbm
//   fuzz MS [seed]          random sticks + SA/SD + ENTER/wheel (never EXIT) for MS
//   quit
#include "opentx.h"
#include "targets/simu/simulcd.h"
#include <unistd.h>
#include <string>
#include <fstream>
#include <sstream>
#include <cstdlib>

extern "C" {
  extern size_t simuLuaMem, simuLuaMemPeak, simuLuaMemCap;
  extern unsigned simuLuaMemFail;
}
extern unsigned simuLuaCBoundaryHits, simuLuaBudgetYields, simuLuaMaxCycleInstr;
extern unsigned simuLuaBudget;
extern char simuLuaCBoundaryWhere[];

static int16_t simSticks[4] = {0, 0, 0, 0};
static std::string outDir = ".";

uint16_t anaIn(uint8_t chan)
{
  if (chan < NUM_STICKS) return simSticks[chan];
  if (chan < NUM_STICKS + NUM_POTS + NUM_SLIDERS) return 1024;
  return 0;
}

uint16_t getAnalogValue(uint8_t index) { return anaIn(index); }
void createBitmap(int, uint16_t *, int, int, int, int) {}

extern volatile uint32_t rotencDt;

// one 10 ms tick of the "hardware": what the FOX GUI timer does
static void tick()
{
  per10ms();
  if (simuLcdRefresh) { simuLcdRefresh = false; lcdFlushed(); }
  usleep(10000);
}

static void run(int ms) { for (int t = 0; t < ms; t += 10) tick(); }

static int keyIndex(const std::string & k)
{
  if (k == "EXIT") return KEY_EXIT;
  if (k == "ENTER") return KEY_ENTER;
  if (k == "PAGEUP") return KEY_PAGEUP;
  if (k == "PAGEDN") return KEY_PAGEDN;
  if (k == "SYS") return KEY_SYS;
  if (k == "MDL") return KEY_MODEL;
  if (k == "TELE") return KEY_TELE;
  fprintf(stderr, "unknown key %s\n", k.c_str());
  exit(2);
}

static void shot(const std::string & name)
{
  std::string path = outDir + "/" + name + ".pbm";
  FILE * f = fopen(path.c_str(), "w");
  if (!f) return;
  fprintf(f, "P1\n%d %d\n", LCD_W, LCD_H);
  for (int y = 0; y < LCD_H; y++) {
    for (int x = 0; x < LCD_W; x++)
      fputc((simuLcdBuf[x + (y / 8) * LCD_W] & (1 << (y % 8))) ? '1' : '0', f);
    fputc('\n', f);
  }
  fclose(f);
}

static void rot(int n)
{
  for (int i = 0; i < abs(n); i++) {
    ROTARY_ENCODER_NAVIGATION_VALUE += (n > 0 ? 1 : -1) * ROTARY_ENCODER_GRANULARITY;
    rotencDt += 100;
    run(60);
  }
}

static void fuzz(int ms, unsigned seed)
{
  srand(seed);
  for (int t = 0; t < ms; t += 50) {
    int r = rand() % 100;
    if (r < 20) simuSetSwitch(0, (rand() & 1) ? 1 : -1);        // SA momentary
    else if (r < 40) simuSetSwitch(3, (rand() & 1) ? 1 : -1);   // SD momentary
    else if (r < 55) simSticks[rand() % 4] = (rand() % 2049) - 1024;
    else if (r < 58) { simuSetKey(KEY_ENTER, true); run(80); simuSetKey(KEY_ENTER, false); }
    else if (r < 60) rot((rand() & 1) ? 1 : -1);
    run(50);
  }
  simuSetSwitch(0, -1); simuSetSwitch(3, -1);
  for (int i = 0; i < 4; i++) simSticks[i] = 0;
}

int main(int argc, char ** argv)
{
  if (argc < 3) { fprintf(stderr, "usage: simu-headless <sd dir> <commands> [out dir]\n"); return 2; }
  if (argc > 3) outDir = argv[3];
  if (getenv("LUA_MEM_CAP")) simuLuaMemCap = atoi(getenv("LUA_MEM_CAP"));
  if (getenv("LUA_BUDGET")) simuLuaBudget = atoi(getenv("LUA_BUDGET"));
  setvbuf(stdout, nullptr, _IOLBF, 0);

  for (int i = 0; i < NUM_SWITCHES; i++) simuSetSwitch(i, -1);
  simuInit();
  simuStart(false, argv[1], nullptr);
  run(3000);   // boot

  std::ifstream in(argv[2]);
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream ss(line);
    std::string cmd;
    if (!(ss >> cmd) || cmd[0] == '#') continue;
    if (cmd == "wait") { int ms; ss >> ms; run(ms); }
    else if (cmd == "press") { std::string k; int ms = 150; ss >> k >> ms; simuSetKey(keyIndex(k), true); run(ms); simuSetKey(keyIndex(k), false); run(150); }
    else if (cmd == "long") { std::string k; ss >> k; simuSetKey(keyIndex(k), true); run(1200); simuSetKey(keyIndex(k), false); run(150); }
    else if (cmd == "key") { std::string k; int v; ss >> k >> v; simuSetKey(keyIndex(k), v); }
    else if (cmd == "rot") { int n; ss >> n; rot(n); }
    else if (cmd == "sw") { std::string s; int p; ss >> s >> p; simuSetSwitch(s[0] - 'A', p); }
    else if (cmd == "stick") { int n, v; ss >> n >> v; simSticks[n & 3] = v; }
    else if (cmd == "shot") { std::string n; ss >> n; shot(n); }
    else if (cmd == "fuzz") { int ms; unsigned seed = 1; ss >> ms >> seed; fuzz(ms, seed); }
    else if (cmd == "quit") break;
    else fprintf(stderr, "unknown command: %s\n", line.c_str());
  }

  printf("STATS luaMemPeak=%u luaMemNow=%u cap=%u allocFails=%u cBoundaryHits=%u budgetYields=%u maxCycleInstr=%u\n",
         (unsigned)simuLuaMemPeak, (unsigned)simuLuaMem, (unsigned)simuLuaMemCap, simuLuaMemFail,
         simuLuaCBoundaryHits, simuLuaBudgetYields, simuLuaMaxCycleInstr);
  if (simuLuaCBoundaryHits) printf("CBOUNDARY first at %s\n", simuLuaCBoundaryWhere);
  fflush(stdout);
  _exit(0);   // the firmware threads don't need a clean shutdown
}
