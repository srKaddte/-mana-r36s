#!/usr/bin/env bash
set -euo pipefail

ROOT="/workspace"
SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.mana-build"
DEPS="$WORK/deps"
BUILD="$WORK/build"
INSTALL="$WORK/install"
SRC="$WORK/mana-master"

PORT="$ROOT/port"
DIST="$ROOT/dist"

rm -rf "$WORK" "$PORT" "$DIST"
mkdir -p "$DEPS" "$BUILD" "$INSTALL" "$DIST" "$PORT"

echo "============================================================"
echo " Mana 0.8.0 - R36S / PortMaster / AArch64"
echo "============================================================"

if [ ! -f "$SRC_ARCHIVE" ]; then
    echo "ERROR: missing source archive: $SRC_ARCHIVE"
    exit 1
fi

echo "=== Extracting Mana source ==="
tar -xzf "$SRC_ARCHIVE" -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: expected source directory $SRC was not found."
    echo "Extracted directories:"
    find "$WORK" -mindepth 1 -maxdepth 1 -type d -print
    exit 2
fi

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

echo "=== Patching SDL2_ttf requirement ==="

python3 - "$SRC" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])

files = list(src.rglob("CMakeLists.txt")) + list(src.rglob("*.cmake"))

for path in files:
    text = path.read_text(encoding="utf-8")

    new = re.sub(
        r"SDL2_ttf\s*>=\s*2\.0\.18",
        "SDL2_ttf>=2.0.15",
        text,
    )

    if new != text:
        path.write_text(new, encoding="utf-8")
        print(f"patched: {path}")

for path in files:
    text = path.read_text(encoding="utf-8")

    if re.search(
        r"SDL2_ttf\s*>=\s*2\.0\.18",
        text,
    ):
        raise SystemExit(
            f"ERROR: SDL2_ttf >= 2.0.18 remains in {path}"
        )

print("SDL2_ttf requirement: OK")
PY

echo "=== Patching TrueTypeFont::updateFontScale ==="

python3 - "$SRC/src/gui/truetypefont.cpp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])

if not path.is_file():
    raise SystemExit(
        f"ERROR: {path} not found"
    )

text = path.read_text(
    encoding="utf-8"
)

new, count = re.subn(
    r"(?m)^[ \t]*TTF_SetFontSize\s*\([^;]*\);[ \t]*\n?",
    "",
    text,
)

if count == 0:
    print("TTF_SetFontSize calls already absent.")
else:
    path.write_text(
        new,
        encoding="utf-8"
    )

    print(
        f"removed {count} TTF_SetFontSize call(s)"
    )

final = path.read_text(
    encoding="utf-8"
)

if re.search(
    r"TTF_SetFontSize\s*\(",
    final
):
    raise SystemExit(
        "ERROR: an actual TTF_SetFontSize() call remains"
    )

print(
    "TTF_SetFontSize validation: OK"
)
PY

echo "=== Downloading Guichan 0.8.3 ==="

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$DEPS/guichan-0.8.3.tar.gz" \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$SRC/libs/guichan"

mkdir -p "$SRC/libs/guichan"

tar \
    -xzf "$DEPS/guichan-0.8.3.tar.gz" \
    -C "$SRC/libs/guichan" \
    --strip-components=1

if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then
    echo "ERROR: Guichan extraction failed."
    exit 3
fi

echo "=== Downloading ENet 1.3.18 ==="

curl \
    -L \
    --fail \
    --retry 3 \
    -o "$DEPS/enet-1.3.18.tar.gz" \
    "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$SRC/libs/enet"

mkdir -p "$SRC/libs/enet"

tar \
    -xzf "$DEPS/enet-1.3.18.tar.gz" \
    -C "$SRC/libs/enet" \
    --strip-components=1

if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then
    echo "ERROR: ENet extraction failed."
    exit 4
fi

echo "=== Patching R36S software cursor ==="

python3 \
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
# gui.h
# ============================================================

if '#include "resources/imageset.h"' not in h:

    marker = '#include "resources/theme.h"'

    if marker not in h:
        raise SystemExit(
            "ERROR: gui.h does not contain resources/theme.h"
        )

    h = h.replace(
        marker,
        marker + '\n#include "resources/imageset.h"',
        1,
    )

# Remove ALL previous cursor declarations.
#
# This catches both:
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
        stripped,
    ):
        continue

    if re.fullmatch(
        r"bool\s+mSoftwareCursorVisible\s*=\s*true\s*;",
        stripped,
    ):
        continue

    lines.append(line)

h = "\n".join(lines) + "\n"

# Insert exactly one cursor declaration.

cursor_member = re.compile(
    r"(?m)^(\s*)"
    r"Cursor\s+mCursorType\s*="
    r"\s*Cursor::Pointer\s*;"
)

match = cursor_member.search(h)

if not match:
    raise SystemExit(
        "ERROR: mCursorType declaration not found"
    )

indent = match.group(1)

replacement = (
    f"{indent}ResourceRef<ImageSet> mSoftwareCursor;\n"
    f"{indent}bool mSoftwareCursorVisible = true;\n"
    f"{indent}Cursor mCursorType = Cursor::Pointer;"
)

h = cursor_member.sub(
    replacement,
    h,
    count=1
)

header.write_text(
    h,
    encoding="utf-8"
)

# ============================================================
# gui.cpp
# ============================================================

# Remove software-cursor blocks left by previous attempts.

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

# Mana normally enables the SDL hardware cursor after movement.
# R36S needs the hardware cursor disabled because Mana renders
# its own software cursor.

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);",
)

# ============================================================
# Constructor
# ============================================================

init_marker = (
    "    setUseCustomCursor(config.customCursor);"
)

if (
    "mSoftwareCursor = "
    "ResourceManager::getInstance()->getImageSet("
    not in c
):

    if init_marker not in c:
        raise SystemExit(
            "ERROR: Gui constructor cursor "
            "initialization marker not found"
        )

    init_block = '''    setUseCustomCursor(config.customCursor);

    // R36S / PortMaster software cursor.
    // GPTOKEYB supplies mouse movement; Mana renders the cursor
    // directly into the SDL frame.
    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);'''

    c = c.replace(
        init_marker,
        init_block,
        1
    )

# ============================================================
# Replace a complete C++ function safely.
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
            f"ERROR: function not found: {signature}"
        )

    brace = text.find(
        "{",
        match.start()
    )

    if brace < 0:
        raise SystemExit(
            f"ERROR: opening brace not found: {signature}"
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
            f"ERROR: closing brace not found: {signature}"
        )

    return (
        text[:match.start()]
        + replacement
        + text[end:]
    )

# ============================================================
# Gui::draw()
#
# IMPORTANT:
# Cursor uses drawImage().
#
# There is NO global drawRescaledImage() validation because
# Mana legitimately uses drawRescaledImage() elsewhere.
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

    // Software cursor for PortMaster/R36S.
    //
    // drawImage() is intentional.
    // The cursor image is already 40x40.
    // Mana's original cursor hotspot is 15x17.

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
    new_draw,
)

# ============================================================
# Gui::keyPressed()
#
# SELECT -> F12
#
# F12 ONLY toggles the visible cursor.
# It does not disable mouse input.
# ============================================================

