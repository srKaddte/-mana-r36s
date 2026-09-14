#!/bin/bash
set -e

ROOT=/workspace
SRC_TAR="$ROOT/source/mana-master.tar.gz"
BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

rm -rf "$BUILD" "$INSTALL" "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"
mkdir -p "$PORT"

echo "========================================"
echo " Mana 0.8.0 AArch64 / PortMaster Build"
echo "========================================"
echo

echo "=== Instalando dependencias de build ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    git \
    zip \
    file \
    binutils \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext \
    pkg-config \
    python3

echo
echo "=== Dependencias instaladas ==="
echo

echo "=== Extraindo source do Mana ==="

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: arquivo source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

tar -xzf "$SRC_TAR" -C "$BUILD"

SRC_DIR="$(find "$BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)"

if [ -z "$SRC_DIR" ]; then
    echo "ERRO: source do Mana nao encontrado"
    exit 1
fi

echo "Source:"
echo "$SRC_DIR"
echo

echo "========================================"
echo " Corrigindo compatibilidade SDL2_ttf"
echo "========================================"
echo

TRUETYPE_CPP="$SRC_DIR/src/gui/truetypefont.cpp"

if [ ! -f "$TRUETYPE_CPP" ]; then
    echo "ERRO: truetypefont.cpp nao encontrado:"
    echo "$TRUETYPE_CPP"
    exit 1
fi

echo "Arquivo encontrado:"
echo "$TRUETYPE_CPP"
echo

python3 - "$TRUETYPE_CPP" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    source = f.read()

pattern = re.compile(
    r"""
    TTF_SetFontSize\(
        [^;]*
    \);
    """,
    re.VERBOSE,
)

source_new, count = pattern.subn("", source)

if count != 2:
    print(
        "ERRO: esperadas 2 chamadas TTF_SetFontSize(), "
        f"encontradas {count}."
    )
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(source_new)

print("OK: removidas as 2 chamadas TTF_SetFontSize().")
print("OK: restante de updateFontScale() preservado.")
PY

echo
echo "=== Verificando correcao SDL2_ttf ==="

if grep -n "TTF_SetFontSize" "$TRUETYPE_CPP"; then
    echo
    echo "ERRO: TTF_SetFontSize ainda esta presente."
    exit 1
fi

echo
echo "Correcao SDL2_ttf aplicada com sucesso."
echo

echo "=== Preparando submodules ==="

rm -rf "$SRC_DIR/libs/guichan"
rm -rf "$SRC_DIR/libs/enet"

echo
echo "========================================"
echo " Clonando Guichan 0.8.3"
echo "========================================"
echo

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC_DIR/libs/guichan"

echo
echo "=== Verificando Guichan ==="

cd "$SRC_DIR/libs/guichan"

echo "Tag/revisao:"
git describe --tags --always

echo "Commit:"
git rev-parse HEAD

cd "$ROOT"

echo
echo "========================================"
echo " Clonando ENet"
echo "========================================"
echo

git clone \
    --depth 1 \
    https://github.com/lsalzman/enet.git \
    "$SRC_DIR/libs/enet"

echo
echo "=== Verificando ENet ==="

cd "$SRC_DIR/libs/enet"

git rev-parse HEAD

cd "$ROOT"

echo
echo "========================================"
echo " Ajustando requisito do SDL2_ttf"
echo "========================================"

find "$SRC_DIR" -type f \
    \( -name "CMakeLists.txt" -o -name "*.cmake" \) \
    -print0 | while IFS= read -r -d '' FILE
do
    sed -i 's/SDL2_ttf>=2\.0\.18/SDL2_ttf>=2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf >= 2\.0\.18/SDL2_ttf >= 2.0.15/g' "$FILE"
    sed -i 's/SDL2_ttf 2\.0\.18/SDL2_ttf 2.0.15/g' "$FILE"
done

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
echo "========================================"
echo " Aplicando software cursor para R36S"
echo "========================================"
echo

GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ] || [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.h/gui.cpp nao encontrados."
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import re
import sys

gui_h_path, gui_cpp_path = sys.argv[1], sys.argv[2]

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
    i = brace
    quote = None
    escaped = False
    line_comment = False
    block_comment = False

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

        if ch in ('"', "'"):
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
# HEADER
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


marker = '        int mMouseY = 0;'

if marker not in h:
    raise SystemExit("ERRO: mMouseY nao encontrado em gui.h.")


h = h.replace(
    marker,
    marker
    + '\n        ResourceRef<ImageSet> mSoftwareCursor;'
    + '\n        bool mSoftwareCursorVisible = true;',
    1
)


# ============================================================
# CONSTRUCTOR
# ============================================================

c = re.sub(
    r'\n\s*mSoftwareCursor\s*=\s*\n'
    r'\s*ResourceManager::getInstance\(\)->getImageSet\(\n'
    r'\s*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);\n'
    r'\s*SDL_ShowCursor\(SDL_DISABLE\);\n',
    '\n',
    c
)


marker = '    setUseCustomCursor(config.customCursor);\n'

if marker not in c:
    raise SystemExit(
        "ERRO: setUseCustomCursor nao encontrado em gui.cpp."
    )


init_code = (
    '    mSoftwareCursor =\n'
    '        ResourceManager::getInstance()->getImageSet(\n'
    '            mTheme->resolvePath("mouse.png"), 40, 40);\n'
    '    SDL_ShowCursor(SDL_DISABLE);\n'
)

c = c.replace(
    marker,
    marker + init_code,
    1
)


# ============================================================
# GUI::DRAW
# ============================================================

body = find_function_body(
    c,
    "void Gui::draw()"
)

if body is None:
    raise SystemExit("ERRO: Gui::draw nao localizado.")


draw_start, draw_brace, draw_end = body

draw_content = c[
    draw_brace + 1:
    draw_end
]


# Remove qualquer patch anterior do cursor.
draw_content = re.sub(
    r'\n\s*if\s*\(\s*mSoftwareCursorVisible'
    r'.*?mSoftwareCursor->get\(0\).*?\n\s*\}',
    '\n',
    draw_content,
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
    + draw_content
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
        "ERRO: Gui::keyPressed nao localizado."
    )


key_start, key_brace, key_end = body

key_content = c[
    key_brace + 1:
    key_end
]


# Remove qualquer F12 anterior do patch.
key_content = re.sub(
    r'\n\s*if\s*\(\s*'
    r'event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12'
    r'\s*\)\s*\{.*?\n\s*\}',
    '\n',
    key_content,
    flags=re.DOTALL
)


f12_toggle = (
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
    + f12_toggle
    + key_content
    + c[key_end:]
)


# ============================================================
# CURSOR NATIVO
# ============================================================

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

if [ "$(grep -c 'ResourceRef<ImageSet> mSoftwareCursor;' "$GUI_H" || true)" -ne 1 ]; then
    echo "ERRO: mSoftwareCursor declaration invalida."
    exit 1
fi

echo "mSoftwareCursor declaration: OK"

if [ "$(grep -c 'bool mSoftwareCursorVisible = true;' "$GUI_H" || true)" -ne 1 ]; then
    echo "ERRO: mSoftwareCursorVisible declaration invalida."
    exit 1
fi

echo "mSoftwareCursorVisible declaration: OK"

if [ "$(grep -c 'Key::F12' "$GUI_CPP" || true)" -ne 1 ]; then
    echo "ERRO: F12 binding nao encontrado exatamente uma vez."
    exit 1
fi

echo "F12 binding: OK"

if ! grep -Eq \
    'mSoftwareCursorVisible[[:space:]]*=[[:space:]]*![[:space:]]*mSoftwareCursorVisible[[:space:]]*;' \
    "$GUI_CPP"
then
    echo "ERRO: F12 toggle nao encontrado."
    exit 1
fi

echo "F12 toggle: OK"

if ! grep -q 'mSoftwareCursor =' "$GUI_CPP"; then
    echo "ERRO: inicializacao do software cursor nao encontrada."
    exit 1
fi

if ! grep -q 'getImageSet' "$GUI_CPP" || \
   ! grep -q 'mouse.png' "$GUI_CPP"
then
    echo "ERRO: carregamento de mouse.png nao encontrado."
    exit 1
fi

echo "Cursor initialization: OK"

if ! grep -q 'softwareCursorGraphics->drawImage(' "$GUI_CPP"; then
    echo "ERRO: drawImage() do software cursor nao encontrado."
    exit 1
fi

echo "drawImage(): OK"

if grep -q 'SDL_ShowCursor(SDL_ENABLE)' "$GUI_CPP"; then
    echo "ERRO: SDL cursor nativo ainda pode ser reativado."
    exit 1
fi

echo "Native SDL cursor: disabled"

if grep -Eq \
    'softwareCursorGraphics->drawRescaledImage\([^;]*mSoftwareCursor->get\(0\)' \
    "$GUI_CPP"
then
    echo "ERRO: software cursor esta usando drawRescaledImage()."
    exit 1
fi

echo "Software cursor draw method: OK"
echo "OK: software cursor validado."
echo
echo

echo "========================================"
echo " Configurando CMake"
echo "========================================"

cmake -S "$SRC_DIR" -B "$BUILD/cmake" \
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

cmake --build "$BUILD/cmake" -j"$(nproc)"

echo

echo "========================================"
echo " Instalando Mana"
echo "========================================"

cmake --install "$BUILD/cmake"

echo

echo "========================================"
echo " Procurando executavel"
echo "========================================"

BIN="$(find "$INSTALL" -type f -name mana | head -1)"

if [ -z "$BIN" ]; then
    echo "ERRO: executavel Mana nao foi encontrado"
    echo
    echo "Conteudo do INSTALL:"
    find "$INSTALL" -maxdepth 5 -type f -print || true
    exit 1
fi

echo
echo "Executavel encontrado:"
echo "$BIN"

echo

echo "========================================"
echo " Copiando executavel"
echo "========================================"

cp "$BIN" "$DIST/mana.aarch64"

chmod +x "$DIST/mana.aarch64"

echo

echo "========================================"
echo " Informacoes do ELF"
echo "========================================"

file "$DIST/mana.aarch64"

echo

echo "=== GLIBC requerida ==="

readelf --version-info "$DIST/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu || true

echo

echo "=== Dependencias dinamicas ==="

readelf -d "$DIST/mana.aarch64" \
    | grep NEEDED || true

echo

echo "=== RPATH / RUNPATH ==="

readelf -d "$DIST/mana.aarch64" \
    | grep -E 'RPATH|RUNPATH' || true

echo

echo "========================================"
echo " Salvando diagnosticos"
echo "========================================"

{
    echo "========================================"
    echo " Mana 0.8.0 AArch64 Diagnostics"
    echo "========================================"
    echo

    echo "=== FILE ==="

    file "$DIST/mana.aarch64"

    echo

    echo "=== GLIBC ==="

    readelf --version-info "$DIST/mana.aarch64" \
        | grep -o 'GLIBC_[0-9.]*' \
        | sort -Vu || true

    echo

    echo "=== NEEDED ==="

    readelf -d "$DIST/mana.aarch64" \
        | grep NEEDED || true

    echo

    echo "=== RPATH/RUNPATH ==="

    readelf -d "$DIST/mana.aarch64" \
        | grep -E 'RPATH|RUNPATH' || true

    echo

    echo "=== GUICHAN ==="

    cd "$SRC_DIR/libs/guichan"

    git describe --tags --always
    git rev-parse HEAD

    cd "$ROOT"

    echo

    echo "=== ENET ==="

    cd "$SRC_DIR/libs/enet"

    git rev-parse HEAD

    cd "$ROOT"

} > "$DIST/diagnostics.txt"

echo

echo "========================================"
echo " Verificando GLIBC incompativel"
echo "========================================"

if readelf --version-info "$DIST/mana.aarch64" \
    | grep -q 'GLIBC_2.43'; then

    echo "ERRO: o executavel ainda exige GLIBC_2.43"
    exit 1
fi

echo
echo "GLIBC 2.43 nao encontrada."

echo

echo "========================================"
echo " PREPARANDO PACOTE PORTMASTER"
echo "========================================"

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

echo

echo "=== Preparando launcher Mana.sh ==="

echo "Criando/atualizando launcher Mana.sh..."

cat > "$PORT/Mana.sh" <<'EOF'
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

echo "========================================"
echo " Mana 0.8.0 PortMaster"
echo "========================================"
echo "GAMEDIR=$GAMEDIR"
echo "CONTROLFOLDER=$controlfolder"
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
    "$GPTOKEYB2" "$GAME" -c "./mana.gptk2" &
    GPTOKEYB_PID=$!
elif [ -n "${GPTOKEYB:-}" ] && [ -f "./mana.gptk" ]; then
    echo "Starting GPTOKEYB..."
    "$GPTOKEYB" "$GAME" -c "./mana.gptk" &
    GPTOKEYB_PID=$!
else
    echo "WARNING: GPTOKEYB2/GPTOKEYB nao encontrado."
fi

echo "Starting Mana..."
echo "$GAME"
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

chmod +x "$PORT/Mana.sh"

echo "OK: port/Mana.sh atualizado."

echo

echo "=== Verificando launcher ==="

if [ ! -f "$PORT/Mana.sh" ]; then
    echo "ERRO: nao foi possivel criar port/Mana.sh"
    exit 1
fi

if [ ! -s "$PORT/Mana.sh" ]; then
    echo "ERRO: port/Mana.sh esta vazio"
    exit 1
fi

echo "Launcher encontrado:"
ls -lh "$PORT/Mana.sh"

echo

echo "=== Copiando arquivos do PortMaster ==="

cp "$PORT/Mana.sh" "$PACKAGE/"

if [ -f "$PORT/README.md" ]; then
    cp "$PORT/README.md" "$PACKAGE/"
fi

if [ -f "$PORT/gameinfo.xml" ]; then
    cp "$PORT/gameinfo.xml" "$PACKAGE/"
fi

if [ -f "$PORT/port.json" ]; then
    cp "$PORT/port.json" "$PACKAGE/"
fi

if [ -f "$PORT/screenshot.png" ]; then
    cp "$PORT/screenshot.png" "$PACKAGE/"
fi

echo

echo "=== Copiando dados do jogo ==="

if [ -d "$PORT/mana/data" ]; then
    cp -a "$PORT/mana/data" "$PACKAGE/mana/"
else
    echo "AVISO: port/mana/data nao encontrado"
fi

echo

echo "=== Copiando licencas ==="

if [ -d "$PORT/mana/licenses" ]; then
    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"
fi

echo

echo "=== Criando configuracao GPTK ==="

mkdir -p "$PORT/mana"

cat > "$PORT/mana/mana.gptk" <<'EOF'
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

cat > "$PORT/mana/mana.gptk2" <<'EOF'
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

echo "OK: mana.gptk criado."
echo "OK: mana.gptk2 criado."

echo
echo "=== Copiando configuracao GPTK ==="

cp "$PORT/mana/mana.gptk" "$PACKAGE/mana/"
cp "$PORT/mana/mana.gptk2" "$PACKAGE/mana/"

echo "OK: mana.gptk copiado."
echo "OK: mana.gptk2 copiado."

echo
echo

echo "========================================"
echo " Instalando novo executavel"
echo "========================================"

cp "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x "$PACKAGE/Mana.sh"
chmod +x "$PACKAGE/mana/mana.aarch64"

echo

echo "========================================"
echo " Conteudo final do pacote"
echo "========================================"

find "$PACKAGE" -maxdepth 5 -type f -print

echo

echo "========================================"
echo " Verificando launcher final"
echo "========================================"

if [ ! -f "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta no pacote final"
    exit 1
fi

if [ ! -x "$PACKAGE/Mana.sh" ]; then
    echo "ERRO: Mana.sh nao esta executavel"
    exit 1
fi

if [ ! -f "$PACKAGE/mana/mana.aarch64" ]; then
    echo "ERRO: mana.aarch64 nao esta no pacote final"
    exit 1
fi

echo "OK: Mana.sh presente."
echo "OK: mana.aarch64 presente."

echo

echo "========================================"
echo " Gerando ZIP"
echo "========================================"

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

echo "Arquivos gerados:"

ls -lh "$DIST/"

echo

echo "ZIP:"

ls -lh "$DIST/mana-r36s-portmaster-aarch64.zip"

echo

echo "Executavel:"

ls -lh "$DIST/mana.aarch64"

echo

echo "Diagnosticos:"

ls -lh "$DIST/diagnostics.txt"

echo

echo "========================================"
echo " FIM"
echo "========================================"
