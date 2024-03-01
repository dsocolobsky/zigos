const outb = @import("asm.zig").outb;
const inb = @import("asm.zig").inb;
const iowait = @import("asm.zig").iowait;

const PIC1 = 0x20; // I/O base address for master PIC
const PIC2 = 0xA0; // I/O base address for slave PIC
const PIC1_COMMAND = PIC1; // master PIC command port
const PIC1_DATA = (PIC1 + 1); // master PIC data port
const PIC2_COMMAND = PIC2; // slave PIC command port
const PIC2_DATA = (PIC2 + 1); // slave PIC data port
const ICW4_8086 = 0x01;

pub fn Remap() void {
    const mask1 = inb(PIC1_DATA);
    const mask2 = inb(PIC2_DATA);

    outb(PIC1_COMMAND, 0x11);
    outb(PIC2_COMMAND, 0x11);
    iowait();

    outb(PIC1_DATA, 0x20);
    outb(PIC2_DATA, 0x28);
    iowait();

    outb(PIC1_DATA, 0x04);
    outb(PIC2_DATA, 0x02);
    iowait();

    outb(PIC1_DATA, 0x01);
    outb(PIC2_DATA, 0x01);
    iowait();

    outb(PIC1_DATA, 0x00);
    outb(PIC2_DATA, 0x00);
    iowait();

    outb(PIC1_DATA, ICW4_8086);
    iowait();
    outb(PIC2_DATA, ICW4_8086);
    iowait();

    outb(PIC1_DATA, mask1);
    outb(PIC2_DATA, mask2);
}

pub fn SetMask(irq_line: u8) void {
    const port = if (irq_line < 8) {
        PIC1_DATA;
    } else {
        PIC2_DATA;
    };

    const value = inb(port) | (1 << irq_line % 8);
    outb(port, value);
}

pub fn ClearMask(irq_line: u8) void {
    var port: u16 = PIC1_DATA;

    const irq_line_mod: u8 = irq_line % 8;
    const value = inb(port) & ~(@as(u1, 1) << irq_line_mod);
    outb(port, value);
}

pub fn maskAll() void {
    outb(PIC1_DATA, 0xFF);
    outb(PIC2_DATA, 0xFF);
}

pub fn clearAllMasks() void {
    var i: u8 = 0;
    while (i < 16) {
        ClearMask(i);
        i += 1;
    }
}
