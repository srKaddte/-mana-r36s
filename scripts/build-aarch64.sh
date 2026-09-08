#!/usr/bin/env bash

set -euo pipefail

ROOT="/workspace"

SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.build"
SRC="$WORK/mana-master"
BUILD="$WORK/build"
INSTALL="$WORK/install"

PORT="$ROOT/port"
DIST="$ROOT/dist"

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

echo "========================================"
echo " Mana R36S PortMaster AArch64"
echo "========================================"

echo ""
echo "ROOT: $ROOT"
echo "SOURCE: $SRC_ARCHIVE"
echo ""

# ============================================================
# LIMPEZA
# ============================================================

rm -rf "$WORK"
rm -rf "$DIST"

mkdir -p "$WORK"
mkdir -p "$DIST"

# ============================================================
# DEPENDÊNCIAS
# ============================================================

export DEBIAN_FRONTEND=noninteractive

echo "========================================"
echo " Instalando dependências"
echo "========================================"

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
# SOURCE
# ============================================================

if [ ! -f "$SRC_ARCHIVE" ]; then

    echo ""
    echo "ERRO: source não encontrado:"
    echo "$SRC_ARCHIVE"
    echo ""

    exit 1
fi

echo "========================================"
echo " Extraindo Mana"
echo "========================================"

tar \
    -xzf "$SRC_ARCHIVE" \
    -C "$WORK"

if [ ! -d "$SRC" ]; then

    FOUND="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)"

    if [ -z "$FOUND" ]; then

        echo "ERRO: diretório do Mana não encontrado."

        exit 1
    fi

    SRC="$FOUND"
fi

echo ""
echo "Source:"
echo "$SRC"
echo ""

# ============================================================
# DEPENDÊNCIA GUICHAN
# ============================================================

echo "========================================"
echo " Preparando Guichan 0.8.3"
echo "========================================"

rm -rf "$SRC/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC/libs/guichan"

# ============================================================
# DEPENDÊNCIA ENET
# ============================================================

echo "========================================"
echo " Preparando ENet 1.3.18"
echo "========================================"

rm -rf "$SRC/libs/enet"

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/lsalzman/enet.git \
    "$SRC/libs/enet"

# ============================================================
# PATCHES
# ============================================================

echo "========================================"
echo " Aplicando patches"
echo "========================================"

python3 - "$SRC" <<'PY'

import re
import sys
from pathlib import Path

src = Path(sys.argv[1])

print("Source:", src)

# ============================================================
# SDL2_ttf - CMAKE
# ============================================================

print("=== Corrigindo requisito SDL2_ttf ===")

for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except Exception:
        continue

    original = text

    text = text.replace(
        "SDL2_ttf>=2.0.18",
        "SDL2_ttf>=2.0.15"
    )

    text = text.replace(
        "SDL2_ttf >= 2.0.18",
        "SDL2_ttf >= 2.0.15"
    )

    text = text.replace(
        "SDL2_ttf>= 2.0.18",
        "SDL2_ttf>= 2.0.15"
    )

    text = text.replace(
        "SDL2_ttf >=2.0.18",
        "SDL2_ttf >=2.0.15"
    )

    text = text.replace(
        "SDL2_ttf>=2.0.18",
        "SDL2_ttf>=2.0.15"
    )

    if text != original:

        path.write_text(text)

        print("Patched:", path)

# ============================================================
# VALIDAR SDL2_ttf
# ============================================================

print("=== Verificando SDL2_ttf ===")

for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except Exception:
        continue

    if re.search(
        r"SDL2_ttf\s*(?:>=|>)\s*2\.0\.18",
        text
    ):

        raise SystemExit(
            "ERRO: SDL2_ttf >= 2.0.18 ainda existe em "
            + str(path)
        )

print("SDL2_ttf requirement OK")

# ============================================================
# SDL_ttf - TTF_SetFontSize
# ============================================================

print("=== Corrigindo TTF_SetFontSize ===")

for path in src.rglob("*.cpp"):

    try:
        text = path.read_text()
    except Exception:
        continue

    if "TTF_SetFontSize" not in text:
        continue

    original = text

    text = re.sub(
        r"(?m)^[ \t]*TTF_SetFontSize\s*\([^;]*\);\s*$",
        "        /* SDL_ttf 2.0.15 compatibility. */",
        text
    )

    text = re.sub(
        r"TTF_SetFontSize\s*\([^;]*\);",
        "/* SDL_ttf 2.0.15 compatibility. */",
        text
    )

    if text != original:

        path.write_text(text)

        print("Patched:", path)

