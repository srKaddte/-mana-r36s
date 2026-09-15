#!/bin/bash
set -e

ROOT=/workspace
SRC_TAR="$ROOT/source/mana-master.tar.gz"
BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

rm -rf "$BUILD" "$INSTALL" "$DIST"
mkdir -p "$BUILD" "$INSTALL" "$DIST" "$PORT"

echo "========================================"
echo " Mana 0.8.0 AArch64 / PortMaster Build"
echo " Base: Mana 1.0 controles funcionando"
echo " Change: software cursor only"
echo "========================================"
echo

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
echo "=== Extraindo source do Mana ==="
if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: arquivo source nao encontrado: $SRC_TAR"
    exit 1
fi

tar -xzf "$SRC_TAR" -C "$BUILD"
SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: source do Mana nao encontrado"
    exit 1
fi

echo "Source: $SRC_DIR"

# -----------------------------------------------------------------------------
# SDL2_ttf compatibility patch.
# Keep the existing build compatibility behavior; do not alter other font code.
# -----------------------------------------------------------------------------
TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"
if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: truetypefont.cpp nao encontrado: $TRUETYPE_CPP"
    exit 1
fi

python3 - "$TRUETYPE_CPP" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    source = f.read()

if "TTF_SetFontSize(" not in source:
    print("TTF_SetFontSize nao encontrado; nenhuma substituicao necessaria.")
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

        TTF_SetFontStyle(newFont, font->mStyle);
        TTF_SetFontStyle(newFontOutline, font->mStyle);

        const int outlineSize = std::max(
            1,
            static_cast<int>(
                std::lround(scale)
            )
        );

        TTF_SetFontOutline(newFontOutline, outlineSize);

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

source_new, count = pattern.subn(replacement, source, count=1)
if count != 1:
    print("ERRO: nao foi possivel localizar updateFontScale().")
    sys.exit(1)

if "TTF_SetFontSize(" in source_new:
    print("ERRO: TTF_SetFontSize ainda existe depois da correcao.")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(source_new)

print("OK: SDL2_ttf updateFontScale corrigida.")
PY

if grep -n "TTF_SetFontSize" "$TRUETYPE_CPP"; then
    echo "ERRO: TTF_SetFontSize ainda esta presente."
    exit 1
fi

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
if h.count("ResourceRef<Image> mSoftwareCursor;") != 0:
    raise SystemExit("ERRO: mSoftwareCursor ja existe no gui.h; patch nao sera duplicado.")

if '#include "resources/image.h"' not in h:
    marker = '#include "resources/theme.h"\n'
    if marker not in h:
        raise SystemExit("ERRO: ponto de insercao de resources/image.h nao encontrado.")
    h = h.replace(marker, marker + '#include "resources/image.h"\n', 1)

member_marker = '        std::vector<SDL_Cursor *> mSystemMouseCursors;\n'
if member_marker not in h:
    raise SystemExit("ERRO: declaracao mSystemMouseCursors nao encontrada.")

h = h.replace(
    member_marker,
    '        ResourceRef<Image> mSoftwareCursor;\n'
    '        bool mSoftwareCursorVisible = true;\n'
    + member_marker,
    1,
)

# ---- gui.cpp constructor ----
init_marker = '    setUseCustomCursor(config.customCursor);\n'
init_insert = '''    setUseCustomCursor(config.customCursor);

    // PortMaster/R36S software cursor. The hardware cursor is disabled because
    // the R36S does not provide a desktop compositor for SDL cursor rendering.
    mSoftwareCursor = ResourceManager::getInstance()->getImage(
        "graphics/gui/mouse.png"
    );
    mMouseX = graphics->getWidth() / 2;
    mMouseY = graphics->getHeight() / 2;
    mSoftwareCursorVisible = true;
    SDL_ShowCursor(SDL_DISABLE);
'''

if cpp.count(init_marker) != 1:
    raise SystemExit("ERRO: setUseCustomCursor(config.customCursor) inesperado; patch interrompido.")
