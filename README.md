# A CHIP-8 interpreter for Apple II / ProDOS-8

[CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) is a fantasy video game console definition from the 1970s by Joseph Weisbecker.

This version runs on Apple II models that support Double Low Resolution graphics (DGR):

* Apple IIe (original)
* Apple IIe Enhanced
* Apple IIc
* Apple IIc Plus
* Apple IIgs
* Macintosh IIe Option Card (_untested_)
* Clones such as the Laser 128, Franklin ACE 2200, Franklin ACE 500
* Emulators such as MAME, Virtual ][, AppleWin, etc.

It runs in ProDOS-8 and follows the "interpreter protocol" so that launchers such as [Bitsy Bye](https://prodos8.com/bitsy-bye/) and [Apple II DeskTop](https://a2desktop.com) can automatically launch CHIP-8 programs with it.

# For Users

Download the latest floppy disk image and run it in your favorite emulator:

https://github.com/a2stuff/chip8.system/releases/latest/download/chip8.po

Try it right in your browser with [Apple2TS](https://apple2ts.com/?color=color#https://github.com/a2stuff/chip8.system/releases/latest/download/chip8.po) - _some games do not respond to keys in this emulator_.

## CHIP-8 Programs

To run a CHIP-8 program, copy the file to a [ProDOS-8 2.4](https://prodos8.com/) with the `CHIP8.SYSTEM` renamed to (or copied as) `BASIS.SYSTEM`, then boot the disk. [Bitsy Bye](https://prodos8.com/bitsy-bye/) will run. Pick the CHIP-8 file and it will run automatically.

> TIP: [Apple II DeskTop](https://a2desktop.com) will use a copy of `BASIS.SYSTEM` in the same directory to launch unknown file types.


There are many online archives of CHIP-8 programs:

* https://johnearnest.github.io/chip8Archive/?sort=platform#chip8
* https://chip-8.github.io/links/
* https://github.com/kripod/chip8-roms
* https://www.zophar.net/pdroms/chip8/chip-8-games-pack.html

> NOTE: Only CHIP-8 games are supported, not SUPER-CHIP or XO-CHIP.

## Controls

* Press <kbd>Esc</kbd> at any time to quit to ProDOS.
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

> TIP: CHIP-8 programs use a variety of key combinations. Look for documentation where you found the program, or mash the keys to figure out the controls. Have fun!

### Compatibility & Quirks

Some CHIP-8 programs require different compatibility settings. This can be enabled by changing the ProDOS file type of the program to `$5D` (`ENT` or Entertainment), and setting the aux type to `$C800` (for "CHIP-8") with the lower byte used as "quirks" flags as follows:

| Bit | Name         | ID                       | Default     |
|-----|--------------|--------------------------|-------------|
| 0   | VF Reset     | `logic`                  | on / true   |
| 1   | Memory       | `memoryLeaveIUnchanged`* | on / false  |
| 2   | Display Wait | `vblank`                 | on / true   |
| 3   | Clipping     | `wrap`*                  | on / false  |
| 4   | Shifting     | `shift`                  | off / false |
| 5   | Jumping      | `jump`                   | off / false |

Names are per [Timendus's CHIP-8 quirks test](https://github.com/Timendus/chip8-test-suite?tab=readme-ov-file#quirks-test). The defaults match the passing expectations in these tests.

IDs are per the [CHIP-8 database](https://github.com/chip-8/chip-8-database/blob/master/database/quirks.json), which lists the same quirks but with slightly different expectations. A * signifies that sense is inverted, i.e. _setting_ the bit is the same as turning _off_ the quirk, per the database definition.

Defaults "on" and "off" reference Timendus' tests, "true" and "false" reference the CHIP-8 database.

Otherwise, all quirks are set to the defaults. This is equivalent to file type `$5D` and aux type `$C80F`.

For exmple, the `BLINKY` game (a Pac-Man clone) requires the "Memory" quirk disabled and the "Shifting" quirk enabled, so is packaged with file type `$5D` and aux type `$C81D`.

For detailed "quirks" definitions, see https://github.com/Timendus/chip8-test-suite?tab=readme-ov-file#the-test

> TIP: You can use [Apple II DeskTop](https://a2desktop.com) to easily change the file type and auxtype; use the **Change Type** accessory in the **Apple** menu.

# For Developers

## Development References

* https://tobiasvl.github.io/blog/write-a-chip-8-emulator/
* https://github.com/Timendus/chip8-test-suite
* https://chip-8.github.io/

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
