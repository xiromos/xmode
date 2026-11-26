;String library
;Copyright (C) 2026 Technodon

;include it with following method: include "/path/to/library/string.inc"

;functions:
;   string_uppercase
;   string_lowercase
;   string_to_hex
;   string_utf8_word
;   string_copy
;   string_parse_filename


section .text
jmp end_000
string_uppercase:
;   Input:
;   ESI = pointer to null-terminated string
;
;   Output:
;   ESI = pointer to edited string
    pusha
    mov edi, esi
.loop:
    lodsb
    cmp al, 0
    je .done

    cmp al, 0x61
    jb .next
    cmp al, 0x7a
    ja .next

    sub al, 0x20
.next:
    stosb
    jmp .loop

.done:
    stosb
    popa
    ret


string_lowercase:
;   Input:
;   ESI = pointer to null-terminated string
;
;   Output:
;   ESI = pointer to edited string
    pusha
    mov edi, esi
.loop:
    lodsb
    cmp al, 0
    je .done

    cmp al, 0x41
    jb .next

    cmp al, 0x61
    ja .next

    add al, 0x20
.next:
    stosb
    jmp .loop
.done:
    stosb
    popa
    ret


string_to_hex:
;   Input:
;   ESI = pointer to hex string
;   ECX = length of string (max 8 byte)
;   Output:
;   ESI contains hex number
    push eax
    push ebx
    push ecx
    push edx

    cmp ecx, 0
    je .error

    cmp ecx, 8
    ja .error

    xor ebx, ebx
.loop:
    lodsb

    cmp al, 0
    je .done_convert

    cmp al, '0'
    jb .loop
    cmp al, '9'
    jbe .number

    cmp al, 'A'
    jb .loop
    cmp al, 'F'
    jbe .string

    dec ecx
    jnz .loop
    jmp .done_convert

.number:
    sub al, '0'
    jmp .add
.string:
    sub al, 0x41 - 10
.add:
    shl ebx, 4
    movzx edx, al
    or ebx, edx
    dec ecx
    jnz .loop

.done_convert:
    mov esi, ebx

    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret

.error:
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

string_utf8_word:
    ;converts a single UTF-8 word into a Unicode character
    ;AX = UTF-8 code
    ;Output: AX = Unicode character

    push ecx
    test al, 0x80
    jz .done    ;its an ASCII char

    movzx cx, ah
    xor ah, ah
    
    ;remove UTF-8 masks
    and ax, 0x1f
    and cx, 0x3f

    ;connect bits
    shl ax, 6
    or ax, cx
.done:
    pop ecx
    ret


string_copy:
    ;copies null terminated string from ESI to EDI (excluding null terminator)
    push eax
    push edi
    push esi
.loop:
    lodsb
    cmp al, 0
    je .done
    stosb
    jmp .loop
.done:
    pop esi
    pop edi
    pop eax
    ret


string_parse_filename:
    pusha
    xor ecx, ecx
.loop:
    mov al, [esi]
    cmp al, 0       ;check for 0-terminator
    je .add_spaces     ;invalid string
    cmp al, '.'     ;chech for extension
    je .add_spaces
    stosb           ;stores al in EDI
    inc esi
    inc ecx
    cmp ecx, 8
    jnz .loop
.add_spaces:
    cmp ecx, 8
    je .parse_ext
    mov al, ' '     ;fill the rest of the name with spaces to achieve 8.3 format
    stosb
    inc ecx
    jmp .add_spaces
.parse_ext:
    cmp byte [esi], '.'
    jne .parse_ext_loop
    inc esi
.parse_ext_loop:
    xor ecx, ecx
.loop2:
    mov al, [esi]
    cmp al, 0
    je .add_spaces_ext
    stosb
    inc esi
    inc ecx
    cmp ecx, 3
    jb .loop2
.add_spaces_ext:
    cmp ecx, 3
    je .done
    mov al, ' '
    stosb
    inc ecx
    jmp .add_spaces_ext
.done:
    popa
    ret


end_000: