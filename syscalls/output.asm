;=======================================================
;output functions for user programs
;Copyright (C) 2026 Technodon
;0x30
;AH = 0x01: print colored string
;   ESI: pointer to null-terminated string
;   EBX: color (0x00RRGGBB)
;AH = 0x02: print a single character
;   AL: character
;   EBX: color (0x00RRGGBB)
;AH = 0x03: newline
;AH = 0x04: print decimal number
;   EBX: number
;AH = 0x0A:     print string with custom CurX and CurY - increases X and Y
;   ESI: pointer to null-terminated string
;   EDI: pointer to structure
;       dd color
;       dd bgcolor
;       dd width
;       dd height
;       dd CurX
;       dd CurY
;AH = 0x0B:     print char with custom CurX and CurY - increases X and Y
;   AL: character
;   EDI: pointer to structure
;=======================================================

output_handler:
    pusha
    cmp ah, 0x01
    je .print_string
    cmp ah, 0x02
    je .print_char
    cmp ah, 0x03
    je .print_newline
    cmp ah, 0x04
    je .print_dec

    cmp ah, 0x0a
    je .print_string_custom
    cmp ah, 0x0b
    je .print_char_custom
    cmp ah, 0x0c
    je .print_newline_custom
    cmp ah, 0x0d
    je .print_dec_custom
    cmp ah, 0x0e
    je .custom_clear
    popa
    iret
.print_string:
    push bx
    mov bx, [current_task]
    cmp bx, [main_task]
    pop bx
    ;jne .print_string_sleep

    mov [color], ebx
    lodsb
    cmp al, 0
    je .done_print
    call print_char
    jmp .print_string
.done_print:
    popa
    iret
.print_string_sleep:
    sti
    hlt
    jmp .print_string


.print_char:
    push bx
    mov bx, [current_task]
    cmp bx, [main_task]
    pop bx
    jne .print_char_sleep

    mov [color], ebx
    cmp al, 0x0a
    je .newline

    call draw_char
    add dword [cur_x], 8
    mov edx, [real_width]
    cmp dword [cur_x], edx
    jae .newline
    jmp .done
.newline:
    mov dword [cur_x], 0
    add dword [cur_y], 16    ;font is 8x16
    mov edx, [real_height]
    cmp dword [cur_y], edx
    jae .scroll
.done:
    popa
    iret
.scroll:
    call scroll
    mov edx, [real_height]
    sub edx, 16
    mov dword [cur_y], edx
    jmp .done
.print_char_sleep:
    sti
    hlt
    jmp .print_char

.print_newline:
    mov dword [cur_x], 0
    add dword [cur_y], 16
    mov edx, [real_height]
    cmp dword [cur_y], edx
    jae .scroll
    popa
    iret
.print_dec:
    mov eax, ebx
    xor ecx, ecx
    mov ebx, 10
.div_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    cmp eax, 0
    jne .div_loop
.print_loop:
    pop eax
    add al, '0'
    mov ebx, 0x00ffffff
    mov [color], ebx
    call print_char
    loop .print_loop
    popa
    iret

.print_string_custom:
    ;ESI: pointer to null-terminated string
    ;EDI: pointer to structure
    ;    dd color
    ;    dd bgcolor
    ;    dd width
    ;    dd height
    ;    dd CurX        / WinX when clearing screen
    ;    dd CurY        / WinY when clearing screen
    ;    dd original CurX
    ;    dd original CurY
    mov eax, [edi]
    mov [color], eax
    mov eax, [edi+4]
    mov [char_bgcolor], eax
.print_string_custom_loop:
    lodsb
    cmp al, 0
    je .done_print_str
    call print_char_custom
    jmp .print_string_custom_loop
.done_print_str:
    popa
    iret
.print_char_custom:
    mov ebx, [edi]
    mov [color], ebx
    mov ebx, [edi+4]
    mov [char_bgcolor], ebx
    cmp al, 0x0a
    je .char_newline

    call draw_char_custom

    add dword [edi+16], 16
    mov eax, [edi+8]
    add eax, [edi+24]
    cmp dword [edi+16], eax
    jae .char_newline
    sub dword [edi+16], 8
    jmp .char_done
.char_newline:
    mov eax, [edi+24]
    mov dword [edi+16], eax
    add dword [edi+20], 24    ;font is 8x16
    mov eax, [edi+12]
    add eax, [edi+28]
    cmp dword [edi+20], eax
    jae .custom_scroll
    sub dword [edi+20], 8
.char_done:
    popa
    iret
.custom_scroll:
    call custom_scroll
    sub dword [edi+20], 24
    jmp .char_done
.print_newline_custom:
    popa
    iret
.print_dec_custom:
    popa
    iret

.custom_clear:
    mov esi, [frame_buffer]
    mov eax, [edi+24]           ;window X
    movzx ebx, byte [bpp]
    imul eax, ebx
    add esi, eax
    mov eax, [edi+28]           ;window Y
    imul eax, [pitch]
    add esi, eax

    mov eax, [edi+8]
    movzx ebx, byte [bpp]
    imul eax, ebx
    mov [win_pitch], eax

    mov ecx, [edi+8]            ;width
    mov eax, [edi+12]           ;height
    mov edx, [edi+4]            ;color
    movzx ebx, byte [bpp]
