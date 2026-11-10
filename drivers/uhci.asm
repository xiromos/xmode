;========================================================================================================
;UHCI driver
;Copyright (C) 2026 Technodon
;========================================================================================================
section .text
start:
    ;AX = UHCI I/O Base Address
    ;EDX = pointer to uhci_structure

    mov [uhci_base], ax
    mov [driver_packet], edx

    cmp byte [uhci_list_offset], NUM_CONTROLLERS
    jb .save_ioaddr

    stc
    ret

.save_ioaddr:
    movzx ebx, byte [uhci_list_offset]
    shl ebx, 1      ;*2
    add ebx, uhci_controllers

    mov [ebx], ax
    movzx ebx, byte [uhci_list_offset]
    shl ebx, 1      ;*2
    add ebx, device_list

    mov [ebx], ax

    inc byte [uhci_list_offset]

    ;clear kernel packet
    push eax
    mov edi, kernel_packet
    xor eax, eax
    mov ecx, 96/4
    rep stosd
    pop eax

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

    or byte [kernel_packet+32], (1 << 2)    ;device attached = true

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
    cmp edi, 0
    je .port2

    ; #################################
    cmp al, 3
    je .port1_dev3
    jmp .port2

.port1_dev3:
    ;USB Storage device
    push esi
    mov esi, usbstick_buffer
    mov edi, usbstick_buffer1
    mov ecx, 48
    rep movsb
    pop esi
    mov dword [kernel_packet+48], usbstick_buffer1
    test byte [kernel_packet+34], (1 << 7)
    jnz .port1_dev3in

    mov al, [bulk_out_t]
    mov [kernel_packet+44], al
    mov al, [bulk_in_t]
    mov [kernel_packet+45], al
    jmp .port2
.port1_dev3in:
    mov al, [bulk_in_t]
    mov [kernel_packet+44], al
    mov al, [bulk_out_t]
    mov [kernel_packet+45], al

    ; #################################

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
    or byte [kernel_packet+64], (1 << 1) | (1 << 2)  ;port number = 1 + device attached = true

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

    mov bh, 2
    mov ecx, ebp
    test dword [kernel_packet+32], (1 << 0)
    jnz .fullspeed2

    or ebx, (1 << 16)
.fullspeed2:
    call init_usb_device

    mov [kernel_packet+73], al
    cmp edi, 0
    je .done

    ; #################################
    cmp al, 3
    je .port2_dev3
    jmp .done

.port2_dev3:
    ;USB Storage device
    push esi
    mov esi, usbstick_buffer
    mov edi, usbstick_buffer2
    mov ecx, 48
    rep movsb
    pop esi
    mov dword [kernel_packet+80], usbstick_buffer2
    test byte [kernel_packet+66], (1 << 7)
    jnz .port2_dev3in

    mov al, [bulk_out_t]
    mov [kernel_packet+76], al
    mov al, [bulk_in_t]
    mov [kernel_packet+77], al
    jmp .done

.port2_dev3in:
    mov al, [bulk_in_t]
    mov [kernel_packet+76], al
    mov al, [bulk_out_t]
    mov [kernel_packet+77], al

    ; #################################

.done:
    mov dx, [uhci_base]
    add dx, 4
    mov ax, (7 << 0)
    out dx, ax

    mov edx, kernel_packet
    mov dword [edx], interrupt_handler
    mov dword [edx+4], usb_read_sectors
    mov dword [edx+8], usb_write_sectors
    mov dword [edx+16], save_usb_dev
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
    ;EDI = pointer to buffer with more information, (if 0 then there is no such buffer)

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
    xor edi, edi
    stc
    ret
.error2:
    mov al, 0xff
    xor edi, edi
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
    xor edi, edi
    jmp .done

.printer:
    mov al, 5
    xor edi, edi
    jmp .done

; #### BOOT KEYBOARD AND MOUSE PROTOCOL ####
.hid_boot_keyboard:
    call init_boot_keyboard
    jc .error2

    mov al, 1
    xor edi, edi
    jmp .done
.hid_boot_mouse:
    call init_boot_mouse
    jc .error2

    mov al, 2
    xor edi, edi
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
    mov edi, usbstick_buffer
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

    mov ecx, ebx
    and ecx, (1 << 16)
    shl ecx, 10

    ;SET_PROTOCOL (boot)
    mov byte [kb_setup_packet], 0x21
    mov byte [kb_setup_packet+1], 0x0b  ;SET_PROTOCOL
    mov word [kb_setup_packet+2], 0
    mov word [kb_setup_packet+4], 0
    mov word [kb_setup_packet+6], 0

    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)
    or dword [td_setup+4], ecx
    or dword [td_status+4], ecx

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
    mov dword [usb_keyboard_td+20], usb_keyboard_qh
    mov ax, [uhci_base]
    mov [usb_keyboard_td+24], ax

    mov edi, esi

    ;find free index for QH
    cli
    mov ecx, 4
    xor bl, bl
.loop:
    cmp dword [edi], 1
    je .found_free

    add edi, 4
    inc bl
    dec ecx
    jnz .loop
    sti
    jmp .error

.found_free:
    mov eax, usb_keyboard_qh
    or eax, 2
    mov byte [usb_keyboard_td+18], bl

    mov ecx, 1024/4
