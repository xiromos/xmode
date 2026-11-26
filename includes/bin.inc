;==============================================================
;useful for binary programs, written for Xiromos-X32
;==============================================================

bits 32

jmp end_of_include_file000
print_string:
    ;ESI = pointer to string
    ;EBX = color
    push eax
    mov ah, 0x15
    mov al, 1
    int 0x35
    pop eax
    ret

print_char:
    ;AX = char
    ;EBX = color
    ret

print_newline:
    push eax
    mov ah, 0x15
    mov al, 3
    int 0x35
    pop eax
    ret

close:
    mov ah, 0x05
    int 0x35
    ret

end_of_include_file000: