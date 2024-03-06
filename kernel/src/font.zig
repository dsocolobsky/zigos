const framebuffer = @import("framebuffer.zig");
const serial = @import("serial.zig");

extern var _binary_tamsyn_psf_start: u8;
extern var _binary_tamsyn_psf_end: u8;

const PSF = packed struct {
    magic: u32,
    version: u32,
    header_size: u32,
    flags: u32,
    glyph_count: u32,
    bytes_per_glyph: u32,
    height: u32,
    width: u32,

    pub fn log(self: *PSF) void {
        serial.println("PSF magic: {x}", .{self.magic});
        serial.println("PSF dimensions: {d}x{d}", .{ self.width, self.height });
        serial.println("PSF glyph count: {d}", .{self.glyph_count});
        serial.println("PSF bytes per glyph: {d}", .{self.bytes_per_glyph});
        serial.println("PSF bytes per line: {d}", .{self.bytesPerLine()});
        const start = @intFromPtr(&self) + self.header_size;
        serial.println("PSF glyph start addr: 0x{x}", .{start});
    }

    fn getGlyph(self: *PSF, c: u8) *u8 {
        const start = @intFromPtr(self) + self.header_size;
        return @ptrFromInt(start + c * self.bytes_per_glyph);
    }

    fn getGlyph2(self: *PSF, c: u8) [*]u8 {
        const new_idx: [*]u8 = self.glyphs[c * self.bytes_per_glyph ..];
        return new_idx;
    }

    inline fn bytesPerLine(self: *PSF) u32 {
        return (self.width + 7) / 8;
    }

    pub fn putChar(
        self: *PSF,
        fbuff: *framebuffer.Framebuffer,
        char: u8,
        cx: u32,
        cy: u32,
        fg: u32,
        bg: u32,
    ) void {
        var glyph: *u8 = self.getGlyph(char);

        // bytes per line, it's 4*1920 = 7680
        const bytes_per_pixel = 4;
        const pitch = fbuff.framebuffer.pitch;
        var offs = (cy * self.height * pitch) +
            (cx * (self.width + 1) * bytes_per_pixel);

        for (0..self.height) |_| {
            var line: u32 = @intCast(offs);
            var mask = @as(u32, 1) << @truncate(self.width + 1);

            for (0..self.width) |_| {
                const pixel_addr: usize = @intFromPtr(fbuff.framebuffer.address) + @as(usize, line);
                const masked_glyph: u32 = glyph.* & mask;
                var color: u32 = if (masked_glyph != 0) fg else bg;
                const pixel_ptr: *u32 = @ptrFromInt(pixel_addr);
                pixel_ptr.* = color;

                // adjust next pixel
                mask >>= 1;
                line += bytes_per_pixel;
            }

            // This segfaults
            const new_glyph_addr = @intFromPtr(glyph) + self.bytesPerLine();
            glyph = @ptrFromInt(new_glyph_addr);
            offs += pitch;
        }
    }

    pub fn puts(
        self: *PSF,
        fbuff: *framebuffer.Framebuffer,
        str: []const u8,
        cx: u32,
        cy: u32,
        fg: u32,
        bg: u32,
    ) void {
        var idx: usize = 0;
        while (str[idx] != 0x00) {
            self.putChar(
                fbuff,
                str[idx],
                @truncate(cx + idx),
                cy,
                fg,
                bg,
            );
            idx += 1;
        }
    }
};

pub var psf: *PSF = undefined;

pub fn init() *PSF {
    const addr: usize = @intFromPtr(&_binary_tamsyn_psf_start);
    psf = @ptrFromInt(addr);
    return psf;
}
