#!/bin/bash

set -e

ROOT=/workspace

SRC_TAR="$ROOT/source/mana-master.tar.gz"

BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

echo "========================================"
echo " Mana 0.8.0 AArch64 / R36S"
echo " Mouse + Teclado + PortMaster"
echo "========================================"
echo

rm -rf "$BUILD"
rm -rf "$INSTALL"
rm -rf "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"
mkdir -p "$PORT"
mkdir -p "$PORT/mana"

export DEBIAN_FRONTEND=noninteractive

echo "========================================"
echo " Instalando dependencias"
echo "========================================"

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
    pkg-config \
    python3

echo
echo "Dependencias instaladas."
echo

echo "========================================"
echo " Verificando source"
echo "========================================"

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

echo "Source encontrado:"
echo "$SRC_TAR"
echo

echo "========================================"
echo " Extraindo Mana"
echo "========================================"

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: diretorio do Mana nao encontrado."
    exit 1
fi

echo "SRC_DIR=$SRC_DIR"
echo

echo "========================================"
echo " Corrigindo SDL2_ttf"
echo "========================================"

TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: truetypefont.cpp nao encontrado."
    exit 1
fi

python3 - "$TRUETYPE_CPP" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    source = f.read()

if "TTF_SetFontSize(" not in source:
    print("TTF_SetFontSize nao encontrado.")
    print("Nenhuma alteracao necessaria.")
    sys.exit(0)

replacement = r'''void TrueTypeFont::updateFontScale(float scale)
{
    if (mScale == scale)
        return;

    if (scale <= 0.0f)
        return;

    for (auto font : mFonts)
    {
        const int newSize = std::max(
            1,
            static_cast<int>(
                std::lround(font->mPointSize * scale)
            )
        );

        TTF_Font *newFont = TTF_OpenFont(
            font->mFilename.c_str(),
            newSize
        );

        TTF_Font *newFontOutline = TTF_OpenFont(
            font->mFilename.c_str(),
            newSize
        );

        if (!newFont || !newFontOutline)
        {
            if (newFont)
                TTF_CloseFont(newFont);

            if (newFontOutline)
                TTF_CloseFont(newFontOutline);

            std::cerr
                << "WARNING: unable to resize font '"
                << font->mFilename
                << "' to "
                << newSize
                << " pixels: "
                << TTF_GetError()
                << std::endl;

            continue;
        }

        TTF_SetFontStyle(
            newFont,
            font->mStyle
        );

        TTF_SetFontStyle(
            newFontOutline,
            font->mStyle
        );

        const int outlineSize = std::max(
            1,
            static_cast<int>(
                std::lround(scale)
            )
        );

        TTF_SetFontOutline(
            newFontOutline,
            outlineSize
        );

        TTF_CloseFont(font->mFont);
        TTF_CloseFont(font->mFontOutline);

        font->mFont = newFont;
        font->mFontOutline = newFontOutline;

        font->mCache.clear();
    }

    mScale = scale;
}
'''

pattern = re.compile(
    r"void\s+TrueTypeFont::updateFontScale\s*\(float\s+scale\)\s*\{.*?\n\}\s*\n\s*(?=int\s+TrueTypeFont::getWidth)",
    re.DOTALL
)

source_new, count = pattern.subn(
    replacement,
    source,
    count=1
)

if count != 1:
    print("ERRO: updateFontScale() nao localizada.")
    sys.exit(1)

if "TTF_SetFontSize(" in source_new:
    print("ERRO: TTF_SetFontSize ainda existe.")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(source_new)

print("OK: SDL2_ttf corrigido.")
PY

if grep -q "TTF_SetFontSize(" "$TRUETYPE_CPP"; then
    echo "ERRO: TTF_SetFontSize ainda esta presente."
    exit 1
fi

echo "SDL2_ttf OK."
echo

echo "========================================"
echo " Adicionando cursor de software R36S"
echo "========================================"

GUI_CPP="$SRC_DIR/src/gui/gui.cpp"
GUI_H="$SRC_DIR/src/gui/gui.h"