.loop2:
    mov [edi], eax
    add edi, FL_OFFSET
    dec ecx
    jnz .loop2

    mov eax, usb_keyboard_td
    call set_active_td
    sti
    jc .error

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

    ;cant handle low speed devices because of packet sizes bigger than 8 Byte
    test ebx, (1 << 16)
    jnz .error

    mov dword [td_setup+4], 0
    mov dword [td_data+4], 0
    mov dword [td_status+4], 0

    mov dword [cbw+8], 36
    mov byte [cbw+12], 0x80     ;IN
    mov byte [cbw+13], 0
    mov byte [cbw+14], 6        ;length of command
    mov byte [cbw+15], 0x12     ;INQUIRY
    mov dword [cbw+16], 0
    mov byte [cbw+19], 36       ;allocation length
    mov byte [cbw+20], 0

    ;configure CBW (Command Block Wrapper) TD
    ;direction: OUT
    ;data toggle: DATA0
    ;buffer length: 31

    mov dword [td_setup+8], 0xe1   ;OUT
    movzx ecx, bh
    shl ecx, 8
    or dword [td_setup+8], ecx     ;set USB address
    movzx ecx, dh
    and ecx, 0x0f
    shl ecx, 15
    or dword [td_setup+8], ecx
    or dword [td_setup+8], (30 << 21)

    or dword [td_setup+4], (1 << 23)
    mov dword [td_setup+12], cbw
    mov dword [td_setup], td_data

    ;configure Data TD
    ;direction: IN
    ;data toggle: DATA0
    ;buffer length: 36

    mov dword [td_data+8], 0x69
    movzx ecx, bh
    shl ecx, 8
    or dword [td_data+8], ecx
    movzx ecx, dl
    and ecx, 0x0f
    shl ecx, 15
    or dword [td_data+8], ecx
    or dword [td_data+8], (35 << 21)

    or dword [td_data+4], (1 << 23)
    mov dword [td_data+12], descriptor_buffer   ;use random buffer
    mov dword [td_data], td_status

    ;Configure CSW (Command Status Wrapper) TD
    ;direction: IN
    ;data toggle: DATA1
    ;buffer length: 13

    mov dword [td_status+8], 0x69
    movzx ecx, bh
    shl ecx, 8
    or dword [td_status+8], ecx
    movzx ecx, dl
    and ecx, 0x0f
    shl ecx, 15
    or dword [td_status+8], ecx
    or dword [td_status+8], (12 << 21) | (1 << 19)

    or dword [td_status+4], (1 << 23)
    mov dword [td_status+12], csw_buffer
    mov dword [td_status], 1

    mov dword [queue_head], 1
    mov dword [queue_head+4], td_setup

    push edx
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop edx
    jc .error

    cmp byte [csw_buffer+12], 0
    jne .error

    ;keep track of data toggle of endpoints
    mov byte [bulk_in_t], 1
    mov byte [bulk_out_t], 0

    push esi
    mov esi, descriptor_buffer
    add esi, 8
    mov edi, usbstick_buffer
    mov ecx, 8+16   ;copy vendor ID + Product ID
    rep movsb
    pop esi

    xor ebp, ebp

    ;send TEST UNIT READY
.send_test_unit:
    cmp ebp, 1
    ja .error

    mov dword [cbw+8], 0
    mov byte [cbw+12], 0
    mov byte [cbw+14], 6
    mov dword [cbw+15], 0
    mov dword [cbw+19], 0

    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup], td_status
    mov dword [td_status], 1

    and dword [td_setup+8], ~(1 << 19)
    and dword [td_status+8], ~(1 << 19)

    ; movzx ecx, byte [bulk_out_t]
    ; not ecx
    ; and ecx, 1  ;rm all bits except bit 0
    ; mov [bulk_out_t], cl
    ; shl ecx, 19
    ; or dword [td_setup+8], ecx
    mov ecx, bulk_out_t
    call get_dtoggle
    or dword [td_setup+8], ecx

    ; movzx ecx, byte [bulk_in_t]
    ; not ecx
    ; and ecx, 1  ;rm all bits except bit 0
    ; mov [bulk_in_t], cl
    ; shl ecx, 19
    ; or dword [td_status+8], ecx

    mov ecx, bulk_in_t
    call get_dtoggle
    or dword [td_status+8], ecx

    mov dword [queue_head+4], td_setup

    push edx
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop edx
    jc .error

    cmp byte [csw_buffer+12], 2
    je .error
    cmp byte [csw_buffer+12], 0
    je .send_read_capacity

    inc ebp

    ; ## SEND REQUEST SENSE ##
    or dword [td_setup+4], (1 << 23)
    or dword [td_data+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup], td_data
    mov dword [td_data], td_status
    mov dword [td_status], 1

    and dword [td_setup+8], ~(1 << 19)
    and dword [td_data+8], ~(1 << 19)
    and dword [td_status+8], ~(1 << 19)

    and dword [td_data+8], ~(0x7ff << 21)
    or dword [td_data+8], (17 << 21)

    mov dword [td_data+12], descriptor_buffer

    mov ecx, bulk_out_t
    call get_dtoggle
    or dword [td_setup+8], ecx

    mov ecx, bulk_in_t
    call get_dtoggle
    or dword [td_data+8], ecx

    mov ecx, bulk_in_t
    call get_dtoggle
    or dword [td_status+8], ecx

    mov dword [queue_head+4], td_setup

    mov dword [cbw+8], 18
    mov byte [cbw+12], 0x80
    mov byte [cbw+13], 0
    mov byte [cbw+14], 6
    mov byte [cbw+15], 3
    mov dword [cbw+16], 0
    mov byte [cbw+19], 18
    mov byte [cbw+20], 0    

    push edx
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop edx
    jc .error

    cmp byte [descriptor_buffer+2], 2
    je .not_ready
    cmp byte [descriptor_buffer+2], 6
    je .send_test_unit      ;try again
    jmp .error

.not_ready:
    ;sleep 50ms

    push ebx
    mov ah, 0x22
    mov al, 1
    mov ebx, 50
    int 0x35
    pop ebx

    jmp .send_test_unit

.send_read_capacity:
    ; ## SEND READ CAPACITY (10) ##
    
    mov dword [cbw+8], 8
    mov byte [cbw+12], 0x80
    mov byte [cbw+13], 0
    mov byte [cbw+14], 10
    mov byte [cbw+15], 0x25
    mov dword [cbw+16], 0
    mov dword [cbw+20], 0
    mov byte [cbw+24], 0

    or dword [td_setup+4], (1 << 23)
    or dword [td_data+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    mov dword [td_setup], td_data
    mov dword [td_data], td_status
    mov dword [td_status], 1

    and dword [td_setup+8], ~(1 << 19)
    and dword [td_data+8], ~(1 << 19)
    and dword [td_status+8], ~(1 << 19)

    and dword [td_data+8], ~(0x7ff << 21)
    or dword [td_data+8], (7 << 21)

    mov dword [td_data+12], descriptor_buffer

    mov ecx, bulk_out_t
    call get_dtoggle
    or dword [td_setup+8], ecx

    mov ecx, bulk_in_t
    call get_dtoggle
    or dword [td_data+8], ecx

    mov ecx, bulk_in_t
    call get_dtoggle
    or dword [td_status+8], ecx

    mov dword [queue_head+4], td_setup

    push edx
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop edx
    jc .error

    mov edi, descriptor_buffer
    mov eax, [edi]      ;max. LBA
    call swap
    mov [usbstick_buffer+24], eax

    mov eax, [edi+4]    ;block size
    call swap
    mov [usbstick_buffer+28], eax

    clc
    ret

.error:
    stc
    ret

get_dtoggle:
    ;ECX = pointer to current data toggle of endpoint
    ;Output: ECX = bit 19: DATA0 or DATA1, updatet current data toggle

    push edx
    mov edx, ecx
    movzx ecx, byte [ecx]
    not ecx
    and ecx, 1
    mov [edx], cl
    shl ecx, 19
    pop edx
    ret
get_dtoggle2:
    ;ECX = pointer to current data toggle of endpoint
    ;Output: ECX = bit 19: DATA0 or DATA1, updatet current data toggle
    ;doesnt write the data toggle value back

    push edx
    mov edx, ecx
    movzx ecx, byte [ecx]
    not ecx
    and ecx, 1
    shl ecx, 19
    pop edx
    ret

swap:
    push ebx
    xor ebx, ebx
    mov bx, ax
    xchg bh, bl
    shl ebx, 16
    shr eax, 16
    mov bx, ax
    xchg bh, bl
    mov eax, ebx
    pop ebx
    ret

set_active_td:
    ;EAX = TD
    pusha
    mov edi, active_tds
    mov ecx, MAX_ACTIVE_TDS
.loop:
    cmp dword [edi], 0
    je .found_free

    add edi, 4
    dec ecx
    jnz .loop

    popa
    stc
    ret
.found_free:
    mov [edi], eax
    popa
    clc
    ret

save_usb_dev:
    ;BL = index in USB_LIST
    ;BH = port number (port 0 or port 1)
    ;SI = base I/O address of controller

    push ecx
    push edi
    mov ecx, NUM_CONTROLLERS
    mov edi, device_list
.loop:
    cmp word [edi], si
    je .found

    add edi, 4
    dec ecx
    jnz .loop

    pop edi
    pop ecx
    stc
    ret
.found:
    add edi, 2
    movzx ecx, bh   ;0 or 1
    add edi, ecx
    mov [edi], bl

    pop edi
    pop ecx
    clc
    ret
    
get_dev_index:
    ;finds index in USB_LIST of the device and removes it from device_list
    ;AL = port number
    ;DX = base I/O address

    pusha
    mov edi, device_list
    mov ecx, NUM_CONTROLLERS
.loop:
    cmp word [edi], dx
    je .found

    add edi, 4
    dec ecx
    jnz .loop
    popa
    stc
    ret
.found:
    add edi, 2
    movzx ecx, al
    add edi, ecx
    mov al, [edi]
    mov byte [edi], 0xff
    popa
    clc
    ret

usb_read_sectors:
    ;AX = number of sectors to read
    ;EAX (bits 16 - 23): IN endpoint
    ;EAX (bits 24 - 31): OUT endpoint
    ;BL = protocol
    ;BH = USB address
    ;EBX (bits 16 - 23): data toggle state for IN endpoint
    ;EBX (bits 24 - 31): data toggle state for OUT endpoint
    ;ECX = LBA
    ;ESI = pointer to structure
    ;EDI = buffer address

    ;structure:
    ;   dw base_address (I/O)
    ;   dd block size
    ;   dd max. LBA
    ;   db port number (0 or 1)
    ;   dd 0

    pusha

    cmp bl, 0x50
    jne .error
    cmp ax, 0
    je .error
    cmp word [esi], 0
    je .error
    cmp dword [esi+2], 0
    je .error
    cmp dword [esi+6], ecx
    jbe .error

    sti
.wait_loop:
    cmp byte [running], 0
    jne .wait_loop

    cli
    mov byte [running], 1
    sti

    mov [esi+11], bh

    push eax
    push ecx
    push edi

    mov dx, [esi]
    add dx, 8
    in eax, dx
    mov [frame_list], eax

    mov edi, bulk_cbw_td
    xor eax, eax
    mov ecx, 32/4
    rep stosd

    mov edi, bulk_csw_td
    xor eax, eax
    mov ecx, 32/4
    rep stosd

    pop edi
    pop ecx
    pop eax

    push ax
    push bx
    shr eax, 16
    shr ebx, 16

    mov byte [esi+12], al   ;IN Endpoint
    mov byte [esi+13], ah   ;OUT Endpoint

    mov dword [bulk_data_tds], bulk_data1_td
    mov dword [bulk_data_tds+4], bulk_data2_td
    mov dword [bulk_data_tds+8], bulk_data3_td
    mov dword [bulk_data_tds+12], bulk_data4_td
    mov dword [bulk_data_tds+16], bulk_data5_td
    mov dword [bulk_data_tds+20], bulk_data6_td
    mov dword [bulk_data_tds+24], bulk_data7_td
    mov dword [bulk_data_tds+28], bulk_data8_td

    push esi
    push ecx
    push eax
    push edi

    mov esi, bulk_data_tds
    mov ecx, 8
.loop4:
    lodsd
    
    push ecx
    mov edi, eax
    xor eax, eax
    mov ecx, 32/4
    rep stosd
    pop ecx

    dec ecx
    jnz .loop4

    pop edi
    pop eax
    pop ecx
    pop esi

    ;set endpoints
    movzx edx, ah
    and edx, 0x0f
    shl edx, 15
    or dword [bulk_cbw_td+8], edx

    movzx edx, al
    and edx, 0x0f
    shl edx, 15
    or dword [bulk_data1_td+8], edx
    or dword [bulk_data2_td+8], edx
    or dword [bulk_data3_td+8], edx
    or dword [bulk_data4_td+8], edx
    or dword [bulk_data5_td+8], edx
    or dword [bulk_data6_td+8], edx
    or dword [bulk_data7_td+8], edx
    or dword [bulk_data8_td+8], edx

    or dword [bulk_csw_td+8], edx
    or dword [bulk_csw_td+4], (1 << 24)

    ;set data toggle
    mov [bulk_in_t2], bl
    mov [bulk_out_t2], bh

    push ecx
    mov ecx, bulk_out_t2
    call get_dtoggle
    or dword [bulk_cbw_td+8], ecx
    pop ecx

    pop bx
    pop ax

    mov byte [bulk_cbw_td+8], 0xe1
    mov byte [bulk_data1_td+8], 0x69
    mov byte [bulk_data2_td+8], 0x69
    mov byte [bulk_data3_td+8], 0x69
    mov byte [bulk_data4_td+8], 0x69
    mov byte [bulk_data5_td+8], 0x69
    mov byte [bulk_data6_td+8], 0x69
    mov byte [bulk_data7_td+8], 0x69
    mov byte [bulk_data8_td+8], 0x69
    mov byte [bulk_csw_td+8], 0x69

    movzx edx, bh
    shl edx, 8
    or dword [bulk_cbw_td+8], edx
    or dword [bulk_data1_td+8], edx
    or dword [bulk_data2_td+8], edx
    or dword [bulk_data3_td+8], edx
    or dword [bulk_data4_td+8], edx
    or dword [bulk_data5_td+8], edx
    or dword [bulk_data6_td+8], edx
    or dword [bulk_data7_td+8], edx
    or dword [bulk_data8_td+8], edx
    or dword [bulk_csw_td+8], edx

    mov dword [bulk_qh], 1
    mov dword [bulk_qh+4], bulk_cbw_td
    mov dword [bulk_cbw_td], bulk_data1_td
    mov dword [bulk_csw_td], 1

    mov dword [bulk_cbw_td+12], bulk_cbw_buffer
    mov dword [bulk_csw_td+12], bulk_csw_buffer

    or dword [bulk_cbw_td+8], (30 << 21)
    or dword [bulk_csw_td+8], (12 << 21)

    ;get current task PID
    push ax
    mov ah, 0x08
    int 0x35
    mov [bulk_csw_td+18], ax
    pop ax

    mov dl, [esi+10]
    mov byte [bulk_csw_td+16], 3    ;USB device
    mov byte [bulk_csw_td+17], dl   ;port number

    cli
    push edi
    push ecx
    mov edi, [frame_list]
    mov ecx, 4
    xor ebp, ebp
.loop:
    cmp dword [edi], 1
    je .found_free

    add edi, 4
    inc ebp
    dec ecx
    jnz .loop

    pop ecx
    pop edi
    sti
    jmp .error2

.found_free:
    push eax

    mov ecx, 1024/4
.loop2:
    mov dword [edi], 0x11   ;0x11 = reserved for USB Stick
    add edi, FL_OFFSET
    dec ecx
    jnz .loop2

    pop eax
    pop ecx
    pop edi
    sti

    mov [num_sectors], ax
    cmp ax, 1
    jbe .read_loop

    mov ax, 1

.read_loop:
    ;init CBW buffer
    mov dword [bulk_cbw_buffer], 'USBC'
    mov dword [bulk_cbw_buffer+4], 0xCAFEBABE

    movzx edx, ax
    imul edx, 512
    push edx
    push eax
    mov ebx, edx
    xor edx, edx
    add ebx, dword [esi+2]
    dec ebx
    mov eax, ebx
    mov ebx, [esi+2]
    div ebx
    mov ebx, eax
    pop eax
    pop edx

    mov [bulk_cbw_buffer+8], edx
    mov byte [bulk_cbw_buffer+12], 0x80     ;IN
    mov byte [bulk_cbw_buffer+13], 0
    mov byte [bulk_cbw_buffer+14], 10
    mov byte [bulk_cbw_buffer+15], 0x28     ;READ(10)
    mov byte [bulk_cbw_buffer+16], 0

    push eax
    mov eax, ecx
    call swap
    mov ecx, eax
    pop eax

    mov [bulk_cbw_buffer+17], ecx
    mov byte [bulk_cbw_buffer+21], 0
    xchg bl, bh
    mov [bulk_cbw_buffer+22], bx
    mov word [bulk_cbw_buffer+24], 0

    ;set size + data toggle in data TDs
    push esi
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
    mov edx, edi
.loop3:
    lodsd
    or dword [eax+8], (63 << 21)
    mov [eax+12], edx

    push ecx
    mov ecx, bulk_in_t2
    call get_dtoggle
    or dword [eax+8], ecx
    pop ecx

    add edx, 64
    dec ecx
    jnz .loop3

    pop eax
    pop esi

    mov dword [bulk_data1_td], bulk_data2_td
    mov dword [bulk_data2_td], bulk_data3_td
    mov dword [bulk_data3_td], bulk_data4_td
    mov dword [bulk_data4_td], bulk_data5_td
    mov dword [bulk_data5_td], bulk_data6_td
    mov dword [bulk_data6_td], bulk_data7_td
    mov dword [bulk_data7_td], bulk_data8_td
    mov dword [bulk_data8_td], bulk_csw_td

    mov ecx, bulk_in_t2
    call get_dtoggle
    or [bulk_csw_td+8], ecx

    push eax
    mov eax, bulk_csw_td
    call set_active_td
    pop eax
    jc .error2

    push esi
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
.loop5:
    lodsd
    or dword [eax+4], (1 << 23)
    dec ecx
    jnz .loop5
    pop eax
    pop esi

    or dword [bulk_csw_td+4], (1 << 23)
    or dword [bulk_cbw_td+4], (1 << 23)

    cli
    push esi
    push eax
    push ecx

    mov esi, ebp
    imul esi, 4
    add esi, dword [frame_list]
    mov eax, bulk_qh
    or eax, 2
    mov ecx, 1024/4
.loop8:
    mov [esi], eax
    add esi, FL_OFFSET
    dec ecx
    jnz .loop8

    pop ecx
    pop eax
    pop esi

    ;set task state to 'sleeping'
    push eax
    mov ah, 0x07
    mov al, 1
    int 0x35
    pop eax
    sti
    int 0x20

    cmp byte [bulk_error], 1
    je .error2

    push esi
    push eax
    push ecx

    mov esi, ebp
    imul esi, 4
    add esi, dword [frame_list]
    mov eax, 0x11
    mov ecx, 1024/4
.loop9:
    mov [esi], eax
    add esi, FL_OFFSET
    dec ecx
    jnz .loop9

    pop ecx
    pop eax
    pop esi

    sub word [num_sectors], ax
    cmp word [num_sectors], 0
    je .done

    movzx edx, ax

    mov ax, [num_sectors]
    cmp ax, 1
    je .next

    mov ax, 1
.next:
    ;increase LBA
    mov ecx, [bulk_cbw_buffer+17]
    push eax
    mov eax, ecx
    call swap
    mov ecx, eax
    pop eax
    add ecx, edx

    ;increase buffer
    imul edx, 512
    add edi, edx

    push esi
    push ecx
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
.loop7:
    lodsd
    mov dword [eax+4], 0
    and dword [eax+8], ~(0x7ff << 21)
    and dword [eax+8], ~(1 << 19)

    dec ecx
    jnz .loop7
    pop eax
    pop ecx
    pop esi

    and dword [bulk_cbw_td+8], ~(1 << 19)
    and dword [bulk_csw_td+8], ~(1 << 19)

    push ecx
    mov ecx, bulk_out_t2
    call get_dtoggle
    or dword [bulk_cbw_td+8], ecx
    mov dword [bulk_qh+4], bulk_cbw_td
    pop ecx
    jmp .read_loop

.done:
    mov byte [running], 0

    mov dx, [esi]
    add dx, 8
    in eax, dx
    imul ebp, 4
    add eax, ebp
    mov ecx, 1024/4
.done_loop:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .done_loop

    popa
    mov bl, [bulk_in_t2]
    mov bh, [bulk_out_t2]
    clc
    ret
.error:
    shr ebx, 16
    popa
    stc
    ret
.error2:
    mov byte [running], 0

    mov dx, [esi]
    add dx, 8
    in eax, dx
    imul ebp, 4
    add eax, ebp
    mov ecx, 1024/4
.error_loop:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .error_loop

    call bot_error
    popa
    mov bl, 1
    mov bh, 1
    stc
    ret

usb_write_sectors:
    ;AX = number of sectors to write
    ;EAX (bits 16 - 23): IN endpoint
    ;EAX (bits 24 - 31): OUT endpoint
    ;BL = protocol
    ;BH = USB address
    ;EBX (bits 16 - 23): data toggle state for IN endpoint
    ;EBX (bits 24 - 31): data toggle state for OUT endpoint
    ;ECX = LBA
    ;ESI = pointer to structure
    ;EDI = buffer address

    ;structure:
    ;   dw base_address (I/O)
    ;   dd block size
    ;   dd max. LBA
    ;   db port number (0 or 1)
    ;   dd 0

    pusha
    cmp bl, 0x50
    jne .error
    cmp ax, 0
    je .error
    cmp word [esi], 0
    je .error
    cmp dword [esi+2], 0
    je .error
    cmp dword [esi+6], ecx
    jbe .error

    sti
.wait_loop:
    cmp byte [running], 0
    jne .wait_loop

    cli
    mov byte [running], 1
    sti

    mov [esi+11], bh

    push eax
    push ecx
    push edi

    mov dx, [esi]
    add dx, 8
    in eax, dx
    mov [frame_list], eax

    mov edi, bulk_cbw_td
    xor eax, eax
    mov ecx, 32/4
    rep stosd

    mov edi, bulk_csw_td
    xor eax, eax
    mov ecx, 32/4
    rep stosd

    pop edi
    pop ecx
    pop eax

    push ax
    push bx
    shr eax, 16
    shr ebx, 16

    mov byte [esi+12], al   ;IN Endpoint
    mov byte [esi+13], ah   ;OUT Endpoint

    mov dword [bulk_data_tds], bulk_data1_td
    mov dword [bulk_data_tds+4], bulk_data2_td
    mov dword [bulk_data_tds+8], bulk_data3_td
    mov dword [bulk_data_tds+12], bulk_data4_td
    mov dword [bulk_data_tds+16], bulk_data5_td
    mov dword [bulk_data_tds+20], bulk_data6_td
    mov dword [bulk_data_tds+24], bulk_data7_td
    mov dword [bulk_data_tds+28], bulk_data8_td

    push esi
    push ecx
    push eax
    push edi

    mov esi, bulk_data_tds
    mov ecx, 8
.loop4:
    lodsd
    
    push ecx
    mov edi, eax
    xor eax, eax
    mov ecx, 32/4
    rep stosd
    pop ecx

    dec ecx
    jnz .loop4

    pop edi
    pop eax
    pop ecx
    pop esi

    ;set endpoints
    movzx edx, ah
    and edx, 0x0f
    shl edx, 15
    or dword [bulk_cbw_td+8], edx
    or dword [bulk_data1_td+8], edx
    or dword [bulk_data2_td+8], edx
    or dword [bulk_data3_td+8], edx
    or dword [bulk_data4_td+8], edx
    or dword [bulk_data5_td+8], edx
    or dword [bulk_data6_td+8], edx
    or dword [bulk_data7_td+8], edx
    or dword [bulk_data8_td+8], edx

    movzx edx, al
    and edx, 0x0f
    shl edx, 15
    or dword [bulk_csw_td+8], edx
    or dword [bulk_csw_td+4], (1 << 24)

    ;set data toggle
    mov [bulk_in_t2], bl
    mov [bulk_out_t2], bh

    push ecx
    mov ecx, bulk_out_t2
    call get_dtoggle
    or dword [bulk_cbw_td+8], ecx
    pop ecx

    pop bx
    pop ax

    mov byte [bulk_cbw_td+8], 0xe1
    mov byte [bulk_data1_td+8], 0xe1
    mov byte [bulk_data2_td+8], 0xe1
    mov byte [bulk_data3_td+8], 0xe1
    mov byte [bulk_data4_td+8], 0xe1
    mov byte [bulk_data5_td+8], 0xe1
    mov byte [bulk_data6_td+8], 0xe1
    mov byte [bulk_data7_td+8], 0xe1
    mov byte [bulk_data8_td+8], 0xe1
    mov byte [bulk_csw_td+8], 0x69

    movzx edx, bh
    shl edx, 8
    or dword [bulk_cbw_td+8], edx
    or dword [bulk_data1_td+8], edx
    or dword [bulk_data2_td+8], edx
    or dword [bulk_data3_td+8], edx
    or dword [bulk_data4_td+8], edx
    or dword [bulk_data5_td+8], edx
    or dword [bulk_data6_td+8], edx
    or dword [bulk_data7_td+8], edx
    or dword [bulk_data8_td+8], edx
    or dword [bulk_csw_td+8], edx

    mov dword [bulk_qh], 1
    mov dword [bulk_qh+4], bulk_cbw_td
    mov dword [bulk_cbw_td], bulk_data1_td
    mov dword [bulk_csw_td], 1

    mov dword [bulk_cbw_td+12], bulk_cbw_buffer
    mov dword [bulk_csw_td+12], bulk_csw_buffer

    or dword [bulk_cbw_td+8], (30 << 21)
    or dword [bulk_csw_td+8], (12 << 21)

    ;get current task PID
    push ax
    mov ah, 0x08
    int 0x35
    mov [bulk_csw_td+18], ax
    pop ax

    mov dl, [esi+10]
    mov byte [bulk_csw_td+16], 3    ;USB device
    mov byte [bulk_csw_td+17], dl   ;port number

    cli
    push edi
    push ecx
    mov edi, [frame_list]
    mov ecx, 4
    xor ebp, ebp
.loop:
    cmp dword [edi], 1
    je .found_free

    add edi, 4
    inc ebp
    dec ecx
    jnz .loop

    pop ecx
    pop edi
    sti
    jmp .error2

.found_free:
    push eax
    mov eax, bulk_qh
    or eax, 2

    mov ecx, 1024/4
.loop2:
    mov [edi], eax
    add edi, FL_OFFSET
    dec ecx
    jnz .loop2

    pop eax
    pop ecx
    pop edi
    sti

    mov [num_sectors], ax
    cmp ax, 1
    jbe .write_loop

    mov ax, 1

.write_loop:
    ;init CBW buffer
    mov dword [bulk_cbw_buffer], 'USBC'
    mov dword [bulk_cbw_buffer+4], 0xCAFEBABE

    movzx edx, ax
    imul edx, 512
    push edx
    push eax
    mov ebx, edx
    xor edx, edx
    add ebx, dword [esi+2]
    dec ebx
    mov eax, ebx
    mov ebx, [esi+2]
    div ebx
    mov ebx, eax
    pop eax
    pop edx

    mov [bulk_cbw_buffer+8], edx
    mov byte [bulk_cbw_buffer+12], 0x00     ;OUT
    mov byte [bulk_cbw_buffer+13], 0
    mov byte [bulk_cbw_buffer+14], 10
    mov byte [bulk_cbw_buffer+15], 0x2A     ;WRITE(10)
    mov byte [bulk_cbw_buffer+16], 0

    push eax
    mov eax, ecx
    call swap
    mov ecx, eax
    pop eax

    mov [bulk_cbw_buffer+17], ecx
    mov byte [bulk_cbw_buffer+21], 0
    xchg bl, bh
    mov [bulk_cbw_buffer+22], bx
    mov word [bulk_cbw_buffer+24], 0

    ;set size + data toggle in data TDs
    push esi
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
    mov edx, edi
.loop3:
    lodsd
    or dword [eax+8], (63 << 21)
    mov [eax+12], edx

    push ecx
    mov ecx, bulk_out_t2
    call get_dtoggle
    or dword [eax+8], ecx
    pop ecx

    add edx, 64
    dec ecx
    jnz .loop3

    pop eax
    pop esi

    mov dword [bulk_data1_td], bulk_data2_td
    mov dword [bulk_data2_td], bulk_data3_td
    mov dword [bulk_data3_td], bulk_data4_td
    mov dword [bulk_data4_td], bulk_data5_td
    mov dword [bulk_data5_td], bulk_data6_td
    mov dword [bulk_data6_td], bulk_data7_td
    mov dword [bulk_data7_td], bulk_data8_td
    mov dword [bulk_data8_td], bulk_csw_td

    mov ecx, bulk_in_t2
    call get_dtoggle
    or [bulk_csw_td+8], ecx

    push eax
    mov eax, bulk_csw_td
    call set_active_td
    pop eax
    jc .error2

    cli
    push esi
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
.loop5:
    lodsd
    or dword [eax+4], (1 << 23)
    dec ecx
    jnz .loop5
    pop eax
    pop esi

    or dword [bulk_csw_td+4], (1 << 23)
    or dword [bulk_cbw_td+4], (1 << 23)

    ;set task state to 'sleeping'
    push eax
    mov ah, 0x07
    mov al, 1
    int 0x35
    pop eax
    sti
    int 0x20

    cmp byte [bulk_error], 1
    je .error2

    sub word [num_sectors], ax
    cmp word [num_sectors], 0
    je .done

    movzx edx, ax

    mov ax, [num_sectors]
    cmp ax, 1
    je .next

    mov ax, 1
.next:
    ;increase LBA
    mov ecx, [bulk_cbw_buffer+17]
    push eax
    mov eax, ecx
    call swap
    mov ecx, eax
    pop eax
    add ecx, edx

    ;increase buffer
    imul edx, 512
    add edi, edx

    push esi
    push ecx
    push eax
    mov esi, bulk_data_tds
    mov ecx, 8
.loop7:
    lodsd
    mov dword [eax+4], 0
    and dword [eax+8], ~(0x7ff << 21)
    and dword [eax+8], ~(1 << 19)

    dec ecx
    jnz .loop7
    pop eax
    pop ecx
    pop esi

    and dword [bulk_cbw_td+8], ~(1 << 19)
    and dword [bulk_csw_td+8], ~(1 << 19)

    push ecx
    mov ecx, bulk_out_t2
    call get_dtoggle
    or dword [bulk_cbw_td+8], ecx
    mov dword [bulk_qh+4], bulk_cbw_td
    pop ecx
    jmp .write_loop

.done:
    mov byte [running], 0

    mov dx, [esi]
    add dx, 8
    in eax, dx
    imul ebp, 4
    add eax, ebp
    mov ecx, 1024/4
.done_loop:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .done_loop

    popa
    mov bl, [bulk_in_t2]
    mov bh, [bulk_out_t2]
    clc
    ret
.error:
    shr ebx, 16
    popa
    stc
    ret
.error2:
    mov byte [running], 0

    mov dx, [esi]
    add dx, 8
    in eax, dx
    imul ebp, 4
    add eax, ebp
    mov ecx, 1024/4
.error_loop:
    mov dword [eax], 1
    add eax, FL_OFFSET
    dec ecx
    jnz .error_loop

    call bot_error
    popa
    mov bl, 1
    mov bh, 1
    stc
    ret

bot_error:
    add dx, 8
    movzx ax, byte [esi+10]
    shl ax, 1   ;*2
    add dx, ax

    in ax, dx
    test ax, (1 << 0)
    jz .no_connection

    mov dx, [esi]
    add dx, 8
    in eax, dx
    mov ebp, eax

    mov byte [bot_setup_packet], 0x21
    mov byte [bot_setup_packet+1], 0xff
    mov dword [bot_setup_packet+2], 0
    mov word [bot_setup_packet+6], 0

    mov dword [td_setup], td_status
    mov dword [td_status], 1

    mov dword [td_setup+4], 0
    mov dword [td_status+4], 0
    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)
    mov dword [td_setup+8], 0x2d
    mov dword [td_status+8], 0x69

    movzx eax, byte [esi+11]
    shl eax, 8
    or dword [td_setup+8], eax
    or dword [td_status+8], eax
    or dword [td_setup+8], (7 << 21)
    mov dword [td_setup+12], bot_setup_packet
    or dword [td_status+8], (0x7ff << 21)
    or dword [td_status+8], (1 << 19)

    push esi
    mov esi, ebp
    mov dword [queue_head], td_setup
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop esi
    jc .no_connection

    mov edx, td_status
    call check_error
    jc .no_connection

    movzx eax, byte [esi+12]    ;IN Endpoint
    mov byte [bot_setup_packet], 2
    mov byte [bot_setup_packet+1], 1
    mov word [bot_setup_packet+2], 0
    mov word [bot_setup_packet+4], ax
    mov word [bot_setup_packet+6], 0

    mov dword [td_setup+12], bot_setup_packet
    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    push esi
    mov esi, ebp
    mov dword [queue_head], td_setup
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop esi
    jc .no_connection

    mov edx, td_status
    call check_error
    jc .no_connection

    movzx eax, byte [esi+13]    ;OUT Endpoint
    mov byte [bot_setup_packet], 2
    mov byte [bot_setup_packet+1], 1
    mov word [bot_setup_packet+2], 0
    mov word [bot_setup_packet+4], ax
    mov word [bot_setup_packet+6], 0

    mov dword [td_setup+12], bot_setup_packet
    or dword [td_setup+4], (1 << 23)
    or dword [td_status+4], (1 << 23)

    push esi
    mov esi, ebp
    mov dword [queue_head], td_setup
    mov eax, queue_head
    mov edx, td_status
    call wait_controller
    pop esi
    jc .no_connection

    mov edx, td_status
    call check_error
    jc .no_connection

    ret
