;==========================================================================
;PS/2 mouse driver
;Copyright (C) 2026 Technodon
;==========================================================================

section .text
init_mouse:
    cli
    ;deactivate keyboard
    call .wait_input
    jc .error
    mov al, 0xad
    out 0x64, al

.flush:
    in al, 0x64
    test al, (1 << 0)
    jz .empty
    in al, 0x60
    jmp .flush
.empty:
    call .wait_input
    mov al, 0xa9
    out 0x64, al

    call .wait_output_ctrl
    jc .error
    in al, 0x60
    cmp al, 0
    jne .error

    ;activate auxiliary device
    call .wait_input
    mov al, 0xa8
    out 0x64, al

    ;ask for command byte
    call .wait_input
    mov al, 0x20
    out 0x64, al

    ;read command byte
    call .wait_output_ctrl
    jc .error
    in al, 0x60

    and al, ~(1 << 1)   ;no IRQ12
    and al, ~(1 << 5)   ;remove bit "disable mouse"
    mov ah, al

    call .wait_input
    mov al, 0x60
    out 0x64, al

    call .wait_input
    mov al, ah
    out 0x60, al

    ;reset mouse
    call .wait_input
    mov al, 0xd4
    out 0x64, al

    call .wait_input
    mov al, 0xff
    out 0x60, al

    call .wait_output_mouse
    jc .error
    in al, 0x60
    cmp al, 0xfa
    jne .error

    call .wait_output_mouse
    jc .error
    in al, 0x60
    cmp al, 0xaa
    jne .error

    ;read device ID
    in al, 0x64
    test al, (1 << 0)
    jz .no_id
    in al, 0x60
.no_id:

    ;set default configuration
    call .wait_input
    mov dx, 0x64
    mov al, 0xd4
    out dx, al

    call .wait_input
    mov dx, 0x60
    mov al, 0xf6        ;load defaults
    out dx, al

    call .wait_output_mouse
    jc .error
    in al, dx
    cmp al, 0xfa
    jne .error

    call .wait_input
    mov dx, 0x64
    mov al, 0xd4
    out dx, al

    call .wait_input
    mov dx, 0x60
    mov al, 0xf4        ;enable data reporting
    out dx, al

    call .wait_output_mouse
    jc .error
    in al, 0x60
    cmp al, 0xfa
    jne .error

    ;ask for command byte
    call .wait_input
    mov al, 0x20
    out 0x64, al

    ;read command byte
    call .wait_output_ctrl
    jc .error
    in al, 0x60

    or al, (1 << 1)     ;activate interrupts for mouse on IRQ12
    and al, ~(1 << 5)   ;remove bit "disable mouse"
    mov ah, al

    call .wait_input
    mov al, 0x60
    out 0x64, al

    call .wait_input
    mov al, ah
    out 0x60, al

    mov al, 0xae
    out 0x64, al

    clc                 ;no error
    sti
    ret

.error:
    ;activate keyboard again
    mov al, 0xae
    out 0x64, al
    stc
    sti
    ret

.error_timer:
    pop edx
    pop ebx
    pop eax

    pop eax

    mov al, 0xae
    out 0x64, al
    stc
    sti
    ret

; .wait_input:
;     push ecx
;     mov ecx, 0xfffff
; .wait_input_loop:
;     in al, 0x64
;     test al, (1 << 1)
;     jz .wait_input_done
;     loop .wait_input_loop

;     pop ecx
;     stc
;     ret
; .wait_input_done:
;     pop ecx
;     clc
;     ret

; .wait_output_ctrl:
;     push ecx
;     mov ecx, 0xfffff
; .wait_output_loop:
;     in al, 0x64
;     test al, (1 << 0)
;     jnz .wait_output_done
;     loop .wait_output_loop
;     pop ecx
;     stc
;     ret
; .wait_output_done:
;     pop ecx
;     clc
;     ret

; .wait_output_mouse:
;     push ecx
;     mov ecx, 0xfffff
; .wait_mouse_loop:
;     in al, 0x64
;     test al, (1 << 0)
;     jz .retry

;     test al, (1 << 5)       ;check if data came from keyboard (0 = keyboard, 1 = mouse (auxiliary device))
;     jnz .ready

;     in al, 0x60

; .retry:
;     loop .wait_mouse_loop
;     pop ecx
;     stc
;     ret
; .ready:
;     pop ecx
;     clc
;     ret  100529a

.wait_input:
    sti
    push eax
    push ebx
    push edx
    mov ah, 0x22
    mov al, 0x02
    movzx ebx, byte [counter_no]
    inc byte [counter_no]
    imul ebx, 4
    add ebx, counter
    mov dword [ebx], 0
    mov edx, 100
    int 0x35
    jc .error_timer
.wait_input_loop:
    in al, 0x64
    test al, (1 << 1)
    jz .wait_input_done
    
    cmp dword [ebx], 100
    jb .wait_input_loop
    
    pop edx
    pop ebx
    pop eax
    stc
    cli
    ret
.wait_input_done:
    pop edx
    pop ebx
    pop eax
    clc
    cli
    ret

.wait_output_ctrl:
    sti
    push eax
    push ebx
    push edx
    mov ah, 0x22
    mov al, 0x02
    movzx ebx, byte [counter_no]
    inc byte [counter_no]
    imul ebx, 4
    add ebx, counter
    mov dword [ebx], 0
    mov edx, 150    ;150ms
    int 0x35
    jc .error_timer
.wait_output_loop:
    in al, 0x64
    test al, (1 << 0)
    jnz .wait_output_done
    
    cmp dword [ebx], 150
    jb .wait_output_loop
    pop edx
    pop ebx
    pop eax
    cli
    stc
    ret
.wait_output_done:
    pop edx
    pop ebx
    pop eax
    cli
    clc
    ret

.wait_output_mouse:
    sti
    push eax
    push ebx
    push edx

    mov ah, 0x22
    mov al, 0x02
    movzx ebx, byte [counter_no]
    inc byte [counter_no]
    imul ebx, 4
    add ebx, counter
    mov dword [ebx], 0
    mov edx, 800    ;800ms
    int 0x35
    jc .error_timer
.wait_mouse_loop:
    in al, 0x64
    test al, (1 << 0)
    jz .wait

    test al, (1 << 5)       ;check if data came from keyboard (0 = keyboard, 1 = mouse (auxiliary device))
    jnz .ready

    in al, 0x60

.wait:
    cmp dword [ebx], 800
    jb .wait_mouse_loop

    pop edx
    pop ebx
    pop eax
    cli
    stc
    ret
.ready:
    pop edx
    pop ebx
    pop eax
    cli
    clc
    ret


section .data
counter: times 20 dd 0
counter_no: db 0