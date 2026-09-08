#!/usr/bin/env bash
set -euo pipefail

ROOT=/workspace

SRC_TAR="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.build"
SRC="$WORK/mana-master"
BUILD="$WORK/build"
STAGE="$WORK/stage"

PORT="$ROOT/port"
DIST="$ROOT/dist"

export DEBIAN_FRONTEND=noninteractive

echo "=============================================="
echo " Mana 0.8.0 - R36S AArch64 PortMaster Build"
echo "=============================================="

echo
echo "=== Installing build dependencies ==="

apt-get update

apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    zip \
    unzip \
    file \
    binutils \
    pkg-config \
    curl \
    ca-certificates \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext \
    libfreetype6-dev \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    libsdl2-net-dev \
    libsdl2-ttf-dev \
    python3

echo
echo "=== Cleaning previous build ==="

rm -rf "$WORK"
rm -rf "$DIST"

mkdir -p "$WORK"
mkdir -p "$DIST"

echo
echo "=== Checking Mana source archive ==="

if [ ! -f "$SRC_TAR" ]; then
    echo "ERROR: source archive not found:"
    echo "$SRC_TAR"
    exit 1
fi

echo "Source archive:"
echo "$SRC_TAR"

echo
echo "=== Extracting Mana source ==="

tar -xzf "$SRC_TAR" -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: Mana source was not extracted correctly."
    echo "Expected:"
    echo "$SRC/CMakeLists.txt"
    exit 1
fi

echo "Mana source OK."

# ============================================================
# GUICHAN 0.8.3
# ============================================================

echo
echo "=============================================="
echo " Downloading Guichan 0.8.3"
echo "=============================================="

rm -rf "$SRC/libs/guichan"

GUICHAN_TMP="$WORK/guichan-0.8.3.tar.gz"

curl -fL \
    --retry 3 \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz" \
    -o "$GUICHAN_TMP"

if [ ! -s "$GUICHAN_TMP" ]; then
    echo "ERROR: Guichan archive is empty."
    exit 1
fi

echo "Guichan archive downloaded."

echo
echo "=== Extracting Guichan ==="

tar -xzf "$GUICHAN_TMP" -C "$WORK"

GUICHAN_DIR="$WORK/guichan-0.8.3"

if [ ! -d "$GUICHAN_DIR" ]; then
    echo "ERROR: Guichan directory was not found:"
    echo "$GUICHAN_DIR"
    exit 1
fi

mkdir -p "$SRC/libs/guichan"

cp -a "$GUICHAN_DIR"/. "$SRC/libs/guichan"/

if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then
    echo "ERROR: Guichan CMakeLists.txt not found."
    exit 1
fi

echo "Guichan 0.8.3 installed."

# ============================================================
# ENET 1.3.18
# ============================================================

echo
echo "=============================================="
echo " Downloading ENet"
echo "=============================================="

rm -rf "$SRC/libs/enet"

ENET_TMP="$WORK/enet.tar.gz"

curl -fL \
    --retry 3 \
    "https://github.com/zpl-c/enet/archive/refs/tags/v1.3.18.tar.gz" \
    -o "$ENET_TMP"

if [ ! -s "$ENET_TMP" ]; then
    echo "ERROR: ENet archive is empty."
    exit 1
fi

echo "ENet archive downloaded."

echo
echo "=== Extracting ENet ==="

tar -xzf "$ENET_TMP" -C "$WORK"

ENET_DIR="$WORK/enet-1.3.18"

if [ ! -d "$ENET_DIR" ]; then
    echo "ERROR: ENet directory was not found:"
    echo "$ENET_DIR"

    echo
    echo "Extracted directories:"
    find "$WORK" -maxdepth 1 -type d -print

    exit 1
fi

mkdir -p "$SRC/libs/enet"

cp -a "$ENET_DIR"/. "$SRC/libs/enet"/

if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then
    echo "ERROR: ENet CMakeLists.txt not found."
    exit 1
fi

echo "ENet installed."

# ============================================================
# SDL2_TTF COMPATIBILITY
# ============================================================

echo
echo "=============================================="
echo " Checking SDL2_ttf compatibility"
echo "=============================================="

TRUETYPE="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE" ]; then
    echo "ERROR: truetypefont.cpp not found."
    exit 1
fi

if grep -q "TTF_SetFontSize" "$TRUETYPE"; then

    echo
    echo "WARNING: TTF_SetFontSize was found."
    echo "Removing incompatible SDL2_ttf calls..."

    python3 - "$TRUETYPE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text()

text = re.sub(
    r'^\s*TTF_SetFontSize\s*\([^;]*\);\s*$',
    '',
    text,
    flags=re.MULTILINE
)