.no_connection:
    ret
interrupt_handler:
    pusha
    mov ecx, NUM_CONTROLLERS
    mov edi, uhci_controllers

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

    out dx, ax
    sub dx, 2
    test ax, (1 << 0)
    jnz .find_td
    jmp .done

.find_td:
    mov edi, active_tds
    mov ecx, MAX_ACTIVE_TDS
    xor ebp, ebp
.td_loop:
    cmp dword [edi], 0
    je .td_next

    mov ebx, [edi]
    test dword [ebx+4], (1 << 23)
    jnz .td_next
    test dword [ebx+4], (1 << 24)
    jz .td_next

    cmp byte [ebx+16], 1
    je .boot_keyboard
    cmp byte [ebx+16], 3
    je .storage_dev

.td_next:
    inc ebp
    add edi, 4
    dec ecx
    jnz .td_loop
.done:
    popa
    ret

.boot_keyboard:
    ;EBX = usb_keyboard_td
    ;UHCI controller should set the right value for 'data toggle' itself

    movzx ebp, byte [ebx+18]
    mov dword [ebx+12], key_buffer

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
    mov ecx, [driver_packet]
    call dword [ecx]    ;usb_set_keys()

.kb_skip_data:
    mov dword [ebx+4], 0
    or dword [ebx+4], (1 << 24) | (1 << 23)
    mov eax, [ebx+20]   ;QH of this TD
    mov [eax+4], ebx
    jmp .done

