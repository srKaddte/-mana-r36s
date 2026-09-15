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

if "TTF_SetFontSize(" not in source:
    print("TTF_SetFontSize nao encontrado.")
    print("Nenhuma substituicao necessaria.")
    sys.exit(0)

replacement = r'''void TrueTypeFont::updateFontScale(float scale)
{
    if (mScale == scale)
        return;

    if (scale <= 0.0f)
        return;

    for (auto font : mFonts)
    {
        const int newSize = std::max(
            1,
            static_cast<int>(
                std::lround(font->mPointSize * scale)
            )
        );

        TTF_Font *newFont = TTF_OpenFont(
            font->mFilename.c_str(),
            newSize
        );

        TTF_Font *newFontOutline = TTF_OpenFont(
            font->mFilename.c_str(),
            newSize
        );

        if (!newFont || !newFontOutline)
        {
            if (newFont)
                TTF_CloseFont(newFont);

            if (newFontOutline)
                TTF_CloseFont(newFontOutline);

            std::cerr
                << "WARNING: unable to resize font '"
                << font->mFilename
                << "' to "
                << newSize
                << " pixels: "
                << TTF_GetError()
                << std::endl;

            continue;
        }

        TTF_SetFontStyle(
            newFont,
            font->mStyle
        );

        TTF_SetFontStyle(
            newFontOutline,
            font->mStyle
        );

        const int outlineSize = std::max(
            1,
            static_cast<int>(
                std::lround(scale)
            )
        );

        TTF_SetFontOutline(
            newFontOutline,
            outlineSize
        );

        TTF_CloseFont(font->mFont);
        TTF_CloseFont(font->mFontOutline);

        font->mFont = newFont;
        font->mFontOutline = newFontOutline;

        font->mCache.clear();
    }

    mScale = scale;
}
'''

pattern = re.compile(
    r"void\s+TrueTypeFont::updateFontScale\s*\(float\s+scale\)\s*\{.*?\n\}\s*\n\s*(?=int\s+TrueTypeFont::getWidth)",
    re.DOTALL
)

source_new, count = pattern.subn(
    replacement,
    source,
    count=1
)

if count != 1:
    print("ERRO: nao foi possivel localizar a funcao updateFontScale().")
    sys.exit(1)

if "TTF_SetFontSize(" in source_new:
    print("ERRO: TTF_SetFontSize ainda existe depois da correcao.")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(source_new)

print("OK: updateFontScale() foi corrigida.")
print("OK: TTF_SetFontSize() foi removida do arquivo.")
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

echo "========================================"
echo " Adicionando teclado virtual do R36S"
echo "========================================"
echo
GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"
if [ ! -f "$GUI_H" ] || [ ! -f "$GUI_CPP" ]; then
    echo "ERRO: gui.h/gui.cpp nao encontrados."
    exit 1
fi
python3 - "$GUI_H" "$GUI_CPP" <<'PYCODE'
import sys
from pathlib import Path

header = Path(sys.argv[1])
source = Path(sys.argv[2])
h = header.read_text(encoding='utf-8')
c = source.read_text(encoding='utf-8')

if 'mVirtualKeyboardVisible' not in h:
    old = '        ResourceRef<Image> mSoftwareCursor;\n'
    new = old + '''        bool mSoftwareCursorVisible = true;
        bool mVirtualKeyboardVisible = false;
        bool mVirtualKeyboardStartPressed = false;
        int mVirtualKeyboardRow = 0;
        int mVirtualKeyboardColumn = 0;
        std::string mVirtualKeyboardOriginalText;
'''
    if old not in h:
        raise SystemExit('ERRO: ponto de insercao em gui.h nao encontrado')
    h = h.replace(old, new, 1)

