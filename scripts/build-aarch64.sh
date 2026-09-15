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

printf '\n============================================================\n'
printf ' MANA 0.8.0 - R36S / PortMaster / AArch64\n'
printf ' BUILD FINAL\n'
printf '============================================================\n\n'

rm -rf "$WORK" "$PORT" "$DIST"
mkdir -p "$WORK" "$DEPS" "$DIST"

[ -f "$SRC_ARCHIVE" ] || {
    echo "ERROR: source archive not found: $SRC_ARCHIVE"
    exit 1
}

echo "=== Extracting Mana source ==="

tar -xzf "$SRC_ARCHIVE" -C "$WORK"

[ -f "$SRC/CMakeLists.txt" ] || {
    echo "ERROR: Mana source not found at $SRC"
    exit 2
}

# ============================================================
# SDL2_ttf 2.0.15 compatibility
# ============================================================

echo "=== Patching SDL2_ttf requirement ==="

python3 - "$SRC" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])

for p in src.rglob("CMakeLists.txt"):
    s = p.read_text()

    n = re.sub(
        r'SDL2_ttf\s*>=\s*2\.0\.18',
        'SDL2_ttf>=2.0.15',
        s
    )

    if n != s:
        p.write_text(n)
        print("Patched:", p)

for p in src.rglob("CMakeLists.txt"):
    s = p.read_text()

    if re.search(
        r'SDL2_ttf\s*>=\s*2\.0\.18',
        s
    ):
        raise SystemExit(
            f"ERROR: SDL2_ttf >= 2.0.18 remains in {p}"
        )

print("SDL2_ttf requirement OK")
PY


# ============================================================
# Remove unavailable TTF_SetFontSize calls, preserving the
# rest of TrueTypeFont::updateFontScale(). This is idempotent.
# ============================================================

echo "=== Patching TTF_SetFontSize ==="

python3 - "$SRC/src/gui/truetypefont.cpp" <<'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])

if not p.exists():
    raise SystemExit(
        "ERROR: truetypefont.cpp not found"
    )

s = p.read_text()

# Remove actual calls only.
# Do not replace the whole function.
s = re.sub(
    r'(?m)^[ \t]*TTF_SetFontSize\s*\([^;]*\);[ \t]*\n?',
    '',
    s
)

p.write_text(s)

if re.search(
    r'TTF_SetFontSize\s*\(',
    p.read_text()
):
    raise SystemExit(
        "ERROR: TTF_SetFontSize() still exists"
    )

print("TTF_SetFontSize calls removed")
PY


# ============================================================
# Software cursor patch.
#
# The cursor resource is ResourceRef<Image>.
#
# We render only the first 40x40 frame from the 320x80
# mouse.png cursor sheet.
# ============================================================

echo "=== Patching software cursor ==="

python3 - "$SRC/src/gui/gui.h" "$SRC/src/gui/gui.cpp" <<'PY'
import re
import sys
from pathlib import Path


h = Path(sys.argv[1])
cpp = Path(sys.argv[2])

hs = h.read_text()
cs = cpp.read_text()


# ============================================================
# gui.h
# ============================================================

# Remove the ImageSet include from the failed previous
# implementation.
#
# The current implementation uses Mana's existing Image resource.
hs = hs.replace(
    '#include "resources/imageset.h"\n',
    ''
)


# Explicitly include Image because mSoftwareCursor is
# ResourceRef<Image>.
if '#include "resources/image.h"' not in hs:

    marker = '#include "resources/theme.h"'

    if marker not in hs:
        raise SystemExit(
            'ERROR: resources/theme.h not found in gui.h'
        )

    hs = hs.replace(
        marker,
        marker + '\n\n#include "resources/image.h"',
        1
    )


# ============================================================
# Remove EVERY previous cursor declaration.
#
# This is the important fix.
#
# It handles:
#
# ResourceRef<Image> mSoftwareCursor;
#
# and:
#
# ResourceRef<ImageSet> mSoftwareCursor;
#
# so an old failed patch can never leave a duplicate.
# ============================================================

hs = re.sub(
    r'(?m)^[ \t]*ResourceRef\s*<\s*(?:Image|ImageSet)\s*>\s*'
    r'mSoftwareCursor\s*;[ \t]*\n?',
    '',
    hs
)


# Remove previous visibility declarations.
hs = re.sub(
    r'(?m)^[ \t]*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;[ \t]*\n?',
    '',
    hs
)


# ============================================================
# Insert exactly one Image cursor declaration.
# ============================================================

marker_re = (
    r'(?m)^(\s*)'
    r'int\s+mMouseY\s*=\s*0\s*;[ \t]*$'
)

if not re.search(
    marker_re,
    hs
):
    raise SystemExit(
        'ERROR: mMouseY member not found in gui.h'
    )


