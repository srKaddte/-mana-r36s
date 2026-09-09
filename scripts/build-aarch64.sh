#!/bin/bash
set -e

ROOT="/workspace"
SOURCE_DIR="$ROOT/source"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
WORK_DIR="$ROOT/work"

echo "=========================================="
echo " Mana R36S - AArch64 PortMaster Builder"
echo "=========================================="

rm -rf "$BUILD_DIR" "$WORK_DIR" "$DIST_DIR"

mkdir -p "$BUILD_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$DIST_DIR"

# ============================================================
# BUILD DEPENDENCIES
# ============================================================

echo
echo "=== Installing build dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    curl \
    zip \
    unzip \
    file \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libpng-dev \
    zlib1g-dev \
    gettext

# ============================================================
# PHYSFS CHECK
# ============================================================

echo
echo "=== Checking PhysFS ==="

dpkg -l | grep -i physfs || true

pkg-config --modversion physfs 2>/dev/null || true

PHYSFS_HEADER=""

for candidate in \
    /usr/include/physfs.h \
    /usr/include/aarch64-linux-gnu/physfs.h
do
    if [ -f "$candidate" ]; then
        PHYSFS_HEADER="$candidate"
        break
    fi
done

if [ -z "$PHYSFS_HEADER" ]; then
    echo "ERROR: physfs.h não foi encontrado."
    dpkg -L libphysfs-dev 2>/dev/null || true
    exit 1
fi

echo "PhysFS headers: OK"
echo "PHYSFS_HEADER=$PHYSFS_HEADER"

PHYSFS_LIB=""

for candidate in \
    /usr/lib/aarch64-linux-gnu/libphysfs.so \
    /usr/lib/aarch64-linux-gnu/libphysfs.so.1 \
    /usr/lib/libphysfs.so \
    /usr/lib/libphysfs.so.1
do
    if [ -f "$candidate" ]; then
        PHYSFS_LIB="$candidate"
        break
    fi
done

if [ -n "$PHYSFS_LIB" ]; then
    echo "PhysFS library: OK"
    echo "PHYSFS_LIB=$PHYSFS_LIB"
else
    echo "WARNING: não encontrei libphysfs diretamente."
    ldconfig -p 2>/dev/null | grep -i physfs || true
fi

# ============================================================
# CURL CHECK
# ============================================================

echo
echo "=== Checking CURL ==="

CURL_HEADER=""

for candidate in \
    /usr/include/curl/curl.h \
    /usr/include/aarch64-linux-gnu/curl/curl.h \
    /usr/include/arm-linux-gnueabihf/curl/curl.h
do
    if [ -f "$candidate" ]; then
        CURL_HEADER="$candidate"
        break
    fi
done

if [ -z "$CURL_HEADER" ]; then
    echo "ERROR: curl.h não foi encontrado."
    echo
    dpkg -L libcurl4-openssl-dev 2>/dev/null |
        grep '/curl.h$' || true
    exit 1
fi

echo "CURL headers: OK"
echo "CURL_HEADER=$CURL_HEADER"

CURL_LIB=""

for candidate in \
    /usr/lib/aarch64-linux-gnu/libcurl.so \
    /usr/lib/aarch64-linux-gnu/libcurl.so.4 \
    /usr/lib/libcurl.so \
    /usr/lib/libcurl.so.4
do
    if [ -f "$candidate" ]; then
        CURL_LIB="$candidate"
        break
    fi
done

if [ -z "$CURL_LIB" ]; then
    echo "ERROR: libcurl não foi encontrada."
    ldconfig -p 2>/dev/null |
        grep -i libcurl || true
    exit 1
fi

echo "CURL library: OK"
echo "CURL_LIB=$CURL_LIB"

pkg-config --modversion libcurl 2>/dev/null || true

# ============================================================
# LIBXML2 CHECK
# ============================================================

echo
echo "=== Checking LibXml2 ==="

XML_HEADER=""

for candidate in \
    /usr/include/libxml2/libxml/parser.h \
    /usr/include/aarch64-linux-gnu/libxml2/libxml/parser.h