if 'void handleVirtualKeyboardKey' not in h:
    old = '        void handleTextInput(const TextInput &textInput);\n'
    new = old + '''        void handleVirtualKeyboardKey(int key);
        void moveVirtualKeyboard(int dRow, int dColumn);
        void openVirtualKeyboard();
        void closeVirtualKeyboard(bool cancel);
'''
    if old not in h:
        raise SystemExit('ERRO: handleTextInput em gui.h nao encontrado')
    h = h.replace(old, new, 1)

if 'R36S_VIRTUAL_KEYBOARD_ROWS' not in c:
    marker = 'bool Gui::debugDraw;\n'
    block = r'''

namespace
{
static const char *const R36S_VIRTUAL_KEYBOARD_ROWS[] =
{
    "ABCDEFGHIJ",
    "KLMNOPQRST",
    "UVWXYZ0123",
    "456789.!?,",
    "-_\'@#$%&*",
    "()[]{}+=:;",
    " !?.,-_/",
};

constexpr int R36S_VIRTUAL_KEYBOARD_ROWS_COUNT =
    sizeof(R36S_VIRTUAL_KEYBOARD_ROWS) /
    sizeof(R36S_VIRTUAL_KEYBOARD_ROWS[0]);
}
'''
    if marker not in c:
        raise SystemExit('ERRO: ponto de insercao em gui.cpp nao encontrado')
    c = c.replace(marker, marker + block, 1)

old = '''void Gui::keyPressed(gcn::KeyEvent &event)
{
    if (mActiveDrag && event.getKey().getValue() == Key::ESCAPE)
    {
        cancelActiveDrag();
        event.consume();
    }
}

void Gui::keyReleased(gcn::KeyEvent &/*event*/)
{
}
'''

if old in c:
    new = r'''void Gui::keyPressed(gcn::KeyEvent &event)
{
    const int key = event.getKey().getValue();

    if (mVirtualKeyboardVisible)
    {
        if (key == Key::F12 || key == Key::ESCAPE)
        {
            closeVirtualKeyboard(true);
            event.consume();
            return;
        }

        if (key == Key::UP)
        {
            moveVirtualKeyboard(-1, 0);
            event.consume();
            return;
        }
        if (key == Key::DOWN)
        {
            moveVirtualKeyboard(1, 0);
            event.consume();
            return;
        }
        if (key == Key::LEFT)
        {
            moveVirtualKeyboard(0, -1);
            event.consume();
            return;
        }
        if (key == Key::RIGHT)
        {
            moveVirtualKeyboard(0, 1);
            event.consume();
            return;
        }
        if (key == SDLK_SPACE || key == Key::ENTER)
        {
            handleVirtualKeyboardKey(key);
            event.consume();
            return;
        }
    }
    else
    {
        if (key == Key::ENTER)
        {
            mVirtualKeyboardStartPressed = true;
        }
        else if (key == Key::DOWN && mVirtualKeyboardStartPressed)
        {
            openVirtualKeyboard();
            event.consume();
            return;
        }

        if (key == Key::F12)
        {
            mSoftwareCursorVisible = !mSoftwareCursorVisible;
            SDL_ShowCursor(SDL_DISABLE);
            event.consume();
            return;
        }
    }

    if (mActiveDrag && key == Key::ESCAPE)
    {
        cancelActiveDrag();
        event.consume();
    }
}

void Gui::keyReleased(gcn::KeyEvent &event)
{
    if (event.getKey().getValue() == Key::ENTER)
        mVirtualKeyboardStartPressed = false;
}
'''
    c = c.replace(old, new, 1)
elif 'void Gui::openVirtualKeyboard()' not in c:
    raise SystemExit('ERRO: keyPressed original nao encontrado')

if 'mSoftwareCursorVisible && mSoftwareCursor' not in c:
    c = c.replace('    if (mSoftwareCursor)\n    {\n', '    if (mSoftwareCursorVisible && mSoftwareCursor)\n    {\n', 1)

