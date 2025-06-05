const limine = @import("limine");
const serial = @import("serial.zig");
const Bitmap = @import("bitmap.zig").Bitmap;

const PAGE_SIZE = 4096;

pub export var memmap_request = limine.MemoryMapRequest{
    .revision = 1,
};

pub export var hhdm_request = limine.HhdmRequest{
    .revision = 1,
};

inline fn div_roundup(a: usize, b: usize) usize {
    return (a + (b - 1)) / b;
}

inline fn align_up(value: usize, al: usize) usize {
    return div_roundup(value, al) * al;
}

var offset: usize = undefined;
var bitmap: Bitmap = undefined;

pub fn init() void {
    serial.puts("[pmm] init...");
    // Ensure the response from the memmap_request is valid
    const memmap_response = memmap_request.response orelse {
        serial.print_err("[pmm] Limine memmap response is null!", .{});
        return;
    };

    const hhdm_response = hhdm_request.response;
    if (hhdm_response == null) {
        serial.print_err("[pmm] Failed to get hhdm response", .{});
    }

    offset = hhdm_response.?.offset;

    const usable_pages: usize = 0;
    const reserved_pages: usize = 0;
    const highest_addr: usize = 0;

    serial.puts("[pmm] Usable Entries:");
    const entries = memmap_response.entries orelse {
        serial.print_err("memmap_response.entries has null pointer", .{});
        return;
    };
    for (0..32) |i| {
        const entry = entries[i];
        if (entry.length > 0) { // I made this up it was usable before
            serial.println(
                "[pmm] base: 0x{X}, length: 0x{X}, size: {d}Kb, {d}Mb",
                .{ entry.base, entry.length, entry.length / 1024, entry.length / 1024 / 1024 },
            );
        } else {
            serial.println(
                "[pmm] reserved base: 0x{X}, length: 0x{X}",
                .{ entry.base, entry.length },
            );
        }
    }

    const highest_page_idx = div_roundup(highest_addr, PAGE_SIZE);
    const bitmap_size = align_up(highest_page_idx / 8, PAGE_SIZE);

    serial.println(
        "[pmm] Highest Address: 0x{X} , Highest Page Index: {d}",
        .{ highest_addr, highest_page_idx },
    );
    serial.println(
        "[pmm] Usable memory: {any}MiB",
        .{(usable_pages * PAGE_SIZE) / 1024 / 1024},
    );
    serial.println(
        "[pmm] Reserved memory: {any}MiB",
        .{(reserved_pages * PAGE_SIZE) / 1024 / 1024},
    );

    // Find the first entry suitable to store the page bitmap
    var bitmap_start: usize = 0; // Initialize to 0 or another sensible default
    var found_space_for_bitmap = false;
    // Iterate again to find space for the bitmap
    // It's important to use a fresh iteration or ensure the previous one didn't modify entries in a way that affects this search
    for (0..32) |i| {
        const entry = entries[i];
        if (entry.length <= 0) {
            continue;
        }
        if (entry.length >= bitmap_size) {
            bitmap_start = offset + entry.base;
            entry.base += bitmap_size;
            entry.length -= bitmap_size;
            found_space_for_bitmap = true;
            break;
        }
    }

    if (!found_space_for_bitmap) {
        serial.print_err("[pmm] did not find space for the bitmap!", .{});
        return;
    }
    serial.println(
        "[pmm] Bitmap starts at: 0x{X} , has size of {d} Kb.",
        .{ bitmap_start, bitmap_size / 1024 },
    );

    const total_pages = usable_pages + reserved_pages;
    bitmap = Bitmap.init(bitmap_start, bitmap_size, total_pages);
    bitmap.set_all_used();
    bitmap.log();

    // Mark all available regions as free in the bitmap
    for (0..32) |i| {
        const entry = entries[i];
        if (entry.length <= 0) {
            continue;
        }
        serial.println(
            "[pmm] Marking range: 0x{X} of {d} bytes as free",
            .{ entry.base, entry.length },
        );
        bitmap.clear_range(entry.base, entry.length);
    }
    bitmap.log();

    sanity_test();
}

fn sanity_test() void {
    const prev_total: usize = bitmap.total_pages;
    const prev_free: usize = bitmap.free_pages;
    const prev_used: usize = bitmap.used_pages;
    serial.println(
        "[pmm] Performing sanity test, prev total pages: {}, prev free pages: {}, prev used pages: {}",
        .{ bitmap.total_pages, bitmap.free_pages, bitmap.used_pages },
    );
    serial.puts("[pmm] Asking for 4 pages...");
    const p1: usize = alloc_page();
    const p2: usize = alloc_page();
    const p3: usize = alloc_page();
    const p4: usize = alloc_page();
    if ((bitmap.total_pages != prev_total) or (bitmap.free_pages != (prev_free - 4)) or
        (bitmap.used_pages != (prev_used + 4)))
    {
        serial.print_err("[pmm] Mismatch detected! total: {}, free: {}, used: {}", .{
            bitmap.total_pages,
            bitmap.free_pages,
            bitmap.used_pages,
        });
    } else {
        serial.puts("First thing ok ");
    }
    free(p4);
    free(p2);
    free(p1);
    free(p3);
    if (bitmap.total_pages != prev_total or (bitmap.free_pages != prev_free) or
        (bitmap.used_pages != prev_used))
    {
        serial.print_err(
            "[pmm] Mismatch detected after free! total: {}, free: {}, used: {}",
            .{ bitmap.total_pages, bitmap.free_pages, bitmap.used_pages },
        );
    } else {
        serial.puts("[pmm] Sanity test OK");
    }
}

/// Returns the first available 4Kb page
pub fn alloc_page() usize {
    const addr = offset + bitmap.alloc_page().?;
    serial.println(
        "[pmm] Returning page starting at 0x{X}",
        .{addr},
    );
    return addr;
}

fn free(address: usize) void {
    const off = address - offset;
    serial.println(
        "[pmm] Freeing page for 0x{X} offset 0x{X}",
        .{ address, off },
    );
    bitmap.free(off);
}
