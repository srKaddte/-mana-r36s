#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo " Mana 0.8.0 - R36S / PortMaster AArch64 Builder"
echo "============================================================"

ROOT="$(pwd)"
SOURCE_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/work"
BUILD="$WORK/build"
DIST="$ROOT/dist"
PORT="$WORK/port"

rm -rf "$WORK" "$DIST"

mkdir -p "$WORK"
mkdir -p "$DIST"
mkdir -p "$PORT"

echo
echo "=== CHECK SOURCE ==="

if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "ERRO: source/mana-master.tar.gz não encontrado."
    echo
    echo "Arquivos encontrados em source/:"
    find "$ROOT/source" -maxdepth 2 -type f -print 2>/dev/null || true
    exit 1
fi

echo "Source: $SOURCE_ARCHIVE"

echo
echo "=== INSTALL BUILD DEPENDENCIES ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    git \
    wget \
    curl \
    tar \
    gzip \
    zip \
    unzip \
    file \
    binutils \
    python3 \
    gettext \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libpng-dev \
    zlib1g-dev \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    libsdl2-net-dev \
    libsdl2-ttf-dev

echo
echo "=== VERIFY DEPENDENCIES ==="

echo
echo "--- PhysFS ---"

if ldconfig -p | grep -q "libphysfs"; then
    echo "PhysFS library: OK"
else
    echo "ERRO: PhysFS library não encontrada."
    exit 1
fi

if [ -f /usr/include/physfs.h ]; then
    echo "PhysFS headers: OK"
else
    echo "ERRO: PhysFS headers não encontrados."
    exit 1
fi

echo
echo "--- CURL ---"

if ldconfig -p | grep -q "libcurl"; then
    echo "CURL library: OK"
else
    echo "ERRO: CURL library não encontrada."
    exit 1
fi

if [ -f /usr/include/curl/curl.h ] ||
   [ -f /usr/include/aarch64-linux-gnu/curl/curl.h ] ||
   [ -f /usr/include/arm-linux-gnueabihf/curl/curl.h ]; then
    echo "CURL headers: OK"
else
    echo "ERRO: CURL headers não encontrados."
    exit 1
fi

echo
echo "--- LibXml2 ---"

if ldconfig -p | grep -q "libxml2"; then
    echo "LibXml2 library: OK"
else
    echo "ERRO: LibXml2 library não encontrada."
    exit 1
fi

if [ -f /usr/include/libxml2/libxml/parser.h ]; then
    echo "LibXml2 headers: OK"
else
    echo "ERRO: LibXml2 headers não encontrados."
    exit 1
fi

echo
echo "--- SDL2 ---"

if pkg-config --exists sdl2; then
    echo "SDL2: OK"
else
    echo "ERRO: SDL2 não encontrado."
    exit 1
fi

echo
echo "--- SDL2_image ---"

if pkg-config --exists SDL2_image; then
    echo "SDL2_image: OK"
else
    echo "ERRO: SDL2_image não encontrado."
    exit 1
fi

echo
echo "--- SDL2_mixer ---"

if pkg-config --exists SDL2_mixer; then
    echo "SDL2_mixer: OK"
else
    echo "ERRO: SDL2_mixer não encontrado."
    exit 1
fi

echo
echo "--- SDL2_net ---"

if pkg-config --exists SDL2_net; then
    echo "SDL2_net: OK"
else
    echo "ERRO: SDL2_net não encontrado."
    exit 1
fi

echo
echo "--- SDL2_ttf ---"

if pkg-config --exists SDL2_ttf; then
    echo "SDL2_ttf: OK"
    pkg-config --modversion SDL2_ttf || true
else
    echo "ERRO: SDL2_ttf não encontrado."
    exit 1
fi

echo
echo "=== EXTRACT SOURCE ==="

tar -xzf "$SOURCE_ARCHIVE" -C "$WORK"

SOURCE_DIR=""

if [ -d "$WORK/mana-master" ]; then
    SOURCE_DIR="$WORK/mana-master"
else
    SOURCE_DIR="$(
        find "$WORK" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            | head -n 1
    )"
fi

if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
    echo "ERRO: diretório do source do Mana não encontrado."
    echo
    find "$WORK" -maxdepth 2 -type d -print
    exit 1
fi

SRC="$SOURCE_DIR"

echo "Source directory:"
echo "$SRC"

