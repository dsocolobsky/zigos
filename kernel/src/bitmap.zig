const std = @import("std");
const serial = @import("serial.zig");

const PAGE_SIZE = 4096;

inline fn bit_is_set(n: u8, bit: u8) bool {
    return (n & (@as(u8, 1) << @intCast(bit))) != 0;
}

inline fn set_bit(n: *u8, bit: u8) void {
    n.* |= (@as(u8, 1) << @intCast(bit));
}

inline fn clear_bit(n: *u8, bit: u8) void {
    n.* &= ~(@as(u8, 1) << @intCast(bit));
}

inline fn div_roundup(a: usize, b: usize) usize {
    return (a + (b - 1)) / b;
}

inline fn page_index_for_addr(addr: usize) usize {
    return @divFloor(addr, PAGE_SIZE);
}

inline fn map_index_for_page(page_index: usize) usize {
    return div_roundup(page_index, 8);
}

pub const Bitmap = struct {
    total_pages: usize = 0,
    free_pages: usize = 0,
    used_pages: usize = 0,
    size: usize = 0,
    map: [*]u8 = undefined,

    const Self = @This();

    pub fn init(start_of_map: usize, size: usize, total_pages: usize) Bitmap {
        return Bitmap{
            .total_pages = total_pages,
            .free_pages = total_pages,
            .used_pages = 0,
            .size = size,
            .map = @ptrFromInt(start_of_map),
        };
    }

    pub fn log(self: *const Self) void {
        serial.print("[bitmap] total_pages: {d} ({d}Mb)\n" ++
            "[bitmap] free_pages: {d} ({d}Mb)\n" ++
            "[bitmap] used_pages: {d} ({d}Mb)\n" ++
            "[bitmap] Bitmap size: {d}b , {d}kb\n", .{
            self.total_pages,
            self.total_pages * 4 / 1024,
            self.free_pages,
            self.free_pages * 4 / 1024,
            self.used_pages,
            self.used_pages * 4 / 1024,
            self.size,
            self.size / 1024,
        });
    }

    /// Sets all entries to used
    pub fn set_all_used(self: *Self) void {
        @memset(self.map[0..self.size], 0xFF);
        self.free_pages = 0;
        self.used_pages = self.total_pages;
    }

    /// Sets a range of memory (in usize) marking it as unavailable with 0xFF
    pub fn set_used_range(self: *Self, start_addr: usize, size: usize) void {
        self.set_range_to(start_addr, size, 0xFF);
    }

    /// Clears a range of memory (in usize) marking it as available with 0x00
    pub fn clear_range(self: *Self, start_addr: usize, size: usize) void {
        self.set_range_to(start_addr, size, 0x00);
    }

    /// Sets a range of memory (in usize) to a certain value (0x00 or 0xFF)
    fn set_range_to(self: *Self, start_addr: usize, size: usize, value: u8) void {
        const num_pages = @divFloor(size, PAGE_SIZE);
        const start_page = @divFloor(start_addr, PAGE_SIZE);
        const byte_index = @divFloor(start_page, 8);
        const num_bytes = @divFloor(num_pages, 8);
        serial.println(
            "[bitmap] Setting {d} pages from page #{d} byte index #{d} total {d} bytes",
            .{ num_pages, start_page, byte_index, num_bytes },
        );
        self.map[byte_index] = value;
        //@memset(self.map[byte_index .. byte_index + 1], value);
        if (value == 0x00) {
            self.free_pages +|= num_pages;
            self.used_pages -|= num_pages;
        } else {
            self.used_pages +|= num_pages;
            self.free_pages -|= num_pages;
        }
    }

    /// Returns a single 4Kb page
    pub fn alloc_page(self: *Self) ?usize {
        if (self.free_pages < 1) {
            serial.print_err("[bitmap] failed to get free page", .{});
            return null;
        }
        var byte_index: usize = 0;
        while (byte_index < self.total_pages / 8) : (byte_index += 1) {
            var b: *u8 = &self.map[byte_index];
            if (b.* & 0xFF == 0xFF) continue;

            // Found a byte with at least 1 page (bit) clear
            var bit_index: u8 = 0;
            while (bit_index < 8) : (bit_index += 1) {
                if (!bit_is_set(b.*, bit_index)) {
                    const page_num = byte_index * 8 + bit_index;
                    const addr: usize = page_num * PAGE_SIZE;
                    serial.println(
                        "[bitmap] returning page #{d} at addr 0x{X}",
                        .{ page_num, addr },
                    );
                    set_bit(b, bit_index);
                    self.free_pages -= 1;
                    self.used_pages += 1;
                    return addr;
                }
            }
        }
        serial.print_err("[bitmap] failed to get free page", .{});
        return null;
    }

    /// Frees a page given an address. This will free the entire page.
    pub fn free(self: *Self, address: usize) void {
        const page = page_index_for_addr(address);
        self.free_page(page);
    }

    /// Frees a page given the page number
    pub fn free_page(self: *Self, page: usize) void {
        const byte = self.map_byte_for_page(page);
        const bit_index: u8 = @as(u8, @truncate(page % 8));
        serial.println(
            "[bitmap] Freeing page #{d} at byte {d} bit {d}",
            .{ page, byte, bit_index },
        );
        clear_bit(byte, bit_index);
        self.free_pages += 1;
        self.used_pages -= 1;
    }

    inline fn map_byte_for_page(self: *Self, page_index: usize) *u8 {
        return &self.map[map_index_for_page(page_index)];
    }
};
