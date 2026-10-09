;====================================================
;USB driver for OHCI
;Copyright (C) 2026 Technodon
;====================================================

bits 32
[org 0x61000]
;=========OHCI=========
get_ohci_devices:
    ;dw 0xebec magic number
    ;Gets: EAX = OHCI BASE
    pusha
    mov [ohci_base], eax
    cmp dword [ohci_base], 0
    je .done                ;no OHCI controller found

    mov eax, [ohci_base]
    or dword [eax+8], 1     ;set Bit 0 to reset controller

.wait_reset_end:
    mov edi, [eax+8]
    test edi, 1
    jnz .wait_reset_end

    mov dword [eax+0x14], (1 << 31)     ;Master Interrupt Disable

    mov edi, hcca

    push edi
    push ecx
    push eax
    xor eax, eax
    mov ecx, 256/4
    rep stosd
    pop eax
    pop ecx
    pop edi

    mov [eax+0x18], edi     ;set Host Controller Communications Area
    
    ; mov ecx, 0x80000002     ;set Bit 1 and Bit 31 (Writeback Done Head & Master Interrupt Enable)
    ; mov [eax+0x10], ecx     ;InterruptEnable
    mov ecx, [eax+0x48]
    and ecx, 0xff
    mov esi, 0x54
    xor ebx, ebx

.loop:
    push esi
    add esi, eax
    mov edx, [esi]
    pop esi

    test edx, 1
    jz .next_port

    call init_ohci_port     ;send GET_DESCRITOR and set address
.next_port:
    inc ebx
    add esi, 4
    dec ecx
    jnz .loop
.done:
    mov dword [eax+12], 0xffffffff  ;clear interrupt status
    mov ecx, 0x80000002     ;set Bit 1 and Bit 31 (Writeback Done Head & Master Interrupt Enable)
    mov [eax+0x10], ecx     ;InterruptEnable

    mov esi, USB_DEVICE_LIST
    add esi, [usb_list_offset]
    mov dword [esi], 0xeeeeeeee     ;end of list marker
    popa

    mov al, [usb_keyboard_used]
    mov ah, [usb_devices]
    mov ebx, usb_keyboard_buffer        ;return pointer of keyboard buffer
    mov esi, usb_keyboard_ed
    mov edi, usb_keyboard_td
    
    mov dword [kernel_packet], usb_read_sectors
    mov dword [kernel_packet+4], usb_write_sectors
    mov edx, kernel_packet
    clc
    ret

;==== INIT OHCI PORT - GET_DESCRIPTOR and set address ====
init_ohci_port:
    ;EAX = [ohci_base]
    ;ESI = port offset (0x54 = 1. Port, 0x58 = 2. Port...)
    ;-----------------------------
    ;1: Send a GET_DESCRIPTOR (type 0x01, device descriptor)
    ;2: Set the Address of device
    ;3: Send a GET_DESCRITPOR again but with type 0x02 to get the full lenght of all descriptors
    ;4: Send a GET_DESCRIPTOR again but with the full lenght set, so we can read the interface descriptor to see what devices are there (keyboard, usb-stick,...)
    pusha
    push eax
    add esi, eax
    mov dword [esi], 16     ;set Bit 4 (reset status)

.wait_reset:
    mov eax, [esi]
    test eax, 16
    jnz .wait_reset
    pop eax

    ;set controller into operational mode
    mov edi, [eax+4]
    and edi, ~(1 << 6)               ;rm Bit 6
    or edi, (1 << 7)                 ;set Bit 7 (set operational mode)
    mov [eax+4], edi

    mov dword [esi], 2          ;set bit 1 (PortEnable)

    ;GET_DESCRIPTOR (device descriptor)
    ;connect TDs
    mov edi, td_data
    mov [td_setup+8], edi        ;NextTD is on offset 8

    mov edi, td_status
    mov [td_data+8], edi

    mov edi, td_empty
    mov [td_status+8], edi

    mov dword [td_empty+8], 0
    push ebx
    ;fill TDs
    mov ebx, ohci_setup_packet  ;address of 1.Byte in transfer buffer
    mov [td_setup+4], ebx
    mov ebx, ohci_setup_packet+7    ;address of last byte in transfer buffer
    mov [td_setup+12], ebx
    mov dword [td_setup], 0xfe200000         ;direction = SETUP (00b),  no interrupts

    mov ebx, ohci_descriptor_buffer
    mov [td_data+4], ebx
    mov ebx, ohci_descriptor_buffer+7
    mov [td_data+12], ebx
    mov dword [td_data], 0xfe100000  ;direction = IN + data toggle, no interrupts

    mov dword [td_status+4], 0
    mov dword [td_status+12], 0
    mov dword [td_status], 0xfe080000    ;OUT, no int, data toggle

    mov ebx, td_empty
    mov [control_ed+4], ebx
    mov ebx, td_setup
    mov [control_ed+8], ebx
    mov dword [control_ed+12], 0        ;no next ED

    mov dword [control_ed], 0x00080000  ;max packet size
    or dword [control_ed], 8192         ;set Bit 13
    pop ebx

    mov edi, control_ed
    mov [eax+0x20], edi

    or dword [eax+4], 16    ;control list enable
    or dword [eax+8], 2    ;control list filled

    push eax
