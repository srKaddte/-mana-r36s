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

if [ -f /usr/include/curl/curl.h ] || \
   [ -f /usr/include/aarch64-linux-gnu/curl/curl.h ] || \
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

# CAMINHO CORRETO
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

if [ ! -f "$GUI_H" ]; then
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

            if stripped.startswith("#include") or stripped == "":
                insert_at += 1
                continue

            break

        lines.insert(
            insert_at,
            '#include "resources/imageset.h"'
        )

        h = "\n".join(lines) + "\n"

# Remove duplicates from previous attempts.

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

# Insert software cursor declarations.

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
# CONSTRUCTOR
# ============================================================

cursor_initialization = '''
    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
'''

# Remove previous initialization if present.

c = re.sub(
    r'\n[ \t]*mSoftwareCursor[ \t]*=[ \t]*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'[^;]*mouse\.png[^;]*\)\s*;\s*',
    '\n',
    c,
    flags=re.DOTALL
)

if 'mSoftwareCursor =' not in c:

    marker = 'setUseCustomCursor(config.customCursor);'

    if marker in c:

        c = c.replace(
            marker,
            marker
            + "\n"
            + cursor_initialization,
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
            + "\n"
            + cursor_initialization
            + c[constructor.end():]
        )

# ============================================================
# DRAW SOFTWARE CURSOR
# ============================================================

# Remove any previous injected software cursor block.

c = re.sub(
    r'\n[ \t]*auto\s+\*softwareCursorGraphics\s*='
    r'\s*static_cast<Graphics\*>\(mGraphics\)\s*;'
    r'\s*if\s*\('
    r'.*?'
    r'mSoftwareCursorVisible'
    r'.*?'
    r'mSoftwareCursor->get\(0\)'
    r'.*?'
    r'\}\s*',
    '\n',
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
        "ERRO: fim de Gui::draw() não encontrado"
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
# F12
# ============================================================

# Remove old F12 cursor toggle blocks.

c = re.sub(
    r'\n[ \t]*if\s*\('
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12'
    r'\)\s*\{'
    r'.*?'
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;'
    r'.*?'
    r'event\.consume\(\)\s*;'
    r'.*?'
    r'(?:return\s*;\s*)?'
    r'\}',
    '\n',
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

c = (
    c[:key_function.end()]
    + "\n"
    + f12_block
    + c[key_function.end():]
)

# ============================================================
# NATIVE SDL CURSOR
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

# ============================================================
# DECLARATION
# ============================================================

decl = re.findall(
    r'\bResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    header
)

if len(decl) != 1:
    raise SystemExit(
        "ERRO: mSoftwareCursor deveria existir exatamente "
        f"uma vez. Encontrado: {len(decl)}"
    )

print("mSoftwareCursor declaration: OK")

# ============================================================
# VISIBILITY
# ============================================================

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

# ============================================================
# F12
# ============================================================

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

# ============================================================
# TOGGLE
# ============================================================

toggle = re.search(
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;',
    cpp
)

if not toggle:
    raise SystemExit(
        "ERRO: toggle F12 do cursor não encontrado."
    )

print("F12 toggle: OK")

# ============================================================
# CURSOR INITIALIZATION
#
# Não exigimos uma formatação específica.
# Procuramos os três elementos necessários:
# mSoftwareCursor + getImageSet + mouse.png
# ============================================================

init_pattern = re.compile(
    r'mSoftwareCursor\s*='
    r'.{0,1000}?'
    r'getImageSet\s*\('
    r'.{0,1000}?'
    r'mouse\.png'
    r'.{0,1000}?\)',
    flags=re.DOTALL
)

if not init_pattern.search(cpp):
    raise SystemExit(
        "ERRO: inicialização do software cursor não encontrada."
    )

print("Cursor initialization: OK")

# ============================================================
# drawImage DO CURSOR
# ============================================================

draw = re.search(
    r'softwareCursorGraphics\s*->\s*drawImage\s*\('
    r'\s*mSoftwareCursor\s*->\s*get\s*\(\s*0\s*\)\s*,'
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

# ============================================================
# drawRescaledImage
#
# NÃO rejeitar globalmente.
#
# O Mana pode usar drawRescaledImage normalmente em outras
# partes da interface.
#
# Só rejeitamos se o software cursor estiver usando essa
# função especificamente.
# ============================================================

bad_cursor_scale = re.search(
    r'\w+\s*->\s*drawRescaledImage\s*\('
    r'[^;]*?'
    r'mSoftwareCursor\s*->\s*get\s*\(\s*0\s*\)',
    cpp,
    flags=re.DOTALL
)

if bad_cursor_scale:
    raise SystemExit(
        "ERRO CRÍTICO: o software cursor ainda está "
        "usando drawRescaledImage()."
    )

print("Cursor does not use drawRescaledImage(): OK")

# ============================================================
# NATIVE SDL CURSOR
# ============================================================

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
    )

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
echo "$