cpp = cpp.replace(init_marker, init_insert, 1)

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

# -----------------------------------------------------------------------------
# Bundled dependencies.
# -----------------------------------------------------------------------------
rm -rf "$SRC_DIR/libs/guichan" "$SRC_DIR/libs/enet"

git clone --depth 1 --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

git clone --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

find "$SRC_DIR" -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 | while IFS= read -r -d '' FILE
do
    sed -i 's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' "$FILE"
done

echo
echo "=== Dependencias ==="
pkg-config --modversion sdl2 || true
pkg-config --modversion SDL2_image || true
pkg-config --modversion SDL2_mixer || true
pkg-config --modversion SDL2_net || true
pkg-config --modversion SDL2_ttf || true
pkg-config --modversion physfs || true
pkg-config --modversion libxml-2.0 || true

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
    echo "ERRO: executavel Mana nao foi encontrado"
    find "$INSTALL" -maxdepth 5 -type f -print || true
    exit 1
fi

cp "$BIN" "$DIST/mana.aarch64"
chmod +x "$DIST/mana.aarch64"

file "$DIST/mana.aarch64"
readelf --version-info "$DIST/mana.aarch64" | grep -o 'GLIBC_[0-9.]*' | sort -Vu || true
readelf -d "$DIST/mana.aarch64" | grep NEEDED || true
readelf -d "$DIST/mana.aarch64" | grep -E 'RPATH|RUNPATH' || true

{
    echo "========================================"
    echo " Mana 0.8.0 AArch64 Diagnostics"
    echo "========================================"
    echo
    echo "=== FILE ==="
    file "$DIST/mana.aarch64"
    echo
    echo "=== GLIBC ==="
    readelf --version-info "$DIST/mana.aarch64" | grep -o 'GLIBC_[0-9.]*' | sort -Vu || true
    echo
    echo "=== NEEDED ==="
    readelf -d "$DIST/mana.aarch64" | grep NEEDED || true
    echo
    echo "=== RPATH/RUNPATH ==="
    readelf -d "$DIST/mana.aarch64" | grep -E 'RPATH|RUNPATH' || true
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

if readelf --version-info "$DIST/mana.aarch64" | grep -q 'GLIBC_2.43'; then
    echo "ERRO: o executavel exige GLIBC_2.43"
    exit 1
fi

# -----------------------------------------------------------------------------
# PortMaster package: literal working launcher/layout, plus cursor toggle only.
# -----------------------------------------------------------------------------
PACKAGE="$DIST/mana-r36s-portmaster-aarch64"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/mana"

cat > "$PACKAGE/Mana.sh" <<'EOF_LAUNCHER'
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
EOF_LAUNCHER
chmod +x "$PACKAGE/Mana.sh"

cat > "$PACKAGE/mana/mana.gptk" <<'EOF_GPTK'
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
EOF_GPTK

if [ -f "$PORT/gameinfo.xml" ]; then
    cp "$PORT/gameinfo.xml" "$PACKAGE/"
else
    cat > "$PACKAGE/gameinfo.xml" <<'EOF_XML'
<?xml version="1.0" encoding="UTF-8"?>
<game>
  <name>Mana 0.8.0</name>
  <description>The Mana Client 0.8.0 for PortMaster AArch64 devices.</description>
  <developer>Mana Developers</developer>
  <publisher>Mana Project</publisher>
  <genre>MMORPG</genre>
  <release>2026</release>
  <version>0.8.0</version>
  <porters>local</porters>
</game>
EOF_XML
fi

if [ -f "$PORT/port.json" ]; then
    cp "$PORT/port.json" "$PACKAGE/"
else
    cat > "$PACKAGE/port.json" <<'EOF_JSON'
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
    "porter": ["local"],
    "desc": "The Mana Client 0.8.0, built for AArch64/ARM64 PortMaster devices.",
    "desc_md": null,
    "inst": "ready to run",
    "inst_md": null,
    "genres": ["rpg", "mmorpg"],
    "image": null,
    "rtr": true,
    "exp": true,
    "runtime": [],
    "store": [],
    "availability": "source",
    "reqs": [],
    "arch": ["aarch64"],
    "min_glibc": "2.29"
  }
}
EOF_JSON
fi

