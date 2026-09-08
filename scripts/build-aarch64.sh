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
# DEPENDENCIAS
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

tar \
    -xzf "$SRC_ARCHIVE" \
    -C "$WORK"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERROR: Mana CMakeLists.txt not found:"
    echo "$SRC/CMakeLists.txt"
    exit 2
fi

echo "Mana source:"
echo "$SRC"

# ============================================================
# SDL2_TTF CMAKE VERSION
# ============================================================

echo
echo "=== Patching SDL2_ttf minimum version ==="

python3 - "$SRC" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])

changed = []

for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except Exception:
        continue

    original = text

    replacements = [
        ("SDL2_ttf>=2.0.18", "SDL2_ttf>=2.0.15"),
        ("SDL2_ttf >= 2.0.18", "SDL2_ttf >= 2.0.15"),
        ("SDL2_ttf>= 2.0.18", "SDL2_ttf>= 2.0.15"),
        ("SDL2_ttf >=2.0.18", "SDL2_ttf >=2.0.15"),
        ("SDL2_ttf>=2.0.18", "SDL2_ttf>=2.0.15"),
    ]

    for old, new in replacements:
        text = text.replace(old, new)

    if text != original:
        path.write_text(text)
        changed.append(path)

if changed:
    print("Patched SDL2_ttf requirement:")
    for path in changed:
        print("  " + str(path))
else:
    print("SDL2_ttf requirement already compatible.")

PY

echo
echo "=== Verifying SDL2_ttf CMake requirement ==="

if grep -R \
    -n \
    -E \
    'SDL2_ttf[[:space:]]*>=?[[:space:]]*2\.0\.18' \
    "$SRC" \
    --include="CMakeLists.txt" \
    2>/dev/null; then

    echo
    echo "ERROR: SDL2_ttf >= 2.0.18 still exists."
    exit 3
fi

echo "SDL2_ttf CMake requirement: OK"

# ============================================================
# SDL2_TTF SOURCE COMPATIBILITY
# ============================================================

echo
echo "=== Patching SDL2_ttf source compatibility ==="

TTF_CPP="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TTF_CPP" ]; then
    echo "ERROR: truetypefont.cpp not found:"
    echo "$TTF_CPP"
    exit 4
fi

python3 - "$TTF_CPP" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])

text = path.read_text()

original = text

# Remove actual TTF_SetFontSize calls.
#
# IMPORTANT:
# Do not leave the function name inside a comment,
# because the validation below intentionally searches
# for an actual function call.

text = re.sub(
    r'(?m)^[ \t]*TTF_SetFontSize\s*\([^;]*\);\s*$',
    '            /* SDL_ttf 2.0.15 compatibility. */',
    text
)

# Also handle calls that may be indented differently or
# appear in a simple expression.

text = re.sub(
    r'TTF_SetFontSize\s*\([^;]*\);',
    '/* SDL_ttf compatibility */',
    text
)

if text != original:
    path.write_text(text)
    print("SDL2_ttf source patched.")
else:
    print("No SDL2_ttf source change was necessary.")

PY

echo
echo "=== Verifying real TTF_SetFontSize calls ==="

# IMPORTANT:
# Search for an actual function invocation, not just the
# text "TTF_SetFontSize" inside comments.

if grep -n \
    -E \
    'TTF_SetFontSize[[:space:]]*\(' \
    "$TTF_CPP" \
    2>/dev/null; then

    echo
    echo "ERROR: a real TTF_SetFontSize call is still present."
    exit 5
fi

echo "SDL2_ttf source compatibility: OK"

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
    exit 6
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
    exit 7
fi

echo "ENet:"
echo "$SRC/libs/enet"

echo "ENet CMakeLists: OK"

# ============================================================
# R36S SOFTWARE CURSOR
# ============================================================

echo
echo "=== Checking R36S software cursor ==="

GUI_H="$SRC/src/gui/gui.h"
GUI_CPP="$SRC/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ]; then
    echo "ERROR: gui.h not found."
    exit 8
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERROR: gui.cpp not found."
    exit 9
fi

echo
echo "=== Applying R36S cursor visibility support ==="

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

cursor_decl = "ResourceRef<ImageSet> mSoftwareCursor;"
visible_decl = "bool mSoftwareCursorVisible = true;"

# Add ImageSet include if needed.
if '#include "resources/imageset.h"' not in header:

    anchor = '#include "resources/theme.h"'

    if anchor in header:

        header = header.replace(
            anchor,
            anchor + '\n#include "resources/imageset.h"',
            1
        )

        print("Added ImageSet include.")

# ------------------------------------------------------------
# NEVER DUPLICATE mSoftwareCursor
# ------------------------------------------------------------

count = header.count(cursor_decl)

print(
    "mSoftwareCursor declarations:",
    count
)