# ============================================================
# VALIDAR TTF_SetFontSize
# ============================================================

print("=== Verificando chamadas TTF_SetFontSize ===")

for path in src.rglob("*.cpp"):

    try:
        text = path.read_text()
    except Exception:
        continue

    if re.search(
        r"TTF_SetFontSize\s*\(",
        text
    ):

        raise SystemExit(
            "ERRO: TTF_SetFontSize() ainda existe em "
            + str(path)
        )

print("TTF_SetFontSize OK")

# ============================================================
# GUI.H
# ============================================================

print("=== Corrigindo cursor no gui.h ===")

gui_h = src / "src/gui/gui.h"

if not gui_h.exists():

    raise SystemExit(
        "ERRO: gui.h não encontrado."
    )

text = gui_h.read_text()

# ------------------------------------------------------------
# Include ImageSet
# ------------------------------------------------------------

if '#include "resources/imageset.h"' not in text:

    marker = '#include "resources/theme.h"'

    if marker in text:

        text = text.replace(
            marker,
            marker + '\n#include "resources/imageset.h"',
            1
        )

    else:

        text = (
            '#include "resources/imageset.h"\n'
            + text
        )

# ------------------------------------------------------------
# REMOVER TODAS AS DECLARAÇÕES DUPLICADAS
# ------------------------------------------------------------

text = re.sub(
    r"(?m)^[ \t]*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;\s*\n?",
    "",
    text
)

text = re.sub(
    r"(?m)^[ \t]*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*\n?",
    "",
    text
)

# ------------------------------------------------------------
# INSERIR EXATAMENTE UMA
# ------------------------------------------------------------

marker = "    bool mCustomCursor = false;"

if marker not in text:

    raise SystemExit(
        "ERRO: marcador mCustomCursor não encontrado."
    )

cursor_members = """    ResourceRef<ImageSet> mSoftwareCursor;
    bool mSoftwareCursorVisible = true;
"""

text = text.replace(
    marker,
    cursor_members + marker,
    1
)

gui_h.write_text(text)

# ============================================================
# GUI.CPP
# ============================================================

print("=== Corrigindo cursor no gui.cpp ===")

gui_cpp = src / "src/gui/gui.cpp"

if not gui_cpp.exists():

    raise SystemExit(
        "ERRO: gui.cpp não encontrado."
    )

text = gui_cpp.read_text()

# ============================================================
# REMOVER PATCHES ANTIGOS DO CURSOR
# ============================================================

text = re.sub(
    r"""
    \n?[ \t]*
    //\s*PortMaster/R36S software cursor\.
    [ \t]*mSoftwareCursor\s*=
    ResourceManager::getInstance\(\)\.getImageSet\(
    [ \t]*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);
    [ \t]*
    SDL_ShowCursor\(SDL_DISABLE\);
    """,
    "\n",
    text,
    flags=re.VERBOSE
)

text = re.sub(
    r"""
    \n?[ \t]*
    //\s*PortMaster/R36S can receive GPTK mouse input without displaying an SDL
    [ \t]*//.*?
    mSoftwareCursor\s*=
    ResourceManager::getInstance\(\)\.getImageSet\(
    [ \t]*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);
    [ \t]*
    SDL_ShowCursor\(SDL_DISABLE\);
    """,
    "\n",
    text,
    flags=re.VERBOSE
)

# ============================================================
# GARANTIR INICIALIZAÇÃO DO CURSOR
# ============================================================

cursor_init = """    // R36S software cursor.
    mSoftwareCursor =
        ResourceManager::getInstance().getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);

"""

# Remove qualquer inicialização antiga restante.

text = re.sub(
    r"""
    [ \t]*mSoftwareCursor\s*=
    \s*ResourceManager::getInstance\(\)\.getImageSet\(
    \s*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);
    """,
    "",
    text,
    flags=re.VERBOSE
)

# Remove múltiplos SDL_ShowCursor ENABLE/DISABLE antes de
# recolocar o disable no construtor.

# ------------------------------------------------------------
# Procurar setInput(guiInput)
# ------------------------------------------------------------

marker = "    setInput(guiInput);"

if marker not in text:

    raise SystemExit(
        "ERRO: setInput(guiInput) não encontrado."
    )

text = text.replace(
    marker,
    marker + "\n\n" + cursor_init,
    1
)

