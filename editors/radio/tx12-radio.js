// A TX12 running one Lua tool script, in the browser (or node): the real game code under
// fengari (Lua 5.3 in JS, close to the radio's 5.2 for what the games use), the radio's
// screen from tx12-lcd.js, and EdgeTX's timing: run() is called every 50 ms and getTime()
// moves 5 ticks per call, like the 20 Hz menu task of EdgeTX 2.8 on the TX12.
// Per frame it counts lcd draw calls, Lua instructions (in steps of 10) and writes outside
// the screen memory.
//
//   var r = TX12Radio.create({ fengari: fengari, files: { "/SCRIPTS/GAMES/x.lua": "..." },
//                              tone: function (hz, ms) {} });
//   r.start("/SCRIPTS/GAMES/Game-GeometryDash.lua");   // runs init()
//   r.input.sa = 1024;                                  // switches / sticks, -1024..1024
//   var f = r.frame(EVT.ENTER);  // f = { calls, instr, oob, exit, error }
(function (root) {
"use strict";
var EVT = { NONE: 0, EXIT: 1, ENTER: 2, NEXT: 3, PREV: 4, ENTER_LONG: 5, MENU: 6 };

function create(opt) {
  var F = opt.fengari, lua = F.lua, lauxlib = F.lauxlib, lualib = F.lualib, S = F.to_luastring;
  var Lcd = root.TX12Lcd, scr = opt.screen || new Lcd.Screen(), fl = Lcd.flags;
  var files = {}, k;
  for (k in opt.files) files[k] = opt.files[k];
  var r = { screen: scr, files: files, input: { sa: -1024, sd: -1024, sb: -1024, sc: -1024, thr: -1024, ele: 0, ail: 0, rud: 0 },
    time: 0, calls: 0, instr: 0, error: null, exited: false, tone: opt.tone || function () {} };
  var L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  function num(i) { return lua.lua_tonumber(L, i); }
  // luaL_checkinteger on the radio (ARM): C cast, truncates toward zero
  function int(i) { return Math.trunc(lua.lua_tonumber(L, i)) | 0; }
  // luaL_checkunsigned stored in an int coord: modulo 2^32, so -3.5 becomes -4
  function uns(i) { var n = lua.lua_tonumber(L, i); n = n - Math.floor(n / 4294967296) * 4294967296; return Math.floor(n) | 0; }
  function optu(i, d) { return lua.lua_isnoneornil(L, i) ? d : uns(i); }
  function reg(name, fn) { lua.lua_pushjsfunction(L, function () { r.calls++; fn(); return 0; }); lua.lua_setfield(L, -2, S(name)); }

  lua.lua_newtable(L);
  reg("clear", function () { scr.clear(); });
  reg("drawPoint", function () { scr.point(int(1), int(2), optu(3, 0)); });
  reg("drawLine", function () {
    var x1 = uns(1), y1 = uns(2), x2 = uns(3), y2 = uns(4), pat = uns(5) & 255, f = uns(6);
    if (x1 > 128 || y1 > 64 || x2 > 128 || y2 > 64) return;  // the radio's check: lets 128 / 64 and negatives through
    if (pat === fl.SOLID && x1 === x2) { scr.vline(x1, Math.min(y1, y2), Math.abs(y2 - y1) + 1, 0xff, f); return; }
    if (pat === fl.SOLID && y1 === y2) { scr.hline(Math.min(x1, x2), y1, Math.abs(x2 - x1) + 1, 0xff, f); return; }
    scr.line(x1, y1, x2, y2, pat, f);
  });
  reg("drawRectangle", function () { scr.rect(int(1), int(2), int(3), int(4), 0xff, optu(5, 0)); });
  reg("drawFilledRectangle", function () { scr.fillRect(int(1), int(2), int(3), int(4), 0xff, optu(5, 0)); });
  reg("drawText", function () { scr.text(int(1), int(2), lua.lua_tojsstring(L, 3) || "", optu(4, 0)); });
  reg("drawNumber", function () { scr.number(int(1), int(2), int(3), optu(4, 0)); });
  reg("drawSwitch", function () {});
  reg("drawSource", function () {});
  reg("drawTimer", function () { var s = int(3), m = Math.floor(Math.abs(s) / 60); scr.text(int(1), int(2), (s < 0 ? "-" : "") + (m < 10 ? "0" : "") + m + ":" + ("0" + Math.abs(s) % 60).slice(-2), optu(4, 0)); });
  reg("drawScreenTitle", function () {});
  reg("drawPixmap", function () {});  // bitmap files are not loaded here
  reg("refresh", function () {});
  reg("resetBacklightTimeout", function () {});
  lua.lua_setglobal(L, S("lcd"));

  function glob(name, fn) { lua.lua_pushjsfunction(L, fn); lua.lua_setglobal(L, S(name)); }
  glob("getTime", function () { lua.lua_pushinteger(L, r.time); return 1; });
  glob("getValue", function () {
    var n = lua.lua_tojsstring(L, 1), v = r.input[n];
    lua.lua_pushinteger(L, v == null ? 0 : v); return 1;
  });
  glob("playTone", function () { r.tone(num(1), num(2)); return 0; });
  glob("getAvailableMemory", function () { lua.lua_pushinteger(L, 88 * 1024); return 1; });
  glob("__readfile", function () {
    var p = lua.lua_tojsstring(L, 1), d = files[p];
    if (d == null) lua.lua_pushnil(L); else lua.lua_pushstring(L, S(d, true));
    return 1;
  });
  glob("__writefile", function () { files[lua.lua_tojsstring(L, 1)] = lua.lua_tojsstring(L, 2); return 0; });
  glob("__listdir", function () {
    var p = lua.lua_tojsstring(L, 1) + "/", out = [];
    Object.keys(files).forEach(function (f) { if (f.indexOf(p) === 0 && f.slice(p.length).indexOf("/") < 0) out.push(f.slice(p.length)); });
    lua.lua_pushstring(L, S(out.join("\n"))); return 1;
  });

  var pre = "table = nil\nLCD_W, LCD_H = 128, 64\n";
  for (k in fl) pre += k + " = " + fl[k] + "\n";
  for (k in EVT) pre += "EVT_VIRTUAL_" + k + " = " + EVT[k] + "\n";
  pre += [
    "EVT_ENTER_BREAK, EVT_EXIT_BREAK, EVT_ROT_RIGHT, EVT_ROT_LEFT = 2, 1, 3, 4",
    "PLAY_NOW, PLAY_BACKGROUND = 1, 2",
    "function playFile() end function playNumber() end function playHaptic() end function killEvents() end",
    "function getDateTime() local s = math.floor(getTime() / 100) return { year = 2026, mon = 1, day = 1, hour = 12, min = math.floor(s / 60) % 60, sec = s % 60 } end",
    "do local cg = collectgarbage; collectgarbage = function(...) local ok, r = pcall(cg, ...); return ok and r or 0 end end",
    // io the EdgeTX way: io.open(path, mode), io.read(f, n), io.write(f, ...), io.close(f)
    "io = { open = function(p, m) if m and string.sub(m, 1, 1) == 'w' then return { p = p, w = '' } end",
    "  if m and string.sub(m, 1, 1) == 'a' then return { p = p, w = __readfile(p) or '' } end",
    "  local d = __readfile(p) if not d then return nil end return { p = p, d = d, pos = 1 } end,",
    "  read = function(f, n) if not f.d or f.pos > #f.d then return '' end local s = string.sub(f.d, f.pos, f.pos + (n or 1) - 1) f.pos = f.pos + #s return s end,",
    "  write = function(f, ...) if f.w then for _, v in ipairs({...}) do f.w = f.w .. tostring(v) end end end,",
    "  close = function(f) if f.w then __writefile(f.p, f.w) end end }",
    "function loadScript(p, mode) local d = __readfile(p) if not d then return nil end return load(d, '@' .. p) end",
    "function dir(p) return string.gmatch(__listdir(p), '[^\\n]+') end",
    "function __start(p) local c = assert(loadScript(p)) __g = c() if __g.init then __g.init() end end",
    "function __run(e) return __g.run(e) end"
  ].join("\n");
  if (lauxlib.luaL_dostring(L, S(pre)) !== 0) throw new Error(lua.lua_tojsstring(L, -1));

  // instruction counter: a count hook every 10 VM instructions
  lua.lua_sethook(L, function () { r.instr += 10; }, lua.LUA_MASKCOUNT, 10);

  function call(name, arg) {
    lua.lua_getglobal(L, S("debug")); lua.lua_getfield(L, -1, S("traceback")); lua.lua_remove(L, -2);
    var base = lua.lua_gettop(L);
    lua.lua_getglobal(L, S(name));
    var n = 0;
    if (arg !== undefined) { if (typeof arg === "string") lua.lua_pushstring(L, S(arg)); else lua.lua_pushinteger(L, arg); n = 1; }
    var st = lua.lua_pcall(L, n, 1, base);
    var res = st === 0 ? lua.lua_tonumber(L, -1) : null;
    if (st !== 0) r.error = lua.lua_tojsstring(L, -1);
    lua.lua_settop(L, base - 1);
    return res;
  }
  r.start = function (path) {
    r.error = null; r.exited = false; r.calls = 0; r.instr = 0;
    call("__start", path);
    return !r.error;
  };
  // one 50 ms frame
  r.frame = function (event) {
    if (r.error || r.exited) return { calls: 0, instr: 0, oob: 0, exit: r.exited, error: r.error };
    r.time += 5;
    r.calls = 0; r.instr = 0; scr.oob = 0;
    var res = call("__run", event || 0);
    if (res != null && res !== 0) r.exited = true;
    return { calls: r.calls, instr: r.instr, oob: scr.oob, exit: r.exited, error: r.error };
  };
  // run Lua source in this state (tools: measuring, debugging)
  r.exec = function (src) { if (lauxlib.luaL_dostring(L, S(src)) !== 0) { var e = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return e; } return null; };
  r.L = L;
  return r;
}
root.TX12Radio = { create: create, EVT: EVT };
})(typeof window !== "undefined" ? window : globalThis);