.kb_error:
    cmp byte [ebx+17], 1
    je .kb_port1

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

    sub dx, 8
    mov al, [ebx+17]    ;port number
    call get_dev_index
    mov edx, [driver_packet]
    call dword [edx+8]

    jmp .done
.kb_port1:
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

    sub dx, 8
    mov al, [ebx+17]    ;port number
    call get_dev_index
    mov edx, [driver_packet]
    call dword [edx+8]
    jmp .done

.storage_dev:
    imul ebp, 4
    add ebp, active_tds
    mov dword [ebp], 0

    test dword [ebx+4], (1 << 16)
    jnz .bot_error
    test dword [ebx+4], (1 << 17)
    jnz .bot_error
    test dword [ebx+4], (1 << 18)
    jnz .bot_error
    test dword [ebx+4], (1 << 20)
    jnz .bot_error
    test dword [ebx+4], (1 << 21)
    jnz .bot_error
    test dword [ebx+4], (1 << 22)
    jnz .bot_error

    mov esi, [ebx+12]
    cmp byte [esi+12], 0
    jne .bot_error

    mov byte [bulk_error], 0
    mov bx, [ebx+18]
    mov ah, 0x07
    mov al, 0x80
    int 0x35
    jmp .done
.bot_error:
    mov byte [bulk_error], 1
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
bot_setup_packet:
    db 0x21
    db 0xff
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
csw_buffer: times 13 db 0

