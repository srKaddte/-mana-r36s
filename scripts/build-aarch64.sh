#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo " Mana 0.8.0 - R36S / PortMaster AArch64 Builder"
echo "============================================================"

ROOT="$(pwd)"
SOURCE_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/work"
SRCROOT="$WORK"
BUILD="$WORK/build"
DIST="$ROOT/dist"
PORT="$WORK/port"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST" "$PORT"

echo
echo "=== CHECK SOURCE ==="

if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "ERRO: source/mana-master.tar.gz não encontrado."
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
    file \
    python3 \
    python3-pip \
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

if ldconfig -p | grep -q "libphysfs"; then
    echo "PhysFS: OK"
else
    echo "ERRO: PhysFS não encontrado."
    exit 1
fi

if ldconfig -p | grep -q "libcurl"; then
    echo "CURL: OK"
else
    echo "ERRO: CURL não encontrado."
    exit 1
fi

if ldconfig -p | grep -q "libxml2"; then
    echo "LibXml2: OK"
else
    echo "ERRO: LibXml2 não encontrado."
    exit 1
fi

if [ -f /usr/include/curl/curl.h ] ||
   [ -f /usr/include/aarch64-linux-gnu/curl/curl.h ] ||
   [ -f /usr/include/arm-linux-gnueabihf/curl/curl.h ]; then
    echo "CURL headers: OK"
else
    echo "ERRO: headers CURL não encontrados."
    exit 1
fi

if [ -f /usr/include/libxml2/libxml/parser.h ]; then
    echo "LibXml2 headers: OK"
else
    echo "ERRO: headers LibXml2 não encontrados."
    exit 1
fi

if [ -f /usr/include/physfs.h ]; then
    echo "PhysFS headers: OK"
else
    echo "ERRO: headers PhysFS não encontrados."
    exit 1
fi

echo
echo "=== EXTRACT SOURCE ==="

tar -xzf "$SOURCE_ARCHIVE" -C "$WORK"

SOURCE_DIR="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'mana-*' | head -n 1 || true)"

if [ -z "$SOURCE_DIR" ]; then
    echo "ERRO: diretório do source do Mana não encontrado."
    find "$WORK" -maxdepth 2 -type d -print
    exit 1
fi

SRC="$SOURCE_DIR"

echo "Source directory:"
echo "$SRC"

echo
echo "=== SOURCE STRUCTURE ==="

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
echo "=== DOWNLOAD BUNDLED GUICHAN ==="

mkdir -p "$SRC/libs"

GUICHAN_URL="https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$SRC/libs/guichan" "$WORK/guichan"

wget -q --show-progress \
    "$GUICHAN_URL" \
    -O "$WORK/guichan.tar.gz"

tar -xzf "$WORK/guichan.tar.gz" -C "$WORK"

GUICHAN_DIR="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'guichan-*' | head -n 1 || true)"

if [ -z "$GUICHAN_DIR" ]; then
    echo "ERRO: Guichan não foi extraído."
    exit 1
fi

mv "$GUICHAN_DIR" "$SRC/libs/guichan"

echo "Guichan: OK"

echo
echo "=== DOWNLOAD BUNDLED ENET ==="

ENET_URL="https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$SRC/libs/enet" "$WORK/enet"

wget -q --show-progress \
    "$ENET_URL" \
    -O "$WORK/enet.tar.gz"

tar -xzf "$WORK/enet.tar.gz" -C "$WORK"

ENET_DIR="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'enet-*' | head -n 1 || true)"

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

text2 = re.sub(
    r'(find_package\s*\(\s*SDL2_ttf\s+)[0-9]+\.[0-9]+\.[0-9]+',
    r'\g<1>2.0.15',
    text,
    count=1
)

if text2 != text:
    path.write_text(text2)
    print("SDL2_ttf requirement patched to 2.0.15")
else:
    print("SDL2_ttf requirement already compatible or not found")
PY

echo
echo "=== PATCH TRUE TYPE FONT ==="

TTF_FILE="$SRC/src/gui/fonts/truetypefont.cpp"

