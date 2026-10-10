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

utf8_convert_word:
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

utf8_string_char:
    ;ESI = *string
    ;loads the UTF-8 code of the first char in ESI
    ;increases ESI
    ;converts the UTF-8 code to Unicode and outputs it in AX
    ;if Unicode is: > 0x800, then it outputs AX = 1
    ;if the char at *ESI is 0, AX = 0

    mov al, [esi]
    cmp al, 0
    je .null

    test al, 0x80
    jz .ascii

    push ecx
    push ebx

    mov cl, al
    and cl, 0xe0
    cmp cl, 0xc0
    je .bytes2

    mov cl, al
    and cl, 0xf0
    cmp cl, 0xe0
    je .bytes3

    mov cl, al
    and cl, 0xf8
    cmp cl, 0xf0
    je .bytes4

    jmp .error

.null:
    inc esi
    xor ax, ax
    ret
.ascii:
    inc esi
    xor ah, ah
    ret

.bytes2:
    mov bl, [esi+1]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    add esi, 2
    mov ah, bl
    
    ;call utf8_convert_word
    pop ebx
    pop ecx
    ret

.bytes3:
    mov bl, [esi+1]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    mov bl, [esi+2]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    add esi, 3
    mov ax, 1
    pop ebx
    pop ecx
    ret
.bytes4:
    mov bl, [esi+1]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    mov bl, [esi+2]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    mov bl, [esi+3]
    mov cl, bl
    and cl, 0xc0
    cmp cl, 0x80
    jne .error

    add esi, 4
    mov ax, 1
    pop ebx
    pop ecx
    ret

.error:
    pop ebx
    pop ecx

    inc esi
    mov ax, 1
    ret