do
    if [ -f "$candidate" ]; then
        XML_HEADER="$candidate"
        break
    fi
done

if [ -z "$XML_HEADER" ]; then
    echo "ERROR: libxml2 headers não foram encontrados."
    dpkg -L libxml2-dev 2>/dev/null |
        grep '/parser.h$' || true
    exit 1
fi

echo "LibXml2 headers: OK"
echo "XML_HEADER=$XML_HEADER"

XML_LIB=""

for candidate in \
    /usr/lib/aarch64-linux-gnu/libxml2.so \
    /usr/lib/aarch64-linux-gnu/libxml2.so.2 \
    /usr/lib/libxml2.so \
    /usr/lib/libxml2.so.2
do
    if [ -f "$candidate" ]; then
        XML_LIB="$candidate"
        break
    fi
done

if [ -z "$XML_LIB" ]; then
    echo "ERROR: libxml2 library não foi encontrada."
    ldconfig -p 2>/dev/null |
        grep -i libxml2 || true
    exit 1
fi

echo "LibXml2 library: OK"
echo "XML_LIB=$XML_LIB"

pkg-config --modversion libxml-2.0 2>/dev/null || true

# ============================================================
# PNG CHECK
# ============================================================

echo
echo "=== Checking PNG ==="

PNG_HEADER=""

for candidate in \
    /usr/include/png.h \
    /usr/include/aarch64-linux-gnu/png.h
do
    if [ -f "$candidate" ]; then
        PNG_HEADER="$candidate"
        break
    fi
done

if [ -z "$PNG_HEADER" ]; then
    echo "ERROR: png.h não foi encontrado."
    exit 1
fi

echo "PNG headers: OK"
echo "PNG_HEADER=$PNG_HEADER"

# ============================================================
# ZLIB CHECK
# ============================================================

echo
echo "=== Checking ZLIB ==="

ZLIB_HEADER=""

for candidate in \
    /usr/include/zlib.h \
    /usr/include/aarch64-linux-gnu/zlib.h
do
    if [ -f "$candidate" ]; then
        ZLIB_HEADER="$candidate"
        break
    fi
done

if [ -z "$ZLIB_HEADER" ]; then
    echo "ERROR: zlib.h não foi encontrado."
    exit 1
fi

echo "ZLIB headers: OK"
echo "ZLIB_HEADER=$ZLIB_HEADER"

# ============================================================
# SOURCE
# ============================================================

echo
echo "=== Locating Mana source ==="

SRC_TAR="$SOURCE_DIR/mana-master.tar.gz"

if [ ! -f "$SRC_TAR" ]; then
    echo "ERROR: não encontrei:"
    echo "  $SRC_TAR"
    echo
    ls -lah "$SOURCE_DIR" || true
    exit 1
fi

echo "Source encontrado:"
ls -lh "$SRC_TAR"

# ============================================================
# EXTRACT SOURCE
# ============================================================

echo
echo "=== Extracting Mana source ==="

tar -xzf "$SRC_TAR" -C "$WORK_DIR"

SRC=""

