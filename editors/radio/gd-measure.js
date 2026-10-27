// Geometry Dash performance meter: runs the game's real GDASH/phys.lua and draw.lua on a
// TX12Radio and records, for every level column, the lcd draw calls
// and Lua instructions of one frame with the screen centred on it (the most over the camera heights a tall level can
// show). Drawing is the part of a frame that grows with what is on screen; physics stays
// about the same everywhere.
//
//   var m = GDMeasure.start(radio, levelSource, function (done, total) {}, function (res) {});
//   res = { cols, calls: Int32Array, instr: Int32Array, maxCalls, maxCallsCol, maxInstr, maxInstrCol }
//   m.cancel()
(function (root) {
"use strict";
var SETUP = [
  "function __gdm_setup(src)",
  "  local lv = load(src)()",
  "  local tile, step, music, endX, newP, N = loadScript('/SCRIPTS/GAMES/GDASH/phys.lua')()(lv)",
  "  __gdm = { draw = loadScript('/SCRIPTS/GAMES/GDASH/draw.lua')()(tile, endX, N), newP = newP, N = N, endX = endX }",
  "  return 0",
  "end",
  // one frame with the camera at world x (icon at x + 28) and screen offset oy = 8 * k
  "function __gdm_frame(arg)",
  "  local x, k = string.match(arg, '(%S+) (%S+)')",
  "  local P = __gdm.newP(); P.x = tonumber(x); P.y = 18 - 8 * tonumber(k)",
  "  __gdm.draw(P, nil, true, 'A1', 50, 1)",
  "  return 0",
  "end",
  "function __gdm_info() return __gdm.endX * 100 + __gdm.N end"
].join("\n");

function start(radio, src, progress, finish) {
  var err = radio.exec(SETUP);
  if (err) { finish({ error: err }); return { cancel: function () {} }; }
  radio.files["/__gdm_level.lua"] = src;
  err = radio.exec("__gdm_setup(__readfile('/__gdm_level.lua'))");
  if (err) { finish({ error: err }); return { cancel: function () {} }; }
  var info = 0;
  radio.exec("__gdm_i = __gdm_info()");
  // read back endX and N through a file (keeps tx12-radio.js small)
  radio.exec("__writefile('/__gdm_info', tostring(__gdm_i))");
  info = +radio.files["/__gdm_info"];
  var endX = Math.floor(info / 100), N = info % 100;
  var cols = Math.ceil(endX / 8) + 1, bands = Math.max(1, N - 5);
  var calls = new Int32Array(cols), instr = new Int32Array(cols);
  var col = 0, band = 0, done = 0, total = cols * bands, stop = false;
  function frame(x, k) {
    radio.calls = 0; radio.instr = 0;
    var e = radio.exec("__gdm_frame('" + x + " " + k + "')");
    if (e) throw new Error(e);
    return [radio.calls, radio.instr];
  }
  function chunk() {
    if (stop) return;
    var t0 = Date.now();
    try {
      while (band < bands && Date.now() - t0 < 30) {
        var r = frame(col * 8 - 36, band);  // screen centred on this column (camera = x - 28)
        if (r[0] > calls[col]) calls[col] = r[0];
        if (r[1] > instr[col]) instr[col] = r[1];
        done++;
        if (++col >= cols) { col = 0; band++; }
      }
    } catch (e) { finish({ error: String(e.message || e) }); return; }
    if (progress) progress(done, total);
    if (band < bands) { setTimeout(chunk, 0); return; }
    var mc = 0, mcc = 0, mi = 0, mic = 0;
    for (var c = 0; c < cols; c++) {
      if (calls[c] > mc) { mc = calls[c]; mcc = c; }
      if (instr[c] > mi) { mi = instr[c]; mic = c; }
    }
    finish({ cols: cols, calls: calls, instr: instr, maxCalls: mc, maxCallsCol: mcc, maxInstr: mi, maxInstrCol: mic });
  }
  setTimeout(chunk, 0);
  return { cancel: function () { stop = true; } };
}
root.GDMeasure = { start: start };
})(typeof window !== "undefined" ? window : globalThis);
