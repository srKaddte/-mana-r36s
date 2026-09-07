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
echo "========================================"

echo
echo "=== Extraindo source ==="

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: source do Mana não encontrado"
    exit 1
fi

echo "Source: $SRC_DIR"

echo
echo "=== Preparando submodules ==="

rm -rf "$SRC_DIR/libs/guichan"
rm -rf "$SRC_DIR/libs/enet"

echo "Clonando Guichan..."

git clone --depth 1 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

echo "Clonando ENet..."

git clone --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

echo
echo "=== Ajustando requisito do SDL2_ttf ==="

# O builder AArch64 do PortMaster possui SDL2_ttf 2.0.15.
# O Mana exige 2.0.18 no CMake.
# Reduzimos somente a verificação mínima do CMake.
# Se o código realmente depender de uma API posterior,
# a compilação irá acusar o erro diretamente.

find "$SRC_DIR" -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 | while IFS= read -r -d '' FILE
do
    sed -i 's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' "$FILE"
done

echo
echo "=== Configurando CMake ==="

cmake -S "$SRC_DIR" -B "$BUILD/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

echo
echo "=== Compilando Mana ==="

cmake --build "$BUILD/cmake" -j"$(nproc)"

echo
echo "=== Instalando ==="

cmake --install "$BUILD/cmake"

echo
echo "=== Procurando executável ==="

BIN="$(find "$INSTALL" -type f -name mana | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executável Mana não foi encontrado"
    echo
    echo "Conteúdo do INSTALL:"
    find "$INSTALL" -maxdepth 4 -type f -print || true
    exit 1
fi

echo "Executável encontrado:"
echo "$BIN"

echo
echo "=== Copiando executável ==="

cp "$BIN" "$DIST/mana.aarch64"

chmod +x "$DIST/mana.aarch64"

echo
echo "=== Informações do ELF ==="

file "$DIST/mana.aarch64"

echo
echo "=== GLIBC requerida ==="

readelf --version-info "$DIST/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu || true

echo
echo "=== Dependências dinâmicas ==="

readelf -d "$DIST/mana.aarch64" \
    | grep NEEDED || true

echo
echo "=== Salvando diagnósticos ==="

{
    echo "========================================"
    echo "Mana 0.8.0 AArch64 Diagnostics"
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
} > "$DIST/diagnostics.txt"

echo
echo "=== Verificando GLIBC incompatível ==="

if readelf --version-info "$DIST/mana.aarch64" \
    | grep -q 'GLIBC_2.43'; then

    echo "ERRO: o executável ainda exige GLIBC_2.43"
    exit 1
fi

echo
echo "=== PREPARANDO PACOTE PORTMASTER ==="

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

echo
echo "=== Copiando arquivos do PortMaster ==="

if [ -f "$ROOT/port/Mana.sh" ]; then
    cp "$ROOT/port/Mana.sh" "$PACKAGE/"
else
    echo "ERRO: port/Mana.sh não encontrado"
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
    echo "AVISO: port/mana/data não encontrado"
fi

echo
echo "=== Copiando licenças ==="

if [ -d "$ROOT/port/mana/licenses" ]; then
    cp -a "$ROOT/port/mana/licenses" "$PACKAGE/mana/"
fi

echo
echo "=== Copiando configuração GPTK ==="

if [ -f "$ROOT/port/mana/mana.gptk.0" ]; then
    cp "$ROOT/port/mana/mana.gptk.0" "$PACKAGE/mana/"
fi

echo
echo "=== Instalando novo executável ==="

cp "$DIST/mana.aarch64" "$PACKAGE/mana/mana.aarch64"

chmod +x "$PACKAGE/Mana.sh"
chmod +x "$PACKAGE/mana/mana.aarch64"

echo
echo "=== Conteúdo final do pacote ==="

find "$PACKAGE" -maxdepth 4 -type f -print

echo
echo "=== Gerando ZIP ==="

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
echo "Executável:"
ls -lh "$DIST/mana.aarch64"

echo
echo "Diagnósticos:"
ls -lh "$DIST/diagnostics.txt"

echo
echo "=== FIM ==="
