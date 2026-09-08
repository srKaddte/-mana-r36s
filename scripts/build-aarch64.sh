#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Mana 0.8.0 - R36S / PortMaster / AArch64
#
# Build completo
#
# Correções:
#   - SDL2_ttf 2.0.15
#   - TTF_SetFontSize incompatível
#   - Guichan 0.8.3
#   - ENet 1.3.18
#   - software cursor
#   - cursor duplicado Image/ImageSet
#   - SELECT -> F12
#   - F12 SOMENTE alterna visibilidade
#   - mouse continua ativo
#   - controles normais continuam funcionando
#   - validação AArch64
#   - validação GLIBC
#   - geração PortMaster ZIP
# ============================================================


ROOT="/workspace"

SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.build"
SRC="$WORK/mana-master"

BUILD="$WORK/build"
INSTALL="$WORK/install"

PORT="$ROOT/port"
DIST="$ROOT/dist"

PACKAGE="$DIST/mana-r36s-portmaster-aarch64"


echo ""
echo "========================================"
echo " Mana 0.8.0"
echo " R36S / PortMaster / AArch64"
echo "========================================"
echo ""


# ============================================================
# LIMPEZA
# ============================================================

echo "=== Limpando build anterior ==="

rm -rf "$WORK"
rm -rf "$DIST"

mkdir -p "$WORK"
mkdir -p "$DIST"


# ============================================================
# DEPENDÊNCIAS
# ============================================================

echo ""
echo "========================================"
echo " Instalando dependências"
echo "========================================"
echo ""

export DEBIAN_FRONTEND=noninteractive

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
# VALIDAR SOURCE
# ============================================================

echo ""
echo "========================================"
echo " Verificando source"
echo "========================================"
echo ""

if [ ! -f "$SRC_ARCHIVE" ]; then

    echo "ERRO:"
    echo "Source não encontrado:"
    echo "$SRC_ARCHIVE"

    exit 1
fi


# ============================================================
# EXTRAIR SOURCE
# ============================================================

echo ""
echo "========================================"
echo " Extraindo Mana"
echo "========================================"
echo ""

tar \
    -xzf "$SRC_ARCHIVE" \
    -C "$WORK"


if [ ! -d "$SRC" ]; then

    FOUND="$(
        find "$WORK" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            | head -1
    )"

    if [ -z "$FOUND" ]; then

        echo "ERRO:"
        echo "Diretório do source não encontrado."

        exit 1
    fi

    SRC="$FOUND"
fi


echo "Source:"
echo "$SRC"


# ============================================================
# GUICHAN
# ============================================================

echo ""
echo "========================================"
echo " Preparando Guichan 0.8.3"
echo "========================================"
echo ""

rm -rf "$SRC/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC/libs/guichan"


# ============================================================
# ENET
# ============================================================

echo ""
echo "========================================"
echo " Preparando ENet 1.3.18"
echo "========================================"
echo ""

rm -rf "$SRC/libs/enet"

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/lsalzman/enet.git \
    "$SRC/libs/enet"


# ============================================================
# PATCHES DO SOURCE
# ============================================================

echo ""
echo "========================================"
echo " Aplicando patches"
echo "========================================"
echo ""


python3 - "$SRC" <<'PY'

import re
import sys
from pathlib import Path


src = Path(sys.argv[1])


print("Source:", src)


# ============================================================
# SDL2_ttf - CMAKE
# ============================================================

print("")
print("=== Corrigindo requisito SDL2_ttf ===")


for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except Exception:
        continue


    original = text


    replacements = [

        (
            "SDL2_ttf>=2.0.18",
            "SDL2_ttf>=2.0.15"
        ),

        (
            "SDL2_ttf >= 2.0.18",
            "SDL2_ttf >= 2.0.15"
        ),

        (
            "SDL2_ttf>= 2.0.18",
            "SDL2_ttf>=2.0.15"
        ),

        (
            "SDL2_ttf >=2.0.18",
            "SDL2_ttf >=2.0.15"
        ),

        (
            "SDL2_ttf>=2.0.18",
            "SDL2_ttf>=2.0.15"
        ),

        (
            "SDL2_ttf >=2.0.18",
            "SDL2_ttf >=2.0.15"
        ),
    ]


    for old, new in replacements:

        text = text.replace(
            old,
            new
        )


    if text != original:

        path.write_text(text)

        print(
            "Patched:",
            path
        )