# ============================================================
# DESABILITAR CURSOR HARDWARE
# ============================================================

text = text.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)

# ============================================================
# DRAW
# ============================================================

print("=== Corrigindo desenho do cursor ===")

# Remover blocos antigos de software cursor do draw.

text = re.sub(
    r"""
    \n?[ \t]*
    if\s*\(\s*mSoftwareCursorVisible\s*&&
    \s*mSoftwareCursor\s*&&
    \s*mSoftwareCursor->size\(\)\s*>\s*0\s*\)
    \s*\{
    .*?
    \}
    """,
    "\n",
    text,
    flags=re.VERBOSE | re.DOTALL
)

text = re.sub(
    r"""
    \n?[ \t]*
    if\s*\(\s*mSoftwareCursor\s*&&
    \s*mSoftwareCursor->size\(\)\s*>\s*0\s*\)
    \s*\{
    .*?
    \}
    """,
    "\n",
    text,
    flags=re.VERBOSE | re.DOTALL
)

# ------------------------------------------------------------
# Inserir no final de Gui::draw()
# ------------------------------------------------------------

draw_marker = "void Gui::draw()\n{"

if draw_marker not in text:

    raise SystemExit(
        "ERRO: Gui::draw() não encontrado."
    )

# Encontrar o fechamento da função draw() usando contagem de
# chaves.

start = text.index(draw_marker)

brace_start = text.index(
    "{",
    start
)

depth = 0
end = None

for i in range(brace_start, len(text)):

    char = text[i]

    if char == "{":
        depth += 1

    elif char == "}":

        depth -= 1

        if depth == 0:

            end = i
            break

if end is None:

    raise SystemExit(
        "ERRO: não foi possível localizar fim de Gui::draw()."
    )

cursor_draw = """

    // R36S software cursor.
    if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        auto *graphics =
            static_cast<Graphics *>(mGraphics);

        if (graphics)
        {
            graphics->drawImage(
                mSoftwareCursor->get(0),
                mMouseX - 15,
                mMouseY - 17);
        }
    }
"""

text = (
    text[:end]
    + cursor_draw
    + text[end:]
)

# ============================================================
# F12
# ============================================================

print("=== Corrigindo toggle F12 ===")

# ------------------------------------------------------------
# Remover qualquer bloco anterior nosso.
# ------------------------------------------------------------

text = re.sub(
    r"""
    \n?[ \t]*
    //\s*SELECT is mapped to F12 by mana\.gptk\.
    .*?
    if\s*\(\s*event\.getKey\(\)\.getValue\(\)\s*==\s*Key::F12\s*\)
    \s*\{
    .*?
    mSoftwareCursorVisible\s*=
    \s*!mSoftwareCursorVisible\s*;
    .*?
    event\.consume\(\)\s*;
    \s*return\s*;
    \s*\}
    """,
    "\n",
    text,
    flags=re.VERBOSE | re.DOTALL
)

# ------------------------------------------------------------
# Encontrar keyPressed
# ------------------------------------------------------------

key_marker = "void Gui::keyPressed(gcn::KeyEvent &event)\n{"

if key_marker not in text:

    raise SystemExit(
        "ERRO: Gui::keyPressed() não encontrado."
    )

toggle = """
    // SELECT -> F12.
    // F12 altera SOMENTE a visibilidade do cursor.
    // O mouse continua ativo.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();
        return;
    }

"""

text = text.replace(
    key_marker,
    key_marker + toggle,
    1
)

gui_cpp.write_text(text)

# ============================================================
# VALIDAR GUI.H
# ============================================================

print("========================================")
print(" VALIDANDO GUI.H")
print("========================================")

h = gui_h.read_text()

cursor_count = len(
    re.findall(
        r"\bResourceRef<ImageSet>\s+mSoftwareCursor\s*;",
        h
    )
)

visible_count = len(
    re.findall(
        r"\bbool\s+mSoftwareCursorVisible\s*=\s*true\s*;",
        h
    )
)

print(
    "mSoftwareCursor:",
    cursor_count
)

print(
    "mSoftwareCursorVisible:",
    visible_count
)

if cursor_count != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursor deve existir exatamente uma vez."
    )

if visible_count != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursorVisible deve existir exatamente uma vez."
    )

# ============================================================
# VALIDAR GUI.CPP
# ============================================================

print("========================================")
print(" VALIDANDO GUI.CPP")
print("========================================")

