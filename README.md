# zigos

Simple x86_64 kernel written in Zig for learning purposes.
This is very barebones as of yet and it's work in progress.
Uses the [Limine](https://limine-bootloader.org/) bootloader which already leaves us in long mode.

**Important** This was built under Zig `0.11`, the current stable version is `0.12` so it might
not work yet with that version.

## Requirements
zig `0.11.X`, standard build tools, xorriso, qemu-system-x86_64 and/or bochs.

TODO: Add requirements properly.

## Running
* `make run` compiles and runs in QEMU
* `make bochs` compiles and runs in Bochs

## Already implemented (somewhat):
* GDT
* TSS
* Clock Interrupts
* Debug output via serial port
* Loading .sym font and printing text
* Keyboard interrupts
