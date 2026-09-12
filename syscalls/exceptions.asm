int0x0:
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808
    mov al, '0'
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    add dword [esp], 1
    iret
int0x1:
    iret
    pop eax
    pop ebx
    pop ecx
    pop edx
    pop esi
    pop edi
    mov ebp, 0x12345678
    cli
    hlt

int0x6:
    pop eax
    pop ebx
    pop ecx
    pop edx
    mov ebp, 6
    cli
    hlt
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808
    mov ebx, [color]
    mov al, '6'
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    add dword [esp], 2
    ;call kill_processes
    iret

int0x08:
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808
    mov al, '8'
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    add dword esp, 1
    iret
int0xd:
    pop eax
    pop ebx
    pop ecx
    pop edx
    mov ebp, 0x0d
    cli
    hlt
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808       ;red
    mov al, 'D'                         ;0x0d
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    add esp, 4              ;skip error code
    add dword [esp], 1      ;add EIP 1 to skip instruction
    iret

int0xe:
    cli
    pusha
    mov eax, cr2
    mov ebx, [esp+32]

    test ebx, (1 << 0)
    jnz .access_violation

    ; cmp ebx, 0x05
    ; je .access_violation
    ; cmp ebx, 0x07
    ; je .access_violation

    mov ebx, 0x1000
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_RW | PAGE_USER
    call map_region
    jmp .done
.access_violation:
    mov ah, 0x04
    movzx ebx, word [current_task]
    cmp ebx, 1
    je .error
    xor esi, esi
    int 0x35
.done:
    popa
    add esp, 4
    iret
.error:
    mov ecx, 0x10000
    mov al, 0xff
    mov edi, [frame_buffer]
    rep stosb

    mov esi, .error_msg
    call rsod
    cli
    hlt
.error_msg: db 'Page Access Violation By Task SHELL.SYS', 0
int_no_err:
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808
    mov al, 'X'
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    iret
int_err:
    pusha
    mov ebx, [cur_x]
    mov ecx, [cur_y]
    push ebx
    push ecx

    mov dword [cur_x], 0
    mov dword [cur_y], 0
    mov edx, [color]

    push edx
    mov dword [color], 0x00a60808
    mov al, 'E'
    call print_char
    pop edx

    mov [color], edx
    pop ecx
    pop ebx
    mov [cur_y], ecx
    mov [cur_x], ebx
    popa
    add dword esp, 4
    iret

irq0_handler:
    cli
    pushad
    push ds
    push es
    push fs
    push gs

    cmp word [task_count], 2
    jb .done

    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp

    mov bx, [current_task]
    inc bx
.search_loop:
    mov edi, tasks_esp

    movzx eax, bx
    imul eax, TASK_SIZE
    add edi, eax
    cmp byte [edi], 0
    je .next
    cmp byte [edi], 0xe5
    je .next

    mov ax, bx
    jmp .load_next
.next:
    inc bx
    cmp bx, [task_slots]
    ja .load_shell

    mov edi, tasks_esp
    jmp .search_loop
.load_shell:
    ; mov ax, 1
    ; mov edi, tasks_esp+TASK_SIZE    ;EDI points to shell task

    mov ax, 0
    mov edi, tasks_esp              ;EDI points to idle task
.load_next:
    ;check attributes
    cmp dword [edi+11], 0
    jne .check_attributes
.continue:
    mov [current_task], ax

    ;load next task context
    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax

    mov esp, [edi+15]

    ;update TSS.ESP0
    movzx eax, word [current_task]
    imul eax, tasks_kernel_stack_off
    add eax, tasks_kernel_stack

    mov [tss+4], eax
.done:
    mov al, 0x20
    out 0x20, al

    pop gs
    pop fs
    pop es
    pop ds
    popad
    iretd

.check_attributes:
    mov bx, ax
    inc bx
    cmp dword [edi+11], 0x0000df00      ;waiting for ATA hard disk
    je .search_loop     ;skip this task
    cmp dword [edi+11], 0x0000b100      ;sleeping
    je .search_loop

    ;unknown attribute
    jmp .continue