.wait_controller:
    mov eax, [td_data]
    shr eax, 28
    and eax, 0x0f

    cmp eax, 0x0f
    je .wait_controller

    cmp eax, 0
    jne .init_port_error

    pop eax

    ;BUG: Controller overwrites Root Directory at Address 0x00000000

    ;SET_ADDRESS
    push ebx
    inc bx
    mov [set_address_packet+2], bx

    mov edi, td_status
    mov [td_setup+8], edi
    
    mov edi, td_empty
    mov dword [td_status+8], edi

    ;fill setup TD
    mov ebx, td_setup
    mov edi, set_address_packet
    mov [ebx+4], edi
    mov edi, set_address_packet+7
    mov [ebx+12], edi
    mov dword [ebx], 0xfe200000         ;SETUP / DATA0

    ;fill status TD
    mov dword [td_status+4], 0
    mov dword [td_status+12], 0
    mov dword [td_status], 0xfe100000        ;IN
    pop ebx
    add ebx, 1

    mov edi, td_setup
    mov [control_ed+8], edi     ;HeadP = first TD
    mov edi, td_empty
    mov [control_ed+4], edi     ;TailP = last TD

    or dword [eax+8], 2         ;set ControlListFilled to active

    push eax
.wait_address:
    mov eax, [td_status]
    shr eax, 28
    and eax, 0x0f
    cmp eax, 0x0f
    je .wait_address

    cmp eax, 0
    jne .init_port_error
    pop eax

    ;update address in control_ed
    mov edi, [control_ed]
    and edi, 0xffffff80
    or edi, ebx         ;set address
    mov [control_ed], edi

    ;GET_DESCRIPTOR 2 (configuration descriptor, not device)

    mov byte [ohci_setup_packet+2], 0
    mov byte [ohci_setup_packet+3], 0x02        ;configuration descriptor
    mov word [ohci_setup_packet+6], 9           ;read 9 bytes

    ;connect TDs
    mov edi, td_data
    mov [td_setup+8], edi        ;NextTD is on offset 8

    mov edi, td_status
    mov [td_data+8], edi

    mov edi, td_empty
    mov [td_status+8], edi

    mov dword [td_empty+8], 0

    push ebx
    ;fill TDs
    mov ebx, ohci_setup_packet  ;address of 1.Byte in transfer buffer
    mov [td_setup+4], ebx
    mov ebx, ohci_setup_packet+7    ;address of last byte in transfer buffer
    mov [td_setup+12], ebx
    mov dword [td_setup], 0xfe200000         ;direction = SETUP (00b),  no interrupts

    mov ebx, ohci_descriptor_buffer
    mov [td_data+4], ebx
    mov ebx, ohci_descriptor_buffer+8
    mov [td_data+12], ebx
    mov dword [td_data], 0xfe100000  ;direction = IN + data 0, no interrupts

    mov dword [td_status+4], 0
    mov dword [td_status+12], 0
    mov dword [td_status], 0xfe080000    ;OUT, no int, data toggle

    mov ebx, td_empty
    mov [control_ed+4], ebx
    mov ebx, td_setup
    mov [control_ed+8], ebx
    pop ebx

    or dword [eax+8], 2    ;control list filled

    push eax
.wait_controller2:
    mov eax, [td_status]
    shr eax, 28
    and eax, 0x0f

    cmp eax, 0x0f
    je .wait_controller2

    cmp eax, 0
    jne .init_port_error

    ; mov edi, [ohci_descriptor_buffer]
    ; cli
    ; hlt

    ;get total length
    movzx ecx, word [ohci_descriptor_buffer+2]
    cmp ecx, 9
    jb .init_port_error                                   ;check if value is valid
    pop eax

    mov [ohci_setup_packet+6], cx

    mov edi, td_data
    mov [td_setup+8], edi
    mov edi, td_status
    mov [td_data+8], edi
    mov edi, td_empty
    mov [td_status+8], edi
    mov dword [td_empty+8], 0

    mov edi, ohci_setup_packet
    mov [td_setup+4], edi
    mov edi, ohci_setup_packet+7
    mov [td_setup+12], edi

    mov edi, ohci_descriptor_buffer
    mov [td_data+4], edi
    add edi, ecx
    dec edi
    mov [td_data+12], edi

    mov dword [td_setup], 0xfe200000        ;SETUP, data0
    mov dword [td_data], 0xfe100000         ;IN, data1
    mov dword [td_status], 0xfe080000       ;OUT, data1

    mov edi, td_setup
    mov [control_ed+8], edi
    mov edi, td_empty
    mov [control_ed+4], edi

    or dword [eax+8], 2

    push eax
