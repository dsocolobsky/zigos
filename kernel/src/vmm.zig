const std = @import("std");
const serial = @import("serial.zig");
const pmm = @import("pmm.zig");
const limine = @import("limine");

/// Size of a page in bytes. Usually will be 4Kb
const PAGE_SIZE = 4096;
/// Number of page entries in the main page table
const PAGE_ENTRIES = 512;

// Virtual memory layout constants
pub const KERNEL_BASE: u64 = 0xFFFF800000000000;
pub const USER_BASE: u64 = 0x0000000000000000;
pub const USER_LIMIT: u64 = 0x00007FFFFFFFFFFF;

// Page entry flags for x86_64
pub const PageFlags = packed struct(u64) {
    present: bool = false,
    writable: bool = false,
    user_accessible: bool = false,
    write_through: bool = false,
    cache_disabled: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    huge_page: bool = false,
    global: bool = false,
    available1: u3 = 0,
    address: u40 = 0,
    available2: u11 = 0,
    no_execute: bool = false,

    pub fn init(phys_addr: u64, flags: struct {
        writable: bool = false,
        user_accessible: bool = false,
        write_through: bool = false,
        cache_disabled: bool = false,
        global: bool = false,
        no_execute: bool = false,
    }) PageFlags {
        return PageFlags{
            .present = true,
            .writable = flags.writable,
            .user_accessible = flags.user_accessible,
            .write_through = flags.write_through,
            .cache_disabled = flags.cache_disabled,
            .global = flags.global,
            .no_execute = flags.no_execute,
            .address = @truncate(phys_addr >> 12),
        };
    }

    pub fn get_address(self: PageFlags) u64 {
        return @as(u64, self.address) << 12;
    }
};

/// Page table structure (512 entries, 4KB aligned)
pub const PageTable = struct {
    /// page-aligned array of PAGE_ENTRIES page flag entries, each initialized to an empty PageFlags{}
    entries: [PAGE_ENTRIES]PageFlags align(PAGE_SIZE) = [_]PageFlags{PageFlags{}} ** PAGE_ENTRIES,

    const Self = @This();

    pub fn clear(self: *Self) void {
        @memset(&self.entries, PageFlags{});
    }

    pub fn get_entry(self: *Self, index: usize) *PageFlags {
        return &self.entries[index];
    }
};

// Address space structure representing a virtual memory context
pub const AddressSpace = struct {
    pml4: *PageTable,

    const Self = @This();

    pub fn init() !Self {
        const pml4_phys = pmm.alloc_page();
        if (pml4_phys == 0) {
            return error.OutOfMemory;
        }

        const pml4: *PageTable = @ptrFromInt(pml4_phys);
        pml4.clear();

        return AddressSpace{
            .pml4 = pml4,
        };
    }

    pub fn get_pml4_phys(self: *Self) u64 {
        return @intFromPtr(self.pml4) - kernel_hhdm_offset;
    }
};

/// Global kernel address space
var kernel_address_space: AddressSpace = undefined;
var kernel_hhdm_offset: u64 = undefined;

// Helper functions for address manipulation
inline fn align_down(addr: u64, alignment: u64) u64 {
    return addr & ~(alignment - 1);
}

inline fn align_up(addr: u64, alignment: u64) u64 {
    return align_down(addr + alignment - 1, alignment);
}

/// Get the Page Map Level 4 index given the virtual address
inline fn get_pml4_index(virt_addr: u64) u9 {
    return @truncate((virt_addr >> 39) & 0x1FF);
}

/// Get the Page Directory Pointer Table index given the virtual address
inline fn get_pdpt_index(virt_addr: u64) u9 {
    return @truncate((virt_addr >> 30) & 0x1FF);
}

/// Get the Page Directory index given the virtual address
inline fn get_pd_index(virt_addr: u64) u9 {
    return @truncate((virt_addr >> 21) & 0x1FF);
}

/// Get the Page Table index given the virtual address
inline fn get_pt_index(virt_addr: u64) u9 {
    return @truncate((virt_addr >> 12) & 0x1FF);
}

