#!/bin/bash

set -e

ROOT="/workspace"

SRC_TAR="$ROOT/source/mana-master.tar.gz"

BUILD="$ROOT/build"
INSTALL="$ROOT/install"
DIST="$ROOT/dist"
PORT="$ROOT/port"

SRC_DIR="$BUILD/mana-master"

echo
echo "========================================"
echo " Mana 0.8.0 - R36S AArch64"
echo " PortMaster Build"
echo "========================================"
echo

rm -rf "$BUILD"
rm -rf "$INSTALL"
rm -rf "$DIST"

mkdir -p "$BUILD"
mkdir -p "$INSTALL"
mkdir -p "$DIST"

# ============================================================
# DEPENDENCIAS
# ============================================================

echo
echo "========================================"
echo " Instalando dependencias"
echo "========================================"
echo

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    git \
    curl \
    ca-certificates \
    zip \
    unzip \
    file \
    binutils \
    build-essential \
    cmake \
    pkg-config \
    python3 \
    libphysfs-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    zlib1g-dev \
    libpng-dev \
    gettext \
    libssl-dev

echo
echo "Dependencias instaladas."
echo

# ============================================================
# VERIFICAR SOURCE
# ============================================================

echo
echo "========================================"
echo " Verificando source"
echo "========================================"
echo

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: source nao encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

echo "Source encontrado:"
echo "$SRC_TAR"

# ============================================================
# EXTRAIR MANA
# ============================================================

echo
echo "========================================"
echo " Extraindo Mana"
echo "========================================"
echo

tar -xzf "$SRC_TAR" -C "$BUILD"

if [ ! -d "$SRC_DIR" ]; then
    FOUND_DIR="$(find "$BUILD" -maxdepth 1 -mindepth 1 -type d | head -n 1)"

    if [ -z "$FOUND_DIR" ]; then
        echo "ERRO: diretorio do Mana nao encontrado."
        exit 1
    fi

    SRC_DIR="$FOUND_DIR"
fi

echo "SRC_DIR=$SRC_DIR"

# ============================================================
# CORRECAO SDL2_TTF
# ============================================================

echo
echo "========================================"
echo " Corrigindo SDL2_ttf"
echo "========================================"
echo

TTF_FILE="$SRC_DIR/src/gui/truetypefont.cpp"

if [ -f "$TTF_FILE" ]; then

    python3 - "$TTF_FILE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

old = """void TrueTypeFont::updateFontScale(float scale)
{
    if (mFont)
        TTF_SetFontSize(mFont, static_cast<int>(mSize * scale));
}
"""

new = """void TrueTypeFont::updateFontScale(float scale)
{
    mScale = scale;
}
"""

if old in text:
    text = text.replace(old, new)

path.write_text(text)
PY

    echo "OK: SDL2_ttf corrigido."

else
    echo "AVISO: truetypefont.cpp nao encontrado."
fi

echo
echo "SDL2_ttf OK."

# ============================================================
# CURSOR DE SOFTWARE R36S
# ============================================================

echo
echo "========================================"
echo " Adicionando cursor de software R36S"
echo "========================================"
echo

GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"

if [ ! -f "$GUI_H" ]; then
    echo "ERRO: gui.h nao encontrado:"
    echo "$GUI_H"
    exit 1
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.cpp nao encontrado:"
    echo "$GUI_CPP"
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" <<'PY'
import sys
from pathlib import Path

gui_h = Path(sys.argv[1])
gui_cpp = Path(sys.argv[2])

h = gui_h.read_text()
cpp = gui_cpp.read_text()

# ------------------------------------------------------------
# gui.h
# ------------------------------------------------------------

include_line = '#include "resources/imageset.h"'

if include_line not in h:
    marker = '#include "resources/theme.h"'

    if marker in h:
        h = h.replace(
            marker,
            marker + '\n#include "resources/imageset.h"',
            1
        )
    else:
        raise SystemExit(
            "ERRO: nao foi encontrado o include resources/theme.h"
        )