.wait_controller3:
    mov eax, [td_data]
    shr eax, 28
    and eax, 0x0f

    cmp eax, 0x0f
    je .wait_controller3

    cmp eax, 0
    jne .init_port_error
    pop eax

    ;SET_CONFIGURATION
    push eax
    movzx eax, byte [ohci_descriptor_buffer+5]
    mov byte [ohci_setup_packet], 0
    mov byte [ohci_setup_packet+1], 0x09   ;set configuration

    mov [ohci_setup_packet+2], al
    pop eax
    mov byte [ohci_setup_packet+3], 0
    mov word [ohci_setup_packet+4], 0
    mov word [ohci_setup_packet+6], 0

    mov edi, td_status
    mov [td_setup+8], edi

    mov edi, td_empty
    mov [td_status+8], edi
    mov dword [td_empty+8], 0

    mov edi, ohci_setup_packet
    mov [td_setup+4], edi
    mov edi, ohci_setup_packet+7
    mov [td_setup+12], edi

    mov dword [td_setup], 0xfe200000    ;not accessed, SETUP, DATA0
    mov dword [td_status], 0xfe100000
    mov dword [td_status+4], 0
    mov dword [td_status+12], 0

    mov edi, td_empty
    mov [control_ed+4], edi

    mov edi, td_setup
    mov [control_ed+8], edi

    or dword [eax+8], 2
    push eax
.wait_controller4:
    mov eax, [td_status]
    shr eax, 28
    and eax, 0x0f

    cmp eax, 0x0f
    je .wait_controller4

    cmp eax, 0
    jne .init_port_error
    pop eax


    ;GET USB DEVICE
    mov edi, ohci_descriptor_buffer
    add edi, 9

    push eax
    cmp byte [edi], 9                         ;length of packet should be 9 bytes
    jne .init_port_error
    cmp byte [edi+1], 4
    jne .init_port_error
    pop eax

    ;OFF +5 (+14): bInterfaceClass
    ;OFF +6 (+15): bInterfaceSubClass
    ;OFF +7 (+16): bInterfaceProtocol
    cmp byte [edi+5], 0x03      ;HID
    je .hid_device
    cmp byte [edi+5], 0x02
    je .printer
    cmp byte [edi+5], 0x08      ;Mass Storage
    je .mass_storage
    cmp byte [edi+5], 0x09
    je .usb_hub

.done:
    mov byte [ohci_setup_packet], 0x80
    mov byte [ohci_setup_packet+1], 0x06
    mov byte [ohci_setup_packet+3], 0x01        ;set device descriptor (for next port)
    mov word [ohci_setup_packet+6], 18          ;set packet size to 18 bytes (for next port)
    clc
    popa
    ret

.hid_device:
    cmp byte [edi+6], 0x01      ;Boot interface / 0x00 = No subclass
    ja .unknown
    cmp byte [edi+7], 0x01
    je .hid_keyboard
    cmp byte [edi+7], 0x0
    je .hid_mouse

    jmp .unknown


;#####################################################
;===================KEYBOARD INIT=====================
;#####################################################


.hid_keyboard:
    push esi
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 1
    add dword [usb_list_offset], USB_LIST_OFF
    pop esi

    ;GET ENDPOINT DESCRIPTOR
    mov edi, ohci_descriptor_buffer
    add edi, 9              ;skip configuration descriptor
.find_ep:
    cmp byte [edi+1], 5
    je .found_endpoint

    movzx edx, byte [edi]

    push eax
    test edx, edx
    jz .init_port_error
    pop eax

    add edi, edx
    jmp .find_ep

    ;SET ED
.found_endpoint:
    ;EDI + 2: Endpoint Address
    ;EDI + 3: Attributes
    ;EDI + 4: max. Packet Size
    ;EDI +6: Intervall
    
    mov edx, ebx        ;set function address

    movzx ecx, byte [edi+2]
    push ecx
    and ecx, 0x0f
    shl ecx, 7
    or edx, ecx         ;set endpoint address

    pop ecx
    test cl, 0x80
    jz .direction_out

    or edx, (1 << 12)       ;set direction
