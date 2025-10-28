const serial = @import("serial.zig");
const framebuffer = @import("framebuffer.zig");
const CPUState = @import("interrupts.zig").CPUState;
const inb = @import("asm.zig").inb;
const outb = @import("asm.zig").outb;

var shift_pressed: bool = false;
var ctrl_pressed: bool = false;
var alt_pressed: bool = false;

// US QWERTY keyboard scancode to ASCII mapping
const scancode_to_ascii = [_]u8{
    0, 0, '1', '2', '3', '4', '5', '6', // 0x00-0x07
    '7', '8', '9', '0', '-', '=', 8, '\t', // 0x08-0x0F (8 = backspace)
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', // 0x10-0x17
    'o', 'p', '[', ']', '\n', 0, 'a', 's', // 0x18-0x1F (0x1C = enter, 0x1D = ctrl)
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', // 0x20-0x27
    '\'', '`', 0, '\\', 'z', 'x', 'c', 'v', // 0x28-0x2F (0x2A = shift)
    'b', 'n', 'm', ',', '.', '/', 0, '*', // 0x30-0x37 (0x36 = right shift)
    0, ' ', 0, 0, 0, 0, 0, 0, // 0x38-0x3F (0x38 = alt, 0x39 = space)
};

const scancode_to_ascii_shift = [_]u8{
    0, 0, '!', '@', '#', '$', '%', '^', // 0x00-0x07
    '&', '*', '(', ')', '_', '+', 8, '\t', // 0x08-0x0F
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', // 0x10-0x17
    'O', 'P', '{', '}', '\n', 0, 'A', 'S', // 0x18-0x1F
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', // 0x20-0x27
    '"', '~', 0, '|', 'Z', 'X', 'C', 'V', // 0x28-0x2F
    'B', 'N', 'M', '<', '>', '?', 0, '*', // 0x30-0x37
    0, ' ', 0, 0, 0, 0, 0, 0, // 0x38-0x3F
};

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

fn scancode_to_char(scancode: u8) ?u8 {
    const key_code = scancode & 0x7F;
    const key_released = (scancode & 0x80) != 0;

    // Handle modifier keys
    switch (key_code) {
        0x2A, 0x36 => { // Left shift, Right shift
            shift_pressed = !key_released;
            return null;
        },
        0x1D => { // Ctrl
            ctrl_pressed = !key_released;
            return null;
        },
        0x38 => { // Alt
            alt_pressed = !key_released;
            return null;
        },
        else => {},
    }

    // Only process key press events (not release)
    if (key_released) {
        return null;
    }

    // Convert scancode to ASCII
    if (key_code < scancode_to_ascii.len) {
        const ascii_char = if (shift_pressed)
            scancode_to_ascii_shift[key_code]
        else
            scancode_to_ascii[key_code];

        if (ascii_char != 0) {
            return ascii_char;
        }
    }

    return null;
}

pub fn keyboard_interrupt_handler(rsp: usize) u64 {
    const cpu_state: *CPUState = @ptrFromInt(rsp);
    const scancode = retrieve_scancode();

    // Handle ESC key (scancode 0x01) for exit
    if (scancode == 0x01) {
        framebuffer.global_framebuffer.println_color("\nHalting", framebuffer.COLOR_RED);
        asm volatile ("cli; hlt");
        while (true) {}
    }

    if (scancode_to_char(scancode)) |ascii_char| {
        framebuffer.global_framebuffer.put_char(ascii_char);
    }

    return @intFromPtr(cpu_state);
}
