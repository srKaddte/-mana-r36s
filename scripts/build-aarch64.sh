#!/usr/bin/env bash
set -euo pipefail

ROOT="/workspace"

SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"
WORK="$ROOT/.build"
SRC="$WORK/mana-master"
BUILD="$WORK/build"
DEPS="$WORK/deps"

PORT="$ROOT/port"
DIST="$ROOT/dist"

echo "========================================"
echo " Mana 0.8.0 - R36S AArch64 Build"
echo "========================================"

# ============================================================
# LIMPEZA
# ============================================================

rm -rf "$WORK"
rm -rf "$PORT"
rm -rf "$DIST"

mkdir -p "$WORK"
mkdir -p "$DEPS"
mkdir -p "$DIST"

# ============================================================
# DEPENDÊNCIAS
# ============================================================

echo
echo "=== Installing build dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    wget \
    zip \
    unzip \
    file \
    binutils \
    pkg-config \
    python3 \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    libsdl2-net-dev \
    libsdl2-ttf-dev \
    libgl-dev \
    libglu1-mesa-dev

# ============================================================
# SOURCE
# ============================================================

echo
echo "=== Checking source archive ==="

if [ ! -f "$SRC_ARCHIVE" ]; then
    echo "ERROR: source archive not found:"
    echo "$SRC_ARCHIVE"
    exit 1
fi

echo "Source:"
echo "$SRC_ARCHIVE"

echo
echo "=== Extracting Mana source ==="

tar -xzf "$SRC_ARCHIVE" -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: Mana CMakeLists.txt not found:"
    echo "$SRC/CMakeLists.txt"
    exit 2
fi

echo "Mana source:"
echo "$SRC"

# ============================================================
# SDL2_TTF COMPATIBILITY
# ============================================================

echo
echo "=== Patching SDL2_ttf compatibility ==="

TTF_CPP="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TTF_CPP" ]; then
    echo "ERROR: truetypefont.cpp not found."
    exit 3
fi

python3 - "$TTF_CPP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

old1 = "        TTF_SetFontSize(font->mFont, font->mPointSize * mScale);"
old2 = "        TTF_SetFontSize(font->mFontOutline, font->mPointSize * mScale);"

changed = False

if old1 in text:
    text = text.replace(old1, "        /* SDL_ttf 2.0.15 compatibility: font size is set when the font is created. */", 1)
    changed = True

if old2 in text:
    text = text.replace(old2, "        /* SDL_ttf 2.0.15 compatibility: outline size update unavailable. */", 1)
    changed = True

path.write_text(text)

if changed:
    print("TTF_SetFontSize compatibility patch applied.")
else:
    print("TTF_SetFontSize calls were already patched.")
PY

if grep -q "TTF_SetFontSize" "$TTF_CPP"; then
    echo "ERROR: TTF_SetFontSize is still present."
    grep -n "TTF_SetFontSize" "$TTF_CPP"
    exit 4
fi

echo "SDL2_ttf compatibility: OK"

# ============================================================
# GUICHAN 0.8.3
# ============================================================

echo
echo "=== Downloading Guichan 0.8.3 ==="

GUICHAN_TAR="$DEPS/guichan-0.8.3.tar.gz"

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$GUICHAN_TAR" \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$SRC/libs/guichan"

mkdir -p "$SRC/libs/guichan"

tar \
    -xzf "$GUICHAN_TAR" \
    -C "$SRC/libs/guichan" \
    --strip-components=1

if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then
    echo "ERROR: Guichan CMakeLists.txt not found."
    exit 5
fi

echo "Guichan:"
echo "$SRC/libs/guichan"

echo "Guichan CMakeLists: OK"

# ============================================================
# ENET 1.3.18
# ============================================================

echo
echo "=== Downloading ENet 1.3.18 ==="

ENET_TAR="$DEPS/enet-1.3.18.tar.gz"

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$ENET_TAR" \
    "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$SRC/libs/enet"

mkdir -p "$SRC/libs/enet"

tar \
    -xzf "$ENET_TAR" \
    -C "$SRC/libs/enet" \
    --strip-components=1

