#!/usr/bin/env bash
set -euo pipefail

ROOT=/workspace
SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"
WORK="$ROOT/.build"
SRC="$WORK/mana-master"
BUILD="$WORK/build"
STAGE="$WORK/stage"
PORT="$ROOT/port"
DIST="$ROOT/dist"
DEPS="$WORK/deps"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST" "$DEPS"

if [ ! -f "$SRC_ARCHIVE" ]; then
  echo "ERROR: source archive not found: $SRC_ARCHIVE"
  exit 1
fi

echo "=== Extracting Mana source ==="
tar -xzf "$SRC_ARCHIVE" -C "$WORK"

[ -f "$SRC/CMakeLists.txt" ] || {
  echo "ERROR: Mana source not found at $SRC"
  exit 2
}

# ============================================================
# SDL2_ttf compatibility
# ============================================================

TTF_CPP="$SRC/src/gui/truetypefont.cpp"

if [ -f "$TTF_CPP" ]; then
  python3 - "$TTF_CPP" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()

old = '''void TrueTypeFont::updateFontScale(float scale)
{
    if (mFont)
        TTF_SetFontSize(mFont, static_cast<int>(mSize * scale));
}
'''

new = '''void TrueTypeFont::updateFontScale(float scale)
{
    mScale = scale;
}
'''

if old in s:
    s = s.replace(old, new, 1)

p.write_text(s)
PY
fi

echo "=== Patching SDL2_ttf minimum version ==="

sed -i 's/2\.0\.18/2.0.15/g' \
  "$SRC/CMakeLists.txt" 2>/dev/null || true

find "$SRC/CMake" "$SRC/src" \
  -type f -print0 2>/dev/null |
  xargs -0 -r sed -i 's/2\.0\.18/2.0.15/g'

# ============================================================
# Verify software cursor source
# ============================================================

GUI_CPP="$SRC/src/gui/gui.cpp"
GUI_H="$SRC/src/gui/gui.h"

echo "=== Checking R36S software cursor ==="

grep -q 'mSoftwareCursor' "$GUI_H" || {
  echo "ERROR: software cursor patch missing from source archive."
  exit 3
}

grep -q 'mSoftwareCursorVisible' "$GUI_H" || {
  echo "ERROR: cursor visibility patch missing from source archive."
  exit 3
}

grep -q 'Key::F12' "$GUI_CPP" || {
  echo "ERROR: F12 cursor toggle missing from source archive."
  exit 3
}

grep -q 'SDL_ShowCursor(SDL_DISABLE' "$GUI_CPP" || {
  echo "ERROR: SDL hardware cursor disable missing from source archive."
  exit 3
}

echo "Software cursor + SELECT/F12 toggle: FOUND"

# ============================================================
# IMPORTANT:
# Mana 0.8.0 CMakeLists.txt explicitly uses:
#
#   add_subdirectory(libs/enet)
#   add_subdirectory(libs/guichan)
#
# Therefore ENet and Guichan MUST be installed inside:
#
#   $SRC/libs/enet
#   $SRC/libs/guichan
#
# ============================================================

mkdir -p "$SRC/libs"

# ============================================================
# Guichan 0.8.3
# ============================================================

echo "=== Getting Guichan 0.8.3 ==="

GUICHAN_TAR="$DEPS/guichan-0.8.3.tar.gz"

curl -L \
  --fail \
  --retry 3 \
  -o "$GUICHAN_TAR" \
  "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$SRC/libs/guichan"

mkdir -p "$SRC/libs/guichan"

tar -xzf "$GUICHAN_TAR" \
  -C "$SRC/libs/guichan" \
  --strip-components=1

if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then
  echo "ERROR: Guichan CMakeLists.txt was not installed at:"
  echo "$SRC/libs/guichan"
  exit 4
fi

echo "Guichan CMakeLists: OK"

# ============================================================
# ENet 1.3.18
# ============================================================

echo "=== Getting ENet 1.3.18 ==="

ENET_TAR="$DEPS/enet-1.3.18.tar.gz"

curl -L \
  --fail \
  --retry 3 \
  -o "$ENET_TAR" \
  "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$SRC/libs/enet"

mkdir -p "$SRC/libs/enet"

tar -xzf "$ENET_TAR" \
  -C "$SRC/libs/enet" \
  --strip-components=1

if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then
  echo "ERROR: ENet CMakeLists.txt was not installed at:"
  echo "$SRC/libs/enet"
  exit 5
fi

echo "ENet CMakeLists: OK"

# ============================================================
# Verify library layout before CMake
# ============================================================

echo "=== Library layout ==="

ls -la "$SRC/libs"

echo
echo "--- Guichan ---"
ls -l "$SRC/libs/guichan/CMakeLists.txt"

echo
echo "--- ENet ---"
ls -l "$SRC/libs/enet/CMakeLists.txt"

# ============================================================
# CMake configuration
# ============================================================

echo
echo "=== Configuring CMake ==="

cmake -S "$SRC" \
  -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DWITH_OPENGL=ON \
  -DENABLE_NLS=OFF \
  -DENABLE_MANASERV=ON \
  -DUSE_SYSTEM_ENET=OFF \
  -DUSE_SYSTEM_GUICHAN=OFF

