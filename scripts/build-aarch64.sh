#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Mana 0.8.0 - PortMaster AArch64 / R36S
#
# Build:
#   - AArch64
#   - PortMaster
#   - Guichan 0.8.3
#   - ENet 1.3.18
#   - SDL2_ttf compatível com o builder
#   - software cursor interno ao Mana
#   - F12/SELECT somente mostra/esconde o cursor
#   - mouse sempre ativo
#   - R3 = mouse esquerdo
#   - L3 = mouse direito
#   - analógico direito = movimento do mouse
#   - teclado virtual via gptokeyb2
###############################################################################

echo "============================================================"
echo " Mana 0.8.0 - R36S / PortMaster AArch64"
echo "============================================================"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build-aarch64"
SRCROOT="$ROOT/source"
PORTROOT="$ROOT/port"
DIST="$ROOT/dist"

mkdir -p "$WORK" "$DIST" "$PORTROOT"

###############################################################################
# Helpers
###############################################################################

die()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

need_cmd()
{
    command -v "$1" >/dev/null 2>&1 ||
        die "comando necessário não encontrado: $1"
}

###############################################################################
# Check environment
###############################################################################

echo "=== Checking build environment ==="

need_cmd bash
need_cmd cmake
need_cmd make
need_cmd tar
need_cmd gzip
need_cmd curl
need_cmd git
need_cmd python3
need_cmd file
need_cmd readelf
need_cmd zip

if [ -n "${DEVICE_ARCH:-}" ]; then
    echo "DEVICE_ARCH=$DEVICE_ARCH"
fi

if [ -n "${DEVICE_CPU:-}" ]; then
    echo "DEVICE_CPU=$DEVICE_CPU"
fi

###############################################################################
# Detect source archive
###############################################################################

echo "=== Locating Mana source ==="

ARCHIVE=""

for candidate in \
    "$SRCROOT/mana-0.8.0-source.tar.gz" \
    "$SRCROOT/mana-0.8.0.tar.gz" \
    "$SRCROOT/mana.tar.gz" \
    "$ROOT/mana-0.8.0-source.tar.gz"
do
    if [ -f "$candidate" ]; then
        ARCHIVE="$candidate"
        break
    fi
done

[ -n "$ARCHIVE" ] ||
    die "não encontrei o source tar.gz do Mana 0.8.0 em source/"

echo "Source: $ARCHIVE"

###############################################################################
# Clean build tree
###############################################################################

rm -rf "$WORK/src"
mkdir -p "$WORK/src"

tar -xzf "$ARCHIVE" -C "$WORK/src"

TOPDIR="$(find "$WORK/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

[ -n "$TOPDIR" ] ||
    die "não consegui localizar a pasta extraída do Mana"

echo "Mana source: $TOPDIR"

###############################################################################
# Download bundled dependencies
###############################################################################

GUICHAN_URL="https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"
ENET_URL="https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

DEPS="$WORK/deps"
mkdir -p "$DEPS"

echo
echo "=== Downloading Guichan 0.8.3 ==="

if [ ! -f "$DEPS/guichan-0.8.3.tar.gz" ]; then
    curl -L --fail --retry 3 \
        "$GUICHAN_URL" \
        -o "$DEPS/guichan-0.8.3.tar.gz"
fi

echo "=== Downloading ENet 1.3.18 ==="

if [ ! -f "$DEPS/enet-1.3.18.tar.gz" ]; then
    curl -L --fail --retry 3 \
        "$ENET_URL" \
        -o "$DEPS/enet-1.3.18.tar.gz"
fi

###############################################################################
# Install bundled Guichan
###############################################################################

rm -rf "$TOPDIR/libs/guichan"
mkdir -p "$TOPDIR/libs"

mkdir -p "$WORK/guichan"
rm -rf "$WORK/guichan/"*

tar -xzf "$DEPS/guichan-0.8.3.tar.gz" \
    -C "$WORK/guichan"

GUICHAN_DIR="$(find "$WORK/guichan" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

[ -n "$GUICHAN_DIR" ] ||
    die "Guichan 0.8.3 não foi extraído corretamente"

cp -a "$GUICHAN_DIR" "$TOPDIR/libs/guichan"

echo "=== Guichan OK ==="

###############################################################################
# Install bundled ENet
###############################################################################