echo
echo "=== VERIFY SOURCE STRUCTURE ==="

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "ERRO: CMakeLists.txt não encontrado."
    exit 1
fi

if [ ! -d "$SRC/src" ]; then
    echo "ERRO: src/ não encontrado."
    exit 1
fi

echo "CMakeLists.txt: OK"
echo "src/: OK"

echo
echo "=== VERIFY TRUE TYPE FONT SOURCE ==="

TTF_FILE="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TTF_FILE" ]; then
    echo "ERRO: truetypefont.cpp não encontrado."
    echo
    echo "Procurando o arquivo:"
    find "$SRC/src" \
        -type f \
        -iname 'truetypefont.cpp' \
        -print || true
    exit 1
fi

echo "truetypefont.cpp:"
echo "$TTF_FILE"
echo "truetypefont.cpp: OK"

echo
echo "=== VERIFY GUI SOURCE ==="

GUI_H="$SRC/src/gui/gui.h"
GUI_CPP="$SRC/src/gui/gui.cpp"

if [ !f "$GUI_H" ]; then
    echo "ERRO: gui.h não encontrado."
    exit 1
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.cpp não encontrado."
    exit 1
fi

echo "gui.h: OK"
echo "gui.cpp: OK"

echo
echo "=== DOWNLOAD BUNDLED GUICHAN ==="

mkdir -p "$SRC/libs"

GUICHAN_URL="https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$SRC/libs/guichan"
rm -rf "$WORK/guichan"

wget \
    --no-verbose \
    "$GUICHAN_URL" \
    -O "$WORK/guichan.tar.gz"

tar -xzf "$WORK/guichan.tar.gz" -C "$WORK"

GUICHAN_DIR="$(
    find "$WORK" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'guichan-*' \
        | head -n 1
)"

if [ -z "$GUICHAN_DIR" ]; then
    echo "ERRO: Guichan não foi extraído."
    exit 1
fi

mv "$GUICHAN_DIR" "$SRC/libs/guichan"

echo "Guichan: OK"

echo
echo "=== DOWNLOAD BUNDLED ENET ==="

ENET_URL="https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$SRC/libs/enet"
rm -rf "$WORK/enet"

wget \
    --no-verbose \
    "$ENET_URL" \
    -O "$WORK/enet.tar.gz"

tar -xzf "$WORK/enet.tar.gz" -C "$WORK"

ENET_DIR="$(
    find "$WORK" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'enet-*' \
        | head -n 1
)"

if [ -z "$ENET_DIR" ]; then
    echo "ERRO: ENet não foi extraído."
    exit 1
fi

mv "$ENET_DIR" "$SRC/libs/enet"

echo "ENet: OK"

echo
echo "=== PATCH SDL2_TTF REQUIREMENT ==="

python3 - "$SRC/src/CMakeLists.txt" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text()

original = text

text = re.sub(
    r'(find_package\s*\(\s*SDL2_ttf\s+)[0-9]+\.[0-9]+\.[0-9]+',
    r'\g<1>2.0.15',
    text,
    count=1
)

if text != original:
    path.write_text(text)
    print("SDL2_ttf requirement patched to 2.0.15")
else:
    print("SDL2_ttf requirement already compatible or not found")
PY

echo
echo "=== PATCH TRUE TYPE FONT ==="

python3 - "$TTF_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

text = path.read_text()

original = text

# Mana 0.8 source uses TTF_SetFontSize() here.
#
# The builder's SDL2_ttf is older, so these calls are removed.
# The rest of updateFontScale() remains intact.

text = re.sub(
    r'^[ \t]*TTF_SetFontSize\(\s*'
    r'font->mFont\s*,\s*'
    r'font->mPointSize\s*\*\s*mScale\s*\)\s*;\s*$',
    '',
    text,
    flags=re.MULTILINE
)

text = re.sub(
    r'^[ \t]*TTF_SetFontSize\(\s*'
    r'font->mFontOutline\s*,\s*'
    r'font->mPointSize\s*\*\s*mScale\s*\)\s*;\s*$',
    '',
    text,
    flags=re.MULTILINE
)

if text != original:
    path.write_text(text)
    print("TTF_SetFontSize scaling calls removed")
else:
    print("No TTF_SetFontSize scaling calls changed")
PY

echo
echo "=== VERIFY TRUE TYPE PATCH ==="

if grep -q "TTF_SetFontSize(font->mFont" "$TTF_FILE"; then
    echo "ERRO: TTF_SetFontSize(font->mFont...) ainda existe."
    exit 1
fi

if grep -q "TTF_SetFontSize(font->mFontOutline" "$TTF_FILE"; then
    echo "ERRO: TTF_SetFontSize(font->mFontOutline...) ainda existe."
    exit 1
fi

echo "TrueTypeFont compatibility patch: OK"

echo
echo "=== SOFTWARE CURSOR PATCH ==="

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
from pathlib import Path
import re
import sys

header_path = Path(sys.argv[1])
cpp_path = Path(sys.argv[2])

h = header_path.read_text()
c = cpp_path.read_text()

print("Aplicando software cursor...")

# ============================================================
# HEADER
# ============================================================

if '#include "resources/imageset.h"' not in h:
    marker = '#include "gui/widgets/container.h"'

    if marker in h:
        h = h.replace(
            marker,
            '#include "resources/imageset.h"\n' + marker,
            1
        )
    else:
        lines = h.splitlines()

        insert_at = 0

        while insert_at < len(lines):
            stripped = lines[insert_at].strip()

            if stripped.startswith("#include"):
                insert_at += 1
                continue

            if stripped == "":
                insert_at += 1
                continue

            break

        lines.insert(
            insert_at,
            '#include "resources/imageset.h"'
        )

        h = "\n".join(lines) + "\n"

# Remove old duplicate declarations.
h = re.sub(
    r'^[ \t]*ResourceRef<ImageSet>[ \t]+mSoftwareCursor[ \t]*;[ \t]*\n',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^[ \t]*bool[ \t]+mSoftwareCursorVisible[ \t]*=[ \t]*true[ \t]*;[ \t]*\n',
    '',
    h,
    flags=re.MULTILINE
)

# Insert after mCursorType when possible.
if 'ResourceRef<ImageSet> mSoftwareCursor;' not in h:

    cursor_marker = re.search(
        r'^[ \t]*Cursor[ \t]+mCursorType[ \t]*=[ \t]*Cursor::Pointer[ \t]*;[ \t]*$',
        h,
        flags=re.MULTILINE
    )

    if cursor_marker:

        insertion = (
            cursor_marker.group(0)
            + "\n"
            + "    ResourceRef<ImageSet> mSoftwareCursor;\n"
            + "    bool mSoftwareCursorVisible = true;"
        )

        h = (
            h[:cursor_marker.start()]
            + insertion
            + h[cursor_marker.end():]
        )

    else:

        class_match = re.search(
            r'\bclass\s+Gui\b',
            h
        )

        if not class_match:
            raise SystemExit(
                "ERRO: classe Gui não encontrada em gui.h"
            )

        class_start = class_match.start()

        class_end = h.find(
            "};",
            class_start
        )

        if class_end == -1:
            raise SystemExit(
                "ERRO: fim da classe Gui não encontrado"
            )

        declarations = (
            "    ResourceRef<ImageSet> mSoftwareCursor;\n"
            "    bool mSoftwareCursorVisible = true;\n"
        )

        h = (
            h[:class_end]
            + declarations
            + h[class_end:]
        )

# ============================================================
# CPP - CONSTRUCTOR
# ============================================================

cursor_initialization = '''    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"), 40, 40);
    SDL_ShowCursor(SDL_DISABLE);
'''

# Remove any previous software cursor initialization.
c = re.sub(
    r'\n[ \t]*mSoftwareCursor[ \t]*=[ \t]*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'\s*mTheme->resolvePath\("mouse\.png"\)\s*,\s*40\s*,\s*40\s*'
    r'\)\s*;\s*',
    '\n',
    c,
    flags=re.DOTALL
)

# Remove duplicated disable calls.
c = re.sub(
    r'(SDL_ShowCursor\(SDL_DISABLE\);\s*){2,}',
    'SDL_ShowCursor(SDL_DISABLE);\n',
    c
)

if 'mSoftwareCursor =' not in c:

    marker = 'setUseCustomCursor(config.customCursor);'

    if marker in c:

        c = c.replace(
            marker,
            marker
            + "\n\n"
            + cursor_initialization.rstrip(),
            1
        )

    else:

        constructor = re.search(
            r'Gui::Gui\s*\([^)]*\)\s*\{',
            c
        )

        if not constructor:
            raise SystemExit(
                "ERRO: constructor Gui::Gui não encontrado"
            )

        c = (
            c[:constructor.end()]
            + "\n\n"
            + cursor_initialization.rstrip()
            + "\n"
            + c[constructor.end():]
        )