c = gui_cpp.read_text()

# ------------------------------------------------------------
# F12 REAL
# ------------------------------------------------------------

f12_count = len(
    re.findall(
        r"Key::F12",
        c
    )
)

print(
    "Key::F12:",
    f12_count
)

if f12_count != 1:

    raise SystemExit(
        "ERRO: Key::F12 deve existir exatamente uma vez."
    )

# ------------------------------------------------------------
# VISIBILIDADE
# ------------------------------------------------------------

visibility_count = len(
    re.findall(
        r"mSoftwareCursorVisible\s*=",
        c
    )
)

print(
    "mSoftwareCursorVisible assignments:",
    visibility_count
)

if visibility_count < 1:

    raise SystemExit(
        "ERRO: toggle do cursor não encontrado."
    )

# ------------------------------------------------------------
# CURSOR SOFTWARE
# ------------------------------------------------------------

if "mSoftwareCursor->get(0)" not in c:

    raise SystemExit(
        "ERRO: desenho do cursor não encontrado."
    )

# ------------------------------------------------------------
# HARDWARE CURSOR
# ------------------------------------------------------------

if "SDL_ShowCursor(SDL_DISABLE);" not in c:

    raise SystemExit(
        "ERRO: SDL cursor não foi desabilitado."
    )

print("GUI.CPP OK")

# ============================================================
# VALIDAR SDL_ttf
# ============================================================

print("========================================")
print(" VALIDANDO SDL_ttf")
print("========================================")

for path in src.rglob("*.cpp"):

    try:
        content = path.read_text()
    except Exception:
        continue

    if re.search(
        r"TTF_SetFontSize\s*\(",
        content
    ):

        raise SystemExit(
            "ERRO: TTF_SetFontSize() encontrado em "
            + str(path)
        )

print("SDL_ttf OK")

# ============================================================
# FIM DOS PATCHES
# ============================================================

print("")
print("========================================")
print(" TODOS OS PATCHES ESTÃO OK")
print("========================================")
print("")

PY

# ============================================================
# CONFIGURAÇÃO
# ============================================================

echo "========================================"
echo " Configurando CMake"
echo "========================================"

rm -rf "$BUILD"
mkdir -p "$BUILD"

cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF

# ============================================================
# BUILD
# ============================================================

echo "========================================"
echo " Compilando Mana"
echo "========================================"

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"

# ============================================================
# INSTALL
# ============================================================

echo "========================================"
echo " Instalando"
echo "========================================"

cmake \
    --install "$BUILD"

# ============================================================
# LOCALIZAR BINÁRIO
# ============================================================

echo "========================================"
echo " Procurando executável"
echo "========================================"

BIN="$(
    find "$INSTALL" \
        -type f \
        -name "mana" \
        -perm -u+x \
        | head -1
)"

if [ -z "$BIN" ]; then

    echo "ERRO: executável mana não encontrado."

    echo ""
    echo "Arquivos instalados:"
    find "$INSTALL" -type f -print

    exit 1
fi

echo ""
echo "Executável:"
echo "$BIN"
echo ""

# ============================================================
# DIST
# ============================================================

mkdir -p "$DIST"

cp \
    "$BIN" \
    "$DIST/mana.aarch64"

chmod +x \
    "$DIST/mana.aarch64"

# ============================================================
# VALIDAR AARCH64
# ============================================================

echo "========================================"
echo " Validando arquitetura"
echo "========================================"

file "$DIST/mana.aarch64"

if ! file "$DIST/mana.aarch64" \
    | grep -qi "aarch64"; then

    echo "ERRO: binário não é AArch64."

    exit 1
fi

# ============================================================
# VALIDAR GLIBC
# ============================================================

echo "========================================"
echo " Validando GLIBC"
echo "========================================"

readelf \
    --version-info \
    "$DIST/mana.aarch64" \
    | grep -o "GLIBC_[0-9.]*" \
    | sort -Vu \
    || true

if readelf \
    --version-info \
    "$DIST/mana.aarch64" \
    | grep -q "GLIBC_2.43"; then

    echo ""
    echo "ERRO: binário exige GLIBC_2.43."
    echo ""

    exit 1
fi

# ============================================================
# PORTMASTER
# ============================================================

echo "========================================"
echo " Preparando PortMaster"
echo "========================================"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"
mkdir -p "$PACKAGE/mana"

# ============================================================
# MANA.SH
# ============================================================