irq1_handler:
    cli
    push ebx
    push edi
    push ecx
    xor ecx, ecx
    in al, 0x60
    mov ah, al

    cmp al, 0xaa
    je .no_shift
    cmp al, 0xb6
    je .no_shift

    cmp al, 0x80
    jae .done

    cmp al, 0x2a
    je .shift
    cmp al, 0x36
    je .shift
    cmp al, 0xb6
    je .no_shift
    jmp .continue

.shift:
    mov byte [shift], 1
    jmp .done
.no_shift:
    mov byte [shift], 0
    jmp .done
.continue:
    cmp al, 0
    je .done

    cmp byte [shift], 1
    je .get_shift

    movzx ebx, al
    mov al, [scan_codes+ebx]
    jmp .save
.get_shift:
    movzx ebx, al
    mov al, [keymap_shift+ebx]
.save:
    ; mov ebx, [buf_head]
    ; mov [key_buffer+ebx], al
    ; inc ebx
    ; and ebx, 255
    ; mov [buf_head], ebx
    movzx edi, word [main_task]
    mov ebx, edi
    imul edi, KEY_BUFFER_SIZE
    add edi, KEY_BUFFER

    movzx ecx, byte [BUFFER_HEAD+ebx]
    mov [edi+ecx], al
    inc cl

    mov [BUFFER_HEAD+ebx], cl
    cmp al, 0x3b        ;F1
    jne .done
    call switch_tasks
    xor al, al
.done:
    push ax
    mov al, 0x20
    out 0x20, al
    pop ax
.end:
    pop ecx
    pop edi
    pop ebx
    iret

keyboard_handler:
    cmp ah, 0
    je .get_key
    iret

.get_key:
    push ebx
    push edi
    push ecx

    cmp byte [usb_keyboard_used], 1
    je .usb_keyboard

.block:
    movzx ecx, word [main_task]
    mov bx, [current_task]
    cmp bx, [main_task]
    jne .sleep

    cli
    movzx ebx, byte [BUFFER_TAIL+ecx]
    movzx eax, byte [BUFFER_HEAD+ecx]
    sti

    cmp bl, al
    je .sleep

    mov edi, ecx
    imul edi, KEY_BUFFER_SIZE
    add edi, KEY_BUFFER

    mov al, [edi+ebx]
    inc byte [BUFFER_TAIL+ecx]

    pop ecx
    pop edi
    pop ebx
    iret

.sleep:
    sti
    hlt
    jmp .block

.usb_keyboard:
    movzx ebx, word [main_task]
    movzx ecx, word [current_task]
    cmp cx, [main_task]
    jne .sleep_usb

    cli
    mov al, [BUFFER_TAIL+ebx]
    mov cl, [BUFFER_HEAD+ebx]
    sti

    cmp al, cl
    je .sleep_usb


    mov edi, ebx
    imul edi, KEY_BUFFER_SIZE
    add edi, KEY_BUFFER

    movzx ecx, byte [BUFFER_TAIL+ebx]
    add edi, ecx

    ;mov dl, [edi]   ;modifier

    push ebx
    movzx ebx, byte [edi+1] ;Key1
    movzx eax, byte [usb_keymap+ebx]
    pop ebx

    add ecx, 7
    and ecx, 0xff
    mov [BUFFER_TAIL+ebx], cl

    cmp byte [edi+1], 0
    je .sleep_usb

    pop ecx
    pop edi
    pop ebx
    iret
.sleep_usb:
    sti
    hlt
    jmp .usb_keyboard

keyboard_handler2:
    cli
    cmp ah, 0
    je .get_key
    iret

.get_key:
    push ebx
.block:
    cli
    mov ebx, [buf_tail]
    mov eax, [buf_head]
    sti

    cmp ebx, eax
    je .sleep
    mov al, [key_buffer+ebx]

    inc ebx
    and ebx, 255
    mov [buf_tail], ebx

    pop ebx
    iret

.sleep:
    hlt
    jmp .block
irq7_handler:
    iret

irq12_handler:
    iret