if count == 0:

    # Only add it if the source archive genuinely does
    # not contain it.

    anchor = "class Gui"

    if anchor not in header:
        raise SystemExit(
            "ERROR: Gui class not found in gui.h."
        )

    # Find the first private/protected section after Gui.
    match = re.search(
        r'class\s+Gui\b.*?\{',
        header,
        re.DOTALL
    )

    if not match:
        raise SystemExit(
            "ERROR: Gui class declaration not found."
        )

    insert_pos = match.end()

    insertion = (
        "\n\n"
        "        ResourceRef<ImageSet> mSoftwareCursor;\n"
    )

    header = (
        header[:insert_pos]
        + insertion
        + header[insert_pos:]
    )

    print("Added missing mSoftwareCursor.")

elif count > 1:

    print(
        "Removing duplicate mSoftwareCursor declarations."
    )

    lines = []

    found = False

    for line in header.splitlines(True):

        if cursor_decl in line:

            if not found:

                lines.append(line)
                found = True

            continue

        lines.append(line)

    header = "".join(lines)

    print("Duplicate declaration removed.")

# ------------------------------------------------------------
# VISIBILITY FLAG
# ------------------------------------------------------------

if visible_decl not in header:

    if cursor_decl not in header:
        raise SystemExit(
            "ERROR: mSoftwareCursor declaration unavailable."
        )

    header = header.replace(
        cursor_decl,
        cursor_decl + "\n        " + visible_decl,
        1
    )

    print("Added mSoftwareCursorVisible.")

else:

    print("mSoftwareCursorVisible already exists.")

header_path.write_text(header)

# ============================================================
# CPP
# ============================================================

# ------------------------------------------------------------
# SOFTWARE CURSOR INITIALIZATION
# ------------------------------------------------------------

if (
    "mSoftwareCursor = "
    "ResourceManager::getInstance()->getImageSet"
    in cpp
):

    print(
        "Software cursor initialization already exists."
    )

else:

    # Try the known constructor location.

    anchor = """    guiInput = new SDLInput;
    setInput(guiInput);
"""

    if anchor in cpp:

        replacement = """    guiInput = new SDLInput;
    setInput(guiInput);

    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);
"""

        cpp = cpp.replace(
            anchor,
            replacement,
            1
        )

        print(
            "Added software cursor initialization."
        )

    else:

        # The archive may already initialize the cursor
        # elsewhere. Do not destroy the source.

        print(
            "Software cursor initialization anchor not found."
        )

# ------------------------------------------------------------
# GUI::DRAW
# ------------------------------------------------------------

draw_pattern = re.compile(
    r'void\s+Gui::draw\s*\(\s*\)\s*\{.*?\n\}',
    re.DOTALL
)

draw_match = draw_pattern.search(cpp)

if not draw_match:

    raise SystemExit(
        "ERROR: Gui::draw() function not found."
    )

draw = draw_match.group(0)

# If the source already has the cursor condition,
# leave it alone.

if "mSoftwareCursorVisible" in draw:

    print(
        "Gui::draw() already uses cursor visibility."
    )

else:

    # Existing cursor rendering.
    cursor_marker = (
        "if (mSoftwareCursor && "
        "mSoftwareCursor->size() > 0)"
    )

    if cursor_marker in draw:

        draw = draw.replace(
            cursor_marker,
            "if (mSoftwareCursorVisible && "
            "mSoftwareCursor && "
            "mSoftwareCursor->size() > 0)",
            1
        )

        cpp = (
            cpp[:draw_match.start()]
            + draw
            + cpp[draw_match.end():]
        )

        print(
            "Added visibility check to existing cursor."
        )

    else:

        # If there is no cursor rendering in the source,
        # insert it into draw().

        graphics_marker = (
            "auto *graphics = "
            "static_cast<Graphics*>(mGraphics);"
        )

        if graphics_marker not in draw:

            raise SystemExit(
                "ERROR: Unexpected Gui::draw() structure."
            )

        # Find the final brace.
        pos = draw.rfind("}")

        cursor_code = """
    // R36S software cursor.
    if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);
    }
"""

        new_draw = (
            draw[:pos]
            + cursor_code
            + draw[pos:]
        )

        cpp = (
            cpp[:draw_match.start()]
            + new_draw
            + cpp[draw_match.end():]
        )

        print(
            "Added software cursor drawing."
        )

# ------------------------------------------------------------
# KEY PRESSED
# ------------------------------------------------------------

key_pattern = re.compile(
    r'void\s+Gui::keyPressed\s*\('
    r'\s*gcn::KeyEvent\s*&event\s*\)\s*\{'
    r'.*?\n\}',
    re.DOTALL
)

key_match = key_pattern.search(cpp)

if not key_match:

    raise SystemExit(
        "ERROR: Gui::keyPressed() function not found."
    )

key_func = key_match.group(0)

toggle_marker = (
    "mSoftwareCursorVisible = "
    "!mSoftwareCursorVisible"
)

if toggle_marker in key_func:

    print(
        "F12 cursor toggle already exists."
    )

