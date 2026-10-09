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


string_to_hex6:
;   Input:
;   ESI = pointer to hex string
;   Output:
;   ESI contains hex number
    push eax
    push ebx
    push ecx
    push edx

    xor ebx, ebx
    mov ecx, 6
.loop:
    lodsb

    push ax
    call print_char
    pop ax

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


bcd_convert_byte:
    ;AL = hex number
    ;Output: AL = decimal number
    ;Example:
    ;   before: EAX = 0x59
    ;   after: EAX = 59
    
    push ebx
    push ecx

    mov bl, al
    shr al, 4
    mov cl, 10
    mul cl
    xor ah, ah

    and bl, 0x0f
    add al, bl

    pop ecx
    pop ebx
    ret