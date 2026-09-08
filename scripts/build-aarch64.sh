#!/usr/bin/env bash
set -euo pipefail

ROOT="/workspace"

SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.mana-build"
SRC="$WORK/mana-master"
BUILD="$WORK/build"
DEPS="$WORK/deps"
INSTALL="$WORK/install"

PORT="$ROOT/port"
DIST="$ROOT/dist"

echo "============================================================"
echo " MANA 0.8.0 - R36S / PortMaster / AArch64"
echo "============================================================"

rm -rf \
    "$WORK" \
    "$PORT" \
    "$DIST"

mkdir -p \
    "$WORK" \
    "$DEPS" \
    "$BUILD" \
    "$INSTALL" \
    "$PORT" \
    "$DIST"

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

echo "=== Extracting Mana source ==="

tar \
    -xzf "$SRC_ARCHIVE" \
    -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: Mana CMakeLists.txt not found:"
    echo "$SRC/CMakeLists.txt"

    find "$WORK" \
        -maxdepth 2 \
        -type f \
        -name CMakeLists.txt \
        -print

    exit 2
fi

# ============================================================
# DEPENDENCIES
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
# SDL2_TTF
# ============================================================

echo
echo "=== Patching SDL2_ttf minimum version ==="

python3 - "$SRC" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])

files = []

for path in src.rglob("CMakeLists.txt"):
    files.append(path)

for path in src.rglob("*.cmake"):
    if path not in files:
        files.append(path)

for path in files:

    text = path.read_text(
        encoding="utf-8"
    )

    new = re.sub(
        r"SDL2_ttf\s*>=\s*2\.0\.18",
        "SDL2_ttf>=2.0.15",
        text,
    )

    if new != text:

        path.write_text(
            new,
            encoding="utf-8"
        )

        print(
            "Patched SDL2_ttf:",
            path
        )

for path in files:

    text = path.read_text(
        encoding="utf-8"
    )

    if re.search(
        r"SDL2_ttf\s*>=\s*2\.0\.18",
        text
    ):

        raise SystemExit(
            "ERROR: SDL2_ttf >= 2.0.18 remains in "
            + str(path)
        )

print(
    "SDL2_ttf requirement validation: OK"
)
PY

echo
echo "=== Patching TTF_SetFontSize compatibility ==="

python3 - "$SRC/src/gui/truetypefont.cpp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])

if not path.is_file():

    raise SystemExit(
        "ERROR: truetypefont.cpp not found"
    )

text = path.read_text(
    encoding="utf-8"
)

new, count = re.subn(
    r"(?m)^[ \t]*TTF_SetFontSize\s*\([^;]*\);[ \t]*\n?",
    "",
    text
)

if count:

    path.write_text(
        new,
        encoding="utf-8"
    )

    print(
        "Removed TTF_SetFontSize calls:",
        count
    )

else:

    print(
        "TTF_SetFontSize calls already absent."
    )

final = path.read_text(
    encoding="utf-8"
)

if re.search(
    r"TTF_SetFontSize\s*\(",
    final
):

    raise SystemExit(
        "ERROR: actual TTF_SetFontSize() call remains."
    )

print(
    "TTF_SetFontSize validation: OK"
)
PY

# ============================================================
# GUICHAN
# ============================================================

echo
echo "=== Downloading Guichan 0.8.3 ==="

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$DEPS/guichan-0.8.3.tar.gz" \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf \
    "$SRC/libs/guichan"

mkdir -p \
    "$SRC/libs/guichan"

tar \
    -xzf "$DEPS/guichan-0.8.3.tar.gz" \
    -C "$SRC/libs/guichan" \
    --strip-components=1

if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then

    echo "ERROR: Guichan extraction failed."

    exit 3
fi

echo
echo "=== Guichan OK ==="

# ============================================================
# ENET
# ============================================================

echo
echo "=== Downloading ENet 1.3.18 ==="

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$DEPS/enet-1.3.18.tar.gz" \
    "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf \
    "$SRC/libs/enet"

mkdir -p \
    "$SRC/libs/enet"

