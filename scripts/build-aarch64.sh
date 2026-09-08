#!/bin/bash
set -e

ROOT=/workspace
SRC_TAR="$ROOT/source/mana-master.tar.gz"
BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"

rm -rf "$BUILD" "$INSTALL" "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"

echo "========================================"
echo " Mana 0.8.0 AArch64 / PortMaster Build"
echo " Software Cursor / R36S"
echo "========================================"

echo
echo "=== Instalando dependencias de build ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    git \
    zip \
    file \
    binutils \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext \
    pkg-config

echo
echo "=== Dependencias instaladas ==="

echo
echo "=== Extraindo source do Mana ==="

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: arquivo source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: source do Mana nao encontrado"
    exit 1
fi

echo "Source:"
echo "$SRC_DIR"

echo
echo "=== Preparando submodules ==="

rm -rf "$SRC_DIR/libs/guichan"
rm -rf "$SRC_DIR/libs/enet"

echo
echo "========================================"
echo " Clonando Guichan 0.8.3"
echo "========================================"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

echo
echo "=== Verificando Guichan ==="

cd "$SRC_DIR/libs/guichan"

echo "Tag/revisao:"
git describe --tags --always

echo "Commit:"
git rev-parse HEAD

cd "$ROOT"

echo
echo "========================================"
echo " Clonando ENet"
echo "========================================"

git clone \
    --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

echo
echo "=== Verificando ENet ==="

cd "$SRC_DIR/libs/enet"

git rev-parse HEAD

cd "$ROOT"

echo
echo "========================================"
echo " Ajustando requisito do SDL2_ttf"
echo "========================================"

find "$SRC_DIR" -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 | while IFS= read -r -d '' FILE
do
    sed -i 's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' "$FILE"
done

echo
echo "=== Verificando dependencias ==="

echo
echo "--- SDL2 ---"
pkg-config --modversion sdl2 || true

echo
echo "--- SDL2_image ---"
pkg-config --modversion SDL2_image || true

echo
echo "--- SDL2_mixer ---"
pkg-config --modversion SDL2_mixer || true

echo
echo "--- SDL2_net ---"
pkg-config --modversion SDL2_net || true

echo
echo "--- SDL2_ttf ---"
pkg-config --modversion SDL2_ttf || true

echo
echo "--- PhysFS ---"
pkg-config --modversion physfs || true

echo
echo "--- libxml2 ---"
pkg-config --modversion libxml-2.0 || true

echo
echo "========================================"
echo " Configurando CMake"
echo "========================================"

cmake -S "$SRC_DIR" -B "$BUILD/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

echo
echo "========================================"
echo " Compilando Mana"
echo "========================================"

cmake --build "$BUILD/cmake" -j"$(nproc)"

echo
echo "========================================"
echo " Instalando Mana"
echo "========================================"

cmake --install "$BUILD/cmake"

echo
echo "========================================"
echo " Procurando executavel"
echo "========================================"

BIN="$(find "$INSTALL" -type f -name mana | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executavel Mana nao foi encontrado"
    echo
    echo "Conteudo do INSTALL:"
    find "$INSTALL" -maxdepth 5 -type f -print || true
    exit 1
fi

echo
echo "Executavel encontrado:"
echo "$BIN"

echo
echo "========================================"
echo " Copiando executavel"
echo "========================================"

cp "$BIN" "$DIST/mana.aarch64"

chmod +x "$DIST/mana.aarch64"

echo
echo "========================================"
echo " Informacoes do ELF"
echo "========================================"

file "$DIST/mana.aarch64"

echo
echo "=== GLIBC requerida ==="

readelf --version-info "$DIST/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu || true

echo
echo "=== Dependencias dinamicas ==="

readelf -d "$DIST/mana.aarch64" \
    | grep NEEDED || true

echo
echo "=== RPATH / RUNPATH ==="

readelf -d "$DIST/mana.aarch64" \
    | grep -E 'RPATH|RUNPATH' || true

echo
echo "========================================"
echo " Salvando diagnosticos"
echo "========================================"