# ============================================================
# CPP - SOFTWARE CURSOR DRAW
# ============================================================

# Remove previously injected software cursor blocks.
c = re.sub(
    r'\n[ \t]*auto[ \t]+\*softwareCursorGraphics[ \t]*=[ \t]*'
    r'static_cast<Graphics\*>\(mGraphics\)[ \t]*;'
    r'\s*'
    r'if[ \t]*\([^{]*'
    r'mSoftwareCursorVisible'
    r'[^)]*\)'
    r'\s*\{'
    r'\s*'
    r'(?:\w+->)?draw(?:Rescaled)?Image\([^;]*mSoftwareCursor->get\(0\)[^;]*\);'
    r'\s*\}',
    '',
    c,
    flags=re.DOTALL
)

draw_block = '''
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
    }
'''

draw_function = re.search(
    r'\bvoid\s+Gui::draw\s*\(\s*\)\s*\{',
    c
)

if not draw_function:
    raise SystemExit(
        "ERRO: Gui::draw() não encontrado"
    )

# Find matching closing brace.
pos = draw_function.end()

depth = 1

while pos < len(c) and depth > 0:

    if c[pos] == "{":
        depth += 1

    elif c[pos] == "}":
        depth -= 1

    pos += 1

if depth != 0:
    raise SystemExit(
        "ERRO: não foi possível localizar o fim de Gui::draw()"
    )

draw_end = pos - 1

c = (
    c[:draw_end]
    + "\n"
    + draw_block
    + "\n"
    + c[draw_end:]
)

# ============================================================
# CPP - F12 TOGGLE
# ============================================================

# Remove previous cursor toggle blocks.
c = re.sub(
    r'\n[ \t]*if[ \t]*\('
    r'event\.getKey\(\)\.getValue\(\)[ \t]*==[ \t]*Key::F12'
    r'\)[ \t]*\{'
    r'\s*mSoftwareCursorVisible[ \t]*=[ \t]*'
    r'![ \t]*mSoftwareCursorVisible[ \t]*;'
    r'\s*event\.consume\(\)[ \t]*;'
    r'\s*(?:return;)?'
    r'\s*\}',
    '',
    c,
    flags=re.DOTALL
)

key_function = re.search(
    r'\bvoid\s+Gui::keyPressed\s*\('
    r'\s*gcn::KeyEvent\s*&event\s*\)\s*\{',
    c
)

if not key_function:
    raise SystemExit(
        "ERRO: Gui::keyPressed() não encontrado"
    )

f12_block = '''
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }
'''

key_insert = key_function.end()

c = (
    c[:key_insert]
    + "\n"
    + f12_block
    + c[key_insert:]
)

# ============================================================
# DISABLE NATIVE SDL CURSOR
# ============================================================

c = c.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

header_path.write_text(h)
cpp_path.write_text(c)

print("Software cursor patch aplicado.")
PY

echo
echo "=== SOFTWARE CURSOR VALIDATION ==="

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
from pathlib import Path
import re
import sys

header = Path(sys.argv[1]).read_text()
cpp = Path(sys.argv[2]).read_text()

print("Validando software cursor...")

# ------------------------------------------------------------
# Declaration
# ------------------------------------------------------------

decl = re.findall(
    r'\bResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    header
)

if len(decl) != 1:
    raise SystemExit(
        "ERRO: mSoftwareCursor deveria existir "
        f"exatamente uma vez. Encontrado: {len(decl)}"
    )

print("mSoftwareCursor declaration: OK")

# ------------------------------------------------------------
# Visibility declaration
# ------------------------------------------------------------

visible = re.findall(
    r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    header
)

if len(visible) != 1:
    raise SystemExit(
        "ERRO: mSoftwareCursorVisible deveria existir "
        f"exatamente uma vez. Encontrado: {len(visible)}"
    )

print("mSoftwareCursorVisible declaration: OK")

# ------------------------------------------------------------
# F12
# ------------------------------------------------------------

f12 = re.findall(
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12',
    cpp
)

if len(f12) != 1:
    raise SystemExit(
        "ERRO: F12 deveria existir exatamente uma vez. "
        f"Encontrado: {len(f12)}"
    )

