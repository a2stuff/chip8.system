#!/bin/bash

# Use Cadius to create a disk image for distribution
# https://github.com/mach-kernel/cadius

set -e

IMGFILE="out/chip8.2mg"
VOLNAME="CHIP8"

# cecho - "color echo"
# ex: cecho red ...
# ex: cecho green ...
# ex: cecho yellow ...
function cecho {
    case $1 in
        red)    tput setaf 1 ; shift ;;
        green)  tput setaf 2 ; shift ;;
        yellow) tput setaf 3 ; shift ;;
    esac
    echo -e "$@"
    tput sgr0
}

# suppress - hide command output unless it failed; and if so show in red
# ex: suppress command_that_might_fail args ...
function suppress {
    set +e
    local result
    result=$("$@")
    if [ $? -ne 0 ]; then
        cecho red "$result" >&2
        exit 1
    fi
    set -e
}

rm -f "$IMGFILE"
suppress cadius CREATEVOLUME "$IMGFILE" "$VOLNAME" 800KB --quiet --no-case-bits

PACKDIR=$(mktemp -d)
trap "rm -r $PACKDIR" EXIT

add_file () {
  src="$1"
  dir=$(dirname "$2")
  path="/$VOLNAME"
  if [ "$dir" != "." ]; then
    path="$path/$dir"
  fi
  filename=$(basename "$2")

  cp "$src" "$PACKDIR/$filename"
  suppress cadius ADDFILE "$IMGFILE" "$path" "$PACKDIR/$filename" --quiet --no-case-bits
}

add_file "res/PRODOS.SYS" "ProDOS#FF0000"
add_file "out/chip8.system.SYS" "CHIP8.system#FF0000"
add_file "out/chip8.system.SYS" "BASIS.system#FF0000"
add_file "res/ibm_logo.ch8" "IBM.LOGO.CH8#060000"
add_file "res/apple_logo.ch8" "APPLE.LOGO.CH8#060000"

# Octojam titles from https://johnearnest.github.io/chip8Archive/
for i in $(seq 1 10); do
  add_file "res/octojam${i}title.ch8" "DEMOS/OCTOJAM${i}.CH8#5DC807"
done

# Games from https://www.zophar.net/pdroms/chip8/chip-8-games-pack.html
add_file "res/15PUZZLE.ch8" "GAMES/PUZZLE15.CH8#060000"
add_file "res/BLINKY.ch8" "GAMES/BLINKY.CH8#5DC81D"
add_file "res/BLITZ.ch8" "GAMES/BLITZ.CH8#060000"
add_file "res/BRIX.ch8" "GAMES/BRIX.CH8#060000"
add_file "res/CONNECT4.ch8" "GAMES/CONNECT4.CH8#060000"
add_file "res/GUESS.ch8" "GAMES/GUESS.CH8#060000"
add_file "res/HIDDEN.ch8" "GAMES/HIDDEN.CH8#060000"
add_file "res/INVADERS.ch8" "GAMES/INVADERS.CH8#060000"
add_file "res/KALEID.ch8" "GAMES/KALEID.CH8#060000"
add_file "res/MAZE.ch8" "GAMES/MAZE.CH8#060000"
add_file "res/MERLIN.ch8" "GAMES/MERLIN.CH8#060000"
add_file "res/MISSILE.ch8" "GAMES/MISSILE.CH8#060000"
add_file "res/PONG.ch8" "GAMES/PONG.CH8#060000"
add_file "res/PONG2.ch8" "GAMES/PONG2.CH8#060000"
add_file "res/PUZZLE.ch8" "GAMES/PUZZLE.CH8#060000"
add_file "res/SYZYGY.ch8" "GAMES/SYZYGY.CH8#060000"
add_file "res/TANK.ch8" "GAMES/TANK.CH8#060000"
add_file "res/TETRIS.ch8" "GAMES/TETRIS.CH8#060000"
add_file "res/TICTAC.ch8" "GAMES/TICTAC.CH8#060000"
add_file "res/UFO.ch8" "GAMES/UFO.CH8#060000"
add_file "res/VBRIX.ch8" "GAMES/VBRIX.CH8#060000"
add_file "res/VERS.ch8" "GAMES/VERS.CH8#060000"
add_file "res/WIPEOFF.ch8" "GAMES/WIPEOFF.CH8#060000"

cadius CATALOG "$IMGFILE" | cut -c1-$(tput cols)