usbstick_buffer:  times 48 db 0
;+0: Vendor ID
;+8: Product ID
;+24: max. LBA
;+28: block size

usbstick_buffer1: times 48 db 0
usbstick_buffer2: times 48 db 0

running: db 0
frame_list: dd 0

uhci_base: dw 0     ;base I/O address
ep_offset: dd 0
uhci_controllers: times 4 dw 0
;max. 4 controllers supported
uhci_list_offset: db 0
NUM_CONTROLLERS     equ 4
MAX_ACTIVE_TDS      equ 24
cur_port: db 0

;DATA Toggles for various endpoints
bulk_in_t: db 0
bulk_out_t: db 0
bkeyboard_t: db 0

bulk_in_t2: db 0
bulk_out_t2: db 0
num_sectors: dw 0
bulk_error: db 0

driver_packet: dd 0
;+0: usb_set_keys()
;+4: usb_add_device()
;+8: usb_remove_device()

kernel_packet:
    dd 0    ;interrupt_handler

    dd 0    ;usb_read_sectors
    dd 0    ;usb_write_sectors

    dd 0    ;frame list
    dd 0    ;save_usb_dev

    dd 0    ;reserved
    dd 0    ;reserved
    dd 0    ;reserved

    ;port #1
    times 32 db 0
    ;+0: port information
    ; - bit 0: fullspeed device attached
    ; - bit 1: port number
    ; - bit 2: device attached
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
    ;+12: data toggle status for EP 1
    ;+13: data toggle status for EP 2
    ;+14: data toggle status for EP 3
    ;+15: data toggle status for EP 4
    ;+16: pointer to buffer with more information
    ;   if 'USB device' == 3: *usbstick_buffer

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
;+16: USB device
;+17: current port
;+18: offset in frame list
;+20: pointer to QH
;+24: controller base I/O address

