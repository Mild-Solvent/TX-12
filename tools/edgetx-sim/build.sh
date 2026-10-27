#!/bin/bash
# Builds the headless EdgeTX v2.8.0 simulator for the RadioMaster TX12 MKII
# (the firmware father's radio runs), 32-bit like the radio's STM32.
# usage: tools/edgetx-sim/build.sh [work dir, default /tmp/edgetx-sim]
# Needs (Ubuntu): build-essential cmake gcc-multilib g++-multilib git python3-venv
#                 libclang-dev (llvm 18 tested)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
W="${1:-/tmp/edgetx-sim}"
mkdir -p "$W"; cd "$W"
[ -d edgetx ] || git clone -q --depth 1 --branch v2.8.0 --recurse-submodules --shallow-submodules https://github.com/EdgeTX/edgetx.git edgetx
[ -d venv ] || { python3 -m venv venv; venv/bin/pip install -q lz4 jinja2 pillow "clang==18.1.8" filelock asciitree future lxml; }
cd edgetx
git apply --check "$HERE/edgetx-v2.8.0.patch" 2>/dev/null && git apply "$HERE/edgetx-v2.8.0.patch"
cp "$HERE/simu_headless.cpp" radio/src/
mkdir -p build32 && cd build32
export PATH="$W/venv/bin:$PATH" LIBCLANG_LIBRARY_PATH="${LIBCLANG_LIBRARY_PATH:-/usr/lib/llvm-18/lib}"
cmake -DPCB=X7 -DPCBREV=TX12MK2 -DCMAKE_BUILD_TYPE=Debug -DGVARS=YES -DLUA=YES \
  -DEdgeTX_SUPERBUILD=0 -DNATIVE_BUILD=1 -DSIMU_AUDIO=OFF \
  -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain/native.cmake \
  -DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32 -DCMAKE_EXE_LINKER_FLAGS=-m32 \
  -DPYTHON_EXECUTABLE="$W/venv/bin/python3" -Wno-dev .. > ../cfg32.log
make -j"$(nproc)" simu-headless > ../build32.log
echo "built $W/edgetx/build32/simu-headless"