switch_tasks:
    pusha
    mov ah, 0x01
    mov ebp, switch_tasks_str
    mov esi, width/2-250
    mov edi, height/2-150
    mov ecx, 500
    mov edx, 200
    mov ebx, 0x00ffffff
    int 0x34
    mov [switch_tasks_win_id], ax

    mov ah, 0x0a
    mov edi, switch_tasks_window
    mov esi, switch_tasks_msg
    int 0x30

    mov al, 0x0a
    mov ah, 0x0b
    mov edi, switch_tasks_window
    int 0x30

    mov esi, tasks_esp
    add esi, TASK_SIZE     ;skip task 0
    mov dx, [max_tasks]
    xor ebx, ebx
.loop:
    cmp byte [esi], 0xe5
    je .skip
    cmp byte [esi], 0
    je .skip

    inc bl
    push bx
    add bl, '0'
    mov al, bl
    pop bx
    mov ah, 0x0b
    mov edi, switch_tasks_window
    int 0x30

    mov al, ':'
    mov ah, 0x0b
    mov edi, switch_tasks_window
    int 0x30
    mov al, 0x20
    mov ah, 0x0b
    mov edi, switch_tasks_window
    int 0x30

    mov cx, 11
    push esi
.print_loop:
    lodsb
    mov edi, switch_tasks_window
    mov ah, 0x0b
    int 0x30
    dec cx
    jnz .print_loop
    pop esi

    mov edi, switch_tasks_window
    mov al, 0x0a
    mov ah, 0x0b
    int 0x30
.skip:
    add esi, TASK_SIZE
    dec dx
    jnz .loop

    xor ax, ax
    sti
.exit:
    hlt
    in al, 0x60

    sub al, 1
    cmp ax, [task_count]
    ja .exit
    add al, 1
    
    cmp al, 0
    je .exit
    cmp al, 0x01
    je .done

    jmp .switch_task
.done:
    mov al, 0x20
    out 0x20, al
    cli
    mov bx, [switch_tasks_win_id]
    mov ah, 0x02
    mov edi, switch_tasks_window
    int 0x34
    sti

    mov dword [edi+16], width / 2-250
    mov dword [edi+20], height / 2-150
    popa
    ret

.switch_task:
    cli
    sub al, 1
    mov [main_task], ax

    mov bx, [switch_tasks_win_id]
    mov ah, 0x02
    mov edi, switch_tasks_window
    int 0x34
    sti

    mov dword [edi+16], width / 2-250
    mov dword [edi+20], height / 2-150
    popa
    ret
irq14_handler:
    cli
    pusha

    ;stop DMA
    mov dx, [bm_base4]
    xor al, al
    out dx, al

    mov dx, [bm_base4]
    add dx, 2
    in al, dx
    mov bl, al

    mov al, 0x06
    out dx, al
    
    mov dx, 0x1f7
    in al, dx

    ;test if error
    test bl, 0x02
    jnz .error

    cmp byte [ide_running], 1
    jne .done
    mov byte [ide_running], 0

    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    add eax, tasks_esp
    movzx edx, word [max_tasks]
.loop:
    cmp dword [eax+11], 0x0000df00
    je .found
    add eax, TASK_SIZE
    dec edx
    jnz .loop
    jmp .done
.found:
    mov dword [eax+11], 0       ;remove 'wait for drive' attribute

.done:
    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    mov byte [ide_running], 0
    popa
    iret

.error:
    mov al, '%'
    call print_char
    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    mov byte [ide_running], 0
    popa
    iret

irq15_handler:
    cli
    pusha

    mov dx, 0x177
    in al, dx

    mov dx, [bm_base4]
    add dx, 0x0a
    in al, dx
    mov bl, al

    mov al, 0x06
    out dx, al

    ;stop DMA
    mov dx, [bm_base4]
    add dx, 8
    xor al, al
    out dx, al
    
    ;test if error
    test bl, 0x02
    jnz .error

    cmp byte [ide_running], 1
    jne .done
    mov byte [ide_running], 0

    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    add eax, tasks_esp
    movzx edx, word [max_tasks]
.loop:
    cmp dword [eax+11], 0x0000df00
    je .found
    add eax, TASK_SIZE
    dec edx
    jnz .loop
    jmp .done
.found:
    mov dword [eax+11], 0       ;remove 'wait for drive' attribute

.done:
    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    mov byte [ide_running], 0
    popa
    iret

