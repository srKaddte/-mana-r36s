#!/bin/bash
set -e

ROOT="/workspace"

SRC_TAR="$ROOT/source/mana-master.tar.gz"

BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

echo "========================================"
echo " Mana 0.8.0 AArch64 PortMaster Builder"
echo "========================================"
echo

rm -rf "$BUILD"
rm -rf "$INSTALL"
rm -rf "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"
mkdir -p "$PORT"

echo "========================================"
echo " Instalando dependencias"
echo "========================================"
echo

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    git \
    zip \
    file \
    binutils \
    pkg-config \
    python3 \
    gettext \
    zlib1g-dev \
    libpng-dev \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev

echo
echo "Dependencias instaladas."
echo

echo "========================================"
echo " Verificando dependencias"
echo "========================================"
echo

echo "SDL2:"
pkg-config --modversion sdl2 || true

echo "SDL2_image:"
pkg-config --modversion SDL2_image || true

echo "SDL2_mixer:"
pkg-config --modversion SDL2_mixer || true

echo "SDL2_net:"
pkg-config --modversion SDL2_net || true

echo "SDL2_ttf:"
pkg-config --modversion SDL2_ttf || true

echo "PhysFS:"
pkg-config --modversion physfs || true

echo "libxml2:"
pkg-config --modversion libxml-2.0 || true

echo "CURL:"
pkg-config --modversion libcurl || true

echo

echo "========================================"
echo " Extraindo source do Mana"
echo "========================================"
echo

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: diretorio do source nao encontrado."
    exit 1
fi

echo "SRC_DIR=$SRC_DIR"
echo

echo "========================================"
echo " Corrigindo SDL2_ttf"
echo "========================================"
echo

TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: truetypefont.cpp nao encontrado:"
    echo "$TRUETYPE_CPP"
    exit 1
fi

python3 - "$TRUETYPE_CPP" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

pattern = re.compile(
    r"TTF_SetFontSize\([^;]*\);"
)

text, count = pattern.subn("", text)

if count != 2:
    raise SystemExit(
        "ERRO: esperadas exatamente 2 chamadas "
        f"TTF_SetFontSize(), encontradas {count}."
    )

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

print("OK: removidas 2 chamadas TTF_SetFontSize().")
PY

if grep -q "TTF_SetFontSize" "$TRUETYPE_CPP"; then
    echo "ERRO: TTF_SetFontSize ainda existe."
    exit 1
fi

echo "OK: SDL2_ttf corrigido."
echo

echo "========================================"
echo " Preparando Guichan"
echo "========================================"
echo

rm -rf "$SRC_DIR/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

if [ ! -d "$SRC_DIR/libs/guichan" ]; then
    echo "ERRO: Guichan nao foi clonado."
    exit 1
fi

echo "OK: Guichan 0.8.3."
echo

echo "========================================"
echo " Preparando ENet"
echo "========================================"
echo

rm -rf "$SRC_DIR/libs/enet"

git clone \
    --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

if [ ! -d "$SRC_DIR/libs/enet" ]; then
    echo "ERRO: ENet nao foi clonado."
    exit 1
fi

echo "OK: ENet."
echo

echo "========================================"
echo " Ajustando requisito SDL2_ttf"
echo "========================================"
echo

find "$SRC_DIR" \
    -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 |
while IFS= read -r -d '' FILE
do
    sed -i \
        's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' \
        "$FILE"

    sed -i \
        's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' \
        "$FILE"

    sed -i \
        's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' \
        "$FILE"
done

echo "OK: requisito SDL2_ttf ajustado."
echo

echo "========================================"
echo " Aplicando software cursor para R36S"
echo "========================================"
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

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import re
import sys

gui_h_path = sys.argv[1]
gui_cpp_path = sys.argv[2]

with open(gui_h_path, "r", encoding="utf-8") as f:
    h = f.read()

with open(gui_cpp_path, "r", encoding="utf-8") as f:
    c = f.read()


# ============================================================
# FUNCAO PARA LOCALIZAR UMA FUNCAO C++ COMPLETA
# ============================================================

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


# ============================================================
# HEADER - INCLUDE
# ============================================================

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