cat > "$PACKAGE/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

GAMEDIR="/roms/ports/mana"
CONFDIR="$GAMEDIR/config"

GAME="$GAMEDIR/mana/mana.aarch64"

export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"

export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"

export SDL_GAMECONTROLLERCONFIG="${SDL_GAMECONTROLLERCONFIG:-}"

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

cd "$GAMEDIR"

if [ -x "/opt/system/Tools/PortMaster/gptokeyb2/gptokeyb2" ]; then

    GPTOKEYB="/opt/system/Tools/PortMaster/gptokeyb2/gptokeyb2"

elif [ -x "/opt/system/Tools/PortMaster/gptokeyb2" ]; then

    GPTOKEYB="/opt/system/Tools/PortMaster/gptokeyb2"

else

    GPTOKEYB="gptokeyb2"

fi

"$GPTOKEYB" \
    "$GAME" \
    -c "$GAMEDIR/mana/mana.gptk.0" &

GPTK_PID=$!

cleanup()
{
    kill "$GPTK_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"
EOF

chmod +x "$PACKAGE/Mana.sh"

# ============================================================
# GPTK
# ============================================================

cat > "$PACKAGE/mana/mana.gptk.0" <<'EOF'
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
# BINÁRIO
# ============================================================

cp \
    "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x \
    "$PACKAGE/mana/mana.aarch64"

# ============================================================
# DATA
# ============================================================

if [ -d "$PORT/mana/data" ]; then

    cp -a \
        "$PORT/mana/data" \
        "$PACKAGE/mana/"

else

    echo ""
    echo "AVISO: port/mana/data não existe."
    echo ""

fi

# ============================================================
# PORT.JSON
# ============================================================

cat > "$PACKAGE/port.json" <<'EOF'
{
    "version": 1,
    "name": "mana",
    "items": [
        {
            "title": "The Mana World",
            "name": "mana",
            "desc": "The Mana World",
            "inst": "Copy the Mana World game data into the data directory.",
            "genres": [
                "RPG",
                "MMORPG"
            ],
            "porter": "Kaddte",
            "runtime": "native",
            "reqs": [
                "aarch64"
            ],
            "arch": [
                "aarch64"
            ],
            "min_glibc": "2.29"
        }
    ]
}
EOF

# ============================================================
# README
# ============================================================

cat > "$PACKAGE/README.md" <<'EOF'
# Mana World - R36S PortMaster

Native AArch64 PortMaster build.

## Controls

SELECT:
Toggle software cursor visibility.

RIGHT ANALOG:
Move mouse cursor.

R3:
Left mouse button.

L3:
Right mouse button.

START:
Enter.

A:
Space.

B:
Escape.

The mouse remains active while normal controller controls continue working.
EOF

# ============================================================
# DIAGNÓSTICOS
# ============================================================

echo "========================================"
echo " Gerando diagnósticos"
echo "========================================"

{
    echo "=== FILE ==="
    file "$DIST/mana.aarch64"

    echo ""
    echo "=== GLIBC ==="

    readelf \
        --version-info \
        "$DIST/mana.aarch64" \
        | grep -o "GLIBC_[0-9.]*" \
        | sort -Vu \
        || true

    echo ""
    echo "=== NEEDED ==="

    readelf \
        -d \
        "$DIST/mana.aarch64" \
        | grep NEEDED \
        || true

    echo ""
    echo "=== GUI.H CURSOR ==="

    grep \
        -n \
        "mSoftwareCursor" \
        "$SRC/src/gui/gui.h" \
        || true

    echo ""
    echo "=== GUI.CPP F12 ==="

    grep \
        -n \
        "Key::F12" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo ""
    echo "=== GPTK ==="

    cat \
        "$PACKAGE/mana/mana.gptk.0"

} > "$DIST/diagnostics.txt"

# ============================================================
# ZIP
# ============================================================

echo "========================================"
echo " Criando ZIP PortMaster"
echo "========================================"

cd "$PACKAGE"

zip \
    -r \
    "$DIST/mana-r36s-portmaster-aarch64.zip" \
    .

cd "$ROOT"

# ============================================================
# FINAL
# ============================================================

echo ""
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"

echo ""
echo "Arquivos:"

find \
    "$DIST" \
    -maxdepth 2 \
    -type f \
    -printf "%p\n"

echo ""
echo "========================================"
echo " MANA R36S PORTMASTER PRONTO"
echo "========================================"