# ============================================================
# VALIDAR SDL2_ttf
# ============================================================

print("")
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
# TTF_SetFontSize
# ============================================================

print("")
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

        print(
            "Patched:",
            path
        )


# ============================================================
# VALIDAR TTF_SetFontSize
# ============================================================

print("")
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

print("")
print("=== Corrigindo cursor no gui.h ===")


gui_h = src / "src/gui/gui.h"


if not gui_h.exists():

    raise SystemExit(
        "ERRO: gui.h não encontrado."
    )


text = gui_h.read_text()


# ============================================================
# INCLUDE IMAGESET
# ============================================================

if '#include "resources/imageset.h"' not in text:

    marker = '#include "resources/theme.h"'


    if marker in text:

        text = text.replace(
            marker,
            marker +
            '\n#include "resources/imageset.h"',
            1
        )

    else:

        text = (
            '#include "resources/imageset.h"\n'
            + text
        )


# ============================================================
# CORREÇÃO DEFINITIVA DO DUPLICATE
#
# Remove QUALQUER declaração de mSoftwareCursor.
#
# Isso inclui:
#
# ResourceRef<Image> mSoftwareCursor;
#
# ResourceRef<ImageSet> mSoftwareCursor;
#
# etc.
# ============================================================

lines = text.splitlines()

clean = []


for line in lines:

    stripped = line.strip()


    # --------------------------------------------------------
    # Qualquer declaração de ResourceRef que tenha
    # mSoftwareCursor.
    # --------------------------------------------------------

    if (
        "mSoftwareCursor" in stripped
        and "ResourceRef<" in stripped
        and stripped.endswith(";")
    ):

        print(
            "Removendo declaração antiga:",
            stripped
        )

        continue


    # --------------------------------------------------------
    # Qualquer declaração antiga da flag.
    # --------------------------------------------------------

    if (
        "mSoftwareCursorVisible" in stripped
        and stripped.startswith("bool ")
        and stripped.endswith(";")
    ):

        print(
            "Removendo flag antiga:",
            stripped
        )

        continue


    clean.append(line)


text = "\n".join(clean) + "\n"


# ============================================================
# INSERIR UMA ÚNICA DECLARAÇÃO
# ============================================================

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
# VALIDAR GUI.H
# ============================================================

h = gui_h.read_text()


cursor_declarations = []


for number, line in enumerate(
    h.splitlines(),
    start=1
):

    if (
        "ResourceRef<"
        in line
        and "mSoftwareCursor"
        in line
        and line.strip().endswith(";")
    ):

        cursor_declarations.append(
            (number, line.strip())
        )


print("")
print("=== DECLARAÇÕES FINAIS ===")


for number, line in cursor_declarations:

    print(
        f"{number}: {line}"
    )


if len(cursor_declarations) != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursor precisa existir "
        "exatamente uma vez."
    )


if cursor_declarations[0][1] != \
        "ResourceRef<ImageSet> mSoftwareCursor;":

    raise SystemExit(
        "ERRO: tipo final de mSoftwareCursor está incorreto."
    )


visible_declarations = []


for number, line in enumerate(
    h.splitlines(),
    start=1
):

    if (
        "bool mSoftwareCursorVisible = true;"
        in line
    ):

        visible_declarations.append(
            (number, line.strip())
        )


if len(visible_declarations) != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursorVisible precisa "
        "existir exatamente uma vez."
    )


print("")
print("GUI.H CURSOR OK")


# ============================================================
# GUI.CPP
# ============================================================

print("")
print("=== Corrigindo cursor no gui.cpp ===")


gui_cpp = src / "src/gui/gui.cpp"


if not gui_cpp.exists():

    raise SystemExit(
        "ERRO: gui.cpp não encontrado."
    )


cpp = gui_cpp.read_text()


# ============================================================
# REMOVER INICIALIZAÇÕES ANTIGAS
# ============================================================

cpp = re.sub(
    r"""
    [ \t]*mSoftwareCursor\s*=
    \s*ResourceManager::getInstance\(\)
    \.getImageSet\(
    \s*mTheme->resolvePath\("mouse\.png"\)
    \s*,\s*40\s*,\s*40\s*\)
    \s*;
    """,
    "",
    cpp,
    flags=re.VERBOSE
)


