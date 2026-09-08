#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# MANA 0.8.0
# R36S / dArkOSen
# PortMaster AArch64
#
# BUILD COMPLETO
#
# Corrige:
#
#   SDL2_ttf >= 2.0.18
#   TTF_SetFontSize()
#   Guichan
#   ENet
#   cursor duplicado
#   ResourceRef<Image> mSoftwareCursor
#   ResourceRef<ImageSet> mSoftwareCursor
#   cursor software
#   SELECT -> F12
#   mouse sempre ativo
#   R3 -> mouse esquerdo
#   L3 -> mouse direito
#   analógico direito -> mouse
#
# IMPORTANTE:
#
# O cursor é desenhado com drawImage().
# NÃO usamos drawRescaledImage().
#
# ============================================================


ROOT="/workspace"

SRC_ARCHIVE="$ROOT/source/mana-master.tar.gz"

WORK="$ROOT/.build"

SRC="$WORK/mana-master"

BUILD="$WORK/build"

PORT="$ROOT/port"

DIST="$ROOT/dist"

DEPS="$WORK/deps"


# ============================================================
# INÍCIO
# ============================================================

echo ""
echo "============================================================"
echo " MANA 0.8.0 - R36S PORTMASTER AARCH64"
echo "============================================================"
echo ""


# ============================================================
# LIMPEZA
# ============================================================

echo "=== Limpando build anterior ==="

rm -rf "$WORK"

rm -rf "$PORT"

rm -rf "$DIST"

mkdir -p "$WORK"

mkdir -p "$DEPS"

mkdir -p "$DIST"


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


# ============================================================
# EXTRAIR SOURCE
# ============================================================

echo ""
echo "=== Extraindo Mana source ==="
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

        echo "ERRO: diretório do Mana não encontrado."

        exit 2

    fi

    SRC="$FOUND"

fi


if [ ! -f "$SRC/CMakeLists.txt" ]; then

    echo "ERRO: CMakeLists.txt não encontrado."

    echo "SRC=$SRC"

    exit 2

fi


echo "SOURCE:"
echo "$SRC"


# ============================================================
# DEPENDÊNCIAS
# ============================================================

echo ""
echo "============================================================"
echo " DEPENDÊNCIAS"
echo "============================================================"
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
# SDL2_ttf
# ============================================================

echo ""
echo "============================================================"
echo " SDL2_ttf"
echo "============================================================"
echo ""


python3 - "$SRC" <<'PY'

import re
import sys

from pathlib import Path


src = Path(sys.argv[1])


print("=== Corrigindo requisitos SDL2_ttf ===")


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
            "SDL2_ttf>= 2.0.15"
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


print("")
print("=== Validando SDL2_ttf ===")


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
            "ERRO: requisito SDL2_ttf 2.0.18 "
            "ainda existe em "
            + str(path)
        )


print("SDL2_ttf requirement OK")

PY


# ============================================================
# TTF_SetFontSize
# ============================================================

echo ""
echo "=== Corrigindo TTF_SetFontSize ==="
echo ""


python3 - "$SRC" <<'PY'

import re
import sys

from pathlib import Path


src = Path(sys.argv[1])


for path in src.rglob("*.cpp"):

    try:

        text = path.read_text()

    except Exception:

        continue


    if "TTF_SetFontSize" not in text:

        continue


    original = text


    # --------------------------------------------------------
    # Remove somente as chamadas incompatíveis.
    #
    # Não alteramos a lógica restante da função.
    # --------------------------------------------------------

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


# ------------------------------------------------------------
# Validação.
#
# Procuramos somente chamada real.
# Comentários não causam falso positivo.
# ------------------------------------------------------------

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
            "ERRO: chamada TTF_SetFontSize() "
            "ainda existe em "
            + str(path)
        )


print("TTF_SetFontSize OK")

PY


# ============================================================
# GUICHAN
# ============================================================

