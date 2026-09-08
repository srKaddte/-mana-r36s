#!/bin/bash
set -euo pipefail

ROOT="/workspace"
SRC_TAR="$ROOT/source/mana-master.tar.gz"
WORK="$ROOT/.build"
SRC="$WORK/mana-master"
BUILD="$WORK/cmake"
INSTALL="$WORK/install"
DIST="$ROOT/dist"
PACKAGE="$DIST/mana-r36s-portmaster-aarch64"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST"

echo "========================================"
echo " Mana 0.8.0 AArch64 / PortMaster FIXED"
echo "========================================"

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

if [ ! -f "$SRC_TAR" ]; then
    echo "ERRO: source não encontrado:"
    echo "$SRC_TAR"
    exit 1
fi

echo "=== Extraindo Mana ==="

tar -xzf "$SRC_TAR" -C "$WORK"

if [ ! -d "$SRC" ]; then
    FOUND="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)"

    if [ -z "$FOUND" ]; then
        echo "ERRO: diretório do source não encontrado."
        exit 1
    fi

    SRC="$FOUND"
fi

echo "Source:"
echo "$SRC"

echo "=== Preparando Guichan ==="

rm -rf "$SRC/libs/guichan"

git clone \
    --depth 1 \
    --branch v0.8.3 \
    https://github.com/darkbitsorg/guichan.git \
    "$SRC/libs/guichan"

echo "=== Preparando ENet ==="

rm -rf "$SRC/libs/enet"

git clone \
    --depth 1 \
    --branch v1.3.18 \
    https://github.com/lsalzman/enet.git \
    "$SRC/libs/enet"

echo "=== Aplicando patches ==="

python3 - "$SRC" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])

print("Source:", src)

# ============================================================
# 1. SDL2_ttf
# ============================================================

print("=== Corrigindo requisito SDL2_ttf ===")

for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except UnicodeDecodeError:
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
            "SDL2_ttf>= 2.0.18",
            "SDL2_ttf>= 2.0.15"
        ),
        (
            "SDL2_ttf >= 2.0.18",
            "SDL2_ttf >= 2.0.15"
        ),
    ]

    for old, new in replacements:
        text = text.replace(old, new)

    if text != original:
        path.write_text(text)
        print("Patched:", path)

print("=== Verificando SDL2_ttf ===")

for path in src.rglob("CMakeLists.txt"):

    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue

    if re.search(
        r"SDL2_ttf\s*[>=]+\s*2\.0\.18",
        text
    ):
        raise SystemExit(
            f"ERRO: requisito SDL2_ttf 2.0.18 ainda existe em {path}"
        )

print("SDL2_ttf requirement OK")


# ============================================================
# 2. SDL_ttf 2.0.15
# ============================================================

print("=== Corrigindo TTF_SetFontSize ===")

for path in src.rglob("*.cpp"):

    try:
        text = path.read_text()
    except UnicodeDecodeError:
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
        "/* SDL_ttf compatibility. */",
        text
    )

    if text != original:
        path.write_text(text)
        print("Patched:", path)


print("=== Verificando chamadas TTF_SetFontSize ===")

for path in src.rglob("*.cpp"):

    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue

    if re.search(
        r"TTF_SetFontSize[[:space:]]*\(",
        text
    ):
        raise SystemExit(
            f"ERRO: chamada TTF_SetFontSize ainda existe em {path}"
        )

print("TTF_SetFontSize OK")


# ============================================================
# 3. GUI.H
# ============================================================

print("=== Corrigindo cursor no gui.h ===")

gui_h = src / "src/gui/gui.h"