if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then
    echo "ERROR: ENet CMakeLists.txt not found."
    exit 6
fi

echo "ENet:"
echo "$SRC/libs/enet"

echo "ENet CMakeLists: OK"

# ============================================================
# SOFTWARE CURSOR
#
# O source tar.gz pode ser vanilla.
# O patch é aplicado aqui.
# ============================================================

echo
echo "=== Applying R36S software cursor patch ==="

GUI_H="$SRC/src/gui/gui.h"
GUI_CPP="$SRC/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ]; then
    echo "ERROR: gui.h not found."
    exit 7
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERROR: gui.cpp not found."
    exit 8
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys
import re
from pathlib import Path

header_path = Path(sys.argv[1])
cpp_path = Path(sys.argv[2])

header = header_path.read_text()
cpp = cpp_path.read_text()

# ============================================================
# HEADER
# ============================================================

if '#include "resources/imageset.h"' not in header:

    anchor = '#include "resources/theme.h"'

    if anchor not in header:
        raise SystemExit(
            "ERROR: resources/theme.h include not found."
        )

    header = header.replace(
        anchor,
        anchor + '\n#include "resources/imageset.h"',
        1
    )

if 'ResourceRef<ImageSet> mSoftwareCursor;' not in header:

    anchor = 'Cursor mCursorType = Cursor::Pointer;'

    if anchor not in header:
        raise SystemExit(
            "ERROR: mCursorType member not found."
        )

    replacement = (
        anchor +
        '\n        ResourceRef<ImageSet> mSoftwareCursor;' +
        '\n        bool mSoftwareCursorVisible = true;'
    )

    header = header.replace(
        anchor,
        replacement,
        1
    )

header_path.write_text(header)

# ============================================================
# CONSTRUCTOR
# ============================================================

if 'mSoftwareCursor = ResourceManager::getInstance()->getImageSet' not in cpp:

    anchor = '''    guiInput = new SDLInput;
    setInput(guiInput);
'''

    if anchor not in cpp:
        raise SystemExit(
            "ERROR: Gui constructor input section not found."
        )

    replacement = '''    guiInput = new SDLInput;
    setInput(guiInput);

    // R36S / PortMaster software cursor.
    // GPTK provides the mouse position and button events.
    // Mana renders the cursor itself because KMS/DRM may not
    // display an SDL hardware cursor.
    mSoftwareCursor = ResourceManager::getInstance()->getImageSet(
        mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
'''

    cpp = cpp.replace(
        anchor,
        replacement,
        1
    )

# ============================================================
# GUI::DRAW
#
# Procura a função pelo nome, independentemente do corpo
# original.
# ============================================================

draw_pattern = re.compile(
    r'void\s+Gui::draw\s*\(\s*\)\s*\{.*?\n\}',
    re.DOTALL
)

draw_match = draw_pattern.search(cpp)

if not draw_match:
    raise SystemExit(
        "ERROR: Gui::draw() function not found."
    )

new_draw = '''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);

    if (!graphics)
        return;

    // R36S software cursor.
    // The right analog stick is converted by GPTK into SDL
    // mouse movement, updating mMouseX and mMouseY.
    if (mSoftwareCursorVisible && mSoftwareCursor)
    {
        graphics->pushClipArea(
            gcn::Rectangle(
                0,
                0,
                graphics->getWidth(),
                graphics->getHeight()));

        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);

        graphics->popClipArea();
    }

    if (!mActiveDrag)
        return;

    graphics->pushClipArea(
        gcn::Rectangle(
            0,
            0,
            graphics->getWidth(),
            graphics->getHeight()));

    mActiveDrag->draw(
        graphics,
        mMouseX,
        mMouseY);

    graphics->popClipArea();
}'''

cpp = (
    cpp[:draw_match.start()]
    + new_draw
    + cpp[draw_match.end():]
)

# ============================================================
# GUI::KEYPRESSED
# ============================================================

key_pattern = re.compile(
    r'void\s+Gui::keyPressed\s*\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{.*?\n\}',
    re.DOTALL
)