echo ""
echo "============================================================"
echo " GUICHAN 0.8.3"
echo "============================================================"
echo ""


GUICHAN_TAR="$DEPS/guichan-0.8.3.tar.gz"


curl \
    -L \
    --fail \
    --retry 3 \
    -o "$GUICHAN_TAR" \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"


rm -rf "$SRC/libs/guichan"


mkdir -p "$SRC/libs/guichan"


tar \
    -xzf "$GUICHAN_TAR" \
    -C "$SRC/libs/guichan" \
    --strip-components=1


if [ ! -f "$SRC/libs/guichan/CMakeLists.txt" ]; then

    echo "ERRO: Guichan não foi instalado corretamente."

    exit 3

fi


echo "Guichan OK"


# ============================================================
# ENET
# ============================================================

echo ""
echo "============================================================"
echo " ENET 1.3.18"
echo "============================================================"
echo ""


ENET_TAR="$DEPS/enet-1.3.18.tar.gz"


curl \
    -L \
    --fail \
    --retry 3 \
    -o "$ENET_TAR" \
    "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"


rm -rf "$SRC/libs/enet"


mkdir -p "$SRC/libs/enet"


tar \
    -xzf "$ENET_TAR" \
    -C "$SRC/libs/enet" \
    --strip-components=1


if [ ! -f "$SRC/libs/enet/CMakeLists.txt" ]; then

    echo "ERRO: ENet não foi instalado corretamente."

    exit 4

fi


echo "ENet OK"


# ============================================================
# PATCH DO GUI.H
# ============================================================

echo ""
echo "============================================================"
echo " PATCH GUI.H"
echo "============================================================"
echo ""


python3 - "$SRC/src/gui/gui.h" <<'PY'

import re
import sys

from pathlib import Path


path = Path(sys.argv[1])


if not path.exists():

    raise SystemExit(
        "ERRO: gui.h não encontrado."
    )


text = path.read_text()


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
# REMOVER TODAS AS DECLARAÇÕES ANTIGAS
#
# Isto é propositalmente agressivo.
#
# Pode existir:
#
# ResourceRef<Image> mSoftwareCursor;
#
# ou:
#
# ResourceRef<ImageSet> mSoftwareCursor;
#
# ou versões duplicadas.
#
# Todas são removidas.
# ============================================================

lines = text.splitlines()

new_lines = []


for line in lines:

    stripped = line.strip()


    # --------------------------------------------------------
    # Qualquer ResourceRef contendo mSoftwareCursor.
    # --------------------------------------------------------

    if (
        "mSoftwareCursor" in stripped
        and "ResourceRef<" in stripped
        and stripped.endswith(";")
    ):

        print(
            "Removendo:",
            stripped
        )

        continue


    # --------------------------------------------------------
    # Remover flag antiga.
    # --------------------------------------------------------

    if (
        "mSoftwareCursorVisible" in stripped
        and stripped.startswith("bool ")
        and stripped.endswith(";")
    ):

        print(
            "Removendo:",
            stripped
        )

        continue


    new_lines.append(line)


text = "\n".join(new_lines) + "\n"


# ============================================================
# INSERIR EXATAMENTE UMA DECLARAÇÃO
# ============================================================

marker = "        bool mCustomCursor = false;"


if marker not in text:

    # Algumas versões possuem 4 espaços diferentes.
    marker = "    bool mCustomCursor = false;"


if marker not in text:

    raise SystemExit(
        "ERRO: mCustomCursor não encontrado em gui.h."
    )


cursor_block = (
    "        ResourceRef<ImageSet> mSoftwareCursor;\n"
    "        bool mSoftwareCursorVisible = true;\n"
)


if marker.startswith("    bool"):

    cursor_block = (
        "    ResourceRef<ImageSet> mSoftwareCursor;\n"
        "    bool mSoftwareCursorVisible = true;\n"
    )


text = text.replace(
    marker,
    cursor_block + marker,
    1
)


path.write_text(text)


# ============================================================
# VALIDAR
# ============================================================

final = path.read_text()


declarations = []


for number, line in enumerate(
    final.splitlines(),
    start=1
):

    stripped = line.strip()


    if (
        "ResourceRef<"
        in stripped
        and "mSoftwareCursor"
        in stripped
        and stripped.endswith(";")
    ):

        declarations.append(
            (number, stripped)
        )


print("")
print("Declarações encontradas:")


for number, line in declarations:

    print(
        f"{number}: {line}"
    )


if len(declarations) != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursor não está "
        "declarado exatamente uma vez."
    )


if declarations[0][1] != \
        "ResourceRef<ImageSet> mSoftwareCursor;":

    raise SystemExit(
        "ERRO: declaração do cursor está incorreta."
    )


visible = [
    line
    for line in final.splitlines()
    if (
        "bool mSoftwareCursorVisible = true;"
        in line
    )
]


if len(visible) != 1:

    raise SystemExit(
        "ERRO: mSoftwareCursorVisible não está "
        "declarado exatamente uma vez."
    )


print("")
print("GUI.H OK")

PY


# ============================================================
# PATCH GUI.CPP
# ============================================================

echo ""
echo "============================================================"
echo " PATCH GUI.CPP"
echo "============================================================"
echo ""


python3 - "$SRC/src/gui/gui.cpp" <<'PY'

import re
import sys

from pathlib import Path


path = Path(sys.argv[1])


if not path.exists():

    raise SystemExit(
        "ERRO: gui.cpp não encontrado."
    )


text = path.read_text()


# ============================================================
# 1. REMOVER INICIALIZAÇÕES ANTIGAS DO CURSOR
# ============================================================

text = re.sub(
    r"""
    [ \t]*mSoftwareCursor\s*=
    \s*ResourceManager::getInstance\(\)
    \.getImageSet\(
    \s*mTheme->resolvePath\("mouse\.png"\)
    \s*,\s*40\s*,\s*40\s*
    \)
    \s*;
    """,
    "",
    text,
    flags=re.VERBOSE
)


# ============================================================
# 2. DESABILITAR CURSOR HARDWARE
# ============================================================

text = text.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


# ============================================================
# 3. INICIALIZAÇÃO SOFTWARE CURSOR
# ============================================================

cursor_init = """    // R36S software cursor.
    // GPTK fornece a posição do mouse.
    // Mana desenha o cursor dentro do frame.
    mSoftwareCursor =
        ResourceManager::getInstance().getImageSet(
            mTheme->resolvePath("mouse.png"),
            40,
            40);

    SDL_ShowCursor(SDL_DISABLE);

"""


if "mSoftwareCursor =" not in text:

    marker = "    setInput(guiInput);"


    if marker not in text:

        raise SystemExit(
            "ERRO: setInput(guiInput) não encontrado."
        )


    text = text.replace(
        marker,
        marker +
        "\n" +
        cursor_init,
        1
    )


# ============================================================
# 4. SUBSTITUIR COMPLETAMENTE Gui::draw()
#
# Esta parte é importante.
#
# Não usamos drawRescaledImage().
#
# Usamos:
#
# graphics->drawImage(image, x, y);
#
# que existe nessa versão do Graphics.
# ============================================================

draw_pattern = re.compile(
    r"void\s+Gui::draw\s*\(\s*\)\s*\{"
)


match = draw_pattern.search(text)


if not match:

    raise SystemExit(
        "ERRO: Gui::draw() não encontrado."
    )


start = match.start()

brace_start = text.find(
    "{",
    match.start()
)


depth = 0
end = None


for i in range(
    brace_start,
    len(text)
):

    char = text[i]


    if char == "{":

        depth += 1


    elif char == "}":

        depth -= 1


        if depth == 0:

            end = i + 1

            break


if end is None:

    raise SystemExit(
        "ERRO: final de Gui::draw() não encontrado."
    )