print("F12 binding: OK")

# ------------------------------------------------------------
# Toggle
# ------------------------------------------------------------

toggle = re.search(
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;',
    cpp
)

if not toggle:
    raise SystemExit(
        "ERRO: toggle F12 do cursor não encontrado."
    )

print("F12 toggle: OK")

# ------------------------------------------------------------
# Initialization
# ------------------------------------------------------------

init = re.search(
    r'mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'\s*mTheme->resolvePath\("mouse\.png"\)\s*,'
    r'\s*40\s*,\s*40\s*\)',
    cpp,
    flags=re.DOTALL
)

if not init:
    raise SystemExit(
        "ERRO: inicialização do software cursor não encontrada."
    )

print("Cursor initialization: OK")

# ------------------------------------------------------------
# drawImage
# ------------------------------------------------------------

draw = re.search(
    r'softwareCursorGraphics->drawImage\('
    r'\s*mSoftwareCursor->get\(0\)\s*,'
    r'\s*mMouseX\s*-\s*15\s*,'
    r'\s*mMouseY\s*-\s*17\s*'
    r'\)',
    cpp,
    flags=re.DOTALL
)

if not draw:
    raise SystemExit(
        "ERRO: drawImage() do software cursor não encontrado."
    )

print("drawImage(): OK")

# ------------------------------------------------------------
# IMPORTANT:
# Do NOT reject drawRescaledImage globally.
#
# The Mana GUI can legitimately use drawRescaledImage()
# elsewhere.
#
# We only reject it when it is directly being used with
# mSoftwareCursor->get(0).
# ------------------------------------------------------------

bad_cursor_scale = re.search(
    r'\w+->drawRescaledImage\('
    r'[^;]*mSoftwareCursor->get\(0\)',
    cpp,
    flags=re.DOTALL
)

if bad_cursor_scale:
    raise SystemExit(
        "ERRO CRÍTICO: o software cursor ainda está "
        "usando drawRescaledImage()."
    )

print("Cursor does not use drawRescaledImage(): OK")

# ------------------------------------------------------------
# Native SDL cursor
# ------------------------------------------------------------

if 'SDL_ShowCursor(SDL_ENABLE);' in cpp:
    raise SystemExit(
        "ERRO: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )

print("Native SDL cursor disabled: OK")

print("CURSOR PATCH VALIDATION OK")
PY

echo
echo "=== CONFIGURE BUILD ==="

rm -rf "$BUILD"
mkdir -p "$BUILD"

export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:\
/usr/lib/aarch64-linux-gnu/pkgconfig:\
/usr/share/pkgconfig"

cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON

echo
echo "=== BUILD MANA ==="

JOBS="$(nproc)"

if [ "$JOBS" -gt 4 ]; then
    JOBS=4
fi

echo "Build jobs: $JOBS"

cmake \
    --build "$BUILD" \
    --parallel "$JOBS"

echo
echo "=== LOCATE MANA BINARY ==="

GAME=""

for candidate in \
    "$BUILD/mana" \
    "$BUILD/src/mana" \
    "$BUILD/mana-client" \
    "$BUILD/src/mana-client"
do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        GAME="$candidate"
        break
    fi
done

if [ -z "$GAME" ]; then

    GAME="$(
        find "$BUILD" \
            -type f \
            \( -name 'mana' -o -name 'mana-client' \) \
            -perm -111 \
            | head -n 1 || true
    )"

fi

if [ -z "$GAME" ]; then
    echo "ERRO: binário Mana não encontrado."

    echo
    echo "Executáveis encontrados:"
    find "$BUILD" \
        -type f \
        -perm -111 \
        -print \
        | sort || true

    exit 1
fi

echo "Mana binary:"
echo "$GAME"

echo
echo "=== BINARY INFORMATION ==="

file "$GAME"

echo
echo "=== VERIFY AARCH64 ==="

if ! file "$GAME" | grep -Eiq \
    'ELF.*aarch64|ARM aarch64|ARM64'
then
    echo "ERRO: binário não é AArch64."
    exit 1
fi

echo "AArch64 ELF: OK"

echo
echo "=== VERIFY ELF ==="

readelf -h "$GAME" | sed -n '1,25p'

echo
echo "=== VERIFY GLIBC ==="