member_marker = 'bool mCustomCursor = false;'

if 'ResourceRef<ImageSet> mSoftwareCursor;' not in h:
    if member_marker not in h:
        raise SystemExit(
            "ERRO: nao foi encontrado o local dos membros do cursor."
        )

    h = h.replace(
        member_marker,
        member_marker + '''
        ResourceRef<ImageSet> mSoftwareCursor;
        bool mSoftwareCursorVisible = true;
''',
        1
    )

gui_h.write_text(h)

# ------------------------------------------------------------
# gui.cpp - construtor
# ------------------------------------------------------------

constructor_marker = """    setInput(guiInput);
"""

constructor_code = """    setInput(guiInput);

    // R36S / PortMaster software cursor.
    // GPTOKEYB supplies the mouse coordinates, while Mana renders
    // its own visible cursor because KMS/DRM may not display the
    // SDL hardware cursor.
    mSoftwareCursor = ResourceManager::getInstance()->getImageSet(
        mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
"""

if 'mSoftwareCursor = ResourceManager::getInstance()->getImageSet(' not in cpp:
    if constructor_marker not in cpp:
        raise SystemExit(
            "ERRO: nao foi encontrado setInput(guiInput)."
        )

    cpp = cpp.replace(
        constructor_marker,
        constructor_code,
        1
    )

# ------------------------------------------------------------
# gui.cpp - draw()
# ------------------------------------------------------------

draw_start = cpp.find("void Gui::draw()")
draw_end = cpp.find("\nvoid Gui::event(", draw_start)

if draw_start == -1 or draw_end == -1:
    raise SystemExit(
        "ERRO: nao foi possivel localizar o bloco real de Gui::draw()."
    )

new_draw = """void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);

    if (graphics &&
        mSoftwareCursorVisible &&
        mSoftwareCursor.get() &&
        mSoftwareCursor->size() > 0)
    {
        graphics->pushClipArea(
            gcn::Rectangle(
                0,
                0,
                graphics->getWidth(),
                graphics->getHeight()));

        graphics->drawImage(
            mSoftwareCursor->get(0),
            mMouseX - 15,
            mMouseY - 17);

        graphics->popClipArea();
    }

    if (!mActiveDrag)
        return;

    if (!graphics)
        return;

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
"""

cpp = cpp[:draw_start] + new_draw + cpp[draw_end:]

# ------------------------------------------------------------
# gui.cpp - F12 / cursor visibility
# ------------------------------------------------------------

key_start = cpp.find("void Gui::keyPressed(gcn::KeyEvent &event)")
key_end = cpp.find("\nvoid Gui::keyReleased(", key_start)

if key_start == -1 or key_end == -1:
    raise SystemExit(
        "ERRO: nao foi possivel localizar Gui::keyPressed()."
    )

new_key = """void Gui::keyPressed(gcn::KeyEvent &event)
{
    // SELECT is mapped by GPTOKEYB to F12.
    // F12 only changes cursor visibility; it does not disable
    // mouse movement or any other controller mapping.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible = !mSoftwareCursorVisible;

        // Keep the SDL hardware cursor disabled on R36S/KMS-DRM.
        SDL_ShowCursor(SDL_DISABLE);

        event.consume();
        return;
    }

    if (mActiveDrag &&
        event.getKey().getValue() == Key::ESCAPE)
    {
        cancelActiveDrag();
        event.consume();
    }
}
"""

cpp = cpp[:key_start] + new_key + cpp[key_end:]

# ------------------------------------------------------------
# gui.cpp - handleMouseMoved
# ------------------------------------------------------------

mouse_start = cpp.find(
    "void Gui::handleMouseMoved(const gcn::MouseInput &mouseInput)"
)

mouse_end = cpp.find(
    "\nvoid Gui::handleMouseReleased(",
    mouse_start
)

if mouse_start == -1 or mouse_end == -1:
    raise SystemExit(
        "ERRO: nao foi possivel localizar handleMouseMoved()."
    )