.direction_out:
    and edx, ~(1 << 13)
    test dword [esi], (1 << 9)
    jz .full_speed

    or edx, (1 << 13)       ;set Low Speed
.full_speed:
    movzx ecx, word [edi+4]
    shl ecx, 16
    or edx, ecx

    mov [usb_keyboard_ed], edx

    mov edx, td_empty
    mov [usb_keyboard_ed+4], edx

    mov edx, usb_keyboard_td
    mov [usb_keyboard_ed+8], edx

    mov dword [usb_keyboard_ed+12], 0   ;set last ED


    ;SET TD
    xor edx, edx
    ;or edx, (2 << 19)                      ;direction: IN
    ;and edx, ~(1 << 24) | ~(1 << 25)       ;toggle CARRY
    or edx, (1 << 25)                      ;DATA0
    or edx, (15 << 28)                     ;set status - not accessed
    mov [usb_keyboard_td], edx

    mov edx, usb_keyboard_buffer
    mov [usb_keyboard_td+4], edx

    mov edx, td_empty
    mov [usb_keyboard_td+8], edx

    mov edx, usb_keyboard_buffer+7
    mov [usb_keyboard_td+12], edx

    mov edi, td_empty
    mov dword [edi], 0
    mov dword [edi+4], 0
    mov dword [edi+8], 0
    mov dword [edi+12], 0

    mov edi, hcca
    add edi, [.hcca_offset]


    mov edx, usb_keyboard_ed
    mov [edi], edx
    or dword [eax+4], (1 << 2)          ;activate periodic scheduling

    mov byte [usb_keyboard_used], 1

    add dword [.hcca_offset], 4
    add byte [usb_devices], 1
    jmp .done
.hcca_offset: dd 0


;#####################################################
;================MOUSE INIT===========================
;#####################################################
.hid_mouse:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 2
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done

.printer:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 5
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done
.usb_hub:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 6
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done

.mass_storage:
    cmp byte [edi+6], 0x06      ;SCSI
    jne .unknown

    cmp byte [edi+7], 0x50
    je .bulk_only_transport     ;common protocol for flash drives
    cmp byte [edi+7], 0x62
    je .fast_extended_drive     ;used by external SSDs or fast flash drives
    cmp byte [edi+7], 0
    je .floppy_device           ;slower USB 1.1 protocol, used for example by floppy drives


;#####################################################
;===============USB STICK INIT========================
;#####################################################
.bulk_only_transport:
    ;GET ENDPOINT DESCRIPTOR
    mov edi, ohci_descriptor_buffer
    add edi, 9              ;skip configuration descriptor
.find_ep5:
    movzx edx, byte [edi]

    cmp byte [edi+1], 5
    je .found_endpoint5

    push eax
    test edx, edx
    jz .init_port_error
    pop eax

    add edi, edx
    jmp .find_ep5

.found_endpoint5:
    mov bl, [edi+2]
    test bl, 0x80
    jnz .bulk_in

    ;bulk out:
    mov [.usb_out_ep], bl
    mov cx, [edi+4]
    mov [.usb_bulk_out_maxpacket], cx

    add edi, edx
    cmp byte [.usb_in_ep], 0
    je .find_ep5
    jmp .found_bulk_ep

.bulk_in:
    mov [.usb_in_ep], bl
    mov cx, [edi+4]
    mov [.usb_bulk_in_maxpacket], cx

    add edi, edx
    cmp byte [.usb_out_ep], 0
    je .find_ep5