queue_head: resd 4
bulk_cbw_td: resd 8

bulk_data1_td: resd 8
bulk_data2_td: resd 8
bulk_data3_td: resd 8
bulk_data4_td: resd 8
bulk_data5_td: resd 8
bulk_data6_td: resd 8
bulk_data7_td: resd 8
bulk_data8_td: resd 8

bulk_csw_td: resd 8
bulk_qh: resd 4

usb_keyboard_qh: resd 2

key_buffer: resd 2
active_tds: resd 24

device_list: resd 4
    ;Controller #1
    ;dw 0    ;Base I/O address

    ;db 0    ;index in USB_LIST of dev1
    ;db 0    ;index in USB_LIST of dev2

    ;Controller #2
    ;dw 0    ;Base I/O address

    ;db 0    ;index in USB_LIST of dev1
    ;db 0    ;index in USB_LIST of dev2

    ;Controller #3
    ;dw 0    ;Base I/O address

    ;db 0    ;index in USB_LIST of dev1
    ;db 0    ;index in USB_LIST of dev2

    ;Controller #4
    ;dw 0    ;Base I/O address

    ;db 0    ;index in USB_LIST of dev1
    ;db 0    ;index in USB_LIST of dev2

bulk_cbw_buffer: resb 31
bulk_csw_buffer: resb 13
bulk_data_tds: resd 8