hs = re.sub(
    marker_re,
    r'\1int mMouseY = 0;\n'
    r'\1ResourceRef<Image> mSoftwareCursor;\n'
    r'\1bool mSoftwareCursorVisible = true;',
    hs,
    count=1
)

h.write_text(hs)


# ============================================================
# gui.cpp
# ============================================================

# Remove old software cursor initialization blocks from
# previous attempts.
cs = re.sub(
    r'(?s)\n\s*//.*?software cursor.*?\n\s*'
    r'mSoftwareCursor\s*=.*?;\s*\n\s*'
    r'SDL_ShowCursor\(SDL_DISABLE\);\s*\n',
    '\n',
    cs
)


# Never allow the SDL hardware cursor to become visible.
cs = cs.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)


# ============================================================
# Constructor initialization.
#
# mouse.png is a 320x80 cursor sheet.
#
# ResourceRef<Image> stores the entire sheet.
# drawImage() below selects the first 40x40 frame.
# ============================================================

init_marker = (
    '    setUseCustomCursor(config.customCursor);'
)

init_block = """    setUseCustomCursor(config.customCursor);

    // R36S/PortMaster software cursor.
    // GPTOKEYB supplies mouse movement; Mana draws the first 40x40
    // cursor frame directly from mouse.png inside the game frame.
    mSoftwareCursor = ResourceManager::getInstance()->getImage(
        mTheme->resolvePath("mouse.png"));
    SDL_ShowCursor(SDL_DISABLE);"""


if (
    'mSoftwareCursor = '
    'ResourceManager::getInstance()->getImage('
    not in cs
):

    if init_marker not in cs:
        raise SystemExit(
            'ERROR: setUseCustomCursor(config.customCursor) '
            'not found'
        )

    cs = cs.replace(
        init_marker,
        init_block,
        1
    )


# ============================================================
# Generic C++ function replacement helper.
# ============================================================

def replace_function(
    source,
    signature_pattern,
    new_body
):

    m = re.search(
        signature_pattern,
        source
    )

    if not m:
        raise SystemExit(
            'ERROR: function not found: '
            + signature_pattern
        )

    brace = source.find(
        '{',
        m.start()
    )

    if brace < 0:
        raise SystemExit(
            'ERROR: opening brace not found'
        )

    depth = 0
    end = None

    for i in range(
        brace,
        len(source)
    ):

        if source[i] == '{':
            depth += 1

        elif source[i] == '}':
            depth -= 1

            if depth == 0:
                end = i + 1
                break

    if end is None:
        raise SystemExit(
            'ERROR: function end not found'
        )

    return (
        source[:m.start()]
        + new_body
        + source[end:]
    )


# ============================================================
# Gui::draw()
#
# IMPORTANT:
#
# drawImage(image, srcX, srcY, dstX, dstY, width, height)
#
# is used instead of drawRescaledImage().
#
# This draws only the first 40x40 cursor frame.
# ============================================================

new_draw = r'''void Gui::draw()
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

        mActiveDrag->draw(
            graphics,
            mMouseX,
            mMouseY
        );

        graphics->popClipArea();
    }

    // mouse.png is a 320x80 sheet.
    // Draw only its first 40x40 frame.
    if (mSoftwareCursorVisible && mSoftwareCursor)
    {
        graphics->drawImage(
            mSoftwareCursor.get(),
            0,
            0,
            mMouseX - 15,
            mMouseY - 17,
            40,
            40
        );
    }
}'''

cs = replace_function(
    cs,
    r'void\s+Gui::draw\s*\(\s*\)\s*\{',
    new_draw
)


# ============================================================
# keyPressed()
#
# SELECT -> F12
# F12 ONLY hides/shows cursor.
#
# Mouse movement remains active.
# ============================================================