new_draw = r'''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);
    if (!graphics)
        return;

    if (mActiveDrag)
    {
        graphics->pushClipArea(
            gcn::Rectangle(
                0,
                0,
                graphics->getWidth(),
                graphics->getHeight()));

        mActiveDrag->draw(
            graphics,
            mMouseX,
            mMouseY);

        graphics->popClipArea();
    }

    // ========================================================
    // R36S SOFTWARE CURSOR
    //
    // drawImage() usa a imagem original do cursor.
    //
    // Não usamos drawRescaledImage(), pois a sobrecarga
    // completa dessa função possui parâmetros diferentes.
    // ========================================================

    if (mSoftwareCursorVisible &&
        mSoftwareCursor &&
        mSoftwareCursor->size() > 0)
    {
        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);
    }
}'''


text = (
    text[:start]
    +
    new_draw
    +
    text[end:]
)


# ============================================================
# 5. keyPressed()
#
# SELECT -> F12
#
# F12 SOMENTE alterna visibilidade.
#
# O mouse NÃO é desligado.
# ============================================================

key_pattern = re.compile(
    r"void\s+Gui::keyPressed\s*"
    r"\(\s*gcn::KeyEvent\s*&event\s*\)\s*\{"
)


match = key_pattern.search(text)


if not match:

    raise SystemExit(
        "ERRO: Gui::keyPressed() não encontrado."
    )


key_start = match.start()

key_brace = text.find(
    "{",
    match.start()
)


depth = 0
key_end = None


for i in range(
    key_brace,
    len(text)
):

    char = text[i]


    if char == "{":

        depth += 1


    elif char == "}":

        depth -= 1


        if depth == 0:

            key_end = i + 1

            break


if key_end is None:

    raise SystemExit(
        "ERRO: final de Gui::keyPressed() não encontrado."
    )


new_key_pressed = r'''void Gui::keyPressed(gcn::KeyEvent &event)
{
    // ========================================================
    // SELECT -> F12
    //
    // F12 SOMENTE mostra/esconde o cursor.
    //
    // O mouse continua ativo.
    // Os demais controles continuam funcionando.
    // ========================================================

    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();

        return;
    }

    if (mActiveDrag &&
        event.getKey().getValue() == Key::ESCAPE)
    {
        cancelActiveDrag();

        event.consume();
    }
}'''


text = (
    text[:key_start]
    +
    new_key_pressed
    +
    text[key_end:]
)


# ============================================================
# 6. MOVIMENTO DO MOUSE
#
# Nunca mostramos o cursor SDL.
# ============================================================

