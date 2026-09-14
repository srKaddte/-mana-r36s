#!/bin/bash
set -e

ROOT="/workspace"
SOURCE_DIR="$ROOT/source"
SRC_TAR="$SOURCE_DIR/mana-master.tar.gz"

BUILD_DIR="$ROOT/build"
INSTALL_DIR="$ROOT/install"
DIST_DIR="$ROOT/dist"
PORT_DIR="$ROOT/port"

echo "=========================================="
echo " Mana R36S - AArch64 PortMaster Builder"
echo "=========================================="
echo

rm -rf "$BUILD_DIR"
rm -rf "$INSTALL_DIR"
rm -rf "$DIST_DIR"

mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$PORT_DIR"

echo "=== Instalando dependencias ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    git \
    zip \
    file \
    binutils \
    pkg-config \
    python3 \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext

echo
echo "=== Verificando dependencias ==="
echo

echo "--- SDL2 ---"
pkg-config --modversion sdl2 || true

echo
echo "--- SDL2_image ---"
pkg-config --modversion SDL2_image || true

echo
echo "--- SDL2_mixer ---"
pkg-config --modversion SDL2_mixer || true

echo
echo "--- SDL2_net ---"
pkg-config --modversion SDL2_net || true

echo
echo "--- SDL2_ttf ---"
pkg-config --modversion SDL2_ttf || true

echo
echo "--- PhysFS ---"
pkg-config --modversion physfs || true

echo
echo "--- libxml2 ---"
pkg-config --modversion libxml-2.0 || true

echo

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

echo "=== Extraindo Mana ==="

tar -xzf "$SRC_TAR" -C "$BUILD_DIR"

SRC_DIR="$(find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: diretorio do source nao encontrado."
    exit 1
fi

echo "SRC_DIR=$SRC_DIR"
echo

echo "=========================================="
echo " Aplicando compatibilidade SDL2_ttf"
echo "=========================================="
echo

TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: $TRUETYPE_CPP nao encontrado."
    exit 1
fi

python3 - "$TRUETYPE_CPP" <<'PY'
import sys
import re

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

pattern = re.compile(
    r"TTF_SetFontSize\([^;]*\);"
)

text2, count = pattern.subn("", text)

if count != 2:
    raise SystemExit(
        f"ERRO: esperadas 2 chamadas TTF_SetFontSize(), encontradas {count}."
    )

with open(path, "w", encoding="utf-8") as f:
    f.write(text2)

print("OK: 2 chamadas TTF_SetFontSize removidas.")
PY

if grep -q "TTF_SetFontSize" "$TRUETYPE_CPP"; then
    echo "ERRO: TTF_SetFontSize ainda existe."
    exit 1
fi

echo "OK: compatibilidade SDL2_ttf aplicada."
echo

echo "=========================================="
echo " Preparando Guichan"
echo "=========================================="
echo

rm -rf "$SRC_DIR/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

echo "Guichan:"
git -C "$SRC_DIR/libs/guichan" describe --tags --always

echo

echo "=========================================="
echo " Preparando ENet"
echo "=========================================="
echo

rm -rf "$SRC_DIR/libs/enet"

git clone \
    --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

echo "ENet:"
git -C "$SRC_DIR/libs/enet" rev-parse HEAD

echo

echo "=========================================="
echo " Ajustando SDL2_ttf no CMake"
echo "=========================================="
echo

find "$SRC_DIR" \
    -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 |
while IFS= read -r -d '' FILE
do
    sed -i \
        -e 's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' \
        -e 's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' \
        "$FILE"
done

echo "OK: requisito SDL2_ttf ajustado."
echo

echo "=========================================="
echo " Aplicando software cursor para R36S"
echo "=========================================="
echo

GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ]; then
    echo "ERRO: gui.h nao encontrado."
    exit 1
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.cpp nao encontrado."
    exit 1
fi

python3 - \
    "$GUI_H" \
    "$GUI_CPP" <<'PY'
import re
import sys

gui_h_path = sys.argv[1]
gui_cpp_path = sys.argv[2]

with open(gui_h_path, "r", encoding="utf-8") as f:
    h = f.read()

with open(gui_cpp_path, "r", encoding="utf-8") as f:
    c = f.read()


def find_function_body(text, signature):
    start = text.find(signature)

    if start < 0:
        return None

    brace = text.find("{", start)

    if brace < 0:
        return None

    depth = 0
    quote = None
    escaped = False
    line_comment = False
    block_comment = False

    i = brace

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if line_comment:
            if ch == "\n":
                line_comment = False

            i += 1
            continue

        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
                continue

            i += 1
            continue

        if quote:
            if escaped:
                escaped = False

            elif ch == "\\":
                escaped = True

            elif ch == quote:
                quote = None

            i += 1
            continue

        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue

        if ch == '"' or ch == "'":
            quote = ch
            i += 1
            continue

        if ch == "{":
            depth += 1

        elif ch == "}":
            depth -= 1

            if depth == 0:
                return start, brace, i

        i += 1

    return None


# ==========================================================
# GUI.H
# ==========================================================

if '#include "resources/imageset.h"' not in h:

    marker = '#include "resources/theme.h"'

    if marker not in h:
        raise SystemExit(
            "ERRO: resources/theme.h nao encontrado em gui.h."
        )

    h = h.replace(
        marker,
        marker + '\n#include "resources/imageset.h"',
        1
    )


# Remove declaracoes antigas do nosso patch,
# evitando duplicacao em builds repetidos.

h = re.sub(
    r'\n\s*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
    '',
    h
)

h = re.sub(
    r'\n\s*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
    '',
    h
)


mouse_marker = "        int mMouseY = 0;"

if mouse_marker not in h:
    raise SystemExit(
        "ERRO: mMouseY nao encontrado em gui.h."
    )


h = h.replace(
    mouse_marker,
    mouse_marker
    + '\n        ResourceRef<ImageSet> mSoftwareCursor;'
    + '\n        bool mSoftwareCursorVisible = true;',
    1
)


# ==========================================================
# GUI.CPP - INICIALIZACAO DO CURSOR
# ==========================================================

# Remove inicializacao anterior, caso exista.

c = re.sub(
    r'\n\s*mSoftwareCursor\s*=\s*'
    r'\n?\s*ResourceManager::getInstance\(\)->getImageSet\('
    r'\s*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);'
    r'\s*SDL_ShowCursor\(SDL_DISABLE\);',
    '',
    c
)


constructor_marker = (
    "    setUseCustomCursor(config.customCursor);\n"
)

if constructor_marker not in c:
    raise SystemExit(
        "ERRO: setUseCustomCursor nao encontrado em gui.cpp."
    )


cursor_initialization = (
    "    mSoftwareCursor =\n"
    "        ResourceManager::getInstance()->getImageSet(\n"
    '            mTheme->resolvePath("mouse.png"), 40, 40);\n'
    "    SDL_ShowCursor(SDL_DISABLE);\n"
)

c = c.replace(
    constructor_marker,
    constructor_marker + cursor_initialization,
    1
)


# ==========================================================
# GUI::DRAW
# ==========================================================

body = find_function_body(
    c,
    "void Gui::draw()"
)

if body is None:
    raise SystemExit(
        "ERRO: Gui::draw nao localizado."
    )

draw_start, draw_brace, draw_end = body

draw_content = c[
    draw_brace + 1:
    draw_end
]


# Remove um cursor anterior, se houver.

draw_content = re.sub(
    r'\n\s*if\s*\(\s*mSoftwareCursorVisible'
    r'.*?'
    r'softwareCursorGraphics->drawImage\('
    r'.*?'
    r'\n\s*\}',
    '\n',
    draw_content,
    flags=re.DOTALL
)


cursor_draw = """
    
    if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        auto *softwareCursorGraphics =
            static_cast<Graphics*>(mGraphics);

        if (softwareCursorGraphics)
        {
            softwareCursorGraphics->drawImage(
                mSoftwareCursor->get(0),
                mMouseX - 15,
                mMouseY - 17
            );
        }
    }
"""


c = (
    c[:draw_brace + 1]
    + draw_content
    + cursor_draw
    + c[draw_end:]
)


# ==========================================================
# GUI::keyPressed - F12
# ==========================================================

body = find_function_body(
    c,
    "void Gui::keyPressed(gcn::KeyEvent &event)"
)

if body is None:
    raise SystemExit(
        "ERRO: Gui::keyPressed nao localizado."
    )

key_start, key_brace, key_end = body

key_content = c[
    key_brace + 1:
    key_end
]


# Remove F12 anterior, se existir.

key_content = re.sub(
    r'\n\s*if\s*\(\s*'
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12'
    r'\s*\)'
    r'\s*\{.*?\n\s*\}',
    '\n',
    key_content,
    flags=re.DOTALL
)


f12_code = """
    
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();
        return;
    }
"""


c = (
    c[:key_brace + 1]
    + f12_code
    + key_content
    + c[key_end:]
)


# ==========================================================
# DESABILITA CURSOR SDL NATIVO
# ==========================================================

c = c.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


with open(gui_h_path, "w", encoding="utf-8") as f:
    f.write(h)

with open(gui_cpp_path, "w", encoding="utf-8") as f:
    f.write(c)

print("Software cursor patch aplicado.")
PY

echo

echo "=== SOFTWARE CURSOR VALIDATION ==="

python3 - \
    "$GUI_H" \
    "$GUI_CPP" <<'PY'
import re
import sys

gui_h_path = sys.argv[1]
gui_cpp_path = sys.argv[2]

with open(gui_h_path, "r", encoding="utf-8") as f:
    h = f.read()

with open(gui_cpp_path, "r", encoding="utf-8") as f:
    c = f.read()


# ----------------------------------------------------------
# Declaracao do cursor
# ----------------------------------------------------------

count = len(
    re.findall(
        r'\bResourceRef<ImageSet>\s+mSoftwareCursor\s*;',
        h
    )
)

if count != 1:
    raise SystemExit(
        f"ERRO: mSoftwareCursor declaration invalida: {count}"
    )

print("mSoftwareCursor declaration: OK")


# ----------------------------------------------------------
# Visibilidade
# ----------------------------------------------------------

count = len(
    re.findall(
        r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
        h
    )
)

if count != 1:
    raise SystemExit(
        f"ERRO: mSoftwareCursorVisible declaration invalida: {count}"
    )

print("mSoftwareCursorVisible declaration: OK")


# ----------------------------------------------------------
# F12
# ----------------------------------------------------------

f12_count = len(
    re.findall(
        r'Key::F12',
        c
    )
)

if f12_count != 1:
    raise SystemExit(
        f"ERRO: F12 binding invalido: {f12_count}"
    )

print("F12 binding: OK")


# ----------------------------------------------------------
# F12 TOGGLE
#
# IMPORTANTE:
# nao usar grep aqui.
#
# O codigo pode estar assim:
#
# mSoftwareCursorVisible =
#     !mSoftwareCursorVisible;
#
# Por isso a validacao precisa aceitar whitespace,
# incluindo quebra de linha.
# ----------------------------------------------------------

toggle_pattern = re.compile(
    r'''
    mSoftwareCursorVisible
    \s*=\s*
    !
    \s*
    mSoftwareCursorVisible
    \s*;
    ''',
    re.VERBOSE
)

if not toggle_pattern.search(c):
    raise SystemExit(
        "ERRO: F12 toggle nao encontrado."
    )

print("F12 toggle: OK")


# ----------------------------------------------------------
# Inicializacao
# ----------------------------------------------------------

if "mSoftwareCursor =" not in c:
    raise SystemExit(
        "ERRO: inicializacao do software cursor nao encontrada."
    )

if "getImageSet" not in c:
    raise SystemExit(
        "ERRO: getImageSet nao encontrado."
    )

if 'mouse.png' not in c:
    raise SystemExit(
        "ERRO: mouse.png nao encontrado."
    )

print("Cursor initialization: OK")


# ----------------------------------------------------------
# Desenho
# ----------------------------------------------------------

if "softwareCursorGraphics->drawImage(" not in c:
    raise SystemExit(
        "ERRO: drawImage do software cursor nao encontrado."
    )

print("drawImage(): OK")


# ----------------------------------------------------------
# Cursor nativo
# ----------------------------------------------------------

