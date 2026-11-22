;==============================================================
;debug functions for Xiromos-X32 programs
;Copyright (C) 2026 Technodon
;==============================================================

;functions
;halt

section .text
jmp end000_

halt:
    mov ah, 0x01
    int 0x35
    ret

set_counter:
    ;EAX = value
    mov [number_000], eax
    ret
stop_counter:
    ;only stops the system, if the counter reaches a specific value
    push eax
    mov eax, [cntr_000]
    cmp eax, dword [number_000]
    jb .skip

    mov ah, 0x01
    int 0x35
.skip:
    pop eax
    inc dword [cntr_000]
    ret
clear_counter:
    mov dword [cntr_000], 0
    ret

end000_:
section .data
cntr_000: dd 0
number_000: dd 0