.found_bulk_ep:
    ;build EDs

    ;1. BULK-OUT ED (out to USB stick)
    mov edi, bulk_out_ed
    mov dword [edi], 0      ;clear old bits
    or dword [edi], ebx     ;set function address
    movzx edx, byte [.usb_out_ep]
    and edx, 0x0f
    shl edx, 7
    or dword [edi], edx     ;set endpoint address
    ; and dword [edi], ~(1 << 11) | ~(1 << 12)    ;0x00 (get direction from TD)
    ; and dword [edi], ~(1 << 13)         ;Bit 13 = 0 (full speed device)
    movzx edx, word [.usb_bulk_out_maxpacket]
    shl edx, 16
    or dword [edi], edx

    ;2. BULK-IN ED  (in into memory from USB stick)
    mov edi, bulk_in_ed
    mov dword [edi], 0      ;clear old bits
    or dword [edi], ebx     ;set function address
    movzx edx, byte [.usb_in_ep]
    and edx, 0x0f
    shl edx, 7
    or dword [edi], edx     ;set endpoint address
    movzx edx, word [.usb_bulk_in_maxpacket]
    shl edx, 16
    or dword [edi], edx

    mov edx, bulk_in_ed
    mov dword [bulk_out_ed+12], edx
    mov edx, bulk_out_ed
    mov dword [eax+0x28], edx   ;set HcBulkHeadED to address of bulk_out_ed
    or dword [eax+4], (1 << 5)  ;set Bit 5 to activate bulk-processing


    mov edi, .td_cbw
    mov dword [edi], 0
    or dword [edi], (1 << 19)   ;OUT
    ;or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)    ;not accessed

    mov edx, .cbw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .cbw_buffer+30
    mov [edi+12], edx

    mov edx, td_empty
    mov [bulk_out_ed+4], edx
    mov edx, .td_cbw
    mov [bulk_out_ed+8], edx

    ;clear buffer
    push edi
    push eax
    push ecx

    mov edi, .cbw_buffer
    mov ecx, 31
    xor eax, eax
    rep stosb

    pop ecx
    pop eax
    pop edi


    ;fill CBW_BUFFER
    mov dword [.cbw_buffer], 'USBC'     ;signature
    mov dword [.cbw_buffer+4], 0x77777777   ;ID
    mov dword [.cbw_buffer+8], 36           ;transfer 36B
    mov byte [.cbw_buffer+12], 0x80         ;read data from device
    mov byte [.cbw_buffer+14], 6
    mov byte [.cbw_buffer+15], 0x12
    mov word [.cbw_buffer+16], 0
    mov byte [.cbw_buffer+18], 0
    mov byte [.cbw_buffer+19], 0x24
    or dword [eax+4], (1 << 5)  ;set BulkListEnable
    or dword [eax+8], 4       ;set BulkListFilled

.wait_bulk:
    mov edx, [.td_cbw]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_bulk

    push eax
    cmp edx, 0
    jne .init_port_error
    pop eax

    ;set up data-td
    mov dword [td_data], 0
    mov edi, td_data
    or dword [edi], (2 << 19)       ;IN
    or dword [edi], (1 << 24)       ;DATA 1
    or dword [edi], (0xf << 28)     ;not accessed

    mov edx, .inquiry_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .inquiry_buffer+35
    mov [edi+12], edx

    mov edx, td_empty
    mov [bulk_in_ed+4], edx
    mov edx, td_data
    mov [bulk_in_ed+8], edx

    mov dword [eax+0x28], bulk_out_ed
    or dword [eax+8], 4

.wait_bulk_data:
    mov edx, [td_data]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_bulk_data

    push eax
    cmp edx, 0
    jne .init_port_error
    pop eax

    ;get CSW (Command Status Wrapper)
    mov edi, .td_csw
    mov dword [edi], 0          ;clear old bits
    or dword [edi], (2 << 19)   ;IN
    ;or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)

    mov edx, .csw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .csw_buffer+12
    mov [edi+12], edx

    mov edx, .td_csw
    mov dword [bulk_in_ed+8], edx
    mov dword [bulk_in_ed+4], td_empty

    mov dword [eax+0x28], bulk_out_ed
    or dword [eax+8], 4

.wait_csw:
    mov edx, [.td_csw]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_csw

    push eax
    cmp edx, 0
    jne .init_port_error

    mov edi, .csw_buffer
    cmp dword [edi], 'USBS'
    jne .init_port_error
    cmp dword [edi+4], 0x77777777
    jne .init_port_error
    pop eax


    ;#### Send TEST UNIT READY command ####
.send_test_unit:
    mov dword [.cbw_buffer+4], 0x77557755
    mov dword [.cbw_buffer+8], 0
    mov byte [.cbw_buffer+14], 6
    mov byte [.cbw_buffer+15], 0
    mov dword [.cbw_buffer+16], 0

    mov edi, .td_cbw
    mov dword [edi], 0
    or dword [edi], (1 << 19)   ;OUT
    or dword [edi], (0xf << 28)    ;not accessed

    mov edx, .cbw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .cbw_buffer+30
    mov [edi+12], edx

    mov edi, .td_csw
    mov dword [edi], 0          ;clear old bits
    or dword [edi], (2 << 19)   ;IN
    or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)

    mov edx, .csw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .csw_buffer+12
    mov [edi+12], edx

    mov dword [bulk_in_ed+8], .td_csw
    mov dword [bulk_out_ed+8], .td_cbw
    mov dword [bulk_out_ed+4], td_empty
    mov dword [bulk_in_ed+4], td_empty

    or dword [eax+8], 4