mouse_block = cpp[mouse_start:mouse_end]

# Remove qualquer chamada que reative o hardware cursor.
mouse_block = mouse_block.replace(
    """
    // Make sure the cursor is visible
    SDL_ShowCursor(SDL_ENABLE);
""",
    ""
)

mouse_block = mouse_block.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    ""
)

# Garante que o hardware cursor permaneça desligado.
if "SDL_ShowCursor(SDL_DISABLE);" not in mouse_block:
    mouse_block += """
    SDL_ShowCursor(SDL_DISABLE);
"""

cpp = cpp[:mouse_start] + mouse_block + cpp[mouse_end:]

gui_cpp.write_text(cpp)

print("Cursor de software aplicado com sucesso.")
PY

echo
echo "Cursor de software R36S aplicado."

# ============================================================
# VERIFICAR CURSOR
# ============================================================

echo
echo "========================================"
echo " Verificando cursor"
echo "========================================"
echo

if grep -q "mSoftwareCursor" "$GUI_H"; then
    echo "mSoftwareCursor: FOUND"
else
    echo "ERRO: mSoftwareCursor nao encontrado."
    exit 1
fi

if grep -q "mSoftwareCursorVisible" "$GUI_H"; then
    echo "Cursor visibility: FOUND"
else
    echo "ERRO: mSoftwareCursorVisible nao encontrado."
    exit 1
fi

if grep -q "Key::F12" "$GUI_CPP"; then
    echo "F12 cursor toggle: FOUND"
else
    echo "ERRO: F12 cursor toggle nao encontrado."
    exit 1
fi

if grep -q "SDL_ShowCursor(SDL_DISABLE" "$GUI_CPP"; then
    echo "Hardware cursor disable: FOUND"
else
    echo "AVISO: SDL hardware cursor disable nao encontrado."
fi

echo
echo "Cursor verification OK."

# ============================================================
# GUICHAN 0.8.3
# ============================================================

echo
echo "========================================"
echo " Obtendo Guichan 0.8.3"
echo "========================================"
echo

DEPS="$BUILD/deps"

rm -rf "$DEPS"

mkdir -p "$DEPS"

cd "$DEPS"

GUICHAN_TAR="$DEPS/guichan-0.8.3.tar.gz"

curl -L \
    --fail \
    --retry 3 \
    -o "$GUICHAN_TAR" \
    "https://github.com/darkbitsorg/guichan/releases/download/v0.8.3/guichan-0.8.3.tar.gz"

rm -rf "$DEPS/guichan"

mkdir -p "$DEPS/guichan"

tar -xzf "$GUICHAN_TAR" \
    -C "$DEPS/guichan" \
    --strip-components=1

echo
echo "Guichan 0.8.3 OK."

# ============================================================
# ENET 1.3.18
# ============================================================

echo
echo "========================================"
echo " Obtendo ENet 1.3.18"
echo "========================================"
echo

ENET_TAR="$DEPS/enet-1.3.18.tar.gz"

curl -L \
    --fail \
    --retry 3 \
    -o "$ENET_TAR" \
    "https://github.com/lsalzman/enet/archive/refs/tags/v1.3.18.tar.gz"

rm -rf "$DEPS/enet"

mkdir -p "$DEPS/enet"

tar -xzf "$ENET_TAR" \
    -C "$DEPS/enet" \
    --strip-components=1

echo
echo "ENet 1.3.18 OK."

# ============================================================
# SDL2_TTF CMAKE COMPATIBILITY
# ============================================================

echo
echo "========================================"
echo " Ajustando requisito SDL2_ttf"
echo "========================================"
echo

if [ -f "$SRC_DIR/CMakeLists.txt" ]; then

    sed -i \
        's/2\.0\.18/2.0.15/g' \
        "$SRC_DIR/CMakeLists.txt"

fi

grep -RIl \
    "2\.0\.18" \
    "$SRC_DIR/CMake" \
    "$SRC_DIR/src" \
    2>/dev/null \
    | while read -r FILE
