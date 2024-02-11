const limine = @import("limine");

const PIXEL_SIZE: usize = 4;

pub const COLOR_RED = Color{ .r = 255, .g = 0, .b = 0 };
pub const COLOR_GREEN = Color{ .r = 0, .g = 255, .b = 0 };
pub const COLOR_BLUE = Color{ .r = 0, .g = 0, .b = 255 };
pub const COLOR_BLACK = Color{ .r = 0, .g = 0, .b = 0 };
pub const COLOR_WHITE = Color{ .r = 255, .g = 255, .b = 255 };

pub const Position = struct {
    x: usize,
    y: usize,
};

pub const Size = struct {
    width: usize,
    height: usize,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub fn clear(framebuffer: *limine.Framebuffer) void {
    fillrect(
        framebuffer,
        COLOR_WHITE,
        .{ .width = framebuffer.width, .height = framebuffer.height },
    );
}

pub fn putpixel(framebuffer: *limine.Framebuffer, pos: Position, color: u24) void {
    const pixelWidth = 4;
    const where = pos.y * framebuffer.pitch + pos.x * pixelWidth;
    framebuffer.address[where + 0] = @as(u8, @truncate(color & 255)); // BLUE
    framebuffer.address[where + 1] = @as(u8, @truncate((color >> 8) & 255)); // GREEN
    framebuffer.address[where + 2] = @as(u8, @truncate((color >> 16) & 255)); // RED
}

pub fn fillrect(framebuffer: *limine.Framebuffer, color: Color, size: Size) void {
    var where = framebuffer.address;

    for (0..size.height) |_| {
        for (0..size.width) |x| {
            where[x * PIXEL_SIZE + 0] = color.r;
            where[x * PIXEL_SIZE + 1] = color.g;
            where[x * PIXEL_SIZE + 2] = color.b;
        }
        where += framebuffer.pitch;
    }
}
