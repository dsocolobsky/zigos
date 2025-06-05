const idt = @import("idt.zig");
const pic = @import("pic.zig");
const serial = @import("serial.zig");
const keyboard = @import("keyboard.zig");
const cli = @import("asm.zig").cli;
const sti = @import("asm.zig").sti;
const framebuffer = @import("framebuffer.zig");

pub var handlers: [256]usize = undefined;

pub var ticks: u128 = 0;

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

export fn interrupt_handler(rsp: usize) callconv(.C) u64 {
    const cpu_state: *CPUState = @ptrFromInt(rsp);
    logInterrupt(cpu_state.vector, cpu_state.error_code);

    var ret = rsp;
    if (cpu_state.vector == 32) { // 0 (clock)
        tick();
    } else if (cpu_state.vector == 33) { // 1 (keyboard)
        ret = keyboard.keyboard_interrupt_handler(rsp);
    }
    if (cpu_state.vector >= 32) {
        pic.sendEOI(cpu_state.vector);
        return ret;
    }

    while (true) {}

    return rsp;
}

fn register_interrupt_handler(vector: i64, handler: usize) void {
    handlers[vector] = handler;
}

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
    } else if (vector > 33) { // Let's ignore the keyboard and clock interrupts for now
        serial.print("2 Interrupt no: {x}\nError code : {x}\n", .{
            vector,
            error_code,
        });
    }
}

fn tick() void {
    ticks += 1;
    if (ticks % 20 == 0) {
        //framebuffer.global_framebuffer.update_panel();
    }
}

pub fn init() void {
    cli();

    idt.init();

    pic.remap();
    pic.maskAll();
    pic.clearMask(0); // Clock
    pic.clearMask(1); // Keyboard

    serial.puts("Interrupts Initialized");

    sti();
}
