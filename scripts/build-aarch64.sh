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


# ----------------------------------------------------------------------------
# GUI: cursor software + teclado virtual R36S
# ----------------------------------------------------------------------------
GUI_H="$SRC_DIR/src/gui/gui.h"
GUI_CPP="$SRC_DIR/src/gui/gui.cpp"
TEXTFIELD_H="$SRC_DIR/src/gui/widgets/textfield.h"
TEXTFIELD_CPP="$SRC_DIR/src/gui/widgets/textfield.cpp"

if [ ! -f "$GUI_H" ] || [ ! -f "$GUI_CPP" ] || [ ! -f "$TEXTFIELD_H" ] || [ ! -f "$TEXTFIELD_CPP" ]; then
    echo "ERRO: arquivos GUI/TextField necessarios nao encontrados."
    exit 1
fi

python3 - "$GUI_H" "$GUI_CPP" "$TEXTFIELD_H" "$TEXTFIELD_CPP" <<'PYCODE'
from pathlib import Path
import re, shutil, tempfile, sys
h=Path(sys.argv[1]); cpp=Path(sys.argv[2]); th=Path(sys.argv[3]); tc=Path(sys.argv[4])

# GUI header
s=h.read_text()
if 'bool mVirtualKeyboardVisible = false;' not in s:
    marker='        ResourceRef<Image> mSoftwareCursor;\n'
    if marker not in s: raise SystemExit('missing cursor member')
    s=s.replace(marker, marker+'''        bool mSoftwareCursorVisible = true;\n        bool mVirtualKeyboardVisible = false;\n        int mVirtualKeyboardRow = 0;\n        int mVirtualKeyboardCol = 0;\n        void drawVirtualKeyboard(Graphics *graphics);\n        bool handleVirtualKeyboardKey(int key);\n        void openVirtualKeyboard();\n        void closeVirtualKeyboard(bool confirm);\n        void insertVirtualKeyboardText(const std::string &text);\n''',1)
# Remove duplicate visibility if already inserted by earlier source
s=s.replace('        bool mSoftwareCursorVisible = true;\n        bool mSoftwareCursorVisible = true;\n','        bool mSoftwareCursorVisible = true;\n')
# ensure methods before private? declarations inserted in private area okay.
h.write_text(s)

# Textfield public helper
s=th.read_text()
if 'void virtualEnter();' not in s:
    marker='        void textInput(const TextInput &textInput);\n'
    s=s.replace(marker, marker+'        void virtualEnter();\n',1)
th.write_text(s)

s=tc.read_text()
if 'void TextField::virtualEnter()' not in s:
    marker='void TextField::textInput(const TextInput &textInput)\n'
    idx=s.find(marker)
    if idx<0: raise SystemExit('textfield textInput missing')
    impl='''void TextField::virtualEnter()\n{\n    if (mHistory)\n    {\n        if (!getText().empty() && (mHistory->empty() ||\n            !mHistory->matchesLastEntry(getText())))\n        {\n            mHistory->addEntry(getText());\n        }\n        mHistory->toEnd();\n    }\n\n    distributeActionEvent();\n}\n\n'''
    s=s[:idx]+impl+s[idx:]
tc.write_text(s)

