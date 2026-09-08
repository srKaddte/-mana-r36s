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
  build-essential cmake git zip file binutils pkg-config \
  libphysfs-dev libcurl4-openssl-dev libxml2-dev zlib1g-dev libpng-dev \
  gettext libfreetype6-dev libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
  libsdl2-net-dev libsdl2-ttf-dev ca-certificates curl

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST"

tar -xzf "$SRC_TAR" -C "$WORK"

[ -f "$SRC/CMakeLists.txt" ] || {
    echo "ERROR: Mana source not found"
    exit 1
}

# ============================================================
# DEPENDÊNCIAS
# ============================================================

rm -rf "$SRC/libs/guichan" "$SRC/libs/enet"

# Mana 0.8.0 precisa da API antiga do Guichan.
# NÃO usar Guichan master/0.9.x.
#
# O repositório antigo guichan/guichan não deve mais ser usado.
# Baixamos diretamente o release oficial 0.8.3.
GUICHAN_TMP="$WORK/guichan-0.8.3.tar.gz"

echo "=== Downloading Guichan 0.8.3 ==="

curl -fL \
    --retry 3 \
    --retry-all-errors \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz" \
    -o "$GUICHAN_TMP"

[ -s "$GUICHAN_TMP" ] || {
    echo "ERROR: Guichan 0.8.3 download failed"
    exit 1
}

echo "=== Extracting Guichan 0.8.3 ==="

tar -xzf "$GUICHAN_TMP" -C "$WORK"

GUICHAN_DIR="$WORK/guichan-0.8.3"

[ -d "$GUICHAN_DIR" ] || {
    echo "ERROR: Guichan 0.8.3 extraction failed"
    exit 1
}

mkdir -p "$SRC/libs/guichan"

cp -a "$GUICHAN_DIR"/. "$SRC/libs/guichan"/

[ -f "$SRC/libs/guichan/CMakeLists.txt" ] || {
    echo "ERROR: Guichan CMakeLists.txt not found"
    exit 1
}

echo "=== Guichan 0.8.3 ready ==="

# ============================================================
# ENET
# ============================================================

echo "=== Downloading ENet 1.3.18 ==="

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/zpl-c/enet.git \
    "$SRC/libs/enet"

[ -f "$SRC/libs/enet/CMakeLists.txt" ] || {
    echo "ERROR: ENet source was not downloaded correctly"
    exit 1
}

# ============================================================
# SDL2_TTF
# ============================================================

# SDL2_ttf 2.0.15 não fornece TTF_SetFontSize().
# O source do Mana já deve conter a correção correspondente.
if grep -q 'TTF_SetFontSize' "$SRC/src/gui/truetypefont.cpp"; then
    echo "ERROR: incompatible TTF_SetFontSize call remains"
    exit 1
fi

# O builder possui SDL2_ttf 2.0.15.
sed -i \
    's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/' \
    "$SRC/src/CMakeLists.txt"

# ============================================================
# VERIFICAÇÃO DO CURSOR SOFTWARE
# ============================================================

echo "=== Checking software cursor modifications ==="

if grep -q "mSoftwareCursor" "$SRC/src/gui/gui.cpp"; then
    echo "Software cursor code: FOUND"
else
    echo "ERROR: software cursor modification not found"
    exit 1
fi

if grep -q "mSoftwareCursorVisible" "$SRC/src/gui/gui.cpp"; then
    echo "Cursor visibility toggle: FOUND"
else
    echo "ERROR: cursor visibility toggle not found"
    exit 1
fi

if grep -q "SDL_DISABLE" "$SRC/src/gui/gui.cpp"; then
    echo "Hardware cursor disable: FOUND"
else
    echo "WARNING: SDL hardware cursor disable not found"
fi

# ============================================================
# CMAKE
# ============================================================

echo "=== Configuring Mana ==="

cmake -S "$SRC" -B "$BUILD" \
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

echo "=== Building Mana ==="

cmake --build "$BUILD" --parallel "$(nproc)"

BIN="$BUILD/src/mana"

[ -x "$BIN" ] || {
    echo "ERROR: Mana executable was not produced"
    exit 1
}

echo "=== Mana binary created ==="

file "$BIN"

# ============================================================
# PORTMASTER PACKAGE
# ============================================================

echo "=== Preparing PortMaster package ==="

rm -rf "$STAGE"

mkdir -p "$STAGE"

cp -a "$PORT/." "$STAGE/"

mkdir -p "$STAGE/mana"

cp "$BIN" "$STAGE/mana/mana.aarch64"

chmod +x "$STAGE/mana/mana.aarch64"

# Nunca carregar bibliotecas antigas/incompatíveis.
rm -f \
    "$STAGE/mana/libs.aarch64/libguichan.so.0.8" \
    2>/dev/null || true

rm -f \
    "$STAGE/mana/libs.aarch64/libxml2.so.16" \
    2>/dev/null || true

# ============================================================
# ELF DIAGNOSTICS
# ============================================================

echo "=== ELF diagnostics ==="

printf '%s\n' \
    '=== Mana R36S AArch64 ELF diagnostics ===' \
    > "$DIST/diagnostics.txt"

file "$STAGE/mana/mana.aarch64" \
    | tee -a "$DIST/diagnostics.txt"

readelf -h "$STAGE/mana/mana.aarch64" \
    | grep -E 'Class:|Machine:' \
    | tee -a "$DIST/diagnostics.txt"

printf '%s\n' \
    '--- NEEDED ---' \
    | tee -a "$DIST/diagnostics.txt"

readelf -d "$STAGE/mana/mana.aarch64" \
    | grep NEEDED \
    | tee -a "$DIST/diagnostics.txt" \
    || true

printf '%s\n' \
    '--- GLIBC versions ---' \
    | tee -a "$DIST/diagnostics.txt"

readelf --version-info "$STAGE/mana/mana.aarch64" \
    | grep -o 'GLIBC_[0-9][0-9.]*' \
    | sort -Vu \
    | tee -a "$DIST/diagnostics.txt" \
    || true

# ============================================================
# AARCH64 CHECK
# ============================================================

if readelf -h "$STAGE/mana/mana.aarch64" \
    | grep -q 'Machine:.*AArch64'; then

    echo "AArch64 check: OK"

else

    echo "ERROR: output is not AArch64" \
        | tee -a "$DIST/diagnostics.txt"

    exit 2
fi

# ============================================================
# GLIBC CHECK
# ============================================================

if readelf --version-info "$STAGE/mana/mana.aarch64" \
    | grep -q 'GLIBC_2\.43'; then

    echo "ERROR: build still requires GLIBC_2.43" \
        | tee -a "$DIST/diagnostics.txt"

    exit 2
fi

echo "GLIBC compatibility check: OK"

# ============================================================
# PACKAGE
# ============================================================

OUTPUT="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

rm -f "$OUTPUT"

echo "=== Creating PortMaster ZIP ==="

(
    cd "$STAGE"
    zip -qr "$OUTPUT" .
)

[ -s "$OUTPUT" ] || {
    echo "ERROR: PortMaster ZIP was not created"
    exit 1
}

printf '%s\n' \
    '--- PACKAGE ---' \
    | tee -a "$DIST/diagnostics.txt"

unzip -l "$OUTPUT" \
    | tee -a "$DIST/diagnostics.txt"

echo
echo "=============================================="
echo " BUILD FINISHED SUCCESSFULLY"
echo "=============================================="
echo
echo "Output:"
echo "$OUTPUT"
echo