text = text.replace(
    "// Make sure the cursor is visible\n"
    "    SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


# Caso o comentário tenha desaparecido.
text = text.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


path.write_text(text)


# ============================================================
# VALIDAÇÃO
# ============================================================

final = path.read_text()


print("")
print("=== Validando gui.cpp ===")


# drawImage
if "mSoftwareCursor->get(0)" not in final:

    raise SystemExit(
        "ERRO: drawImage do cursor não encontrado."
    )


# Não permitir chamada errada do cursor.
cursor_section = final[
    final.find("void Gui::draw()"):
]


draw_end = cursor_section.find(
    "void Gui::event"
)


if draw_end != -1:

    cursor_section = cursor_section[
        :draw_end
    ]


if "drawRescaledImage" in cursor_section:

    raise SystemExit(
        "ERRO: drawRescaledImage ainda está "
        "sendo usado no cursor."
    )


# F12
f12_count = len(
    re.findall(
        r"Key::F12",
        final
    )
)


if f12_count != 1:

    raise SystemExit(
        "ERRO: Key::F12 deve existir exatamente uma vez."
    )


# Visibility
if (
    "mSoftwareCursorVisible"
    not in final
):

    raise SystemExit(
        "ERRO: mSoftwareCursorVisible não encontrado."
    )


# Hardware cursor
if (
    "SDL_ShowCursor(SDL_ENABLE);"
    in final
):

    raise SystemExit(
        "ERRO: SDL_ShowCursor(SDL_ENABLE) ainda existe."
    )


print("drawImage cursor: OK")
print("drawRescaledImage cursor: NÃO USADO")
print("F12: OK")
print("software cursor visibility: OK")
print("SDL hardware cursor: DISABLED")
print("")
print("GUI.CPP OK")

PY


# ============================================================
# VALIDAÇÃO FINAL DOS PATCHES
# ============================================================

echo ""
echo "============================================================"
echo " VALIDAÇÃO DOS PATCHES"
echo "============================================================"
echo ""


echo "=== Cursor declarations ==="


grep \
    -n \
    "mSoftwareCursor" \
    "$SRC/src/gui/gui.h"


echo ""


echo "=== Cursor code ==="


grep \
    -n \
    -E \
    "mSoftwareCursor|Key::F12|drawImage" \
    "$SRC/src/gui/gui.cpp"


echo ""


# ============================================================
# CMAKE
# ============================================================

echo ""
echo "============================================================"
echo " CONFIGURANDO CMAKE"
echo "============================================================"
echo ""


cmake \
    -S "$SRC" \
    -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF


# ============================================================
# BUILD
# ============================================================

echo ""
echo "============================================================"
echo " COMPILANDO MANA"
echo "============================================================"
echo ""


cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"


# ============================================================
# LOCALIZAR BINÁRIO
# ============================================================

echo ""
echo "============================================================"
echo " LOCALIZANDO BINÁRIO"
echo "============================================================"
echo ""


BIN="$BUILD/src/mana"


if [ ! -x "$BIN" ]; then

    BIN="$(
        find "$BUILD" \
            -type f \
            -name "mana" \
            -perm -111 \
            -print \
            -quit
    )"

fi


if [ -z "${BIN:-}" ]; then

    echo ""
    echo "ERRO: executável Mana não produzido."

    exit 6

fi


if [ ! -x "$BIN" ]; then

    echo ""
    echo "ERRO: binário não executável."

    exit 6

fi


echo "BINÁRIO:"
echo "$BIN"


# ============================================================
# PORTMASTER
# ============================================================

echo ""
echo "============================================================"
echo " MONTANDO PORTMASTER"
echo "============================================================"
echo ""


mkdir -p \
    "$PORT/mana"


# ============================================================
# MANA.SH
# ============================================================

cat > "$PORT/Mana.sh" <<'EOF'
#!/bin/bash

set -u


# ============================================================
# PORTMASTER CONTROL
# ============================================================

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


source "$controlfolder/control.txt"