rm -rf "$TOPDIR/libs/enet"
mkdir -p "$WORK/enet"
rm -rf "$WORK/enet/"*

tar -xzf "$DEPS/enet-1.3.18.tar.gz" \
    -C "$WORK/enet"

ENET_DIR="$(find "$WORK/enet" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

[ -n "$ENET_DIR" ] ||
    die "ENet 1.3.18 não foi extraído corretamente"

cp -a "$ENET_DIR" "$TOPDIR/libs/enet"

echo "=== ENet OK ==="

###############################################################################
# Patch source
###############################################################################

echo
echo "============================================================"
echo " Patching Mana for R36S"
echo "============================================================"

export TOPDIR

python3 - "$TOPDIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])

cmake = root / "src" / "CMakeLists.txt"

if not cmake.exists():
    raise SystemExit("ERROR: src/CMakeLists.txt não encontrado")

text = cmake.read_text()

text2 = re.sub(
    r"SDL2_ttf\s*>=\s*2\.0\.18",
    "SDL2_ttf>=2.0.15",
    text,
)

if text2 == text:
    if "SDL2_ttf>=2.0.15" not in text:
        raise SystemExit(
            "ERROR: não consegui ajustar requisito SDL2_ttf"
        )

cmake.write_text(text2)

print("SDL2_ttf requirement: OK")
PY

###############################################################################
# Patch TrueTypeFont
###############################################################################

python3 - "$TOPDIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
cpp = root / "src" / "resources" / "truetypefont.cpp"

if not cpp.exists():
    raise SystemExit(
        "ERROR: src/resources/truetypefont.cpp não encontrado"
    )

text = cpp.read_text()

old1 = (
    "TTF_SetFontSize("
    "font->mFont, font->mPointSize * mScale);"
)

old2 = (
    "TTF_SetFontSize("
    "font->mFontOutline, font->mPointSize * mScale);"
)

count1 = text.count(old1)
count2 = text.count(old2)

if count1 != 1:
    raise SystemExit(
        f"ERROR: TTF_SetFontSize normal: esperado 1, encontrado {count1}"
    )

if count2 != 1:
    raise SystemExit(
        f"ERROR: TTF_SetFontSize outline: esperado 1, encontrado {count2}"
    )

text = text.replace(old1, "")
text = text.replace(old2, "")

cpp.write_text(text)

print("TrueTypeFont SDL_ttf compatibility patch: OK")
PY

###############################################################################
# Patch software cursor
###############################################################################

echo "=== Patching R36S software cursor ==="

python3 - "$TOPDIR" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])

header = root / "src" / "gui" / "gui.h"
source = root / "src" / "gui" / "gui.cpp"

if not header.exists():
    raise SystemExit("ERROR: gui.h não encontrado")

if not source.exists():
    raise SystemExit("ERROR: gui.cpp não encontrado")

h = header.read_text()
c = source.read_text()

###############################################################################
# gui.h
###############################################################################

if '#include "resources/imageset.h"' not in h:
    marker = '#include "gui/cursor.h"'

    if marker in h:
        h = h.replace(
            marker,
            marker + '\n#include "resources/imageset.h"',
            1,
        )
    else:
        h = '#include "resources/imageset.h"\n' + h

# Remove qualquer declaração antiga que tenha sido adicionada por
# tentativa anterior.
h = re.sub(
    r'^\s*ResourceRef<Image>\s+mSoftwareCursor\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE,
)

h = re.sub(
    r'^\s*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE,
)

# Remove flags antigas duplicadas.
h = re.sub(
    r'^\s*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE,
)

# Insere exatamente uma declaração dentro da classe Gui.
class_match = re.search(
    r'class\s+Gui\b.*?\{',
    h,
    flags=re.DOTALL,
)

if not class_match:
    raise SystemExit("ERROR: classe Gui não encontrada")

insert_pos = class_match.end()

declarations = """
    ResourceRef<ImageSet> mSoftwareCursor;
    bool mSoftwareCursorVisible = true;
"""

h = h[:insert_pos] + declarations + h[insert_pos:]

###############################################################################
# gui.cpp
###############################################################################