key_match = key_pattern.search(cpp)

if not key_match:
    raise SystemExit(
        "ERROR: Gui::keyPressed() function not found."
    )

new_key = '''void Gui::keyPressed(gcn::KeyEvent &event)
{
    // GPTK maps SELECT to F12.
    // F12 only changes cursor visibility.
    // All other controller mappings continue working.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }

    if (mActiveDrag &&
        event.getKey().getValue() == Key::ESCAPE)
    {
        cancelActiveDrag();
        event.consume();
    }
}'''

cpp = (
    cpp[:key_match.start()]
    + new_key
    + cpp[key_match.end():]
)

# ============================================================
# HANDLE MOUSE MOVED
#
# O cursor hardware fica sempre desativado.
# ============================================================

cpp = cpp.replace(
    '''    // Make sure the cursor is visible
    SDL_ShowCursor(SDL_ENABLE);
''',
    '''    // Hardware cursor remains disabled.
    // Mana draws the software cursor in Gui::draw().
''',
    1
)

# Segurança: qualquer chamada restante que habilite o hardware
# cursor é substituída.
cpp = cpp.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

cpp_path.write_text(cpp)

print("Software cursor patch applied successfully.")
PY

# ============================================================
# VALIDAR CURSOR
# ============================================================

echo
echo "=== Checking R36S software cursor patch ==="

grep -q \
    'ResourceRef<ImageSet> mSoftwareCursor;' \
    "$GUI_H" || {
        echo "ERROR: mSoftwareCursor missing."
        exit 9
    }

grep -q \
    'bool mSoftwareCursorVisible = true;' \
    "$GUI_H" || {
        echo "ERROR: mSoftwareCursorVisible missing."
        exit 10
    }

grep -q \
    'mSoftwareCursor = ResourceManager::getInstance()->getImageSet' \
    "$GUI_CPP" || {
        echo "ERROR: software cursor initialization missing."
        exit 11
    }

grep -q \
    'mSoftwareCursorVisible && mSoftwareCursor' \
    "$GUI_CPP" || {
        echo "ERROR: software cursor draw code missing."
        exit 12
    }

grep -q \
    'mSoftwareCursorVisible = !mSoftwareCursorVisible' \
    "$GUI_CPP" || {
        echo "ERROR: cursor visibility toggle missing."
        exit 13
    }

grep -q \
    'SDL_ShowCursor(SDL_DISABLE' \
    "$GUI_CPP" || {
        echo "ERROR: hardware cursor disable missing."
        exit 14
    }

echo "Software cursor: FOUND"
echo "Cursor visibility toggle: FOUND"
echo "Hardware cursor disabled: FOUND"

# ============================================================
# VALIDAR LIBS
# ============================================================

echo
echo "=== Checking embedded libraries ==="

echo
echo "--- Guichan ---"

test -f "$SRC/libs/guichan/CMakeLists.txt"

echo "Guichan CMakeLists: OK"

echo
echo "--- ENet ---"

test -f "$SRC/libs/enet/CMakeLists.txt"

echo "ENet CMakeLists: OK"

# ============================================================
# CMAKE
# ============================================================

echo
echo "=== Configuring CMake ==="

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
echo "=== Building Mana ==="

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"

# ============================================================
# LOCALIZAR BINÁRIO
# ============================================================

echo
echo "=== Locating Mana executable ==="

BIN=""

if [ -f "$BUILD/src/mana" ]; then
    BIN="$BUILD/src/mana"
fi

if [ -z "$BIN" ]; then
    BIN="$(
        find "$BUILD" \
            -type f \
            -name "mana" \
            -perm -111 \
            -print \
            -quit
    )"
fi

if [ -z "$BIN" ]; then
    echo "ERROR: Mana executable was not produced."
    exit 15
fi

echo "Mana binary:"
echo "$BIN"

chmod +x "$BIN"

# ============================================================
# PORTMASTER
# ============================================================

echo
echo "=== Creating PortMaster package ==="

mkdir -p "$PORT/mana"

# ============================================================
# EXECUTÁVEL
# ============================================================

