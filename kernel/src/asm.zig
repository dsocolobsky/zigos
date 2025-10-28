pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[value]"
        : [value] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

pub inline fn iowait() void {
    _ = inb(0x80);
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn hlt() void {
    asm volatile ("hlt");
}

pub inline fn magic_breakpoint() void {
    return asm volatile ("xchgw %bx, %bx");
}

pub inline fn read_cr3() u64 {
    return asm volatile ("mov %cr3, %rax"
        : [value] "={rax}" (-> u64),
    );
}

pub inline fn write_cr3(value: u64) void {
    asm volatile ("mov %rax, %cr3"
        :
        : [value] "{rax}" (value),
        : "memory"
    );
}

pub inline fn read_cr2() u64 {
    return asm volatile ("mov %cr2, %rax"
        : [value] "={rax}" (-> u64),
    );
}