if [ ! -f "$TTF_FILE" ]; then
    echo "ERRO: truetypefont.cpp não encontrado."
    find "$SRC/src" -iname 'truetypefont.cpp' -print
    exit 1
fi

python3 - "$TTF_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = r'''
        TTF_SetFontSize(font->mFont, font->mPointSize * mScale);
        TTF_SetFontSize(font->mFontOutline, font->mPointSize * mScale);
'''

if old in text:
    text = text.replace(old, "")
    path.write_text(text)
    print("TTF_SetFontSize scaling calls removed")
else:
    print("TTF_SetFontSize scaling block not found; leaving source unchanged")
PY

echo
echo "=== SOFTWARE CURSOR PATCH ==="

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

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
from pathlib import Path
import re
import sys

header_path = Path(sys.argv[1])
cpp_path = Path(sys.argv[2])

h = header_path.read_text()
c = cpp_path.read_text()

print("Preparando patch do cursor de software...")

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

if '#include "resources/imageset.h"' not in h:
    marker = '#include "gui/widgets/container.h"'

    if marker in h:
        h = h.replace(
            marker,
            '#include "resources/imageset.h"\n' + marker,
            1
        )
    else:
        # Fallback seguro: adiciona depois dos includes iniciais.
        lines = h.splitlines()
        pos = 0

        while pos < len(lines) and (
            lines[pos].startswith("#include") or
            lines[pos].strip() == ""
        ):
            pos += 1

        lines.insert(pos, '#include "resources/imageset.h"')
        h = "\n".join(lines) + ("\n" if h.endswith("\n") else "")

# Remove declarações anteriores do cursor de software para evitar
# redeclaration caso o source já contenha uma versão parcial.
h = re.sub(
    r'^\s*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;\s*\n',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^\s*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*\n',
    '',
    h,
    flags=re.MULTILINE
)

# Insere as declarações dentro da classe Gui.
if 'ResourceRef<ImageSet> mSoftwareCursor;' not in h:
    class_match = re.search(
        r'(class\s+Gui\b.*?\n)',
        h,
        flags=re.DOTALL
    )

    if not class_match:
        raise SystemExit("ERRO: classe Gui não encontrada em gui.h")

    # Procuramos uma área típica de membros.
    candidate = re.search(
        r'(\n\s*Cursor\s+mCursorType\s*=\s*Cursor::Pointer\s*;\s*)',
        h
    )

    if candidate:
        insertion = (
            candidate.group(1)
            + '\n'
            + '    ResourceRef<ImageSet> mSoftwareCursor;\n'
            + '    bool mSoftwareCursorVisible = true;\n'
        )
        h = h[:candidate.start()] + insertion + h[candidate.end():]
    else:
        # Fallback: insere antes do último }; da classe.
        class_start = class_match.start()
        class_end = h.find("};", class_start)

        if class_end == -1:
            raise SystemExit("ERRO: fim da classe Gui não encontrado")

        h = (
            h[:class_end]
            + '    ResourceRef<ImageSet> mSoftwareCursor;\n'
            + '    bool mSoftwareCursorVisible = true;\n'
            + h[class_end:]
        )

# ------------------------------------------------------------
# CPP - CONSTRUCTOR
# ------------------------------------------------------------

cursor_init = '''    mSoftwareCursor =
        ResourceManager::getInstance()->getImageSet(
            mTheme->resolvePath("mouse.png"), 40, 40);
    SDL_ShowCursor(SDL_DISABLE);
'''

# Remove qualquer inicialização anterior do nosso cursor.
c = re.sub(
    r'\s*mSoftwareCursor\s*=\s*ResourceManager::getInstance\(\)->getImageSet\(\s*'
    r'mTheme->resolvePath\("mouse\.png"\)\s*,\s*40\s*,\s*40\s*\)\s*;\s*',
    '\n',
    c
)

# Remove duplicações de SDL disable introduzidas pelo patch.
c = re.sub(
    r'(\s*)SDL_ShowCursor\(SDL_DISABLE\);\s*'
    r'(\n\s*SDL_ShowCursor\(SDL_DISABLE\);)+',
    r'\1SDL_ShowCursor(SDL_DISABLE);',
    c
)

if 'mSoftwareCursor =' not in c:
    # O constructor original chama setUseCustomCursor(config.customCursor).
    marker = 'setUseCustomCursor(config.customCursor);'

    if marker in c:
        c = c.replace(
            marker,
            marker
            + '\n\n'
            + cursor_init.rstrip(),
            1
        )
    else:
        # Fallback: primeiro constructor de Gui.
        constructor = re.search(
            r'(Gui::Gui\s*\([^)]*\)\s*\{)',
            c
        )

        if not constructor:
            raise SystemExit(
                "ERRO: constructor Gui::Gui não encontrado para inicializar cursor"
            )

        c = (
            c[:constructor.end()]
            + '\n\n'
            + cursor_init.rstrip()
            + '\n'
            + c[constructor.end():]
        )

# ------------------------------------------------------------
# CPP - DRAW
# ------------------------------------------------------------

# Remove versões anteriores do bloco do cursor.
c = re.sub(
    r'\n\s*auto\s*\*softwareCursorGraphics\s*=\s*'
    r'static_cast<Graphics\*>\(mGraphics\);\s*'
    r'\n\s*if\s*\(\s*softwareCursorGraphics\s*&&\s*'
    r'mSoftwareCursorVisible\s*&&\s*'
    r'mSoftwareCursor\s*&&\s*'
    r'mSoftwareCursor->size\(\)\s*>\s*0\s*\)\s*\{\s*'
    r'\n\s*softwareCursorGraphics->draw(?:Rescaled)?Image\([^;]*\);\s*'
    r'\n\s*\}',
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

# Insere no final de Gui::draw(), antes da chave que fecha a função.
draw_match = re.search(
    r'void\s+Gui::draw\s*\(\s*\)\s*\{',
    c
)

if not draw_match:
    raise SystemExit("ERRO: Gui::draw() não encontrado")

# Encontra a chave correspondente ao constructor/função.
start = draw_match.end()
depth = 1
i = start

while i < len(c) and depth:
    if c[i] == '{':
        depth += 1
    elif c[i] == '}':
        depth -= 1
    i += 1

if depth != 0:
    raise SystemExit("ERRO: não foi possível localizar fim de Gui::draw()")

draw_end = i - 1

c = c[:draw_end] + '\n' + draw_block + '\n' + c[draw_end:]

# ------------------------------------------------------------
# CPP - F12 TOGGLE
# ------------------------------------------------------------

# Remove qualquer toggle anterior.
c = re.sub(
    r'\n\s*if\s*\(\s*event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12\s*\)'
    r'\s*\{\s*'
    r'mSoftwareCursorVisible\s*=\s*!mSoftwareCursorVisible\s*;'
    r'\s*event\.consume\(\)\s*;\s*'
    r'\}',
    '',
    c,
    flags=re.DOTALL
)

key_match = re.search(
    r'void\s+Gui::keyPressed\s*\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{',
    c
)

if not key_match:
    raise SystemExit("ERRO: Gui::keyPressed() não encontrado")

key_start = key_match.end()

f12_block = '''
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        event.consume();
        return;
    }