# ============================================================
# REMOVER SDL_SHOWCURSOR ENABLE
# ============================================================

cpp = cpp.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


# ============================================================
# GARANTIR INICIALIZAÇÃO
# ============================================================

cursor_init = """
    // R36S software cursor.
    mSoftwareCursor =
        ResourceManager::getInstance().getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);

"""


if (
    "mSoftwareCursor ="
    not in cpp
):

    marker = "    setInput(guiInput);"


    if marker not in cpp:

        raise SystemExit(
            "ERRO: setInput(guiInput) não encontrado."
        )


    cpp = cpp.replace(
        marker,
        marker +
        "\n" +
        cursor_init,
        1
    )


# ============================================================
# DRAW
# ============================================================

print("")
print("=== Corrigindo desenho do cursor ===")


draw_marker = "void Gui::draw()\n{"


if draw_marker not in cpp:

    raise SystemExit(
        "ERRO: Gui::draw() não encontrado."
    )


# ------------------------------------------------------------
# Se já existe o bloco de cursor, somente garante a flag.
# ------------------------------------------------------------

if "mSoftwareCursor->get(0)" in cpp:

    cpp = cpp.replace(
        "if (mSoftwareCursor && mSoftwareCursor->size() > 0)",
        """if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)""",
        1
    )


# ------------------------------------------------------------
# Se não existe desenho, inserir no draw.
# ------------------------------------------------------------