.error:
    mov al, '%'
    call print_char
    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    mov byte [ide_running], 0
    popa
    iret

ahci_interrupt_handler:
    cli
    pusha

    mov eax, [abar]
    mov ebx, [eax+8]
    test ebx, ebx
    jz .done                ;interrupt did not came from the AHCI controller


    ;check which port interrupted... (bit 1 set = port 1, bit 2 set = port 2,...)
    xor ecx, ecx
.loop:
    cmp ecx, 32
    jae .done

    bt ebx, ecx
    jnc .next

    mov edi, eax
    add edi, 0x100
    mov edx, ecx
    shl edx, 7
    add edi, edx

    mov ebp, [edi+0x10]
    mov [edi+0x10], ebp

    mov edx, [edi+0x30]
    mov [edi+0x30], edx
    mov edx, [edi+0x34]
    push ebx
    xor ebx, ebx
.loop2:
    bt edx, ebx
    jc .next2

    mov esi, ecx    ;port
    imul esi, AHCI_PORT_MEM_OFF
    add esi, AHCI_MEM_BASE
    add esi, AHCI_TASK_STRUCT_OFF

    push ecx
    mov ecx, ebx
    shl ecx, 1
    add esi, ecx
    pop ecx

    cmp word [esi], 0
    je .next2

    push eax
    movzx eax, word [esi]
    imul eax, TASK_SIZE
    add eax, tasks_esp
    mov dword [eax+11], 0   ;remove sleeping flag
    mov word [esi], 0       ;clear PID
    pop eax
.next2:
    inc ebx
    cmp ebx, 32
    jb .loop2

    mov edx, 1
    shl edx, ecx
    mov [eax+0x08], edx
    pop ebx
.next:
    inc ecx
    jmp .loop

.done:
    popa
    sti
    ret

ohci_interrupt_handler:
    cli
    pusha
    mov eax, [ohci_base]
    mov ebx, [eax+12]       ;interrupt status
    test ebx, (1 << 1)
    jz .done                ;no WDH
    ; test ebx, (1 << 31)
    ; jz .done
    mov dword [eax+12], (1 << 1)

    ; test ebx, 2
    ; jz .skip_keyboard

    mov edx, [eax+0x30]         ;read DoneHead
    ;mov dword [eax+0x30], 0     ;clear DoneHead to unblock controller
    mov edx, [hcca+0x84]
    mov bl, [edx+16]
    cmp bl, 1
    je .keyboard
    cmp bl, 3
    je .usb_stick
    ;jmp .keyboard
    jmp .done

    ; mov ebx, td_empty
    ; mov [usb_keyboard_td+8], ebx
    ; mov ebx, usb_keyboard_buffer
    ; mov [usb_keyboard_td+4], ebx
    ; mov ebx, usb_keyboard_buffer+7
    ; mov [usb_keyboard_td+12], ebx

    ; mov ebx, [usb_keyboard_td]
    ; and ebx, 0x0fffffff
    ; or ebx, (15 << 28)      ;mark TD as Not Accessed (0x0F)
    ; mov [usb_keyboard_td], ebx

    ; mov ebx, usb_keyboard_td
    ; mov [usb_keyboard_ed+8], ebx
    ; mov ebx, td_empty
    ; mov [usb_keyboard_ed+4], ebx