path.write_text(text)
PY

fi

if grep -q "TTF_SetFontSize" "$TRUETYPE"; then
    echo "ERROR: TTF_SetFontSize is still present."
    exit 1
fi

echo "SDL2_ttf compatibility check OK."

# ============================================================
# SDL2_TTF VERSION
# ============================================================

echo
echo "=== Adjusting SDL2_ttf minimum version ==="

if [ -f "$SRC/src/CMakeLists.txt" ]; then

    sed -i \
        's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' \
        "$SRC/src/CMakeLists.txt"

fi

# ============================================================
# SOFTWARE CURSOR
# ============================================================

echo
echo "=============================================="
echo " Checking R36S software cursor"
echo "=============================================="

GUI_CPP="$SRC/src/gui/gui.cpp"
GUI_H="$SRC/src/gui/gui.h"

if [ ! -f "$GUI_CPP" ]; then
    echo "ERROR: gui.cpp not found."
    exit 1
fi

if [ ! -f "$GUI_H" ]; then
    echo "ERROR: gui.h not found."
    exit 1
fi

if grep -q "mSoftwareCursor" "$GUI_CPP"; then
    echo "Software cursor: FOUND"
else
    echo "ERROR: software cursor code is missing."
    exit 1
fi

if grep -q "mSoftwareCursorVisible" "$GUI_CPP"; then
    echo "Cursor visibility toggle: FOUND"
else
    echo "ERROR: cursor visibility toggle is missing."
    exit 1
fi

if grep -q "SDL_ShowCursor(SDL_DISABLE" "$GUI_CPP"; then
    echo "Hardware cursor disable: FOUND"
else
    echo "WARNING: SDL hardware cursor disable not found."
fi

# ============================================================
# CMAKE
# ============================================================

echo
echo "=============================================="
echo " Configuring CMake"
echo "=============================================="

rm -rf "$BUILD"

mkdir -p "$BUILD"

cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

# ============================================================
# BUILD
# ============================================================

echo
echo "=============================================="
echo " Compiling Mana"
echo "=============================================="

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"

# ============================================================
# FIND BINARY
# ============================================================

echo
echo "=== Locating Mana executable ==="

BIN=""

for candidate in \
    "$BUILD/src/mana" \
    "$BUILD/mana" \
    "$BUILD/src/mana/mana"
do

    if [ -x "$candidate" ]; then
        BIN="$candidate"
        break
    fi

done

if [ -z "$BIN" ]; then

    echo "ERROR: Mana executable was not produced."

    echo
    echo "Searching build directory..."

    find "$BUILD" \
        -type f \
        -name "mana" \
        -print \
        || true

    exit 1

fi

echo
echo "Mana executable:"
echo "$BIN"

# ============================================================
# ELF
# ============================================================

echo
echo "=============================================="
echo " ELF information"
echo "=============================================="

file "$BIN"

echo
echo "--- ELF header ---"

readelf -h "$BIN" \
    | grep -E \
        "Class:|Machine:|Type:" \
        || true

echo
echo "--- Required libraries ---"

readelf -d "$BIN" \
    | grep NEEDED \
    || true

echo
echo "--- GLIBC requirements ---"

readelf --version-info "$BIN" \
    | grep -o "GLIBC_[0-9][0-9.]*" \
    | sort -Vu \
    || true

# ============================================================
# AARCH64 CHECK
# ============================================================

echo
echo "=============================================="
echo " Checking architecture"
echo "=============================================="

if readelf -h "$BIN" | grep -q "AArch64"; then
    echo "AArch64: OK"
else
    echo "ERROR: executable is not AArch64."
    exit 2
fi

# ============================================================
# GLIBC CHECK
# ============================================================

echo
echo "=============================================="
echo " Checking GLIBC compatibility"
echo "=============================================="

GLIBC_LIST="$WORK/glibc.txt"

readelf --version-info "$BIN" \
    | grep -o "GLIBC_[0-9][0-9.]*" \
    | sort -Vu \
    > "$GLIBC_LIST" \
    || true

cat "$GLIBC_LIST"

if grep -q "GLIBC_2\.43" "$GLIBC_LIST"; then

    echo
    echo "ERROR: executable requires GLIBC_2.43."
    echo "This is incompatible with the R36S target."

    exit 2

fi

echo "GLIBC compatibility check OK."

# ============================================================
# PORTMASTER STAGE
# ============================================================

echo
echo "=============================================="
echo " Preparing PortMaster package"
echo "=============================================="

rm -rf "$STAGE"

mkdir -p "$STAGE"

if [ ! -d "$PORT" ]; then
    echo "ERROR: PortMaster port directory not found:"
    echo "$PORT"
    exit 1