do
    sed -i 's/2\.0\.18/2.0.15/g' "$FILE"
done

echo "SDL2_ttf requirement adjusted."

# ============================================================
# BUILD
# ============================================================

echo
echo "========================================"
echo " Configurando CMake"
echo "========================================"
echo

rm -rf "$BUILD/cmake"

mkdir -p "$BUILD/cmake"

cd "$BUILD/cmake"

cmake "$SRC_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DWITH_OPENGL=ON \
    -DENABLE_NLS=OFF \
    -DENABLE_MANASERV=ON \
    -DUSE_SYSTEM_ENET=OFF \
    -DUSE_SYSTEM_GUICHAN=OFF \
    -DGuichan_DIR="$DEPS/guichan" \
    -DENET_INCLUDE_DIR="$DEPS/enet/include" \
    -DENET_LIBRARY="$DEPS/enet"

echo
echo "CMake configurado."

# ============================================================
# COMPILAR
# ============================================================

echo
echo "========================================"
echo " Compilando Mana"
echo "========================================"
echo

JOBS="$(nproc)"

if [ -z "$JOBS" ] || [ "$JOBS" -lt 1 ]; then
    JOBS=1
fi

cmake --build . --parallel "$JOBS"

echo
echo "Compilacao concluida."

# ============================================================
# INSTALL
# ============================================================

echo
echo "========================================"
echo " Instalando"
echo "========================================"
echo

cmake --install .

echo
echo "Install concluido."

# ============================================================
# LOCALIZAR BINARIO
# ============================================================

echo
echo "========================================"
echo " Localizando executavel"
echo "========================================"
echo

BIN=""

for CANDIDATE in \
    "$BUILD/cmake/mana" \
    "$INSTALL/bin/mana" \
    "$INSTALL/mana"
do

    if [ -f "$CANDIDATE" ]; then
        BIN="$CANDIDATE"
        break
    fi

done

if [ -z "$BIN" ]; then

    BIN="$(find "$BUILD" \
        -type f \
        -name "mana" \
        -perm -111 \
        2>/dev/null \
        | head -n 1)"

fi

if [ -z "$BIN" ]; then
    echo "ERRO: executavel Mana nao encontrado."
    exit 1
fi

echo "BIN=$BIN"

chmod +x "$BIN"

# ============================================================
# ARQUITETURA
# ============================================================

echo
echo "========================================"
echo " Verificando arquitetura"
echo "========================================"
echo

file "$BIN"

if ! file "$BIN" | grep -qi "aarch64"; then
    echo
    echo "ERRO: o executavel nao e AArch64."
    exit 1
fi

echo
echo "AArch64: OK"

# ============================================================
# GLIBC
# ============================================================

echo
echo "========================================"
echo " Verificando GLIBC"
echo "========================================"
echo

GLIBC_LIST="$DIST/glibc_versions.txt"

strings "$BIN" \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' \
    | sort -Vu \
    > "$GLIBC_LIST" || true

cat "$GLIBC_LIST"

MAX_GLIBC="$(
    tail -n 1 "$GLIBC_LIST" \
    | sed 's/GLIBC_//'
)"

if [ -n "$MAX_GLIBC" ]; then

    MAX_GLIBC_NUM="$(
        printf '%s\n' "$MAX_GLIBC" \
        | awk -F. '{printf "%d%02d", $1, $2}'
    )"

    if [ "$MAX_GLIBC_NUM" -gt 229 ]; then
        echo
        echo "ERRO: GLIBC acima de 2.29:"
        echo "$MAX_GLIBC"
        exit 1
    fi

fi

echo
echo "GLIBC compatibility check OK."

# ============================================================
# DIAGNOSTICOS ELF
# ============================================================

echo
echo "========================================"
echo " Gerando diagnosticos ELF"
echo "========================================"
echo

DIAG="$DIST/diagnostics.txt"