# ============================================================
# Build
# ============================================================

echo
echo "=== Building Mana ==="

cmake \
  --build "$BUILD" \
  --parallel "$(nproc)"

# ============================================================
# Locate executable
# ============================================================

BIN="$BUILD/src/mana"

if [ ! -x "$BIN" ]; then
  BIN="$(
    find "$BUILD" \
      -type f \
      -name mana \
      -perm -111 \
      -print \
      -quit
  )"
fi

if [ -z "${BIN:-}" ] || [ ! -x "$BIN" ]; then
  echo "ERROR: Mana executable was not produced."
  exit 6
fi

echo
echo "Mana executable:"
echo "$BIN"

# ============================================================
# Create PortMaster structure
# ============================================================

echo
echo "=== Preparing PortMaster package ==="

rm -rf "$PORT"

mkdir -p "$PORT/mana"

# ============================================================
# Mana.sh
# ============================================================

cat > "$PORT/Mana.sh" <<'LAUNCHER'
#!/bin/bash

set -u

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster" ]; then
    controlfolder="/opt/system/Tools/PortMaster"

elif [ -d "/opt/tools/PortMaster" ]; then
    controlfolder="/opt/tools/PortMaster"

elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"

else
    controlfolder="/roms/ports/PortMaster"
fi

if [ ! -f "$controlfolder/control.txt" ]; then
    echo "ERROR: PortMaster control.txt not found:"
    echo "$controlfolder/control.txt"
    exit 1
fi

source "$controlfolder/control.txt"

if [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/mod_${CFW_NAME}.txt"
fi

if type get_controls >/dev/null 2>&1; then
    get_controls
fi

GAMEDIR="/${directory}/ports/mana"

if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR="/roms/ports/mana"
fi

CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1

LOGFILE="$GAMEDIR/log.txt"

: > "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo " Mana 0.8.0 - R36S"
echo " Mouse + Virtual Keyboard"
echo "========================================"

echo "GAMEDIR=$GAMEDIR"
echo "DEVICE_ARCH=${DEVICE_ARCH:-unknown}"
echo "DEVICE_CPU=${DEVICE_CPU:-unknown}"

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -f "$GAME" ]; then
    echo "ERROR: Mana executable not found:"
    echo "$GAME"
    exit 1
fi

chmod +x "$GAME"

# ============================================================
# PortMaster environment
# ============================================================

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
fi

# ============================================================
# GPTK virtual keyboard
# ============================================================

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

unset TEXTINPUTNOAUTOCAPITALS 2>/dev/null || true

# ============================================================
# Start GPTK
# ============================================================

cd "$GAMEDIR/mana" || exit 1

GPTK_CONFIG="./mana.gptk"

if [ ! -f "$GPTK_CONFIG" ]; then
    echo "ERROR: mana.gptk not found:"
    echo "$GAMEDIR/mana/mana.gptk"
    exit 1
fi

GPTOPID=""

if [ -n "${GPTOKEYB2:-}" ]; then

    echo "Starting GPTOKEYB2..."

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    echo "Starting GPTOKEYB..."

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

else

    echo "ERROR: GPTOKEYB/GPTOKEYB2 not found."
    exit 1

fi

# ============================================================
# Cleanup
# ============================================================

cleanup()
{
    if [ -n "${GPTOPID:-}" ]; then
        kill "$GPTOPID" 2>/dev/null || true
        wait "$GPTOPID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# ============================================================
# Controls information
# ============================================================

echo
echo "Mouse:"
echo "  Right analog = mouse movement"
echo "  R3           = left click"
echo "  L3           = right click"

echo
echo "Cursor:"
echo "  SELECT/F12 = show/hide cursor"

echo
echo "Virtual keyboard:"
echo "  START + D-PAD DOWN = open keyboard"
echo "  D-PAD             = navigate"
echo "  A                 = Enter/select"
echo "  START             = confirm"
echo "  SELECT            = cancel"

echo
echo "Starting Mana..."

# ============================================================
# Start game
# ============================================================

"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"

RET=$?

echo "Mana exited with code $RET"

exit "$RET"
LAUNCHER

chmod +x "$PORT/Mana.sh"

# ============================================================
# GPTK configuration
# ============================================================

cat > "$PORT/mana/mana.gptk" <<'GPTK'
back = esc
start = enter
select = f12

a = space
b = esc
x = z
y = x

l1 = lshift
l2 = home
l3 = mouse_right

r1 = lctrl
r2 = end
r3 = mouse_left

up = up
down = down
left = left
right = right

left_analog_up = up
left_analog_down = down
left_analog_left = left
left_analog_right = right

right_analog_up = mouse_movement_up
right_analog_down = mouse_movement_down
right_analog_left = mouse_movement_left
right_analog_right = mouse_movement_right

deadzone_triggers = 3000

mouse_scale = 8192
mouse_delay = 16
GPTK

# ============================================================
# PortMaster metadata
# ============================================================

cat > "$PORT/port.json" <<'JSON'
{
  "version": 4,
  "name": "mana-0.8.0.zip",
  "items": [
    "Mana.sh",
    "mana"
  ],
  "items_opt": [],
  "attr": {
    "title": "Mana 0.8.0",
    "porter": [
      "local"
    ],
    "desc": "The Mana Client 0.8.0 for AArch64 PortMaster devices.",
    "desc_md": null,
    "inst": "ready to run",
    "inst_md": null,
    "genres": [
      "rpg",
      "mmorpg"
    ],
    "image": null,
    "rtr": true,
    "exp": true,
    "runtime": [],
    "store": [],
    "availability": "source",
    "reqs": [],
    "arch": [
      "aarch64"
    ],
    "min_glibc": "2.29"
  }
}
JSON

# ============================================================
# Gameinfo
# ============================================================

cat > "$PORT/gameinfo.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<game>
  <name>Mana 0.8.0</name>
  <path>Mana.sh</path>
  <description>The Mana Client 0.8.0</description>
</game>
XML

# ============================================================
# Install executable
# ============================================================

cp "$BIN" "$PORT/mana/mana.aarch64"

chmod +x "$PORT/mana/mana.aarch64"

# ============================================================
# Game data
# ============================================================

echo
echo "=== Copying Mana data ==="

rm -rf "$PORT/mana/data"

if [ ! -d "$SRC/data" ]; then
    echo "ERROR: Mana data directory not found:"
    echo "$SRC/data"
    exit 7
fi

cp -a "$SRC/data" "$PORT/mana/data"

# ============================================================
# Verify cursor image
# ============================================================

if [ ! -f "$PORT/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERROR: mouse.png missing from package data."
    exit 8
fi

echo "mouse.png: OK"

# ============================================================
# Licenses
# ============================================================

if [ -d "$SRC/licenses" ]; then
    cp -a "$SRC/licenses" "$PORT/mana/licenses"
fi

# ============================================================
# ELF diagnostics
# ============================================================

echo
echo "=== ELF diagnostics ==="

ELF="$PORT/mana/mana.aarch64"

file "$ELF" | tee "$DIST/diagnostics.txt"

{
    echo
    echo "=== ELF HEADER ==="

    readelf -h "$ELF" || true

    echo
    echo "=== NEEDED ==="

    readelf -d "$ELF" |
        grep NEEDED ||
        true

    echo
    echo "=== RUNPATH/RPATH ==="

    readelf -d "$ELF" |
        grep -E 'RPATH|RUNPATH' ||
        true

    echo
    echo "=== GLIBC ==="

    readelf --version-info "$ELF" 2>/dev/null |
        grep -o 'GLIBC_[0-9][0-9.]*' |
        sort -Vu ||
        true

    echo
    echo "=== Cursor strings ==="

    strings "$ELF" |
        grep -E \
        'mSoftwareCursor|mSoftwareCursorVisible|SDL_ShowCursor|F12' |
        sort -u ||
        true

} >> "$DIST/diagnostics.txt"

# ============================================================
# GLIBC compatibility
# ============================================================

echo
echo "=== Checking GLIBC compatibility ==="

GLIBC_LIST="$(
    readelf --version-info "$ELF" 2>/dev/null |
    grep -o 'GLIBC_[0-9][0-9.]*' |
    sort -Vu ||
    true
)"

echo "$GLIBC_LIST"

if echo "$GLIBC_LIST" | grep -q 'GLIBC_2\.43'; then
    echo
    echo "ERROR: binary requires GLIBC_2.43"
    exit 9
fi

echo
echo "GLIBC compatibility check OK."

# ============================================================
# Architecture validation
# ============================================================

echo
echo "=== Checking architecture ==="

if ! file "$ELF" | grep -qi 'ARM aarch64\|AArch64'; then
    echo "ERROR: generated binary is not AArch64."
    file "$ELF"
    exit 10
fi

echo "AArch64: OK"

# ============================================================
# Final package validation
# ============================================================

echo
echo "=== Validating PortMaster package ==="

test -f "$PORT/Mana.sh"
test -f "$PORT/port.json"
test -f "$PORT/gameinfo.xml"
test -f "$PORT/mana/mana.aarch64"
test -f "$PORT/mana/mana.gptk"
test -f "$PORT/mana/data/graphics/gui/mouse.png"

echo "Mana.sh: OK"
echo "port.json: OK"
echo "gameinfo.xml: OK"
echo "mana.aarch64: OK"
echo "mana.gptk: OK"
echo "mouse.png: OK"

# ============================================================
# Create ZIP
# ============================================================

echo
echo "=== Creating PortMaster ZIP ==="

PACKAGE="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

rm -f "$PACKAGE"

(
    cd "$PORT"

    zip -qr "$PACKAGE" .
)

# ============================================================
# Package listing
# ============================================================

unzip -l "$PACKAGE" > "$DIST/package-list.txt"

echo
echo "=== PACKAGE ==="

ls -lh "$PACKAGE"

echo
echo "=== PACKAGE CONTENTS ==="

cat "$DIST/package-list.txt"

echo
echo "=== BUILD FINALIZADO ==="
echo "$PACKAGE"