/// Attempt to allocate a Page Table
fn allocate_page_table() !*PageTable {
    const phys_addr = pmm.alloc_page();
    if (phys_addr == 0) {
        return error.OutOfMemory;
    }

    const page_table: *PageTable = @ptrFromInt(phys_addr);
    page_table.clear();

    serial.println("[vmm] Allocated page table at 0x{X}", .{phys_addr});
    return page_table;
}

/// Get or create a page table entry. May throw if we're OOM
fn get_or_create_table(parent_table: *PageTable, index: u9, flags: struct {
    writable: bool = true,
    user_accessible: bool = false,
}) !*PageTable {
    const entry = parent_table.get_entry(index);

    if (entry.present) {
        const phys_addr = entry.get_address();
        return @ptrFromInt(phys_addr + kernel_hhdm_offset);
    }

    // Allocate new page table
    const new_table = try allocate_page_table();
    const phys_addr = @intFromPtr(new_table) - kernel_hhdm_offset;

    entry.* = PageFlags.init(phys_addr, .{
        .writable = flags.writable,
        .user_accessible = flags.user_accessible,
    });

    return new_table;
}

/// Map a single page
pub fn map_page(address_space: *AddressSpace, virt_addr: u64, phys_addr: u64, flags: struct {
    writable: bool = false,
    user_accessible: bool = false,
    write_through: bool = false,
    cache_disabled: bool = false,
    global: bool = false,
    no_execute: bool = false,
}) !void {
    const virt_aligned = align_down(virt_addr, PAGE_SIZE);
    const phys_aligned = align_down(phys_addr, PAGE_SIZE);

    const pml4_idx = get_pml4_index(virt_aligned);
    const pdpt_idx = get_pdpt_index(virt_aligned);
    const pd_idx = get_pd_index(virt_aligned);
    const pt_idx = get_pt_index(virt_aligned);

    // Walk through page table hierarchy, creating tables as needed
    const pdpt = try get_or_create_table(address_space.pml4, pml4_idx, .{
        .writable = true,
        .user_accessible = flags.user_accessible,
    });

    const pd = try get_or_create_table(pdpt, pdpt_idx, .{
        .writable = true,
        .user_accessible = flags.user_accessible,
    });

    const pt = try get_or_create_table(pd, pd_idx, .{
        .writable = true,
        .user_accessible = flags.user_accessible,
    });

    // Set the final page table entry
    const page_entry = pt.get_entry(pt_idx);
    page_entry.* = PageFlags.init(phys_aligned, .{
        .writable = flags.writable,
        .user_accessible = flags.user_accessible,
        .write_through = flags.write_through,
        .cache_disabled = flags.cache_disabled,
        .global = flags.global,
        .no_execute = flags.no_execute,
    });

    // log every 1024 pages or so because else there's just way too many logs
    if ((virt_aligned & 0x3FF000) == 0) {
        serial.println("[vmm] Mapped 0x{X} -> 0x{X}", .{ virt_aligned, phys_aligned });
    }
}

/// Unmap a single page, clearing it's entry in the Page Table and invalidating the TLB cache
pub fn unmap_page(address_space: *AddressSpace, virt_addr: u64) void {
    const virt_aligned = align_down(virt_addr, PAGE_SIZE);

    if (get_pt_entry_from_virt_address(address_space, virt_addr)) |pt_entry| {
        pt_entry.* = PageFlags{};
        invalidate_page(virt_aligned);

        serial.println("[vmm] Unmapped 0x{X}", .{virt_aligned});
    }
}

/// Get physical address for a virtual address
pub fn get_physical_address(address_space: *AddressSpace, virt_addr: u64) ?u64 {
    const virt_aligned = align_down(virt_addr, PAGE_SIZE);
    const offset = virt_addr & 0xFFF;

    if (get_pt_entry_from_virt_address(address_space, virt_aligned)) |pt_entry| {
        return pt_entry.get_address() + offset;
    }

    return null;
}