# GUI cpp: remove old cursor block and old draw; then inject methods and key handler.
s=cpp.read_text()
# Remove partial constructor cursor block if present
s=re.sub(r'\n    // R36S/PortMaster software cursor\..*?\n    SDL_ShowCursor\(SDL_DISABLE\);\n', '\n', s, count=1, flags=re.S)
# Add robust cursor init after setUseCustomCursor
s=s.replace('    setUseCustomCursor(config.customCursor);\n', '''    setUseCustomCursor(config.customCursor);\n\n    // PortMaster/R36S software cursor.\n    mSoftwareCursor = ResourceManager::getInstance()->getImage(\n        "graphics/gui/mouse.png"\n    );\n    mMouseX = graphics->getWidth() / 2;\n    mMouseY = graphics->getHeight() / 2;\n    mSoftwareCursorVisible = true;\n    SDL_ShowCursor(SDL_DISABLE);\n''',1)
# draw replacement
pat=re.compile(r'void Gui::draw\(\)\n\{.*?\n\}\n\nvoid Gui::event',re.S)
rep='''void Gui::draw()\n{\n    gcn::Gui::draw();\n\n    auto *graphics = static_cast<Graphics*>(mGraphics);\n    if (!graphics)\n        return;\n\n    if (mActiveDrag)\n    {\n        graphics->pushClipArea(gcn::Rectangle(0, 0,\n                                              graphics->getWidth(),\n                                              graphics->getHeight()));\n        mActiveDrag->draw(graphics, mMouseX, mMouseY);\n        graphics->popClipArea();\n    }\n\n    if (mVirtualKeyboardVisible)\n        drawVirtualKeyboard(graphics);\n\n    if (mSoftwareCursorVisible && mSoftwareCursor)\n    {\n        graphics->pushClipArea(gcn::Rectangle(0, 0,\n                                              graphics->getWidth(),\n                                              graphics->getHeight()));\n        graphics->drawImage(\n            mSoftwareCursor.get(),\n            0,\n            0,\n            mMouseX - 15,\n            mMouseY - 17,\n            40,\n            40\n        );\n        graphics->popClipArea();\n    }\n}\n\nvoid Gui::event'''
s,n=pat.subn(rep,s,count=1)
if n!=1: raise SystemExit('draw replacement failed')
# keyPressed replacement
pat=re.compile(r'void Gui::keyPressed\(gcn::KeyEvent &event\)\n\{.*?\n\}\n\nvoid Gui::keyReleased',re.S)
rep='''void Gui::keyPressed(gcn::KeyEvent &event)\n{\n    const int key = event.getKey().getValue();\n\n    if (!mVirtualKeyboardVisible && key == Key::ENTER)\n    {\n        const Uint8 *state = SDL_GetKeyboardState(nullptr);\n        if (state && state[SDL_SCANCODE_DOWN])\n        {\n            openVirtualKeyboard();\n            event.consume();\n            return;\n        }\n    }\n\n    if (mVirtualKeyboardVisible)\n    {\n        if (handleVirtualKeyboardKey(key))\n        {\n            event.consume();\n            return;\n        }\n    }\n\n    if (key == Key::F12)\n    {\n        mSoftwareCursorVisible = !mSoftwareCursorVisible;\n        event.consume();\n        return;\n    }\n\n    if (mActiveDrag && key == Key::ESCAPE)\n    {\n        cancelActiveDrag();\n        event.consume();\n    }\n}\n\nvoid Gui::keyReleased'''
s,n=pat.subn(rep,s,count=1)
if n!=1: raise SystemExit('key replace failed')
# Add helper methods before keyPressed
marker='void Gui::keyPressed(gcn::KeyEvent &event)\n'
helpers=r'''void Gui::openVirtualKeyboard()
{
    if (mVirtualKeyboardVisible)
        return;

    auto focused = mFocusHandler->getFocused();
    if (!dynamic_cast<TextField*>(focused))
        return;

    mVirtualKeyboardVisible = true;
    mVirtualKeyboardRow = 1;
    mVirtualKeyboardCol = 0;
}

void Gui::closeVirtualKeyboard(bool confirm)
{
    auto focused = mFocusHandler->getFocused();
    if (confirm)
    {
        if (auto textField = dynamic_cast<TextField*>(focused))
            textField->virtualEnter();
    }

    mVirtualKeyboardVisible = false;
    mVirtualKeyboardRow = 0;
    mVirtualKeyboardCol = 0;
}

void Gui::insertVirtualKeyboardText(const std::string &text)
{
    auto focused = mFocusHandler->getFocused();
    auto textField = dynamic_cast<TextField*>(focused);
    if (!textField || text.empty())
        return;

    const std::string current = textField->getText();
    const unsigned caret = textField->getCaretPosition();
    const unsigned safeCaret = std::min<unsigned>(caret, current.size());

    std::string updated = current;
    updated.insert(safeCaret, text);
    textField->setText(updated);
    textField->setCaretPosition(safeCaret + text.size());
}

bool Gui::handleVirtualKeyboardKey(int key)
{
    if (!mVirtualKeyboardVisible)
        return false;

    // SELECT/F12 cancels the keyboard while it is open.
    if (key == Key::F12 || key == Key::ESCAPE)
    {
        closeVirtualKeyboard(false);
        return true;
    }

    static const std::vector<std::vector<std::string>> rows = {
        {"1","2","3","4","5","6","7","8","9","0"},
        {"Q","W","E","R","T","Y","U","I","O","P"},
        {"A","S","D","F","G","H","J","K","L"},
        {"Z","X","C","V","B","N","M"},
        {".",",","!","?","-","_","/","@","#","$"},
        {":",";","'","\"","(",")","[","]","+","="},
        {"SPACE","BKSP","ENTER","CANCEL"}
    };

    auto move = [&](int dr, int dc) {
        int row = mVirtualKeyboardRow + dr;
        if (row < 0) row = static_cast<int>(rows.size()) - 1;
        if (row >= static_cast<int>(rows.size())) row = 0;

        int col = mVirtualKeyboardCol + dc;
        const int count = static_cast<int>(rows[row].size());
        if (col < 0) col = count - 1;
        if (col >= count) col = 0;

        mVirtualKeyboardRow = row;
        mVirtualKeyboardCol = std::min(col, count - 1);
    };

    switch (key)
    {
        case Key::UP:
            move(-1, 0);
            return true;
        case Key::DOWN:
            move(1, 0);
            return true;
        case Key::LEFT:
            move(0, -1);
            return true;
        case Key::RIGHT:
            move(0, 1);
            return true;
        case Key::SPACE:
        {
            const std::string &value = rows[mVirtualKeyboardRow][mVirtualKeyboardCol];
            if (value == "SPACE")
                insertVirtualKeyboardText(" ");
            else if (value == "BKSP")
            {
                auto focused = mFocusHandler->getFocused();
                if (auto textField = dynamic_cast<TextField*>(focused))
                {
                    const std::string current = textField->getText();
                    const unsigned caret = textField->getCaretPosition();
                    if (caret > 0 && caret <= current.size())
                    {
                        std::string updated = current;
                        updated.erase(caret - 1, 1);
                        textField->setText(updated);
                        textField->setCaretPosition(caret - 1);
                    }
                }
            }
            else if (value == "ENTER")
                closeVirtualKeyboard(true);
            else if (value == "CANCEL")
                closeVirtualKeyboard(false);
            else
                insertVirtualKeyboardText(value);
            return true;
        }
        case Key::ENTER:
        {
            const std::string &value = rows[mVirtualKeyboardRow][mVirtualKeyboardCol];
            if (value == "ENTER")
                closeVirtualKeyboard(true);
            else
                insertVirtualKeyboardText(value);
            return true;
        }
        default:
            return false;
    }
}

void Gui::drawVirtualKeyboard(Graphics *graphics)
{
    static const std::vector<std::vector<std::string>> rows = {
        {"1","2","3","4","5","6","7","8","9","0"},
        {"Q","W","E","R","T","Y","U","I","O","P"},
        {"A","S","D","F","G","H","J","K","L"},
        {"Z","X","C","V","B","N","M"},
        {".",",","!","?","-","_","/","@","#","$"},
        {":",";","'","\"","(",")","[","]","+","="},
        {"SPACE","BKSP","ENTER","CANCEL"}
    };

    const int screenW = graphics->getWidth();
    const int screenH = graphics->getHeight();
    const int margin = 10;
    const int gap = 3;
    const int keyW = std::max(36, (screenW - margin * 2 - gap * 9) / 10);
    const int keyH = 32;
    const int rowGap = 4;
    const int keyboardH = static_cast<int>(rows.size()) * keyH +
                          (static_cast<int>(rows.size()) - 1) * rowGap + 34;
    const int y0 = std::max(5, screenH - keyboardH - 8);

    graphics->setColor(gcn::Color(0, 0, 0));
    graphics->fillRectangle(gcn::Rectangle(0, y0 - 8, screenW, keyboardH + 16));

    graphics->setColor(Theme::getThemeColor(Theme::TEXT));
    graphics->setFont(mGuiFont);
    graphics->drawText("Teclado virtual - START confirma / SELECT cancela",
                       screenW / 2, y0,
                       gcn::Graphics::CENTER, mGuiFont);

    for (size_t r = 0; r < rows.size(); ++r)
    {
        const int count = static_cast<int>(rows[r].size());
        const int rowW = count * keyW + (count - 1) * gap;
        const int x0 = (screenW - rowW) / 2;
        const int y = y0 + 28 + static_cast<int>(r) * (keyH + rowGap);

        for (int c = 0; c < count; ++c)
        {
            const int x = x0 + c * (keyW + gap);
            const bool selected = static_cast<int>(r) == mVirtualKeyboardRow &&
                                  c == mVirtualKeyboardCol;

            graphics->setColor(selected
                ? Theme::getThemeColor(Theme::HIGHLIGHT)
                : gcn::Color(55, 55, 55));
            graphics->fillRectangle(gcn::Rectangle(x, y, keyW, keyH));

            graphics->setColor(Theme::getThemeColor(Theme::TEXT));
            graphics->drawText(rows[r][c], x + keyW / 2, y + keyH / 2 - 8,
                               gcn::Graphics::CENTER, mGuiFont);
        }
    }
}

'''
s=s.replace(marker,helpers+marker,1)
# remove hardware cursor enable if any
s=s.replace('    SDL_ShowCursor(SDL_ENABLE);\n','')
cpp.write_text(s)
print('PATCH GUI/TECLADO OK')

