[bits 64]

%macro push_all 0
        push rbp
        push rsp
%endmacro

%macro pop_all 0
        pop rsp
        pop rbp
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
    cld
    push_all
    mov rdi, rsp
    call interrupt_handler
    mov rsp, rax
    pop_all
    add rsp, 16
    iretq

section .data
global interrupt_vector
interrupt_vector:
%assign i 0 
%rep    256 
    dq interrupt_%+i
%assign i i+1 
%endrep