tar \
    -xzf "$DEPS/enet-1.3.18.tar.gz" \
    -C "$SRC/libs/enet" \
    --strip-components=1

if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then

    echo "ERROR: ENet extraction failed."

    exit 4
fi

echo
echo "=== ENet OK ==="

# ============================================================
# R36S SOFTWARE CURSOR
# ============================================================

echo
echo "=== Patching R36S software cursor ==="

# IMPORTANT:
#
# The "-" after python3 means:
#
#     python3 - file1 file2
#
# reads the Python program from the heredoc.
#
# Without "-", Python would interpret gui.h as the Python
# program and produce:
#
#     SyntaxError: invalid syntax
#
python3 - \
    "$SRC/src/gui/gui.h" \
    "$SRC/src/gui/gui.cpp" <<'PY'
import re
import sys
from pathlib import Path

header = Path(sys.argv[1])
source = Path(sys.argv[2])

h = header.read_text(
    encoding="utf-8"
)

c = source.read_text(
    encoding="utf-8"
)

# ============================================================
# GUI.H
# ============================================================

if '#include "resources/imageset.h"' not in h:

    marker = '#include "resources/theme.h"'

    if marker not in h:

        raise SystemExit(
            "ERROR: resources/theme.h not found in gui.h"
        )

    h = h.replace(
        marker,
        marker
        + '\n#include "resources/imageset.h"',
        1
    )

# Remove every previous software cursor declaration.
#
# This deliberately catches both:
#
# ResourceRef<Image> mSoftwareCursor;
#
# and:
#
# ResourceRef<ImageSet> mSoftwareCursor;
#
lines = []

for line in h.splitlines():

    stripped = line.strip()

    if re.fullmatch(
        r"ResourceRef<[^>]+>\s+mSoftwareCursor\s*;",
        stripped
    ):
        continue

    if re.fullmatch(
        r"bool\s+mSoftwareCursorVisible\s*=\s*true\s*;",
        stripped
    ):
        continue

    lines.append(line)

h = "\n".join(lines) + "\n"

# Find the existing cursor type member.

cursor_pattern = re.compile(
    r"(?m)^(\s*)"
    r"Cursor\s+mCursorType\s*="
    r"\s*Cursor::Pointer\s*;"
)

match = cursor_pattern.search(h)

if not match:

    raise SystemExit(
        "ERROR: Cursor::Pointer member not found in gui.h"
    )

indent = match.group(1)

replacement = (
    f"{indent}ResourceRef<ImageSet> "
    f"mSoftwareCursor;\n"
    f"{indent}bool "
    f"mSoftwareCursorVisible = true;\n"
    f"{indent}Cursor mCursorType = Cursor::Pointer;"
)

h = cursor_pattern.sub(
    replacement,
    h,
    count=1
)

header.write_text(
    h,
    encoding="utf-8"
)

# ============================================================
# GUI.CPP
# ============================================================

# Remove software-cursor initialization blocks from previous
# attempts so the patch is idempotent.

c = re.sub(
    r"\n\s*// R36S / PortMaster software cursor\..*?"
    r"\n\s*SDL_ShowCursor\(SDL_DISABLE\);\s*",
    "\n",
    c,
    count=1,
    flags=re.DOTALL,
)

c = re.sub(
    r"\n\s*// PortMaster/R36S can receive GPTK mouse input.*?"
    r"\n\s*SDL_ShowCursor\(SDL_DISABLE\);\s*",
    "\n",
    c,
    count=1,
    flags=re.DOTALL,
)

# Hardware cursor must stay disabled.

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)

# ============================================================
# CONSTRUCTOR
# ============================================================

cursor_init = (
    "mSoftwareCursor = "
    "ResourceManager::getInstance().getImageSet("
)

cursor_init_arrow = (
    "mSoftwareCursor = "
    "ResourceManager::getInstance()->getImageSet("
)