# Include ResourceManager/ImageSet support if necessary.
if '#include "resources/imageset.h"' not in c:
    first_include = re.search(r'^#include .*$', c, flags=re.MULTILINE)

    if first_include:
        pos = first_include.end()
        c = c[:pos] + '\n#include "resources/imageset.h"' + c[pos:]
    else:
        c = '#include "resources/imageset.h"\n' + c

###############################################################################
# Constructor cursor initialization
###############################################################################

cursor_init_regex = re.compile(
    r'mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\s*\(',
    re.MULTILINE,
)

cursor_init = """    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"), 40, 40);
    mSoftwareCursorVisible = true;
    SDL_ShowCursor(SDL_DISABLE);
"""

if not cursor_init_regex.search(c):
    constructor = re.search(
        r'Gui::Gui\s*\([^)]*\)\s*\{',
        c,
        flags=re.DOTALL,
    )

    if not constructor:
        raise SystemExit(
            "ERROR: construtor Gui::Gui não encontrado"
        )

    pos = constructor.end()

    c = c[:pos] + "\n" + cursor_init + c[pos:]

###############################################################################
# F12 handling
###############################################################################

# Remove old F12 software cursor handlers from previous attempts.
c = re.sub(
    r'\s*if\s*\(\s*event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12\s*\)'
    r'\s*\{\s*'
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;'
    r'\s*return\s*;\s*'
    r'\}',
    '',
    c,
    flags=re.DOTALL,
)

key_pressed = re.search(
    r'void\s+Gui::keyPressed\s*\([^)]*\)\s*\{',
    c,
    flags=re.DOTALL,
)

if not key_pressed:
    raise SystemExit(
        "ERROR: Gui::keyPressed não encontrado"
    )

start = key_pressed.end()

brace = 1
i = start

while i < len(c) and brace:
    if c[i] == '{':
        brace += 1
    elif c[i] == '}':
        brace -= 1
    i += 1

if brace != 0:
    raise SystemExit(
        "ERROR: não consegui determinar fim de Gui::keyPressed"
    )

body = c[start:i-1]

f12_block = """
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;
        return;
    }

"""

# Coloca F12 no começo da função.
body = f12_block + body

c = c[:start] + body + c[i-1:]

###############################################################################
# Software cursor drawing
###############################################################################

draw_match = re.search(
    r'void\s+Gui::draw\s*\(\s*\)\s*\{',
    c,
)

if not draw_match:
    raise SystemExit(
        "ERROR: Gui::draw() não encontrado"
    )

draw_start = draw_match.end()

brace = 1
i = draw_start

while i < len(c) and brace:
    if c[i] == '{':
        brace += 1
    elif c[i] == '}':
        brace -= 1
    i += 1

if brace != 0:
    raise SystemExit(
        "ERROR: não consegui determinar fim de Gui::draw()"
    )

draw_body = c[draw_start:i-1]

# Remove cursor blocks anteriores.
draw_body = re.sub(
    r'\n\s*if\s*\(\s*mSoftwareCursorVisible.*?'
    r'\n\s*\}\s*',
    '\n',
    draw_body,
    flags=re.DOTALL,
)

