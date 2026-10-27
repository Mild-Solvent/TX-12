#!/bin/bash
# run.sh <card dir (ABSOLUTE path, e.g. a copy of My_TX-12)> <commands file> <out dir (absolute)>
# env: SIMU (binary, default /tmp/edgetx-sim/edgetx/build32/simu-headless)
#      LUA_MEM_CAP bytes (102400 = the 102 KB father's radio reached), LUA_BUDGET instructions per 50 ms cycle
# Prints the STATS line; screenshots land in <out> as .pbm and .png.
HERE="$(cd "$(dirname "$0")" && pwd)"
SIMU="${SIMU:-/tmp/edgetx-sim/edgetx/build32/simu-headless}"
mkdir -p "$3"
timeout "${TMO:-300}" "$SIMU" "$1" "$2" "$3" > "$3/log.txt" 2>&1
grep -E "STATS|CBOUND|LCDOOB|PANIC|killing|not enough" "$3/log.txt" | tail -8
(cd "$3" && "${PY:-/tmp/edgetx-sim/venv/bin/python3}" "$HERE/pbm2png.py" ./*.pbm 2>/dev/null) || true