new_key = r'''void Gui::keyPressed(gcn::KeyEvent &event)
{
    // SELECT is mapped to F12 by mana.gptk.
    // F12 changes ONLY cursor visibility;
    // mouse input stays active.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

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

cs = replace_function(
    cs,
    r'void\s+Gui::keyPressed\s*\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{',
    new_key
)


# Make absolutely sure the hardware cursor is never
# re-enabled by another mouse movement function.
cs = cs.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

cpp.write_text(cs)


# ============================================================
# HARD VALIDATION BEFORE COMPILING
# ============================================================

hfinal = h.read_text()
cfinal = cpp.read_text()


# Exactly one ResourceRef<Image>.
cursor_count = len(
    re.findall(
        r'\bResourceRef\s*<\s*Image\s*>\s+'
        r'mSoftwareCursor\s*;',
        hfinal
    )
)


# Absolutely zero ImageSet cursor declarations.
image_set_count = len(
    re.findall(
        r'\bResourceRef\s*<\s*ImageSet\s*>\s+'
        r'mSoftwareCursor\s*;',
        hfinal
    )
)


# Exactly one visibility flag.
visible_count = len(
    re.findall(
        r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
        hfinal
    )
)


if cursor_count != 1:
    raise SystemExit(
        'ERROR: mSoftwareCursor Image declaration '
        f'count = {cursor_count}; expected 1'
    )


if image_set_count != 0:
    raise SystemExit(
        'ERROR: ImageSet mSoftwareCursor declaration '
        f'count = {image_set_count}; expected 0'
    )


if visible_count != 1:
    raise SystemExit(
        'ERROR: mSoftwareCursorVisible declaration '
        f'count = {visible_count}; expected 1'
    )


# Exactly one initialization.
if cfinal.count(
    'mSoftwareCursor = '
    'ResourceManager::getInstance()->getImage('
) != 1:

    raise SystemExit(
        'ERROR: software cursor Image initialization '
        'count != 1'
    )


# Exactly one F12 reference.
if cfinal.count(
    'Key::F12'
) != 1:

    raise SystemExit(
        'ERROR: Key::F12 count != 1'
    )


# Exactly one F12 toggle.
toggle_pattern = re.compile(
    r'mSoftwareCursorVisible\s*=\s*!\s*'
    r'mSoftwareCursorVisible\s*;'
)

if len(
    toggle_pattern.findall(cfinal)
) != 1:

    raise SystemExit(
        'ERROR: F12 cursor toggle count != 1'
    )


# Exactly one cursor draw.
if cfinal.count(
    'mSoftwareCursor.get()'
) != 1:

    raise SystemExit(
        'ERROR: cursor draw count != 1'
    )


# Hardware SDL cursor must never be explicitly enabled.
if 'SDL_ShowCursor(SDL_ENABLE);' in cfinal:
    raise SystemExit(
        'ERROR: SDL_ShowCursor(SDL_ENABLE) remains'
    )


# ============================================================
# Validate only the cursor portion of Gui::draw().
# ============================================================

draw_start = cfinal.find(
    'void Gui::draw()'
)

draw_end = cfinal.find(
    '\nvoid Gui::event',
    draw_start
)

draw_text = cfinal[
    draw_start:
    draw_end
    if draw_end > draw_start
    else len(cfinal)
]


if (
    'graphics->drawImage(' not in draw_text
    or
    'mSoftwareCursor.get()' not in draw_text
):

    raise SystemExit(
        'ERROR: cursor drawImage validation failed'
    )


if 'drawRescaledImage' in draw_text:

    raise SystemExit(
        'ERROR: cursor block uses '
        'drawRescaledImage()'
    )


print(
    'Software cursor patch validation: OK'
)

print(
    'mSoftwareCursor Image declarations:',
    cursor_count
)

print(
    'mSoftwareCursor ImageSet declarations:',
    image_set_count
)

print(
    'mSoftwareCursorVisible declarations:',
    visible_count
)

PY


# ============================================================
# Dependencies
# ============================================================

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
# Bundled libraries expected by Mana's CMakeLists.txt
# ============================================================

echo "=== Getting Guichan 0.8.3 ==="

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

[ -f "$SRC/libs/guichan/CMakeLists.txt" ] || {
    echo "ERROR: Guichan missing"
    exit 4
}


echo "=== Getting ENet 1.3.18 ==="

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

[ -f "$SRC/libs/enet/CMakeLists.txt" ] || {
    echo "ERROR: ENet missing"
    exit 5
}


# ============================================================
# Configure / build
# ============================================================

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


echo "=== Building Mana ==="

cmake \
  --build "$BUILD" \
  --parallel "$(nproc)"


BIN="$BUILD/src/mana"

if [ ! -x "$BIN" ]; then

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


[ -n "$BIN" ] && [ -x "$BIN" ] || {
    echo "ERROR: Mana executable was not produced"
    exit 6
}


# ============================================================
# PortMaster package
# ============================================================

echo "=== Building PortMaster package ==="

mkdir -p "$PORT/mana"


# ============================================================
# Mana.sh
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

source "$controlfolder/control.txt"

[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] &&
    source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/$directory/ports/mana"

CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1

: > "$GAMEDIR/log.txt"

exec > >(tee -a "$GAMEDIR/log.txt") 2>&1

echo "Mana 0.8.0 - R36S"
echo "Architecture: ${DEVICE_ARCH:-unknown}"
echo "Mouse: right analog / R3 left click / L3 right click"
echo "Cursor: SELECT/F12 show-hide"
echo "Virtual keyboard: START + D-PAD DOWN"

GAME="$GAMEDIR/mana/mana.aarch64"

[ -f "$GAME" ] || {
    echo "ERROR: $GAME not found"
    exit 1
}

chmod +x "$GAME"

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

[ -n "${sdl_controllerconfig:-}" ] &&
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

cd "$GAMEDIR/mana" || exit 1

GPTK_CONFIG="./mana.gptk"
GPTOPID=""

if [ -n "${GPTOKEYB2:-}" ]; then

    echo "Starting GPTOKEYB2"

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    echo "Starting GPTOKEYB"

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

else

    echo "ERROR: GPTOKEYB/GPTOKEYB2 not found"
    exit 1

fi


cleanup() {

    if [ -n "${GPTOPID:-}" ]; then

        kill "$GPTOPID" \
            2>/dev/null \
            || true

        wait "$GPTOPID" \
            2>/dev/null \
            || true

    fi

}

trap cleanup EXIT INT TERM


"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"

RET=$?

exit "$RET"

LAUNCHER

chmod +x "$PORT/Mana.sh"


# ============================================================
# GPTOKEYB
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
# port.json
# ============================================================

cat > "$PORT/port.json" <<'JSON'
{
  "version": 4,
  "name": "mana-0.8.0.zip",
  "items": ["Mana.sh", "mana"],
  "items_opt": [],
  "attr": {
    "title": "Mana 0.8.0",
    "porter": ["Kaddte"],
    "desc": "The Mana Client 0.8.0 for AArch64 PortMaster devices.",
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
JSON


# ============================================================
# gameinfo.xml
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
# Copy executable
# ============================================================

cp \
  "$BIN" \
  "$PORT/mana/mana.aarch64"

chmod +x \
  "$PORT/mana/mana.aarch64"


# ============================================================
# Copy game data
# ============================================================

cp -a \
  "$SRC/data" \
  "$PORT/mana/data"


# ============================================================
# Verify mouse.png
# ============================================================

[ -f "$PORT/mana/data/graphics/gui/mouse.png" ] || {

    echo "ERROR: mouse.png missing from package data"

    exit 7
}


# ============================================================
# Licenses
# ============================================================

if [ -d "$SRC/licenses" ]; then

    cp -a \
      "$SRC/licenses" \
      "$PORT/mana/licenses"

fi


# ============================================================
# Final validation
# ============================================================

echo "=== Final validation ==="

test -f "$PORT/Mana.sh"

test -x "$PORT/Mana.sh"

test -f "$PORT/mana/mana.aarch64"

test -f "$PORT/mana/mana.gptk"

test -f "$PORT/port.json"

test -f "$PORT/gameinfo.xml"

test -f "$PORT/mana/data/graphics/gui/mouse.png"


grep \
  -q \
  '^select = f12$' \
  "$PORT/mana/mana.gptk"


grep \
  -q \
  '^right_analog_up = mouse_movement_up$' \
  "$PORT/mana/mana.gptk"


grep \
  -q \
  '^r3 = mouse_left$' \
  "$PORT/mana/mana.gptk"


grep \
  -q \
  '^l3 = mouse_right$' \
  "$PORT/mana/mana.gptk"


# ============================================================
# ELF validation
# ============================================================

file "$PORT/mana/mana.aarch64"

file "$PORT/mana/mana.aarch64" |
    grep -qi 'aarch64' || {

    echo 'ERROR: binary is not AArch64'

    exit 8
}


if readelf \
    --version-info \
    "$PORT/mana/mana.aarch64" \
    2>/dev/null |
    grep -q 'GLIBC_2\.43'
then

    echo 'ERROR: binary requires GLIBC_2.43'

    exit 9

fi


# ============================================================
# ZIP
# ============================================================

PACKAGE="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

(
    cd "$PORT"

    zip \
      -qr \
      "$PACKAGE" \
      .
)


unzip \
  -l \
  "$PACKAGE" \
  > "$DIST/package-list.txt"


# ============================================================
# Diagnostics
# ============================================================

{
    echo '=== FILE ==='

    file \
      "$PORT/mana/mana.aarch64"


    echo

    echo '=== GLIBC ==='

    readelf \
      --version-info \
      "$PORT/mana/mana.aarch64" \
      2>/dev/null |
      grep \
        -o \
        'GLIBC_[0-9][0-9.]*' |
      sort -Vu ||
      true


    echo

    echo '=== GPTK ==='

    cat \
      "$PORT/mana/mana.gptk"


    echo

    echo '=== CURSOR SOURCE ==='

    grep \
      -n \
      -E \
      'mSoftwareCursor|mSoftwareCursorVisible|Key::F12|SDL_ShowCursor' \
      "$SRC/src/gui/gui.h" \
      "$SRC/src/gui/gui.cpp" ||
      true

} > "$DIST/diagnostics.txt"


echo

echo '============================================================'

echo ' BUILD FINALIZADO COM SUCESSO'

echo '============================================================'

echo "ZIP: $PACKAGE"

ls -lh "$PACKAGE"