GLIBC_VERSIONS="$(
    readelf --version-info "$GAME" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' \
        | sort -Vu \
        | tr '\n' ' ' \
        || true
)"

echo "GLIBC versions:"
echo "$GLIBC_VERSIONS"

if echo "$GLIBC_VERSIONS" | grep -q "GLIBC_2.43"; then
    echo
    echo "ERRO CRÍTICO: GLIBC_2.43 detectado."
    echo "O binário não deve ser enviado ao R36S."
    exit 1
fi

echo "GLIBC compatibility check: OK"

echo
echo "=== PREPARE PORTMASTER PACKAGE ==="

rm -rf "$PORT"

mkdir -p "$PORT"
mkdir -p "$PORT/mana"

echo
echo "Copy binary..."

cp "$GAME" "$PORT/mana/mana.aarch64"

chmod +x "$PORT/mana/mana.aarch64"

echo "mana.aarch64: OK"

echo
echo "=== COPY GAME DATA ==="

if [ ! -d "$SRC/data" ]; then
    echo "ERRO: diretório data/ não encontrado."
    exit 1
fi

cp -a "$SRC/data" "$PORT/mana/"

echo "data/: OK"

echo
echo "=== VERIFY MOUSE IMAGE ==="

MOUSE_IMAGE="$PORT/mana/data/graphics/gui/mouse.png"

if [ ! -f "$MOUSE_IMAGE" ]; then
    echo "ERRO: mouse.png não encontrado:"
    echo "$MOUSE_IMAGE"
    exit 1
fi

echo "mouse.png: OK"

echo
echo "=== CREATE GPTOKEYB CONFIG ==="

cat > "$PORT/mana/mana.gptk" <<'EOF'
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

echo "mana.gptk: OK"

echo
echo "=== CREATE PORTMASTER LAUNCHER ==="

cat > "$PORT/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GAMEDIR="/roms/ports/mana"
PORTDIR="$GAMEDIR/mana"

GAME="$PORTDIR/mana.aarch64"
GAMEDATA="$PORTDIR/data"
CONFDIR="$XDG_CONFIG_HOME/mana"

mkdir -p "$CONFDIR"

# ------------------------------------------------------------
# PortMaster control system
# ------------------------------------------------------------

CONTROL_FILES="
/opt/system/Tools/PortMaster/control.txt
/opt/tools/PortMaster/control.txt
$XDG_DATA_HOME/PortMaster/control.txt
/roms/ports/PortMaster/control.txt
"

for CONTROL_FILE in $CONTROL_FILES
do
    if [ -f "$CONTROL_FILE" ]; then
        . "$CONTROL_FILE"
        break
    fi
done

# ------------------------------------------------------------
# Controller configuration
# ------------------------------------------------------------

if command -v get_controls >/dev/null 2>&1; then
    get_controls
fi

# ------------------------------------------------------------
# GPTOKEYB
# ------------------------------------------------------------

GPTK_PID=""

if [ -n "${GPTOKEYB:-}" ]; then

    "$GPTOKEYB" \
        "$GAME" \
        -c "$PORTDIR/mana.gptk" &

    GPTK_PID=$!

fi

# ------------------------------------------------------------
# Start Mana
# ------------------------------------------------------------

cd "$PORTDIR"

"$GAME" \
    --data "$GAMEDATA" \
    --localdata-dir "$CONFDIR"

STATUS=$?

# ------------------------------------------------------------
# Stop GPTOKEYB
# ------------------------------------------------------------

if [ -n "$GPTK_PID" ]; then
    kill "$GPTK_PID" 2>/dev/null || true
    wait "$GPTK_PID" 2>/dev/null || true
fi

# ------------------------------------------------------------
# PortMaster finish
# ------------------------------------------------------------

if command -v pm_finish >/dev/null 2>&1; then
    pm_finish
fi

exit "$STATUS"
EOF

chmod +x "$PORT/Mana.sh"

echo "Mana.sh: OK"

echo
echo "=== CREATE PORT.JSON ==="

cat > "$PORT/port.json" <<'EOF'
{
  "version": "1.0",
  "name": "mana",
  "items": [
    {
      "name": "The Mana World",
      "label": "The Mana World",
      "type": "port",
      "runner": "Mana.sh",
      "reqs": [],
      "attr": {
        "title": "The Mana World",
        "description": "The Mana World MMORPG client for R36S / PortMaster.",
        "genre": "RPG",
        "players": "1",
        "porter": "Kaddte Real",
        "runtime": "native",
        "arch": "aarch64"
      }
    }
  ]
}
EOF

