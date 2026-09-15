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

echo " Adicionando mouse virtual e teclado virtual"
echo "========================================"
echo

GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"
TEXTFIELD_H="$SRC_DIR/src/gui/widgets/textfield.h"
TEXTFIELD_CPP="$SRC_DIR/src/gui/widgets/textfield.cpp"

for REQUIRED in "$GUI_H" "$GUI_CPP" "$TEXTFIELD_H" "$TEXTFIELD_CPP"; do
    if [ ! -f "$REQUIRED" ]; then
        echo "ERRO: arquivo esperado nao encontrado: $REQUIRED"
        exit 1
    fi
done

python3 - "$GUI_H" "$GUI_CPP" "$TEXTFIELD_H" "$TEXTFIELD_CPP" <<'PYPATCH'
import sys
def replace_function_once(text, signature, new_body, label):
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"ERRO: funcao para {label} nao encontrada")

    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"ERRO: abertura da funcao para {label} nao encontrada")

    depth = 0
    in_string = False
    in_char = False
    escape = False
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
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if in_char:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == "'":
                in_char = False
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
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "'":
            in_char = True
            i += 1
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[:start] + new_body + text[i + 1:]
        i += 1

    raise SystemExit(f"ERRO: fim da funcao para {label} nao encontrado")

h = read(GUI_H)
if '#include "resources/image.h"' not in h:
    count = h.count('#include "resources/theme.h"')
    if count != 1:
        raise SystemExit(f"ERRO: marcador para resources/image.h encontrado {count} vezes")
    h = h.replace('#include "resources/theme.h"', '#include "resources/image.h"\n#include "resources/theme.h"', 1)
if 'class Image;' not in h:
    count = h.count('class SDLInput;')
    if count != 1:
        raise SystemExit(f"ERRO: marcador para Image encontrado {count} vezes")
    h = h.replace('class SDLInput;', 'class SDLInput;\nclass Image;', 1)
h = replace_once(h, '        void updateDragTargetFromPosition(int x, int y);\n\n', '''        void updateDragTargetFromPosition(int x, int y);
        void drawVirtualKeyboard(Graphics *graphics);
        bool handleVirtualKeyboardKey(int key);
        void openVirtualKeyboard();
        void closeVirtualKeyboard(bool confirm);
        void insertVirtualKeyboardText(const std::string &text);

''', 'metodos teclado')
h = replace_once(h, '        int mMouseY = 0;\n        Cursor mCursorType = Cursor::Pointer;\n', '''        int mMouseY = 0;
        Cursor mCursorType = Cursor::Pointer;
        ResourceRef<Image> mSoftwareCursorImage;
        bool mSoftwareCursorVisible = true;
        bool mVirtualKeyboardVisible = false;
        int mVirtualKeyboardRow = 0;
        int mVirtualKeyboardCol = 0;
''', 'estado teclado/mouse')
write(GUI_H, h)

th = read(TEXTFIELD_H)
th = replace_once(th, '        void keyPressed(gcn::KeyEvent &keyEvent) override;\n', '        void keyPressed(gcn::KeyEvent &keyEvent) override;\n        void virtualEnter();\n', 'virtualEnter declaration')
write(TEXTFIELD_H, th)

tc = read(TEXTFIELD_CPP)
virtual_enter = '''void TextField::virtualEnter()
{
    if (mHistory)
    {
        if (!getText().empty() && (mHistory->empty() ||
            !mHistory->matchesLastEntry(getText())))
        {
            mHistory->addEntry(getText());
        }
        mHistory->toEnd();
    }
    distributeActionEvent();
}

'''
if 'void TextField::virtualEnter()' not in tc:
    count = tc.count('void TextField::textInput(const TextInput &textInput)')
    if count != 1:
        raise SystemExit(f"ERRO: marcador para virtualEnter encontrado {count} vezes")
    tc = tc.replace('void TextField::textInput(const TextInput &textInput)\n', virtual_enter + 'void TextField::textInput(const TextInput &textInput)\n', 1)
write(TEXTFIELD_CPP, tc)

c = read(GUI_CPP)
c = replace_once(c, '    setUseCustomCursor(config.customCursor);\n\n    listen(Event::ConfigChannel);\n', '''    setUseCustomCursor(config.customCursor);

    mSoftwareCursorImage = ResourceManager::getInstance()->getImage(
        "graphics/gui/mouse.png");
    SDL_ShowCursor(SDL_DISABLE);

    listen(Event::ConfigChannel);
''', 'cursor image load')

