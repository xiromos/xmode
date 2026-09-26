;##############################################################################################################
;Test program for window manager 
;##############################################################################################################

section .text
start:
    xor esi, esi
    xor ebx, ebx            ;text color (black)
    mov ecx, 0x00ffffff     ;background color (white)
    mov ah, 0x0a
    int 0x34

    mov [window_packet], edi
    mov [win_id], ax

    mov esi, welcome_msg
    mov edi, [window_packet]
    mov bx, [win_id]
    mov ah, 0x1a
    int 0x30

.loop:
    mov ah, 0x1b
    mov al, '>'
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    mov ah, 0x1b
    mov al, 0x20
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    xor ecx, ecx
    mov edi, command_buffer
.get_input:
    xor ah, ah
    int 0x31

    cmp al, 0x08
    je .handle_backspace
    cmp al, 0x0d
    je .done

    cmp ecx, 200
    jae .get_input
    inc ecx

    push edi
    mov ah, 0x1b
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30
    pop edi
    
    stosb

    cmp al, 'q'
    je .quit
    jmp .get_input

.handle_backspace:
    cmp ecx, 0
    jbe .get_input
    mov ah, 0x1b
    mov bx, [win_id]
    mov al, 0x08
    push edi
    mov edi, [window_packet]
    int 0x30

    mov ah, 0x1b
    mov al, 0x20
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    mov ah, 0x1b
    mov al, 0x08
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30
    pop edi

    dec edi
    dec ecx
    jmp .get_input

.done:
    mov byte [edi], 0
    mov ah, 0x1b
    mov al, 0x0a
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

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

    mov esi, no_cmd
    mov ah, 0x1a
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    mov ah, 0x1b
    mov al, 0x0a
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    jmp .loop

.clear_screen:
    mov ah, 0x1e
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30

    jmp .loop
.help:
    mov ah, 0x1a
    mov bx, [win_id]
    mov esi, help_msg
    mov edi, [window_packet]
    int 0x30

    mov ah, 0x1b
    mov al, 0x0a
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x30
    jmp .loop
.quit:
    mov ah, 0x0b
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x34
    
    mov ah, 0x05        ;exit syscall
    int 0x35

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
    mov edi, [window_packet]
    mov bx, [win_id]
    mov ah, 0x1a
    int 0x30
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

    mov ah, 0x05
    int 0x35


section .data
window_packet: dd 0
win_id: dw 0

clear_str: db 'clear', 0
help_str: db 'help', 0
spawn_str: db 'spawn', 0
no_cmd: db 'Not a known command', 0

help_msg: db 'Help', 0x0a,
          db 'HELP: show this message', 0x0a,
          db 'CLEAR: clear screen', 0x0a,
          db 'Press "q" to quit program', 0

welcome_msg: db 'Mini-Shell: Type "help" for list of commands', 0x0a, 0
command_buffer: db 200 dup(0)

wmtest: db 'WMTEST  OBJ', 0
error_msg: db 'Error loading new program', 0x0a, 0