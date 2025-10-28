const framebuffer = @import("framebuffer.zig");

var last_ticks: u128 = 0;
var spinner_pos: u32 = 0;

const SPINNER_CHARS = [_]u8{ '|', '/', '-', '\\' };

const CHAR_WIDTH = 8;
const CHAR_HEIGHT = 8;

const PATTERNS = [4][8]u8{
    [_]u8{ 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // '|'
    [_]u8{ 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80 }, // '/'
    [_]u8{ 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00 }, // '-'
    [_]u8{ 0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01 }, // '\'
};

pub fn update(current_ticks: u128) void {
    if (current_ticks - last_ticks > 10) {
        last_ticks = current_ticks;
        spinner_pos = (spinner_pos + 1) % 4;

        draw_spinner_character();
    }
}

fn draw_spinner_character() void {
    const fb = &framebuffer.global_framebuffer;

    // Position in upper right corner (with some margin)
    const spinner_x: u32 = @intCast(fb.framebuffer.width - CHAR_WIDTH - 10);
    const spinner_y: u32 = 10;

    // Clear previous character (black background)
    var y: u32 = 0;
    while (y < CHAR_HEIGHT) : (y += 1) {
        var x: u32 = 0;
        while (x < CHAR_WIDTH) : (x += 1) {
            fb.set_pixel(spinner_x + x, spinner_y + y, framebuffer.COLOR_BLACK);
        }
    }

    // Draw current spinner character
    const pattern = PATTERNS[spinner_pos];

    y = 0;
    while (y < CHAR_HEIGHT) : (y += 1) {
        var x: u32 = 0;
        while (x < CHAR_WIDTH) : (x += 1) {
            if ((pattern[y] & (@as(u8, 1) << @truncate(7 - x))) != 0) {
                fb.set_pixel(spinner_x + x, spinner_y + y, framebuffer.COLOR_WHITE);
            }
        }
    }
}
