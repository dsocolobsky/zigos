pub const Framebuffer = @This();
const limine = @import("limine");
const serial = @import("serial.zig");
const PSF = @import("font.zig").PSF;

pub var global_framebuffer: Framebuffer = undefined;
var tick_color_index: usize = 0;

framebuffer: *limine.Framebuffer = undefined,

font: *PSF = undefined,
bpp: u32 = 4,

pub export var framebuffer_request: limine.FramebufferRequest = .{};

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
    self.fillrect(COLOR_WHITE, self.framebuffer.width, self.framebuffer.height);
}

pub fn putpixel(self: Framebuffer, x: u32, y: u32, color: u32) void {
    const where = y * self.framebuffer.pitch + x * self.bpp;
    self.framebuffer.address[where + 0] = get_blue(color);
    self.framebuffer.address[where + 1] = get_green(color);
    self.framebuffer.address[where + 2] = get_red(color);
}

pub fn fillrect(self: Framebuffer, color: u32, width: u64, height: u64) void {
    var where = self.framebuffer.address;

    for (0..height) |_| {
        for (0..width) |x| {
            where[x * self.bpp + 0] = get_blue(color);
            where[x * self.bpp + 1] = get_green(color);
            where[x * self.bpp + 2] = get_red(color);
        }
        where += self.framebuffer.pitch;
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
            var color: u32 = if (masked_glyph != 0) fg else bg;
            self.framebuffer.address[line + 0] = get_blue(color);
            self.framebuffer.address[line + 1] = get_green(color);
            self.framebuffer.address[line + 2] = get_red(color);

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
        }

        const framebuffer = Framebuffer{
            .framebuffer = framebuffer_response.framebuffers()[0],
            .bpp = framebuffer_response.framebuffers()[0].bpp / 8,
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