fi

cp -a "$PORT"/. "$STAGE"/

mkdir -p "$STAGE/mana"

cp "$BIN" \
    "$STAGE/mana/mana.aarch64"

chmod +x \
    "$STAGE/mana/mana.aarch64"

# ============================================================
# PORTMASTER FILE CHECK
# ============================================================

echo
echo "=== Checking PortMaster files ==="

REQUIRED_FILES=(
    "$STAGE/Mana.sh"
    "$STAGE/port.json"
    "$STAGE/mana/mana.aarch64"
    "$STAGE/mana/mana.gptk"
)

for file in "${REQUIRED_FILES[@]}"; do

    if [ ! -f "$file" ]; then
        echo "ERROR: required file missing:"
        echo "$file"
        exit 1
    fi

    echo "OK: $file"

done

# ============================================================
# GPTK CHECK
# ============================================================

echo
echo "=============================================="
echo " Checking GPTK controls"
echo "=============================================="

GPTK="$STAGE/mana/mana.gptk"

grep -q \
    "right_analog_up = mouse_movement_up" \
    "$GPTK" \
    || {
        echo "ERROR: right analog mouse-up mapping missing."
        exit 1
    }

grep -q \
    "right_analog_down = mouse_movement_down" \
    "$GPTK" \
    || {
        echo "ERROR: right analog mouse-down mapping missing."
        exit 1
    }

grep -q \
    "right_analog_left = mouse_movement_left" \
    "$GPTK" \
    || {
        echo "ERROR: right analog mouse-left mapping missing."
        exit 1
    }

grep -q \
    "right_analog_right = mouse_movement_right" \
    "$GPTK" \
    || {
        echo "ERROR: right analog mouse-right mapping missing."
        exit 1
    }

grep -q \
    "l3 = mouse_right" \
    "$GPTK" \
    || {
        echo "ERROR: L3 mouse-right mapping missing."
        exit 1
    }

grep -q \
    "r3 = mouse_left" \
    "$GPTK" \
    || {
        echo "ERROR: R3 mouse-left mapping missing."
        exit 1
    }

grep -q \
    "select = f12" \
    "$GPTK" \
    || {
        echo "ERROR: Select/F12 cursor toggle mapping missing."
        exit 1
    }

echo "GPTK mouse controls: OK."

# ============================================================
# OLD MOUSE STATE CHECK
# ============================================================

echo
echo "=== Checking old mouse-state configuration ==="

if grep -R \
    "controls:mouse" \
    "$STAGE" \
    --exclude="*.png" \
    --exclude="*.jpg" \
    --exclude="*.gif" \
    2>/dev/null
then

    echo
    echo "WARNING: old controls:mouse reference detected."

else

    echo "No old mouse state detected."

fi

# ============================================================
# DIAGNOSTICS
# ============================================================

echo
echo "=============================================="
echo " Creating diagnostics"
echo "=============================================="

DIAG="$DIST/diagnostics.txt"

{
    echo "Mana R36S AArch64 PortMaster"
    echo
    echo "Architecture:"
    file "$STAGE/mana/mana.aarch64"

    echo
    echo "ELF:"
    readelf -h "$STAGE/mana/mana.aarch64" \
        | grep -E \
            "Class:|Machine:|Type:" \
        || true

    echo
    echo "NEEDED:"
    readelf -d "$STAGE/mana/mana.aarch64" \
        | grep NEEDED \
        || true

    echo
    echo "GLIBC:"
    readelf --version-info "$STAGE/mana/mana.aarch64" \
        | grep -o "GLIBC_[0-9][0-9.]*" \
        | sort -Vu \
        || true

    echo
    echo "Software cursor:"
    grep -n \
        "mSoftwareCursor" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo
    echo "Cursor visibility:"
    grep -n \
        "mSoftwareCursorVisible" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo
    echo "GPTK:"
    cat "$GPTK"

} > "$DIAG"

# ============================================================
# CREATE ZIP
# ============================================================

echo
echo "=============================================="
echo " Creating final ZIP"
echo "=============================================="

OUTPUT="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

rm -f "$OUTPUT"

(
    cd "$STAGE"
    zip -qr "$OUTPUT" .
)

if [ ! -s "$OUTPUT" ]; then
    echo "ERROR: ZIP was not created."
    exit 1
fi

echo
echo "=== ZIP contents ==="

unzip -l "$OUTPUT"

echo
echo "=============================================="
echo " BUILD SUCCESSFUL"
echo "=============================================="

echo
echo "Output:"
echo "$OUTPUT"

echo
echo "Diagnostics:"
echo "$DIAG"

echo
echo "Mana R36S package is ready."
