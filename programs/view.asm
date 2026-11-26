;========================================================================================
;image viewer
;========================================================================================

%include "includes/string.inc"
%include "includes/stdfunc.inc"

section .text
start:
    pop eax     ;old SS
    pop esi     ;filename
    pop edi     ;directory

    cmp dword [esi], 0xffffffff
    je .error

    push esi
    push edi
    mov edi, filebuffer2
    mov ecx, 11
    rep movsb
    pop edi
    pop esi

    push edi
    mov edi, filebuffer
    call string_parse_filename
    pop edi
    mov esi, filebuffer

    push edi
    xor ah, ah
    int 0x33
    pop edi
    jc .error

    cmp ebx, 0
    je .empty_file

    mov ah, 0x0a
    int 0x35

    mov [heap], esi
    mov [size], ecx

    mov edx, edi
    mov edi, esi
    mov esi, filebuffer
    
    mov ah, 0x21
    int 0x33
    mov bl, al

    mov ah, 0x0a
    int 0x33
    jc .error

    cmp word [edi], 'BM'
    jne .not_bmp

    mov eax, [edi+2]
    cmp eax, dword [size]
    jne .not_bmp

    mov eax, [edi+18]
    mov ecx, eax
    mov [win_packet+8], eax
    mov eax, [edi+22]
    mov edx, eax
    mov [win_packet+12], eax
    mov ebx, 0x00ffffff
    mov ebp, filebuffer2

    xor esi, esi
    mov edi, 20     ;leave space for the header
    mov ah, 0x01
    int 0x34

    mov edi, [heap]
    mov ax, [edi+28]

    cmp ax, 8
    jbe .color_table

    cmp ax, 16
    je .bytes2

    movzx edx, ax
    shr edx, 3  ;/8

    add edi, 14
    movzx eax, word [edi]
    add edi, eax

    xor eax, eax
    mov ebx, [win_packet+12]
    dec ebx

    mov ecx, [win_packet+8]
    mov esi, [win_packet+12]
.loop1:
    mov ebp, [edi]
    call win_set_pixel

    add edi, edx

    inc eax
    dec ecx
    jnz .loop1

    dec ebx
    mov ecx, [win_packet+8]
    xor eax, eax

    dec esi
    jnz .loop1

    xor ah, ah
    int 0x31
.done:
    mov edi, win_packet
    mov bx, [win_id]
    mov ah, 0x02
    int 0x34

    mov ah, 0x05
    int 0x35

.color_table:
    jmp .done
.bytes2:
    jmp .done
.error:
    mov esi, error_str
    mov ebx, COLOR_RED
    call print_string
    call print_newline

    call end_program

.empty_file:
    mov esi, empty_file_str
    mov ebx, COLOR_RED
    call print_string
    call print_newline

    call end_program

.not_bmp:
    mov esi, not_bmp_str
    mov ebx, COLOR_RED
    call print_string
    call print_newline

    call end_program

win_set_pixel:
    ;EAX = X
    ;EBX = Y
    ;EBP = color

    pusha
    mov ecx, eax
    mov edx, ebx
    mov edi, win_packet
    mov bx, [win_id]
    mov ah, 0x04
    int 0x34
    popa
    ret

section .data
heap: dd 0
size: dd 0
error_str: db 'File not found', 0
empty_file_str: db 'File is empty', 0
not_bmp_str: db 'Not a Bitmap Image File', 0
filebuffer: times 11 db 0
filebuffer2: times 12 db 0

win_packet:
    dd 0
    dd 0x00ffffff
    dd 0    ;width
    dd 0    ;height
    dd 0    ;CurX
    dd 20    ;CurY
    dd 0
    dd 20

win_id: dw 0