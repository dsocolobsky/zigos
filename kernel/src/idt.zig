const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const inb = @import("asm.zig").inb;
const outb = @import("asm.zig").outb;
const serial = @import("serial.zig");

const IDT_SIZE = 256;

const IdtEntry = packed struct(u128) {
    isr_low: u16 = 0, // lower 16 bits of ISR address
    kernel_cs: u16 = 0, // kernel code segment selector
    ist: u8 = 0, // The IST in the TSS that the CPU will load into RSP
    attributes: u8 = 0, // type and attributes
    isr_mid: u16 = 0, // bits 15..31 of ISR address
    isr_high: u32 = 0, // higher 32 bits of ISR address
    reserved: u32 = 0,

    pub fn new(handler: u64, flags: u8) @This() {
        var self = IdtEntry{ .attributes = flags };

        self.set_function(handler);

        return self;
    }

    pub fn set_function(self: *@This(), handler: u64) void {
        self.set_isr_addr(handler);

        self.*.kernel_cs = 8;
    }

    pub fn set_isr_addr(self: *@This(), base: u64) void {
        self.*.isr_low = @truncate(base);
        self.*.isr_mid = @truncate(base >> 16);
        self.*.isr_high = @truncate(base >> 32);
    }

    const GateType = enum(u4) { Interrupt = 0xE, Trap = 0xF };

    const EntryAttributes = packed struct(u8) {
        gate_type: GateType = .Interrupt,
        _reserved: u1 = 0,
        privilege: u2 = 0,
        present: bool = false,
    };
};

const IDTR = packed struct {
    limit: u16, // size of IDT - 1
    base: u64, // address of IDT
};
pub var idtr: IDTR = undefined;
pub extern const interrupt_vector: [256]usize;

const IDT = struct {
    entries: [IDT_SIZE]IdtEntry,
};

var idt: IDT = undefined;

pub fn get_idtr_value() IDTR {
    var ret: IDTR = undefined;
    asm volatile ("sidt %[ret]"
        : [ret] "=m" (ret),
    );
    return ret;
}

pub fn init() void {
    inline for (0..31) |i| {
        idt.entries[i] = IdtEntry.new(interrupt_vector[i], 0x8F);
    }
    inline for (31..256) |i| {
        idt.entries[i] = IdtEntry.new(interrupt_vector[i], 0x8E);
    }

    const idtptr = IDTR{ .limit = @sizeOf(IDT) - 1, .base = @intFromPtr(&idt) };

    asm volatile ("lidt %[idtptr]"
        :
        : [idtptr] "*p" (&idtptr),
    );

    const loaded_idtr = get_idtr_value();
    if (loaded_idtr.base != idtptr.base) {
        serial.print_err("IDT limit mismatch: {x} != {x}\n", .{
            loaded_idtr.base,
            idtptr.base,
        });
    }

    serial.puts("IDT Initialized");
}