'''

c = c[:key_start] + f12_block + c[key_start:]

# ------------------------------------------------------------
# SDL CURSOR
# ------------------------------------------------------------

# O R36S não usa cursor X11/compositor.
# O cursor é desenhado pelo próprio Mana.
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
cpp = Path(sys.argv[2])

print("Validando cursor de software...")

decl = re.findall(
    r'\bResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    header
)

if len(decl) != 1:
    raise SystemExit(
        f"ERRO: mSoftwareCursor deveria existir exatamente 1 vez; "
        f"encontrado: {len(decl)}"
    )

print("mSoftwareCursor declaration: OK")

visible = re.findall(
    r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    header
)

if len(visible) != 1:
    raise SystemExit(
        f"ERRO: mSoftwareCursorVisible deveria existir exatamente 1 vez; "
        f"encontrado: {len(visible)}"
    )

print("mSoftwareCursorVisible declaration: OK")

f12 = re.findall(
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12',
    cpp
)

if len(f12) != 1:
    raise SystemExit(
        f"ERRO: binding F12 deveria existir exatamente 1 vez; "
        f"encontrado: {len(f12)}"
    )

print("F12 binding: OK")

toggle = re.search(
    r'mSoftwareCursorVisible\s*=\s*!mSoftwareCursorVisible\s*;',
    cpp
)

if not toggle:
    raise SystemExit(
        "ERRO: toggle F12 do cursor não encontrado."
    )

print("F12 toggle: OK")

init = re.search(
    r'mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'\s*mTheme->resolvePath\("mouse\.png"\)\s*,\s*40\s*,\s*40\s*\)',
    cpp
)

if not init:
    raise SystemExit(
        "ERRO: inicialização do software cursor não encontrada."
    )

print("Cursor initialization: OK")

draw = re.search(
    r'softwareCursorGraphics->drawImage\(\s*'
    r'mSoftwareCursor->get\(0\)\s*,\s*'
    r'mMouseX\s*-\s*15\s*,\s*'
    r'mMouseY\s*-\s*17\s*'
    r'\)',
    cpp,
    flags=re.DOTALL
)

if not draw:
    raise SystemExit(
        "ERRO: drawImage() do software cursor não encontrado."
    )

print("drawImage(): OK")

# IMPORTANTE:
# Não podemos rejeitar drawRescaledImage() no gui.cpp inteiro.
# O Mana pode usá-lo legitimamente em outras partes da GUI.
#
# Aqui verificamos SOMENTE se existe drawRescaledImage aplicado
# diretamente ao mSoftwareCursor.
bad_cursor_scale = re.search(
    r'\w+->drawRescaledImage\([^;]*mSoftwareCursor->get\(0\)',
    cpp,
    flags=re.DOTALL
)

if bad_cursor_scale:
    raise SystemExit(
        "ERRO CRÍTICO: o software cursor ainda está usando "
        "drawRescaledImage()."
    )

print("Cursor does not use drawRescaledImage(): OK")

if 'SDL_ShowCursor(SDL_ENABLE);' in cpp:
    raise SystemExit(
        "ERRO: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )

print("SDL cursor remains disabled: OK")

print("CURSOR PATCH VALIDATION OK")
PY

echo
echo "=== CONFIGURE CMAKE ==="

rm -rf "$BUILD"
mkdir -p "$BUILD"

export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"

cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DCMAKE_C_FLAGS="-O2" \
    -DCMAKE_CXX_FLAGS="-O2"

echo
echo "=== BUILD ==="

JOBS="$(nproc)"

if [ "$JOBS" -gt 4 ]; then
    JOBS=4
fi

cmake --build "$BUILD" --parallel "$JOBS"

echo
echo "=== LOCATE MANA BINARY ==="

GAME=""

for candidate in \
    "$BUILD/mana" \
    "$BUILD/src/mana" \
    "$BUILD/src/mana-client" \
    "$BUILD/mana-client"
do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        GAME="$candidate"
        break
    fi
done

if [ -z "$GAME" ]; then
    GAME="$(find "$BUILD" -type f \
        \( -name 'mana' -o -name 'mana-client' \) \
        -perm -111 \
        | head -n 1 || true)"
fi

if [ -z "$GAME" ]; then
    echo "ERRO: binário Mana não encontrado."
    echo
    echo "Executáveis encontrados:"
    find "$BUILD" -type f -perm -111 -print | sort || true
    exit 1
fi

echo "Mana binary:"
echo "$GAME"

file "$GAME"

echo
echo "=== CHECK ELF ==="

file "$GAME" | grep -Eiq 'ELF.*aarch64|ARM aarch64|ARM64' || {
    echo "ERRO: binário não parece ser AArch64."
    exit 1
}

echo "AArch64 ELF: OK"

echo
echo "=== PREPARE PORTMASTER PACKAGE ==="

rm -rf "$PORT"
mkdir -p "$PORT/mana"

cp "$GAME" "$PORT/mana/mana.aarch64"
chmod +x "$PORT/mana/mana.aarch64"

echo
echo "=== COPY GAME DATA ==="

if [ -d "$SRC/data" ]; then
    cp -a "$SRC/data" "$PORT/mana/"
else
    echo "ERRO: diretório data/ não encontrado no source."
    exit 1
fi

echo
echo "=== VERIFY MOUSE IMAGE ==="

MOUSE_IMAGE="$PORT/mana/data/graphics/gui/mouse.png"

if [ ! -f "$MOUSE_IMAGE" ]; then
    echo "ERRO: data/graphics/gui/mouse.png não encontrado."
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
echo "=== CREATE PORT LAUNCHER ==="

cat > "$PORT/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

directory="$(dirname "$0")"
directory="$(cd "$directory" && pwd)"

PORTDIR="$directory/mana"
GAME="$PORTDIR/mana.aarch64"

GAMEDIR="/roms/ports/mana"
GAMEDATA="$GAMEDIR/mana/data"
CONFDIR="$XDG_CONFIG_HOME/mana"

mkdir -p "$CONFDIR"

if [ -f "/opt/system/Tools/PortMaster/control.txt" ]; then
    . "/opt/system/Tools/PortMaster/control.txt"
fi

if [ -f "$PORTDIR/mana.gptk" ]; then
    MOD="$PORTDIR/mana.gptk"
fi

if command -v get_controls >/dev/null 2>&1; then
    get_controls
fi

if [ -n "${GPTOKEYB:-}" ]; then
    "$GPTOKEYB" "$GAME" -c "$PORTDIR/mana.gptk" &
    GPTK_PID=$!
else
    GPTK_PID=""
fi

cd "$PORTDIR"

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
        "description": "The Mana World MMORPG client for PortMaster / R36S.",
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

- D-Pad: movement
- Left analog: movement
- Right analog: mouse
- R3: left mouse button
- L3: right mouse button
- START: Enter
- A: Space
- B: Escape
- X: Z
- Y: X
- L1: Shift
- R1: Ctrl
- L2: Home
- R2: End
- F12: toggle software cursor visibility

The mouse remains active during gameplay.

The cursor is rendered by the Mana client itself because the R36S environment does not require an X11 compositor.
EOF

echo
echo "=== CREATE DIAGNOSTICS ==="

{
    echo "Mana R36S AArch64 PortMaster diagnostics"
    echo
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo
    echo "Architecture:"
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
    echo "Binary dependencies:"
    if command -v readelf >/dev/null 2>&1; then
        readelf -d "$PORT/mana/mana.aarch64" 2>/dev/null \
            | grep -E 'NEEDED|RPATH|RUNPATH' || true
    fi
    echo
    echo "Package files:"
    find "$PORT" -type f -printf '%M %s %p\n' | sort
} > "$DIST/diagnostics.txt"

echo
echo "=== PACKAGE MANIFEST ==="

find "$PORT" -type f -printf '%M %s %p\n' | sort

echo
echo "=== CREATE ZIP ==="

ZIP_NAME="$DIST/mana-r36s-portmaster-aarch64.zip"

(
    cd "$PORT"
    zip -r -9 "$ZIP_NAME" .
)

echo
echo "=== ZIP CREATED ==="

ls -lh "$ZIP_NAME"

echo
echo "=== FINAL VALIDATION ==="

if [ ! -s "$ZIP_NAME" ]; then
    echo "ERRO: ZIP final está vazio."
    exit 1
fi

if [ ! -s "$DIST/diagnostics.txt" ]; then
    echo "ERRO: diagnostics.txt está vazio."
    exit 1
fi

unzip -t "$ZIP_NAME" >/dev/null

echo "ZIP integrity: OK"
echo "Diagnostics: OK"
echo "PortMaster package: OK"

echo
echo "============================================================"
echo " BUILD CONCLUÍDO"
echo "============================================================"
echo
echo "ZIP:"
echo "$ZIP_NAME"
echo
echo "Diagnostics:"
echo "$DIST/diagnostics.txt"
echo
echo "Arquivos finais:"
find "$PORT" -maxdepth 3 -type f -print | sort
echo
