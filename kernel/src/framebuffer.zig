const limine = @import("limine");

pub fn clear(framebuffer: *limine.Framebuffer) void {
    fillrect(framebuffer, 255, 255, 255, framebuffer.width, framebuffer.height);
}

pub fn putpixel(framebuffer: *limine.Framebuffer, x: usize, y: usize, color: u24) void {
    const pixelWidth = 4;
    const where = y * framebuffer.pitch + x * pixelWidth;
    framebuffer.address[where + 0] = @as(u8, @truncate(color & 255)); // BLUE
    framebuffer.address[where + 1] = @as(u8, @truncate((color >> 8) & 255)); // GREEN
    framebuffer.address[where + 2] = @as(u8, @truncate((color >> 16) & 255)); // RED
}

pub fn fillrect_naive(framebuffer: *limine.Framebuffer, r: u8, g: u8, b: u8, w: usize, h: usize) void {
    for (0..h) |y| {
        for (0..w) |x| {
            const r24 = @as(u24, r);
            const g24 = @as(u24, g);
            const b24 = @as(u24, b);
            const color: u24 = (r24 << 16) + (g24 << 8) + b24;
            putpixel(framebuffer, 64 + x, 64 + y, color);
        }
    }
}

pub fn fillrect(framebuffer: *limine.Framebuffer, r: u8, g: u8, b: u8, w: usize, h: usize) void {
    var where = framebuffer.address;
    const pixelSize = 4;

    for (0..h) |_| {
        for (0..w) |x| {
            where[x * pixelSize + 0] = r;
            where[x * pixelSize + 1] = g;
            where[x * pixelSize + 2] = b;
        }
        where += framebuffer.pitch;
    }
}
