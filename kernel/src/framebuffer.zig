pub const Framebuffer = @This();
const std = @import("std");
const limine = @import("limine");
const serial = @import("serial.zig");
const PSF = @import("font.zig").PSF;

pub var global_framebuffer: Framebuffer = undefined;
var tick_color_index: usize = 0;

var framebuffer_request: limine.FramebufferRequest = .{};

framebuffer: *limine.Framebuffer = undefined,

font: *PSF = undefined,
bpp: u32 = 4,

pub const COLOR_RED: u32 = 0x00_FF_00_00;
pub const COLOR_GREEN: u32 = 0x00_00_FF_00;
pub const COLOR_BLUE: u32 = 0x00_00_00_FF;
pub const COLOR_WHITE: u32 = 0xFF_FF_FF_FF;

pub const colors = [3]u32{
    COLOR_RED,
    COLOR_GREEN,
    COLOR_BLUE,
};

inline fn get_red(color: u32) u8 {
    return @as(u8, @truncate((color >> 16) & 255));
}

inline fn get_blue(color: u32) u8 {
    return @as(u8, @truncate(color & 255));
}

inline fn get_green(color: u32) u8 {
    return @as(u8, @truncate((color >> 8) & 255));
}

pub fn clear(self: Framebuffer) void {
    // Ensure width and height are positive for fillrect
    if (self.framebuffer.width > 0 and self.framebuffer.height > 0) {
        self.fillrect(COLOR_WHITE, self.framebuffer.width, self.framebuffer.height);
    }
}

pub fn putpixel(self: Framebuffer, x: u32, y: u32, color: u32) void {
    if (self.framebuffer.address == null) {
        return;
    }
    // Since it's not null, we can use it directly.
    const fb_base_address: *anyopaque = self.framebuffer.address;

    // 2. Calculate the total size of the framebuffer in bytes
    const fb_total_size = self.framebuffer.height * self.framebuffer.pitch;
    if (fb_total_size == 0) return; // Avoid zero-length slice

    // 3. Create a slice for the entire framebuffer
    var fb_slice: []u8 = @as([*]u8, @ptrCast(fb_base_address))[0..fb_total_size];

    const offset = @as(usize, y) * @as(usize, self.framebuffer.pitch) + @as(usize, x) * @as(usize, self.bpp);

    // Bounds check
    if (offset + self.bpp <= fb_slice.len) {
        fb_slice[offset + 0] = get_blue(color);
        fb_slice[offset + 1] = get_green(color);
        fb_slice[offset + 2] = get_red(color);
        // if self.bpp == 4, handle alpha if necessary:
        // fb_slice[offset + 3] = get_alpha(color);
    }
}

pub fn fillrect(self: Framebuffer, color: u32, width: u64, height: u64) void {
    // Check if the framebuffer base address is null
    if (@intFromPtr(self.framebuffer.address) == 0) {
        return; // Can't draw if address is null
    }
    // Since it's not null, we can use it directly.
    const fb_base_address: *anyopaque = self.framebuffer.address;

    const fb_pitch = self.framebuffer.pitch;
    const fb_height = self.framebuffer.height;
    const fb_width = self.framebuffer.width; // Use actual framebuffer width for bounds checking

    // Calculate total framebuffer size for the slice
    const fb_total_size = fb_height * fb_pitch;
    if (fb_total_size == 0) return;

    var fb_slice: []u8 = @as([*]u8, @ptrCast(fb_base_address))[0..fb_total_size];

    const rect_height = @min(height, fb_height); // Don't draw past framebuffer height
    const rect_width = @min(width, fb_width); // Don't draw past framebuffer width

    var y: u64 = 0;
    while (y < rect_height) : (y += 1) {
        const current_row_offset: usize = @intCast(y * fb_pitch); // Changed var to const
        var x: u64 = 0;
        while (x < rect_width) : (x += 1) {
            const pixel_offset_in_row: usize = @intCast(x * self.bpp);
            const final_offset = current_row_offset + pixel_offset_in_row;

            if (final_offset + self.bpp <= fb_slice.len) {
                fb_slice[final_offset + 0] = get_blue(color);
                fb_slice[final_offset + 1] = get_green(color);
                fb_slice[final_offset + 2] = get_red(color);
                // if self.bpp == 4, handle alpha:
                // fb_slice[final_offset + 3] = get_alpha(color);
            }
        }
    }
}

pub fn update_panel(self: Framebuffer) void {
    self.fillrect(colors[tick_color_index], 256, 32);
    tick_color_index = (tick_color_index + 1) % colors.len;
}

pub fn putChar(
    self: *Framebuffer,
    char: u8,
    cx: u32,
    cy: u32,
    fg: u32,
    bg: u32,
) void {
    var glyph: [*]u8 = self.font.getGlyph(char);

    const pitch = self.framebuffer.pitch;
    var offs = (cy * self.font.height * pitch) +
        (cx * (self.font.width + 1) * self.bpp);

    for (0..self.font.height) |_| {
        var line: u32 = @intCast(offs);
        var mask = @as(u32, 1) << @truncate(self.font.width + 1);

        for (0..self.font.width) |_| {
            const masked_glyph: u32 = glyph[0] & mask;
            const color: u32 = if (masked_glyph != 0) fg else bg;

            // TODO figure out if this limit is safe, I just made it up
            var address: []u8 = @as([*]u8, @ptrCast(self.framebuffer.address))[0..65536];
            address[line + 0] = get_blue(color);
            address[line + 1] = get_green(color);
            address[line + 2] = get_red(color);

            // adjust next pixel
            mask >>= 1;
            line += self.bpp;
        }

        // This segfaults
        glyph += self.font.bytesPerLine();
        offs += pitch;
    }
}

pub fn puts(
    self: *Framebuffer,
    str: []const u8,
    cx: u32,
    cy: u32,
    fg: u32,
    bg: u32,
) void {
    for (str, 0..) |c, i| {
        self.putChar(
            c,
            @truncate(cx + i),
            cy,
            fg,
            bg,
        );
    }
}

pub fn init(font: *PSF) void {
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            serial.print_err("Error initializing framebuffer", .{});
            return;
        }

        // Ensure framebuffer_response.framebuffers is not null
        const limine_framebuffers = framebuffer_response.framebuffers orelse {
            serial.print_err("Framebuffer response has null framebuffers pointer", .{});
            return;
        };

        // Correctly type framebuffer_ptr to match the type from limine library
        const framebuffer_ptr: [*]*limine.Framebuffer = limine_framebuffers;
        const framebuffer = Framebuffer{
            .framebuffer = framebuffer_ptr[0], // Now framebuffer_ptr[0] is *limine.Framebuffer
            .bpp = framebuffer_ptr[0].bpp / 8, // Accessing .bpp from limine.Framebuffer
            .font = font,
        };

        framebuffer.clear();
        //framebuffer.update_panel();

        global_framebuffer = framebuffer;

        serial.println(
            "framebuffer dimensions: {d}x{d}",
            .{ framebuffer.framebuffer.width, framebuffer.framebuffer.height },
        );
        serial.println(
            "framebuffer pitch: {d}",
            .{framebuffer.framebuffer.pitch},
        );
        serial.println(
            "framebuffer bits per pixel: {d}",
            .{framebuffer.framebuffer.bpp},
        );
    }
}
