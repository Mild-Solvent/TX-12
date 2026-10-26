// levels.txt -> L<n>.lua
// usage: node build.js <levels.txt> <out dir> [--plain]
// Source format (see the header of levels.txt):
//   = <n> [Name|Difficulty]   starts level n (Name|Difficulty becomes the "-- @" first line)
//   ! <u> <tune>              music: seconds per unit, then the tune tokens
//   ~<N>                      N empty columns
//   // ...                    comment
//   other lines               a segment: up to 6 rows of tiles, bottom-aligned
//                             (space = empty); segments are separated by blank lines
// Output rows are run-length coded (see encodeRow) unless --plain is given.
const fs = require("fs");

// Run-length code one row: a run of n >= 4 equal chars becomes "c*N" with
// N = String.fromCharCode(32 + n). Runs are capped at 94 and the count chars
// '"' (n=2) and '\' (n=60) are never written, so the result is a plain Lua string.
function encodeRow(s) {
  let out = "", i = 0;
  while (i < s.length) {
    let j = i;
    while (j < s.length && s[j] === s[i]) j++;
    let n = j - i;
    while (n > 0) {
      let k = Math.min(n, 94);
      if (k === 60) k = 59;
      if (k >= 4) out += s[i] + "*" + String.fromCharCode(32 + k);
      else out += s[i].repeat(k);
      n -= k;
    }
    i = j;
  }
  return out;
}
function decodeRow(s) {
  return s.replace(/(.)\*([\s\S])/g, (m, c, n) => c.repeat(n.charCodeAt(0) - 32));
}

function parse(text) {
  const src = text.replace(/\r/g, "").split("\n");
  const levels = {};
  let cur = null, seg = [];
  function flush() {
    if (!cur || !seg.length) return;
    const w = Math.max(...seg.map(s => s.length));
    const lines = seg.map(s => s.replace(/ /g, ".").padEnd(w, "."));
    if (lines.length > 6) throw new Error("segment >6 rows in level " + cur.n);
    for (let r = 0; r < 6; r++) { const li = lines.length - 1 - r; cur.rows[r] += li >= 0 ? lines[li] : ".".repeat(w); }
    seg = [];
  }
  for (const l of src) {
    if (l.startsWith("//")) continue;
    if (l.startsWith("= ")) {
      flush();
      const m = /^= (\d+)\s*(.*)$/.exec(l);
      const nd = (m[2] || "").split("|");
      cur = { n: +m[1], name: nd[0] || "", diff: nd[1] || "", rows: ["", "", "", "", "", ""] };
      levels[cur.n] = cur; continue;
    }
    if (l.startsWith("! ")) { const p = l.slice(2).split(" "); cur.u = p[0]; cur.m = p.slice(1).join(" "); continue; }
    if (l.startsWith("~")) { flush(); const n = +l.slice(1); for (let r = 0; r < 6; r++) cur.rows[r] += ".".repeat(n); continue; }
    if (l.trim() === "") { flush(); continue; }
    seg.push(l);
  }
  flush();
  return levels;
}

function luaStr(s) { return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }

// level {n, name, diff, rows[6] plain, u, m} -> file text (same layout as the editor's export)
function levelFile(lv, plain) {
  const len = Math.max(...lv.rows.map(r => r.length));
  // row 1 keeps its full length (it fixes where the level ends), rows 2-6 lose trailing dots
  const rows = lv.rows.map((r, i) => i === 0 ? r.padEnd(len, ".") : r.replace(/\.+$/, ""));
  const enc = rows.map(r => plain ? r : encodeRow(r));
  return "-- @" + (lv.name || ("Level " + lv.n)) + "|" + (lv.diff || "?") + "\n" +
    "-- Geometry Dash level " + lv.n + ": rows bottom (ground) to top, tiles see GDASH/phys.lua\n" +
    "-- u = seconds per music unit, m = looping tune: note+octave+length, R<n> = rest\n" +
    (plain ? "" : "-- rows are run-length coded: c*N = char c repeated byte(N)-32 times\n") +
    "return {\n" + enc.map(luaStr).join(",\n") +
    (lv.m ? ",\nu = " + lv.u + ",\nm = " + luaStr(lv.m) : "") + "\n}\n";
}

module.exports = { encodeRow, decodeRow, parse, levelFile };

if (require.main === module) {
  const plain = process.argv.includes("--plain");
  const args = process.argv.slice(2).filter(a => a !== "--plain");
  const levels = parse(fs.readFileSync(args[0], "utf8"));
  const out = args[1]; fs.mkdirSync(out, { recursive: true });
  for (const k in levels) {
    const lv = levels[k];
    for (const r of lv.rows) if (/[*"\\]/.test(r)) throw new Error("L" + k + ": rows may not contain * \" \\");
    const s = levelFile(lv, plain);
    fs.writeFileSync(out + "/L" + k + ".lua", s);
    const len = Math.max(...lv.rows.map(r => r.length));
    console.log("L" + k, "cols", len, "bytes", s.length);
    for (let r = 5; r >= 0; r--) console.log("  " + lv.rows[r]);
  }
}
