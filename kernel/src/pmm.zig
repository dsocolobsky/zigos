const limine = @import("limine");
const serial = @import("serial.zig");
const stdheap = @import("std").heap;

const PAGE_SIZE = 4096;

pub export var memmap_request = limine.MemoryMapRequest{
    .revision = 1,
};

pub export var hhdm_request = limine.HhdmRequest{
    .revision = 1,
};

inline fn max(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

inline fn div_roundup(a: usize, b: usize) usize {
    return (a + (b - 1)) / b;
}

pub fn init() void {
    const memmap_response = memmap_request.response.?;
    //if (memmap_response == 0) {
    //    serial.print_err("Failed to get remmap response", .{});
    //}

    const hhdm_response = hhdm_request.response;
    if (hhdm_response == null) {
        serial.print_err("[pmm] Failed to get hhdm response", .{});
    }

    var usable_pages: usize = 0;
    var reserved_pages: usize = 0;
    var highest_addr: usize = 0;

    serial.puts("[pmm] Usable Entries:");
    for (memmap_response.entries()) |entry| {
        if (entry.kind == limine.MemoryMapEntryType.usable) {
            usable_pages += div_roundup(entry.length, PAGE_SIZE);
            highest_addr += max(highest_addr, entry.base + entry.length);
            serial.println(
                "[pmm] base: 0x{X}, length: 0x{X}, size: {d}Kb, {d}Mb",
                .{ entry.base, entry.length, entry.length / 1024, entry.length / 1024 / 1024 },
            );
        } else {
            reserved_pages += div_roundup(entry.length, PAGE_SIZE);
        }
    }

    const highest_page_idx = highest_addr / PAGE_SIZE;

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

    const FREELIST_RESERVED_SIZE = 1024;
    var freelist_start: usize = undefined;

    for (memmap_response.entries()) |entry| {
        if (entry.kind != limine.MemoryMapEntryType.usable) {
            continue;
        }

        // Allocate the freelist in the first 1Kb of the first usable page
        if (entry.length >= FREELIST_RESERVED_SIZE) {
            freelist_start = entry.base;
            entry.base += FREELIST_RESERVED_SIZE;
            entry.length -= FREELIST_RESERVED_SIZE;
            break;
        }

        serial.print_err("[pmm] did not find space for the freelist!", .{});
        return;
    }
    serial.println(
        "[pmm] Freelist starts at: 0x{X} , has size of {d} bytes.",
        .{ freelist_start, FREELIST_RESERVED_SIZE },
    );
}