.wait_rdy:
    mov edx, [.td_cbw]
    shr edx, 28
    and edx, 0x0f
    cmp edx, 0x0f
    je .wait_rdy

.wait_rdy2:
    mov edx, [.td_csw]
    shr edx, 28
    and edx, 0x0f
    cmp edx, 0x0f
    je .wait_rdy2

    mov edi, .csw_buffer
    cmp dword [edi+4], 0x77557755
    jne .init_port_error

    cmp byte [edi+12], 0
    je .send_read_capacity
    push eax
    cmp byte [edi+12], 2
    je .init_port_error
    pop eax


    ;#### Send REQUEST SENSE ####
    mov dword [.cbw_buffer+8], 18
    mov byte [.cbw_buffer+12], 0x80
    mov byte [.cbw_buffer+13], 0
    mov byte [.cbw_buffer+14], 6
    mov byte [.cbw_buffer+15], 0x03
    mov word [.cbw_buffer+16], 0
    mov byte [.cbw_buffer+18], 0
    mov byte [.cbw_buffer+19], 18
    mov byte [.cbw_buffer+20], 0

    mov edi, .td_cbw
    mov dword [edi], 0
    or dword [edi], (1 << 19)   ;OUT
    or dword [edi], (0xf << 28)    ;not accessed

    mov edx, .cbw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .cbw_buffer+30
    mov [edi+12], edx

    ;fill data TD
    mov edi, td_data
    mov dword [edi], 0
    or dword [edi], (0x0f << 28)
    or dword [edi], (2 << 19)       ;IN

    mov edx, .sense_buffer
    mov [edi+4], edx
    mov edx, .sense_buffer+17
    mov [edi+12], edx

    ;fill CSW TD
    mov edi, .td_csw
    mov dword [edi], 0          ;clear old bits
    or dword [edi], (2 << 19)   ;IN
    or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)

    mov edx, .csw_buffer
    mov [edi+4], edx
    mov edx, .csw_buffer+12
    mov [edi+12], edx


    mov edx, td_empty
    mov [bulk_out_ed+4], edx
    mov edx, .td_cbw
    mov [bulk_out_ed+8], edx

    ;connect TDs to send command once
    mov dword [td_data+8], .td_csw
    mov dword [.td_csw+8], td_empty

    mov dword [bulk_in_ed+4], td_empty
    mov dword [bulk_in_ed+8], td_data

    or dword [eax+8], 4
.wait_rqst:
    mov edx, [.td_cbw]
    shr edx, 28
    and edx, 0x0f
    cmp edx, 0x0f
    je .wait_rqst

.wait_rqst2:
    mov edx, [.td_csw]
    shr edx, 28
    and edx, 0x0f
    cmp edx, 0x0f
    je .wait_rqst2

    push eax
    cmp edx, 0
    jne .init_port_error
    pop eax

    jmp .send_test_unit
.send_read_capacity:
    ;#### Send READ_CAPACITY command ####

    ;fill CBW + cbw_td
    mov dword [.cbw_buffer+8], 8    ;read 8 bytes
    mov byte [.cbw_buffer+14], 10   ;command length

    mov byte [.cbw_buffer+15], 0x25     ;READ_CAPACITY command
    mov dword [.cbw_buffer+16], 0
    mov dword [.cbw_buffer+20], 0
    mov dword [.cbw_buffer+24], 0

    mov edi, .td_cbw
    mov dword [edi], 0
    or dword [edi], (1 << 19)   ;OUT
    or dword [edi], (0xf << 28)    ;not accessed

    mov edx, .cbw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, .cbw_buffer+30
    mov [edi+12], edx

    ;fill data TD
    mov edi, td_data
    mov dword [edi], 0
    or dword [edi], (0x0f << 28)
    or dword [edi], (2 << 19)       ;IN

    mov edx, .capacity_buffer
    mov [edi+4], edx
    mov edx, .capacity_buffer+7
    mov [edi+12], edx

    ;fill CSW TD
    mov edi, .td_csw
    mov dword [edi], 0          ;clear old bits
    or dword [edi], (2 << 19)   ;IN
    or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)

    mov edx, .csw_buffer
    mov [edi+4], edx
    mov edx, .csw_buffer+12
    mov [edi+12], edx


    mov edx, td_empty
    mov [bulk_out_ed+4], edx
    mov edx, .td_cbw
    mov [bulk_out_ed+8], edx

    ;connect TDs to send command once
    mov dword [td_data+8], .td_csw
    mov dword [.td_csw+8], td_empty

    mov dword [bulk_in_ed+4], td_empty
    mov dword [bulk_in_ed+8], td_data

    or dword [eax+8], 4