# ============================================================
# IMPORTANTE:
#
# REMOVE TODAS AS DECLARACOES EXISTENTES DO SOFTWARE CURSOR.
#
# Isso torna o patch idempotente.
#
# Mesmo se o source ja tiver recebido o patch anteriormente,
# nao deixaremos duas declaracoes.
# ============================================================

h = re.sub(
    r'[ \t]*ResourceRef\s*<\s*ImageSet\s*>\s+'
    r'mSoftwareCursor\s*;\s*\n?',
    '',
    h
)

h = re.sub(
    r'[ \t]*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*\n?',
    '',
    h
)


# ============================================================
# GARANTE QUE NAO EXISTE UMA SEGUNDA VARIACAO DO NOME
# ============================================================

if re.search(
    r'\bmSoftwareCursor\b',
    h
):
    # Neste ponto nenhuma ocorrencia deveria existir.
    # Qualquer uma seria uma forma diferente da declaracao
    # que precisamos detectar antes de inserir a oficial.
    leftovers = re.findall(
        r'.{0,80}\bmSoftwareCursor\b.{0,80}',
        h,
        flags=re.DOTALL
    )

    raise SystemExit(
        "ERRO: ainda existem referencias antigas a "
        "mSoftwareCursor no gui.h antes da insercao:\n"
        + "\n".join(leftovers[:10])
    )


# ============================================================
# ENCONTRA mMouseY
# ============================================================

mouse_y_pattern = re.compile(
    r'(?m)^([ \t]*)int\s+mMouseY\s*=\s*0\s*;[ \t]*$'
)

mouse_y_matches = list(mouse_y_pattern.finditer(h))

if len(mouse_y_matches) != 1:
    raise SystemExit(
        "ERRO: mMouseY deveria existir exatamente uma vez. "
        f"Encontrado: {len(mouse_y_matches)}."
    )

mouse_y_match = mouse_y_matches[0]

indent = mouse_y_match.group(1)

replacement = (
    indent + "int mMouseY = 0;\n"
    + indent + "ResourceRef<ImageSet> mSoftwareCursor;\n"
    + indent + "bool mSoftwareCursorVisible = true;"
)

h = (
    h[:mouse_y_match.start()]
    + replacement
    + h[mouse_y_match.end():]
)


# ============================================================
# VALIDACAO DO HEADER
# ============================================================

cursor_decl_pattern = re.compile(
    r'\bResourceRef\s*<\s*ImageSet\s*>\s+'
    r'mSoftwareCursor\s*;'
)

visible_decl_pattern = re.compile(
    r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;'
)

cursor_count = len(cursor_decl_pattern.findall(h))
visible_count = len(visible_decl_pattern.findall(h))

if cursor_count != 1:
    raise SystemExit(
        "ERRO INTERNO: mSoftwareCursor terminou com "
        f"{cursor_count} declaracoes."
    )

if visible_count != 1:
    raise SystemExit(
        "ERRO INTERNO: mSoftwareCursorVisible terminou com "
        f"{visible_count} declaracoes."
    )

print("HEADER: mSoftwareCursor = 1")
print("HEADER: mSoftwareCursorVisible = 1")


# ============================================================
# CONSTRUCTOR
# ============================================================

# Remove inicializacoes anteriores do software cursor.

c = re.sub(
    r'\n[ \t]*mSoftwareCursor\s*=\s*'
    r'ResourceManager::getInstance\(\)->getImageSet\('
    r'.*?'
    r'\);\s*'
    r'\n[ \t]*SDL_ShowCursor\(\s*SDL_DISABLE\s*\);\s*',
    '\n',
    c,
    flags=re.DOTALL
)

constructor_marker = (
    '    setUseCustomCursor(config.customCursor);\n'
)

if constructor_marker not in c:
    raise SystemExit(
        "ERRO: setUseCustomCursor(config.customCursor) "
        "nao encontrado."
    )

constructor_code = (
    '    setUseCustomCursor(config.customCursor);\n'
    '\n'
    '    mSoftwareCursor =\n'
    '        ResourceManager::getInstance()->getImageSet(\n'
    '            mTheme->resolvePath("mouse.png"), 40, 40);\n'
    '\n'
    '    SDL_ShowCursor(SDL_DISABLE);\n'
)

c = c.replace(
    constructor_marker,
    constructor_code,
    1
)


# ============================================================
# DRAW
# ============================================================

body = find_function_body(
    c,
    "void Gui::draw()"
)

