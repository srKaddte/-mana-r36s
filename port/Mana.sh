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

# Support both the normal PortMaster layout and a flattened install.
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
