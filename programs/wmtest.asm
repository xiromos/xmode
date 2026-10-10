;##############################################################################################################
;Test program for window manager 
;##############################################################################################################

section .text
start:
    xor esi, esi
    xor ebx, ebx            ;text color (black)
    mov ecx, 0x00ffffff     ;background color (white)
    call init_window

    mov esi, welcome_msg
    xor ebx, ebx
    call print_string

.loop:
    mov ax, '>'
    call print_char

    mov ax, ' '
    call print_char

    xor ecx, ecx
    mov edi, command_buffer
.get_input:
    xor ah, ah
    int 0x31

    cmp al, 0x08
    je .handle_backspace
    cmp al, 0x0d
    je .done

    cmp ecx, 100
    jae .get_input
    inc ecx

    xor ah, ah
    call print_char
    
    stosb

    jmp .get_input

.handle_backspace:
    cmp ecx, 0
    jbe .get_input

    mov ax, 0x08
    xor ebx, ebx
    call print_char

    mov ax, 0x20
    xor ebx, ebx
    call print_char

    mov ax, 0x08
    xor ebx, ebx
    call print_char

    dec edi
    dec ecx
    jmp .get_input

.done:
    mov byte [edi], 0
    call print_newline

    mov edi, command_buffer
    mov esi, clear_str
    call cmp_cmd
    jc .clear_screen

    mov edi, command_buffer
    mov esi, help_str
    call cmp_cmd
    jc .help

    mov edi, command_buffer
    mov esi, spawn_str
    call cmp_cmd
    jc .novyi

    mov edi, command_buffer
    mov esi, quit_str
    call cmp_cmd
    jc .quit

    mov esi, no_cmd
    xor ebx, ebx
    call print_string

    call print_newline

    jmp .loop

.clear_screen:
    call clear_window

    jmp .loop
.help:
    mov esi, help_msg
    xor ebx, ebx
    call print_string

    call print_newline
    jmp .loop
.quit:
    call end_program
    jmp .loop
.novyi:
    mov ah, 0x02
    mov esi, wmtest
    mov edi, esi
    xor ebx, ebx
    int 0x35
    jc .error

    jmp .loop

.error:
    mov esi, error_msg
    xor ebx, ebx
    call print_string
    jmp .loop

cmp_cmd:
    mov al, [edi]
    mov bl, [esi]

    cmp al, bl
    jne .not_equal
    cmp al, 0
    je .equal

    inc esi
    inc edi
    jmp cmp_cmd
.equal:
    stc
    ret
.not_equal:
    clc
    ret

%include "includes/stdfunc.inc"
section .data
clear_str: db 'clear', 0
help_str: db 'help', 0
spawn_str: db 'spawn', 0
quit_str: db 'quit', 0
no_cmd: db 'Not a known command', 0

help_msg: db 'Help', 0x0a,
          db 'HELP: show this message', 0x0a,
          db 'CLEAR: clear screen', 0x0a,
          db 'QUIT: quit program', 0x0a,
          db 'Press "q" to quit program', 0

welcome_msg: db 'Mini-Shell: Type "help" for list of commands', 0x0a, 0
command_buffer: db 100 dup(0)

wmtest: db 'WMTEST  OBJ', 0
error_msg: db 'Error loading new program', 0x0a, 0