if body is None:
    raise SystemExit(
        "ERRO: Gui::draw() nao encontrado."
    )

draw_start, draw_brace, draw_end = body

draw_body = c[
    draw_brace + 1:
    draw_end
]


# Remove qualquer bloco de desenho anterior do cursor.

draw_body = re.sub(
    r'\n[ \t]*if\s*\(\s*'
    r'mSoftwareCursorVisible\s*&&.*?'
    r'softwareCursorGraphics->drawImage\s*\('
    r'.*?'
    r'\n[ \t]*\}',
    '\n',
    draw_body,
    flags=re.DOTALL
)

cursor_draw = (
    '\n'
    '    if (mSoftwareCursorVisible &&\n'
    '        mSoftwareCursor &&\n'
    '        mSoftwareCursor->size() > 0)\n'
    '    {\n'
    '        auto *softwareCursorGraphics =\n'
    '            static_cast<Graphics*>(mGraphics);\n'
    '\n'
    '        if (softwareCursorGraphics)\n'
    '        {\n'
    '            softwareCursorGraphics->drawImage(\n'
    '                mSoftwareCursor->get(0),\n'
    '                mMouseX - 15,\n'
    '                mMouseY - 17\n'
    '            );\n'
    '        }\n'
    '    }\n'
)

c = (
    c[:draw_brace + 1]
    + draw_body
    + cursor_draw
    + c[draw_end:]
)


# ============================================================
# F12
# ============================================================

body = find_function_body(
    c,
    "void Gui::keyPressed(gcn::KeyEvent &event)"
)

if body is None:
    raise SystemExit(
        "ERRO: Gui::keyPressed(gcn::KeyEvent &event) "
        "nao encontrado."
    )

key_start, key_brace, key_end = body

key_body = c[
    key_brace + 1:
    key_end
]


# Remove qualquer bloco F12 anterior.

key_body = re.sub(
    r'\n[ \t]*if\s*\(\s*'
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12'
    r'\s*\)\s*\{.*?'
    r'\n[ \t]*\}',
    '\n',
    key_body,
    flags=re.DOTALL
)

f12_code = (
    '\n'
    '    if (event.getKey().getValue() == Key::F12)\n'
    '    {\n'
    '        mSoftwareCursorVisible =\n'
    '            !mSoftwareCursorVisible;\n'
    '\n'
    '        event.consume();\n'
    '        return;\n'
    '    }\n'
)

c = (
    c[:key_brace + 1]
    + f12_code
    + key_body
    + c[key_end:]
)


# ============================================================
# NUNCA REATIVAR CURSOR SDL NATIVO
# ============================================================

c = re.sub(
    r'SDL_ShowCursor\s*\(\s*SDL_ENABLE\s*\)\s*;',
    'SDL_ShowCursor(SDL_DISABLE);',
    c
)


# ============================================================
# SALVA
# ============================================================

with open(gui_h_path, "w", encoding="utf-8") as f:
    f.write(h)

with open(gui_cpp_path, "w", encoding="utf-8") as f:
    f.write(c)

print("Software cursor patch aplicado.")
PY


echo
echo "========================================"
echo " SOFTWARE CURSOR VALIDATION"
echo "========================================"
echo

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import re
import sys

gui_h_path = sys.argv[1]
gui_cpp_path = sys.argv[2]

with open(gui_h_path, "r", encoding="utf-8") as f:
    h = f.read()

with open(gui_cpp_path, "r", encoding="utf-8") as f:
    c = f.read()


# ============================================================
# DECLARACOES
# ============================================================

cursor_count = len(
    re.findall(
        r'\bResourceRef\s*<\s*ImageSet\s*>\s+'
        r'mSoftwareCursor\s*;',
        h
    )
)

visible_count = len(
    re.findall(
        r'\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;',
        h
    )
)

mouse_y_count = len(
    re.findall(
        r'(?m)^[ \t]*int\s+mMouseY\s*=\s*0\s*;',
        h
    )
)

if cursor_count != 1:
    raise SystemExit(
        "ERRO: mSoftwareCursor possui "
        f"{cursor_count} declaracoes."
    )

print("mSoftwareCursor declaration: OK")


if visible_count != 1:
    raise SystemExit(
        "ERRO: mSoftwareCursorVisible possui "
        f"{visible_count} declaracoes."
    )

