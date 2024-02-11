const limine = @import("limine");

pub fn clear(framebuffer: *limine.Framebuffer) void {
    for (0..framebuffer.width) |w| {
        for (0..framebuffer.height) |h| {
            // Calculate the pixel offset using the framebuffer information we obtained above.
            // We skip `h` scanlines (pitch is provided in bytes) and add `w * 4` to skip `w` pixels forward.
            const pixel_offset = h * framebuffer.pitch + w * 4;

            // Write 0xFFFFFFFF to the provided pixel offset to fill it white.
            @as(*u32, @ptrCast(@alignCast(framebuffer.address + pixel_offset))).* = 0xFFFFFFFF;
        }
    }
}

pub fn putpixel(framebuffer: *limine.Framebuffer, x: usize, y: usize, color: u32) void {
    const pixelWidth = framebuffer.bpp;
    const where = x * pixelWidth + y * framebuffer.pitch;
    framebuffer.address[where] = @as(u8, @truncate(color & 255)); // BLUE
    framebuffer.address[where + 1] = @as(u8, @truncate((color >> 8) & 255)); // GREEN
    framebuffer.address[where + 2] = @as(u8, @truncate((color >> 16) & 255)); // RED
}

pub fn fillrect_naive(framebuffer: *limine.Framebuffer, r: u8, g: u8, b: u8, w: u8, h: u8) void {
    for (0..w) |i| {
        for (0..h) |j| {
            const r32 = @as(u32, r);
            const g32 = @as(u32, g);
            const b32 = @as(u32, b);
            const color: u32 = (r32 << 16) + (g32 << 8) + b32;
            putpixel(framebuffer, 64 + j, 64 + i, color);
        }
    }
}

pub fn fillrect(framebuffer: *limine.Framebuffer, r: u8, g: u8, b: u8, w: u8, h: u8) void {
    var where = framebuffer.address;
    const pixelSize = framebuffer.bpp;

    for (0..w) |_| {
        for (0..h) |j| {
            where[j * pixelSize] = r;
            where[j * pixelSize + 1] = g;
            where[j * pixelSize + 2] = b;
        }
        where += framebuffer.pitch;
    }
}