if "SDL_ShowCursor(SDL_ENABLE)" in c:
    raise SystemExit(
        "ERRO: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )

print("Native SDL cursor: disabled")


# ----------------------------------------------------------
# Garante que o cursor nao usa drawRescaledImage
# ----------------------------------------------------------

if "softwareCursorGraphics->drawRescaledImage(" in c:
    raise SystemExit(
        "ERRO: software cursor esta usando drawRescaledImage."
    )

print("Software cursor draw method: OK")

print()
print("OK: software cursor validado.")
PY

echo

echo "=========================================="
echo " Configurando CMake"
echo "=========================================="
echo

cmake -S "$SRC_DIR" \
    -B "$BUILD_DIR/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

echo

echo "=========================================="
echo " Compilando Mana"
echo "=========================================="
echo

cmake \
    --build "$BUILD_DIR/cmake" \
    -j"$(nproc)"

echo

echo "=========================================="
echo " Instalando Mana"
echo "=========================================="
echo

cmake \
    --install "$BUILD_DIR/cmake"

echo

echo "=========================================="
echo " Procurando executavel"
echo "=========================================="
echo

BIN="$(find "$INSTALL_DIR" -type f -name "mana" | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executavel mana nao encontrado."
    echo
    find "$INSTALL_DIR" -maxdepth 5 -type f -print || true
    exit 1
fi

echo "Executavel:"
echo "$BIN"

cp "$BIN" "$DIST_DIR/mana.aarch64"

chmod +x "$DIST_DIR/mana.aarch64"

echo

echo "=========================================="
echo " Verificando ELF"
echo "=========================================="
echo

file "$DIST_DIR/mana.aarch64"

echo

echo "=== GLIBC ==="

readelf --version-info "$DIST_DIR/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu || true

echo

echo "=== NEEDED ==="

readelf -d "$DIST_DIR/mana.aarch64" \
    | grep NEEDED || true

echo

echo "=== RPATH/RUNPATH ==="

readelf -d "$DIST_DIR/mana.aarch64" \
    | grep -E 'RPATH|RUNPATH' || true

echo

if readelf --version-info "$DIST_DIR/mana.aarch64" \
    | grep -q "GLIBC_2.43"
then
    echo "ERRO: executavel exige GLIBC_2.43."
    exit 1
fi

echo "OK: nenhuma GLIBC_2.43 encontrada."

echo

echo "=========================================="
echo " Gerando diagnosticos"
echo "=========================================="
echo

{
    echo "=========================================="
    echo " Mana R36S AArch64 Diagnostics"
    echo "=========================================="
    echo

    echo "=== FILE ==="
    file "$DIST_DIR/mana.aarch64"

    echo

    echo "=== GLIBC ==="
    readelf --version-info "$DIST_DIR/mana.aarch64" \
        | grep -o 'GLIBC_[0-9.]*' \
        | sort -Vu || true

    echo

    echo "=== NEEDED ==="
    readelf -d "$DIST_DIR/mana.aarch64" \
        | grep NEEDED || true

    echo

    echo "=== RPATH/RUNPATH ==="
    readelf -d "$DIST_DIR/mana.aarch64" \
        | grep -E 'RPATH|RUNPATH' || true

    echo

    echo "=== GUICHAN ==="
    git -C "$SRC_DIR/libs/guichan" describe --tags --always
    git -C "$SRC_DIR/libs/guichan" rev-parse HEAD

    echo

    echo "=== ENET ==="
    git -C "$SRC_DIR/libs/enet" rev-parse HEAD

} > "$DIST_DIR/diagnostics.txt"

echo "OK: diagnostics.txt criado."

echo

echo "=========================================="
echo " Preparando PortMaster"
echo "=========================================="
echo

PACKAGE="$DIST_DIR/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

echo "Criando Mana.sh..."

cat > "$PORT_DIR/Mana.sh" <<'EOF'
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

if [ -f "$controlfolder/control.txt" ]; then
    source "$controlfolder/control.txt"
else
    echo "ERRO: control.txt do PortMaster nao encontrado."
    exit 1
fi

if type get_controls >/dev/null 2>&1; then
    get_controls
fi

GAMEDIR="/${directory}/ports/mana"

if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR="/roms/ports/mana"
fi

CONFDIR="$GAMEDIR/conf"
GAMEDATA="$GAMEDIR/mana/data"
GAME="$GAMEDIR/mana/mana.aarch64"
LOGFILE="$GAMEDIR/log.txt"

mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1

: > "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "=========================================="
echo " Mana 0.8.0 PortMaster"
echo "=========================================="
echo "GAMEDIR=$GAMEDIR"
echo "ARCH=$(uname -m)"
echo

if [ ! -f "$GAME" ]; then
    echo "ERRO: executavel nao encontrado:"
    echo "$GAME"
    exit 1
fi

chmod +x "$GAME"

cd "$GAMEDIR/mana" || exit 1

if [ -d "$GAMEDIR/mana/libs.aarch64" ]; then
    export LD_LIBRARY_PATH="$GAMEDIR/mana/libs.aarch64:${LD_LIBRARY_PATH:-}"
fi

if type pm_platform_helper >/dev/null 2>&1; then
    pm_platform_helper "$GAME"
fi

GPTOKEYB_PID=""

if [ -n "${GPTOKEYB2:-}" ] && [ -f "./mana.gptk2" ]; then

    echo "Starting GPTOKEYB2..."

    "$GPTOKEYB2" \
        "$GAME" \
        -c "./mana.gptk2" &

    GPTOKEYB_PID=$!

elif [ -n "${GPTOKEYB:-}" ] && [ -f "./mana.gptk" ]; then

    echo "Starting GPTOKEYB..."

    "$GPTOKEYB" \
        "$GAME" \
        -c "./mana.gptk" &

    GPTOKEYB_PID=$!

else

    echo "WARNING: GPTOKEYB nao encontrado."

fi

echo "Starting Mana..."
echo

"$GAME" \
    --data "$GAMEDATA" \
    --localdata-dir "$CONFDIR"

GAME_EXIT=$?

if [ -n "$GPTOKEYB_PID" ]; then
    kill "$GPTOKEYB_PID" 2>/dev/null || true
    wait "$GPTOKEYB_PID" 2>/dev/null || true
fi

if type pm_finish >/dev/null 2>&1; then
    pm_finish
fi

exit "$GAME_EXIT"
EOF

chmod +x "$PORT_DIR/Mana.sh"

echo "OK: Mana.sh criado."

echo

echo "=========================================="
echo " Criando mana.gptk"
echo "=========================================="
echo

mkdir -p "$PORT_DIR/mana"

cat > "$PORT_DIR/mana/mana.gptk" <<'EOF'
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
EOF

echo "OK: mana.gptk criado."

echo

echo "=========================================="
echo " Criando mana.gptk2"
echo "=========================================="
echo

cat > "$PORT_DIR/mana/mana.gptk2" <<'EOF'
[controls]

back = esc
select = f12

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

start = hold_state hotkey_start

[controls:hotkey_start]

down = push_state text_input
start = enter

[controls:text_input]

charset = extended

up = prev_letter
down = next_letter
right = add_letter
left = backspace

a = enter
b = backspace

start = enter
select = pop_state
EOF

echo "OK: mana.gptk2 criado."

echo

echo "=========================================="
echo " Montando pacote"
echo "=========================================="
echo

cp "$PORT_DIR/Mana.sh" \
    "$PACKAGE/Mana.sh"

cp "$PORT_DIR/mana/mana.gptk" \
    "$PACKAGE/mana/mana.gptk"

cp "$PORT_DIR/mana/mana.gptk2" \
    "$PACKAGE/mana/mana.gptk2"

cp "$DIST_DIR/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x "$PACKAGE/Mana.sh"
chmod +x "$PACKAGE/mana/mana.aarch64"

if [ -d "$PORT_DIR/mana/data" ]; then
    cp -a \
        "$PORT_DIR/mana/data" \
        "$PACKAGE/mana/"
fi

if [ -d "$PORT_DIR/mana/licenses" ]; then
    cp -a \
        "$PORT_DIR/mana/licenses" \
        "$PACKAGE/mana/"
fi

for FILE in \
    README.md \
    gameinfo.xml \
    port.json \
    screenshot.png
do

    if [ -f "$PORT_DIR/$FILE" ]; then
        cp "$PORT_DIR/$FILE" "$PACKAGE/"
    fi

done

echo

echo "=========================================="
echo " Verificando pacote"
echo "=========================================="
echo

if [ ! -f "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh ausente."
    exit 1
fi

if [ ! -x "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao executavel."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 ausente."
    exit 1
fi

if [ ! -x "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 nao executavel."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk ausente."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.gptk2" ]; then
    echo "ERRO: mana.gptk2 ausente."
    exit 1
fi

echo "OK: Mana.sh"
echo "OK: mana.aarch64"
echo "OK: mana.gptk"
echo "OK: mana.gptk2"

echo

echo "=== Estrutura final ==="

find "$PACKAGE" \
    -maxdepth 5 \
    -type f \
    -print \
    | sort

echo

echo "=========================================="
echo " Criando ZIP PortMaster"
echo "=========================================="
echo

cd "$PACKAGE"

zip -r \
    "$DIST_DIR/mana-r36s-portmaster-aarch64.zip" \
    . \
    -x "*.DS_Store"

cd "$ROOT"

echo

echo "=========================================="
echo " BUILD FINALIZADO"
echo "=========================================="
echo

echo "Arquivos gerados:"
echo

ls -lh "$DIST_DIR"

echo

echo "ZIP:"
ls -lh \
    "$DIST_DIR/mana-r36s-portmaster-aarch64.zip"

echo

echo "Executavel:"
ls -lh \
    "$DIST_DIR/mana.aarch64"

echo

echo "Diagnosticos:"
ls -lh \
    "$DIST_DIR/diagnostics.txt"

echo

echo "=========================================="
echo " FIM"
echo "=========================================="