/// Walks the table hierarchy and returns the page table entry for a given virtual address (previously aligned)
fn get_pt_entry_from_virt_address(address_space: *AddressSpace, virt_aligned: u64) ?*PageFlags {
    const pml4_idx = get_pml4_index(virt_aligned);
    const pdpt_idx = get_pdpt_index(virt_aligned);
    const pd_idx = get_pd_index(virt_aligned);
    const pt_idx = get_pt_index(virt_aligned);

    const pml4_entry = address_space.pml4.get_entry(pml4_idx);
    if (!pml4_entry.present) return null;

    const pdpt: *PageTable = @ptrFromInt(pml4_entry.get_address() + kernel_hhdm_offset);
    const pdpt_entry = pdpt.get_entry(pdpt_idx);
    if (!pdpt_entry.present) return null;

    const pd: *PageTable = @ptrFromInt(pdpt_entry.get_address() + kernel_hhdm_offset);
    const pd_entry = pd.get_entry(pd_idx);
    if (!pd_entry.present) return null;

    const pt: *PageTable = @ptrFromInt(pd_entry.get_address() + kernel_hhdm_offset);
    const pt_entry = pt.get_entry(pt_idx);
    if (!pt_entry.present) return null;

    return pt_entry;
}

/// Map a range of pages from virt_start->phys_start, size in bytes number of pages.
pub fn map_range(address_space: *AddressSpace, virt_start: u64, phys_start: u64, size: u64, flags: struct {
    writable: bool = false,
    user_accessible: bool = false,
    write_through: bool = false,
    cache_disabled: bool = false,
    global: bool = false,
    no_execute: bool = false,
}) !void {
    const virt_aligned = align_down(virt_start, PAGE_SIZE);
    const phys_aligned = align_down(phys_start, PAGE_SIZE);
    const size_aligned = align_up(size, PAGE_SIZE);
    const pages = size_aligned / PAGE_SIZE;

    serial.println("[vmm] Mapping range: 0x{X} -> 0x{X}, {} pages", .{ virt_aligned, phys_aligned, pages });

    var i: u64 = 0;
    while (i < pages) : (i += 1) {
        const virt_addr = virt_aligned + (i * PAGE_SIZE);
        const phys_addr = phys_aligned + (i * PAGE_SIZE);

        try map_page(address_space, virt_addr, phys_addr, .{
            .writable = flags.writable,
            .user_accessible = flags.user_accessible,
            .write_through = flags.write_through,
            .cache_disabled = flags.cache_disabled,
            .global = flags.global,
            .no_execute = flags.no_execute,
        });
    }
}

// Identity map a range (virtual address = physical address)
pub fn identity_map_range(address_space: *AddressSpace, start: u64, size: u64, flags: struct {
    writable: bool = false,
    user_accessible: bool = false,
    write_through: bool = false,
    cache_disabled: bool = false,
    global: bool = false,
    no_execute: bool = false,
}) !void {
    try map_range(address_space, start, start, size, flags);
}

// TLB invalidation
inline fn invalidate_page(virt_addr: u64) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (virt_addr),
        : "memory"
    );
}

pub fn flush_tlb() void {
    asm volatile ("mov %cr3, %rax; mov %rax, %cr3" ::: "rax", "memory");
}

// Initialize VMM
pub fn init() !void {
    serial.puts("[vmm] Initializing Virtual Memory Manager...");

    // Get HHDM offset from Limine
    const hhdm_response = @import("pmm.zig").hhdm_request.response orelse {
        serial.print_err("[vmm] Failed to get HHDM response", .{});
        return error.NoHHDM;
    };

    kernel_hhdm_offset = hhdm_response.offset;
    serial.println("[vmm] HHDM offset: 0x{X}", .{kernel_hhdm_offset});

    kernel_address_space = try AddressSpace.init();
    serial.println("[vmm] Created kernel address space with PML4 at 0x{X}", .{@intFromPtr(kernel_address_space.pml4)});

    try setup_kernel_mappings();
    try sanity_test();

    serial.puts("[vmm] VMM initialization complete");
}

/// Set up kernel virtual memory mappings
fn setup_kernel_mappings() !void {
    // NOTE: Limine already provides HHDM mapping, so we don't need to recreate it

    // TODO: Map kernel code/data sections when we switch to our own page tables
    // TODO: Map framebuffer when needed
    // TODO: Map any other essential kernel resources
    serial.puts("[vmm] Minimal kernel mappings complete");
}

