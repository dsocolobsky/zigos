# zigos

Simple x86_64 kernel written in Zig for learning purposes.
This is very barebones as of yet and it's work in progress.
Uses the [Limine](https://limine-bootloader.org/) bootloader which already leaves us in long mode.

## Requirements
zig `0.14.X`, standard build tools, xorriso, qemu-system-x86_64 and/or bochs.

You may need to run 

## Running
} Run `make limine` at least once to download Limine as a local dependency
* `make run` compiles and runs in QEMU
* `make bochs` compiles and runs in Bochs

## Already implemented (somewhat):
* GDT
* TSS
* Clock Interrupts
* Debug output via serial port
* Loading .sym font and printing text
* Keyboard interrupts
* Basic framebuffer printing
* VMM 4-level paging
* Type things into the screen

## Current TODO
* Console atm is too basic, proper delete, cursor, scroll, etc.
* Processes ?
* Filesystem ?
