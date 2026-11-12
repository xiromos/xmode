;==============================================================
;useful functions for Win32 COFF programs of XiromosX32
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

    push eax
    push edi

    mov ah, 0x0a
    int 0x34
    jc .already_init

    mov [win_fg_color000], ebx
    mov [win_bg_color000], ecx

    mov byte [win_initialized], 1

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
    push ebx
    push ecx
    push edx
    push edi

    mov ecx, ebx
    mov edx, [win_bg_color000]

    mov ah, 0x0e
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x34

    mov ah, 0x1a
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    mov ecx, [win_fg_color000]
    mov edx, [win_bg_color000]
    mov ah, 0x0e
    int 0x34

    pop edi
    pop edx
    pop ecx
    pop ebx
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
    push ebx
    push ecx
    push edx
    push edi

    mov ecx, ebx
    mov edx, [win_bg_color000]

    push ax
    mov ah, 0x0e
    mov bx, [win_id]
    mov edi, [window_packet]
    int 0x34
    pop ax

    mov dx, ax
    mov ah, 0x1b
    mov edi, [window_packet]
    mov bx, [win_id]
    int 0x30

    mov ecx, [win_fg_color000]
    mov edx, [win_bg_color000]
    mov ah, 0x0e
    int 0x34

    pop edi
    pop edx
    pop ecx
    pop ebx
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

input:
    ret

memalloc:
    ;Input: ECX = size of heap in bytes
    ;Output: ESI = pointer to allocated chunk or ESI = 0 and CF set if an error occured
    cmp byte [heap_init000], 1
    je .skip

    ;allocate 4Kib chunk
    push esi
    call .alloc_mem_os
    mov [heap_ptr000], esi
    mov byte [heap_init000], 1
    mov dword [esi+4], 0x1000
    or byte [esi+8], (1 << 4) | (1 << 5)
    pop esi
.skip:
    cmp eax, 0
    je .err

    pusha

    add eax, 9      ;header
    mov edi, [heap_ptr000]
.loop:
    ;check if header is valid
    mov bl, [edi+8]
    test bl, (1 << 4)
    jz .err2
    test bl, (1 << 5)
    jz .err2

    test byte [edi+8], (1 << 0)
    jnz .next
    cmp dword [edi+4], eax
    jb .next

    mov edx, [edi+4]
    mov [edi+4], eax        ;set size, including header
    or byte [edi+8], (1 << 0)
    mov esi, edi
    add esi, 9

    mov ebx, edi
    add ebx, eax
    mov [edi], ebx

    or byte [ebx+8], (1 << 4) | (1 << 5)
    sub edx, eax
    mov [ebx+4], edx

    mov [heap_esi000], esi
    popa
    mov esi, [heap_esi000]
    clc
    ret
.next:
    mov ebx, [edi]
    cmp ebx, 0
    je .alloc_new
.err:
    stc
    ret
.err2:
    popa
    xor esi, esi
    stc
    ret

.alloc_new:
    jmp .loop

.alloc_mem_os:
    ;Output: ESI = pointer to 4Kib chunk
    push eax
    push ecx
    push edi

    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35

    mov edi, esi
    xor eax, eax
    mov ecx, 0x1000/4
    rep stosd

    pop edi
    pop ecx
    pop eax
    ret
freemem:
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
win_fg_color000: dd 0
win_bg_color000: dd 0

heap_init000: db 0
heap_ptr000: dd 0
;heap is split into different fractions, each with following header:
;dd next_fraction
;dd size (of this fraction, including the header)
;db status (bit0 = used, bit1 = is fragmented (this block and the block above cant be combined, because this is a new heap block with a different address), bit4 and bit5 have to be 1, to show that this is a valid header)

;#########################################################################
;pointer to 4kib chunk, following structure:
;+0: pointer to next 4kib chunk (if 0, then there is no next chunk)
;+4: area, which manages the heap memory of this 4kib chunk (1 Bit = 4 Bytes)
;+128: heap memory

heap_esi000: dd 0