;==============================================================
;useful for binary programs, written for Xiromos-X32
;==============================================================

bits 32

jmp end_of_include_file000
print_string:
    ;ESI = pointer to string
    ;EBX = color
    ret

print_char:
    ;AX = char
    ;EBX = color
    ret

close:
    mov ah, 0x05
    int 0x35
    ret

end_of_include_file000: