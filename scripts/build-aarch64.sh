#!/bin/bash
set -e

ROOT="/workspace"
SOURCE_DIR="$ROOT/source"
PORT_DIR="$ROOT/port"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
WORK_DIR="$ROOT/work"

echo "=========================================="
echo " Mana R36S - AArch64 PortMaster Builder"
echo "=========================================="

rm -rf "$BUILD_DIR" "$WORK_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$WORK_DIR" "$DIST_DIR"

echo
echo "=== Locating Mana source ==="

SRC_TAR="$SOURCE_DIR/mana-master.tar.gz"

if [ ! -f "$SRC_TAR" ]; then
    echo "ERROR: não encontrei:"
    echo "  $SRC_TAR"
    echo
    echo "Arquivos encontrados em source/:"
    ls -lah "$SOURCE_DIR" || true
    exit 1
fi

echo "Source encontrado:"
ls -lh "$SRC_TAR"

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

echo
echo "=== Checking source ==="

if [ ! -f "$SRC/src/CMakeLists.txt" ]; then
    echo "ERROR: src/CMakeLists.txt não encontrado."
    exit 1
fi

echo
echo "=== Patching SDL2_ttf requirement ==="

python3 - "$SRC/src/CMakeLists.txt" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

s2 = s.replace(
    "SDL2_ttf>=2.0.18",
    "SDL2_ttf>=2.0.15"
)

if s2 == s:
    print("SDL2_ttf requirement já estava compatível ou não foi encontrado.")
else:
    with open(path, "w", encoding="utf-8") as f:
        f.write(s2)
    print("SDL2_ttf requirement corrigido para 2.0.15.")

PY

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
    if [ -d "$d/include" ] || [ -f "$d/CMakeLists.txt" ] || [ -f "$d/Makefile.am" ]; then
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

echo "=== Guichan OK ==="

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
    if [ -f "$d/CMakeLists.txt" ] || [ -f "$d/Makefile.am" ]; then
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

echo "=== ENet OK ==="

echo
echo "=== Patching TrueTypeFont for R36S SDL_ttf ==="

TTF="$SRC/src/gui/truetypefont.cpp"

if [ ! -f "$TTF" ]; then
    echo "ERROR: não encontrei:"
    echo "  $TTF"
    exit 1
fi

python3 - "$TTF" <<'PY'
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

old1 = """        TTF_SetFontSize(font->mFont, font->mPointSize * mScale);
"""

old2 = """        TTF_SetFontSize(font->mFontOutline, font->mPointSize * mScale);
"""

count1 = s.count(old1)
count2 = s.count(old2)

if count1:
    s = s.replace(old1, "")

if count2:
    s = s.replace(old2, "")

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

print("Removidas chamadas TTF_SetFontSize incompatíveis:")
print("  mFont =", count1)
print("  mFontOutline =", count2)

PY

echo
echo "=== Patching R36S software cursor ==="

GUI_H="$SRC/src/gui/gui.h"
GUI_CPP="$SRC/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ]; then
    echo "ERROR: gui.h não encontrado."
    exit 1
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERROR: gui.cpp não encontrado."
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys
import re

header = sys.argv[1]
source = sys.argv[2]

with open(header, "r", encoding="utf-8") as f:
    h = f.read()

with open(source, "r", encoding="utf-8") as f:
    c = f.read()

# ------------------------------------------------------------
# gui.h
# ------------------------------------------------------------

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