.wait_bulk2:
    mov edx, [.td_csw]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_bulk2

    push eax
    cmp edx, 0
    jne .init_port_error
    pop eax

    ;0x00 0x00 0x07 0xff 0x00 0x00 0x02 0x00
    ;#### End of READ_CAPACITY command ####


    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov byte [esi], 3

    push esi
    push ecx
    mov ecx, 24
    mov edi, esi
    add edi, 1

    mov esi, .inquiry_buffer+8
    rep movsb
    pop ecx
    pop esi

    push ebx
    xor ebx, ebx
    mov edi, .capacity_buffer
    mov ax, [edi+2]
    mov bl, ah
    mov bh, al

    mov dx, bx
    shr ebx, 16
    
    mov ax, [edi]
    mov bl, ah
    mov bh, al
    shl ebx, 16
    mov bx, dx

    mov [esi+25], ebx
    mov [max_lba], ebx

    xor ebx, ebx
    mov edi, .capacity_buffer
    mov ax, [edi+6]
    mov bl, ah
    mov bh, al

    mov dx, bx
    shr ebx, 16
    
    mov ax, [edi+4]
    mov bl, ah
    mov bh, al
    shl ebx, 16
    mov bx, dx

    mov [esi+29], ebx
    mov [block_size], ebx
    pop ebx

    mov word [esi+33], bx
    add dword [usb_list_offset], USB_LIST_OFF

    ;## Test Read

    ; mov al, 10
    ; mov ecx, 0
    ; mov edi, 0x5000
    ; call usb_read_sectors

    ; mov al, 2
    ; mov ecx, 1
    ; mov edi, 0x3000
    ; call usb_read_sectors
    ; cli
    ; hlt

    add byte [usb_devices], 1
    jmp .done
.usb_out_ep: db 0
.usb_in_ep: db 0
.usb_bulk_out_maxpacket: dw 0
.usb_bulk_in_maxpacket: dw 0
.sense_buffer: times 18 db 0

.cbw_buffer: times 31 db 0
align 16
.td_cbw: times 4 dd 0
.td_csw:
    times 4 dd 0
    db 3    ;USB Stick
    db 0    ;status: 0 = ready, 1 = busy
.inquiry_buffer: times 36 db 0
.csw_buffer: times 13 db 0
.capacity_buffer: times 8 db 0

;#####################################################
;=============EXTERNAL SSD INIT=======================
;#####################################################
.fast_extended_drive:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 7
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done
.floppy_device:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 4
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done

.unknown:
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 0
    add dword [usb_list_offset], USB_LIST_OFF

    add byte [usb_devices], 1
    jmp .done
.init_port_error:
    pop eax
    mov esi, USB_DEVICE_LIST
    add esi, dword [usb_list_offset]
    mov dword [esi], 0xffffffff
    add dword [usb_list_offset], USB_LIST_OFF

    mov byte [ohci_setup_packet], 0x80
    mov byte [ohci_setup_packet+1], 0x06
    mov byte [ohci_setup_packet+3], 0x01        ;set device descriptor (for next port)
    mov word [ohci_setup_packet+6], 18          ;set packet size to 18 bytes (for next port)
    stc
    popa
    ret


;====data====
ohci_base: dd 0
hcca                    equ 0x162500              ;Host Controller Communications Area
USB_DEVICE_LIST         equ 0x163000
USB_LIST_OFF            equ 40

align 16
control_ed:                           ;Endpoint Desciptor
    dd 0    ;control
    dd 0    ;TD queue tail
    dd 0    ;TD queue head
    dd 0    ;Next ED
td_setup:
    dd 0
    dd 0
    dd 0
    dd 0
td_data:
    dd 0
    dd 0
    dd 0
    dd 0
td_status:
    dd 0
    dd 0
    dd 0
    dd 0
td_empty: times 4 dd 0
usb_keyboard_ed: times 4 dd 0
usb_keyboard_td:
    times 4 dd 0
    db 1    ;keyboard

align 16
ohci_setup_packet:
    db 0x80          ; Device to Host
    db 0x06          ; GET_DESCRIPTOR

    dw 0x0100        ; Device Descriptor
    dw 0
    dw 18
set_address_packet:
    db 0x00
    db 0x05
    dw 0             ; Address (off 2)
    dw 0
    dw 0
ohci_descriptor_buffer: times 128 db 0
usb_keyboard_buffer: times 8 db 0
usb_keyboard_used: db 0
usb_list_offset: dd 0

usb_devices: db 0
low_speed: db 0

align 16
bulk_in_ed: times 4 dd 0
bulk_out_ed: times 4 dd 0

kernel_packet:
    dd 0        ;address to usb_read_sectors function
    dd 0        ;address to usb_write_sectors function

