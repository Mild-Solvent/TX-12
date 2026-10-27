// TX12 (EdgeTX 2.8, 128x64 B&W) screen, ported from EdgeTX radio/src/gui/128x64/lcd.cpp
// and radio/src/lua/api_lcd.cpp (GPLv2, https://github.com/EdgeTX/edgetx), fonts from
// radio/src/fonts/std. Same pixels, same flag values, same quirks: lines ending at
// x = 128 / y = 64 are accepted, rectangles and points at negative x/y are not clipped.
// Writes outside the 1 KB display buffer are skipped here and counted in .oob (on the
// radio they overwrite other memory).
(function (root) {
"use strict";
var LCD_W = 128, LCD_H = 64, SIZE = LCD_W * LCD_H / 8;
// flags (gui/128x64/lcd.h)
var BLINK = 0x01, INVERS = 0x02, RIGHT = 0x04, CONDENSED = 0x08, FIXEDWIDTH = 0x10, CENTERED = 0x20, BOLD = 0x40,
    FORCE = 0x02, ERASE = 0x04, ROUND = 0x08, SMLSIZE = 0x0200, MIDSIZE = 0x0300, DBLSIZE = 0x0400, FONTMASK = 0x0700,
    PREC1 = 0x10, PREC2 = 0x20, LEADING0 = 0x08, SOLID = 0xff, DOTTED = 0x55;
function hex(s) { var a = new Uint8Array(s.length / 2); for (var i = 0; i < a.length; i++) a[i] = parseInt(s.substr(i * 2, 2), 16); return a; }
var F = {"f4x6": "0000ffffffffff2fffffff070007ff143e143e14042a3e2a1013080432ff142a1420ffff07ffffffff1e21ffffff211effffff2a1c2aff08083e0808ff403010ff08080808ffff20ffffff10080402ff1e21211eff00223f20ff22312926ff1125251bff0c0a3f08ff17252519ff1e252518ff01310d03ff1a25251aff0629291effff14ffffffff761600ffff081422ff14141414ffff221408ffff022906ff020502ffff3e09093eff3f25251aff1e212112ff3f21211eff3f252521ff3f050501ff1e21293aff3f04043fff213f21ffff1020201fff3f0c1221ff3f202020ff3f0204023f3f06183fff1e21211eff3f090906ff1e31215eff3f091926ff12252912ff013f01ffff1f20201fff0f30300fff3f180c183f330c0c33ff073807ffff31292523ff3f2121ffff02040810ff21213fffff020102ffff20202020ff0102ffffff1824143cff3f242418ff182424ffff1824243fff18342c08ff083e0902ff2854544cff3f040438ff243d20ffff20403dffff3f081420ff213f20ffff3c08380c383c040438ff18242418ff7c242418ff1824247cff3c040408ff282c3414ff041f2420ff1c20203cff1c201cffff3c3018303c24181824ff0c50201cff24342c24ff041e21ffffff3fffffff211e04ffff082a1c08ff081c2a08ff", "f5x7": "0000ffffffffff6fffffff070007ff1830180c06087f7f7f0823130864623649552250ff0503ffffff1c2241ffff41221cff14083e081408083e0808ff5030ffff00080808ffffff40ffff20100804023e41413eff00427f40ff62514946ff41494936ff1814127fff27454539ff3e494932ff01790503ff36494936ff0649291effff3636ffffff5636ffffff08142241141414141441221408ff020151090606090906ff7e0909097e7f494949363e414141227f4141221c7f494949417f090909013e4149497a7f0808087fff417f41ff2040413f017f081422417f404040ff7f020c027f7f0408107f3e4141413e7f090909063e4151215e7f09192946264949493201017f01013f4040403f1f2040201f3f4030403f631408146307087008076151494543ff7f4141ff0204081020ff41417fff040201020440404040ffff010204ff20545454787f484444383844444420384444487f3854545418087e0901020c5252523e7f08040478ff447d40ff2040443dff7f102844ffff417f40ff7c041804787c0804047838444444387c14141408081414187c7c080404084854545420043f4440203c4040207c1c2040201c3c4020403c44281028440c5050503c4464544c4410081008ffffff7fffff41225428ff0808221c08081c220808", "f8x10": "0000000000000000fffffffffffffffffffffffffe05fe05ffffffffffffffffffff0e000e0000000e000e00ffffffff9000fc03fc039000fc03fc039000ffff38027c066404fe0fc404cc078803ffff0c041e078c03e00070001c038e0702038003dc077e047204de068c038007c004ffffffff1e001e00fffffffffffffffffffff000fc030e07030c0108ffffffffffff0108030c0e07fc03f000ffffffff40005001f001e000f00150014000ffffffff40004000f00140004000ffffffffffffffff8009800f8007ffffffffffffffff40004000400040004000ffffffffffffffffffff00060006ffffffffffff000400078003e00070001c000e000200fffffc03fe0702040204fe07fc03ffffffff08040c04fe07fe0700040004ffffffff0c060e078205e2047e041c04ffffffff0c030e0722042204fe07dc03ffffffffc001e0013001fc07fe070001ffffffff3e033e0712041204f207e203fffffffff803fc0726042204ee07cc03ffffffff0e000e00e207fa071e000600ffffffff9c03fe0762046204fe079c03ffffffff3c037e0742044206fe03fc01ffffffffffff98019801ffffffffffffffffffff08009c099c0f8807ffffffffffffffff6000f00098010c0306060204ffffffff200120012001200120012001ffffffff020406060c039801f0006000ffff0c000e008206c20662003e001c00ffffffff0c001e00120012001e000c00fffff007f8078c00860086008c00f807f007fe07fe072204220422047606dc038801f801fc03060602040204020406060c03fe07fe070204020402040606fc03f801fe07fe0722042204220422040204fffffe07fe07220022002200220002000200f801fc030606020402044204c607c403fe07fe072000200020002000fe07fe07ffff02040204fe07fe0702040204ffffffff0003000602040206fe03fe01fffffe07fe076000f00098010c0306060204fe07fe0700040004000400040004fffffe07fe070c00780078000c00fe07fe07fe07fe071c007800e0008003fe07fe07f801fc030606020402040606fc03f801fe07fe0722002200220022003e001c00f801fc030606820482050607fc03f805fe07fe0762006200e200a2013e071c061c023e062204220422042204e607c403020002000200fe07fe07020002000200fe01fe030006000400040006fe03fe010e007e00f00180078007f0017e000e00fe07fe070003e001e0010003fe07fe0706060e079801f000f00098010e07060606000e001800f007f00718000e00060002078207c204620432041e040e04fffffffffe07fe07020402040204ffffffff02000e001c007000e000800300070004ffffffff020402040204fe07fe07ffffffff18000c00060006000c001800ffff00080008000800080008000800080008ffffffff0100030006000400ffffffff0003a007b00490049002f007e007fffffe07fe07200210043006e003c001ffffc001e00330061004100430062002ffffc001e003300610042002fe07fe07ffffc001e003b0069004b004e006c002ffff40004000fc07fe0742000e000c00ffff6005f00f900a900af00a600e3004fffffe07fe07200010003000e007c007ffff00041004f607f60700040004ffffffff0007000f000810081008f60ff607fffffe07fe07c001600330060004ffffffff00040204fe07fe0700040004fffffffff007e0071000e0071000f007e007fffff007f007200010003000e007c007ffffc001e003300610043006e003c001fffff00ff00f10011001b001e000c000ffffc000e000b00110011001f00ff00fffff1000f007e0073000100030002000ffff6002f006900490049004b0072003ffff10001000fc03fc07100410060002fffff001f003000600040002f007f007ffff3000f000c0030007c003f0003000fffff003f0070006c0030006f007f003ffff100430066003c001600330061004fffff004f00c00090009800cf007f003ffff100610079005d00470043004ffffffffffff6000fe079f0f01080108fffffffffffffffffffffe07fe07ffffffffffffffffffff010801089f0ffe076000ffff60006000600064026801f0006000ffff6000f00068016402600060006000ffff", "f10x14": "00000000000000000000000000000000000000000000000000000000fe71fe710000000000000000000000003e007e00000000007e003e000000000060066006fe7ffe7f60066006fe7ffe7f600660066018f01898199819fe7ffe7f98199819180f18060c181e1c1e0e0c078003c001e030707838781830781efc3f8e71c663e66776663c3c183c0066006600000000660076003e001e00000000000000000000000000e007f00f381c1c380e700660000000000000000006600e701c38381cf00fe0070000000060066006c0038001f81ff81f8001c003600660068001800180018001f81ff81f80018001800180010000000000660076003e001e000000000000000080018001800180018001800180018001ffffffff00000000003000780078003000000000000000000018001c000e00078003c001e000700038001800f81ffc3f0e70066006600e70fc3ff81fffffffff000018601c60fe7ffe7f006000600000ffffffff18781c7c0e6e06678663ce61fc607860ffffffff06600660866186618661ce73fc3f781effffffff8007c007e006700638061c06fe7ffe7fffffffff7e187e38667066606660e670c63f861ffffffffff81ffc3f8e71866186618e731c3f181effffffff06000600867fc67fe60076003e001e00ffffffff781efc3fce7386618661ce73fc3f781effffffff7800fc00ce6186718639ce1dfc0ff807ffffffff00000000300c781e781e300c00000000000000000000000030667876783e301e0000000000000000000000008001c003e007700e381c1c380e700660600660066006600660066006600660066006600606600e701c38381c700ee007c00380010000000018001c000e000600066606678603ce01fc0078007800fc00ce0186018601ce01fc00780000000000e07ff07fb8019c018e018e019c01b801f07fe07ffe7ffe7f86618661866186618661ce73fc3f781ef81ffc3f0e7006600660066006600e701c381818fe7ffe7f0660066006600e701c38381cf00fe007fe7ffe7f86618661866186618661866106600660fe7ffe7f86018601860186018601860106000600f81ffc3f0e7006608661866186618e719c7f983ffe7ffe7f800180018001800180018001fe7ffe7f06600660fe7ffe7f06600660ffffffffffffffff001800380070006006600670fe3ffe1f06000600fe7ffe7f8001c003e007700e381c1c380e700660fe7ffe7f00600060006000600060006000600060fe7ffe7f1c003800f001f00138001c00fe7ffe7ffe7ffe7f7000e000c00180030007000efe7ffe7ff81ffc3f0e7006600660066006600e70fc3ff81ffe7ffe7f86018601860186018601ce01fc007800f81ffc3f0e7006600666066e063c0e38fc7ff867fe7ffe7f860186018607860f861dce39fc7078607818fc38ce7186618661866186618e731c3f181e0600060006000600fe7ffe7f0600060006000600fe1ffe3f007000600060006000600070fe3ffe1ffe07fe0f001c0038007000700038001cfe0ffe07fe1ffe3f00700070003e003e00700070fe3ffe1f1e783e7c700ee007c003c003e007700e3e7c1e787e00fe00c0018003007f007f8003c001fe007e000678067c066e06678663c661e66076603e601e6000000000fe7ffe7f066006600660066000000000180038007000e000c00180030007000e001c0018000000000660066006600660fe7ffe7f000000006000700038001c000e000e001c0038007000600000600060006000600060006000600060006000600000000006000e001c00380070006000000000000018003c607e6066606660666066e066c07f807ffe7ffe7f8061c061e06060606060e070c03f801f801fc03fe0706060606060606060607000380018801fc03fe07060606060e060c0618061fe7ffe7f801fc03fe0766066606660666066e066c007800780018001f87ffc7f8e01860106000e001c001800e001f003386718661866186618661876f83ff81ffe7ffe7f8001c001e00060006000e000c07f807f60606060e67fe67f00600060ffffffffffffffff001800380070006060606070e63fe61ffffffffffe7ffe7f0006000f801fc039e0706060ffffffff06600660fe7ffe7f00600060ffffffffffffffffe07fe07f6000e000c007c007e000e000c07f807fe07fe07f8001c001e00060006000e000c07f807f801fc03fe0706060606060606060e070c03f801fe07fe07f60066006600660066006e007c00380018001c003e007600660066006c0078007e07fe07fe07fe07f8001c001e00060006000e000c00180018061c063e0676066606660666066607e003c001860006000fe1ffe3f607060600060007000380018e01fe03f007000600060007000380018e07fe07fe007e00f001c0038007000700038001ce00fe007e01fe03f007000700038003800700070e03fe01f6060e070c039801f000f000f801fc039e0706060e001e003006700660066006600660076e03fe01f606060706078607c606e6067e063e061e0606060000000008001c003781e7c3e0e700660000000000000000000000000fe7ffe7f00000000000000000000000006600e707c3e781ec00380010000000080018001800180011818381cf00fe007c00380018001c003e007f00f381c18188001800180018001"};
var f4x6 = hex(F.f4x6), f5x7 = hex(F.f5x7), f8x10 = hex(F.f8x10), f10x14 = hex(F.f10x14);

function Screen() { this.buf = new Uint8Array(SIZE); this.oob = 0; this.nextPos = 0; }
var S = Screen.prototype;
S.clear = function () { this.buf.fill(0); };
S.get = function (x, y) { return (this.buf[(y >> 3) * LCD_W + x] >> (y & 7)) & 1; };
// p = byte index into the display buffer (may be outside it)
S.mask = function (p, m, att) {
  if (p < 0 || p >= SIZE) { this.oob++; return; }
  if (att & FORCE) this.buf[p] |= m; else if (att & ERASE) this.buf[p] &= ~m & 255; else this.buf[p] ^= m;
};
// C integer division and modulo truncate toward zero
function cdiv(a, b) { return (a / b) | 0; }
function cmod(a, b) { return a % b; }
S.point = function (x, y, att) {
  var p = cdiv(y, 8) * LCD_W + x;
  if (p < SIZE) this.mask(p, (1 << cmod(y, 8)) & 255, att);  // no lower bound check, like the radio
};
S.hline = function (x, y, w, pat, att) {
  if (y >= LCD_H) return;
  if (x + w > LCD_W) w = LCD_W - x;
  var p = cdiv(y, 8) * LCD_W + x, m = (1 << cmod(y, 8)) & 255;
  while (w-- > 0) {
    if (pat & 1) { this.mask(p, m, att); pat = (pat >> 1) | 0x80; } else pat = pat >> 1;
    p++;
  }
};
S.vline = function (x, y, h, pat, att) {
  if (x >= LCD_W || y >= LCD_H) return;
  if (h < 0) { y += h; h = -h; }
  if (y < 0) { h += y; y = 0; }
  if (y + h > LCD_H) h = LCD_H - y;
  if (pat === DOTTED && !(y % 2)) pat = ~pat & 255;
  var p = cdiv(y, 8) * LCD_W + x;
  y = y & 7;
  if (y) {
    var msk = ~((1 << y) - 1) & 255;
    h -= 8 - y;
    if (h < 0) msk -= ~((1 << (8 + h)) - 1) & 255;
    this.mask(p, msk & pat, att); p += LCD_W;
  }
  while (h >= 8) { this.mask(p, pat, att); p += LCD_W; h -= 8; }
  if (h > 0) this.mask(p, ((1 << h) - 1) & pat, att);
};
S.line = function (x1, y1, x2, y2, pat, att) {
  var dx = x2 - x1, dy = y2 - y1, dxabs = Math.abs(dx), dyabs = Math.abs(dy), sdx = Math.sign(dx), sdy = Math.sign(dy);
  var x = dyabs >> 1, y = dxabs >> 1, px = x1, py = y1, i;
  if (dxabs >= dyabs) {
    for (i = 0; i <= dxabs; i++) {
      if ((1 << cmod(px, 8)) & pat) this.point(px, py, att);
      y += dyabs; if (y >= dxabs) { y -= dxabs; py += sdy; }
      px += sdx;
    }
  } else {
    for (i = 0; i <= dyabs; i++) {
      if ((1 << cmod(py, 8)) & pat) this.point(px, py, att);
      x += dxabs; if (x >= dyabs) { x -= dyabs; px += sdx; }
      py += sdy;
    }
  }
};
S.rect = function (x, y, w, h, pat, att) {
  this.vline(x, y, h, pat, att);
  this.vline(x + w - 1, y, h, pat, att);
  if (~att & ROUND) { x += 1; w -= 2; }
  this.hline(x, y + h - 1, w, pat, att);
  this.hline(x, y, w, pat, att);
};
S.fillRect = function (x, y, w, h, pat, att) {
  for (var i = y; i < y + h; i++) {
    if ((att & ROUND) && (i === y || i === y + h - 1)) this.hline(x + 1, i, w - 2, pat, att);
    else this.hline(x, i, w, pat, att);
    pat = ((pat >> 1) + ((pat & 1) << 7)) & 255;
  }
};

// ---- text ----
function remap(c) {
  if (c >= 44 && c <= 58) return c - 44 + 1;
  if (c >= 65 && c <= 90) return c - 65 + 16;
  if (c >= 97 && c <= 122) return c - 97 + 42;
  if (c === 95) return 4;
  return 0;
}
// [data, offset, width, height]
function pattern(c, flags) {
  var fs = flags & FONTMASK;
  if (fs === DBLSIZE) return [f10x14, remap(c) * 20, 10, 16];
  if (fs === MIDSIZE) return [f8x10, (c - 32) * 16, 8, 12];
  if (fs === SMLSIZE) return [f4x6, (c - 32) * 5, 5, 6];
  return [f5x7, (c - 32) * 5, 5, 7];
}
function patternWidth(pt) {
  var lines = (pt[3] + 7) >> 3, r = 0, d = pt[1];
  for (var i = 0; i < pt[2]; i++) { for (var j = 0; j < lines; j++) if (pt[0][d + j] !== 0xff) { r++; break; } d += lines; }
  return r;
}
S.putPattern = function (x, y, pt, flags) {
  var data = pt[0], q = pt[1], width = pt[2], height = pt[3];
  var inv = !!(flags & INVERS), lines = (height + 7) >> 3;
  for (var i = 0; i < width + 2; i++) {
    if (x >= 0 && x < LCD_W) {
      var b = [0, 0, 0, 0, 0], skip = false;
      if (i === 0) {
        if (x === 0 || !inv) { this.nextPos++; continue; }  // C: 'continue' skips the x++ below
        x--;
      } else if (i <= width) {
        skip = true;
        for (var j = 0; j < lines; j++) { b[j] = data[q++]; if (b[j] !== 0xff) skip = false; }
        if (skip) {
          if (flags & FIXEDWIDTH) { for (j = 0; j < lines; j++) b[j] = 0; }
          else continue;  // empty column: skipped, x does not advance
        }
        if ((flags & CONDENSED) && i === 2) continue;
      }
      for (var k = -1; k <= height; k++) {
        var plot;
        if (k < 0 || (k === height && (flags & FONTMASK) !== SMLSIZE)) {
          plot = false;
          if (height >= 12) continue;
          if (k < 0 && !inv) continue;
          if (y + k < 0) continue;
        } else plot = !!(b[k >> 3] & (1 << (k & 7)));
        if (inv) plot = !plot;
        if (!(flags & BLINK)) this.point(x, y + k, plot ? FORCE : ERASE);
      }
    }  // off screen: the radio does not step through the glyph data either
    x++;
    this.nextPos++;
  }
};
S.textWidth = function (s, flags) {
  var w = 0;
  for (var i = 0; i < s.length; i++) w += patternWidth(pattern(s.charCodeAt(i) & 255, flags)) + 1;
  return w;
};
S.text = function (x, y, s, flags) {
  flags = flags || 0;
  if (flags & RIGHT) x -= this.textWidth(s, flags);
  else if (flags & CENTERED) x -= (this.textWidth(s, flags) / 2) | 0;
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i) & 255;
    if (c < 32) continue;
    if (c > 127) c = 63;
    this.nextPos = x - 1;
    this.putPattern(x, y, pattern(c, flags), flags);
    x = this.nextPos;
  }
};
S.number = function (x, y, val, flags) {
  flags = flags || 0;
  var mode = flags & 0x30, neg = val < 0, s = "", idx = 0, dec = mode === PREC1 ? 1 : mode === PREC2 ? 2 : 0;
  val = Math.abs(val | 0);
  do { s = (val % 10) + s; idx++; val = (val / 10) | 0; if (dec && idx === dec) { s = "." + s; dec = 0; if (val === 0) s = "0" + s; } } while (val !== 0 || dec > 0);
  if (neg) s = "-" + s;
  this.text(x, y, s, flags & ~0x38);
};
// draw to a canvas 2d context, s px per pixel; ghost = previous frame weights (LCD smear)
S.blit = function (ctx, scale, prev, smear) {
  var img = ctx.createImageData(LCD_W * scale, LCD_H * scale), d = img.data;
  for (var y = 0; y < LCD_H; y++) for (var x = 0; x < LCD_W; x++) {
    var on = this.get(x, y), v = on ? 1 : 0;
    if (prev) { var k = y * LCD_W + x; if (smear) v = prev[k] + (v - prev[k]) * (1 - smear); prev[k] = v; }
    var r = 196 - v * 170, g = 210 - v * 175, bl = 186 - v * 150;
    for (var yy = 0; yy < scale; yy++) for (var xx = 0; xx < scale; xx++) {
      var o = ((y * scale + yy) * LCD_W * scale + x * scale + xx) * 4;
      d[o] = r; d[o + 1] = g; d[o + 2] = bl; d[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
};

root.TX12Lcd = {
  Screen: Screen, LCD_W: LCD_W, LCD_H: LCD_H,
  flags: { BLINK: BLINK, INVERS: INVERS, RIGHT: RIGHT, CENTER: CENTERED, BOLD: BOLD, FORCE: FORCE, ERASE: ERASE, ROUND: ROUND,
    SMLSIZE: SMLSIZE, MIDSIZE: MIDSIZE, DBLSIZE: DBLSIZE, PREC1: PREC1, PREC2: PREC2, LEADING0: LEADING0, SOLID: SOLID, DOTTED: DOTTED,
    GREY_DEFAULT: 0, TIMEHOUR: 0x0400 }
};
})(typeof window !== "undefined" ? window : globalThis);
