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

pub fn print(str: []const u8) void {
    asm volatile ("movw $0x3f8, %dx");

    for (str) |c| {
        putchar(c);
    }
}

pub fn println(str: []const u8) void {
    print(str);

    putchar('\n');
    putchar(0x0);
}
