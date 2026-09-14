;=================================================
;Basic output functions
;Copyright (C) 2026 Technodon
;=================================================

;ESI: pointer to string
;EBX: color
print_string:
    mov [color], ebx
    lodsb
    cmp al, 0
    je .done
    call print_char
    jmp print_string
.done:
    ret

print_char:
    pusha
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
    ret
.scroll:
    call scroll
    mov edx, [real_height]
    sub edx, 16
    mov dword [cur_y], edx
    jmp .done

print_newline:
    pusha
    mov dword [cur_x], 0
    add dword [cur_y], 16
    mov edx, [real_height]
    sub edx, 16
    cmp dword [cur_y], edx
    jae .scroll
    popa
    ret
.scroll:
    call scroll
    mov edx, [real_height]
    sub edx, 16
    mov dword [cur_y], edx
    popa
    ret
draw_char:
    pusha
    cmp al, 0xff        ;clear
    je .clear
    ; font index
    movzx esi, al
    imul esi, 16
    add esi, font8x16

    mov eax, [cur_y]
    imul eax, [pitch]        ; y * pitch

    mov ebx, [cur_x]
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

    mov eax, [color]
    mov [edi], eax

.skip:
    shl dl, 1
    push ecx
    movzx ecx, byte [bpp]
    add edi, ecx               ;next pixel
    pop ecx
    
    dec ebp
    jnz .col

    add ebx, [pitch]         ;next line
    dec ecx
    jnz .row

    popa
    ret
.clear:
    mov eax, [cur_y]
    imul eax, [pitch]        ; y * pitch

    mov ebx, [cur_x]
    movzx ecx, byte [bpp]
    imul ebx, ecx              ; x * 3

    add eax, ebx
    add eax, [frame_buffer]

    mov ebx, eax             ; ebx = start address

    mov ecx, 16               ; rows
.clear_row:
    mov edi, ebx             ; start of this row
    mov ebp, 8               ; columns
.clear_col:
    mov eax, [bgcolor]
    mov [edi], eax

    push ecx
    movzx ecx, byte [bpp]
    add edi, ecx               ;next pixel
    pop ecx

    dec ebp
    jnz .clear_col

    add ebx, [pitch]         ;next line
    dec ecx
    jnz .clear_row

    popa
    ret
clear_screen:
    pusha
    mov edi, [frame_buffer]
    mov ecx, [real_width]
    imul ecx, [real_height]
    ;mov ecx, width*height
    mov ebx, [bgcolor]
    ;mov ebx, 0x00111111
    ;mov [bgcolor], ebx
.loop:
    mov dword [edi], ebx
    movzx eax, byte [bpp]
    add edi, eax
    loop .loop
    mov dword [cur_x], 0
    mov dword [cur_y], 0
    popa
    ret
scroll:
    pusha

    mov esi, [frame_buffer]
    mov edi, [frame_buffer]

    ;source = framebuffer + 16
    mov eax, [rows]
    imul eax, [pitch]
    add esi, eax

    ;size = pitch * (height - 16)
    mov eax, [real_height]
    ;mov eax, height
    sub eax, [rows]
    imul eax, [pitch]

    mov ecx, eax
    rep movsb

    ;clear last row
    mov edi, [frame_buffer]

    mov eax, [real_height]
    ;mov eax, height
    sub eax, [rows]
    imul eax, [pitch]
    add edi, eax

    mov ecx, [rows]
    imul ecx, [pitch]

    mov eax, [bgcolor]
    movzx edx, byte [bpp]
.loop:
    mov [edi], eax
    add edi, edx
    dec ecx
    jnz .loop
    ;mov [bgcolor], eax

    popa
    ret