new_draw = '''void Gui::draw()
{
    gcn::Gui::draw();

    auto *graphics = static_cast<Graphics*>(mGraphics);
    if (!graphics)
        return;

    if (mVirtualKeyboardVisible)
        drawVirtualKeyboard(graphics);

    if (mActiveDrag)
    {
        graphics->pushClipArea(gcn::Rectangle(0, 0,
                                              graphics->getWidth(),
                                              graphics->getHeight()));
        mActiveDrag->draw(graphics, mMouseX, mMouseY);
        graphics->popClipArea();
    }

    if (mSoftwareCursorVisible && mSoftwareCursorImage)
    {
        const int cursorX = std::max(0, mMouseX - 15);
        const int cursorY = std::max(0, mMouseY - 17);
        graphics->drawImage(mSoftwareCursorImage,
                            0, 0,
                            cursorX, cursorY,
                            40, 40);
    }
}
'''
c = replace_function_once(c, 'void Gui::draw()', new_draw, 'Gui::draw')
# Keep the real SDL cursor hidden while the software cursor is active.
c = replace_once(c, '    // Make sure the cursor is visible\n    SDL_ShowCursor(SDL_ENABLE);\n', '    // Keep the OS cursor hidden while the software cursor is enabled.\n    SDL_ShowCursor(mSoftwareCursorVisible ? SDL_DISABLE : SDL_ENABLE);\n', 'mouse cursor visibility')

