;========================================================================================================
;UHCI driver
;Copyright (C) 2026 Technodon
;========================================================================================================
section .text
start:
    ;AX = UHCI I/O Base Address
    mov [uhci_base], ax

    cmp byte [uhci_list_offset], NUM_CONTROLLERS
    jb .save_ioaddr

    stc
    ret

.save_ioaddr:
    movzx ebx, byte [uhci_list_offset]
    shl ebx, 1      ;*2
    add ebx, uhci_controllers

    mov [ebx], ax
    inc byte [uhci_list_offset]

    mov dx, ax
    in ax, dx
    or ax, (1 << 1)
    out dx, ax

.wait_reset:
    in ax, dx
    test ax, (1 << 1)
    jnz .wait_reset

    ;do Global Reset
    in ax, dx
    or ax, (1 << 2)
    out dx, ax

    ;sleep 10ms
    push ax
    mov ah, 0x22
    mov al, 1
    mov ebx, 10
    int 0x35
    pop ax

    in ax, dx
    and ax, ~(1 << 2)
    out dx, ax
    

    ;allocate 4Kib for frame list
    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35

    mov [kernel_packet+12], esi

    mov edi, esi
    mov eax, (1 << 0)
    mov ecx, 0x1000/4
    rep stosd

    mov dx, [uhci_base]
    add dx, 8
    mov eax, esi
    out dx, eax

    sub dx, 2
    xor ax, ax
    out dx, ax

    sub dx, 6
    in ax, dx
    or ax, (1 << 0)     ;run/stop bit
    or ax, (1 << 6)     ;configure flag bit
    or ax, (1 << 7)     ;max packet bit (allows 64 byte packets)
    out dx, ax
    
    ;clear all error flags
    mov ax, 0x0f
    add dx, 2
    out dx, ax

    mov dx, [uhci_base]
    add dx, 0x10        ;port 1 status/control register
    in ax, dx

    test ax, (1 << 0)   ;check Current Connect Status
    jz .port2

    or ax, (1 << 9)     ;set port reset bit
    out dx, ax

    push ax
    mov ah, 0x22
    mov al, 1
    mov ebx, 75
    int 0x35
    pop ax

    in ax, dx
    and ax, ~(1 << 9)
    or ax, (1 << 2)
    or ax, (1 << 1) ;rm Connect Status Change bit
    out dx, ax

    nop
    nop

    in ax, dx
    test ax, (1 << 2)   ;check if port was enabled (PE Bit)
    jz .port2

    xor bh, bh
    test ax, (1 << 8)
    jnz .no_fullspeed1

    or byte [kernel_packet+32], (1 << 0)    ;fullspeed device attached = 1
    mov bh, 1
.no_fullspeed1:
    mov bl, 1
    mov byte [cur_port], 1
    push esi
    call enumerate_usb_device
    pop esi
    jc .port2

    mov ax, cx
    shr ecx, 16
    
    push esi
    mov esi, kernel_packet
    add esi, 32
    mov dword [ep_offset], 2

    push ebp

    cmp al, 0
    je .skip1

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], al
    inc dword [ep_offset]

.skip1:
    cmp ah, 0
    je .skip2

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], ah
    inc dword [ep_offset]
.skip2:
    cmp cl, 0
    je .skip3

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], cl
    inc dword [ep_offset]
.skip3:
    cmp ch, 0
    je .skip4

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], ch
    inc dword [ep_offset]
.skip4:
    mov byte [kernel_packet+33], 1
    pop ebp
    pop esi

    mov ax, dx
    shr edx, 16
    mov [kernel_packet+38], dl
    mov [kernel_packet+39], ah
    mov [kernel_packet+40], al
    mov [kernel_packet+42], bx

    mov bl, al  ;Protocol
    mov al, dl  ;Interface Class

    mov bh, 1
    mov ecx, ebp
    test dword [kernel_packet+32], (1 << 0)
    jnz .fullspeed1

    or ebx, (1 << 16)
.fullspeed1:
    call init_usb_device
    
    mov [kernel_packet+41], al

