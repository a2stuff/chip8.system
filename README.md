# A CHIP-8 interpreter for Apple II / ProDOS-8

CHIP-8 is a fantasy video game console definition from the 1970s by Joseph Weisbecker.

References:

* https://en.wikipedia.org/wiki/CHIP-8
* https://github.com/mattmikolay/chip-8/
* https://tobiasvl.github.io/blog/write-a-chip-8-emulator/
* https://github.com/Timendus/chip8-test-suite

This version runs on Apple II models that support Double Low Resolution graphics (DGR):

* Apple IIe (original)
* Apple IIe Enhanced
* Apple IIc
* Apple IIc Plus
* Apple IIgs
* Macintosh IIe Option Card (_untested_)
* Clones such as the Laser 128, Franklin ACE 2200, Franklin ACE 500
* Emulators such as MAME, Virtual ][, AppleWin, etc.

It runs in ProDOS-8 and follows the "interpreter protocol" so that launchers such as Bitsy Bye and Apple II DeskTop can automatically launch CHIP-8 programs with it, when appropriately configured.

# For Users

If distributed on a disk with [ProDOS-8 2.4](https://prodos8.com/) and the file is named `BASIS.SYSTEM` then files selected in [Bitsy Bye](https://prodos8.com/bitsy-bye/) will launch with the interpreter automatically.

* Press <kbd>Esc</kbd> at any time to return to ProDOS.
* Press <kbd>9</kbd> and <kbd>0</kbd> to change border colors.
* Press <kbd>[</kbd> and <kbd>]</kbd> to change background colors.
* Press <kbd>,</kbd> and <kbd>.</kbd> to change foreground colors.

## Keypad

The CHIP-8 assumes a 16-key keypad:
| | | | |
|-|-|-|-|
|<kbd>1</kbd>|<kbd>2</kbd>|<kbd>3</kbd>|<kbd>C</kbd>|
|<kbd>4</kbd>|<kbd>5</kbd>|<kbd>6</kbd>|<kbd>D</kbd>|
|<kbd>7</kbd>|<kbd>8</kbd>|<kbd>9</kbd>|<kbd>E</kbd>|
|<kbd>A</kbd>|<kbd>0</kbd>|<kbd>B</kbd>|<kbd>F</kbd>|

Use these keys on a QWERTY keyboard instead:

| | | | |
|-|-|-|-|
|<kbd>1</kbd>|<kbd>2</kbd>|<kbd>3</kbd>|<kbd>4</kbd>|
|<kbd>Q</kbd>|<kbd>W</kbd>|<kbd>E</kbd>|<kbd>R</kbd>|
|<kbd>A</kbd>|<kbd>S</kbd>|<kbd>D</kbd>|<kbd>F</kbd>|
|<kbd>Z</kbd>|<kbd>X</kbd>|<kbd>C</kbd>|<kbd>V</kbd>|

## CHIP-8 Programs

* https://johnearnest.github.io/chip8Archive/?sort=platform#chip8

Note that only CHIP-8 ("chip8") games are supported, not SUPER-CHIP ("schip") or XO-CHIP ("xochip").

CHIP-8 programs ("ROMs") can be copied to a ProDOS disk and launched using Bitsy Bye, as long as `CHIP8.SYSTEM` has been placed on the disk and renamed `BASIS.SYSTEM`.

Some programs require different compatibility settings. This can be enabled by changing the ProDOS file type of the program to `$5D` (`ENT` or Entertainment), and setting the aux type to `$C800` (for "CHIP-8") with the lower byte used as "quirks" flags as follows:

* Bit 0 = "VF Reset"                    (default: on)
* Bit 1 = "Memory"                      (default: on)
* Bit 2 = "Display Wait"                (default: on)
* Bit 3 = "Clipping"                    (default: on)
* Bit 4 = "Shifting"                    (default: off)

Otherwise, all quirks are set to the defaults. This is equivalent to file type `$5D` and aux type `$C80F`.

For detailed "quirks" definitions, see https://github.com/Timendus/chip8-test-suite?tab=readme-ov-file#the-test

# For Developers

## Building

Fetch, build, and install [cc65](http://cc65.github.io/cc65/) (in a separate directory):

```
git clone https://github.com/cc65/cc65
make -C cc65 && make -C cc65 avail
```

Then run: `make`

## Packaging

To produce a ProDOS disk image, first install and build [Cadius](https://github.com/mach-kernel/cadius) (in a separate directory):

```
git clone https://github.com/mach-kernel/cadius
make -C cadius && make -C cadius install
```

Then run: `make package`
