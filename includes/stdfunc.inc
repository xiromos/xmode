;==============================================================
;useful functions for programs of XiromosX32
;Copyright (C) 2026 Technodon
;==============================================================

; Functions:
;     clear_window
;     print_char
;     print_string
;     init_window

section .text
jmp end_of_include_file_alhkgjf

init_window:
    ;EBX = foreground color
    ;ECX = background color
    ;ESI = *title, max. 17 chars, if ESI = 0: title = 'untitled'

    cmp byte [win_initialized], 1
    je .already_init
    mov byte [win_initialized], 1

    push eax
    push edi

    mov ah, 0x0a
    int 0x34

    mov [window_packet], edi
    mov [win_id], ax

    pop edi
    pop eax
    clc
    ret
.already_init:
    stc
    ret

print_string:
    ;ESI = string
    ;EBX = color
    cmp byte [win_initialized], 1
    je .win

    push eax
    mov ah, 0x01
    int 0x30
    pop eax
    ret
.win:
    push eax
    push edi

    mov ah, 0x1a
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    pop edi
    pop eax
    ret

print_char:
    ;AX = char
    ;EBX = color
    cmp byte [win_initialized], 1
    je .win

    push eax
    mov ah, 0x01
    int 0x30
    pop eax
    ret
.win:
    push eax
    push edi
    push ebx

    mov dx, ax
    mov ah, 0x1b
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    pop ebx
    pop edi
    pop eax
    ret

print_newline:
    cmp byte [win_initialized], 1
    je .win

    push eax
    mov ah, 0x0c
    int 0x30
    pop eax
    ret
.win:
    push eax
    push ebx
    push edi

    mov ah, 0x1c
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    pop edi
    pop ebx
    pop eax
    ret

clear_window:
    cmp byte [win_initialized], 1
    jne .error

    push eax
    push ebx
    push edi

    mov ah, 0x1e
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    pop edi
    pop ebx
    pop eax
    ret
.error:
    stc
    ret

end_program:
    cmp byte [win_initialized], 1
    jne .skip

    mov ah, 0x0b
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x34
.skip:
    mov ah, 0x05
    int 0x35
    ret

open_file:
    ret

end_of_include_file_alhkgjf:
section .data
window_packet: dd 0xffffff00
win_id: dw 0

COLOR_RED       equ 0xbf0d0d
COLOR_GREEN     equ 0x12b00c
COLOR_CYAN      equ 0x0fa0ab
COLOR_YELLOW    equ 0xede137
COLOR_BLUE      equ 0x141dba

win_initialized: db 0