.port2:
    mov esi, [kernel_packet+12]

    mov dx, [uhci_base]
    add dx, 0x12        ;port 1 status/control register
    in ax, dx

    test ax, (1 << 0)   ;check Current Connect Status
    jz .done

    or ax, (1 << 9)     ;set port reset bit
    out dx, ax

    push ax
    mov ah, 0x22
    mov al, 1
    mov ebx, 75
    int 0x35
    pop ax

    in ax, dx
    and ax, ~(1 << 9)
    or ax, (1 << 2)
    or ax, (1 << 1) ;rm Connect Status Change bit
    out dx, ax

    nop
    nop

    in ax, dx
    test ax, (1 << 2)   ;check if port was enabled (PE Bit)
    jz .done

    xor bh, bh
    test ax, (1 << 8)
    jnz .no_fullspeed2

    or byte [kernel_packet+64], (1 << 0)    ;fullspeed device attached = 1
    mov bh, 1
.no_fullspeed2:
    mov bl, 2
    mov byte [cur_port], 2
    push esi
    call enumerate_usb_device
    pop esi

    jc .done

    mov ax, cx
    shr ecx, 16
    
    push esi
    mov esi, kernel_packet
    add esi, 64
    mov dword [ep_offset], 2

    push ebp

    cmp al, 0
    je .skip5

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], al
    inc dword [ep_offset]

.skip5:
    cmp ah, 0
    je .skip6

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], ah
    inc dword [ep_offset]
.skip6:
    cmp cl, 0
    je .skip7

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], cl
    inc dword [ep_offset]
.skip7:
    cmp ch, 0
    je .skip8

    mov ebp, esi
    add ebp, dword [ep_offset]
    mov [ebp], ch
    inc dword [ep_offset]
.skip8:
    mov byte [kernel_packet+65], 2
    pop ebp
    pop esi

    mov ax, dx
    shr edx, 16
    mov [kernel_packet+70], dl
    mov [kernel_packet+71], ah
    mov [kernel_packet+72], al
    mov [kernel_packet+74], bx

    mov bl, al  ;Protocol
    mov al, dl  ;Interface Class

    mov bh, 1
    mov ecx, ebp
    test dword [kernel_packet+32], (1 << 0)
    jnz .fullspeed2

    or ebx, (1 << 16)
.fullspeed2:
    call init_usb_device

    mov [kernel_packet+73], al

.done:
    mov dx, [uhci_base]
    add dx, 4
    mov ax, (7 << 0)
    out dx, ax

    mov edx, kernel_packet
    mov dword [edx], interrupt_handler
    clc
    ret

enumerate_usb_device:
    ;BL = USB Address
    ;BH = fullspeed (0x01 = yes, 0x00 = no)
    ;ESI = address to frame list

    ;returns:
    ;BX = max. packet size
    ;ECX = Endpoint Addresses (max. 4, 8 bits each)
    ;EDX = Interface Class (bits 16-23), Subclass (bits 8-15), Protocol (bits 0-7)
    ;EDI = pointer to descriptor packet
    ;EBP = size of descriptor packet


    ;1. GET_DESCRIPTOR
    ;2. SET_ADDRESS
    ;3. GET_DESCRIPTOR (1)
    ;4. GET_DESCRIPTOR (2)
    ;5. SET_CONFIGURATION

    mov edi, td_setup
    mov ecx, 32/4
    xor eax, eax
    rep stosd

    mov edi, td_data
    mov ecx, 32/4
    xor eax, eax
    rep stosd

    mov edi, td_status
    mov ecx, 32/4
    xor eax, eax
    rep stosd

    mov dword [queue_head], 0
    mov dword [queue_head+4], 0

    mov dword [td_setup+8], 0x2d   ;SETUP
    mov dword [td_data+8], 0x69    ;IN
    mov dword [td_status+8], 0xe1  ;OUT

    cmp bh, 1
    je .skip

    ;set device to low speed
    or dword [td_setup+4], (1 << 26)
    or dword [td_data+4], (1 << 26)
    or dword [td_status+4], (1 << 26)
