# zigos

Simple x86_64 kernel written in Zig for learning purposes.
This uses the [Limine](https://limine-bootloader.org/) bootloader which already leaves us in long mode.

## Running
* `make run` (requires qemu and a buch of things).
* Alternatively you can also `make all` and run in bochs with `bochs -q`.

## TODO (and done)
- [x] Writing to serial ports
- [x] GDT
- [ ] Write to `debugcon` for qemu/bochs
- [ ] Make debuggable with GDB or similar
- [ ] Replace Makefile with Zig Build System
- [ ] Figure out how to link nasm code
- [ ] Interrupts
- [ ] Paging