echo "port.json: OK"

echo
echo "=== CREATE GAMEINFO.XML ==="

cat > "$PORT/gameinfo.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<gameList>
  <game>
    <path>./Mana.sh</path>
    <name>The Mana World</name>
    <desc>The Mana World MMORPG client for R36S / PortMaster.</desc>
    <genre>RPG</genre>
    <players>1</players>
    <publisher>Mana</publisher>
    <developer>Mana</developer>
  </game>
</gameList>
EOF

echo "gameinfo.xml: OK"

echo
echo "=== CREATE README ==="

cat > "$PORT/README.md" <<'EOF'
# The Mana World - R36S PortMaster

Native AArch64 PortMaster build for R36S.

## Controls

D-Pad:
Movement

Left analog:
Movement

Right analog:
Mouse movement

R3:
Left mouse button

L3:
Right mouse button

START:
Enter

A:
Space

B:
Escape

X:
Z

Y:
X

L1:
Shift

R1:
Ctrl

L2:
Home

R2:
End

F12:
Show / hide software cursor

The mouse remains active during gameplay.

The cursor is rendered directly by the Mana client.
EOF

echo "README.md: OK"

echo
echo "=== VERIFY PORT TREE ==="

if [ ! -x "$PORT/Mana.sh" ]; then
    echo "ERRO: Mana.sh não executável."
    exit 1
fi

if [ ! -x "$PORT/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 não executável."
    exit 1
fi

if [ ! -f "$PORT/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk não encontrado."
    exit 1
fi

if [ ! -f "$PORT/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERRO: mouse.png não encontrado."
    exit 1
fi

echo
echo "Port tree:"
find "$PORT" -type f -printf '%M %s %p\n' | sort

echo
echo "=== VERIFY CONTROLLER MAPPING ==="

grep -q '^right_analog_up = mouse_movement_up$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: right analog mouse mapping ausente."
        exit 1
    }

grep -q '^right_analog_down = mouse_movement_down$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: right analog mouse mapping ausente."
        exit 1
    }

grep -q '^right_analog_left = mouse_movement_left$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: right analog mouse mapping ausente."
        exit 1
    }

grep -q '^right_analog_right = mouse_movement_right$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: right analog mouse mapping ausente."
        exit 1
    }

grep -q '^r3 = mouse_left$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: R3 mouse-left ausente."
        exit 1
    }

grep -q '^l3 = mouse_right$' \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: L3 mouse-right ausente."
        exit 1
    }

echo "Right analog mouse: OK"
echo "R3 left click: OK"
echo "L3 right click: OK"

echo
echo "=== CREATE DIAGNOSTICS ==="

DIAGNOSTICS="$DIST/diagnostics.txt"

{
    echo "============================================================"
    echo "Mana R36S AArch64 PortMaster Diagnostics"
    echo "============================================================"
    echo

    echo "Build date:"
    date -u '+%Y-%m-%d %H:%M:%S UTC'
    echo

    echo "Host architecture:"
    uname -m || true
    echo

    echo "Compiler:"
    "${CXX:-g++}" --version | head -n 1 || true
    echo

    echo "CMake:"
    cmake --version | head -n 1 || true
    echo

    echo "Binary:"
    file "$PORT/mana/mana.aarch64"
    echo

    echo "ELF header:"
    readelf -h "$PORT/mana/mana.aarch64" 2>/dev/null || true
    echo

    echo "Dynamic dependencies:"
    readelf -d "$PORT/mana/mana.aarch64" 2>/dev/null \
        | grep -E 'NEEDED|RPATH|RUNPATH' \
        || true

    echo

    echo "GLIBC versions:"
    readelf --version-info "$PORT/mana/mana.aarch64" 2>/dev/null \
        | grep -oE 'GLIBC_[0-9]+\.[0-9]+' \
        | sort -Vu \
        || true

    echo

    echo "Port tree:"
    find "$PORT" \
        -type f \
        -printf '%M %s %p\n' \
        | sort

} > "$DIAGNOSTICS"

echo "diagnostics.txt: OK"

echo
echo "=== CREATE ZIP ==="

ZIP_NAME="$DIST/mana-r36s-portmaster-aarch64.zip"

rm -f