.skip:
    mov dword [td_setup], td_data
    mov dword [td_data], td_status
    mov dword [td_status], 1
    mov dword [queue_head], 1

    or dword [td_setup+4], (1 << 23)
    or dword [td_data+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    or dword [td_setup+8], (7 << 21)   ;max packet length = 8 bytes
    mov dword [td_setup+12], setup_packet

    or dword [td_data+8], (1 << 19)
    or dword [td_data+8], (17 << 21)   ;max packet length = 18 bytes
    mov dword [td_data+12], descriptor_buffer

    or dword [td_status+8], (1 << 19)
    or dword [td_status+8], (0x7ff << 21)  ;max packet length = 0 bytes
    mov dword [queue_head+4], td_setup

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    mov [setup_packet2+2], bl

    ;SET_ADDRESS
    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup+8], 0x2d
    or dword [td_setup+8], (7 << 21)   ;max packet length = 8 bytes
    mov dword [td_setup+12], setup_packet2

    mov dword [td_status+8], 0x69
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    mov dword [queue_head+4], td_setup
    mov dword [td_setup], td_status
    mov dword [td_status], 1

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    ;GET_DESCRIPTOR
    or dword [td_setup+4], (1 << 23)
    or dword [td_data+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    movzx edx, bl
    shl edx, 8
    or dword [td_setup+8], edx
    or dword [td_data+8], edx
    or dword [td_status+8], edx

    or dword [td_setup+8], (7 << 21)
    or dword [td_data+8], (8 << 21)
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    or dword [td_data+8], (1 << 19)
    or dword [td_status+8], (1 << 19)

    mov dword [td_setup+12], setup_packet3
    mov dword [td_data+12], descriptor_buffer

    mov dword [td_setup], td_data
    mov dword [td_data], td_status
    mov dword [td_status], 1
    mov dword [queue_head+4], td_setup

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    ;GET_DESCRIPTOR

    movzx eax, word [descriptor_buffer+2]
    mov [setup_packet4+6], ax

    or dword [td_setup+4], (1 << 23)
    or dword [td_data+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    movzx edx, bl
    shl edx, 8
    or dword [td_setup+8], edx
    or dword [td_data+8], edx
    or dword [td_status+8], edx

    or dword [td_setup+8], (7 << 21)
    shl eax, 21
    or dword [td_data+8], eax
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    or dword [td_data+8], (1 << 19)
    or dword [td_status+8], (1 << 19)

    mov dword [td_setup+12], setup_packet4
    mov dword [td_data+12], descriptor_buffer

    mov dword [td_setup], td_data
    mov dword [td_data], td_status
    mov dword [td_status], 1
    mov dword [queue_head+4], td_setup

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    ;SET_CONFIGURATION
    mov al, [descriptor_buffer]
    mov [setup_packet5+2], al

    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup+8], 0x2d
    or dword [td_setup+8], (7 << 21)
    mov dword [td_setup+12], setup_packet5

    mov dword [td_status+8], 0x69
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    movzx edx, bl
    shl edx, 8
    or dword [td_setup+8], edx
    or dword [td_status+8], edx

    mov dword [queue_head+4], td_setup
    mov dword [td_setup], td_status
    mov dword [td_status], 1

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    mov edi, descriptor_buffer
    movzx ebp, word [setup_packet4+6]
    xor ecx, ecx

    mov esi, edi
    push ebp
.loop:
    movzx eax, byte [edi]
    mov ah, [edi+1]
    cmp ah, 4
    je .interface_descriptor
    cmp ah, 5
    je .ep_descriptor

.next:
    xor ah, ah
    add edi, eax
    sub ebp, eax
    cmp ebp, 0
    jg .loop

    pop ebp
    mov edi, esi
    clc
    ret

.interface_descriptor:
    movzx edx, byte [edi+5] ;Interface Class
    shl edx, 16
    mov dh, [edi+6]     ;Subclass
    mov dl, [edi+7]     ;Protocol
    jmp .next

.ep_descriptor:
    shl ecx, 8
    mov cl, [edi+2]     ;Endpoint Address

    mov bx, [edi+4]     ;max. packet size
    jmp .next

.error:
    popa
    stc
    ret

wait_controller:
    ;ESI = address to frame list
    ;EAX = *Queue Head
    ;EDX = *status TD

    pusha
    mov edi, esi
    mov ecx, 1024/4
    or eax, 2

    mov ebx, 4
    xor ebp, ebp
.search:
    cmp dword [edi], 1
    je .loop

    add edi, 4
    inc ebp
    dec ebx
    jnz .search

    popa
    stc
    ret

.loop:
    mov [edi], eax
    add edi, FL_OFFSET
    dec ecx
    jnz .loop

.wait1:
    test dword [edx+4], (1 << 23)
    jnz .wait1

    mov edi, esi
    imul ebp, 4
    add edi, ebp

    mov ecx, 1024/4
    mov eax, 1
.loop2:
    mov [edi], eax
    add edi, FL_OFFSET
    dec ecx
    jnz .loop2

    popa
    clc
    ret

check_error:
    test dword [td_status+4], (1 << 22)    ;STALL
    jnz .error
    test dword [td_status+4], (1 << 18)    ;Timeout
    jnz .error

    clc
    ret
.error:
    stc
    ret


init_usb_device:
    ;AL = Interface Descriptor
    ;AH = Subclass
    ;BL = Protocol
    ;BH = USB Address
    ;bit 16 of EBX: low speed (1 = yes, 0 = no)
    ;ECX = length if device descriptor buffer
    ;EDI = buffer of device descriptor
    ;ESI = address of frame list

    ;returns:
    ;AL = USB device
    ;AL = 0xff, if there was an error while initializing device

    cmp al, 3
    je .hid
    cmp al, 7
    je .printer
    cmp al, 8
    je .mass_storage
    cmp al, 9
    je .usb_hub

.error:
    xor al, al
    stc
    ret
.error2:
    mov al, 0xff
    stc
    ret

.hid:
    cmp ah, 0
    je .hid_report_protocol
    cmp ah, 1
    je .hid_boot_interface
    jmp .error

.hid_boot_interface:
    cmp bl, 1
    je .hid_boot_keyboard
    cmp bl, 2
    je .hid_boot_mouse
    jmp .error

.hid_report_protocol:
    cmp bl, 0
    je .report_descriptor
    jmp .error

.mass_storage:
    cmp ah, 6
    je .scsi_transparent
    cmp ah, 7
    je .scsi
    jmp .error

.scsi_transparent:
    cmp bl, 0x50
    je .scsi_bot_storage
    jmp .error

.scsi:
    cmp bl, 0x50
    je .scsi_bot_storage
    jmp .error

.usb_hub:
    mov al, 6
    jmp .done

.printer:
    mov al, 5
    jmp .done

; #### BOOT KEYBOARD AND MOUSE PROTOCOL ####
.hid_boot_keyboard:
    call init_boot_keyboard
    jc .error2

    mov al, 1
    jmp .done
.hid_boot_mouse:
    call init_boot_mouse
    jc .error2

    mov al, 2
    jmp .done

; #### HID DEVICE REPORT PROTOCOL ####
.report_descriptor:
    xor al, al
    jmp .done

; #### SCSI BOT USB STICK ####
.scsi_bot_storage:
    call init_scsi_bot
    jc .error2

    mov al, 3
    jmp .done
.done:
    clc
    ret


init_boot_keyboard:
    ;BH = USB Address
    ;EDI = buffer of device descriptor
    ;ECX = size of device descriptor buffer
    ;ESI = address of frame list
    ;Bit 16 of EBX = low speed device (1 = yes, 0 = no)

    movzx eax, byte [edi]
    mov ah, [edi+1]
    cmp ah, 5
    je .found_ep

.next:
    xor ah, ah
    add edi, eax
    sub ecx, eax
    cmp ecx, 0
    jg init_boot_keyboard
    jmp .error

.found_ep:
    mov bl, [edi+2]     ;endpoint address
    test bl, (1 << 7)
    jz .next

    ;SET_PROTOCOL (boot)
    mov byte [kb_setup_packet], 0x21
    mov byte [kb_setup_packet+1], 0x0b  ;SET_PROTOCOL
    mov word [kb_setup_packet+2], 0
    mov word [kb_setup_packet+4], 0
    mov word [kb_setup_packet+6], 0

    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup+8], 0x2d
    or dword [td_setup+8], (7 << 21)
    mov dword [td_setup+12], kb_setup_packet

    mov dword [td_status+8], 0xe1
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    movzx edx, bh
    shl edx, 8
    or dword [td_setup+8], edx
    or dword [td_status+8], edx

    mov dword [queue_head+4], td_setup
    mov dword [td_setup], td_status
    mov dword [td_status], 1

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    ;SET_IDLE
    mov byte [kb_setup_packet+1], 0x0a

    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup+8], 0x2d
    or dword [td_setup+8], (7 << 21)
    mov dword [td_setup+12], kb_setup_packet

    mov dword [td_status+8], 0xe1
    or dword [td_status+8], (1 << 19) | (0x7ff << 21)

    movzx edx, bh
    shl edx, 8
    or dword [td_setup+8], edx
    or dword [td_status+8], edx

    mov dword [queue_head+4], td_setup
    mov dword [td_setup], td_status
    mov dword [td_status], 1

    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    jc .error
    call check_error
    jc .error

    mov edx, ebx
    and edx, (1 << 16)
    shl edx, 10

    mov dword [usb_keyboard_td], 1
    or dword [usb_keyboard_td+4], (1 << 23) | (1 << 24)
    or dword [usb_keyboard_td+4], edx       ;set low speed bit

    mov dword [usb_keyboard_td+8], 0x69
    movzx edx, bh
    shl edx, 8
    or dword [usb_keyboard_td+8], edx
    movzx edx, bl
    and edx, 0x0f
    shl edx, 15
    or dword [usb_keyboard_td+8], edx
    or dword [usb_keyboard_td+8], (7 << 21)
    mov dword [usb_keyboard_td+12], key_buffer

    mov dword [usb_keyboard_qh+4], usb_keyboard_td
    mov dword [usb_keyboard_qh], 1
    mov byte [usb_keyboard_td+16], 1   ;mark TD as "boot keyboard TD"
    mov al, [cur_port]
    mov [usb_keyboard_td+17], al

    mov edi, esi

    ;find free index for QH
    mov ecx, 4
