#!/bin/bash
set -e

ROOT=/workspace
SRC_TAR="$ROOT/source/mana-master.tar.gz"
BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"

rm -rf "$BUILD" "$INSTALL" "$DIST"
mkdir -p "$BUILD" "$INSTALL" "$DIST"

echo "=== Mana AArch64 / PortMaster build ==="

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: source do Mana não encontrado"
    exit 1
fi

echo "Source: $SRC_DIR"

# Os submodules não vêm dentro do tar.gz.
rm -rf "$SRC_DIR/libs/guichan"
rm -rf "$SRC_DIR/libs/enet"

git clone --depth 1 https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

git clone --depth 1 https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

cmake -S "$SRC_DIR" -B "$BUILD/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

cmake --build "$BUILD/cmake" -j"$(nproc)"
cmake --install "$BUILD/cmake"

BIN="$(find "$INSTALL" -type f -name mana | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executável Mana não foi encontrado"
    exit 1
fi

mkdir -p "$DIST"

cp "$BIN" "$DIST/mana.aarch64"

echo
echo "=== ELF ==="
file "$DIST/mana.aarch64"

echo
echo "=== GLIBC requerida ==="
readelf --version-info "$DIST/mana.aarch64" | grep -o 'GLIBC_[0-9.]*' | sort -Vu || true

if readelf --version-info "$DIST/mana.aarch64" | grep -q 'GLIBC_2.43'; then
    echo "ERRO: ainda exige GLIBC_2.43"
    exit 1
fi

readelf --version-info "$DIST/mana.aarch64" > "$DIST/diagnostics.txt" || true

echo
echo "=== BUILD OK ==="
ls -lh "$DIST/mana.aarch64"
