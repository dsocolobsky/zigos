const outb = @import("asm.zig").outb;
const inb = @import("asm.zig").inb;
const iowait = @import("asm.zig").iowait;

const PIC_MASTER_COMMAND = 0x20;
const PIC_MASTER_DATA = 0x21;
const PIC_SLAVE_COMMAND = 0xA0;
const PIC_SLAVE_DATA = 0xA1;
const ICW4_8086 = 0x01;

pub fn remap() void {
    const mask1 = inb(PIC_MASTER_DATA);
    const mask2 = inb(PIC_SLAVE_DATA);

    outb(PIC_MASTER_COMMAND, 0x11);
    outb(PIC_SLAVE_COMMAND, 0x11);
    iowait();

    outb(PIC_MASTER_DATA, 0x20);
    outb(PIC_SLAVE_DATA, 0x28);
    iowait();

    outb(PIC_MASTER_DATA, 0x04);
    outb(PIC_SLAVE_DATA, 0x02);
    iowait();

    outb(PIC_MASTER_DATA, 0x01);
    outb(PIC_SLAVE_DATA, 0x01);
    iowait();

    outb(PIC_MASTER_DATA, 0x00);
    outb(PIC_SLAVE_DATA, 0x00);
    iowait();

    outb(PIC_MASTER_DATA, ICW4_8086);
    iowait();
    outb(PIC_SLAVE_DATA, ICW4_8086);
    iowait();

    outb(PIC_MASTER_DATA, mask1);
    outb(PIC_SLAVE_DATA, mask2);
}

pub fn setMask(irq_line: u8) void {
    const port = if (irq_line < 8) {
        PIC_MASTER_DATA;
    } else {
        PIC_SLAVE_DATA;
    };

    const value = inb(port) | (1 << irq_line % 8);
    outb(port, value);
}

pub fn clearMask(irq_line: u8) void {
    const irq_line_mod: u8 = irq_line % 8;
    const value = inb(PIC_MASTER_DATA) & ~(@as(u1, 1) << irq_line_mod);
    outb(PIC_MASTER_DATA, value);
}

pub fn maskAll() void {
    outb(PIC_MASTER_DATA, 0xFF);
    outb(PIC_SLAVE_DATA, 0xFF);
}

pub fn clearKeyboardMask() void {
    outb(PIC_MASTER_DATA, 0xfd);
    outb(PIC_SLAVE_DATA, 0xff);
}

// Send end-of-interrupt signal for the given IRQ
pub fn sendEOI(vector: usize) void {
    if (vector >= 40) {
        outb(PIC_SLAVE_COMMAND, 0x20);
    }
    outb(PIC_MASTER_COMMAND, 0x20);
}