if (
    cursor_init not in c
    and cursor_init_arrow not in c
):

    marker = (
        "    setUseCustomCursor("
        "config.customCursor);"
    )

    if marker not in c:

        raise SystemExit(
            "ERROR: setUseCustomCursor() "
            "marker not found in gui.cpp"
        )

    block = '''    setUseCustomCursor(config.customCursor);

    // R36S / PortMaster software cursor.
    // GPTOKEYB supplies mouse movement.
    // Mana renders the pointer inside the SDL frame.

    mSoftwareCursor =
        ResourceManager::getInstance().getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);'''

    c = c.replace(
        marker,
        block,
        1
    )

# ============================================================
# SAFE C++ FUNCTION REPLACEMENT
# ============================================================

def replace_function(
    text,
    signature,
    replacement
):

    match = re.search(
        signature,
        text
    )

    if not match:

        raise SystemExit(
            "ERROR: function not found: "
            + signature
        )

    brace = text.find(
        "{",
        match.start()
    )

    if brace < 0:

        raise SystemExit(
            "ERROR: opening brace not found: "
            + signature
        )

    depth = 0
    end = None

    for index in range(
        brace,
        len(text)
    ):

        char = text[index]

        if char == "{":

            depth += 1

        elif char == "}":

            depth -= 1

            if depth == 0:

                end = index + 1
                break

    if end is None:

        raise SystemExit(
            "ERROR: function closing brace not found: "
            + signature
        )

    return (
        text[:match.start()]
        + replacement
        + text[end:]
    )

# ============================================================
# GUI::DRAW
# ============================================================

new_draw = r'''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics =
        static_cast<Graphics*>(mGraphics);

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

    // R36S software cursor.
    //
    // The mouse remains active continuously.
    // SELECT only changes this boolean.
    //
    // IMPORTANT:
    // drawImage() is used here.
    // There is intentionally no drawRescaledImage()
    // in the cursor code.

    if (
        mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0
    )
    {
        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17
        );
    }
}'''

c = replace_function(
    c,
    r"void\s+Gui::draw\s*\(\s*\)\s*\{",
    new_draw
)

# ============================================================
# GUI::KEYPRESSED
# ============================================================

new_key_pressed = r'''void Gui::keyPressed(gcn::KeyEvent &event)
{
    // SELECT is mapped to F12 by the PortMaster controls.
    //
    // F12 ONLY changes software cursor visibility.
    // It does not disable mouse input.

    if (
        event.getKey().getValue()
        == Key::F12
    )
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();
        return;
    }

    if (
        mActiveDrag &&
        event.getKey().getValue()
        == Key::ESCAPE
    )
    {
        cancelActiveDrag();
        event.consume();
    }
}'''

c = replace_function(
    c,
    r"void\s+Gui::keyPressed\s*"
    r"\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{",
    new_key_pressed
)

# Make absolutely sure the hardware SDL cursor cannot be
# re-enabled by the existing mouse movement handler.

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)

source.write_text(
    c,
    encoding="utf-8"
)

# ============================================================
# SOURCE VALIDATION
# ============================================================

h = header.read_text(
    encoding="utf-8"
)

c = source.read_text(
    encoding="utf-8"
)

def require_exact(
    text,
    needle,
    expected,
    name
):

    actual = text.count(
        needle
    )

    if actual != expected:

        raise SystemExit(
            "ERROR: "
            + name
            + ": expected "
            + str(expected)
            + ", got "
            + str(actual)
        )

require_exact(
    h,
    "ResourceRef<ImageSet> mSoftwareCursor;",
    1,
    "mSoftwareCursor declaration"
)

require_exact(
    h,
    "bool mSoftwareCursorVisible = true;",
    1,
    "mSoftwareCursorVisible declaration"
)

require_exact(
    c,
    "Key::F12",
    1,
    "F12 handler"
)

require_exact(
    c,
    "mSoftwareCursorVisible = "
    "!mSoftwareCursorVisible;",
    1,
    "cursor visibility toggle"
)

require_exact(
    c,
    "mSoftwareCursor->get(0)",
    1,
    "software cursor rendering"
)

if "SDL_ShowCursor(SDL_ENABLE);" in c:

    raise SystemExit(
        "ERROR: SDL_ShowCursor(SDL_ENABLE) remains."
    )