# Preserve the same data tree as the working package.
if [ -d "$PORT/mana/data" ]; then
    cp -a "$PORT/mana/data" "$PACKAGE/mana/"
elif [ -d "$SRC_DIR/data" ]; then
    cp -a "$SRC_DIR/data" "$PACKAGE/mana/"
else
    echo "ERRO: data do Mana nao encontrada em port/mana/data nem no source."
    exit 1
fi

if [ -d "$PORT/mana/licenses" ]; then
    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"
fi

cp "$DIST/mana.aarch64" "$PACKAGE/mana/mana.aarch64"
chmod +x "$PACKAGE/mana/mana.aarch64"

# Optional metadata from the existing port tree, without changing the core layout.
for OPTIONAL in README.md screenshot.png; do
    if [ -f "$PORT/$OPTIONAL" ]; then
        cp "$PORT/$OPTIONAL" "$PACKAGE/"
    fi
done

# -----------------------------------------------------------------------------
# Final validation before ZIP.
# -----------------------------------------------------------------------------
echo
echo "=== Validacao final ==="

[ -x "$PACKAGE/Mana.sh" ] || { echo "ERRO: Mana.sh nao executavel"; exit 1; }
[ -f "$PACKAGE/mana/mana.aarch64" ] || { echo "ERRO: mana.aarch64 ausente"; exit 1; }
[ -f "$PACKAGE/mana/mana.gptk" ] || { echo "ERRO: mana.gptk ausente"; exit 1; }
[ -d "$PACKAGE/mana/data" ] || { echo "ERRO: data ausente"; exit 1; }

grep -Fq 'pm_platform_helper "$GAME"' "$PACKAGE/Mana.sh" || { echo "ERRO: pm_platform_helper removido"; exit 1; }
grep -Fq 'SDL_GAMECONTROLLERCONFIG_FILE' "$PACKAGE/Mana.sh" || { echo "ERRO: SDL_GAMECONTROLLERCONFIG_FILE removido"; exit 1; }
grep -Fq 'LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"' "$PACKAGE/Mana.sh" || { echo "ERRO: LD_LIBRARY_PATH da base removido"; exit 1; }
! grep -Fq -- '--fullscreen' "$PACKAGE/Mana.sh" || { echo "ERRO: --fullscreen nao pode existir"; exit 1; }
grep -Fq 'select = f12' "$PACKAGE/mana/mana.gptk" || { echo "ERRO: select = f12 ausente"; exit 1; }
grep -Fq 'right_analog_up = mouse_movement_up' "$PACKAGE/mana/mana.gptk" || { echo "ERRO: mouse do analogo direito alterado"; exit 1; }
grep -Fq 'r3 = mouse_left' "$PACKAGE/mana/mana.gptk" || { echo "ERRO: R3 alterado"; exit 1; }
grep -Fq 'l3 = mouse_right' "$PACKAGE/mana/mana.gptk" || { echo "ERRO: L3 alterado"; exit 1; }

if grep -q 'SDL_ShowCursor(SDL_ENABLE)' "$SRC_DIR/src/gui/gui.cpp"; then
    echo "ERRO: cursor SDL hardware ainda pode ser reativado."
    exit 1
fi

cd "$PACKAGE"
zip -r "$DIST/mana-r36s-portmaster-aarch64.zip" . -x '*.DS_Store'
cd "$ROOT"

# Diagnostics stay outside the game payload, like the previous Actions artifact.
printf '\nBuild finalizado.\n'
ls -lh "$DIST/mana-r36s-portmaster-aarch64.zip" "$DIST/diagnostics.txt"