if 'void Gui::openVirtualKeyboard()' not in c:
    marker = 'void Gui::handleTextInput(const TextInput &textInput)\n'
    methods = r'''
void Gui::openVirtualKeyboard()
{
    if (mVirtualKeyboardVisible || !mFocusHandler)
        return;

    if (!dynamic_cast<TextField*>(mFocusHandler->getFocused()))
        return;

    mVirtualKeyboardVisible = true;
    mVirtualKeyboardRow = 0;
    mVirtualKeyboardColumn = 0;
    auto *textField = dynamic_cast<TextField*>(mFocusHandler->getFocused());
    mVirtualKeyboardOriginalText = textField ? textField->getText() : std::string();
}

void Gui::closeVirtualKeyboard(bool cancel)
{
    if (cancel && mFocusHandler)
    {
        if (auto *textField = dynamic_cast<TextField*>(mFocusHandler->getFocused()))
        {
            textField->setText(mVirtualKeyboardOriginalText);
            textField->setCaretPosition(textField->getText().size());
        }
    }

    mVirtualKeyboardVisible = false;
    mVirtualKeyboardRow = 0;
    mVirtualKeyboardColumn = 0;
    mVirtualKeyboardOriginalText.clear();
}

void Gui::moveVirtualKeyboard(int dRow, int dColumn)
{
    if (!mVirtualKeyboardVisible)
        return;

    int row = mVirtualKeyboardRow + dRow;
    int column = mVirtualKeyboardColumn + dColumn;

    if (row < 0)
        row = R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1;
    if (row >= R36S_VIRTUAL_KEYBOARD_ROWS_COUNT)
        row = 0;

    const int rowLength = static_cast<int>(
        std::strlen(R36S_VIRTUAL_KEYBOARD_ROWS[row])
    );

    if (column < 0)
        column = rowLength - 1;
    if (column >= rowLength)
        column = 0;

    mVirtualKeyboardRow = row;
    mVirtualKeyboardColumn = column;
}

void Gui::handleVirtualKeyboardKey(int key)
{
    if (!mVirtualKeyboardVisible || !mFocusHandler)
        return;

    auto *textField = dynamic_cast<TextField*>(mFocusHandler->getFocused());
    if (!textField)
    {
        closeVirtualKeyboard(true);
        return;
    }

    if (key == Key::ENTER)
    {
        gcn::KeyEvent enterEvent(textField, gcn::Key(Key::ENTER));
        textField->keyPressed(enterEvent);
        closeVirtualKeyboard(false);
        return;
    }

    const int row = mVirtualKeyboardRow;
    const int column = mVirtualKeyboardColumn;
    const std::string rowText = R36S_VIRTUAL_KEYBOARD_ROWS[row];

    if (row == R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1 && column == 8)
    {
        std::string text = textField->getText();
        unsigned caret = textField->getCaretPosition();
        if (caret > 0)
        {
            --caret;
            text.erase(caret, 1);
            textField->setText(text);
            textField->setCaretPosition(caret);
        }
        return;
    }

    if (row == R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1 && column == 9)
    {
        gcn::KeyEvent enterEvent(textField, gcn::Key(Key::ENTER));
        textField->keyPressed(enterEvent);
        closeVirtualKeyboard(false);
        return;
    }

    if (column >= static_cast<int>(rowText.size()))
        return;

    std::string text = textField->getText();
    unsigned caret = textField->getCaretPosition();
    text.insert(caret, 1, rowText[column]);
    ++caret;
    textField->setText(text);
    textField->setCaretPosition(caret);
}

'''
    if marker not in c:
        raise SystemExit('ERRO: handleTextInput nao encontrado')
    c = c.replace(marker, methods + marker, 1)

