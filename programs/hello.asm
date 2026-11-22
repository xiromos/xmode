;simple test program that prints a welcome message
bits 32
[org 0x400000]

start:

    mov esi, welcome_msg
    mov ebx, 0xffffff
    call print_string

    call close

%include "includes/bin.inc"
welcome_msg: db 'Hello World', 0