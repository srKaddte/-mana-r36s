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

echo "Source archive:"
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
# SDL2_TTF CMAKE
# ============================================================

echo
echo "=== Patching SDL2_ttf minimum version ==="

python3 - "$SRC" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])

changed_files = []

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
    ]

    for old, new in replacements:
        text = text.replace(old, new)

    if text != original:
        path.write_text(text)
        changed_files.append(str(path))

if changed_files:
    print("SDL2_ttf requirement patched in:")
    for item in changed_files:
        print("  " + item)
else:
    print("No SDL2_ttf 2.0.18 CMake requirement needed patching.")

print()
print("CMakeLists.txt files checked:")

for path in src.rglob("CMakeLists.txt"):
    print("  " + str(path))
PY

echo
echo "=== Verifying SDL2_ttf requirement ==="

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
# SDL2_TTF SOURCE
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
from pathlib import Path

path = Path(sys.argv[1])

text = path.read_text()

old = text

text = text.replace(
    "TTF_SetFontSize(font->mFont, font->mPointSize * mScale);",
    "/* SDL_ttf 2.0.15 compatibility: TTF_SetFontSize disabled. */"
)

text = text.replace(
    "TTF_SetFontSize(font->mFontOutline, font->mPointSize * mScale);",
    "/* SDL_ttf 2.0.15 compatibility: TTF_SetFontSize disabled. */"
)

if text != old:
    path.write_text(text)
    print("TTF_SetFontSize calls patched.")
else:
    print("TTF_SetFontSize already patched or absent.")
PY

if grep -q "TTF_SetFontSize" "$TTF_CPP"; then
    echo
    echo "ERROR: TTF_SetFontSize is still present."
    grep -n "TTF_SetFontSize" "$TTF_CPP"
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
echo "=== Applying R36S software cursor patch ==="

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

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys
import re
from pathlib import Path

header_path = Path(sys.argv[1])
cpp_path = Path(sys.argv[2])

header = header_path.read_text()
cpp = cpp_path.read_text()

# ============================================================
# GUI.H
# ============================================================

print("Checking gui.h...")

# Include ImageSet only if missing.
if '#include "resources/imageset.h"' not in header:

    anchor = '#include "resources/theme.h"'

    if anchor in header:
        header = header.replace(
            anchor,
            anchor + '\n#include "resources/imageset.h"',
            1
        )

        print("Added resources/imageset.h")

# ------------------------------------------------------------
# IMPORTANT:
# The source archive ALREADY contains mSoftwareCursor.
# Do NOT add another ResourceRef<ImageSet>.
# ------------------------------------------------------------

cursor_decl = 'ResourceRef<ImageSet> mSoftwareCursor;'
visible_decl = 'bool mSoftwareCursorVisible = true;'

cursor_count = header.count(cursor_decl)

print(
    "Existing mSoftwareCursor declarations:",
    cursor_count
)

# Remove accidental duplicate declarations.
if cursor_count > 1:

    first = True
    lines = []

    for line in header.splitlines(True):

        if cursor_decl in line:

            if first:
                lines.append(line)
                first = False
            else:
                print("Removing duplicate mSoftwareCursor declaration.")
                continue

        else:
            lines.append(line)

    header = ''.join(lines)

# Add visibility flag if missing.
if visible_decl not in header:

    if cursor_decl not in header:
        raise SystemExit(
            "ERROR: mSoftwareCursor declaration not found."
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
# GUI.CPP
# ============================================================

print()
print("Checking gui.cpp...")

# ------------------------------------------------------------
# SOFTWARE CURSOR INITIALIZATION
# ------------------------------------------------------------

init_marker = 'mSoftwareCursor = ResourceManager::getInstance()->getImageSet'

if init_marker in cpp:

    print("Software cursor initialization already exists.")

else:

    # Find setInput(guiInput) and insert after it.
    anchor = '''    guiInput = new SDLInput;
    setInput(guiInput);
'''

    if anchor in cpp:

        replacement = '''    guiInput = new SDLInput;
    setInput(guiInput);

    // R36S / PortMaster software cursor.
    // GPTK supplies mouse events and Mana renders the pointer.
    mSoftwareCursor = ResourceManager::getInstance()->getImageSet(
        mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
'''

        cpp = cpp.replace(
            anchor,
            replacement,
            1
        )

        print("Added software cursor initialization.")

    else:

        # Alternative: insert immediately after constructor start
        # if the normal anchor is not found.
        raise SystemExit(
            "ERROR: Could not locate Gui constructor input initialization."
        )

# ------------------------------------------------------------
# GUI::DRAW
# ------------------------------------------------------------

print()
print("Patching Gui::draw()...")

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

# The existing source already draws the software cursor.
# We only add the visibility condition.

if 'mSoftwareCursorVisible' in draw:

    print("Gui::draw() visibility condition already exists.")

else:

    cursor_condition = (
        'if (mSoftwareCursor && mSoftwareCursor->size() > 0)'
    )

    if cursor_condition in draw:

        draw = draw.replace(
            cursor_condition,
            'if (mSoftwareCursorVisible && '
            'mSoftwareCursor && '
            'mSoftwareCursor->size() > 0)',
            1
        )

        cpp = (
            cpp[:draw_match.start()]
            + draw
            + cpp[draw_match.end():]
        )

        print("Added cursor visibility condition.")

    else:

        # If the source has no cursor draw yet, inject one
        # before the end of Gui::draw().
        if 'auto *graphics = static_cast<Graphics*>(mGraphics);' not in draw:
            raise SystemExit(
                "ERROR: Unexpected Gui::draw() structure."
            )

        new_draw = draw.rstrip()

        pos = new_draw.rfind('}')

        cursor_code = '''
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
'''

        new_draw = (
            new_draw[:pos]
            + cursor_code
            + new_draw[pos:]
        )

        cpp = (
            cpp[:draw_match.start()]
            + new_draw
            + cpp[draw_match.end():]
        )

        print("Added software cursor drawing.")

# ------------------------------------------------------------
# GUI::KEYPRESSED
# ------------------------------------------------------------

print()
print("Patching Gui::keyPressed()...")

key_pattern = re.compile(
    r'void\s+Gui::keyPressed\s*\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{.*?\n\}',
    re.DOTALL
)

key_match = key_pattern.search(cpp)

if not key_match:
    raise SystemExit(
        "ERROR: Gui::keyPressed() function not found."
    )

key_func = key_match.group(0)

toggle_code = '''    // SELECT is mapped to F12 by mana.gptk.
    // F12 toggles ONLY cursor visibility.
    // All other controller controls remain active.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }

'''

if 'mSoftwareCursorVisible = !mSoftwareCursorVisible' in key_func:

    print("F12 cursor toggle already exists.")

else:

    marker = '{\n'

    pos = key_func.find(marker)

    if pos == -1:
        raise SystemExit(
            "ERROR: Could not patch Gui::keyPressed()."
        )

    pos += len(marker)

    key_func = (
        key_func[:pos]
        + toggle_code
        + key_func[pos:]
    )

    cpp = (
        cpp[:key_match.start()]
        + key_func
        + cpp[key_match.end():]
    )

    print("Added F12 cursor toggle.")

# ------------------------------------------------------------
# HARDWARE CURSOR
# ------------------------------------------------------------

print()
print("Disabling SDL hardware cursor...")

cpp = cpp.replace(
    '''    // Make sure the cursor is visible
    SDL_ShowCursor(SDL_ENABLE);
''',
    '''    // Hardware cursor remains disabled.
    // Mana renders the software cursor.
'''
)

# Also handle plain occurrences.
cpp = cpp.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

cpp_path.write_text(cpp)

print()
print("R36S software cursor patch completed.")
PY

# ============================================================
# CURSOR VALIDATION
# ============================================================

echo
echo "=== Checking R36S software cursor ==="

if ! grep -q \
    'ResourceRef<ImageSet> mSoftwareCursor;' \
    "$GUI_H"; then

    echo "ERROR: mSoftwareCursor declaration missing."
    exit 10

fi

if ! grep -q \
    'bool mSoftwareCursorVisible = true;' \
    "$GUI_H"; then

    echo "ERROR: mSoftwareCursorVisible declaration missing."
    exit 11

fi

if ! grep -q \
    'mSoftwareCursor = ResourceManager::getInstance()->getImageSet' \
    "$GUI_CPP"; then

    echo "ERROR: software cursor initialization missing."
    exit 12

fi

if ! grep -q \
    'mSoftwareCursorVisible' \
    "$GUI_CPP"; then

    echo "ERROR: software cursor visibility code missing."
    exit 13

fi

if ! grep -q \
    'mSoftwareCursorVisible = !mSoftwareCursorVisible' \
    "$GUI_CPP"; then

    echo "ERROR: F12 cursor toggle missing."
    exit 14

fi

if ! grep -q \
    'SDL_ShowCursor(SDL_DISABLE' \
    "$GUI_CPP"; then

    echo "ERROR: SDL hardware cursor disable missing."
    exit 15

fi

# Make absolutely sure the header has only one declaration.
COUNT="$(
    grep -c \
        'ResourceRef<ImageSet> mSoftwareCursor;' \
        "$GUI_H"
)"

if [ "$COUNT" -ne 1 ]; then

    echo
    echo "ERROR: mSoftwareCursor declaration count is $COUNT."
    echo "Expected exactly 1."

    grep -n \
        'mSoftwareCursor' \
        "$GUI_H"

    exit 16

fi

echo "mSoftwareCursor declaration: OK"
echo "mSoftwareCursorVisible: OK"
echo "Software cursor initialization: OK"
echo "Software cursor drawing: OK"
echo "F12 visibility toggle: OK"
echo "Hardware cursor disabled: OK"

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
# FIND BINARY
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

    echo
    echo "Executables found:"

    find "$BUILD" \
        -type f \
        -perm -111 \
        -print |
        head -100

    exit 17

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
# EXECUTABLE
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

    exit 18

fi

cp -a \
    "$SRC/data" \
    "$PORT/mana/data"

# ============================================================
# CURSOR IMAGE
# ============================================================

if [ ! -f \
    "$PORT/mana/data/graphics/gui/mouse.png" ]; then

    echo "ERROR: mouse.png not found."

    echo "Expected:"
    echo "$PORT/mana/data/graphics/gui/mouse.png"

    exit 19

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

if ! file "$ELF" |
    grep -qi 'AArch64\|ARM aarch64'; then

    echo "ERROR: generated binary is not AArch64."

    file "$ELF"

    exit 20

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

    exit 21

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
