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
trap "rm -rf $PACKDIR" EXIT

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

cadius CATALOG "$IMGFILE" | cut -c1-$(tput cols)