if 'R36S Virtual Keyboard' not in c:
    marker = '    // Render the cursor last so it stays above all GUI widgets.\n'
    draw = r'''
    if (mVirtualKeyboardVisible)
    {
        const int screenWidth = graphics->getWidth();
        const int screenHeight = graphics->getHeight();
        const int columns = 10;
        const int cellWidth = screenWidth / columns;
        const int keyWidth = std::max(32, cellWidth - 4);
        const int keyHeight = std::max(28, static_cast<int>(graphics->getScale() * 30));
        const int top = std::max(0, screenHeight - keyHeight * R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 48);

        graphics->setColor(gcn::Color(0, 0, 0, 220));
        graphics->fillRectangle(gcn::Rectangle(0, top, screenWidth, screenHeight - top));
        graphics->setFont(mGuiFont);
        graphics->setColor(gcn::Color(255, 255, 255));
        graphics->drawText("R36S Virtual Keyboard", 8, top + 8);

        for (int row = 0; row < R36S_VIRTUAL_KEYBOARD_ROWS_COUNT; ++row)
        {
            const std::string keys = R36S_VIRTUAL_KEYBOARD_ROWS[row];
            for (int column = 0; column < columns; ++column)
            {
                const int x = column * cellWidth + 2;
                const int y = top + 38 + row * keyHeight;
                const bool selected = row == mVirtualKeyboardRow && column == mVirtualKeyboardColumn;

                std::string label;
                if (row == R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1 && column == 8)
                    label = "BKSP";
                else if (row == R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1 && column == 9)
                    label = "ENTER";
                else if (row == R36S_VIRTUAL_KEYBOARD_ROWS_COUNT - 1 && column == 0)
                    label = "SPACE";
                else if (column < static_cast<int>(keys.size()))
                    label = std::string(1, keys[column]);
                else
                    continue;

                graphics->setColor(selected
                    ? gcn::Color(70, 150, 240, 245)
                    : gcn::Color(45, 45, 45, 235));
                graphics->fillRectangle(gcn::Rectangle(x, y, keyWidth, keyHeight - 3));
                graphics->setColor(gcn::Color(180, 180, 180));
                graphics->drawRectangle(gcn::Rectangle(x, y, keyWidth, keyHeight - 3));

                const int tw = mGuiFont->getWidth(label);
                const int th = mGuiFont->getHeight();
                graphics->setColor(gcn::Color(255, 255, 255));
                graphics->drawText(label,
                                   x + std::max(2, (keyWidth - tw) / 2),
                                   y + std::max(1, (keyHeight - th) / 2));
            }
        }
    }

'''
    if marker not in c:
        raise SystemExit('ERRO: ponto de desenho do cursor nao encontrado')
    c = c.replace(marker, draw + marker, 1)

if '#include <cstring>' not in c:
    c = c.replace('#include <cmath>\n', '#include <cmath>\n#include <cstring>\n', 1)

header.write_text(h, encoding='utf-8')
source.write_text(c, encoding='utf-8')
print('OK: teclado virtual adicionado')
PYCODE
python3 - "$GUI_H" "$GUI_CPP" <<'PYCODE'
from pathlib import Path
import sys
h=Path(sys.argv[1]).read_text(encoding='utf-8')
c=Path(sys.argv[2]).read_text(encoding='utf-8')
checks={
'keyboard_state':h.count('mVirtualKeyboardVisible'),
'keyboard_open':c.count('void Gui::openVirtualKeyboard()'),
'keyboard_draw':c.count('R36S Virtual Keyboard'),
'start_down':c.count('key == Key::DOWN && mVirtualKeyboardStartPressed'),
'cursor_toggle':c.count('mSoftwareCursorVisible = !mSoftwareCursorVisible'),
'space_key':c.count('label = "SPACE"'),
}
print(checks)
if checks['keyboard_open'] != 1 or checks['keyboard_draw'] != 1 or checks['start_down'] != 1 or checks['cursor_toggle'] != 1 or checks['space_key'] != 1:
    raise SystemExit('ERRO: validacao teclado/mouse falhou')
print('KEYBOARD/CURSOR PATCH VALIDADO')
PYCODE

echo
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