new_key_pressed = r'''void Gui::keyPressed(gcn::KeyEvent &event)
{
    // SELECT is mapped to F12 by the PortMaster controller config.
    // Outside text-entry mode, F12 only toggles the cursor image.

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
    new_key_pressed,
)

# Never allow Mana's mouse-movement handler to enable
# the hardware SDL cursor.

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);",
)

source.write_text(
    c,
    encoding="utf-8"
)

# ============================================================
# VALIDATION
# ============================================================

h = header.read_text(
    encoding="utf-8"
)

c = source.read_text(
    encoding="utf-8"
)

def exactly(
    text,
    needle,
    expected,
    label
):

    actual = text.count(
        needle
    )

    if actual != expected:

        raise SystemExit(
            f"ERROR: {label}: "
            f"expected {expected}, got {actual}"
        )

exactly(
    h,
    "ResourceRef<ImageSet> mSoftwareCursor;",
    1,
    "mSoftwareCursor declaration",
)

exactly(
    h,
    "bool mSoftwareCursorVisible = true;",
    1,
    "mSoftwareCursorVisible declaration",
)

exactly(
    c,
    "mSoftwareCursor =\n"
    "        ResourceManager::getInstance()->getImageSet(",
    1,
    "software cursor initialization",
)

exactly(
    c,
    "Key::F12",
    1,
    "F12 handler",
)

exactly(
    c,
    "mSoftwareCursorVisible = "
    "!mSoftwareCursorVisible;",
    1,
    "cursor toggle",
)

exactly(
    c,
    "mSoftwareCursor->get(0)",
    1,
    "cursor frame draw",
)

if "SDL_ShowCursor(SDL_ENABLE);" in c:

    raise SystemExit(
        "ERROR: SDL_ShowCursor(SDL_ENABLE) remains"
    )

draw_start = c.find(
    "void Gui::draw()"
)

draw_end = c.find(
    "\nvoid Gui::event",
    draw_start
)

if (
    draw_start < 0
    or draw_end < 0
):

    raise SystemExit(
        "ERROR: cannot isolate patched Gui::draw()"
    )

draw_block = c[
    draw_start:draw_end
]

if "graphics->drawImage(" not in draw_block:

    raise SystemExit(
        "ERROR: software cursor is not "
        "rendered with drawImage()"
    )

if "drawRescaledImage(" in draw_block:

    raise SystemExit(
        "ERROR: software cursor block "
        "uses drawRescaledImage()"
    )

print(
    "software cursor patch validation: OK"
)
PY

if [ ! -f "$SRC/data/graphics/gui/mouse.png" ]; then
    echo "ERROR: Mana source does not contain:"
    echo "data/graphics/gui/mouse.png"
    exit 5
fi

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

echo "=== Building Mana ==="

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"

echo "=== Installing Mana ==="

cmake \
    --install "$BUILD"

BIN="$(
    find "$INSTALL" \
        -type f \
        -name mana \
        -perm -111 \
        -print \
        -quit \
    || true
)"

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

if [
    -z "$BIN"
] || [
    ! -x "$BIN"
]; then

    echo "ERROR: Mana executable was not produced."

    find \
        "$INSTALL" \
        -maxdepth 6 \
        -type f \
        -print \
        || true

    exit 6
fi

echo "=== Creating PortMaster package ==="

mkdir -p "$PORT/mana"

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

if [
    ! -f \
    "$PORT/mana/data/graphics/gui/mouse.png"
]; then

    echo "ERROR: mouse.png missing from final package."

    exit 7
fi

# ============================================================
# Legacy GPTOKEYB mapping
#
# This is the exact known-working Mana controller mapping,
# with SELECT/back changed to F12 so SELECT only toggles the
# software cursor.
# ============================================================

cat > "$PORT/mana/mana.gptk" <<'GPTK'
# Mana 0.8.0 R36S controls
back = f12
start = enter
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
# GPTOKEYB2 FSM configuration
#
# Mouse is ALWAYS active.
#
# SELECT/back:
#     normal mode -> F12 -> cursor visibility toggle
#
# START:
#     Enter + temporary START state
#
# START + DOWN:
#     push text_input state
#
# text_input:
#     D-PAD UP       previous letter
#     D-PAD DOWN     next letter
#     D-PAD RIGHT    add/select character
#     D-PAD LEFT     backspace
#     A              Enter
#     START          Enter/confirm
#     SELECT         Escape + close/cancel
#
# The extended charset supplies letters, numbers and symbols.
# ============================================================

cat > "$PORT/mana/mana.controls.ini" <<'GPTK2'
[config]
repeat_delay = 500
repeat_rate = 60
deadzone_triggers = 3000
mouse_scale = 8192
mouse_delay = 16

[controls]
overlay = clear

back = f12

start = "enter" hold_state hotkey_start

a = "space"
b = "esc"
x = "z"
y = "x"

l1 = "shift"
l2 = "home"
l3 = "mouse_right"

r1 = "ctrl"
r2 = "end"
r3 = "mouse_left"

up = "up"
down = "down"
left = "left"
right = "right"

left_analog_up = "up"
left_analog_down = "down"
left_analog_left = "left"
left_analog_right = "right"

right_analog_up = "mouse_movement_up"
right_analog_down = "mouse_movement_down"
right_analog_left = "mouse_movement_left"
right_analog_right = "mouse_movement_right"

[controls:hotkey_start]
overlay = parent
down = push_state text_input

[controls:text_input]
overlay = parent
charset = extended

up = prev_letter
down = next_letter
right = add_letter
left = "backspace"

a = "enter"
start = "enter"
back = "esc" pop_state
b = "backspace"
GPTK2

# ============================================================
# PortMaster launcher
# ============================================================

cat > "$PORT/Mana.sh" <<'LAUNCHER'
#!/bin/bash

set -u

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/PortMaster/" ]; then
    controlfolder="/PortMaster"

elif [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"

elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"

elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
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

get_controls

GAMEDIR="/$directory/ports/mana"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1

LOGFILE="$GAMEDIR/log.txt"

: > "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo " Mana 0.8.0 / R36S / PortMaster"
echo "========================================"

echo "Architecture: ${DEVICE_ARCH:-unknown}"
echo "Game directory: $GAMEDIR"

if [ "${DEVICE_ARCH:-}" != "aarch64" ]; then

    echo "ERROR: this port requires aarch64."

    pm_finish

    exit 1
fi

GAME="$GAMEDIR/mana/mana.aarch64"
GAMEDATA="$GAMEDIR/mana/data"
GAMEROOT="$GAMEDIR/mana"

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

export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"

export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"

if [ -n "${LD_LIBRARY_PATH:-}" ]; then

    export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"

else

    export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}"

fi

cd "$GAMEROOT" || exit 1

pm_platform_helper "$GAME"

GPTOPID=""

# Prefer GPTOKEYB2 because the R36S text-entry configuration
# uses its state-machine controls.

if [ -n "${GPTOKEYB2:-}" ]; then

    echo "Starting GPTOKEYB2"

    echo "Config:"
    echo "$GAMEROOT/mana.controls.ini"

    $GPTOKEYB2 \
        "mana.aarch64" \
        -c "$GAMEROOT/mana.controls.ini" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    echo "Starting legacy GPTOKEYB"

    echo "Config:"
    echo "$GAMEROOT/mana.gptk"

    $GPTOKEYB \
        "mana.aarch64" \
        -c "$GAMEROOT/mana.gptk" &

    GPTOPID=$!

else

    echo "ERROR: neither GPTOKEYB2 nor GPTOKEYB is available."

    pm_finish

    exit 1
fi

echo "Executable: $GAME"
echo "Data: $GAMEDATA"

echo "Mouse: ALWAYS ACTIVE"
echo "Right analog: mouse movement"
echo "R3: left mouse button"
echo "L3: right mouse button"
echo "SELECT: cursor visibility toggle"
echo "START + DOWN: virtual text input (GPTOKEYB2)"

echo

"$GAME" \
    --data "$GAMEDATA" \
    --localdata-dir "$CONFDIR"

RET=$?

echo "Mana exited with code $RET"

if [ -n "$GPTOPID" ]; then

    kill "$GPTOPID" \
        2>/dev/null \
        || true

fi

pm_finish

exit "$RET"
LAUNCHER

chmod +x "$PORT/Mana.sh"

# ============================================================
# PortMaster metadata
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

echo "=== Final package validation ==="

test -f "$PORT/Mana.sh"
test -s "$PORT/Mana.sh"

test -f "$PORT/mana/mana.aarch64"
test -x "$PORT/mana/mana.aarch64"

test -f "$PORT/mana/mana.gptk"
test -f "$PORT/mana/mana.controls.ini"

test -f \
    "$PORT/mana/data/graphics/gui/mouse.png"

test -f "$PORT/port.json"
test -f "$PORT/gameinfo.xml"

# Legacy mapping validation.

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
    '^r3 = mouse_left$' \
    "$PORT/mana/mana.gptk"

grep -q \
    '^l3 = mouse_right$' \
    "$PORT/mana/mana.gptk"

# GPTOKEYB2 FSM validation.

grep -q \
    '^start = "enter" hold_state hotkey_start$' \
    "$PORT/mana/mana.controls.ini"

grep -q \
    '^down = push_state text_input$' \
    "$PORT/mana/mana.controls.ini"

grep -q \
    '^charset = extended$' \
    "$PORT/mana/mana.controls.ini"

grep -q \
    '^back = "esc" pop_state$' \
    "$PORT/mana/mana.controls.ini"

# ============================================================
# ELF validation
# ============================================================

file "$PORT/mana/mana.aarch64"

file "$PORT/mana/mana.aarch64" |
    grep -qi 'aarch64' || {

    echo "ERROR: built binary is not AArch64."

    exit 8
}

# The official PortMaster AArch64 builder should produce a binary
# compatible with the older R36S-era glibc.
#
# Reject newer glibc requirements.

if readelf \
    --version-info \
    "$PORT/mana/mana.aarch64" \
    2>/dev/null |
    grep -Eq \
        'GLIBC_2\.(3[2-9]|[4-9][0-9])'; then

    echo "ERROR: binary requires a newer glibc than the R36S target."

    readelf \
        --version-info \
        "$PORT/mana/mana.aarch64" \
        2>/dev/null |
        grep -o \
            'GLIBC_[0-9][0-9.]*' |
        sort -Vu || true

    exit 9
fi

# ============================================================
# Create final ZIP
# ============================================================

PACKAGE="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

rm -f "$PACKAGE"

(
    cd "$PORT"

    zip \
        -9qr \
        "$PACKAGE" \
        .
)

unzip \
    -tq \
    "$PACKAGE"

# ============================================================
# Diagnostics
# ============================================================

{
    echo "=== FILE ==="

    file \
        "$PORT/mana/mana.aarch64"

    echo
    echo "=== GLIBC ==="

    readelf \
        --version-info \
        "$PORT/mana/mana.aarch64" \
        2>/dev/null |
        grep -o \
            'GLIBC_[0-9][0-9.]*' |
        sort -Vu || true

    echo
    echo "=== NEEDED ==="

    readelf \
        -d \
        "$PORT/mana/mana.aarch64" \
        2>/dev/null |
        grep NEEDED || true

    echo
    echo "=== RPATH/RUNPATH ==="

    readelf \
        -d \
        "$PORT/mana/mana.aarch64" \
        2>/dev/null |
        grep -E \
            'RPATH|RUNPATH' || true

    echo
    echo "=== GPTK LEGACY ==="

    cat \
        "$PORT/mana/mana.gptk"

    echo
    echo "=== GPTOKEYB2 ==="

    cat \
        "$PORT/mana/mana.controls.ini"

    echo
    echo "=== CURSOR SOURCE ==="

    grep -n -E \
        'mSoftwareCursor|mSoftwareCursorVisible|Key::F12|SDL_ShowCursor' \
        "$SRC/src/gui/gui.h" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo
    echo "=== PACKAGE ==="

    unzip \
        -l \
        "$PACKAGE"

} > "$DIST/diagnostics.txt"

echo

echo "============================================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "============================================================"

echo "ZIP: $PACKAGE"

ls -lh "$PACKAGE"