# Validate ONLY the actual Gui::draw() function.

draw_start = c.find(
    "void Gui::draw()"
)

if draw_start < 0:

    raise SystemExit(
        "ERROR: Gui::draw() not found."
    )

draw_end = c.find(
    "\nvoid Gui::event",
    draw_start
)

if draw_end < 0:

    raise SystemExit(
        "ERROR: could not determine Gui::draw() end."
    )

draw_block = c[
    draw_start:draw_end
]

if (
    "graphics->drawImage(" not in draw_block
):

    raise SystemExit(
        "ERROR: software cursor does not use drawImage()."
    )

if "drawRescaledImage(" in draw_block:

    raise SystemExit(
        "ERROR: drawRescaledImage() is used "
        "inside the cursor draw block."
    )

print(
    "Software cursor source validation: OK"
)

PY

# ============================================================
# CURSOR ASSET
# ============================================================

echo
echo "=== Checking cursor asset ==="

CURSOR_IMAGE="$SRC/data/graphics/gui/mouse.png"

if [ ! -f "$CURSOR_IMAGE" ]; then

    echo "ERROR: cursor image not found:"
    echo "$CURSOR_IMAGE"

    exit 5
fi

echo "Cursor asset:"
file "$CURSOR_IMAGE"

# ============================================================
# CMAKE
# ============================================================

echo
echo "=== Configuring CMake ==="

cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
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
# INSTALL
# ============================================================

echo
echo "=== Installing Mana ==="

cmake \
    --install "$BUILD"

BIN=""

if [ -f "$INSTALL/bin/mana" ]; then

    BIN="$INSTALL/bin/mana"

fi

if [ -z "$BIN" ]; then

    BIN="$(
        find "$INSTALL" \
            -type f \
            -name mana \
            -perm -111 \
            -print \
            -quit \
        || true
    )"

fi

if [ -z "$BIN" ]; then

    BIN="$(
        find "$BUILD" \
            -type f \
            -name mana \
            -perm -111 \
            -print \
            -quit \
        || true
    )"

fi

if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then

    echo
    echo "ERROR: Mana executable was not produced."

    echo
    echo "Install tree:"
    find "$INSTALL" \
        -maxdepth 6 \
        -type f \
        -print \
        || true

    echo
    echo "Build tree:"
    find "$BUILD" \
        -maxdepth 6 \
        -type f \
        -name mana \
        -print \
        || true

    exit 6
fi

echo
echo "Mana executable:"
file "$BIN"

# ============================================================
# PORTMASTER DIRECTORY
# ============================================================

echo
echo "=== Creating PortMaster package ==="

mkdir -p \
    "$PORT/mana"

cp \
    "$BIN" \
    "$PORT/mana/mana.aarch64"

chmod +x \
    "$PORT/mana/mana.aarch64"

cp -a \
    "$SRC/data" \
    "$PORT/mana/data"

if [ -d "$SRC/licenses" ]; then

    cp -a \
        "$SRC/licenses" \
        "$PORT/mana/licenses"

fi

# ============================================================
# KNOWN WORKING CONTROLS
#
# Mouse is ALWAYS active.
#
# Right analog:
#     mouse movement
#
# R3:
#     left mouse button
#
# L3:
#     right mouse button
#
# SELECT:
#     F12 -> software cursor visibility
#
# Normal controls remain active at the same time.
# ============================================================

cat > "$PORT/mana/mana.gptk" <<'GPTK'
back = f12
start = enter
a = space
b = esc
x = z
y = x
l1 = shift
l2 = home
l3 = mouse_right
r1 = ctrl
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
# PORTMASTER LAUNCHER
# ============================================================

cat > "$PORT/Mana.sh" <<'LAUNCHER'
#!/bin/bash

set -u

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster" ]; then

    controlfolder="/opt/system/Tools/PortMaster"

elif [ -d "/opt/tools/PortMaster" ]; then

    controlfolder="/opt/tools/PortMaster"

elif [ -d "/PortMaster" ]; then

    controlfolder="/PortMaster"

