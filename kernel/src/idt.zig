const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const serial = @import("serial.zig");

const IDT_SIZE = 256;

const Entry = packed struct(u128) {
    isr_low: u16 = 0, // lower 16 bits of ISR address
    kernel_cs: u16 = 0, // kernel code segment selector
    ist: u8 = 0, // The IST in the TSS that the CPU will load into RSP
    attributes: u8 = 0, // type and attributes
    isr_mid: u16 = 0, // bits 15..31 of ISR address
    isr_high: u32 = 0, // higher 32 bits of ISR address
    reserved: u32 = 0,

    pub const InterruptHandler = *const fn (interrupt: *const Regs) callconv(.C) void;

    pub fn new(handler: u64, flags: u8) @This() {
        var self = Entry{ .attributes = flags };

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
    entries: [IDT_SIZE]Entry,
};

pub const Regs = packed struct {
    rbp: u64,
    rsp: u64,
};

pub const Interrupt = packed struct {
    regs: Regs,
    interrupt: u64,
    code_err: u64,

    pub fn log(self: *const @This()) void {
        const expections_name = [_][]const u8{
            "Division by zero",
            "Debug",
            "Non-maskable Interrupt",
            "Breakpoint",
            "Overflow",
            "Bound range Exceeded",
            "Invalid Opcode",
            "Device not available",
            "Double fault",
            "0x9",
            "Invalid TSS",
            "Segment not present",
            "Stack-Segment Fault",
            "General Protection fault",
            "Page Fault",
            "Reversed",
            "x87 Floating-Point exception",
            "Alignment check",
            "Machine check",
            "SIMD Floating-Point Excepction",
            "Virtualization Exception",
            "Control Protection Exception",
            "Reserved",
            "Reserved",
            "Reserved",
            "Reserved",
            "Reserved",
            "Hypervisor injection exception",
            "VMM communcation exception",
            "Security exception",
            "Reserved",
        };

        if (self.interrupt < 31) {
            serial.print(
                "Interrupt no: {x} name: {s}\nError code : {x}\n",
                .{ self.interrupt, expections_name[self.interrupt], self.code_err },
            );
            return;
        }

        serial.print("Interrupt no: {x}\nError code : {x}\n", .{ self.interrupt, self.code_err });
    }
};

export fn interrupt_handler(rsp: u64) callconv(.C) u64 {
    const reg: *Interrupt = @ptrFromInt(rsp);
    reg.log();

    while (true) {}

    return rsp;
}

var idt: IDT = undefined;

pub fn init() void {
    asm volatile ("cli");

    inline for (0..31) |i| {
        idt.entries[i] = Entry.new(interrupt_vector[i], 0x8F);
    }
    inline for (31..256) |i| {
        idt.entries[i] = Entry.new(interrupt_vector[i], 0x8E);
    }

    const idtptr = IDTR{ .limit = @sizeOf(IDT) - 1, .base = @intFromPtr(&idt) };

    asm volatile ("lidt %[idtptr]"
        :
        : [idtptr] "*p" (&idtptr),
    );

    pic.remap();
    pic.maskAll();
    pic.clearKeyboardMask();
    //pic.remap();
    //pic.maskAll();
    //pic.clearAllMasks();

    asm volatile ("sti");
}