if not gui_h.exists():
    raise SystemExit(
        f"ERRO: arquivo não encontrado: {gui_h}"
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
# CRITICAL FIX
#
# Remove TODAS as declarações anteriores.
# Depois colocamos exatamente UMA.
# ------------------------------------------------------------

text = re.sub(
    r"^[ \t]*ResourceRef<ImageSet>\s+mSoftwareCursor\s*;\s*\n?",
    "",
    text,
    flags=re.MULTILINE
)

text = re.sub(
    r"^[ \t]*bool\s+mSoftwareCursorVisible\s*=\s*true\s*;\s*\n?",
    "",
    text,
    flags=re.MULTILINE
)


# ------------------------------------------------------------
# Inserção determinística
# ------------------------------------------------------------

member_marker = "    bool mCustomCursor = false;"

cursor_members = (
    "    ResourceRef<ImageSet> mSoftwareCursor;\n"
    "    bool mSoftwareCursorVisible = true;\n"
)

if member_marker not in text:

    raise SystemExit(
        "ERRO: ponto de inserção dos membros do Gui não encontrado."
    )

text = text.replace(
    member_marker,
    cursor_members + member_marker,
    1
)

gui_h.write_text(text)


# ============================================================
# 4. GUI.CPP
# ============================================================

print("=== Corrigindo cursor no gui.cpp ===")

gui_cpp = src / "src/gui/gui.cpp"

if not gui_cpp.exists():
    raise SystemExit(
        f"ERRO: arquivo não encontrado: {gui_cpp}"
    )

text = gui_cpp.read_text()


# ------------------------------------------------------------
# Remove blocos antigos conhecidos de inicialização.
# ------------------------------------------------------------

text = re.sub(
    r"""
    \n?[ \t]*
    // PortMaster/R36S can receive GPTK mouse input without displaying an SDL
    [ \t]*// hardware cursor\. Keep SDL's cursor hidden and render Mana's own pointer
    [ \t]*// as part of the frame instead\.
    [ \t]*mSoftwareCursor\s*=
    ResourceManager::getInstance\(\)\.getImageSet\(
    [ \t]*mTheme->resolvePath\("mouse\.png"\),\s*40,\s*40\);
    [ \t]*SDL_ShowCursor\(SDL_DISABLE\);
    """,
    "\n",
    text,
    flags=re.VERBOSE
)


# ------------------------------------------------------------
# Inicialização do cursor.
# Só adiciona se não existir.
# ------------------------------------------------------------

if (
    "mSoftwareCursor = "
    "ResourceManager::getInstance().getImageSet("
    not in text
):

    init_block = """
    // PortMaster/R36S software cursor.
    mSoftwareCursor = ResourceManager::getInstance().getImageSet(
        mTheme->resolvePath("mouse.png"), 40, 40);

    SDL_ShowCursor(SDL_DISABLE);
"""

    marker = "    setInput(guiInput);"

    if marker not in text:

        raise SystemExit(
            "ERRO: ponto de inicialização do Gui não encontrado."
        )

    text = text.replace(
        marker,
        marker + "\n" + init_block,
        1
    )


# ============================================================
# 5. Draw do cursor
# ============================================================

print("=== Corrigindo desenho do cursor ===")

cursor_condition = (
    "if (mSoftwareCursorVisible &&\n"
    "        mSoftwareCursor && "
    "mSoftwareCursor->size() > 0)"
)

if "mSoftwareCursorVisible &&" not in text:

    old_condition = (
        "if (mSoftwareCursor && "
        "mSoftwareCursor->size() > 0)"
    )

    if old_condition in text:

        text = text.replace(
            old_condition,
            cursor_condition,
            1
        )

    else:

        draw_marker = "void Gui::draw()\n{"

        if draw_marker not in text:

            raise SystemExit(
                "ERRO: Gui::draw() não encontrado."
            )

        cursor_draw = """
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
                mMouseY - 17
            );
        }
    }

"""

        text = text.replace(
            draw_marker,
            draw_marker + "\n" + cursor_draw,
            1
        )


# ============================================================
# 6. Hardware cursor
# ============================================================

print("=== Desativando cursor SDL ===")

text = text.replace(
    "SDL_ShowCursor(SDL_ENABLE);",
    "SDL_ShowCursor(SDL_DISABLE);"
)


# ============================================================
# 7. F12 = somente visibilidade
# ============================================================

print("=== Adicionando toggle F12 ===")

toggle_code = """
    // SELECT is mapped to F12 by mana.gptk.
    // F12 changes ONLY cursor visibility.
    // Mouse input remains active.
    if (event.getKey().getValue() == Key::F12)
    {
        mSoftwareCursorVisible =
            !mSoftwareCursorVisible;

        event.consume();
        return;
    }

"""

if (
    "mSoftwareCursorVisible = "
    "!mSoftwareCursorVisible;"
    not in text
):

    marker = "void Gui::keyPressed(gcn::KeyEvent &event)\n{"

    if marker not in text:

        raise SystemExit(
            "ERRO: Gui::keyPressed não encontrado."
        )

    text = text.replace(
        marker,
        marker + toggle_code,
        1
    )


gui_cpp.write_text(text)


# ============================================================
# 8. VALIDAÇÃO DO PATCH
# ============================================================

print("========================================")
print(" VALIDANDO PATCH")
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


if cursor_count != 1:

    raise SystemExit(
        "ERRO: gui.h possui "
        f"{cursor_count} declarações de "
        "mSoftwareCursor. Esperado: 1."
    )


if visible_count != 1:

    raise SystemExit(
        "ERRO: gui.h possui "
        f"{visible_count} declarações de "
        "mSoftwareCursorVisible. Esperado: 1."
    )


c = gui_cpp.read_text()


toggle_count = c.count(
    "mSoftwareCursorVisible = "
    "!mSoftwareCursorVisible;"
)

if toggle_count != 1:

    raise SystemExit(
        "ERRO: toggle F12 não está exatamente uma vez."
    )


for path in src.rglob("*.cpp"):

    try:
        source = path.read_text()
    except UnicodeDecodeError:
        continue

    if re.search(
        r"TTF_SetFontSize\s*\(",
        source
    ):

        raise SystemExit(
            "ERRO: TTF_SetFontSize() ainda existe em "
            f"{path}"
        )


if "SDL_ShowCursor(SDL_DISABLE);" not in c:

    raise SystemExit(
        "ERRO: cursor SDL não foi desabilitado."
    )


print("")
print("PATCH OK")
print("")
print(
    "mSoftwareCursor declarations:",
    cursor_count
)
print(
    "mSoftwareCursorVisible declarations:",
    visible_count
)
print(
    "F12 toggles:",
    toggle_count
)
print("")


# ============================================================
# 9. DEPENDÊNCIAS
# ============================================================

print("========================================")
echo_marker = "=== Dependências SDL2 ==="
print(echo_marker)
print("========================================")

PY

echo "=== Dependências SDL2 ==="

pkg-config --modversion sdl2 || true
pkg-config --modversion SDL2_image || true
pkg-config --modversion SDL2_mixer || true
pkg-config --modversion SDL2_net || true
pkg-config --modversion SDL2_ttf || true
pkg-config --modversion physfs || true
pkg-config --modversion libxml-2.0 || true


# ============================================================
# 10. CMAKE
# ============================================================

echo "========================================"
echo " CONFIGURANDO CMAKE"
echo "========================================"

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
# 11. BUILD
# ============================================================

echo "========================================"
echo " COMPILANDO MANA"
echo "========================================"

cmake \
    --build "$BUILD" \
    --parallel "$(nproc)"


# ============================================================
# 12. INSTALL
# ============================================================

echo "========================================"
echo " INSTALANDO"
echo "========================================"

cmake --install "$BUILD"


# ============================================================
# 13. LOCALIZAR EXECUTÁVEL
# ============================================================

BIN="$(
    find "$INSTALL" \
        -type f \
        -name mana \
        -perm -u+x \
        | head -1
)"