{
    echo "=== Mana R36S AArch64 diagnostics ==="
    echo
    echo "Binary:"
    echo "$BIN"
    echo

    echo "=== file ==="
    file "$BIN"
    echo

    echo "=== readelf -h ==="
    readelf -h "$BIN"
    echo

    echo "=== NEEDED ==="
    readelf -d "$BIN" \
        | grep NEEDED || true
    echo

    echo "=== RPATH/RUNPATH ==="
    readelf -d "$BIN" \
        | grep -E 'RPATH|RUNPATH' || true
    echo

    echo "=== GLIBC ==="
    cat "$GLIBC_LIST"
    echo

    echo "=== Cursor strings ==="
    strings "$BIN" \
        | grep -E \
        'mSoftwareCursor|mSoftwareCursorVisible|SDL_ShowCursor|F12' \
        | sort -u || true

} > "$DIAG"

echo "Diagnostics:"
cat "$DIAG"

# ============================================================
# PORTMASTER DIRECTORY
# ============================================================

echo
echo "========================================"
echo " Preparando PortMaster"
echo "========================================"
echo

if [ ! -d "$PORT" ]; then
    echo "PortMaster source directory nao existe."
    echo "Criando automaticamente:"
    echo "$PORT"

    mkdir -p "$PORT/mana"
else
    echo "PortMaster source directory encontrado."
fi

mkdir -p "$PORT/mana"

# ============================================================
# MANA.SH
# ============================================================

if [ ! -f "$PORT/Mana.sh" ]; then

    echo
    echo "Criando port/Mana.sh"

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
    echo "ERRO: control.txt nao encontrado."
    exit 1
fi

if [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/mod_${CFW_NAME}.txt"
fi

if type get_controls >/dev/null 2>&1; then
    get_controls
fi

GAMEDIR="/${directory}/ports/mana"

if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR="/roms/ports/mana"
fi

CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1

LOGFILE="$GAMEDIR/log.txt"

: > "$LOGFILE"

exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo " Mana 0.8.0 PortMaster R36S"
echo " Mouse + Teclado Virtual"
echo "========================================"

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -f "$GAME" ]; then
    echo "ERRO: executavel nao encontrado:"
    echo "$GAME"
    exit 1
fi

chmod +x "$GAME"

if [ -d "$GAMEDIR/mana/libs.${DEVICE_ARCH:-aarch64}" ]; then
    export LD_LIBRARY_PATH="$GAMEDIR/mana/libs.${DEVICE_ARCH:-aarch64}:${LD_LIBRARY_PATH:-}"
fi

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
fi

# ============================================================
# TECLADO VIRTUAL GPTOKEYB
# ============================================================

export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

echo "Teclado virtual GPTK: ATIVADO"
echo "Abrir: START + D-PAD DOWN"

# ============================================================
# GPTOKEYB
# ============================================================

cd "$GAMEDIR/mana" || exit 1

GPTK_CONFIG="./mana.gptk"

if [ ! -f "$GPTK_CONFIG" ]; then
    echo "ERRO: mana.gptk nao encontrado:"
    echo "$GAMEDIR/mana/mana.gptk"
    exit 1
fi

GPTOPID=""

if [ -n "${GPTOKEYB2:-}" ]; then

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

elif [ -n "${GPTOKEYB:-}" ]; then

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

else

    echo "ERRO: GPTOKEYB/GPTOKEYB2 nao encontrado."
    exit 1

fi