impl = r'''namespace
{
const char *const virtualKeyboardRows[] =
{
    "1234567890",
    "QWERTYUIOP",
    "ASDFGHJKL",
    "ZXCVBNM",
    "-_/.:@"
};

const int virtualKeyboardRowCount =
    static_cast<int>(sizeof(virtualKeyboardRows) / sizeof(virtualKeyboardRows[0]));
}

void Gui::openVirtualKeyboard()
{
    auto focused = mFocusHandler->getFocused();
    if (!focused || !dynamic_cast<TextField*>(focused))
        return;

    mVirtualKeyboardVisible = true;
    mVirtualKeyboardRow = 0;
    mVirtualKeyboardCol = 0;
}

void Gui::closeVirtualKeyboard(bool confirm)
{
    if (!mVirtualKeyboardVisible)
        return;

    if (confirm)
    {
        if (auto focused = mFocusHandler->getFocused())
        {
            if (auto textField = dynamic_cast<TextField*>(focused))
                textField->virtualEnter();
        }
    }
    mVirtualKeyboardVisible = false;
}

void Gui::insertVirtualKeyboardText(const std::string &text)
{
    auto focused = mFocusHandler->getFocused();
    auto textField = focused ? dynamic_cast<TextField*>(focused) : nullptr;
    if (!textField)
        return;

    std::string value = textField->getText();
    unsigned position = textField->getCaretPosition();
    if (position > value.size())
        position = value.size();

    value.insert(position, text);
    textField->setText(value);
    textField->setCaretPosition(position + text.size());
}

bool Gui::handleVirtualKeyboardKey(int key)
{
    if (key == Key::ESCAPE)
    {
        closeVirtualKeyboard(false);
        return true;
    }

    if (key == Key::ENTER || key == SDLK_SPACE)
    {
        if (mVirtualKeyboardRow < virtualKeyboardRowCount)
        {
            const char *row = virtualKeyboardRows[mVirtualKeyboardRow];
            const int rowLength = static_cast<int>(std::strlen(row));
            if (mVirtualKeyboardCol < rowLength)
                insertVirtualKeyboardText(std::string(1, row[mVirtualKeyboardCol]));
        }
        else if (mVirtualKeyboardCol == 0)
        {
            insertVirtualKeyboardText(" ");
        }
        else if (mVirtualKeyboardCol == 1)
        {
            if (auto focused = mFocusHandler->getFocused())
            {
                if (auto textField = dynamic_cast<TextField*>(focused))
                {
                    std::string value = textField->getText();
                    unsigned oldPosition = textField->getCaretPosition();
                    if (oldPosition > 0 && oldPosition <= value.size())
                    {
                        unsigned position = oldPosition - 1;
                        while (position > 0 &&
                               (static_cast<unsigned char>(value[position]) & 192) == 128)
                            --position;
                        value.erase(position, oldPosition - position);
                        textField->setText(value);
                        textField->setCaretPosition(position);
                    }
                }
            }
        }
        else if (mVirtualKeyboardCol == 2)
        {
            closeVirtualKeyboard(true);
        }
        else
        {
            closeVirtualKeyboard(false);
        }
        return true;
    }

    if (key == Key::UP)
    {
        if (mVirtualKeyboardRow > 0)
            --mVirtualKeyboardRow;
        int rowLength = static_cast<int>(std::strlen(
            virtualKeyboardRows[mVirtualKeyboardRow]));
        if (mVirtualKeyboardCol >= rowLength)
            mVirtualKeyboardCol = std::max(0, rowLength - 1);
        return true;
    }

    if (key == Key::DOWN)
    {
        if (mVirtualKeyboardRow < virtualKeyboardRowCount)
            ++mVirtualKeyboardRow;
        if (mVirtualKeyboardRow < virtualKeyboardRowCount)
        {
            int rowLength = static_cast<int>(std::strlen(
                virtualKeyboardRows[mVirtualKeyboardRow]));
            if (mVirtualKeyboardCol >= rowLength)
                mVirtualKeyboardCol = std::max(0, rowLength - 1);
        }
        else if (mVirtualKeyboardCol > 3)
        {
            mVirtualKeyboardCol = 3;
        }
        return true;
    }

    if (key == Key::LEFT)
    {
        if (mVirtualKeyboardCol > 0)
            --mVirtualKeyboardCol;
        return true;
    }

    if (key == Key::RIGHT)
    {
        int rowLength = 4;
        if (mVirtualKeyboardRow < virtualKeyboardRowCount)
            rowLength = static_cast<int>(std::strlen(
                virtualKeyboardRows[mVirtualKeyboardRow]));
        if (mVirtualKeyboardCol + 1 < rowLength)
            ++mVirtualKeyboardCol;
        return true;
    }

    return false;
}

void Gui::drawVirtualKeyboard(Graphics *graphics)
{
    const int screenW = graphics->getWidth();
    const int screenH = graphics->getHeight();
    const int margin = 8;
    const int keyGap = 4;
    const int keyW = std::max(26, (screenW - margin * 2 - keyGap * 9) / 10);
    const int keyH = std::max(24, std::min(30, screenH / 18));
    const int totalRows = virtualKeyboardRowCount + 1;
    const int panelH = totalRows * (keyH + keyGap) + 34;
    const int panelY = screenH - panelH - margin;

    graphics->setColor(gcn::Color(0, 0, 0, 220));
    graphics->fillRectangle(gcn::Rectangle(
        margin, panelY, screenW - margin * 2, panelH));

    graphics->setFont(mGuiFont);
    graphics->setColor(gcn::Color(255, 255, 255));
    graphics->drawText(
        "Teclado: START seleciona / B cancela / SELECT mouse",
        screenW / 2, panelY + 8, gcn::Graphics::CENTER);

    for (int r = 0; r < virtualKeyboardRowCount; ++r)
    {
        const int length = static_cast<int>(std::strlen(virtualKeyboardRows[r]));
        const int rowWidth = length * keyW + (length - 1) * keyGap;
        const int x0 = (screenW - rowWidth) / 2;
        const int y = panelY + 32 + r * (keyH + keyGap);

        for (int c = 0; c < length; ++c)
        {
            const bool selected = mVirtualKeyboardRow == r &&
                                   mVirtualKeyboardCol == c;
            graphics->setColor(selected
                ? gcn::Color(90, 120, 180)
                : gcn::Color(55, 55, 55));
            graphics->fillRectangle(gcn::Rectangle(
                x0 + c * (keyW + keyGap), y, keyW, keyH));
            graphics->setColor(gcn::Color(255, 255, 255));
            graphics->drawText(
                std::string(1, virtualKeyboardRows[r][c]),
                x0 + c * (keyW + keyGap) + keyW / 2,
                y + keyH / 2 - mGuiFont->getHeight() / 2,
                gcn::Graphics::CENTER);
        }
    }

    const int specialY = panelY + 32 + virtualKeyboardRowCount * (keyH + keyGap);
    const int specialW = (screenW - margin * 2 - keyGap * 3) / 4;
    const char *special[] = { "SPACE", "BKSP", "ENTER", "CANCEL" };

    for (int c = 0; c < 4; ++c)
    {
        const bool selected = mVirtualKeyboardRow == virtualKeyboardRowCount &&
                              mVirtualKeyboardCol == c;
        graphics->setColor(selected
            ? gcn::Color(90, 120, 180)
            : gcn::Color(55, 55, 55));
        graphics->fillRectangle(gcn::Rectangle(
            margin + c * (specialW + keyGap), specialY, specialW, keyH));
        graphics->setColor(gcn::Color(255, 255, 255));
        graphics->drawText(
            special[c],
            margin + c * (specialW + keyGap) + specialW / 2,
            specialY + keyH / 2 - mGuiFont->getHeight() / 2,
            gcn::Graphics::CENTER);
    }
}

'''
if 'void Gui::drawVirtualKeyboard(Graphics *graphics)' not in c:
    marker = 'void Gui::keyReleased(gcn::KeyEvent &/*event*/)\n'
    count = c.count(marker)
    if count != 1:
        raise SystemExit(f"ERRO: marcador para implementacao do teclado encontrado {count} vezes")
    c = c.replace(marker, impl + marker, 1)
