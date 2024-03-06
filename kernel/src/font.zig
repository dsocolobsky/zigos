const framebuffer = @import("framebuffer.zig");
const serial = @import("serial.zig");

extern var _binary_tamsyn_psf_start: u8;
extern var _binary_tamsyn_psf_end: u8;

pub const PSF = packed struct {
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

    pub fn getGlyph(self: *PSF, c: u8) [*]u8 {
        const start = @intFromPtr(self) + self.header_size;
        return @ptrFromInt(start + c * self.bytes_per_glyph);
    }

    pub inline fn bytesPerLine(self: *PSF) u32 {
        return (self.width + 7) / 8;
    }
};

pub var psf: *PSF = undefined;

pub fn init() *PSF {
    const addr: usize = @intFromPtr(&_binary_tamsyn_psf_start);
    psf = @ptrFromInt(addr);
    return psf;
}