if [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.cpp nao encontrado."
    exit 1
fi

if [ ! -f "$GUI_H" ]; then
    echo "ERRO: gui.h nao encontrado."
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys

gui_h = sys.argv[1]
gui_cpp = sys.argv[2]

with open(gui_h, "r", encoding="utf-8") as f:
    h = f.read()

with open(gui_cpp, "r", encoding="utf-8") as f:
    cpp = f.read()

# ------------------------------------------------------------
# gui.h
# ------------------------------------------------------------

if '#include "resources/imageset.h"' not in h:
    marker = '#include "resources/theme.h"'

    if marker not in h:
        print("ERRO: include de resources/theme.h nao encontrado.")
        sys.exit(1)

    h = h.replace(
        marker,
        marker + '\n#include "resources/imageset.h"',
        1
    )

if 'ResourceRef<ImageSet> mSoftwareCursor;' not in h:
    marker = '        int mMouseY = 0;'

    if marker not in h:
        print("ERRO: mMouseY nao encontrado.")
        sys.exit(1)

    h = h.replace(
        marker,
        marker + '\n        ResourceRef<ImageSet> mSoftwareCursor;',
        1
    )

with open(gui_h, "w", encoding="utf-8") as f:
    f.write(h)

# ------------------------------------------------------------
# gui.cpp
# ------------------------------------------------------------

cursor_init = r'''
    // R36S / PortMaster software cursor.
    //
    // GPTOKEYB fornece os eventos de mouse, mas KMS/DRM
    // pode nao desenhar o cursor SDL hardware.
    //
    // Por isso o cursor e desenhado diretamente pelo Mana.
    mSoftwareCursor = ResourceManager::getInstance()->getImageSet(
        mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
'''

if "mSoftwareCursor = ResourceManager::getInstance()->getImageSet(" not in cpp:

    marker = '    setUseCustomCursor(config.customCursor);'

    if marker not in cpp:
        print("ERRO: setUseCustomCursor() nao encontrado.")
        sys.exit(1)

    cpp = cpp.replace(
        marker,
        marker + cursor_init,
        1
    )

# ------------------------------------------------------------
# Substitui Gui::draw()
# ------------------------------------------------------------

old_draw = r'''void Gui::draw()
{
    gcn::Gui::draw();

    if (!mActiveDrag)
        return;

    auto *graphics = static_cast<Graphics*>(mGraphics);
    if (!graphics)
        return;

    graphics->pushClipArea(gcn::Rectangle(0, 0,
                                          graphics->getWidth(),
                                          graphics->getHeight()));
    mActiveDrag->draw(graphics, mMouseX, mMouseY);
    graphics->popClipArea();
}
'''

new_draw = r'''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);

    if (!graphics)
        return;

    if (mActiveDrag)
    {
        graphics->pushClipArea(
            gcn::Rectangle(
                0,
                0,
                graphics->getWidth(),
                graphics->getHeight()
            )
        );

        mActiveDrag->draw(
            graphics,
            mMouseX,
            mMouseY
        );

        graphics->popClipArea();
    }

    // Cursor de software para R36S / KMS-DRM.
    //
    // O analógico direito movimenta mMouseX/mMouseY
    // atraves do GPTOKEYB.
    //
    // O cursor e desenhado dentro do frame do Mana,
    // portanto nao depende de X11 ou compositor.

    if (mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17
        );
    }
}
'''

if old_draw in cpp:
    cpp = cpp.replace(
        old_draw,
        new_draw,
        1
    )

elif "mSoftwareCursor->get(0)" not in cpp:
    print("ERRO: nao foi possivel substituir Gui::draw().")
    sys.exit(1)

with open(gui_cpp, "w", encoding="utf-8") as f:
    f.write(cpp)

print("OK: cursor de software adicionado.")
PY

echo
echo "=== Verificando cursor ==="

if ! grep -q "mSoftwareCursor" "$GUI_H"; then
    echo "ERRO: mSoftwareCursor nao esta em gui.h."
    exit 1
fi

if ! grep -q "mSoftwareCursor" "$GUI_CPP"; then
    echo "ERRO: mSoftwareCursor nao esta em gui.cpp."
    exit 1
fi

if ! grep -q "SDL_ShowCursor(SDL_DISABLE" "$GUI_CPP"; then
    echo "ERRO: cursor SDL hardware nao foi desativado."
    exit 1
fi

if ! grep -q "drawImage" "$GUI_CPP"; then
    echo "ERRO: desenho do cursor nao encontrado."
    exit 1
fi

echo "Cursor de software: OK."
echo

echo "========================================"
echo " Preparando Guichan 0.8.3"
echo "========================================"

rm -rf "$SRC_DIR/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

echo
echo "Guichan:"
cd "$SRC_DIR/libs/guichan"
git describe --tags --always
git rev-parse HEAD
cd "$ROOT"

echo

echo "========================================"
echo " Preparando ENet 1.3.18"
echo "========================================"

rm -rf "$SRC_DIR/libs/enet"

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

echo
echo "ENet:"
cd "$SRC_DIR/libs/enet"
git describe --tags --always
git rev-parse HEAD
cd "$ROOT"

echo

echo "========================================"
echo " Ajustando SDL2_ttf"
echo "========================================"

find "$SRC_DIR" -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 |
while IFS= read -r -d '' FILE
do
    sed -i \
        's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' \
        "$FILE"

    sed -i \
        's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' \
        "$FILE"

    sed -i \
        's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' \
        "$FILE"
done

echo
echo "========================================"
echo " Dependencias detectadas"
echo "========================================"

echo
echo "SDL2:"
pkg-config --modversion sdl2 || true

echo
echo "SDL2_image:"
pkg-config --modversion SDL2_image || true

echo
echo "SDL2_mixer:"
pkg-config --modversion SDL2_mixer || true

echo
echo "SDL2_net:"
pkg-config --modversion SDL2_net || true

echo
echo "SDL2_ttf:"
pkg-config --modversion SDL2_ttf || true

echo
echo "PhysFS:"
pkg-config --modversion physfs || true

echo
echo "libxml2:"
pkg-config --modversion libxml-2.0 || true

echo

echo "========================================"
echo " Configurando CMake"
echo "========================================"

cmake -S "$SRC_DIR" \
    -B "$BUILD/cmake" \
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
    echo "ERRO: executavel nao encontrado."
    find "$INSTALL" -maxdepth 6 -type f -print || true
    exit 1
fi

echo "Executavel:"
echo "$BIN"
echo

echo "========================================"
echo " Copiando executavel"
echo "========================================"

cp "$BIN" "$DIST/mana.aarch64"

chmod +x "$DIST/mana.aarch64"

echo

echo "========================================"
echo " Diagnostico ELF"
echo "========================================"

file "$DIST/mana.aarch64"

echo
echo "GLIBC:"

readelf --version-info "$DIST/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu || true

echo
echo "NEEDED:"

readelf -d "$DIST/mana.aarch64" \
    | grep NEEDED || true

echo
echo "RPATH/RUNPATH:"

readelf -d "$DIST/mana.aarch64" \
    | grep -E 'RPATH|RUNPATH' || true

echo

echo "========================================"
echo " Verificando GLIBC"
echo "========================================"

if readelf --version-info "$DIST/mana.aarch64" \
    | grep -q 'GLIBC_2.43'
then
    echo "ERRO: GLIBC_2.43 encontrada."
    exit 1
fi

echo "GLIBC 2.43 nao encontrada."
echo

echo "========================================"
echo " Preparando PortMaster"
echo "========================================"

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

echo
echo "=== Mana.sh ==="

if [ ! -f "$PORT/Mana.sh" ]; then

    echo "port/Mana.sh nao existe."
    echo "Criando automaticamente."

    cat > "$PORT/Mana.sh" <<'EOF'
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

if [ -f "$controlfolder/control.txt" ]; then
    source "$controlfolder/control.txt"
else
    echo "ERRO: control.txt nao encontrado."
    exit 1
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
echo " Mana 0.8.0 PortMaster R36S"
echo "========================================"

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -f "$GAME" ]; then
    echo "ERRO: executavel nao encontrado:"
    echo "$GAME"
    exit 1