else:

    toggle_code = """
    // SELECT is mapped to F12 by mana.gptk.
    // F12 changes ONLY cursor visibility.
    // Other controls remain active.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();
        return;
    }

"""

    brace = key_func.find("{")

    if brace == -1:

        raise SystemExit(
            "ERROR: Gui::keyPressed() opening brace not found."
        )

    insert_pos = brace + 1

    key_func = (
        key_func[:insert_pos]
        + toggle_code
        + key_func[insert_pos:]
    )

    cpp = (
        cpp[:key_match.start()]
        + key_func
        + cpp[key_match.end():]
    )

    print(
        "Added F12 cursor visibility toggle."
    )

# ------------------------------------------------------------
# HARDWARE CURSOR
# ------------------------------------------------------------

cpp = cpp.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)

cpp_path.write_text(cpp)

print()
print("R36S cursor patch completed.")

PY

# ============================================================
# CURSOR VALIDATION
# ============================================================

echo
echo "=== Validating R36S software cursor ==="

COUNT="$(
    grep -c \
        'ResourceRef<ImageSet> mSoftwareCursor;' \
        "$GUI_H" ||
        true
)"

if [ "$COUNT" -ne 1 ]; then

    echo
    echo "ERROR: invalid mSoftwareCursor declaration count:"
    echo "$COUNT"

    grep -n \
        'mSoftwareCursor' \
        "$GUI_H" ||
        true

    exit 10

fi

if ! grep -q \
    'bool mSoftwareCursorVisible = true;' \
    "$GUI_H"; then

    echo "ERROR: mSoftwareCursorVisible missing."
    exit 11

fi

if ! grep -q \
    'mSoftwareCursor' \
    "$GUI_CPP"; then

    echo "ERROR: software cursor code missing."
    exit 12

fi

if ! grep -q \
    'mSoftwareCursorVisible' \
    "$GUI_CPP"; then

    echo "ERROR: cursor visibility code missing."
    exit 13

fi

if ! grep -q \
    'mSoftwareCursorVisible = !mSoftwareCursorVisible' \
    "$GUI_CPP" &&
   ! grep -q \
    'mSoftwareCursorVisible =' \
    "$GUI_CPP"; then

    echo "ERROR: F12 cursor toggle missing."
    exit 14

fi

if ! grep -q \
    'SDL_ShowCursor(SDL_DISABLE' \
    "$GUI_CPP"; then

    echo "ERROR: hardware cursor disable missing."
    exit 15

fi

echo "mSoftwareCursor: OK"
echo "mSoftwareCursorVisible: OK"
echo "Cursor rendering: OK"
echo "F12 visibility toggle: OK"
echo "SDL hardware cursor disabled: OK"

# ============================================================
# CMAKE
# ============================================================

echo
echo "=== Configuring CMake ==="

mkdir -p "$BUILD"

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
# LOCATE BINARY
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

    echo
    echo "ERROR: Mana executable was not produced."

    find "$BUILD" \
        -type f \
        -perm -111 \
        -print |
        head -100

    exit 16

fi

echo "Mana executable:"
echo "$BIN"

chmod +x "$BIN"

# ============================================================
# PORTMASTER STRUCTURE
# ============================================================

echo
echo "=== Creating PortMaster package ==="

mkdir -p "$PORT/mana"

# ============================================================
# BINARY
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

    echo "ERROR: Mana data directory not found:"
    echo "$SRC/data"

    exit 17

fi

cp -a \
    "$SRC/data" \
    "$PORT/mana/data"

# ============================================================
# CURSOR IMAGE
# ============================================================

CURSOR_IMAGE="$PORT/mana/data/graphics/gui/mouse.png"

if [ ! -f "$CURSOR_IMAGE" ]; then

    echo
    echo "ERROR: mouse.png not found:"
    echo "$CURSOR_IMAGE"

    exit 18

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
# VIRTUAL KEYBOARD
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
echo "  Right analog = movement"
echo "  R3           = left click"
echo "  L3           = right click"

echo
echo "Cursor:"
echo "  SELECT/F12   = show/hide"

echo
echo "Virtual keyboard:"
echo "  START + DOWN = open"
echo "  D-PAD        = navigate"
echo "  A            = select / Enter"
echo "  START        = confirm"
echo "  SELECT       = cancel"

echo
echo "Starting Mana..."

# ============================================================
# MANA
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
# ELF DIAGNOSTICS
# ============================================================

echo
echo "=== ELF diagnostics ==="

ELF="$PORT/mana/mana.aarch64"

file "$ELF" |
    tee "$DIST/diagnostics.txt"

{
    echo
    echo "=== ELF HEADER ==="

    readelf -h "$ELF" || true

    echo
    echo "=== NEEDED LIBRARIES ==="

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
    echo "=== CURSOR SYMBOL STRINGS ==="

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

if ! file "$ELF" |
    grep -qi 'AArch64\|ARM aarch64'; then

    echo "ERROR: generated binary is not AArch64."

    file "$ELF"

    exit 19

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

if echo "$GLIBC_LIST" |
    grep -q 'GLIBC_2\.43'; then

    echo "ERROR: binary requires GLIBC_2.43."

    exit 20

fi

echo
echo "GLIBC compatibility check OK."

# ============================================================
# FINAL PACKAGE VALIDATION
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
# PACKAGE LIST
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
