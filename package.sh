#!/bin/bash

# Use Cadius to create a disk image for distribution
# https://github.com/mach-kernel/cadius

set -e

PACKDIR=$(mktemp -d)
IMGFILE="out/chip8.po"
VOLNAME="CHIP8"

rm -f "$IMGFILE"
cadius CREATEVOLUME "$IMGFILE" "$VOLNAME" 140KB --quiet --no-case-bits > /dev/null

add_file () {
    cp "$1" "$PACKDIR/$2"
    cadius ADDFILE "$IMGFILE" "/$VOLNAME" "$PACKDIR/$2" --quiet --no-case-bits > /dev/null
}

add_file "res/PRODOS.SYS" "ProDOS#FF0000"
add_file "out/chip8.system.SYS" "CHIP8.system#FF0000"
add_file "out/chip8.system.SYS" "BASIS.system#FF0000"
add_file "res/ibm_logo.ch8" "IBM.LOGO.CH8#060000"

# From https://github.com/Timendus/chip8-test-suite
# Not included in package, but good to try
#add_file "res/1-chip8-logo.ch8" "CHIP8.LOGO.CH8#060000"
#add_file "res/2-ibm-logo.ch8" "IBM.LOGO2.CH8#060000"
#add_file "res/3-corax+.ch8" "CORAX.CH8#060000"
#add_file "res/4-flags.ch8" "FLAGS.CH8#060000"
#add_file "res/5-quirks.ch8" "QUIRKS.CH8#060000"
#add_file "res/6-keypad.ch8" "KEYPAD.CH8#060000"
#add_file "res/7-beep.ch8" "BEEP.CH8#060000"
#add_file "res/8-scrolling.ch8" "SCROLLING.CH8#060000"

# Fun stuff from https://johnearnest.github.io/chip8Archive/
#add_file "res/snek.ch8" "SNEK.CH8#060000"
#add_file "res/octojam1title.ch8" "OCTOJAM1.CH8#060000"
#add_file "res/octojam2title.ch8" "OCTOJAM2.CH8#060000"
#add_file "res/octojam6title.ch8" "OCTOJAM6.CH8#060000"

rm -rf "$PACKDIR"

cadius CATALOG "$IMGFILE"