software_draw = """
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

draw_body = draw_body.rstrip() + "\n\n" + software_draw

c = c[:draw_start] + draw_body + c[i-1:]

###############################################################################
# Hardware cursor must remain disabled.
###############################################################################

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);",
)

###############################################################################
# Write
###############################################################################

header.write_text(h)
source.write_text(c)

###############################################################################
# Robust validation
###############################################################################

h = header.read_text()
c = source.read_text()

decls = re.findall(
    r'ResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    h,
)

if len(decls) != 1:
    raise SystemExit(
        "ERROR: declaração mSoftwareCursor: "
        f"esperado 1, encontrado {len(decls)}"
    )

visible_decls = re.findall(
    r'bool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    h,
)

if len(visible_decls) != 1:
    raise SystemExit(
        "ERROR: mSoftwareCursorVisible: "
        f"esperado 1, encontrado {len(visible_decls)}"
    )

cursor_init_count = len(re.findall(
    r'mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\s*\(',
    c,
))

if cursor_init_count != 1:
    raise SystemExit(
        "ERROR: inicialização do cursor: "
        f"esperado 1, encontrado {cursor_init_count}"
    )

f12_count = len(re.findall(
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12',
    c,
))

if f12_count != 1:
    raise SystemExit(
        "ERROR: tratamento F12: "
        f"esperado 1, encontrado {f12_count}"
    )

toggle_count = len(re.findall(
    r'mSoftwareCursorVisible\s*=\s*!\s*'
    r'mSoftwareCursorVisible\s*;',
    c,
))

if toggle_count != 1:
    raise SystemExit(
        "ERROR: toggle F12: "
        f"esperado 1, encontrado {toggle_count}"
    )

# Check draw() specifically.
draw_start = c.find("void Gui::draw()")

if draw_start < 0:
    raise SystemExit("ERROR: Gui::draw() não encontrado na validação")

next_function = c.find("\nvoid Gui::", draw_start + 10)

if next_function < 0:
    draw_block = c[draw_start:]
else:
    draw_block = c[draw_start:next_function]

if not re.search(
    r'graphics->drawImage\s*\(\s*'
    r'mSoftwareCursor->get\(0\)',
    draw_block,
    flags=re.DOTALL,
):
    raise SystemExit(
        "ERROR: draw() não contém o desenho do software cursor"
    )

if "drawRescaledImage(" in draw_block:
    raise SystemExit(
        "ERROR: software cursor não deve usar drawRescaledImage()"
    )

if "SDL_ShowCursor(SDL_ENABLE)" in c:
    raise SystemExit(
        "ERROR: SDL_ShowCursor(SDL_ENABLE) ainda presente"
    )

print("R36S software cursor validation: OK")
PY

echo "=== R36S software cursor patch OK ==="

###############################################################################
# Configure
###############################################################################

echo
echo "============================================================"
echo " Configuring AArch64 build"
echo "============================================================"

BUILD="$WORK/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"

cd "$BUILD"

cmake "$TOPDIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DENABLE_ALLEGRO=OFF \
    -DENABLE_IRRLICHT=OFF \
    -DENABLE_SDL=OFF

###############################################################################
# Build
###############################################################################

echo
echo "============================================================"
echo " Building Mana"
echo "============================================================"

JOBS="${JOBS:-$(nproc)}"

if [ "$JOBS" -gt 4 ]; then
    JOBS=4
fi

cmake --build . --parallel "$JOBS"

###############################################################################
# Locate executable
###############################################################################

echo
echo "=== Locating Mana executable ==="

GAME=""

for candidate in \
    "$BUILD/mana" \
    "$BUILD/src/mana" \
    "$BUILD/bin/mana"
do
    if [ -x "$candidate" ]; then
        GAME="$candidate"
        break
    fi
done

if [ -z "$GAME" ]; then
    GAME="$(find "$BUILD" -type f -name mana -perm -111 | head -n 1 || true)"
fi

[ -n "$GAME" ] ||
    die "executável mana não encontrado após o build"

echo "Executable: $GAME"

###############################################################################
# ELF validation
###############################################################################

echo
echo "============================================================"
echo " ELF validation"
echo "============================================================"

file "$GAME"

if ! file "$GAME" | grep -Eqi 'ARM aarch64|ARM64'; then
    die "o executável não parece ser AArch64"
fi

echo
echo "--- GLIBC requirements ---"

readelf --version-info "$GAME" 2>/dev/null |
    grep -oE 'GLIBC_[0-9]+\.[0-9]+' |
    sort -Vu |
    tail -n 20 || true

###############################################################################
# Create PortMaster package
###############################################################################

echo
echo "============================================================"
echo " Creating PortMaster package"
echo "============================================================"

PACKAGE="$WORK/package"

rm -rf "$PACKAGE"

mkdir -p \
    "$PACKAGE/mana/data" \
    "$PACKAGE/mana"

###############################################################################
# Install executable
###############################################################################

cp "$GAME" "$PACKAGE/mana/mana.aarch64"

chmod 755 "$PACKAGE/mana/mana.aarch64"

###############################################################################
# Install Mana data
###############################################################################

if [ -d "$TOPDIR/data" ]; then
    cp -a "$TOPDIR/data/." "$PACKAGE/mana/data/"
else
    die "pasta data/ do Mana não encontrada"
fi

###############################################################################
# Preserve runtime files that may be needed
###############################################################################

for runtime_file in \
    "$TOPDIR/mana.conf" \
    "$TOPDIR/defaults.xml"
do
    if [ -f "$runtime_file" ]; then
        cp "$runtime_file" "$PACKAGE/mana/"
    fi
done

###############################################################################
# GPTOKEYB2 configuration
###############################################################################

cat > "$PACKAGE/mana/mana.gptk" <<'EOF'
[controls]
back = esc
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
EOF

###############################################################################
# Full virtual keyboard state machine
###############################################################################

cat > "$PACKAGE/mana/mana.gptk2" <<'EOF'
[controls]
back = esc

start = hold_state hotkey_start

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


[controls:hotkey_start]
down = push_state text_input


[controls:text_input]
charset = extended

start = pop_state

up = prev_letter
down = next_letter

right = add_letter
left = backspace

a = enter
b = backspace
EOF

###############################################################################
# Launcher
###############################################################################

cat > "$PACKAGE/Mana.sh" <<'EOF'
#!/bin/bash

###############################################################################
# Mana 0.8.0 - PortMaster launcher
###############################################################################

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

GAMEDIR="$(dirname "$0")/mana"
cd "$GAMEDIR" || exit 1

# PortMaster control environment.
if [ -f "/opt/system/Tools/PortMaster/control.txt" ]; then
    . "/opt/system/Tools/PortMaster/control.txt"
fi

if [ -f "/opt/system/Tools/PortMaster/libs/launchers/control.txt" ]; then
    . "/opt/system/Tools/PortMaster/libs/launchers/control.txt"
fi

if command -v get_controls >/dev/null 2>&1; then
    get_controls
fi

# Prefer gptokeyb2 when available.
GPTK=""

if [ -n "${GPTOKEYB2:-}" ] && [ -x "${GPTOKEYB2:-}" ]; then
    GPTK="$GPTOKEYB2"
elif [ -n "${GPTOKEYB:-}" ] && [ -x "${GPTOKEYB:-}" ]; then
    GPTK="$GPTOKEYB"
elif command -v gptokeyb2 >/dev/null 2>&1; then
    GPTK="$(command -v gptokeyb2)"
elif command -v gptokeyb >/dev/null 2>&1; then
    GPTK="$(command -v gptokeyb)"
fi

# Platform helper.
if command -v pm_platform_helper >/dev/null 2>&1; then
    pm_platform_helper "$GAMEDIR/mana.aarch64"
fi

# Environment used by Mana.
export SDL_VIDEO_GL_DRIVER="${SDL_VIDEO_GL_DRIVER:-libmali.so}"
export SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0

# gptokeyb2 is preferred for the FSM virtual keyboard.
if [ -n "$GPTK" ]; then
    case "$(basename "$GPTK")" in
        gptokeyb2|gptokeyb2.*)
            "$GPTK" "./mana.aarch64" -c "./mana.gptk2" &
            GPTK_PID=$?
            ;;
        *)
            "$GPTK" "./mana.aarch64" -c "./mana.gptk" &
            GPTK_PID=$!
            ;;
    esac
else
    GPTK_PID=""
fi

# Mana configuration/data paths.
CONFDIR="${XDG_CONFIG_HOME}/mana"

mkdir -p "$CONFDIR"

export HOME="${HOME:-/tmp}"

# Launch Mana.
./mana.aarch64 \
    --data "./data" \
    --localdata-dir "$CONFDIR"

RET=$?

# Stop keyboard helper.
if [ -n "${GPTK_PID:-}" ]; then
    kill "$GPTK_PID" 2>/dev/null || true
    wait "$GPTK_PID" 2>/dev/null || true
fi

if command -v pm_finish >/dev/null 2>&1; then
    pm_finish
fi

exit "$RET"
EOF

chmod 755 "$PACKAGE/Mana.sh"

###############################################################################
# PortMaster metadata
###############################################################################

cat > "$PACKAGE/port.json" <<'EOF'
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
    "desc": "The Mana Client 0.8.0, built for AArch64/ARM64 PortMaster devices with R36S mouse and controller support.",
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
EOF

###############################################################################
# gameinfo.xml
###############################################################################

cat > "$PACKAGE/gameinfo.xml" <<'EOF'
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
EOF

###############################################################################
# Validate required files
###############################################################################

echo
echo "============================================================"
echo " PortMaster package validation"
echo "============================================================"

[ -f "$PACKAGE/Mana.sh" ] ||
    die "Mana.sh não existe"

[ -x "$PACKAGE/Mana.sh" ] ||
    die "Mana.sh não é executável"

[ -f "$PACKAGE/mana/mana.aarch64" ] ||
    die "mana.aarch64 não existe"

[ -f "$PACKAGE/mana/mana.gptk" ] ||
    die "mana.gptk não existe"

[ -f "$PACKAGE/mana/mana.gptk2" ] ||
    die "mana.gptk2 não existe"

[ -f "$PACKAGE/mana/data/graphics/gui/mouse.png" ] ||
    die "mouse.png não encontrado"

[ -f "$PACKAGE/port.json" ] ||
    die "port.json não existe"

[ -f "$PACKAGE/gameinfo.xml" ] ||
    die "gameinfo.xml não existe"

bash -n "$PACKAGE/Mana.sh"

###############################################################################
# Validate mouse image
###############################################################################

echo
echo "=== Checking mouse.png ==="

file "$PACKAGE/mana/data/graphics/gui/mouse.png"

###############################################################################
# Validate gptokeyb mappings
###############################################################################

echo
echo "=== Checking controller mapping ==="

grep -q '^r3 = mouse_left$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "R3 não está configurado como mouse_left"

grep -q '^l3 = mouse_right$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "L3 não está configurado como mouse_right"

grep -q '^right_analog_up = mouse_movement_up$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "analógico direito não está configurado como mouse"

grep -q '^right_analog_down = mouse_movement_down$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "analógico direito não está configurado como mouse"

grep -q '^right_analog_left = mouse_movement_left$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "analógico direito não está configurado como mouse"

grep -q '^right_analog_right = mouse_movement_right$' \
    "$PACKAGE/mana/mana.gptk" ||
    die "analógico direito não está configurado como mouse"

###############################################################################
# Validate virtual keyboard
###############################################################################

echo
echo "=== Checking virtual keyboard ==="

grep -q '^start = hold_state hotkey_start$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "START não inicia hotkey_start"

grep -q '^down = push_state text_input$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "START + DOWN não abre text_input"

grep -q '^charset = extended$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "charset extended não configurado"

grep -q '^up = prev_letter$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "UP não navega letras"

grep -q '^down = next_letter$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "DOWN não navega letras"

grep -q '^right = add_letter$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "RIGHT não adiciona letra"

grep -q '^left = backspace$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "LEFT não apaga"

grep -q '^a = enter$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "A não está como Enter"

grep -q '^b = backspace$' \
    "$PACKAGE/mana/mana.gptk2" ||
    die "B não está como Backspace"

###############################################################################
# Diagnostics
###############################################################################

DIAG="$DIST/diagnostics.txt"

{
    echo "Mana 0.8.0 R36S PortMaster AArch64"
    echo
    echo "BUILD_ROOT=$ROOT"
    echo "SOURCE=$ARCHIVE"
    echo "EXECUTABLE=$GAME"
    echo
    echo "=== file ==="
    file "$PACKAGE/mana/mana.aarch64"
    echo
    echo "=== readelf GLIBC ==="
    readelf --version-info "$PACKAGE/mana/mana.aarch64" 2>/dev/null |
        grep -oE 'GLIBC_[0-9]+\.[0-9]+' |
        sort -Vu || true
    echo
    echo "=== package files ==="
    find "$PACKAGE" -type f -printf '%P\n' | sort
} > "$DIAG"

###############################################################################
# Create ZIP
###############################################################################

ZIP="$DIST/mana-r36s-portmaster-aarch64.zip"

rm -f "$ZIP"

cd "$PACKAGE"

zip -r -9 "$ZIP" \
    Mana.sh \
    mana \
    port.json \
    gameinfo.xml

###############################################################################
# Final ZIP validation
###############################################################################

echo
echo "============================================================"
echo " FINAL VALIDATION"
echo "============================================================"

unzip -t "$ZIP"

echo
echo "=== ZIP contents ==="

unzip -l "$ZIP"

echo
echo "============================================================"
echo " BUILD SUCCESS"
echo "============================================================"
echo
echo "ZIP:"
echo "  $ZIP"
echo
echo "Diagnostics:"
echo "  $DIAG"
echo
echo "============================================================"