if [ -z "$BIN" ]; then

    echo "ERRO: executável Mana não encontrado."

    find "$INSTALL" \
        -maxdepth 6 \
        -type f \
        -print

    exit 1
fi

echo "Executável encontrado:"
echo "$BIN"


# ============================================================
# 14. PREPARAR BINÁRIO
# ============================================================

mkdir -p "$DIST"

cp \
    "$BIN" \
    "$DIST/mana.aarch64"

chmod +x "$DIST/mana.aarch64"


# ============================================================
# 15. VALIDAR ARQUITETURA
# ============================================================

echo "========================================"
echo " VALIDANDO BINÁRIO"
echo "========================================"

file "$DIST/mana.aarch64"

echo ""
echo "=== GLIBC ==="

readelf \
    --version-info \
    "$DIST/mana.aarch64" \
    | grep -o 'GLIBC_[0-9.]*' \
    | sort -Vu \
    || true


if ! file "$DIST/mana.aarch64" \
    | grep -qi "ARM aarch64"; then

    echo "ERRO: executável não é AArch64."

    exit 1
fi


if readelf \
    --version-info \
    "$DIST/mana.aarch64" \
    | grep -q "GLIBC_2.43"; then

    echo "ERRO: executável exige GLIBC_2.43."

    exit 1
