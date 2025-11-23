#!/bin/bash

# Use Cadius to create a disk image for distribution
# https://github.com/mach-kernel/cadius

set -e

PACKDIR=$(mktemp -d)
IMGFILE="out/tts.po"
VOLNAME="TTS"

rm -f "$IMGFILE"
cadius CREATEVOLUME "$IMGFILE" "$VOLNAME" 140KB --quiet > /dev/null

add_file () {
    cp "$1" "$PACKDIR/$2"
    cadius ADDFILE "$IMGFILE" "/$VOLNAME" "$PACKDIR/$2" --quiet > /dev/null
}

add_file "out/chip8.system.SYS" "chip8.system#FF0000"
add_file "out/chip8.system.SYS" "basis.system#FF0000"
add_file "res/SAM.BIN"        "SAM#064000"

rm -rf "$PACKDIR"

cadius CATALOG "$IMGFILE"