if [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then

    source "${controlfolder}/mod_${CFW_NAME}.txt"

fi


get_controls


# ============================================================
# DIRETÓRIOS
# ============================================================

GAMEDIR="/$directory/ports/mana"

CONFDIR="$GAMEDIR/conf"


mkdir -p "$CONFDIR"


cd "$GAMEDIR" || exit 1


# ============================================================
# LOG
# ============================================================

: > "$GAMEDIR/log.txt"


exec > >(tee -a "$GAMEDIR/log.txt") 2>&1


echo "================================================"
echo " Mana 0.8.0"
echo " R36S / PortMaster"
echo "================================================"


echo "DEVICE_ARCH=${DEVICE_ARCH:-unknown}"

echo "DEVICE_CPU=${DEVICE_CPU:-unknown}"

echo "CFW_NAME=${CFW_NAME:-unknown}"


# ============================================================
# GAME
# ============================================================

GAME="$GAMEDIR/mana/mana.aarch64"


if [ ! -f "$GAME" ]; then

    echo "ERRO:"

    echo "$GAME não encontrado."

    exit 1

fi


chmod +x "$GAME"


# ============================================================
# CONFIG
# ============================================================

export XDG_DATA_HOME="$CONFDIR"

export XDG_CONFIG_HOME="$CONFDIR"


if [ -n "${sdl_controllerconfig:-}" ]; then

    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

fi


# ============================================================
# TECLADO VIRTUAL GPTK
# ============================================================

export TEXTINPUTINTERACTIVE="Y"

export TEXTINPUTADDEXTRASYMBOLS="Y"


# ============================================================
# GPTOKEYB
# ============================================================

cd "$GAMEDIR/mana" || exit 1


GPTK_CONFIG="./mana.gptk"


GPTOPID=""


if [ -n "${GPTOKEYB2:-}" ]; then

    echo "Starting GPTOKEYB2"

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!


elif [ -n "${GPTOKEYB:-}" ]; then

    echo "Starting GPTOKEYB"

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!


else

    echo "ERRO: GPTOKEYB/GPTOKEYB2 não encontrado."

    exit 1

fi


# ============================================================
# CLEANUP
# ============================================================

cleanup()
{
    if [ -n "${GPTOPID:-}" ]; then

        kill "$GPTOPID" 2>/dev/null || true

        wait "$GPTOPID" 2>/dev/null || true

    fi
}


trap cleanup EXIT INT TERM


# ============================================================
# EXECUTAR
# ============================================================

echo "Starting Mana..."


"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"


RET=$?


exit "$RET"
EOF


chmod +x \
    "$PORT/Mana.sh"


# ============================================================
# GPTK
# ============================================================

echo ""
echo "=== Criando mana.gptk ==="
echo ""


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


# ============================================================
# PORT.JSON
# ============================================================

cat > "$PORT/port.json" <<'EOF'
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
      "Kaddte"
    ],
    "desc": "The Mana Client 0.8.0 for AArch64 PortMaster devices.",
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

cat > "$PORT/gameinfo.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<game>
    <name>Mana 0.8.0</name>
    <path>Mana.sh</path>
    <description>The Mana Client 0.8.0</description>
</game>
EOF


# ============================================================
# BINÁRIO
# ============================================================

cp \
    "$BIN" \
    "$PORT/mana/mana.aarch64"


chmod +x \
    "$PORT/mana/mana.aarch64"


# ============================================================
# DATA
# ============================================================

echo ""
echo "=== Copiando data ==="
echo ""


if [ ! -d "$SRC/data" ]; then

    echo "ERRO: diretório data não encontrado."

    exit 7

fi


rm -rf \
    "$PORT/mana/data"


cp -a \
    "$SRC/data" \
    "$PORT/mana/data"


# ============================================================
# CURSOR IMAGE
# ============================================================

if [ ! -f \
    "$PORT/mana/data/graphics/gui/mouse.png"
]; then

    echo ""
    echo "ERRO:"
    echo "mouse.png não encontrado."

    echo ""
    echo "Procurando mouse.png:"

    find \
        "$PORT/mana/data" \
        -iname "mouse.png" \
        -print \
        || true

    exit 7

fi


echo "mouse.png OK"


# ============================================================
# LICENSES
# ============================================================

if [ -d "$SRC/licenses" ]; then

    cp -a \
        "$SRC/licenses" \
        "$PORT/mana/licenses"

fi


# ============================================================
# VALIDAR GPTK
# ============================================================

echo ""
echo "============================================================"
echo " VALIDANDO CONTROLES"
echo "============================================================"
echo ""


cat \
    "$PORT/mana/mana.gptk"


echo ""


grep -q \
    "^select = f12$" \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: SELECT -> F12 ausente."
        exit 9
    }


grep -q \
    "^right_analog_up = mouse_movement_up$" \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: mouse do analógico direito ausente."
        exit 9
    }


grep -q \
    "^r3 = mouse_left$" \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: R3 -> mouse_left ausente."
        exit 9
    }


grep -q \
    "^l3 = mouse_right$" \
    "$PORT/mana/mana.gptk" \
    || {
        echo "ERRO: L3 -> mouse_right ausente."
        exit 9
    }


echo "Controles OK"