fi

chmod +x "$GAME"

if [ -d "$GAMEDIR/mana/libs.aarch64" ]; then
    export LD_LIBRARY_PATH="$GAMEDIR/mana/libs.aarch64:${LD_LIBRARY_PATH:-}"
fi

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

cd "$GAMEDIR/mana" || exit 1

echo
echo "Iniciando GPTOKEYB..."

GPTOPID=""

if [ -n "${GPTOKEYB2:-}" ]; then

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "./mana.gptk" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "./mana.gptk" &

    GPTOPID=$!

fi

echo
echo "Iniciando Mana..."

"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"

RET=$?

if [ -n "$GPTOPID" ]; then
    kill "$GPTOPID" 2>/dev/null || true
fi

echo
echo "Mana terminou: $RET"

exit "$RET"
EOF

    chmod +x "$PORT/Mana.sh"

else

    echo "port/Mana.sh encontrado."
    chmod +x "$PORT/Mana.sh"

fi

echo

echo "========================================"
echo " Copiando PortMaster"
echo "========================================"

cp "$PORT/Mana.sh" "$PACKAGE/"

if [ -f "$PORT/port.json" ]; then
    cp "$PORT/port.json" "$PACKAGE/"
fi

if [ -f "$PORT/README.md" ]; then
    cp "$PORT/README.md" "$PACKAGE/"