.loop:
    cmp dword [edi], 1
    je .found_free

    add edi, 4
    dec ecx
    jnz .loop
    jmp .error

.found_free:
    mov eax, usb_keyboard_qh
    or eax, 2

    mov ecx, 1024/4
.loop2:
    mov [edi], eax
    add edi, FL_OFFSET
    dec ecx
    jnz .loop2
    clc

    ret
.error:
    stc
    ret

init_boot_mouse:
    ret

init_scsi_bot:
    ;BH = USB Address
    ;EDI = buffer of device descriptor
    ;ECX = size of device descriptor buffer
    ;ESI = address of frame list
    ;Bit 16 of EBX = low speed device (1 = yes, 0 = no)

    movzx eax, byte [edi]
    mov ah, [edi+1]
    cmp ah, 5
    je .found_ep

.next:
    xor ah, ah
    add edi, eax
    sub ecx, eax
    cmp ecx, 0
    jg init_scsi_bot
    jmp .error

.found_ep:
    mov bl, [edi+2]
    test bl, (1 << 7)
    jnz .ep_in
    
    mov dh, bl

    test bh, (1 << 5)
    jnz .send_inquiry

    or bh, (1 << 7)
    jmp .next

.ep_in:
    mov dl, bl
    test bh, (1 << 7)   ;Endpoint OUT found
    jnz .send_inquiry

    or bh, (1 << 5)
    jmp .next