else

    controlfolder="/roms/ports/PortMaster"

fi

if [ ! -f "$controlfolder/control.txt" ]; then

    echo "ERROR: PortMaster control.txt not found:"
    echo "$controlfolder/control.txt"

    exit 1
fi

source "$controlfolder/control.txt"

if [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then

    source "${controlfolder}/mod_${CFW_NAME}.txt"

fi

get_controls

GAMEDIR="/$directory/ports/mana"

GAMEROOT="$GAMEDIR/mana"

GAMEDATA="$GAMEROOT/data"

CONFDIR="$GAMEDIR/conf"

mkdir -p \
    "$CONFDIR"

cd "$GAMEDIR" || exit 1

LOGFILE="$GAMEDIR/log.txt"

: > "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "============================================"
echo " Mana 0.8.0 - R36S"
echo "============================================"

echo "Architecture: ${DEVICE_ARCH:-unknown}"
echo "Game directory: $GAMEDIR"

if [ "${DEVICE_ARCH:-}" != "aarch64" ]; then

    echo "ERROR: this package requires aarch64."

    pm_finish

    exit 1
fi

GAME="$GAMEROOT/mana.aarch64"

if [ ! -f "$GAME" ]; then

    echo "ERROR: Mana executable not found:"
    echo "$GAME"

    pm_finish

    exit 1
fi

if [ ! -d "$GAMEDATA" ]; then

    echo "ERROR: Mana data directory not found:"
    echo "$GAMEDATA"

    pm_finish

    exit 1
fi

chmod +x "$GAME"

export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"

if [ -n "${sdl_controllerconfig:-}" ]; then

    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

fi

# ============================================================
# PortMaster interactive text input.
#
# GPTOKEYB handles:
#
# START + D-PAD DOWN
#
# and provides the interactive text-entry interface.
# ============================================================

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

# ============================================================
# Libraries
# ============================================================

if [ -d "$GAMEDIR/libs.${DEVICE_ARCH:-aarch64}" ]; then

    export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:${LD_LIBRARY_PATH:-}"

fi

if [ -d "$GAMEROOT/libs.${DEVICE_ARCH:-aarch64}" ]; then

    export LD_LIBRARY_PATH="$GAMEROOT/libs.${DEVICE_ARCH}:$GAMEDIR/libs.${DEVICE_ARCH}:${LD_LIBRARY_PATH:-}"

fi

cd "$GAMEROOT" || exit 1

# ============================================================
# Platform helper
# ============================================================

if command -v pm_platform_helper >/dev/null 2>&1; then

    pm_platform_helper "$GAME"

fi

GPTOPID=""

# ============================================================
# GPTOKEYB2
# ============================================================

if [ -n "${GPTOKEYB2:-}" ]; then

    echo "Starting GPTOKEYB2"

    echo "Controls:"
    cat "$GAMEROOT/mana.gptk"

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GAMEROOT/mana.gptk" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    echo "Starting GPTOKEYB"

    echo "Controls:"
    cat "$GAMEROOT/mana.gptk"

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GAMEROOT/mana.gptk" &

    GPTOPID=$!

else

    echo "ERROR: GPTOKEYB/GPTOKEYB2 not available."

    pm_finish

    exit 1
fi

cleanup()
{
    if [ -n "${GPTOPID:-}" ]; then

        kill "$GPTOPID" \
            2>/dev/null \
            || true

        wait "$GPTOPID" \
            2>/dev/null \
            || true

    fi

    pm_finish
}

trap cleanup EXIT

echo
echo "Mouse: ALWAYS ACTIVE"
echo "Right analog: mouse movement"
echo "R3: left mouse button"
echo "L3: right mouse button"
echo "SELECT: show/hide software cursor"
echo "START + DOWN: virtual keyboard"
echo

# ============================================================
# IMPORTANT:
#
# Do NOT pass --fullscreen.
# Mana 0.8.0 does not need that argument here.
# ============================================================

"$GAME" \
    --data "$GAMEDATA" \
    --localdata-dir "$CONFDIR"

RET=$?

echo
echo "Mana exited with code: $RET"

exit "$RET"
LAUNCHER

chmod +x \
    "$PORT/Mana.sh"

# ============================================================
# PORTMASTER METADATA
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
      "Kaddte"
    ],
    "desc": "The Mana Client 0.8.0 for AArch64 PortMaster devices.",
    "desc_md": null,
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

