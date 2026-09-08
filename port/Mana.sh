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
echo " Mouse + Teclado"
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

#
# Bibliotecas locais do port.
#
if [ -d "$GAMEDIR/mana/libs.aarch64" ]; then
    export LD_LIBRARY_PATH="$GAMEDIR/mana/libs.aarch64:${LD_LIBRARY_PATH:-}"
fi

#
# Configuracao local do Mana.
#
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"

#
# Controlador detectado pelo PortMaster.
#
if [ -n "${sdl_controllerconfig:-}" ]; then
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
fi

#
# Entra na pasta que contem o executavel.
#
cd "$GAMEDIR/mana" || exit 1

echo
echo "========================================"
echo " Configuracao GPTOKEYB"
echo "========================================"

GPTK_CONFIG="./mana.gptk"

if [ ! -f "$GPTK_CONFIG" ]; then
    echo "ERRO: mana.gptk nao encontrado:"
    echo "$GAMEDIR/mana/mana.gptk"
    exit 1
fi

echo "GPTK=$GPTK_CONFIG"

#
# Inicia GPTOKEYB2 quando disponivel.
#
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
    echo "AVISO: GPTOKEYB/GPTOKEYB2 nao encontrado."

fi

#
# Garante que o GPTK seja encerrado quando o Mana sair.
#
cleanup()
{
    if [ -n "${GPTOPID:-}" ]; then
        kill "$GPTOPID" 2>/dev/null || true
        wait "$GPTOPID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

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
echo "Cursor:"
echo "Software cursor do Mana"

echo
echo "Mouse:"
echo "Analógico direito = movimento"
echo "R3 = clique esquerdo"
echo "L3 = clique direito"

echo
echo "Teclado:"
echo "GPTOKEYB ativo"

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
