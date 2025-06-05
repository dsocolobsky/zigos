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
    char_code: u8,
    cx: u32,
    cy: u32,
    fg: u32,
    bg: u32,
) void {
    serial.println("putChar: Entered. char='{c}' (ascii {d}), cx={d}, cy={d}, fg=0x{x}, bg=0x{x}", .{ char_code, char_code, cx, cy, fg, bg });

    // --- Initial Checks ---
    if (@intFromPtr(self.framebuffer.address) == 0) { // Limine.Framebuffer.address is ?*anyopaque
        serial.print_err("putChar ERR: Framebuffer.address from Limine is null!", .{});
        return;
    }
    const fb_base_ptr: *anyopaque = self.framebuffer.address; // We know it's not null here

    if (@intFromPtr(self.font) == 0) { // Assuming self.font is a raw pointer that could be zero
        serial.print_err("putChar ERR: self.font pointer is null!", .{});
        return;
    }
    serial.println("putChar DBG: Font metrics: width={d}, height={d} (from self.font)", .{ self.font.width, self.font.height });

    // --- Font Sanity Checks ---
    if (self.font.width == 0 or self.font.height == 0) {
        serial.print_err("putChar ERR: Font width ({d}) or height ({d}) is zero. Aborting char draw.", .{ self.font.width, self.font.height });
        return;
    }
    const bytes_per_font_scanline = self.font.bytesPerLine();
    if (bytes_per_font_scanline == 0) {
        serial.print_err("putChar ERR: Font bytesPerLine() returned zero. Aborting char draw.", .{});
        return;
    }

    // --- Framebuffer Metrics ---
    const fb_pitch_bytes: usize = @intCast(self.framebuffer.pitch);
    const fb_height_pixels: usize = @intCast(self.framebuffer.height);
    const fb_width_pixels: usize = @intCast(self.framebuffer.width);
    const fb_total_size_bytes: usize = fb_height_pixels * fb_pitch_bytes;

    if (fb_total_size_bytes == 0) {
        serial.print_err("putChar ERR: Framebuffer total calculated size is zero. Aborting char draw.", .{});
        return;
    }
    if (self.bpp == 0) {
        serial.print_err("putChar ERR: self.bpp (bytes per pixel for drawing) is zero. Aborting char draw.", .{});
        return;
    }

    // --- Slice and Pointers Setup ---
    var fb_slice: []u8 = @as([*]u8, @ptrCast(fb_base_ptr))[0..fb_total_size_bytes];

    var current_glyph_scanline_ptr: [*]const u8 = self.font.getGlyph(char_code);
    if (@intFromPtr(current_glyph_scanline_ptr) == 0) {
        serial.print_err("putChar ERR: self.font.getGlyph('{c}') returned a NULL pointer!", .{char_code});
        return;
    }

    // --- Character Positioning ---
    const char_start_pixel_y_fb: usize = @intCast(cy * self.font.height);
    const char_cell_width_for_cx_calc: u32 = self.font.width + 1;
    const char_start_pixel_x_fb: usize = @intCast(cx * char_cell_width_for_cx_calc);

    // --- Drawing Loop ---
    var y_font: u32 = 0; // y-offset within the font character glyph (0 to font.height-1)
    while (y_font < self.font.height) : (y_font += 1) {
        const current_fb_pixel_y: usize = char_start_pixel_y_fb + y_font;

        if (@intFromPtr(current_glyph_scanline_ptr) == 0) {
            serial.print_err("putChar ERR: In y_loop, current_glyph_scanline_ptr became NULL! (y_font={d}). Aborting.", .{y_font});
            return;
        }

        // Bounds check: Stop if drawing past framebuffer bottom edge
        if (current_fb_pixel_y >= fb_height_pixels) {
            break;
        }

        var font_pixel_mask = @as(u8, 1) << @truncate(self.font.width - 1); // MSB-first

        var x_font: u32 = 0; // x-offset within the font character glyph (0 to font.width-1)
        while (x_font < self.font.width) : (x_font += 1) {
            const current_fb_pixel_x: usize = char_start_pixel_x_fb + x_font;

            // Bounds check: Stop if drawing past framebuffer right edge for this scanline
            if (current_fb_pixel_x >= fb_width_pixels) {
                break;
            }

            const glyph_byte_for_scanline = current_glyph_scanline_ptr[0]; // Potential read OOB

            const pixel_is_set = (glyph_byte_for_scanline & font_pixel_mask) != 0;
            const color_to_draw = if (pixel_is_set) fg else bg;

            const final_offset_in_fb_slice: usize = current_fb_pixel_y * fb_pitch_bytes +
                current_fb_pixel_x * @as(usize, self.bpp);

            if (final_offset_in_fb_slice + self.bpp <= fb_slice.len) {
                fb_slice[final_offset_in_fb_slice + 0] = get_blue(color_to_draw);
                fb_slice[final_offset_in_fb_slice + 1] = get_green(color_to_draw);
                fb_slice[final_offset_in_fb_slice + 2] = get_red(color_to_draw);
                // if self.bpp == 4, handle alpha: fb_slice[final_offset_in_fb_slice + 3] = get_alpha(color_to_draw);
            } else {
                serial.println(
                    "putChar WARN: Skipping pixel write! Offset OOB. char='{c}' ({d},{d}) font_px=({d},{d}) fb_px=({d},{d}) offset={d}+bpp={d} > slice_len={d}",
                    .{ char_code, cx, cy, x_font, y_font, current_fb_pixel_x, current_fb_pixel_y, final_offset_in_fb_slice, self.bpp, fb_slice.len },
                );
            }
            font_pixel_mask >>= 1;
        }

        current_glyph_scanline_ptr += bytes_per_font_scanline; // Potential OOB if font data buffer is too small
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
    } else {
        serial.print_err("Framebuffer request failed", .{});
        return;
    }
}