.clear_loop:
    mov [esi], edx
    add esi, ebx
    dec ecx
    jnz .clear_loop

    add esi, [pitch]
    mov ecx, [win_pitch]
    sub esi, ecx
    mov ecx, [edi+8]
    dec eax
    jnz .clear_loop

    mov eax, [edi+24]
    mov [edi+16], eax
    mov eax, [edi+28]
    mov [edi+20], eax
    popa
    iret

print_char_custom:
    cmp al, 0x0a
    je .newline

    call draw_char_custom
    add dword [edi+16], 16
    mov eax, [edi+8]
    add eax, [edi+24]
    cmp dword [edi+16], eax      ;compare CurX with window width
    jae .newline
    sub dword [edi+16], 8
    jmp .done
.newline:
    mov eax, [edi+24]
    mov dword [edi+16], eax
    add [edi+20], dword 24
    mov eax, [edi+12]
    add eax, [edi+28]
    cmp dword [edi+20], eax
    jae .scroll
    sub dword [edi+20], 8
.done:
    ret
.scroll:
    call custom_scroll
    sub dword [edi+20], 24
    jmp .done
custom_scroll:
    pusha
    mov eax, [edi+4]
    mov [win_color], eax
    mov eax, [edi+12]
    mov [cust_height], eax

    mov eax, [edi+8]
    mov [win_width], eax
    movzx ebx, byte [bpp]
    mul ebx
    mov [win_pitch], eax

    mov eax, [edi+12]
    mov ebx, 16
    div ebx
    mov [win_rows], eax

    mov esi, [frame_buffer]
    mov eax, [edi+24]       ;original X
    movzx ebx, byte [bpp]
    mul ebx
    add esi, eax

    mov eax, [edi+28]       ;original Y
    imul eax, [pitch]
    add esi, eax

    mov edi, esi
    ;source = framebuffer + 16
    mov eax, 16
    imul eax, [pitch]
    add esi, eax

    ;size = pitch * (height - 16)
    mov eax, [cust_height]
    sub eax, 16

    mov ecx, [win_pitch]
.loop:
    rep movsb
    add esi, [pitch]
    sub esi, [win_pitch]
    add edi, [pitch]
    sub edi, [win_pitch]
    mov ecx, [win_pitch]
    dec eax
    jnz .loop

    mov ecx, [win_width]
    mov esi, [win_color]
    movzx edx, byte [bpp]
    mov eax, 16
.loop2:
    mov [edi], esi
    add edi, edx
    dec ecx
    jnz .loop2

    add edi, [pitch]
    sub edi, [win_pitch]
    mov ecx, [win_width]
    dec eax
    jnz .loop2
    
    popa
    ret
draw_char_custom:
    ;    dd color
    ;    dd bgcolor
    ;    dd width
    ;    dd height
    ;    dd CurX        / WinX when clearing screen
    ;    dd CurY        / WinY when clearing screen
    pusha
    cmp al, 0xff        ;clear
    je .clear
    ; font index
    movzx esi, al
    imul esi, 16
    add esi, font8x16

    mov eax, [edi]
    mov [win_color], eax
    mov eax, [edi+4]
    mov [char_bgcolor], eax

    mov eax, [edi+20]
    imul eax, [pitch]        ; y * pitch

    mov ebx, [edi+16]
    movzx ecx, byte [bpp]
    imul ebx, ecx              ; x * 3

    add eax, ebx
    add eax, [frame_buffer]

    mov ebx, eax             ; ebx = start address

    mov ecx, 16               ; rows
.row:
    mov dl, [esi]
    inc esi

    mov edi, ebx             ; start of this row

    mov ebp, 8               ; columns
.col:
    test dl, 0x80
    jz .skip

    mov eax, [win_color]
    mov [edi], eax
    jmp .continue
.skip:
    mov eax, [char_bgcolor]
    mov [edi], eax
.continue:
    shl dl, 1
    push eax
    movzx eax, byte [bpp]
    add edi, eax               ;next pixel
    pop eax

    dec ebp
    jnz .col

    add ebx, [pitch]         ;next line
    dec ecx
    jnz .row

    popa
    ret
.clear:
    mov eax, [edi+8]
    movzx ebx, byte [bpp]
    mul ebx
    mov [win_pitch], eax

    mov eax, [edi+20]
    imul eax, [pitch]        ; y * pitch

    movzx ecx, byte [bpp]
    mov ebx, [edi+16]
    imul ebx, ecx              ; x * 3

    add eax, ebx
    add eax, [frame_buffer]

    mov ebx, eax             ; ebx = start address

    mov ecx, 16               ; rows
.clear_row:
    mov esi, ebx             ; start of this row
    mov ebp, 8               ; columns
.clear_col:
    mov eax, [edi+4]
    mov [esi], eax

    push eax
    movzx eax, byte [bpp]
    add esi, eax               ;next pixel
    pop eax

    dec ebp
    jnz .clear_col

    add ebx, [pitch]         ;next line
    dec ecx
    jnz .clear_row

    popa
    ; cli
    ; hlt
    ret