if '#include <cstring>' not in c:
    count = c.count('#include <algorithm>')
    if count != 1:
        raise SystemExit(f"ERRO: marcador para cstring encontrado {count} vezes")
    c = c.replace('#include <algorithm>', '#include <algorithm>\n#include <cstring>', 1)
write(GUI_CPP, c)
print("OK: patch de mouse e teclado aplicado.")
PYPATCH

python3 - "$GUI_H" "$GUI_CPP" "$TEXTFIELD_H" "$TEXTFIELD_CPP" <<'PYTEST'
import sys
for path in sys.argv[1:]:
    if not open(path, encoding="utf-8").read().strip():
        raise SystemExit("ERRO: arquivo vazio: " + path)
print("OK: arquivos C++ modificados validos como texto.")
PYTEST

echo "=== Verificando alteracoes do mouse/teclado ==="
grep -n "mSoftwareCursorVisible\|mVirtualKeyboardVisible\|drawVirtualKeyboard\|virtualEnter" \
    "$GUI_H" "$GUI_CPP" "$TEXTFIELD_H" "$TEXTFIELD_CPP"



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

    echo "port/Mana.sh nao encontrado. Criando launcher funcional..."

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
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$GAMEROOT/libs.${DEVICE_ARCH}:${LD_LIBRARY_PATH:-}"

cd "$GAMEROOT" || exit 1

GPTOPID=""
if [ -n "${GPTOKEYB:-}" ]; then
    $GPTOKEYB "mana.aarch64" -c "./mana.gptk" &
    GPTOPID=$!
fi

pm_platform_helper "$GAME"

"$GAME" --data "$GAMEDATA" --localdata-dir "$CONFDIR"
RET=$?

if [ -n "$GPTOPID" ]; then
    kill "$GPTOPID" 2>/dev/null || true
fi

pm_finish
exit $RET
EOF

    chmod +x "$PORT/Mana.sh"
    echo "OK: launcher funcional criado."

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

if [ -d "$INSTALL/share/mana" ]; then
    echo "OK: usando dados instalados pelo CMake: $INSTALL/share/mana"
    cp -a "$INSTALL/share/mana" "$PACKAGE/mana/data"
elif [ -d "$PORT/mana/data" ]; then
    echo "OK: usando dados de port/mana/data"
    cp -a "$PORT/mana/data" "$PACKAGE/mana/"
else
    echo "ERRO: dados do Mana nao encontrados nem no install/share/mana nem em port/mana/data"
    exit 1
fi

# O cursor nao depende de nenhum arquivo enviado pelo usuario.
# Geramos um pequeno cursor PNG durante o build e o colocamos nos dados do Mana.
# Isso elimina a necessidade de manter source/mouse.png no repositorio.
CURSOR_DIR="$PACKAGE/mana/data/graphics/gui"
CURSOR_PNG="$CURSOR_DIR/mouse.png"
mkdir -p "$CURSOR_DIR"

python3 - "$CURSOR_PNG" <<'PYCURSOR'
import base64
import sys

# Cursor branco com contorno preto, 40x40, gerado para o port.
DATA = "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAA6UlEQVR4nO3Yuw6DMBBE0eso///LmwIsAbEBL/twwVShQBzNSDgC3thFsgGtfA7XwmTQHVBEEBGYCHlsEGAqZBMIO2QqtAuEOSY/BdZktnkLCHlt3gbWRCOHgRA7uQoIcZOrgTXeyMdA8J3cBAh+k5sBa6zbNAeCbZsuwBoLpCsQnk/+1T64lKK5TYChG9XANSrlSG5N3Gor6ky+BCqnNMspcMWV5WdOi13gBpeaJrCDa7bonT/gaHOh/2ZmmXWbY4NXuPCZt0D1kz1ndj+Ln0YDDH0nmjWYfeK0IrLUlv79ppdpYW/eWOYHNO94/q+Pq08AAAAASUVORK5CYII="
with open(sys.argv[1], "wb") as f:
    f.write(base64.b64decode(DATA))
PYCURSOR

if [ ! -s "$CURSOR_PNG" ]; then
    echo "ERRO: nao foi possivel gerar o cursor virtual."
    exit 1
fi

echo "OK: cursor virtual gerado em $CURSOR_PNG"
echo "=== Copiando licencas ==="

if [ -d "$PORT/mana/licenses" ]; then

    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"

fi

echo

echo "=== Instalando configuracao GPTK ==="

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

if [ ! -s "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao foi criado"
    exit 1
fi

echo "OK: mana.gptk criado."

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