cp \
    "$BIN" \
    "$PORT/mana/mana.aarch64"

chmod +x \
    "$PORT/mana/mana.aarch64"

# ============================================================
# DATA
# ============================================================

echo
echo "=== Copying Mana data ==="

if [ ! -d "$SRC/data" ]; then
    echo "ERROR: Mana data directory not found."
    exit 16
fi

cp -a \
    "$SRC/data" \
    "$PORT/mana/data"

# ============================================================
# CURSOR IMAGE
# ============================================================

if [ ! -f "$PORT/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERROR: mouse.png not found."
    echo "Required:"
    echo "$PORT/mana/data/graphics/gui/mouse.png"
    exit 17
fi

echo "mouse.png: OK"

# ============================================================
# GPTK
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
# LAUNCHER
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
    echo "ERROR: PortMaster control.txt not found."
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

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
fi

# ============================================================
# GPTK VIRTUAL KEYBOARD
# ============================================================

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

unset TEXTINPUTNOAUTOCAPITALS 2>/dev/null || true

# ============================================================
# GPTK
# ============================================================

cd "$GAMEDIR/mana" || exit 1

GPTK_CONFIG="./mana.gptk"

if [ ! -f "$GPTK_CONFIG" ]; then
    echo "ERROR: mana.gptk not found."
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
# CLEANUP
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
# CONTROLES
# ============================================================

echo
echo "Mouse:"
echo "  Right analog = mouse movement"
echo "  R3           = left click"
echo "  L3           = right click"

echo
echo "Cursor:"
echo "  SELECT/F12   = show/hide cursor"

echo
echo "Virtual keyboard:"
echo "  START + DOWN = open keyboard"
echo "  D-PAD        = navigate"
echo "  A            = select / Enter"
echo "  START        = confirm"
echo "  SELECT       = cancel"

echo
echo "Starting Mana..."

# ============================================================
# GAME
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
# PORT.JSON
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
# GAMEINFO
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
# LICENSES
# ============================================================

if [ -d "$SRC/licenses" ]; then
    cp -a \
        "$SRC/licenses" \
        "$PORT/mana/licenses"
fi

# ============================================================
# ELF
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
    echo "=== RPATH / RUNPATH ==="
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
    echo "=== CURSOR STRINGS ==="
    strings "$ELF" |
        grep -E \
        'mSoftwareCursor|mSoftwareCursorVisible|SDL_ShowCursor|F12' |
        sort -u ||
        true

} >> "$DIST/diagnostics.txt"

# ============================================================
# ARCHITECTURE
# ============================================================

echo
echo "=== Checking architecture ==="

if ! file "$ELF" | grep -qi 'AArch64\|ARM aarch64'; then
    echo "ERROR: generated binary is not AArch64."
    file "$ELF"
    exit 18
fi

echo "AArch64: OK"

# ============================================================
# GLIBC
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
    echo "ERROR: binary requires GLIBC_2.43."
    exit 19
fi

echo
echo "GLIBC compatibility check OK."

# ============================================================
# PACKAGE VALIDATION
# ============================================================

echo
echo "=== Validating PortMaster package ==="

test -f "$PORT/Mana.sh"
test -f "$PORT/port.json"
test -f "$PORT/gameinfo.xml"
test -f "$PORT/mana/mana.aarch64"
test -f "$PORT/mana/mana.gptk"
test -d "$PORT/mana/data"
test -f "$PORT/mana/data/graphics/gui/mouse.png"

echo "Mana.sh: OK"
echo "port.json: OK"
echo "gameinfo.xml: OK"
echo "mana.aarch64: OK"
echo "mana.gptk: OK"
echo "data/: OK"
echo "mouse.png: OK"

# ============================================================
# ZIP
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
# LISTAGEM
# ============================================================

unzip -l "$PACKAGE" > "$DIST/package-list.txt"

echo
echo "=== PACKAGE ==="

ls -lh "$PACKAGE"

echo
echo "=== PACKAGE CONTENTS ==="

cat "$DIST/package-list.txt"

echo
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"

echo
echo "ZIP:"
echo "$PACKAGE"
