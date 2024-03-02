const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const inb = @import("asm.zig").inb;
const outb = @import("asm.zig").outb;
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

pub const CPUState = packed struct {
    // general segment registers
    ds: u64,
    es: u64,
    fs: u64,
    gs: u64,
    // general purpose registers
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    // The vector that caused the interrupt or exception
    vector: u64,
    // The error code, optional, but the interrupt service routine entry
    // should always push one even the interrupt or exception does not generate
    // error code
    error_code: u64,

    rip: u64,
    cs: u64,
    rflags: u64,
    // in 64-bit mode, the SS and rsp are always pushed into stack
    rsp: u64,
    ss: u64,
};

pub var handlers: [256]usize = undefined;

pub fn logInterrupt(vector: u64, error_code: u64) void {
    const name = [_][]const u8{
        "Division by zero",
        "Debug",
        "Non-maskable Interrupt",
        "Breakpoint",
        "Overflow",
        "Bound range exceeded",
        "Invalid Opcode",
        "Device not available",
        "Double fault",
        "0x9",
        "Invalid TSS",
        "Segment not present",
        "Stack-Segment Fault",
        "General Protection Fault",
        "Page Fault",
        "Reversed",
        "x87 Floating-Point Exception",
        "Alignment Check",
        "Machine Check",
        "SIMD Floating-Point Exception",
        "Virtualization Exception",
        "Control Protection Exception",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Reserved",
        "Hypervisor Injection Exception",
        "VMM Communcation Exception",
        "Security Exception",
        "Reserved",
    };

    if (vector < 31) {
        serial.print(
            "1 Interrupt no: {x} name: {s}\nError code: {x}\n",
            .{ vector, name[vector], error_code },
        );
    } else {
        serial.print("2 Interrupt no: {x}\nError code : {x}\n", .{
            vector,
            error_code,
        });
    }
}

export fn interrupt_handler(rsp: usize) callconv(.C) u64 {
    const cpu_state: *CPUState = @ptrFromInt(rsp);
    logInterrupt(cpu_state.vector, cpu_state.error_code);

    if (cpu_state.vector == 0x21) {
        const res = keyboard_interrupt_handler(rsp);
        pic.sendEoi(cpu_state.vector);
        return res;
    }

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

fn register_interrupt_handler(vector: i64, handler: usize) void {
    handlers[vector] = handler;
}

fn retrieve_scancode() u8 {
    var code: u8 = 0;
    while (true) {
        code = inb(0x60);
        if (code != 0) {
            break;
        }
    }
    return code;
}

pub fn keyboard_interrupt_handler(rsp: usize) u64 {
    const cpu_state: *CPUState = @ptrFromInt(rsp);
    const code = retrieve_scancode();
    serial.print("Scancode: {x}\n", .{code});
    return @intFromPtr(cpu_state);
}