# Remove qualquer declaração antiga criada por tentativa anterior.
h = re.sub(
    r'^\s*ResourceRef<Image>\s+mSoftwareCursor;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^\s*ResourceRef<ImageSet>\s+mSoftwareCursor;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

h = re.sub(
    r'^\s*bool\s+mSoftwareCursorVisible\s*=\s*true;\s*$\n?',
    '',
    h,
    flags=re.MULTILINE
)

# Insere os membros perto do estado do cursor.
marker = 'Cursor mCursorType = Cursor::Pointer;'

if marker not in h:
    raise SystemExit(
        "ERROR: não encontrei 'Cursor mCursorType = Cursor::Pointer;' em gui.h"
    )

replacement = """Cursor mCursorType = Cursor::Pointer;

    ResourceRef<ImageSet> mSoftwareCursor;
    bool mSoftwareCursorVisible = true;"""

h = h.replace(marker, replacement, 1)

with open(header, "w", encoding="utf-8") as f:
    f.write(h)

# ------------------------------------------------------------
# gui.cpp
# ------------------------------------------------------------

# Remove alterações anteriores de cursor de software, se existirem.
c = re.sub(
    r'\n\s*mSoftwareCursor\s*=\s*ResourceManager::getInstance\(\)->getImageSet\(\s*'
    r'mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);\s*',
    '\n',
    c,
    flags=re.MULTILINE
)

c = re.sub(
    r'\n\s*SDL_ShowCursor\(SDL_DISABLE\);\s*',
    '\n',
    c
)

# Remove possíveis blocos anteriores de desenho do cursor.
c = re.sub(
    r'\n\s*if\s*\(\s*mSoftwareCursorVisible\s*&&\s*'
    r'mSoftwareCursor\s*&&\s*'
    r'mSoftwareCursor->size\(\)\s*>\s*0\s*\)\s*\{\s*'
    r'graphics->drawImage\(\s*'
    r'mSoftwareCursor->get\(0\),\s*'
    r'mMouseX\s*-\s*15,\s*'
    r'mMouseY\s*-\s*17\s*'
    r'\);\s*\}\s*',
    '\n',
    c,
    flags=re.MULTILINE
)

# Remove possíveis toggles anteriores.
c = re.sub(
    r'\n\s*mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;\s*',
    '\n',
    c
)

# ------------------------------------------------------------
# Constructor
# ------------------------------------------------------------

constructor_marker = 'setUseCustomCursor(config.customCursor);'

if constructor_marker not in c:
    raise SystemExit(
        "ERROR: não encontrei setUseCustomCursor(config.customCursor);"
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

# ------------------------------------------------------------
# Gui::draw()
# ------------------------------------------------------------

draw_marker = """    gcn::Gui::draw();"""

if draw_marker not in c:
    raise SystemExit(
        "ERROR: não encontrei gcn::Gui::draw(); em Gui::draw()."
    )

draw_patch = """    gcn::Gui::draw();

    if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);
    }"""

c = c.replace(
    draw_marker,
    draw_patch,
    1
)

# ------------------------------------------------------------
# F12 toggle
# ------------------------------------------------------------

key_marker = """void Gui::keyPressed(const gcn::KeyEvent &event)
{"""

if key_marker not in c:
    raise SystemExit(
        "ERROR: não encontrei Gui::keyPressed()."
    )

f12_block = """void Gui::keyPressed(const gcn::KeyEvent &event)
{
    if (event.getKey().getValue() == gcn::Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;
        return;
    }"""

c = c.replace(
    key_marker,
    f12_block,
    1
)

# ------------------------------------------------------------
# R36S não possui X11/compositor.
# Mantém SDL hardware cursor desligado.
# ------------------------------------------------------------

c = c.replace(
    'SDL_ShowCursor(SDL_ENABLE);',
    'SDL_ShowCursor(SDL_DISABLE);'
)

with open(source, "w", encoding="utf-8") as f:
    f.write(c)

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

with open(header, "r", encoding="utf-8") as f:
    h = f.read()

with open(source, "r", encoding="utf-8") as f:
    c = f.read()

if len(re.findall(
    r'ResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    h
)) != 1:
    raise SystemExit(
        "ERROR: declaração mSoftwareCursor inválida."
    )

if len(re.findall(
    r'bool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    h
)) != 1:
    raise SystemExit(
        "ERROR: declaração mSoftwareCursorVisible inválida."
    )

if len(re.findall(
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*gcn::Key::F12',
    c
)) != 1:
    raise SystemExit(
        "ERROR: F12 não encontrado exatamente uma vez."
    )

if not re.search(
    r'mSoftwareCursorVisible\s*=\s*!\s*mSoftwareCursorVisible\s*;',
    c
):
    raise SystemExit(
        "ERROR: toggle F12 não encontrado."
    )

if not re.search(
    r'getImageSet\(\s*'
    r'mTheme->resolvePath\("mouse\.png"\)\s*,\s*40\s*,\s*40\s*\)',
    c,
    flags=re.DOTALL
):
    raise SystemExit(
        "ERROR: inicialização do cursor não encontrada."
    )

if 'graphics->drawImage(' not in c:
    raise SystemExit(
        "ERROR: drawImage do cursor não encontrado."
    )

if 'SDL_ShowCursor(SDL_ENABLE);' in c:
    raise SystemExit(
        "ERROR: SDL cursor enable ainda presente."
    )

print("R36S software cursor validation: OK")

PY

echo
echo "=== Software cursor OK ==="

echo
echo "=== Configuring AArch64 build ==="

cd "$BUILD_DIR"

cmake "$SRC" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DENABLE_TESTS=OFF \
    -DBUILD_TESTS=OFF

echo
echo "=== Building Mana ==="

JOBS="$(nproc)"

if [ "$JOBS" -gt 4 ]; then
    JOBS=4
fi

cmake --build . --parallel "$JOBS"

echo
echo "=== Locating Mana executable ==="

GAME=""

for candidate in \
    "$BUILD_DIR/mana" \
    "$BUILD_DIR/mana.aarch64" \
    "$BUILD_DIR/src/mana" \
    "$BUILD_DIR/src/mana.aarch64"
do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        GAME="$candidate"
        break
    fi
done

if [ -z "$GAME" ]; then
    GAME="$(find "$BUILD_DIR" -type f \
        \( -name "mana" -o -name "mana.aarch64" \) \
        -perm -111 \
        | head -1 || true)"
fi

if [ -z "$GAME" ]; then
    echo "ERROR: executável Mana não encontrado."
    echo
    echo "Executáveis encontrados:"
    find "$BUILD_DIR" -type f -perm -111 -print || true
    exit 1
fi

echo "GAME=$GAME"

file "$GAME" || true

echo
echo "=== Checking architecture ==="

if ! file "$GAME" | grep -qiE 'ARM aarch64|ARM64'; then
    echo "ERROR: o executável não parece ser AArch64."
    exit 1
fi

echo "AArch64 OK"

echo
echo "=== Creating PortMaster package ==="

PACKAGE_ROOT="$WORK_DIR/package"

rm -rf "$PACKAGE_ROOT"

mkdir -p "$PACKAGE_ROOT/mana"

cp "$GAME" "$PACKAGE_ROOT/mana/mana.aarch64"

chmod +x "$PACKAGE_ROOT/mana/mana.aarch64"

echo
echo "=== Copying Mana data ==="

if [ -d "$SRC/data" ]; then
    cp -a "$SRC/data" "$PACKAGE_ROOT/mana/"
else
    echo "WARNING: diretório data não encontrado no source."
fi

echo
echo "=== Creating PortMaster launcher ==="

cat > "$PACKAGE_ROOT/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

GAMEDIR="/roms/ports/mana"
CONFDIR="$XDG_CONFIG_HOME/mana"
GAMEDATA="$GAMEDIR/mana/data"

mkdir -p "$CONFDIR"

cd "$GAMEDIR/mana"

# PortMaster control system
if [ -f "/opt/system/Tools/PortMaster/control.txt" ]; then
    source "/opt/system/Tools/PortMaster/control.txt"
fi

if [ -f "/opt/system/Tools/PortMaster/libs/portmaster.control.txt" ]; then
    source "/opt/system/Tools/PortMaster/libs/portmaster.control.txt"
fi

# Resolve helpers when available.
if command -v get_controls >/dev/null 2>&1; then
    get_controls
fi

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -x "$GAME" ]; then
    echo "Mana executable not found:"
    echo "$GAME"
    exit 1
fi

# Preserve the known working R36S control mapping.
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

echo
echo "=== Creating ZIP ==="

cd "$PACKAGE_ROOT"

ZIP="$DIST_DIR/mana-r36s-aarch64-portmaster.zip"

zip -r "$ZIP" \
    Mana.sh \
    mana \
    port.json \
    gameinfo.xml

echo
echo "=== Generating diagnostics ==="

DIAG="$DIST_DIR/diagnostics.txt"

{
    echo "Mana R36S AArch64 PortMaster diagnostics"
    echo
    echo "Source archive:"
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
    echo "SDL libraries:"
    ldd "$GAME" 2>/dev/null |
        grep -Ei 'SDL|ttf|enet|guichan' || true
    echo
    echo "Package:"
    ls -lh "$ZIP"
} > "$DIAG"

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