cleanup()
{
    if [ -n "${GPTOPID:-}" ]; then
        kill "$GPTOPID" 2>/dev/null || true
        wait "$GPTOPID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

echo
echo "Mouse:"
echo "  Analogico direito = movimento"
echo "  R3 = clique esquerdo"
echo "  L3 = clique direito"

echo
echo "Cursor:"
echo "  SELECT = F12 = mostrar/ocultar"

echo
echo "Teclado:"
echo "  START + DOWN = teclado virtual"

"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"

RET=$?

exit "$RET"
EOF

fi

chmod +x "$PORT/Mana.sh"

# ============================================================
# PORT.JSON
# ============================================================

if [ ! -f "$PORT/port.json" ]; then

    echo
    echo "Criando port/port.json"

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

fi

# ============================================================
# GPTK
# ============================================================

if [ ! -f "$PORT/mana/mana.gptk" ]; then

    echo
    echo "Criando mana/mana.gptk"

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

fi

# ============================================================
# LIMPAR ARQUIVO ANTIGO
# ============================================================

rm -f "$PORT/mana/mana.aarch64"

# ============================================================
# COPIAR EXECUTAVEL
# ============================================================

cp "$BIN" "$PORT/mana/mana.aarch64"

chmod +x "$PORT/mana/mana.aarch64"

# ============================================================
# DATA
# ============================================================

if [ -d "$SRC_DIR/data" ]; then

    echo
    echo "Copiando data do source."

    rm -rf "$PORT/mana/data"

    cp -a \
        "$SRC_DIR/data" \
        "$PORT/mana/data"

elif [ -d "$ROOT/mana/data" ]; then

    echo
    echo "Source data nao encontrado."
    echo "Usando data existente em /workspace/mana."

    rm -rf "$PORT/mana/data"

    cp -a \
        "$ROOT/mana/data" \
        "$PORT/mana/data"

else

    echo
    echo "ERRO: diretorio data nao encontrado."
    exit 1

fi

# ============================================================
# GARANTIR MOUSE.PNG
# ============================================================

MOUSE_PNG="$PORT/mana/data/graphics/gui/mouse.png"

if [ ! -f "$MOUSE_PNG" ]; then

    echo
    echo "ERRO: mouse.png nao encontrado:"
    echo "$MOUSE_PNG"

    exit 1

fi

echo
echo "mouse.png: OK"

# ============================================================
# LICENCAS
# ============================================================

if [ -d "$SRC_DIR/licenses" ]; then

    rm -rf "$PORT/mana/licenses"

    cp -a \
        "$SRC_DIR/licenses" \
        "$PORT/mana/licenses"

fi

# ============================================================
# VALIDACAO PORTMASTER
# ============================================================

echo
echo "========================================"
echo " Validando pacote"
echo "========================================"
echo

test -f "$PORT/Mana.sh"
test -f "$PORT/port.json"
test -f "$PORT/mana/mana.aarch64"
test -f "$PORT/mana/mana.gptk"
test -f "$PORT/mana/data/graphics/gui/mouse.png"

echo "Mana.sh: OK"
echo "port.json: OK"
echo "mana.aarch64: OK"
echo "mana.gptk: OK"
echo "mouse.png: OK"

# ============================================================
# PACKAGE
# ============================================================

PACKAGE="$DIST/mana-r36s-portmaster-0.8.0-aarch64"

rm -rf "$PACKAGE"

mkdir -p "$PACKAGE"

cp "$PORT/Mana.sh" \
    "$PACKAGE/Mana.sh"

cp "$PORT/port.json" \
    "$PACKAGE/port.json"

cp "$PORT/mana/mana.aarch64" \
    "$PACKAGE/mana.aarch64"

mkdir -p "$PACKAGE/mana"

cp "$PORT/mana/mana.gptk" \
    "$PACKAGE/mana/mana.gptk"

cp -a "$PORT/mana/data" \
    "$PACKAGE/mana/data"

if [ -d "$PORT/mana/licenses" ]; then

    cp -a "$PORT/mana/licenses" \
        "$PACKAGE/mana/licenses"

fi

# ============================================================
# ZIP
# ============================================================

echo
echo "========================================"
echo " Criando ZIP PortMaster"
echo "========================================"
echo

cd "$PACKAGE"

zip -r \
    "$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip" \
    . \
    >/dev/null

cd "$ROOT"

echo
echo "ZIP criado:"
echo "$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

# ============================================================
# TAMANHO
# ============================================================

ls -lh \
    "$DIST/mana-r36s-portmaster-0.8.0-aarch64.zip"

echo
echo "========================================"
echo " BUILD FINALIZADO"
echo "========================================"
echo