{
    echo "========================================"
    echo " Mana 0.8.0 AArch64 Diagnostics"
    echo " Software Cursor / R36S"
    echo "========================================"
    echo

    echo "=== FILE ==="
    file "$DIST/mana.aarch64"

    echo
    echo "=== GLIBC ==="
    readelf --version-info "$DIST/mana.aarch64" \
        | grep -o 'GLIBC_[0-9.]*' \
        | sort -Vu || true

    echo
    echo "=== NEEDED ==="
    readelf -d "$DIST/mana.aarch64" \
        | grep NEEDED || true

    echo
    echo "=== RPATH/RUNPATH ==="
    readelf -d "$DIST/mana.aarch64" \
        | grep -E 'RPATH|RUNPATH' || true

    echo
    echo "=== GUICHAN ==="
    cd "$SRC_DIR/libs/guichan"
    git describe --tags --always
    git rev-parse HEAD
    cd "$ROOT"

    echo
    echo "=== ENET ==="
    cd "$SRC_DIR/libs/enet"
    git rev-parse HEAD
    cd "$ROOT"

} > "$DIST/diagnostics.txt"

echo
echo "========================================"
echo " Verificando GLIBC incompatível"
echo "========================================"

if readelf --version-info "$DIST/mana.aarch64" \
    | grep -q 'GLIBC_2.43'; then

    echo "ERRO: o executavel ainda exige GLIBC_2.43"
    exit 1
fi

echo
echo "GLIBC 2.43 nao encontrada."

echo
echo "========================================"
echo " PREPARANDO PACOTE PORTMASTER"
echo "========================================"

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

echo
echo "=== Copiando arquivos do PortMaster ==="

if [ -f "$ROOT/port/Mana.sh" ]; then
    cp "$ROOT/port/Mana.sh" "$PACKAGE/"
else
    echo "ERRO: port/Mana.sh nao encontrado"
    exit 1
fi

if [ -f "$ROOT/port/README.md" ]; then
    cp "$ROOT/port/README.md" "$PACKAGE/"
fi

if [ -f "$ROOT/port/gameinfo.xml" ]; then
    cp "$ROOT/port/gameinfo.xml" "$PACKAGE/"
fi

if [ -f "$ROOT/port/port.json" ]; then
    cp "$ROOT/port/port.json" "$PACKAGE/"
fi

if [ -f "$ROOT/port/screenshot.png" ]; then
    cp "$ROOT/port/screenshot.png" "$PACKAGE/"
fi

echo
echo "=== Copiando dados do jogo ==="

if [ -d "$ROOT/port/mana/data" ]; then
    cp -a "$ROOT/port/mana/data" "$PACKAGE/mana/"
else
    echo "AVISO: port/mana/data nao encontrado"
fi

echo
echo "=== Copiando licencas ==="

if [ -d "$ROOT/port/mana/licenses" ]; then
    cp -a "$ROOT/port/mana/licenses" "$PACKAGE/mana/"
fi

echo
echo "=== Copiando configuracao GPTK ==="

if [ -f "$ROOT/port/mana/mana.gptk.0" ]; then
    cp "$ROOT/port/mana/mana.gptk.0" "$PACKAGE/mana/"
fi

if [ -f "$ROOT/port/mana/mana.gptk" ]; then
    cp "$ROOT/port/mana/mana.gptk" "$PACKAGE/mana/"
fi

if [ -f "$ROOT/port/mana/mana.controls.ini" ]; then
    cp "$ROOT/port/mana/mana.controls.ini" "$PACKAGE/mana/"
fi

echo
echo "========================================"
echo " Instalando novo executavel"
echo "========================================"

cp "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x "$PACKAGE/Mana.sh"
chmod +x "$PACKAGE/mana/mana.aarch64"

echo
echo "========================================"
echo " Conteudo final do pacote"
echo "========================================"

find "$PACKAGE" -maxdepth 5 -type f -print

echo
echo "========================================"
echo " Gerando ZIP"
echo "========================================"

cd "$PACKAGE"

zip -r \
    "$DIST/mana-r36s-portmaster-aarch64.zip" \
    . \
    -x "*.DS_Store"

cd "$ROOT"

echo
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"

echo
echo "Arquivos gerados:"

ls -lh "$DIST/"

echo
echo "ZIP:"
ls -lh "$DIST/mana-r36s-portmaster-aarch64.zip"

echo
echo "Executavel:"
ls -lh "$DIST/mana.aarch64"

echo
echo "Diagnosticos:"
ls -lh "$DIST/diagnostics.txt"

echo
echo "========================================"
echo " FIM"
echo "========================================"