# ============================================================
# ARQUITETURA
# ============================================================

echo ""
echo "============================================================"
echo " VALIDANDO BINÁRIO"
echo "============================================================"
echo ""


ELF="$PORT/mana/mana.aarch64"


file "$ELF"


if ! file "$ELF" | grep -qi "aarch64"; then

    echo ""
    echo "ERRO: binário não é AArch64."

    exit 10

fi


# ============================================================
# GLIBC
# ============================================================

echo ""
echo "=== GLIBC ==="
echo ""


readelf \
    --version-info \
    "$ELF" \
    2>/dev/null \
    | grep -o \
        'GLIBC_[0-9][0-9.]*' \
    | sort -Vu \
    || true


if readelf \
    --version-info \
    "$ELF" \
    2>/dev/null \
    | grep -q \
        'GLIBC_2\.43'
then

    echo ""
    echo "ERRO: binário exige GLIBC_2.43."

    exit 11

fi


# ============================================================
# DIAGNÓSTICOS
# ============================================================

echo ""
echo "============================================================"
echo " DIAGNÓSTICOS"
echo "============================================================"
echo ""


{
    echo "Mana 0.8.0 R36S PortMaster AArch64"
    echo ""

    echo "=== FILE ==="

    file "$ELF"

    echo ""

    echo "=== NEEDED ==="

    readelf \
        -d "$ELF" \
        | grep NEEDED \
        || true

    echo ""

    echo "=== RPATH/RUNPATH ==="

    readelf \
        -d "$ELF" \
        | grep -E \
            'RPATH|RUNPATH' \
        || true

    echo ""

    echo "=== GLIBC ==="

    readelf \
        --version-info "$ELF" \
        2>/dev/null \
        | grep -o \
            'GLIBC_[0-9][0-9.]*' \
        | sort -Vu \
        || true

    echo ""

    echo "=== GUI.H ==="

    grep \
        -n \
        "mSoftwareCursor" \
        "$SRC/src/gui/gui.h" \
        || true

    echo ""

    echo "=== GUI.CPP ==="

    grep \
        -n \
        -E \
        "mSoftwareCursor|Key::F12|drawImage" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo ""

    echo "=== GPTK ==="

    cat \
        "$PORT/mana/mana.gptk"

} > "$DIST/diagnostics.txt"


# ============================================================
# VALIDAR PACKAGE
# ============================================================

echo ""
echo "============================================================"
echo " VALIDANDO PACKAGE"
echo "============================================================"
echo ""


test -f \
    "$PORT/Mana.sh"


test -x \
    "$PORT/Mana.sh"


test -f \
    "$PORT/port.json"


test -f \
    "$PORT/gameinfo.xml"


test -f \
    "$PORT/mana/mana.aarch64"


test -f \
    "$PORT/mana/mana.gptk"


test -f \
    "$PORT/mana/data/graphics/gui/mouse.png"


# ============================================================
# ZIP
# ============================================================

echo ""
echo "============================================================"
echo " CRIANDO ZIP"
echo "============================================================"
echo ""


PACKAGE="$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"


rm -f \
    "$PACKAGE"


(
    cd "$PORT"

    zip \
        -qr \
        "$PACKAGE" \
        .
)


# ============================================================
# LISTA DO PACKAGE
# ============================================================

unzip \
    -l \
    "$PACKAGE" \
    > "$DIST/package-list.txt"


# ============================================================
# RESULTADO
# ============================================================

echo ""
echo "============================================================"
echo " BUILD FINALIZADO"
echo "============================================================"
echo ""


ls -lh \
    "$PACKAGE"


echo ""


echo "PACKAGE:"

echo "$PACKAGE"


echo ""


echo "Arquivos:"

find \
    "$PORT" \
    -maxdepth 3 \
    -type f \
    -print \
    | sort


echo ""
echo "============================================================"
echo " MANA R36S PRONTO"
echo "============================================================"
echo ""