fi

if [ -f "$PORT/gameinfo.xml" ]; then
    cp "$PORT/gameinfo.xml" "$PACKAGE/"
fi

if [ -f "$PORT/screenshot.png" ]; then
    cp "$PORT/screenshot.png" "$PACKAGE/"
fi

echo
echo "========================================"
echo " Copiando GPTK"
echo "========================================"

if [ -f "$PORT/mana/mana.gptk" ]; then

    cp "$PORT/mana/mana.gptk" \
       "$PACKAGE/mana/mana.gptk"

elif [ -f "$PORT/mana/mana.gptk.0" ]; then

    cp "$PORT/mana/mana.gptk.0" \
       "$PACKAGE/mana/mana.gptk"

else

    echo "ERRO: mana.gptk nao encontrado."
    exit 1

fi

echo "mana.gptk OK."

echo
echo "========================================"
echo " Copiando data"
echo "========================================"

if [ -d "$PORT/mana/data" ]; then

    cp -a "$PORT/mana/data" \
        "$PACKAGE/mana/"

else

    echo "AVISO: port/mana/data nao encontrado."

    if [ -d "$SRC_DIR/data" ]; then

        cp -a "$SRC_DIR/data" \
            "$PACKAGE/mana/"

    else

        echo "ERRO: data do Mana nao encontrado."
        exit 1

    fi
fi

echo

echo "========================================"
echo " Copiando licencas"
echo "========================================"

if [ -d "$PORT/mana/licenses" ]; then
    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"
fi

echo

echo "========================================"
echo " Procurando mouse.png"
echo "========================================"

if [ -f "$PACKAGE/mana/data/graphics/gui/mouse.png" ]; then

    echo "mouse.png encontrado."

elif [ -f "$ROOT/mouse.png" ]; then

    mkdir -p "$PACKAGE/mana/data/graphics/gui"

    cp "$ROOT/mouse.png" \
       "$PACKAGE/mana/data/graphics/gui/mouse.png"

    echo "mouse.png copiado do repositorio."

else

    echo "ERRO: mouse.png nao encontrado."
    exit 1

fi

echo

echo "========================================"
echo " Instalando executavel"
echo "========================================"

cp "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x "$PACKAGE/Mana.sh"
chmod +x "$PACKAGE/mana/mana.aarch64"

echo

echo "========================================"
echo " Verificacao final"
echo "========================================"

if [ ! -x "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh invalido."
    exit 1
fi

if [ ! -x "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 invalido."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk ausente."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERRO: mouse.png ausente."
    exit 1
fi

echo
echo "Arquivos principais encontrados:"
echo

ls -lh "$PACKAGE/Mana.sh"
ls -lh "$PACKAGE/mana/mana.aarch64"
ls -lh "$PACKAGE/mana/mana.gptk"
ls -lh "$PACKAGE/mana/data/graphics/gui/mouse.png"

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
echo " Salvando diagnosticos"
echo "========================================"

{
    echo "Mana 0.8.0 AArch64 R36S"
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

    echo "=== SOFTWARE CURSOR ==="
    grep -n "mSoftwareCursor" "$GUI_CPP" || true
    echo

    echo "=== GPTK ==="
    cat "$PACKAGE/mana/mana.gptk"
    echo

    echo "=== PACKAGE ==="
    find "$PACKAGE" -type f -print
} > "$DIST/diagnostics.txt"

echo

echo "========================================"
echo " BUILD FINALIZADO"
echo "========================================"

echo
echo "Arquivos em dist:"
ls -lh "$DIST/"

echo
echo "ZIP:"
ls -lh "$DIST/mana-r36s-portmaster-aarch64.zip"

echo
echo "========================================"
echo " FIM"
echo "========================================"
