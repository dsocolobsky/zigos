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

    var usable_pages: usize = 0;
    var reserved_pages: usize = 0;
    var highest_addr: usize = 0;

    serial.puts("[pmm] Memory Map Entries:");
    const entries = memmap_response.entries orelse {
        serial.print_err("memmap_response.entries has null pointer", .{});
        return;
    };

    const entry_count = memmap_response.entry_count;
    serial.println("[pmm] Processing {} memory map entries", .{entry_count});

    // First pass: calculate statistics and find highest address
    for (0..entry_count) |i| {
        const entry = entries[i];
        const entry_end = entry.base + entry.length;

        // Update highest address
        if (entry_end > highest_addr) {
            highest_addr = entry_end;
        }

        // Count pages based on entry type
        const pages_in_entry = div_roundup(entry.length, PAGE_SIZE);

        switch (entry.type) {
            .usable => {
                usable_pages += pages_in_entry;
                serial.println(
                    "[pmm] USABLE: base: 0x{X}, length: 0x{X}, size: {d}Kb, {d}Mb",
                    .{ entry.base, entry.length, entry.length / 1024, entry.length / 1024 / 1024 },
                );
            },
            .bootloader_reclaimable => {
                usable_pages += pages_in_entry;
                serial.println(
                    "[pmm] RECLAIMABLE: base: 0x{X}, length: 0x{X}, size: {d}Kb, {d}Mb",
                    .{ entry.base, entry.length, entry.length / 1024, entry.length / 1024 / 1024 },
                );
            },
            else => {
                reserved_pages += pages_in_entry;
                serial.println(
                    "[pmm] RESERVED({s}): base: 0x{X}, length: 0x{X}, size: {d}Kb, {d}Mb",
                    .{ @tagName(entry.type), entry.base, entry.length, entry.length / 1024, entry.length / 1024 / 1024 },
                );
            },
        }
    }

    // Validate our calculations
    if (highest_addr == 0) {
        serial.print_err("[pmm] No memory found in memory map!", .{});
        return;
    }
    if (usable_pages == 0) {
        serial.print_err("[pmm] No usable memory found!", .{});
        return;
    }

    const highest_page_idx = div_roundup(highest_addr, PAGE_SIZE);
    const bitmap_size = align_up(highest_page_idx / 8, PAGE_SIZE);

    serial.println(
        "[pmm] Highest Address: 0x{X} , Highest Page Index: {d}",
        .{ highest_addr, highest_page_idx },
    );
    serial.println(
        "[pmm] Bitmap size: {d}KB ({d} bytes)",
        .{ bitmap_size / 1024, bitmap_size },
    );
    serial.println(
        "[pmm] Usable memory: {d}MiB ({d} pages)",
        .{ (usable_pages * PAGE_SIZE) / 1024 / 1024, usable_pages },
    );
    serial.println(
        "[pmm] Reserved memory: {d}MiB ({d} pages)",
        .{ (reserved_pages * PAGE_SIZE) / 1024 / 1024, reserved_pages },
    );

    // Find the first usable entry suitable to store the page bitmap
    var bitmap_start: usize = 0;
    var found_space_for_bitmap = false;

    // Second pass: find space for the bitmap in usable memory
    for (0..entry_count) |i| {
        const entry = entries[i];
        // Only use USABLE or BOOTLOADER_RECLAIMABLE memory for the bitmap
        if (entry.type != .usable and entry.type != .bootloader_reclaimable) {
            continue;
        }
        if (entry.length < bitmap_size) {
            continue;
        }

        bitmap_start = offset + entry.base;
        // Modify the entry to reserve space for the bitmap
        entries[i].base += bitmap_size;
        entries[i].length -= bitmap_size;
        found_space_for_bitmap = true;
        serial.println(
            "[pmm] Allocated bitmap in entry {}: start=0x{X}, size={}KB",
            .{ i, bitmap_start, bitmap_size / 1024 },
        );
        break;
    }

    if (!found_space_for_bitmap) {
        serial.print_err("[pmm] Could not find space for bitmap! Need {}KB", .{bitmap_size / 1024});
        return;
    }

    // Validate bitmap allocation
    if (bitmap_start == 0) {
        serial.print_err("[pmm] Invalid bitmap start address!", .{});
        return;
    }

    serial.println(
        "[pmm] Bitmap allocated at: 0x{X}, size: {d}KB",
        .{ bitmap_start, bitmap_size / 1024 },
    );

    // Initialize bitmap with only usable pages (not reserved)
    bitmap = Bitmap.init(bitmap_start, bitmap_size, usable_pages);
    bitmap.set_all_used();
    bitmap.log();

    // Mark all usable regions as free in the bitmap
    for (0..entry_count) |i| {
        const entry = entries[i];
        // Only mark USABLE and BOOTLOADER_RECLAIMABLE memory as free
        if (entry.type != .usable and entry.type != .bootloader_reclaimable) {
            continue;
        }
        if (entry.length == 0) {
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
    const page_addr = bitmap.alloc_page() orelse {
        serial.print_err("[pmm] Out of memory! No free pages available", .{});
        return 0; // Return 0 to indicate failure
    };

    const addr = offset + page_addr;
    serial.println(
        "[pmm] Allocated page at physical: 0x{X}, virtual: 0x{X}",
        .{ page_addr, addr },
    );
    return addr;
}

fn free(address: usize) void {
    if (address == 0) {
        serial.print_err("[pmm] Attempted to free null address!", .{});
        return;
    }
    if (address < offset) {
        serial.print_err("[pmm] Invalid address to free: 0x{X} (below HHDM offset)", .{address});
        return;
    }

    const off = address - offset;
    serial.println(
        "[pmm] Freeing page: virtual 0x{X} -> physical 0x{X}",
        .{ address, off },
    );
    bitmap.free(off);
}