.keyboard:
    mov ebx, td_empty
    mov edi, [usb_keyboard_tdptr]

    mov [edi+8], ebx
    mov ebx, [usb_keybuffer]
    mov [edi+4], ebx
    mov ebx, [usb_keybuffer]
    add ebx, 7
    mov [edi+12], ebx

    mov ebx, [edi]
    and ebx, 0x0fffffff
    or ebx, (15 << 28)      ;mark TD as Not Accessed (0x0F)
    mov [edi], ebx

    mov ebx, [usb_keyboard_tdptr]
    mov edi, [usb_keyboard_edptr]
    mov [edi+8], ebx
    mov ebx, td_empty
    mov [edi+4], ebx

    ;store keys
    movzx edi, word [main_task]
    mov ebx, edi

    imul edi, KEY_BUFFER_SIZE
    add edi, KEY_BUFFER
    movzx ecx, byte [BUFFER_HEAD+ebx]
    add edi, ecx

    mov esi, [usb_keybuffer]
    ; push esi
    ; push edi
    ; push ecx
    ; mov edi, .last_keyreport
    ; mov ecx, 8
    ; repe cmpsb
    ; pop ecx
    ; pop edi
    ; pop esi
    ; je .done       ;skip same keyreport

    mov al, [esi]
    add esi, 2

    mov [edi], al
    add edi, 1

    cld
    mov ecx, 6
    rep movsb
    
    movzx ecx, byte [BUFFER_HEAD+ebx]
    add ecx, 7
    and ecx, 0xff
    mov [BUFFER_HEAD+ebx], cl
    ; mov ebx, [usb_keybuffer]
    ; movzx ebx, byte [ebx+2]
    ; test ebx, ebx
    ; jz .skip_keyboard

    ; mov al, [usb_keymap+ebx]
    ; call print_char

    ; push esi
    ; push edi
    ; push ecx
    ; mov ecx, 8
    ; mov edi, .last_keyreport
    ; mov esi, [usb_keybuffer]
    ; rep movsb
    ; pop ecx
    ; pop edi
    ; pop esi
    jmp .done
.usb_stick:
    mov byte [edx+17], 0
    mov ebx, [edx+4]    ;CSW Buffer
    cmp dword [ebx], 'USBS'
    cmp byte [ebx+12], 0
    ;jne .error
    ; cli
    ; hlt
.done:
    popa
    ret

.last_keyreport: db 0 dup(8)


irq5_handler:
    pusha
    mov esi, irq5_list
    mov ecx, 4
.loop:
    cld
    lodsd
    cmp eax, 0
    je .skip

    push esi
    push ecx
    call eax
    pop ecx
    pop esi
.skip:
    dec ecx
    jnz .loop

    mov al, 0x20
    out 0x20, al
    popa
    iret

irq9_handler:
    pusha
    mov esi, irq9_list
    mov ecx, 4
.loop:
    cld
    lodsd
    cmp eax, 0
    je .skip

    push esi
    push ecx
    call eax
    pop ecx
    pop esi
.skip:
    dec ecx
    jnz .loop

    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    popa
    iret

irq10_handler:
    pusha
    mov esi, irq10_list
    mov ecx, 4
.loop:
    cld
    lodsd
    cmp eax, 0
    je .skip

    push esi
    push ecx
    call eax
    pop ecx
    pop esi
.skip:
    dec ecx
    jnz .loop

    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    popa

    iret
irq11_handler:
    pusha
    mov esi, irq11_list
    mov ecx, 4
.loop:
    cld
    lodsd
    cmp eax, 0
    je .skip

    push esi
    push ecx
    call eax
    pop ecx
    pop esi
.skip:
    dec ecx
    jnz .loop

    mov al, 0x20
    out 0xa0, al
    out 0x20, al
    popa
    iret

irq5_list: times 4 dd 0
irq9_list: times 4 dd 0
irq10_list: times 4 dd 0
irq11_list: times 4 dd 0

;IRQ 8 handler
rtc_handler:
    cli
    pusha

    inc dword [system_tick]
    call check_timers

    mov dx, 0x70
    mov al, 0x0c
    out dx, al

    nop
    nop

    mov dx, 0x71
    in al, dx

    mov al, 0x20
    out 0x20, al
    out 0xa0, al
    popa
    iret

rsod:
    ;ESI = pointer to reason message
    cli
    mov edi, [frame_buffer]
    mov eax, COLOR_RED
    mov ecx, [real_width]
    imul ecx, dword [real_height]
    movzx ebx, byte [bpp]
.loop:
    mov [edi], eax
    add edi, ebx
    dec ecx
    jnz .loop

    mov dword [cur_x], 0
    mov dword [cur_y], 0

    push esi
    mov esi, .error_msg
    mov ebx, 0x00ffffff
    call print_string
    pop esi

    mov ebx, 0x00ffffff
    call print_string

    ;call reboot
    cli
    hlt
    ret


.error_msg: db ':(', 0x0a,
            db 'Sorry, an critical error occured', 0x0a,
            db 'Reason: ',