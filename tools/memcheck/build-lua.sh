#!/bin/sh
# Builds stock Lua 5.2.4 (the version EdgeTX is based on) into ./lua52/
# Run on Linux (the devbox): sh build-lua.sh
set -e
cd "$(dirname "$0")"
[ -x lua52/src/lua ] && exit 0
curl -m 60 -sSL https://www.lua.org/ftp/lua-5.2.4.tar.gz -o lua52.tar.gz
mkdir -p lua52 && tar xzf lua52.tar.gz -C lua52 --strip-components=1
rm lua52.tar.gz
# "posix" target: no readline dependency
make -s -C lua52 posix >/dev/null
echo "built lua52/src/lua"
