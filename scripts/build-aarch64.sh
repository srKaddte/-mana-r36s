#!/bin/bash
set -e

ROOT=/workspace
SRC_TAR="$ROOT/source/mana-master.tar.gz"
BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

rm -rf "$BUILD" "$INSTALL" "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"
mkdir -p "$PORT"

echo "========================================"
echo " Mana 0.8.0 AArch64 / PortMaster Build"
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
    pkg-config \
    python3

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

echo "========================================"
echo " Corrigindo compatibilidade SDL2_ttf"
echo "========================================"
echo

TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: truetypefont.cpp nao encontrado:"
    echo "$TRUETYPE_CPP"
    exit 1
fi

echo "Arquivo encontrado:"
echo "$TRUETYPE_CPP"
echo

python3 - "$TRUETYPE_CPP" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    source = f.read()

if "TTF_SetFontSize(" not in source:
    print("TTF_SetFontSize nao encontrado.")
    print("Nenhuma substituicao necessaria.")
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
    print("ERRO: nao foi possivel localizar a funcao updateFontScale().")
    sys.exit(1)

if "TTF_SetFontSize(" in source_new:
    print("ERRO: TTF_SetFontSize ainda existe depois da correcao.")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(source_new)

print("OK: updateFontScale() foi corrigida.")
print("OK: TTF_SetFontSize() foi removida do arquivo.")
PY

echo
echo "=== Verificando correcao SDL2_ttf ==="

if grep -n "TTF_SetFontSize" "$TRUETYPE_CPP"; then
    echo
    echo "ERRO: TTF_SetFontSize ainda esta presente."
    exit 1
fi

echo
echo "Correcao SDL2_ttf aplicada com sucesso."
echo

