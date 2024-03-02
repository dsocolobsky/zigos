pub const Framebuffer = @This();
const limine = @import("limine");
const serial = @import("serial.zig");

pub var global_framebuffer: Framebuffer = undefined;
var tick_color_index: usize = 0;

framebuffer: *limine.Framebuffer = undefined,

pub export var framebuffer_request: limine.FramebufferRequest = .{};

const PIXEL_SIZE: usize = 4;

pub const COLOR_RED = Color{ .r = 255, .g = 0, .b = 0 };
pub const COLOR_GREEN = Color{ .r = 0, .g = 255, .b = 0 };
pub const COLOR_BLUE = Color{ .r = 0, .g = 0, .b = 255 };
pub const COLOR_BLACK = Color{ .r = 0, .g = 0, .b = 0 };
pub const COLOR_WHITE = Color{ .r = 255, .g = 255, .b = 255 };

pub const colors = [3]Color{
    COLOR_RED,
    COLOR_GREEN,
    COLOR_BLUE,
};

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

pub fn clear(self: Framebuffer) void {
    self.fillrect(
        COLOR_WHITE,
        .{ .width = self.framebuffer.width, .height = self.framebuffer.height },
    );
}

pub fn putpixel(self: Framebuffer, pos: Position, color: u24) void {
    const pixelWidth = 4;
    const where = pos.y * self.framebuffer.pitch + pos.x * pixelWidth;
    self.framebuffer.address[where + 0] = @as(u8, @truncate(color & 255)); // BLUE
    self.framebuffer.address[where + 1] = @as(u8, @truncate((color >> 8) & 255)); // GREEN
    self.framebuffer.address[where + 2] = @as(u8, @truncate((color >> 16) & 255)); // RED
}

pub fn fillrect(self: Framebuffer, color: Color, size: Size) void {
    var where = self.framebuffer.address;

    for (0..size.height) |_| {
        for (0..size.width) |x| {
            where[x * PIXEL_SIZE + 0] = color.r;
            where[x * PIXEL_SIZE + 1] = color.g;
            where[x * PIXEL_SIZE + 2] = color.b;
        }
        where += self.framebuffer.pitch;
    }
}

pub fn update_panel(self: Framebuffer) void {
    self.fillrect(
        colors[tick_color_index],
        .{ .width = 256, .height = 32 },
    );
    tick_color_index = (tick_color_index + 1) % colors.len;
}

pub fn init() void {
    if (framebuffer_request.response) |framebuffer_response| {
        if (framebuffer_response.framebuffer_count < 1) {
            serial.print_err("Error initializing framebuffer", .{});
        }

        const framebuffer = Framebuffer{
            .framebuffer = framebuffer_response.framebuffers()[0],
        };

        framebuffer.clear();
        framebuffer.update_panel();

        global_framebuffer = framebuffer;
    }
}
