const gdt = @import("gdt.zig");

const Entry = packed struct {
    isr_low: u16, // lower 16 bits of ISR address
    kernel_cs: u16, // kernel code segment selector
    ist: u8 = 0, // The IST in the TSS that the CPU will load into RSP
    attributes: u8, // type and attributes
    isr_mid: u16, // bits 15..31 of ISR address
    isr_high: u32, // higher 32 bits of ISR address
    reserved: u32 = 0,
};

const IDTR = packed struct {
    limit: u16, // size of IDT - 1
    base: u64, // address of IDT
};
pub var idtr: IDTR = undefined;
pub extern const interrupt_vector: [256]usize;

pub var IDT: [256]Entry = undefined;

pub const Regs = packed struct {
    rbp: u64,
    rsp: u64,
};

pub const Interrupt = packed struct {
    regs: Regs,
    interrupt: u64,
    code_err: u64,
};

export fn interrupt_handler(rsp: u64) callconv(.C) u64 {
    //const reg: *Interrupt = @ptrFromInt(rsp);
    //reg.log();

    while (true) {}

    return rsp;
}

pub fn init() void {
    asm volatile ("cli");

    for (&IDT, 0..) |*entry, i| {
        const isr_addr = @intFromPtr(&interrupt_vector[i]);
        entry.isr_low = @truncate(isr_addr);
        entry.isr_mid = @truncate(isr_addr >> 16);
        entry.isr_high = @truncate(isr_addr >> 32);
        entry.kernel_cs = gdt.GDT_IDX_KERN_CODE << 3;
        entry.attributes = 0x8E; // Interrupt Gate, DPL=0
    }

    idtr = IDTR{
        .base = @as(u64, @intFromPtr(&IDT)),
        .limit = @sizeOf(Entry) * 256 - 1,
    };

    asm volatile ("lidt %[idtr]"
        :
        : [idtr] "*p" (&idtr),
    );

    asm volatile ("sti");
}
