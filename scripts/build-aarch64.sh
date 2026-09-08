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
  ca-certificates

rm -rf "$WORK"
rm -rf "$DIST"

mkdir -p "$WORK"
mkdir -p "$DIST"

echo "=========================================="
echo " Mana 0.8.0 - R36S AArch64 Build"
echo "=========================================="

echo "Extracting Mana source..."

tar -xzf "$SRC_TAR" -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: Mana source was not found"
    exit 1
fi

echo "Source directory: $SRC"

echo "=========================================="
echo " Installing Guichan 0.8.3"
echo "=========================================="

rm -rf "$SRC/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/guichan/guichan.git \
    "$SRC/libs/guichan"

echo "=========================================="
echo " Installing ENet 1.3.18"
echo "=========================================="

rm -rf "$SRC/libs/enet"

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/zpl-c/enet.git \
    "$SRC/libs/enet"

echo "=========================================="
echo " Checking SDL2_ttf compatibility"
echo "=========================================="

if grep -q 'TTF_SetFontSize' "$SRC/src/gui/truetypefont.cpp"; then
    echo "ERROR: incompatible TTF_SetFontSize call remains"
    exit 1
fi

sed -i \
    's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/' \
    "$SRC/src/CMakeLists.txt"

echo "SDL2_ttf requirement adjusted."

echo "=========================================="
echo " Checking software cursor"
echo "=========================================="

if ! grep -q 'mSoftwareCursor' "$SRC/src/gui/gui.cpp"; then
    echo "ERROR: software cursor modification is missing"
    exit 1
fi

if ! grep -q 'mSoftwareCursorVisible' "$SRC/src/gui/gui.cpp"; then
    echo "ERROR: cursor visibility toggle is missing"
    exit 1
fi

if ! grep -q 'Key::F12' "$SRC/src/gui/gui.cpp"; then
    echo "ERROR: F12 cursor toggle is missing"
    exit 1
fi

echo "Software cursor modification detected."

echo "=========================================="
echo " Configuring CMake"
echo "=========================================="

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

echo "=========================================="
echo " Compiling Mana"
echo "=========================================="

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"

BIN="$BUILD/src/mana"

if [ ! -x "$BIN" ]; then
    echo "ERROR: Mana executable was not produced"
    exit 1
fi

echo "Mana binary generated successfully."

echo "=========================================="
echo " Preparing PortMaster package"
echo "=========================================="

rm -rf "$STAGE"

mkdir -p "$STAGE"

cp -a "$PORT/." "$STAGE/"

mkdir -p "$STAGE/mana"

cp \
    "$BIN" \
    "$STAGE/mana/mana.aarch64"

chmod +x "$STAGE/mana/mana.aarch64"

echo "Executable copied."

echo "=========================================="
echo " Checking AArch64 binary"
echo "=========================================="

printf '%s\n' \
    '=== Mana R36S AArch64 ELF diagnostics ===' \
    > "$DIST/diagnostics.txt"

file \
    "$STAGE/mana/mana.aarch64" \
    | tee -a "$DIST/diagnostics.txt"

readelf -h \
    "$STAGE/mana/mana.aarch64" \
    | grep -E 'Class:|Machine:' \
    | tee -a "$DIST/diagnostics.txt"

printf '%s\n' \
    '--- NEEDED ---' \
    | tee -a "$DIST/diagnostics.txt"

readelf -d \
    "$STAGE/mana/mana.aarch64" \
    | grep NEEDED \
    | tee -a "$DIST/diagnostics.txt" \
    || true

printf '%s\n' \
    '--- GLIBC versions ---' \
    | tee -a "$DIST/diagnostics.txt"

readelf --version-info \
    "$STAGE/mana/mana.aarch64" \
    | grep -o 'GLIBC_[0-9][0-9.]*' \
    | sort -Vu \
    | tee -a "$DIST/diagnostics.txt" \
    || true

if ! readelf -h "$STAGE/mana/mana.aarch64" \
    | grep -q 'Machine:.*AArch64'; then

    echo "ERROR: generated binary is not AArch64" \
        | tee -a "$DIST/diagnostics.txt"

    exit 2
fi

if readelf --version-info "$STAGE/mana/mana.aarch64" \
    | grep -q 'GLIBC_2\.43'; then

    echo "ERROR: binary requires GLIBC_2.43" \
        | tee -a "$DIST/diagnostics.txt"

    exit 2
fi

echo "AArch64/GLIBC compatibility check passed."

echo "=========================================="
echo " Creating final ZIP"
echo "=========================================="

FINAL_ZIP="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

rm -f "$FINAL_ZIP"

(
    cd "$STAGE"
    zip -qr "$FINAL_ZIP" .
)

echo "=========================================="
echo " Final package"
echo "=========================================="

unzip -l "$FINAL_ZIP" \
    | tee -a "$DIST/diagnostics.txt"

echo "=========================================="
echo " BUILD COMPLETE"
echo "=========================================="

echo "ZIP:"
echo "$FINAL_ZIP"