print("mSoftwareCursorVisible declaration: OK")


if mouse_y_count != 1:
    raise SystemExit(
        "ERRO: mMouseY possui "
        f"{mouse_y_count} declaracoes."
    )

print("mMouseY declaration: OK")


# ============================================================
# F12
# ============================================================

f12_count = len(
    re.findall(
        r'Key::F12',
        c
    )
)

if f12_count != 1:
    raise SystemExit(
        "ERRO: Key::F12 aparece "
        f"{f12_count} vezes."
    )

print("F12 binding: OK")


# ============================================================
# TOGGLE
#
# Usa Python regex porque o C++ pode estar quebrado em
# varias linhas.
# ============================================================

toggle_pattern = re.compile(
    r'mSoftwareCursorVisible\s*=\s*!\s*'
    r'mSoftwareCursorVisible\s*;'
)

toggle_count = len(
    toggle_pattern.findall(c)
)

if toggle_count != 1:
    raise SystemExit(
        "ERRO: F12 toggle aparece "
        f"{toggle_count} vezes."
    )

print("F12 toggle: OK")


# ============================================================
# INICIALIZACAO
# ============================================================

init_count = len(
    re.findall(
        r'mSoftwareCursor\s*=\s*'
        r'ResourceManager::getInstance\(\)->getImageSet',
        c
    )
)

if init_count != 1:
    raise SystemExit(
        "ERRO: inicializacao do cursor aparece "
        f"{init_count} vezes."
    )

print("Cursor initialization: OK")


# ============================================================
# DRAWIMAGE
# ============================================================

draw_count = len(
    re.findall(
        r'softwareCursorGraphics->drawImage\s*\(',
        c
    )
)

if draw_count != 1:
    raise SystemExit(
        "ERRO: drawImage do cursor aparece "
        f"{draw_count} vezes."
    )

print("Cursor drawImage: OK")


# ============================================================
# SDL CURSOR NATIVO
# ============================================================

enable_count = len(
    re.findall(
        r'SDL_ShowCursor\s*\(\s*SDL_ENABLE\s*\)',
        c
    )
)