for d in "$WORK_DIR"/*; do
    if [ -d "$d/src" ] && [ -f "$d/CMakeLists.txt" ]; then
        SRC="$d"
        break
    fi
done

if [ -z "$SRC" ]; then
    echo "ERROR: não encontrei a árvore de código do Mana."
    find "$WORK_DIR" -maxdepth 3 -type f | head -100
    exit 1
fi

echo "SRC=$SRC"

# ============================================================
# SOURCE CHECK
# ============================================================

echo
echo "=== Checking source ==="

test -f "$SRC/CMakeLists.txt"
test -f "$SRC/src/CMakeLists.txt"

# ============================================================
# SDL2_TTF
# ============================================================

echo
echo "=== Patching SDL2_ttf requirement ==="

python3 - "$SRC/src/CMakeLists.txt" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

s = s.replace("SDL2_ttf>=2.0.18", "SDL2_ttf>=2.0.15")

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

print("SDL2_ttf requirement checked.")
PY

# ============================================================
# GUICHAN
# ============================================================

echo
echo "=== Preparing bundled Guichan ==="

mkdir -p "$SRC/libs"

GUICHAN_TAR="$WORK_DIR/guichan-0.8.3.tar.gz"

if [ ! -f "$GUICHAN_TAR" ]; then
    curl -L \
        --fail \
        --retry 3 \
        -o "$GUICHAN_TAR" \
        "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"
fi

rm -rf "$WORK_DIR/guichan-src"
mkdir -p "$WORK_DIR/guichan-src"

tar -xzf "$GUICHAN_TAR" -C "$WORK_DIR/guichan-src"

GUICHAN_ROOT=""

for d in "$WORK_DIR/guichan-src"/*; do
    if [ -d "$d/include" ] || \
       [ -f "$d/CMakeLists.txt" ] || \
       [ -f "$d/Makefile.am" ]; then
        GUICHAN_ROOT="$d"
        break
    fi
done

if [ -z "$GUICHAN_ROOT" ]; then
    echo "ERROR: não encontrei Guichan extraído."
    find "$WORK_DIR/guichan-src" -maxdepth 2 -type f | head -100
    exit 1
fi

rm -rf "$SRC/libs/guichan"
mkdir -p "$SRC/libs/guichan"

cp -a "$GUICHAN_ROOT"/. "$SRC/libs/guichan"/

echo "Guichan OK"

# ============================================================
# ENET
# ============================================================

echo
echo "=== Preparing bundled ENet ==="

ENET_TAR="$WORK_DIR/enet-1.3.18.tar.gz"

if [ ! -f "$ENET_TAR" ]; then
    curl -L \
        --fail \
        --retry 3 \
        -o "$ENET_TAR" \
        "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"
fi

rm -rf "$WORK_DIR/enet-src"
mkdir -p "$WORK_DIR/enet-src"

tar -xzf "$ENET_TAR" -C "$WORK_DIR/enet-src"

ENET_ROOT=""

for d in "$WORK_DIR/enet-src"/*; do
    if [ -f "$d/CMakeLists.txt" ] || \
       [ -f "$d/Makefile.am" ]; then
        ENET_ROOT="$d"
        break
    fi
done

if [ -z "$ENET_ROOT" ]; then
    echo "ERROR: não encontrei ENet extraído."
    find "$WORK_DIR/enet-src" -maxdepth 2 -type f | head -100
    exit 1
fi

rm -rf "$SRC/libs/enet"
mkdir -p "$SRC/libs/enet"

cp -a "$ENET_ROOT"/. "$SRC/libs/enet"/

echo "ENet OK"

# ============================================================
# TRUETYPEFONT
# ============================================================

echo
echo "=== Patching TrueTypeFont ==="

TTF="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TTF" ]; then
    echo "ERROR: $TTF não encontrado."
    exit 1
fi

python3 - "$TTF" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

old1 = "        TTF_SetFontSize(font->mFont, font->mPointSize * mScale);\n"
old2 = "        TTF_SetFontSize(font->mFontOutline, font->mPointSize * mScale);\n"

count1 = s.count(old1)
count2 = s.count(old2)

s = s.replace(old1, "")
s = s.replace(old2, "")

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

print("TTF_SetFontSize removidos:")
print("  mFont:", count1)
print("  mFontOutline:", count2)
PY

# ============================================================
# SOFTWARE CURSOR
# ============================================================

echo
echo "=========================================="
echo " Patching R36S software cursor"
echo "=========================================="

GUI_H="$SRC/src/gui/gui.h"
GUI_CPP="$SRC/src/gui/gui.cpp"

test -f "$GUI_H"
test -f "$GUI_CPP"

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys
import re

header = sys.argv[1]
source = sys.argv[2]

with open(header, "r", encoding="utf-8") as f:
    h = f.read()

with open(source, "r", encoding="utf-8") as f:
    c = f.read()

# ============================================================
# HEADER
# ============================================================

if '#include "resources/imageset.h"' not in h:
    marker = '#include "gui/widgets/window.h"'

    if marker in h:
        h = h.replace(
            marker,
            marker + '\n#include "resources/imageset.h"',
            1
        )
    else:
        h = '#include "resources/imageset.h"\n' + h

# Remove EVERY previous cursor declaration.
h = re.sub(
    r'^\s*ResourceRef<Image>\s+mSoftwareCursor\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^\s*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^\s*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

marker = 'Cursor mCursorType = Cursor::Pointer;'

if marker not in h:
    raise SystemExit(
        "ERROR: Cursor mCursorType não encontrado em gui.h"
    )

h = h.replace(
    marker,
    """Cursor mCursorType = Cursor::Pointer;

    ResourceRef<ImageSet> mSoftwareCursor;
    bool mSoftwareCursorVisible = true;""",
    1
)

with open(header, "w", encoding="utf-8") as f:
    f.write(h)

# ============================================================
# SOURCE CLEANUP
# ============================================================

# Remove old software cursor initializations.
c = re.sub(
    r'\n\s*mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'\s*mTheme->resolvePath\("mouse\.png"\)'
    r'\s*,\s*40\s*,\s*40\s*\)\s*;',
    '',
    c,
    flags=re.DOTALL
)

# Remove old cursor visibility toggles.
c = re.sub(
    r'\n\s*if\s*\(\s*event\.getKey\(\)\.getValue\(\)'
    r'\s*==\s*gcn::Key::F12\s*\)'
    r'\s*\{.*?'
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;'
    r'.*?event\.consume\(\)\s*;.*?'
    r'(?:return\s*;)?\s*\}',
    '',
    c,
    flags=re.DOTALL
)

# Remove any old cursor rendering block that references the
# software cursor. This deliberately removes both drawImage
# and drawRescaledImage versions from previous attempts.
c = re.sub(
    r'\n\s*auto\s*\*\s*softwareCursorGraphics\s*='
    r'.*?'
    r'if\s*\(\s*softwareCursorGraphics\s*&&'
    r'.*?'
    r'mSoftwareCursor->get\(0\)'
    r'.*?'
    r'\}\s*',
    '\n',
    c,
    flags=re.DOTALL
)

# Remove hardware cursor ENABLE.
c = c.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

# Remove duplicate DISABLE calls before adding the canonical one.
c = re.sub(
    r'\n\s*SDL_ShowCursor\(SDL_DISABLE\);\s*',
    '\n',
    c
)

# ============================================================
# CONSTRUCTOR
# ============================================================

constructor_marker = 'setUseCustomCursor(config.customCursor);'

if constructor_marker not in c:
    raise SystemExit(
        "ERROR: setUseCustomCursor(config.customCursor); "
        "não encontrado."
    )

constructor_patch = """setUseCustomCursor(config.customCursor);

    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);"""

c = c.replace(
    constructor_marker,
    constructor_patch,
    1
)

# ============================================================
# DRAW
# ============================================================

draw_marker = '    gcn::Gui::draw();'

if draw_marker not in c:
    raise SystemExit(
        "ERROR: gcn::Gui::draw(); não encontrado."
    )

draw_patch = """    gcn::Gui::draw();

    auto *softwareCursorGraphics =
        static_cast<Graphics*>(mGraphics);

    if (softwareCursorGraphics &&
        mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        softwareCursorGraphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);
    }"""

c = c.replace(
    draw_marker,
    draw_patch,
    1
)

# ============================================================
# KEY PRESSED / F12
# ============================================================

key_pattern = (
    r'void\s+Gui::keyPressed\s*'
    r'\(\s*gcn::KeyEvent\s*&\s*event\s*\)\s*'
    r'\{'
)

match = re.search(key_pattern, c)

if not match:
    raise SystemExit(
        "ERROR: Gui::keyPressed(gcn::KeyEvent &event) "
        "não encontrado."
    )

body_start = match.end()

brace_depth = 1
pos = body_start

while pos < len(c) and brace_depth:
    if c[pos] == '{':
        brace_depth += 1
    elif c[pos] == '}':
        brace_depth -= 1
    pos += 1

function_end = pos
function_body = c[body_start:function_end]

if 'mSoftwareCursorVisible = !mSoftwareCursorVisible;' not in function_body:

    f12_code = """    if (event.getKey().getValue() == gcn::Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }

"""

    c = (
        c[:body_start]
        + "\n"
        + f12_code
        + c[body_start:]
    )

with open(source, "w", encoding="utf-8") as f:
    f.write(c)

# ============================================================
# HARD VALIDATION
# ============================================================

with open(header, "r", encoding="utf-8") as f:
    h = f.read()

with open(source, "r", encoding="utf-8") as f:
    c = f.read()

print()
print("=== Cursor validation ===")

# Declaration
if len(re.findall(
    r'ResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    h
)) != 1:
    raise SystemExit(
        "ERROR: mSoftwareCursor não está declarado exatamente uma vez."
    )

# Visibility
if len(re.findall(
    r'bool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    h
)) != 1:
    raise SystemExit(
        "ERROR: mSoftwareCursorVisible não está declarado corretamente."
    )

# F12
f12_matches = re.findall(
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*gcn::Key::F12',
    c
)

if len(f12_matches) != 1:
    raise SystemExit(
        "ERROR: F12 não está configurado exatamente uma vez."
    )

# Toggle
if not re.search(
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;',
    c
):
    raise SystemExit(
        "ERROR: toggle F12 não encontrado."
    )

# Initialization
if not re.search(
    r'getImageSet\(\s*'
    r'mTheme->resolvePath\("mouse\.png"\)\s*,\s*40\s*,\s*40\s*\)',
    c,
    flags=re.DOTALL
):
    raise SystemExit(
        "ERROR: inicialização do cursor não encontrada."
    )

# Rendering
cursor_draw = re.search(
    r'softwareCursorGraphics->drawImage\(\s*'
    r'mSoftwareCursor->get\(0\)\s*,\s*'
    r'mMouseX\s*-\s*15\s*,\s*'
    r'mMouseY\s*-\s*17\s*\)\s*;',
    c,
    flags=re.DOTALL
)

if not cursor_draw:
    raise SystemExit(
        "ERROR: chamada drawImage do cursor não encontrada."
    )

# CRITICAL:
# The cursor must NOT use drawRescaledImage.
if 'softwareCursorGraphics->drawRescaledImage' in c:
    raise SystemExit(
        "ERROR CRÍTICO: drawRescaledImage ainda está sendo "
        "usado pelo cursor."
    )

# No old cursor patch.
if 'drawRescaledImage(mSoftwareCursor' in c:
    raise SystemExit(
        "ERROR CRÍTICO: patch antigo drawRescaledImage "
        "do cursor ainda existe."
    )

# Hardware cursor must never be enabled.
if 'SDL_ShowCursor(SDL_ENABLE);' in c:
    raise SystemExit(
        "ERROR: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )

# ============================================================
# PRINT EXACT CURSOR CODE
# ============================================================

print()
print("=== FINAL CURSOR CODE ===")

draw_pos = c.find(
    'softwareCursorGraphics->drawImage('
)

if draw_pos >= 0:
    start = c.rfind(
        'auto *softwareCursorGraphics',
        0,
        draw_pos
    )

    end = c.find(
        '}',
        draw_pos
    )

    if start >= 0 and end >= 0:
        print(c[start:end + 1])

print()
print("R36S SOFTWARE CURSOR VALIDATION: OK")
print("drawImage(): OK")
print("drawRescaledImage(): NÃO USADO")
print("F12 toggle: OK")
print("SDL hardware cursor: DISABLED")

PY

echo
echo "=== Software cursor patch OK ==="

# ============================================================
# FINAL SOURCE SAFETY CHECK
# ============================================================

echo
echo "=== Final source safety check ==="

if grep -n "softwareCursorGraphics->drawRescaledImage" \
    "$SRC/src/gui/gui.cpp"; then

    echo "ERROR: drawRescaledImage encontrado no cursor."
    exit 1
fi

if grep -n "SDL_ShowCursor(SDL_ENABLE)" \
    "$SRC/src/gui/gui.cpp"; then

    echo "ERROR: SDL hardware cursor ENABLE encontrado."
    exit 1
fi

if ! grep -n "softwareCursorGraphics->drawImage" \
    "$SRC/src/gui/gui.cpp"; then

    echo "ERROR: drawImage do cursor não encontrado."
    exit 1
fi

echo "Source safety check: OK"

# ============================================================
# CMAKE
# ============================================================

echo
echo "=========================================="
echo " Configuring AArch64 build"
echo "=========================================="

cd "$BUILD_DIR"

cmake "$SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DENABLE_TESTS=OFF \
    -DBUILD_TESTS=OFF

# ============================================================
# BUILD
# ============================================================

echo
echo "=========================================="
echo " Building Mana"
echo "=========================================="

JOBS="$(nproc)"

if [ "$JOBS" -gt 4 ]; then
    JOBS=4
fi

cmake --build . --parallel "$JOBS"

# ============================================================
# EXECUTABLE
# ============================================================

echo
echo "=== Locating Mana executable ==="

GAME=""

for candidate in \
    "$BUILD_DIR/src/mana" \
    "$BUILD_DIR/mana" \
    "$BUILD_DIR/src/mana.aarch64" \
    "$BUILD_DIR/mana.aarch64"
do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        GAME="$candidate"
        break
    fi
done

if [ -z "$GAME" ]; then
    GAME="$(
        find "$BUILD_DIR" -type f \
            \( -name "mana" -o -name "mana.aarch64" \) \
            -perm -111 |
        head -1 || true
    )"
fi

if [ -z "$GAME" ]; then
    echo "ERROR: executável Mana não encontrado."
    find "$BUILD_DIR" -type f -perm -111 -print || true
    exit 1
fi

echo "GAME=$GAME"

file "$GAME"

# ============================================================
# ARCHITECTURE
# ============================================================

echo
echo "=== Checking architecture ==="

if ! file "$GAME" | grep -qiE 'ARM aarch64|ARM64'; then
    echo "ERROR: executável não parece ser AArch64."
    exit 1
fi

echo "AArch64 OK"

# ============================================================
# PORTMASTER PACKAGE
# ============================================================

echo
echo "=========================================="
echo " Creating PortMaster package"
echo "=========================================="

PACKAGE_ROOT="$WORK_DIR/package"

rm -rf "$PACKAGE_ROOT"

mkdir -p "$PACKAGE_ROOT/mana"

cp "$GAME" "$PACKAGE_ROOT/mana/mana.aarch64"

chmod +x "$PACKAGE_ROOT/mana/mana.aarch64"

# ============================================================
# DATA
# ============================================================

echo
echo "=== Copying Mana data ==="

if [ -d "$SRC/data" ]; then
    cp -a "$SRC/data" "$PACKAGE_ROOT/mana/"
else
    echo "WARNING: diretório data não encontrado."
fi

# ============================================================
# LAUNCHER
# ============================================================

echo
echo "=== Creating PortMaster launcher ==="

cat > "$PACKAGE_ROOT/Mana.sh" <<'EOF'
#!/bin/bash

GAMEDIR="/roms/ports/mana"
CONFDIR="${XDG_CONFIG_HOME:-$HOME/.config}/mana"
GAMEDATA="$GAMEDIR/mana/data"

mkdir -p "$CONFDIR"

cd "$GAMEDIR/mana"

if [ -f "/opt/system/Tools/PortMaster/control.txt" ]; then
    source "/opt/system/Tools/PortMaster/control.txt"
fi

if [ -f "/opt/system/Tools/PortMaster/libs/portmaster.control.txt" ]; then
    source "/opt/system/Tools/PortMaster/libs/portmaster.control.txt"
fi

if command -v get_controls >/dev/null 2>&1; then
    get_controls
fi

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -x "$GAME" ]; then
    echo "Mana executable not found:"
    echo "$GAME"
    exit 1
fi

if [ -n "${GPTOKEYB:-}" ]; then
    "$GPTOKEYB" "$GAME" -c "$GAMEDIR/mana/mana.gptk" &
    GPTK_PID=$!
fi

"$GAME" \
    --data "$GAMEDATA" \
    --localdata-dir "$CONFDIR"

STATUS=$?

if [ -n "${GPTK_PID:-}" ]; then
    kill "$GPTK_PID" 2>/dev/null || true
    wait "$GPTK_PID" 2>/dev/null || true
fi

if command -v pm_finish >/dev/null 2>&1; then
    pm_finish
fi

exit "$STATUS"
EOF

chmod +x "$PACKAGE_ROOT/Mana.sh"

# ============================================================
# CONTROLS
# ============================================================

echo
echo "=== Creating controller mapping ==="

cat > "$PACKAGE_ROOT/mana/mana.gptk" <<'EOF'
back = esc
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
EOF

# ============================================================
# PORT.JSON
# ============================================================

echo
echo "=== Creating port.json ==="

cat > "$PACKAGE_ROOT/port.json" <<'EOF'
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
    "desc": "The Mana Client 0.8.0, built for AArch64/ARM64 PortMaster devices.",
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

# ============================================================
# GAMEINFO
# ============================================================

echo
echo "=== Creating gameinfo.xml ==="

cat > "$PACKAGE_ROOT/gameinfo.xml" <<'EOF'
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

# ============================================================
# PACKAGE CHECK
# ============================================================

echo
echo "=== Checking package ==="

test -f "$PACKAGE_ROOT/Mana.sh"
test -x "$PACKAGE_ROOT/Mana.sh"

test -f "$PACKAGE_ROOT/mana/mana.aarch64"
test -x "$PACKAGE_ROOT/mana/mana.aarch64"

test -f "$PACKAGE_ROOT/mana/mana.gptk"
test -f "$PACKAGE_ROOT/port.json"
test -f "$PACKAGE_ROOT/gameinfo.xml"

echo "Package structure OK"

# ============================================================
# ZIP
# ============================================================

echo
echo "=== Creating ZIP ==="

cd "$PACKAGE_ROOT"

ZIP="$DIST_DIR/mana-r36s-aarch64-portmaster.zip"

zip -r "$ZIP" \
    Mana.sh \
    mana \
    port.json \
    gameinfo.xml

# ============================================================
# DIAGNOSTICS
# ============================================================

echo
echo "=== Generating diagnostics ==="

DIAG="$DIST_DIR/diagnostics.txt"

{
    echo "Mana R36S AArch64 PortMaster diagnostics"
    echo
    echo "Source:"
    echo "$SRC_TAR"
    echo
    echo "Source directory:"
    echo "$SRC"
    echo
    echo "Executable:"
    echo "$GAME"
    echo
    echo "Architecture:"
    file "$GAME"
    echo
    echo "GLIBC requirements:"
    strings "$GAME" 2>/dev/null |
        grep -oE 'GLIBC_[0-9]+\.[0-9]+' |
        sort -Vu || true
    echo
    echo "SDL / PhysFS / CURL / LibXml2 / PNG / ZLIB libraries:"
    ldd "$GAME" 2>/dev/null |
        grep -Ei 'SDL|ttf|enet|guichan|physfs|curl|xml2|png|z' || true
    echo
    echo "PhysFS:"
    pkg-config --modversion physfs 2>/dev/null || true
    echo
    echo "CURL:"
    pkg-config --modversion libcurl 2>/dev/null || true
    echo
    echo "LibXml2:"
    pkg-config --modversion libxml-2.0 2>/dev/null || true
    echo
    echo "PNG:"
    pkg-config --modversion libpng 2>/dev/null || true
    echo
    echo "Package:"
    ls -lh "$ZIP"
} > "$DIAG"

# ============================================================
# FINAL ZIP VALIDATION
# ============================================================

echo
echo "=== Final validation ==="

unzip -t "$ZIP"

echo
echo "Package contents:"
unzip -l "$ZIP"

echo
echo "=========================================="
echo " BUILD SUCCESS"
echo "=========================================="

echo
echo "ZIP:"
echo "$ZIP"

echo
echo "Diagnostics:"
echo "$DIAG"

echo
ls -lh "$DIST_DIR"