fi


# ============================================================
# 16. PORTMASTER PACKAGE
# ============================================================

echo "========================================"
echo " PREPARANDO PORTMASTER"
echo "========================================"

rm -rf "$PACKAGE"

mkdir -p \
    "$PACKAGE/mana"


# ------------------------------------------------------------
# Arquivos principais
# ------------------------------------------------------------

for f in \
    Mana.sh \
    README.md \
    gameinfo.xml \
    port.json \
    screenshot.png
do

    if [ -f "$ROOT/port/$f" ]; then

        cp \
            "$ROOT/port/$f" \
            "$PACKAGE/"

    fi

done


# ------------------------------------------------------------
# Data
# ------------------------------------------------------------

if [ -d "$ROOT/port/mana/data" ]; then

    cp -a \
        "$ROOT/port/mana/data" \
        "$PACKAGE/mana/"

else

    echo "AVISO:"
    echo "port/mana/data não encontrado."

fi


# ------------------------------------------------------------
# Licenças
# ------------------------------------------------------------

if [ -d "$ROOT/port/mana/licenses" ]; then

    cp -a \
        "$ROOT/port/mana/licenses" \
        "$PACKAGE/mana/"

fi


# ------------------------------------------------------------
# GPTK
# ------------------------------------------------------------

if [ -f "$ROOT/port/mana/mana.gptk.0" ]; then

    cp \
        "$ROOT/port/mana/mana.gptk.0" \
        "$PACKAGE/mana/"

fi


# ------------------------------------------------------------
# Executável
# ------------------------------------------------------------

cp \
    "$DIST/mana.aarch64" \
    "$PACKAGE/mana/mana.aarch64"

chmod +x \
    "$PACKAGE/mana/mana.aarch64"


# ============================================================
# 17. VALIDAR GPTK
# ============================================================

if [ ! -f "$PACKAGE/mana/mana.gptk.0" ]; then

    echo "ERRO: mana.gptk.0 não encontrado."

    echo ""
    echo "Conteúdo de port/mana:"

    find \
        "$ROOT/port/mana" \
        -maxdepth 2 \
        -type f \
        -print \
        || true

    exit 1
fi


# ============================================================
# 18. DIAGNÓSTICOS
# ============================================================

echo "========================================"
echo " GERANDO DIAGNÓSTICOS"
echo "========================================"

{
    echo "Mana 0.8.0 AArch64 PortMaster diagnostics"

    echo ""

    echo "=== FILE ==="

    file \
        "$DIST/mana.aarch64"

    echo ""

    echo "=== GLIBC ==="

    readelf \
        --version-info \
        "$DIST/mana.aarch64" \
        | grep -o 'GLIBC_[0-9.]*' \
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

    echo "=== GUI CURSOR ==="

    grep \
        -n \
        "mSoftwareCursor" \
        "$SRC/src/gui/gui.h" \
        || true

    echo ""

    echo "=== CURSOR VISIBILITY ==="

    grep \
        -n \
        "mSoftwareCursorVisible" \
        "$SRC/src/gui/gui.h" \
        "$SRC/src/gui/gui.cpp" \
        || true

    echo ""

    echo "=== GPTK ==="

    cat \
        "$PACKAGE/mana/mana.gptk.0" \
        || true

} > "$DIST/diagnostics.txt"


# ============================================================
# 19. ZIP
# ============================================================

echo "========================================"
echo " GERANDO ZIP PORTMASTER"
echo "========================================"

cd "$PACKAGE"

zip \
    -r \
    "$DIST/mana-r36s-portmaster-aarch64.zip" \
    . \
    -x '*.DS_Store'

cd "$ROOT"


# ============================================================
# 20. FINAL
# ============================================================

echo ""
echo "========================================"
echo " BUILD FINALIZADO COM SUCESSO"
echo "========================================"

ls -lh "$DIST/"

echo ""
echo "Arquivos gerados:"

find \
    "$DIST" \
    -maxdepth 2 \
    -type f \
    -printf '%p\n'

echo ""
echo "========================================"
echo " MANA R36S PORTMASTER PRONTO"
echo "========================================"
