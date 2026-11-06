#!/bin/sh
# Takes the README screenshots: opens Lax's demo workspace once per scene and captures only
# Lax's window, then lays them out in docs/screenshots/collage.png. Lax opens and closes a
# dozen times while this runs.
set -e
cd "$(dirname "$0")/.."
scripts/bundle.sh > /dev/null
out=docs/screenshots
mkdir -p "$out"

# shoot <file> <"smallest" for Settings, "" for the main window> <launch arguments…>
shoot() {
    name=$1 which=$2
    shift 2
    pkill -x Lax 2> /dev/null || true
    sleep 1
    open -n build/Lax.app --args -demo -ApplePersistenceIgnoreState YES "$@"
    sleep 8
    window=$(swift scripts/lax-window.swift $which)
    screencapture -o -x -l "$window" "$out/$name.png"
    echo "Captured $name"
}

shoot channel "" -demo-scene channel
shoot thread "" -demo-scene thread
shoot direct-messages "" -demo-scene direct-messages
shoot threads "" -demo-scene threads
shoot open-quickly "" -demo-scene open-quickly
shoot composer "" -demo-scene composer
shoot search "" -demo-scene search
shoot bot "" -demo-scene bot
shoot video "" -demo-scene video
shoot emoji-picker "" -demo-scene emoji-picker
shoot settings smallest -demo-scene settings
shoot light "" -demo-scene thread -demo-light
pkill -x Lax 2> /dev/null || true

swift scripts/collage.swift "$out/collage.png" \
    channel thread direct-messages threads open-quickly composer search bot video emoji-picker settings light
echo "Laid out $out/collage.png"