.send_inquiry:
    ;DL = IN Endpoint
    ;DH = OUT Endpoint

    and bh, 0x0f

    mov dword [td_status+8], 0xe1   ;OUT
    movzx ecx, bh
    shl ecx, 8
    or dword [td_status+8], ecx     ;set USB address
    movzx ecx, dh
    and ecx, 0x0f
    shl ecx, 15
    or dword [td_status+8], ecx
    or dword [td_status+8], (30 << 21)

    mov dword [td_status+12], cbw
    mov dword [td_status], td_data

    ret

.error:
    stc
    ret
interrupt_handler:
    pusha
    mov ecx, NUM_CONTROLLERS
    mov edi, uhci_controllers
    cli
    hlt

.loop:
    mov dx, [edi]
    cmp dx, 0
    je .done

    add dx, 2
    in ax, dx
    test ax, (1 << 0)
    jnz .interrupt
    test ax, (1 << 1)
    jnz .interrupt
    test ax, (1 << 2)
    jnz .interrupt
    test ax, (1 << 3)
    jnz .interrupt
    test ax, (1 << 4)
    jnz .interrupt
    test ax, (1 << 5)
    jnz .interrupt

    add edi, 2
    dec ecx
    jnz .loop
    jmp .done
.interrupt:
    cli
    hlt

    out dx, ax
    test ax, (1 << 0)
    jnz .find_td
    jmp .done

.find_td:
    add dx, 6
    in eax, dx

    mov ecx, 4
    xor ebp, ebp
.loop2:
    test dword [eax], (1 << 0)
    jz .qh

.next:
    inc ebp
    add eax, 4
    dec ecx
    jnz .loop2
    jmp .done

.qh:
    mov ebx, [eax]      ;take pointer to QH
    and ebx, ~(1 << 1)
    mov ebx, [ebx+4]      ;take pointer to TD
.check_td:
    test dword [ebx+4], (1 << 23)
    jnz .next

    test dword [ebx+4], (1 << 24)
    jz .next_td
    jmp .td_found

.next_td:
    test dword [ebx], (1 << 0)
    jnz .next

    mov ebx, [ebx]
    jmp .check_td

.td_found:
    mov al, [ebx+16]        ;TD type (keyboard/BOT/...)
    cmp al, 1
    je .boot_keyboard
    
.done:
    popa
    ret