// VMM sanity test
fn sanity_test() !void {
    serial.puts("[vmm] Performing sanity test...");

    // Test 1: Map a few test pages and verify they can be mapped/unmapped
    const test_virt_base: u64 = 0x0000100000000000; // Test virtual address
    const test_pages = 4;

    // Allocate physical pages for testing
    var test_phys_pages: [test_pages]u64 = undefined;
    for (0..test_pages) |i| {
        test_phys_pages[i] = pmm.alloc_page();
        if (test_phys_pages[i] == 0) {
            serial.print_err("[vmm] Failed to allocate test page {}", .{i});
            return;
        }
        // Convert to physical address (remove HHDM offset)
        test_phys_pages[i] -= kernel_hhdm_offset;
    }

    serial.println("[vmm] Allocated {} test pages", .{test_pages});

    // Test 2: Map the pages
    for (0..test_pages) |i| {
        const virt_addr = test_virt_base + (i * PAGE_SIZE);
        const phys_addr = test_phys_pages[i];

        try map_page(&kernel_address_space, virt_addr, phys_addr, .{
            .writable = true,
        });

        serial.println("[vmm] Test mapped: 0x{X} -> 0x{X}", .{ virt_addr, phys_addr });
    }

    // Test 3: Verify virtual-to-physical translation
    for (0..test_pages) |i| {
        const virt_addr = test_virt_base + (i * PAGE_SIZE);
        const expected_phys = test_phys_pages[i];

        const actual_phys = get_physical_address(&kernel_address_space, virt_addr);
        if (actual_phys == null) {
            serial.print_err("[vmm] Translation failed for 0x{X}", .{virt_addr});
            return;
        }

        if (actual_phys.? != expected_phys) {
            serial.print_err("[vmm] Translation mismatch: 0x{X} -> expected 0x{X}, got 0x{X}", .{ virt_addr, expected_phys, actual_phys.? });
            return;
        }

        serial.println("[vmm] Translation OK: 0x{X} -> 0x{X}", .{ virt_addr, actual_phys.? });
    }

    // Test 4: Test range mapping
    const range_virt_base: u64 = 0x0000200000000000;
    const range_size = PAGE_SIZE * 2;
    const range_phys = pmm.alloc_page();
    if (range_phys == 0) {
        serial.print_err("[vmm] Failed to allocate range test page", .{});
        return;
    }
    const range_phys_addr = range_phys - kernel_hhdm_offset;

    try map_range(&kernel_address_space, range_virt_base, range_phys_addr, range_size, .{
        .writable = true,
    });

    // Verify range mapping
    for (0..2) |i| {
        const virt_addr = range_virt_base + (i * PAGE_SIZE);
        const expected_phys = range_phys_addr + (i * PAGE_SIZE);

        const actual_phys = get_physical_address(&kernel_address_space, virt_addr);
        if (actual_phys == null or actual_phys.? != expected_phys) {
            serial.print_err("[vmm] Range mapping failed at page {}", .{i});
            return;
        }
    }
    serial.puts("[vmm] Range mapping test OK");

    // Test 5: Unmap pages and verify they're gone
    for (0..test_pages) |i| {
        const virt_addr = test_virt_base + (i * PAGE_SIZE);
        unmap_page(&kernel_address_space, virt_addr);

        const phys_after_unmap = get_physical_address(&kernel_address_space, virt_addr);
        if (phys_after_unmap != null) {
            serial.print_err("[vmm] Page still mapped after unmap: 0x{X}", .{virt_addr});
            return;
        }
    }
    serial.puts("[vmm] Unmap test OK");

    // Clean up range mapping
    unmap_page(&kernel_address_space, range_virt_base);
    unmap_page(&kernel_address_space, range_virt_base + PAGE_SIZE);

    serial.puts("[vmm] Sanity test PASSED");
}

// Get the kernel address space
pub fn get_kernel_address_space() *AddressSpace {
    return &kernel_address_space;
}