if enable_count != 0:
    raise SystemExit(
        "ERRO: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )

print("Native SDL cursor: disabled")


# ============================================================
# MOUSE.PNG
# ============================================================

if "mouse.png" not in c:
    raise SystemExit(
        "ERRO: mouse.png nao encontrado."
    )

print("mouse.png: OK")


print()
print("========================================")
print(" SOFTWARE CURSOR VALIDADO COM SUCESSO")
print("========================================")
PY

echo


echo "========================================"
echo " Configurando CMake"
echo "========================================"
echo

cmake \
    -S "$SRC_DIR" \
    -B "$BUILD/cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

echo

echo "========================================"
echo " Compilando Mana"
echo "========================================"
echo

cmake \
    --build "$BUILD/cmake" \
    -j"$(nproc)"

echo

echo "========================================"
echo " Instalando Mana"
echo "========================================"
echo

cmake \
    --install "$BUILD/cmake"

echo

echo "========================================"
echo " Localizando executavel"
echo "========================================"
echo

BIN="$(find "$INSTALL" -type f -name mana | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executavel Mana nao encontrado."

    find "$INSTALL" \
        -maxdepth 6 \
        -type f \
        -print || true

    exit 1
fi

echo "Executavel:"
echo "$BIN"
echo

cp \
    "$BIN" \
    "$DIST/mana.aarch64"

chmod +x \
    "$DIST/mana.aarch64"

echo

echo "========================================"
echo " Verificando ELF"
echo "========================================"
echo

file "$DIST/mana.aarch64"

echo
echo "=== GLIBC ==="

readelf \
    --version-info \
    "$DIST/mana.aarch64" |
    grep -o 'GLIBC_[0-9.]*' |
    sort -Vu || true

echo
echo "=== NEEDED ==="

readelf \
    -d \
    "$DIST/mana.aarch64" |
    grep NEEDED || true

echo
echo "=== RPATH/RUNPATH ==="

readelf \
    -d \
    "$DIST/mana.aarch64" |
    grep -E 'RPATH|RUNPATH' || true

echo

if readelf \
    --version-info \
    "$DIST/mana.aarch64" |
    grep -q 'GLIBC_2.43'
then
    echo "ERRO: executavel exige GLIBC_2.43."
    exit 1
fi

echo "OK: GLIBC_2.43 nao encontrada."
echo


echo "========================================"
echo " Gerando diagnostics.txt"
echo "========================================"
echo

{
    echo "Mana R36S AArch64 Diagnostics"
    echo

    echo "=== FILE ==="
    file "$DIST/mana.aarch64"

    echo
    echo "=== GLIBC ==="

    readelf \
        --version-info \
        "$DIST/mana.aarch64" |
        grep -o 'GLIBC_[0-9.]*' |
        sort -Vu || true

    echo
    echo "=== NEEDED ==="

    readelf \
        -d \
        "$DIST/mana.aarch64" |
        grep NEEDED || true

    echo
    echo "=== RPATH/RUNPATH ==="

    readelf \
        -d \
        "$DIST/mana.aarch64" |
        grep -E 'RPATH|RUNPATH' || true

} > "$DIST/diagnostics.txt"

echo


echo "========================================"
echo " Preparando PortMaster"
echo "========================================"
echo

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p \
    "$PACKAGE"

mkdir -p \
    "$PACKAGE/mana"


# ============================================================
# Mana.sh
# ============================================================

cat > "$PACKAGE/Mana.sh" <<'EOF'
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
    echo "ERRO: control.txt nao encontrado."
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

echo "========================================"
echo " Mana 0.8.0 PortMaster"
echo "========================================"
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
echo "$GAME"

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

chmod +x "$PACKAGE/Mana.sh"


# ============================================================
# LEGACY GPTOKEYB
# ============================================================

cat > "$PACKAGE/mana/mana.gptk" <<'EOF'
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


# ============================================================
# GPTOKEYB2
# ============================================================

cat > "$PACKAGE/mana/mana.gptk2" <<'EOF'
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


# ============================================================
# EXECUTAVEL
# ============================================================

cp \
    "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x \
    "$PACKAGE/mana/mana.aarch64"


# ============================================================
# DADOS ADICIONAIS
# ============================================================

if [ -d "$PORT/mana/data" ]; then
    cp -a \
        "$PORT/mana/data" \
        "$PACKAGE/mana/"
fi

if [ -d "$PORT/mana/licenses" ]; then
    cp -a \
        "$PORT/mana/licenses" \
        "$PACKAGE/mana/"
fi

if [ -f "$PORT/README.md" ]; then
    cp \
        "$PORT/README.md" \
        "$PACKAGE/"
fi

if [ -f "$PORT/gameinfo.xml" ]; then
    cp \
        "$PORT/gameinfo.xml" \
        "$PACKAGE/"
fi

if [ -f "$PORT/port.json" ]; then
    cp \
        "$PORT/port.json" \
        "$PACKAGE/"
fi

if [ -f "$PORT/screenshot.png" ]; then
    cp \
        "$PORT/screenshot.png" \
        "$PACKAGE/"
fi


# ============================================================
# VALIDACAO DO PACOTE
# ============================================================

echo
echo "========================================"
echo " Verificacao final do pacote"
echo "========================================"
echo

if [ ! -f "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta no pacote."
    exit 1
fi

if [ ! -x "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta executavel."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 nao esta no pacote."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao esta no pacote."
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.gptk2" ]; then
    echo "ERRO: mana.gptk2 nao esta no pacote."
    exit 1
fi

echo "OK: Mana.sh"
echo "OK: mana.aarch64"
echo "OK: mana.gptk"
echo "OK: mana.gptk2"

echo
echo "========================================"
echo " Estrutura final"
echo "========================================"
echo

find "$PACKAGE" \
    -maxdepth 5 \
    -type f \
    -print

echo


# ============================================================
# ZIP
# ============================================================

echo "========================================"
echo " Criando ZIP"
echo "========================================"
echo

cd "$PACKAGE"

zip -r \
    "$DIST/mana-r36s-portmaster-aarch64.zip" \
    . \
    -x "*.DS_Store"

cd "$ROOT"

echo
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"
echo

ls -lh "$DIST"

echo
echo "ZIP:"
ls -lh \
    "$DIST/mana-r36s-portmaster-aarch64.zip"

echo
echo "========================================"
echo " FIM"
echo "========================================"