.boot_keyboard:
    mov dword [ebx+12], key_buffer
    mov eax, [ebx+8]
    test eax, (1 << 19)
    jz .set_datatoggle

    and eax, ~(1 << 19)
    jmp .kb_continue
.set_datatoggle:
    or eax, (1 << 19)
.kb_continue:
    mov [ebx+8], eax

    test dword [ebx+4], (1 << 16)
    jnz .kb_error
    test dword [ebx+4], (1 << 17)
    jnz .kb_error
    test dword [ebx+4], (1 << 18)
    jnz .kb_error
    test dword [ebx+4], (1 << 20)
    jnz .kb_error
    test dword [ebx+4], (1 << 21)
    jnz .kb_error
    test dword [ebx+4], (1 << 22)
    jnz .kb_error

    mov edi, key_buffer
    cli
    hlt

.kb_skip_data:
    mov dword [ebx+4], 0
    or dword [ebx+4], (1 << 24) | (1 << 23)
    jmp .done

.kb_error:
    cmp byte [ebx+17], 1
    je .kb_port1

    sub dx, 8   ;DX should point to USBCMD
    add dx, 0x10

    in ax, dx
    test ax, (1 << 0)
    jnz .kb_skip_data

    ;device isnt connected anymore to USB Port
    imul ebp, 4
    sub dx, 8   ;DX should point to frame list register
    in eax, dx
    add eax, ebp

    ;remove TD from frame list
    mov ecx, 1024/4
.kb_loop1:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .kb_loop1
    jmp .done
.kb_port1:
    sub dx, 8
    add dx, 0x12

    in ax, dx
    test ax, (1 << 0)
    jnz .kb_skip_data

    imul ebp, 4
    sub dx, 10
    in eax, dx
    add eax, ebp

    ;remove TD from frame list
    mov ecx, 1024/4
.kb_loop2:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .kb_loop2
    jmp .done

section .data
setup_packet:
    db 0x80
    db 0x06
    dw 0x0100
    dw 0
    dw 18
setup_packet2:
    db 0
    db 0x05
    dw 0    ;USB address
    dw 0
    dw 0
setup_packet3:
    db 0x80
    db 0x06
    db 0,2
    dw 0
    db 9,0

setup_packet4:
    db 0x80
    db 0x06
    db 0,2
    dw 0
    dw 0
  
setup_packet5:
    db 0
    db 0x09
    dw 0
    dw 0
    dw 0
kb_setup_packet:
    db 0
    db 0
    dw 0
    dw 0
    dw 0

descriptor_buffer: times 128 db 0
cbw:
    dd 'USBC'       ;signature
    dd 0x77777777   ;tag
    dd 0            ;transfer length
    db 0            ;flags (0x80 = in)
    db 0            ;LUN
    db 0            ;length of CDB
    times 16 db 0

uhci_base: dw 0     ;base I/O address
ep_offset: dd 0
uhci_controllers: times 4 dw 0
;max. 4 controllers supported
uhci_list_offset: db 0
NUM_CONTROLLERS     equ 4
cur_port: db 0


kernel_packet:
    dd 0    ;interrupt_handler

    dd 0    ;usb_read_sectors
    dd 0    ;usb_write_sectors

    dd 0    ;frame list
    times 16 db 0

    ;port #1
    times 32 db 0
    ;+0: port information
    ; - bit 0: fullspeed device attached
    ;+1: USB address
    ;+2: Endpoint 1
    ;+3: Endpoint 2
    ;+4: Endpoint 3
    ;+5: Endpoint 4
    ;+6: Interface Class
    ;+7: Subclass
    ;+8: Protocol
    ;+9: USB device (keyboard, USB Stick, mouse, ...)
    ;+10: max. packet size

    ;port #2
    times 32 db 0

FL_OFFSET   equ 4*4

;USB devices (offset +9 in kernel packet)
;0x00: Unknown
;0x01: Boot Keyboard
;0x02: Boot Mouse
;0x03: USB Storage Device
;0x04: USB 1.1 floppy
;0x05: Printer
;0x06: USB Hub
;0x07: Fast External SSD
;0x0A: Keyboard (device report protocol)
;0x0B: Mouse (device report protocol)
;0xff: error
;0xee: end of list
section .bss align=16
alignb 16
td_setup: resd 8
td_data: resd 8
td_status: resd 8
usb_keyboard_td: resd 8

queue_head: resd 2
usb_keyboard_qh: resd 2

key_buffer: resd 2