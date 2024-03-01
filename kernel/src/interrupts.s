[bits 64]

%macro push_all 0
        push rax
        push rbx
        push rcx
        push rdx
        push rsi
        push rdi
        push rbp
        push r15
        push r14
        push r13
        push r12
        push r11
        push r10
        push r9
        push r8
        xor rax, rax
        mov rax, gs
        push rax
        xor rax, rax
        mov rax, fs
        push rax
        xor rax, rax
        mov rax, es
        push rax
        xor rax, rax
        mov rax, ds
        push rax
%endmacro

%macro pop_all 0
        pop rax
        mov ds, rax
        pop rax
        mov es, rax
        pop rax
        mov fs, rax
        pop rax
        mov gs, rax
        pop r8
        pop r9
        pop r10
        pop r11
        pop r12
        pop r13
        pop r14
        pop r15
        pop rbp
        pop rdi
        pop rsi
        pop rdx
        pop rcx
        pop rbx
        pop rax
%endmacro

%macro interrupt_err 1
interrupt_%+%1:
    push qword %1
    jmp interrupt_common
%endmacro

%macro interrupt_no_err 1
interrupt_%+%1:
    push qword 0
    push qword %1
    jmp interrupt_common
%endmacro

extern interrupt_handler
interrupt_no_err 0
interrupt_no_err 1
interrupt_no_err 2
interrupt_no_err 3
interrupt_no_err 4
interrupt_no_err 5
interrupt_no_err 6
interrupt_no_err 7
interrupt_err    8
interrupt_no_err 9
interrupt_err    10
interrupt_err    11
interrupt_err    12
interrupt_err    13
interrupt_err    14
interrupt_no_err 15
interrupt_no_err 16
interrupt_err    17
interrupt_no_err 18
interrupt_no_err 19
interrupt_no_err 20
interrupt_no_err 21
interrupt_no_err 22
interrupt_no_err 23
interrupt_no_err 24
interrupt_no_err 25
interrupt_no_err 26
interrupt_no_err 27
interrupt_no_err 28
interrupt_no_err 29
interrupt_err    30
interrupt_no_err 31

%assign i 32
%rep 224
    interrupt_no_err i
%assign i i+1
%endrep

interrupt_common:
    swapgs
    push_all
    mov rdi, rsp
    call interrupt_handler
    mov rsp, rax
    pop_all
    add rsp, 16 ; vector and error code
    swapgs
    iretq

section .data
global interrupt_vector
interrupt_vector:
%assign i 0 
%rep    256 
    dq interrupt_%+i
%assign i i+1 
%endrep
