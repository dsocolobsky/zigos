const serial = @import("serial.zig");
const CPUState = @import("interrupts.zig").CPUState;
const inb = @import("asm.zig").inb;
const outb = @import("asm.zig").outb;

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
