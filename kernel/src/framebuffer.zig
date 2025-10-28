pub const Framebuffer = @This();
const std = @import("std");
const limine = @import("limine");
const serial = @import("serial.zig");
const font_data = @import("font.zig");

pub var global_framebuffer: Framebuffer = undefined;
var framebuffer_request: limine.FramebufferRequest = .{};

framebuffer: *limine.Framebuffer = undefined,
fb_ptr: ?[*]volatile u32 = null,
pitch_in_pixels: u32 = 0,

cursor_x: u32 = 0,
cursor_y: u32 = 0,
char_width: u32 = 8,
char_height: u32 = 16,
cols: u32 = 0,
rows: u32 = 0,

fg_color: u32 = 0xFFFFFF,
bg_color: u32 = 0x000000,

pub const COLOR_RED: u32 = 0x00_FF_00_00;
pub const COLOR_GREEN: u32 = 0x00_00_FF_00;
pub const COLOR_BLUE: u32 = 0x00_00_00_FF;
pub const COLOR_WHITE: u32 = 0xFF_FF_FF_FF;
pub const COLOR_BLACK: u32 = 0x00_00_00_00;

pub fn clear(self: *Framebuffer) void {
    if (self.fb_ptr == null) return;

    const fb_ptr = self.fb_ptr.?;
    const fb_size = self.framebuffer.height * self.pitch_in_pixels;
    var i: usize = 0;
    while (i < fb_size) : (i += 1) {
        fb_ptr[i] = self.bg_color;
    }

    self.cursor_x = 0;
    self.cursor_y = 0;
}

pub fn draw_char(self: *Framebuffer, c: u8, x: u32, y: u32) void {
    if (self.fb_ptr == null or c >= 128) return;

    const fb_ptr = self.fb_ptr.?;
    const glyph = font_data.font[c];

    var row: u32 = 0;
    while (row < self.char_height) : (row += 1) {
        var col: u32 = 0;
        while (col < self.char_width) : (col += 1) {
            const pixel_x = x * self.char_width + col;
            const pixel_y = y * self.char_height + row;

            if (pixel_x >= self.framebuffer.width or pixel_y >= self.framebuffer.height) continue;

            const color = if ((glyph[row] & (@as(u8, 1) << @truncate(7 - col))) != 0) self.fg_color else self.bg_color;
            fb_ptr[pixel_y * self.pitch_in_pixels + pixel_x] = color;
        }
    }
}

pub fn scroll_up(self: *Framebuffer) void {
    if (self.fb_ptr == null) return;

    const fb_ptr = self.fb_ptr.?;

    // Move all lines up by one character height
    var y: u32 = self.char_height;
    while (y < self.framebuffer.height) : (y += 1) {
        var x: u32 = 0;
        while (x < self.framebuffer.width) : (x += 1) {
            fb_ptr[(y - self.char_height) * self.pitch_in_pixels + x] = fb_ptr[y * self.pitch_in_pixels + x];
        }
    }

    // Clear the last line
    y = @intCast(self.framebuffer.height - self.char_height);
    while (y < self.framebuffer.height) : (y += 1) {
        var x: u32 = 0;
        while (x < self.framebuffer.width) : (x += 1) {
            fb_ptr[y * self.pitch_in_pixels + x] = self.bg_color;
        }
    }
}

pub fn newline(self: *Framebuffer) void {
    self.cursor_x = 0;
    self.cursor_y += 1;

    if (self.cursor_y >= self.rows) {
        self.scroll_up();
        self.cursor_y = self.rows - 1;
    }
}

pub fn put_char(self: *Framebuffer, c: u8) void {
    if (self.fb_ptr == null) return;

    switch (c) {
        '\n' => {
            self.newline();
            return;
        },
        '\r' => {
            self.cursor_x = 0;
            return;
        },
        '\t' => {
            const tab_stop = 4;
            const spaces = tab_stop - (self.cursor_x % tab_stop);
            var i: u32 = 0;
            while (i < spaces) : (i += 1) {
                self.put_char(' ');
            }
            return;
        },
        8 => { // Backspace
            if (self.cursor_x > 0) {
                self.cursor_x -= 1;
                self.draw_char(' ', self.cursor_x, self.cursor_y);
            }
            return;
        },
        else => {},
    }

    self.draw_char(c, self.cursor_x, self.cursor_y);

    self.cursor_x += 1;
    if (self.cursor_x >= self.cols) {
        self.newline();
    }
}

pub fn print(self: *Framebuffer, str: []const u8) void {
    for (str) |c| {
        self.put_char(c);
    }
}

pub fn println(self: *Framebuffer, str: []const u8) void {
    self.print(str);
    self.put_char('\n');
}

pub fn set_color(self: *Framebuffer, fg: u32, bg: u32) void {
    self.fg_color = fg;
    self.bg_color = bg;
}

pub fn init() void {
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            serial.print_err("Error initializing framebuffer", .{});
            return;
        }

        const limine_framebuffers = framebuffer_response.framebuffers orelse {
            serial.print_err("Framebuffer response has null framebuffers pointer", .{});
            return;
        };

        const framebuffer_ptr: [*]*limine.Framebuffer = limine_framebuffers;
        global_framebuffer = Framebuffer{
            .framebuffer = framebuffer_ptr[0],
            .fb_ptr = @ptrCast(@alignCast(framebuffer_ptr[0].address)),
            .pitch_in_pixels = @intCast(framebuffer_ptr[0].pitch / 4),
            .cursor_x = 0,
            .cursor_y = 0,
            .char_width = 8,
            .char_height = 16,
            .cols = @intCast(framebuffer_ptr[0].width / 8),
            .rows = @intCast(framebuffer_ptr[0].height / 16),
            .fg_color = COLOR_WHITE,
            .bg_color = COLOR_BLACK,
        };

        global_framebuffer.clear();

        serial.println(
            "framebuffer dimensions: {d}x{d}",
            .{ global_framebuffer.framebuffer.width, global_framebuffer.framebuffer.height },
        );
        serial.println(
            "framebuffer pitch: {d}",
            .{global_framebuffer.framebuffer.pitch},
        );
        serial.println(
            "text dimensions: {d}x{d} characters",
            .{ global_framebuffer.cols, global_framebuffer.rows },
        );
    } else {
        serial.print_err("Framebuffer request failed", .{});
        return;
    }
}