block_size: dd 0
max_lba: dd 0


; ###       USB DEVICE LIST ENTRY
; Keyboard:
;     0       BYTE       Type (0x01)

; USB Stick:
;     0       BYTE       Type (0x02)
;     1       24 BYTE    Vendor (8B) + Product name (16B)
;     25      DWORD      Max. LBA
;     29      DWORD      Size of one block (512B or 4096B)
;     33      WORD       USB Address
;#####################################################
;############## USB STICK FUNCTIONS ##################
;#####################################################

usb_read_sectors:
    ;AL = sector count of 512B sectors
    ;BL = USB address
    ;ECX = LBA
    ;EDI = Buffer
    pusha
    mov edx, [max_lba]
    dec edx
    cmp ecx, edx
    jae .error

    cmp al, 0
    je .error

.loop:
    cmp byte [init_ohci_port.td_csw+17], 1
    je .loop

    mov byte [init_ohci_port.td_csw+17], 1

    push ebx
    movzx edx, al
    imul edx, 512
    push edx

    mov ebx, edx
    xor edx, edx
    add ebx, [block_size]
    dec ebx
    mov eax, ebx
    mov ebx, [block_size]
    div ebx
    mov ebx, eax

    mov eax, [ohci_base]
    pop edx

    ;convert ECX into big endian
    push edx
    mov dx, cx
    xchg dl, dh
    shl edx, 16
    shr ecx, 16
    mov dx, cx
    xchg dl, dh
    mov ecx, edx
    pop edx

    mov esi, edi
    mov ebp, edx

    mov [init_ohci_port.cbw_buffer+8], edx  ;read 1 block
    mov byte [init_ohci_port.cbw_buffer+12], 0x80
    mov byte [init_ohci_port.cbw_buffer+13], 0
    mov byte [init_ohci_port.cbw_buffer+14], 10
    mov byte [init_ohci_port.cbw_buffer+15], 0x28 ;READ(10)
    mov [init_ohci_port.cbw_buffer+16], ecx
    mov word [init_ohci_port.cbw_buffer+20], 0
    mov byte [init_ohci_port.cbw_buffer+23], bl    ;1 block
    pop ebx

    mov edi, init_ohci_port.td_cbw
    mov dword [edi], 0
    or dword [edi], (1 << 19)   ;OUT
    or dword [edi], (0xf << 28)    ;not accessed

    mov edx, init_ohci_port.cbw_buffer
    mov [edi+4], edx
    mov edx, td_empty
    mov [edi+8], edx
    mov edx, init_ohci_port.cbw_buffer+30
    mov [edi+12], edx

    ;fill data TD
    mov edi, td_data
    mov dword [edi], 0
    or dword [edi], (0xf << 28)
    or dword [edi], (2 << 19)        ;IN

    mov [edi+4], esi
    mov edx, esi
    add edx, ebp
    dec edx
    mov [edi+12], edx

    ;fill CSW TD
    mov edi, init_ohci_port.td_csw
    mov dword [edi], 0          ;clear old bits
    or dword [edi], (2 << 19)   ;IN
    ;or dword [edi], (1 << 24)   ;DATA1
    or dword [edi], (0xf << 28)

    mov edx, init_ohci_port.csw_buffer
    mov [edi+4], edx
    mov edx, init_ohci_port.csw_buffer+12
    mov [edi+12], edx


    mov dword  [bulk_out_ed+4], td_empty
    mov dword [bulk_out_ed+8], init_ohci_port.td_cbw
    mov dword [bulk_out_ed+12], bulk_in_ed

    ;connect TDs to send command once
    mov dword [td_data+8], init_ohci_port.td_csw
    mov dword [init_ohci_port.td_csw+8], td_empty

    mov dword [bulk_in_ed+4], td_empty
    mov dword [bulk_in_ed+8], td_data
    mov dword [bulk_in_ed+12], 0

    or dword [eax+8], 4
.wait_read1:
    mov edx, [init_ohci_port.td_cbw]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_read1

    cmp edx, 0
    jne .error

.wait_read2:
    mov edx, [td_data]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_read2

    cmp edx, 0
    jne .error

.wait_read3:
    mov edx, [init_ohci_port.td_csw]
    shr edx, 28
    cmp edx, 0x0f
    je .wait_read3

    cmp edx, 0
    jne .error

    ; mov edi, 0x7777
    ; cli
    ; hlt
    popa
    clc
    ret

.error:
    popa
    stc
    ret
usb_write_sectors:
    ;AH = sector count
    ;ECX = LBA
    ;ESI = Buffer
    pusha
    popa
    ret