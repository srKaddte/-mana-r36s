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

echo
echo "GAMEDIR=$GAMEDIR"
echo "CONFDIR=$CONFDIR"

GAME="$GAMEDIR/mana/mana.aarch64"

if [ ! -f "$GAME" ]; then
    echo
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

# Ativa o teclado virtual interativo.
#
# START + D-PAD DOWN = abre o teclado
#
# D-PAD UP/DOWN    = muda a letra
# D-PAD RIGHT      = proxima posicao
# D-PAD LEFT       = apaga e volta
# L1               = pula letras para tras
# R1               = pula letras para frente
# A                = ENTER
# START            = confirma
# SELECT           = cancela
#
# ADDEXTRASYMBOLS permite o conjunto completo de simbolos.
export TEXTINPUTINTERACTIVE="Y"
export TEXTINPUTADDEXTRASYMBOLS="Y"

# Mantem as letras normais com capitalizacao automatica.
unset TEXTINPUTNOAUTOCAPITALS 2>/dev/null || true

echo
echo "Teclado virtual GPTOKEYB: ATIVADO"
echo "Abrir: START + D-PAD DOWN"
echo "Simbolos extras: ATIVADOS"

# ============================================================
# GPTOKEYB
# ============================================================

cd "$GAMEDIR/mana" || exit 1

GPTK_CONFIG="./mana.gptk"

if [ ! -f "$GPTK_CONFIG" ]; then
    echo
    echo "ERRO: mana.gptk nao encontrado:"
    echo "$GAMEDIR/mana/mana.gptk"
    exit 1
fi

echo
echo "========================================"
echo " Configuracao GPTOKEYB"
echo "========================================"

echo "GPTK=$GPTK_CONFIG"

GPTOPID=""

if [ -n "${GPTOKEYB2:-}" ]; then

    echo
    echo "GPTOKEYB2 encontrado:"
    echo "$GPTOKEYB2"

    "$GPTOKEYB2" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

    echo "GPTOKEYB2 PID=$GPTOPID"

elif [ -n "${GPTOKEYB:-}" ]; then

    echo
    echo "GPTOKEYB encontrado:"
    echo "$GPTOKEYB"

    "$GPTOKEYB" \
        "mana.aarch64" \
        -c "$GPTK_CONFIG" &

    GPTOPID=$!

    echo "GPTOKEYB PID=$GPTOPID"

else

    echo
    echo "ERRO: GPTOKEYB/GPTOKEYB2 nao encontrado."
    echo "O teclado e os controles nao poderao ser usados."
    exit 1

fi

# ============================================================
# LIMPEZA
# ============================================================

cleanup()
{
    echo
    echo "Encerrando GPTOKEYB..."

    if [ -n "${GPTOPID:-}" ]; then
        kill "$GPTOPID" 2>/dev/null || true
        wait "$GPTOPID" 2>/dev/null || true
    fi

    echo "GPTOKEYB encerrado."
}

trap cleanup EXIT INT TERM

# ============================================================
# INFORMACOES
# ============================================================

echo
echo "========================================"
echo " Controles"
echo "========================================"

echo
echo "Mouse:"
echo "  Analogico direito = movimento"
echo "  R3 = clique esquerdo"
echo "  L3 = clique direito"

echo
echo "Teclado:"
echo "  START + DOWN = teclado virtual"
echo "  A = Enter"
echo "  START = confirmar"
echo "  SELECT = cancelar"

echo
echo "Cursor:"
echo "  SELECT = F12 / mostrar ou ocultar cursor"

echo
echo "Controles normais:"
echo "  A = Space"
echo "  B = Esc"
echo "  X = Z"
echo "  Y = X"
echo "  L1 = Shift"
echo "  R1 = Ctrl"
echo "  L2 = Home"
echo "  R2 = End"
echo "  D-Pad = Setas"

echo
echo "========================================"
echo " Iniciando Mana"
echo "========================================"

echo
echo "Executavel:"
echo "$GAME"

echo
echo "Dados:"
echo "$GAMEDIR/mana/data"

echo
echo "Configuracao:"
echo "$GAMEDIR/mana/mana.gptk"

echo

"$GAME" \
    --fullscreen \
    --data "$GAMEDIR/mana/data" \
    --localdata-dir "$CONFDIR"

RET=$?

echo
echo "========================================"
echo " Mana terminou"
echo " Codigo: $RET"
echo "========================================"

exit "$RET"