# -----------------------------------------------------------------------------
# Software cursor patch.
# The working controller mapping remains unchanged; the only input addition is
# SELECT -> F12, used exclusively to toggle cursor visibility.
# -----------------------------------------------------------------------------
GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ] || [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.h/gui.cpp nao encontrados."
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import re
import sys
from pathlib import Path

h_path = Path(sys.argv[1])
cpp_path = Path(sys.argv[2])
h = h_path.read_text(encoding="utf-8")
cpp = cpp_path.read_text(encoding="utf-8")

# ---- gui.h ----
# The source tarball may already contain part or all of a previous cursor
# implementation. Reuse what is already present instead of aborting.
cursor_already_complete = (
    h.count("ResourceRef<Image> mSoftwareCursor;") == 1
    and h.count("bool mSoftwareCursorVisible = true;") == 1
    and "graphics/gui/mouse.png" in cpp
    and "mSoftwareCursorVisible = !mSoftwareCursorVisible;" in cpp
    and "graphics->drawImage(" in cpp
    and "SDL_ShowCursor(SDL_ENABLE)" not in cpp
)

if cursor_already_complete:
    print("OK: cursor software ja esta presente; nenhuma duplicacao sera feita.")
    sys.exit(0)

if '#include "resources/image.h"' not in h:
    marker = '#include "resources/theme.h"\n'
    if marker not in h:
        raise SystemExit("ERRO: ponto de insercao de resources/image.h nao encontrado.")
    h = h.replace(marker, marker + '#include "resources/image.h"\n', 1)

member_marker = '        std::vector<SDL_Cursor *> mSystemMouseCursors;\n'
if member_marker not in h:
    raise SystemExit("ERRO: declaracao mSystemMouseCursors nao encontrada.")

if "ResourceRef<Image> mSoftwareCursor;" not in h:
    h = h.replace(
        member_marker,
        '        ResourceRef<Image> mSoftwareCursor;\n'
        '        bool mSoftwareCursorVisible = true;\n'
        + member_marker,
        1,
    )
elif "bool mSoftwareCursorVisible = true;" not in h:
    h = h.replace(
        '        ResourceRef<Image> mSoftwareCursor;\n',
        '        ResourceRef<Image> mSoftwareCursor;\n'
        '        bool mSoftwareCursorVisible = true;\n',
        1,
    )

# ---- gui.cpp constructor ----
init_re = re.compile(
    r'^(?P<indent>\s*)setUseCustomCursor\(config\.customCursor\);\s*$',
    re.MULTILINE,
)
matches = list(init_re.finditer(cpp))

if len(matches) != 1:
    raise SystemExit(
        f"ERRO: setUseCustomCursor(config.customCursor) encontrado {len(matches)} vezes."
    )

indent = matches[0].group("indent")
init_insert = (
    f"{indent}setUseCustomCursor(config.customCursor);\n"
    f"\n"
    f"{indent}// PortMaster/R36S software cursor.\n"
    f"{indent}mSoftwareCursor = ResourceManager::getInstance()->getImage(\n"
    f"{indent}    \"graphics/gui/mouse.png\"\n"
    f"{indent});\n"
    f"{indent}mMouseX = graphics->getWidth() / 2;\n"
    f"{indent}mMouseY = graphics->getHeight() / 2;\n"
    f"{indent}mSoftwareCursorVisible = true;\n"
    f"{indent}SDL_ShowCursor(SDL_DISABLE);"
)

cpp = cpp[:matches[0].start()] + init_insert + cpp[matches[0].end():]

# ---- draw() ----
draw_pattern = re.compile(
    r"void Gui::draw\(\)\n\{.*?\n\}\nvoid Gui::event",
    re.DOTALL,
)

draw_replacement = '''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);
    if (!graphics)
        return;

    if (mActiveDrag)
    {
        graphics->pushClipArea(gcn::Rectangle(0, 0,
                                              graphics->getWidth(),
                                              graphics->getHeight()));
        mActiveDrag->draw(graphics, mMouseX, mMouseY);
        graphics->popClipArea();
    }

    if (mSoftwareCursorVisible && mSoftwareCursor)
    {
        graphics->pushClipArea(gcn::Rectangle(0, 0,
                                              graphics->getWidth(),
                                              graphics->getHeight()));
        graphics->drawImage(
            mSoftwareCursor.get(),
            0,
            0,
            mMouseX - 15,
            mMouseY - 17,
            40,
            40
        );
        graphics->popClipArea();
    }
}
void Gui::event'''

cpp_new, count = draw_pattern.subn(draw_replacement, cpp, count=1)
if count != 1:
    raise SystemExit("ERRO: Gui::draw() nao foi localizado exatamente uma vez.")
cpp = cpp_new

# ---- F12 visibility toggle ----
key_marker = '''void Gui::keyPressed(gcn::KeyEvent &event)
{
'''
key_insert = '''void Gui::keyPressed(gcn::KeyEvent &event)
{
    if (event.getKey().getValue() == SDLK_F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }

'''
if cpp.count(key_marker) != 1:
    raise SystemExit("ERRO: Gui::keyPressed() nao foi localizado exatamente uma vez.")
cpp = cpp.replace(key_marker, key_insert, 1)

# ---- Do not re-enable the SDL hardware cursor on movement ----
show_enable = '    SDL_ShowCursor(SDL_ENABLE);\n'
if cpp.count(show_enable) != 1:
    raise SystemExit("ERRO: SDL_ShowCursor(SDL_ENABLE) esperado nao encontrado exatamente uma vez.")
cpp = cpp.replace(show_enable, '', 1)

h_path.write_text(h, encoding="utf-8")
cpp_path.write_text(cpp, encoding="utf-8")

# Validation
checks = {
    "declaration": h.count("ResourceRef<Image> mSoftwareCursor;"),
    "visibility": h.count("bool mSoftwareCursorVisible = true;"),
    "F12": cpp.count("SDLK_F12"),
    "toggle": len(re.findall(r"mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;", cpp)),
    "init": cpp.count('getImage(\n        "graphics/gui/mouse.png"'),
    "drawImage": cpp.count("graphics->drawImage("),
    "show_enable": cpp.count("SDL_ShowCursor(SDL_ENABLE)"),
}

if checks["declaration"] != 1:
    raise SystemExit(f"ERRO: declaracao de cursor = {checks['declaration']}")
if checks["visibility"] != 1:
    raise SystemExit(f"ERRO: declaracao de visibilidade = {checks['visibility']}")
if checks["F12"] != 1:
    raise SystemExit(f"ERRO: SDLK_F12 = {checks['F12']}")
if checks["toggle"] != 1:
    raise SystemExit(f"ERRO: toggle = {checks['toggle']}")
if checks["init"] != 1:
    raise SystemExit(f"ERRO: inicializacao do cursor = {checks['init']}")
if checks["drawImage"] < 1:
    raise SystemExit("ERRO: drawImage do cursor nao encontrado.")
if checks["show_enable"] != 0:
    raise SystemExit("ERRO: SDL_ShowCursor(SDL_ENABLE) ainda presente.")

print("CURSOR PATCH TEST OK")
print(checks)
PY

echo "=== Preparando submodules ==="

rm -rf "$SRC_DIR/libs/guichan"
rm -rf "$SRC_DIR/libs/enet"

echo
echo "========================================"
echo " Clonando Guichan 0.8.3"
echo "========================================"
echo

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
echo

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
echo " Verificando GLIBC incompativel"
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

echo "=== Preparando launcher Mana.sh ==="

#
# O launcher e criado automaticamente caso o usuario
# ainda nao tenha colocado port/Mana.sh no repositorio.
#

if [ ! -f "$PORT/Mana.sh" ]; then

    echo "port/Mana.sh nao encontrado."
    echo "Criando launcher automaticamente..."

    cat > "$PORT/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/mana"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"
cd "$GAMEDIR" || exit 1

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

echo "Mana 0.8.0"
echo "Architecture: $DEVICE_ARCH"
echo "Game directory: $GAMEDIR"

if [ "$DEVICE_ARCH" != "aarch64" ]; then
    echo "ERROR: This port requires aarch64"
    pm_finish
    exit 1
fi

# Support both the normal PortMaster layout and a flattened install.
if [ -f "$GAMEDIR/mana/mana.aarch64" ]; then
    GAME="$GAMEDIR/mana/mana.aarch64"
    GAMEDATA="$GAMEDIR/mana/data"
    GAMEROOT="$GAMEDIR/mana"
elif [ -f "$GAMEDIR/mana.aarch64" ]; then
    GAME="$GAMEDIR/mana.aarch64"
    GAMEDATA="$GAMEDIR/data"
    GAMEROOT="$GAMEDIR"
else
    echo "ERROR: Mana executable not found"
    echo "Files installed under $GAMEDIR:"
    find "$GAMEDIR" -maxdepth 4 -type f -print 2>/dev/null || true
    pm_finish
    exit 1
fi

if [ ! -d "$GAMEDATA" ]; then
    echo "ERROR: Mana data directory not found: $GAMEDATA"
    echo "Directories installed under $GAMEDIR:"
    find "$GAMEDIR" -maxdepth 4 -type d -print 2>/dev/null || true
    pm_finish
    exit 1
fi

chmod +x "$GAME"

export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
if [ -f "$controlfolder/gamecontrollerdb.txt" ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="$controlfolder/gamecontrollerdb.txt"
fi
export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"

cd "$GAMEROOT" || exit 1

GPTOPID=""
if [ -n "$GPTOKEYB" ]; then
    $GPTOKEYB "mana.aarch64" -c "./mana.gptk" &
    GPTOPID=$!
fi

pm_platform_helper "$GAME"

echo "Executable: $GAME"
echo "Data: $GAMEDATA"
echo "Starting Mana..."

"$GAME" --data "$GAMEDATA" --localdata-dir "$CONFDIR"
RET=$?

echo "Mana exited with code $RET"

if [ -n "$GPTOPID" ]; then
    kill "$GPTOPID" 2>/dev/null || true
fi

pm_finish
exit $RET
EOF

    chmod +x "$PORT/Mana.sh"

    echo "OK: port/Mana.sh criado automaticamente."

else

    echo "OK: port/Mana.sh ja existe."
    chmod +x "$PORT/Mana.sh"

fi

echo

echo "=== Verificando launcher ==="

if [ ! -f "$PORT/Mana.sh" ]; then
    echo "ERRO: nao foi possivel criar port/Mana.sh"
    exit 1
fi

if [ ! -s "$PORT/Mana.sh" ]; then
    echo "ERRO: port/Mana.sh esta vazio"
    exit 1
fi

echo "Launcher encontrado:"
ls -lh "$PORT/Mana.sh"

echo

echo "=== Copiando arquivos do PortMaster ==="

cp "$PORT/Mana.sh" "$PACKAGE/"

if [ -f "$PORT/README.md" ]; then
    cp "$PORT/README.md" "$PACKAGE/"
fi

if [ -f "$PORT/gameinfo.xml" ]; then
    cp "$PORT/gameinfo.xml" "$PACKAGE/"
fi

if [ -f "$PORT/port.json" ]; then
    cp "$PORT/port.json" "$PACKAGE/"
fi

if [ -f "$PORT/screenshot.png" ]; then
    cp "$PORT/screenshot.png" "$PACKAGE/"
fi

echo

echo "=== Copiando dados do jogo ==="

if [ -d "$PORT/mana/data" ]; then

    cp -a "$PORT/mana/data" "$PACKAGE/mana/"

else

    echo "AVISO: port/mana/data nao encontrado"

fi

echo

if [ ! -f "$PACKAGE/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERRO: mouse.png nao foi encontrado nos dados do Mana."
    echo "O cursor software depende de:"
    echo "$PACKAGE/mana/data/graphics/gui/mouse.png"
    exit 1
fi

echo "OK: mouse.png presente."

echo

echo "=== Copiando licencas ==="

if [ -d "$PORT/mana/licenses" ]; then

    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"

fi

echo

echo "=== Copiando configuracao GPTK ==="

if [ -f "$PORT/mana/mana.gptk" ]; then

    cp "$PORT/mana/mana.gptk" "$PACKAGE/mana/"

elif [ -f "$PORT/mana/mana.gptk.0" ]; then

    cp "$PORT/mana/mana.gptk.0" "$PACKAGE/mana/mana.gptk"

else

    echo "port/mana/mana.gptk nao encontrado."
    echo "Criando mana.gptk com o mapeamento conhecido que funciona no R36S..."

    cat > "$PACKAGE/mana/mana.gptk" <<'EOF'
# Mana 0.8.0 R36S controls
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
EOF

fi

if ! grep -Eq '^[[:space:]]*select[[:space:]]*=[[:space:]]*f12[[:space:]]*$' "$PACKAGE/mana/mana.gptk"; then
    printf '\nselect = f12\n' >> "$PACKAGE/mana/mana.gptk"
fi

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao esta no pacote final."
    exit 1
fi

echo "OK: mana.gptk presente."

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
echo " Verificando launcher final"
echo "========================================"

if [ ! -f "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta no pacote final"
    exit 1
fi

if [ ! -x "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta executavel"
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 nao esta no pacote final"
    exit 1
fi

echo "OK: Mana.sh presente."

echo "OK: mana.aarch64 presente."

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao esta no pacote final"
    exit 1
fi

echo "OK: mana.gptk presente."

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
