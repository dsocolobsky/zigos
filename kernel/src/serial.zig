const std = @import("std");

pub fn initialize() void {
    return asm volatile (
        \\ .equ PORT, 0x3f8
        \\ init_serial:
        \\ movb $0x00, %al
        \\ movw $PORT + 1, %dx
        \\ outb %al, (%dx)
        \\ movb $0x80, %al
        \\ movw $PORT + 3, %dx
        \\ outb %al, (%dx)
        \\ movb $0x03, %al
        \\ movw $PORT, %dx
        \\ outb %al, (%dx)
        \\ movb $0x00, %al
        \\ movw $PORT + 1, %dx
        \\ outb %al, (%dx)
        \\ movb $0x03, %al
        \\ movw $PORT + 3, %dx
        \\ outb %al, (%dx)
        \\ movb $0xC7, %al
        \\ movw $PORT + 2, %dx
        \\ outb %al, (%dx)
        \\ movb $0x0B, %al
        \\ movw $PORT + 4, %dx
        \\ outb %al, (%dx)
        \\ movb $0x1E, %al
        \\ movw $PORT + 4, %dx
        \\ outb %al, (%dx)
        \\ movb $0xAE, %al
        \\ movw $PORT, %dx
        \\ outb %al, (%dx)
        \\ movw $PORT, %dx
        \\ inb (%dx), %al
        \\ movb $0x0F, %al
        \\ movw $PORT + 4, %dx
        \\ outb %al, (%dx)
        \\ movl $0, %eax
    );
}

pub fn putchar(c: u8) void {
    asm volatile ("outb %al, (%dx)"
        :
        : [c] "{al}" (c),
    );
}

pub fn newline() void {
    putchar('\n');
}

pub fn print(str: []const u8) void {
    asm volatile ("movw $0x3f8, %dx");

    for (str) |c| {
        putchar(c);
    }
}

pub fn println(str: []const u8) void {
    print(str);
    newline();
}

pub fn print_hex(n: u64) void {
    var buffer: [24]u8 = undefined;
    const buf = buffer[0..];
    const str = std.fmt.bufPrintIntToSlice(
        buf,
        n,
        16,
        .lower,
        std.fmt.FormatOptions{},
    );
    asm volatile ("movw $0x3f8, %dx");
    putchar('0');
    putchar('x');
    print(str);
}

pub fn print_dec(n: u64) void {
    var buffer: [24]u8 = undefined;
    const buf = buffer[0..];
    const str = std.fmt.bufPrintIntToSlice(
        buf,
        n,
        10,
        .lower,
        std.fmt.FormatOptions{},
    );
    asm volatile ("movw $0x3f8, %dx");
    print(str);
}