#
# O launcher e criado automaticamente caso o usuario
# ainda nao tenha colocado port/Mana.sh no repositorio.
#

if [ ! -f "$PORT/Mana.sh" ]; then
    echo "port/Mana.sh nao encontrado."
    echo "Criando launcher funcional automaticamente..."
    cat > "$PORT/Mana.sh" <<'EOF'
#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/mana"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"
cd "$GAMEDIR" || exit 1

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

echo "Mana 0.8.0"
echo "Architecture: $DEVICE_ARCH"
echo "Game directory: $GAMEDIR"

if [ "$DEVICE_ARCH" != "aarch64" ]; then
    echo "ERROR: This port requires aarch64"
    pm_finish
    exit 1
fi

if [ -f "$GAMEDIR/mana/mana.aarch64" ]; then
    GAME="$GAMEDIR/mana/mana.aarch64"
    GAMEDATA="$GAMEDIR/mana/data"
    GAMEROOT="$GAMEDIR/mana"
elif [ -f "$GAMEDIR/mana.aarch64" ]; then
    GAME="$GAMEDIR/mana.aarch64"
    GAMEDATA="$GAMEDIR/data"
    GAMEROOT="$GAMEDIR"
else
    echo "ERROR: Mana executable not found"
    find "$GAMEDIR" -maxdepth 4 -type f -print 2>/dev/null || true
    pm_finish
    exit 1
fi

if [ ! -d "$GAMEDATA" ]; then
    echo "ERROR: Mana data directory not found: $GAMEDATA"
    find "$GAMEDIR" -maxdepth 4 -type d -print 2>/dev/null || true
    pm_finish
    exit 1
fi

chmod +x "$GAME"

export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
if [ -f "$controlfolder/gamecontrollerdb.txt" ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="$controlfolder/gamecontrollerdb.txt"
fi
export XDG_CONFIG_HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"

cd "$GAMEROOT" || exit 1

GPTOPID=""
if [ -n "$GPTOKEYB" ] && [ -f "$GAMEROOT/mana.gptk" ]; then
    $GPTOKEYB "mana.aarch64" -c "./mana.gptk" &
    GPTOPID=$!
fi

pm_platform_helper "$GAME"

echo "Executable: $GAME"
echo "Data: $GAMEDATA"
echo "Starting Mana..."

"$GAME" --data "$GAMEDATA" --localdata-dir "$CONFDIR"
RET=$?

echo "Mana exited with code $RET"

if [ -n "$GPTOPID" ]; then
    kill "$GPTOPID" 2>/dev/null || true
fi

pm_finish
exit $RET
EOF
    chmod +x "$PORT/Mana.sh"
else
    echo "OK: port/Mana.sh ja existe."
    chmod +x "$PORT/Mana.sh"
fi

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

echo "=== Copiando configuracao GPTK ==="

GPTK_SOURCE=""
if [ -f "$PORT/mana/mana.gptk" ]; then
    GPTK_SOURCE="$PORT/mana/mana.gptk"
elif [ -f "$PORT/mana.gptk" ]; then
    GPTK_SOURCE="$PORT/mana.gptk"
elif [ -f "$PORT/mana/mana.gptk.0" ]; then
    GPTK_SOURCE="$PORT/mana/mana.gptk.0"
fi

if [ -z "$GPTK_SOURCE" ]; then
    echo "ERRO: mana.gptk nao encontrado."
    exit 1
fi
cp "$GPTK_SOURCE" "$PACKAGE/mana/mana.gptk"

cat > "$PACKAGE/mana/mana.gptk" <<'EOF'
# Mana 0.8.0 R36S controls
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
select = f12
deadzone_triggers = 3000
mouse_scale = 8192
mouse_delay = 16
EOF

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
if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao esta no pacote final"
    exit 1
fi
if ! grep -q '^select = f12$' "$PACKAGE/mana/mana.gptk"; then
    echo "ERRO: SELECT/F12 ausente no GPTK"
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