PYCODE

if grep -nE 'gcn::KeyEvent[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$GUI_CPP" "$TEXTFIELD_CPP"; then
    echo "ERRO: construcao manual de gcn::KeyEvent detectada."
    exit 1
fi

echo "OK: cursor e teclado virtual preparados."
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
    echo "Files installed under $GAMEDIR:"
    find "$GAMEDIR" -maxdepth 4 -type f -print 2>/dev/null || true
    pm_finish
    exit 1
fi

if [ ! -d "$GAMEDATA" ]; then
    echo "ERROR: Mana data directory not found: $GAMEDATA"
    echo "Directories installed under $GAMEDIR:"
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
if [ -n "$GPTOKEYB" ]; then
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
echo "OK: launcher funcional instalado."

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

echo "=== Verificando cursor do Mana ==="

if [ ! -f "$PACKAGE/mana/data/graphics/gui/mouse.png" ]; then
    echo "ERRO: mouse.png nao encontrado no pacote final."
    echo "Verifique se port/mana/data foi colocado no repositorio."
    exit 1
fi

echo "OK: mouse.png presente."
echo

echo "=== Copiando licencas ==="

if [ -d "$PORT/mana/licenses" ]; then

    cp -a "$PORT/mana/licenses" "$PACKAGE/mana/"

fi

echo

echo "=== Copiando configuracao GPTK ==="

if [ -f "$PORT/mana/mana.gptk" ]; then
    cp "$PORT/mana/mana.gptk" "$PACKAGE/mana/mana.gptk"
elif [ -f "$PORT/mana.gptk" ]; then
    cp "$PORT/mana.gptk" "$PACKAGE/mana/mana.gptk"
else
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
fi

chmod 644 "$PACKAGE/mana/mana.gptk"

if [ ! -f "$PACKAGE/mana/mana.gptk" ]; then
    echo "ERRO: mana.gptk nao foi colocado no pacote final"
    exit 1
fi

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