cat > "$PORT/gameinfo.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<game>
  <name>Mana 0.8.0</name>
  <description>The Mana Client 0.8.0 for PortMaster AArch64 devices.</description>
  <developer>Mana Developers</developer>
  <publisher>Mana Project</publisher>
  <genre>MMORPG</genre>
  <release>2026</release>
  <version>0.8.0</version>
  <porters>Kaddte</porters>
</game>
XML

# ============================================================
# PACKAGE VALIDATION
# ============================================================

echo
echo "=== Validating final package ==="

test -f \
    "$PORT/Mana.sh"

test -x \
    "$PORT/Mana.sh"

test -f \
    "$PORT/mana/mana.aarch64"

test -x \
    "$PORT/mana/mana.aarch64"

test -f \
    "$PORT/mana/mana.gptk"

test -f \
    "$PORT/mana/data/graphics/gui/mouse.png"

test -f \
    "$PORT/port.json"

test -f \
    "$PORT/gameinfo.xml"

# ============================================================
# CONTROL VALIDATION
# ============================================================

grep -q \
    '^back = f12$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^start = enter$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^right_analog_up = mouse_movement_up$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^right_analog_down = mouse_movement_down$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^right_analog_left = mouse_movement_left$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^right_analog_right = mouse_movement_right$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^r3 = mouse_left$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^l3 = mouse_right$' \
    "$PORT/mana/mana.gptk"

# ============================================================
# ELF VALIDATION
# ============================================================

echo
echo "=== Validating ELF ==="

file \
    "$PORT/mana/mana.aarch64"

if ! file \
    "$PORT/mana/mana.aarch64" |
    grep -qi "aarch64"; then

    echo "ERROR: executable is not AArch64."

    exit 7
fi

# ============================================================
# GLIBC VALIDATION
# ============================================================

echo
echo "=== Checking GLIBC requirements ==="

readelf \
    --version-info \
    "$PORT/mana/mana.aarch64" \
    2>/dev/null |
    grep -o \
        'GLIBC_[0-9][0-9.]*' |
    sort -Vu |
    tee "$DIST/glibc.txt" \
    || true

if readelf \
    --version-info \
    "$PORT/mana/mana.aarch64" \
    2>/dev/null |
    grep -Eq \
        'GLIBC_2\.(3[2-9]|[4-9][0-9])'; then

    echo
    echo "ERROR: binary requires too-new GLIBC."

    exit 8
fi

# ============================================================
# DIAGNOSTICS
# ============================================================

echo
echo "=== Generating diagnostics ==="

{
    echo "===== FILE ====="

    file \
        "$PORT/mana/mana.aarch64"

    echo
    echo "===== NEEDED ====="

    readelf \
        -d \
        "$PORT/mana/mana.aarch64" \
        2>/dev/null |
        grep NEEDED \
        || true

    echo
    echo "===== GLIBC ====="

    cat "$DIST/glibc.txt"

    echo
    echo "===== GPTK ====="

    cat \
        "$PORT/mana/mana.gptk"

    echo
    echo "===== SOURCE CURSOR ====="

    grep -n -E \
        'mSoftwareCursor|mSoftwareCursorVisible|Key::F12|SDL_ShowCursor' \
        "$SRC/src/gui/gui.h" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo
    echo "===== CURSOR ASSET ====="

    file \
        "$PORT/mana/data/graphics/gui/mouse.png"

    echo
    echo "===== PACKAGE TREE ====="

    find \
        "$PORT" \
        -type f \
        -print |
        sort

} > "$DIST/diagnostics.txt"

# ============================================================
# ZIP
# ============================================================

echo
echo "=== Creating PortMaster ZIP ==="

PACKAGE