else:

    start = cpp.index(draw_marker)

    brace_start = cpp.index(
        "{",
        start
    )


    depth = 0
    end = None


    for index in range(
        brace_start,
        len(cpp)
    ):

        char = cpp[index]


        if char == "{":

            depth += 1


        elif char == "}":

            depth -= 1


            if depth == 0:

                end = index

                break


    if end is None:

        raise SystemExit(
            "ERRO: fim de Gui::draw() não encontrado."
        )


    cursor_draw = """

    // R36S software cursor.
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


    cpp = (
        cpp[:end]
        +
        cursor_draw
        +
        cpp[end:]
    )


# ============================================================
# F12
# ============================================================

print("")
print("=== Corrigindo toggle F12 ===")


# ------------------------------------------------------------
# Remover blocos antigos que usam
# mSoftwareCursorVisible.
#
# Fazemos isso por análise de chaves para não depender
# de espaçamento.
# ------------------------------------------------------------

while True:

    match = re.search(
        r"if\s*\([^{}]*Key::F12[^{}]*\)\s*\{",
        cpp
    )


    if not match:

        break


    brace_start = cpp.find(
        "{",
        match.start()
    )


    depth = 0
    end = None


    for index in range(
        brace_start,
        len(cpp)
    ):

        char = cpp[index]


        if char == "{":

            depth += 1


        elif char == "}":

            depth -= 1


            if depth == 0:

                end = index + 1

                break


    if end is None:

        break


    block = cpp[
        match.start():end
    ]


    if "mSoftwareCursorVisible" not in block:

        break


    cpp = (
        cpp[:match.start()]
        +
        cpp[end:]
    )


# ============================================================
# INSERIR UM ÚNICO F12
# ============================================================

key_marker = (
    "void Gui::keyPressed(gcn::KeyEvent &event)\n{"
)


if key_marker not in cpp:

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


cpp = cpp.replace(
    key_marker,
    key_marker +
    toggle,
    1
)


gui_cpp.write_text(cpp)


# ============================================================
# VALIDAR GUI.CPP
# ============================================================

c = gui_cpp.read_text()


print("")
print("=== VALIDANDO GUI.CPP ===")


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
        "ERRO: Key::F12 precisa existir exatamente uma vez."
    )


if "mSoftwareCursor->get(0)" not in c:

    raise SystemExit(
        "ERRO: desenho do cursor não encontrado."
    )


if "mSoftwareCursorVisible" not in c:

    raise SystemExit(
        "ERRO: controle de visibilidade não encontrado."
    )


if "SDL_ShowCursor(SDL_DISABLE);" not in c:

    raise SystemExit(
        "ERRO: cursor SDL não foi desabilitado."
    )


print("GUI.CPP OK")


# ============================================================
# VALIDAR TTF NOVAMENTE
# ============================================================

print("")
print("=== Validação final SDL_ttf ===")


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
            "ERRO: chamada TTF_SetFontSize() encontrada em "
            + str(path)
        )


print("SDL_ttf OK")


# ============================================================
# FINAL PATCH
# ============================================================

print("")
print("========================================")
print(" PATCHES VALIDADOS")
print("========================================")
print("")

PY


# ============================================================
# SDL
# ============================================================

echo ""
echo "========================================"
echo " Versões SDL"
echo "========================================"
echo ""

pkg-config --modversion sdl2 || true
pkg-config --modversion SDL2_image || true
pkg-config --modversion SDL2_mixer || true
pkg-config --modversion SDL2_net || true
pkg-config --modversion SDL2_ttf || true
pkg-config --modversion physfs || true
pkg-config --modversion libxml-2.0 || true


# ============================================================
# CMAKE
# ============================================================

echo ""
echo "========================================"
echo " Configurando CMake"
echo "========================================"
echo ""

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

echo ""
echo "========================================"
echo " COMPILANDO MANA"
echo "========================================"
echo ""

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"


# ============================================================
# INSTALL
# ============================================================

echo ""
echo "========================================"
echo " Instalando"
echo "========================================"
echo ""

cmake \
    --install "$BUILD"


# ============================================================
# LOCALIZAR BINÁRIO
# ============================================================

echo ""
echo "========================================"
echo " Localizando executável"
echo "========================================"
echo ""


BIN="$(
    find "$INSTALL" \
        -type f \
        -name "mana" \
        -perm -u+x \
        | head -1
)"


if [ -z "$BIN" ]; then

    echo "ERRO:"
    echo "Executável Mana não encontrado."

    echo ""
    echo "Arquivos instalados:"

    find \
        "$INSTALL" \
        -type f \
        -print

    exit 1
fi


echo "Executável:"
echo "$BIN"


# ============================================================
# COPIAR BINÁRIO
# ============================================================

mkdir -p "$DIST"


cp \
    "$BIN" \
    "$DIST/mana.aarch64"


chmod +x \
    "$DIST/mana.aarch64"


# ============================================================
# VALIDAR ARQUITETURA
# ============================================================

echo ""
echo "========================================"
echo " Validando AArch64"
echo "========================================"
echo ""


file \
    "$DIST/mana.aarch64"


if ! file "$DIST/mana.aarch64" \
    | grep -qi "aarch64"; then

    echo ""
    echo "ERRO:"
    echo "O executável não é AArch64."

    exit 1
fi


# ============================================================
# VALIDAR GLIBC
# ============================================================

echo ""
echo "========================================"
echo " Validando GLIBC"
echo "========================================"
echo ""


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
    echo "ERRO:"
    echo "O binário exige GLIBC_2.43."

    exit 1
fi


# ============================================================
# PORTMASTER PACKAGE
# ============================================================

echo ""
echo "========================================"
echo " Preparando PortMaster"
echo "========================================"
echo ""


rm -rf "$PACKAGE"


mkdir -p \
    "$PACKAGE"


mkdir -p \
    "$PACKAGE/mana"


# ============================================================
# COPIAR ARQUIVOS PORTMASTER
# ============================================================

for file in \
    Mana.sh \
    README.md \
    gameinfo.xml \
    port.json \
    screenshot.png
do

    if [ -f "$PORT/$file" ]; then

        cp \
            "$PORT/$file" \
            "$PACKAGE/$file"

    fi

done


# ============================================================
# DATA
# ============================================================

if [ -d "$PORT/mana/data" ]; then

    cp -a \
        "$PORT/mana/data" \
        "$PACKAGE/mana/"

else

    echo ""
    echo "AVISO:"
    echo "port/mana/data não encontrado."
    echo ""

fi


# ============================================================
# LICENSES
# ============================================================

if [ -d "$PORT/mana/licenses" ]; then

    cp -a \
        "$PORT/mana/licenses" \
        "$PACKAGE/mana/"

fi


# ============================================================
# GPTK
# ============================================================

if [ -f "$PORT/mana/mana.gptk.0" ]; then

    cp \
        "$PORT/mana/mana.gptk.0" \
        "$PACKAGE/mana/"

fi


# ============================================================
# BINÁRIO
# ============================================================

cp \
    "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"


chmod +x \
    "$PACKAGE/mana/mana.aarch64"


# ============================================================
# MANA.SH
#
# Se já existir no repositório, preservamos.
# Se não existir, criamos.
# ============================================================

if [ ! -f "$PACKAGE/Mana.sh" ]; then

    cat > "$PACKAGE/Mana.sh" <<'EOF'
#!/bin/bash

GAMEDIR="/roms/ports/mana"

CONFDIR="$GAMEDIR/config"

GAME="$GAMEDIR/mana/mana.aarch64"


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

fi


chmod +x \
    "$PACKAGE/Mana.sh"


# ============================================================
# CONTROLES
# ============================================================

if [ ! -f "$PACKAGE/mana/mana.gptk.0" ]; then

    echo ""
    echo "ERRO:"
    echo "mana.gptk.0 não encontrado."

    echo ""
    echo "Arquivos em port/mana:"

    find \
        "$PORT/mana" \
        -maxdepth 2 \
        -type f \
        -print \
        || true

    exit 1
fi


# ============================================================
# VALIDAR CONTROLES
# ============================================================

echo ""
echo "========================================"
echo " Validando controles"
echo "========================================"
echo ""


cat \
    "$PACKAGE/mana/mana.gptk.0"


echo ""


if ! grep -q \
    "^select = f12$" \
    "$PACKAGE/mana/mana.gptk.0"; then

    echo "ERRO: SELECT -> F12 não encontrado."

    exit 1
fi


if ! grep -q \
    "^right_analog_up = mouse_movement_up$" \
    "$PACKAGE/mana/mana.gptk.0"; then

    echo "ERRO: mouse do analógico direito não encontrado."

    exit 1
fi


if ! grep -q \
    "^r3 = mouse_left$" \
    "$PACKAGE/mana/mana.gptk.0"; then

    echo "ERRO: R3 -> mouse esquerdo não encontrado."

    exit 1
fi


if ! grep -q \
    "^l3 = mouse_right$" \
    "$PACKAGE/mana/mana.gptk.0"; then

    echo "ERRO: L3 -> mouse direito não encontrado."

    exit 1
fi


echo ""
echo "CONTROLES OK"


# ============================================================
# DIAGNÓSTICOS
# ============================================================

echo ""
echo "========================================"
echo " Gerando diagnostics.txt"
echo "========================================"
echo ""


{
    echo "Mana 0.8.0 R36S PortMaster AArch64"
    echo ""

    echo "========================================"
    echo "FILE"
    echo "========================================"

    file \
        "$DIST/mana.aarch64"

    echo ""

    echo "========================================"
    echo "GLIBC"
    echo "========================================"

    readelf \
        --version-info \
        "$DIST/mana.aarch64" \
        | grep -o "GLIBC_[0-9.]*" \
        | sort -Vu \
        || true

    echo ""

    echo "========================================"
    echo "NEEDED"
    echo "========================================"

    readelf \
        -d \
        "$DIST/mana.aarch64" \
        | grep NEEDED \
        || true

    echo ""

    echo "========================================"
    echo "GUI.H CURSOR"
    echo "========================================"

    grep \
        -n \
        "mSoftwareCursor" \
        "$SRC/src/gui/gui.h" \
        || true

    echo ""

    echo "========================================"
    echo "GUI.CPP F12"
    echo "========================================"

    grep \
        -n \
        "Key::F12" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo ""

    echo "========================================"
    echo "CURSOR VISIBILITY"
    echo "========================================"

    grep \
        -n \
        "mSoftwareCursorVisible" \
        "$SRC/src/gui/gui.h" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo ""

    echo "========================================"
    echo "GPTK"
    echo "========================================"

    cat \
        "$PACKAGE/mana/mana.gptk.0"

} > "$DIST/diagnostics.txt"


# ============================================================
# ZIP
# ============================================================

echo ""
echo "========================================"
echo " Criando ZIP PortMaster"
echo "========================================"
echo ""


cd "$PACKAGE"


zip \
    -r \
    "$DIST/mana-r36s-portmaster-aarch64.zip" \
    .


cd "$ROOT"


# ============================================================
# RESULTADO
# ============================================================

echo ""
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"
echo ""


ls -lh \
    "$DIST/"


echo ""
echo "Arquivos gerados:"
echo ""


find \
    "$DIST" \
    -maxdepth 2 \
    -type f \
    -printf "%p\n"


echo ""
echo "========================================"
echo " MANA R36S PORTMASTER PRONTO"
echo "========================================"
echo ""
