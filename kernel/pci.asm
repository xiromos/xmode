

scan_disk_pci:
    mov byte [avail_disks], 2
    xor ebx, ebx
.bus_loop:
    cmp byte [pci_bus], 255
    jae .done
    mov byte [pci_device], 0
.device_loop:
    cmp byte [pci_device], 32
    jae .next_bus
    mov byte [pci_function], 0
.function_loop:
    cmp byte [pci_function], 8
    jae .next_device

    mov eax, 0x80000000
    movzx ebx, byte [pci_bus]
    shl ebx, 16
    or eax, ebx

    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx

    movzx ebx, byte [pci_function]
    shl ebx, 8
    or eax, ebx
    
    mov ebx, eax
    ;push eax
    call pci_read
    ;pop eax

    cmp ax, 0xffff
    je .skip

    push eax

    mov ecx, ebx
    mov eax, ebx
    or eax, 0x08
    call pci_read

    pop edx

    mov ebx, eax
    mov eax, ecx

    ;class
    mov edx, ebx
    shr edx, 24

    cmp dl, 0x01
    je .ahci_ide

    jmp .skip
    ;sub class
.ahci_ide:
    mov edx, ebx
    shr edx, 16
    cmp dl, 0x6     ;AHCI
    je .found_ahci
    cmp dl, 0x01
    je .found_ide       ;IDE
    jmp .skip
.found_ide:
    cmp byte [ide_found], 1
    je .skip

    call get_pci_addr

    or eax, 0x04
    call pci_read
    or eax, 0x0007
    and eax, ~(1 << 10) ;rm Bit 10 (interrupt disable)

    mov ebx, eax
    mov eax, ecx
    or eax, 0x04
    call pci_write

    call read_bar4

    call ide_init
    mov byte [ide_found], 1       ;block initialization of other IDE controllers
    jmp .skip
.found_ahci:
    mov edx, ebx
    shr edx, 8
    cmp dl, 0x01        ;Programming Interface
    jne .skip

    cmp byte [ahci_found], 1
    je .skip

    call get_pci_addr

    or eax, 0x04
    call pci_read
    or eax, 0x07
    and eax, ~(1 << 10)
    mov ebx, eax
    mov eax, ecx
    add eax, 0x04
    call pci_write

    call read_bar5

    mov eax, ecx
    or eax, 0x3c
    call pci_read

    and eax, 0xff
    add al, 0x20

    movzx ebx, al
    mov eax, ahci_interrupt_handler
    call set_irq

    mov byte [ahci_found], 1
    call ahci_init

.next_device:
    inc byte [pci_device]
    jmp .device_loop
.skip:
    inc byte [pci_function]
    jmp .function_loop
.next_bus:
    inc byte [pci_bus]
    jmp .bus_loop
.done:
    mov byte [ide_running], 0
    ret











scan_pci_driver:
    mov byte [pci_bus], 0
    mov byte [pci_device], 0
    mov byte [pci_function], 0

    xor ebx, ebx
    mov edi, 0x8a000
.bus_loop:
    cmp byte [pci_bus], 255
    jae .done
    mov byte [pci_device], 0
.device_loop:
    cmp byte [pci_device], 32
    jae .next_bus
    mov byte [pci_function], 0
.function_loop:
    cmp byte [pci_function], 8
    jae .next_device

    mov eax, 0x80000000
    movzx ebx, byte [pci_bus]
    shl ebx, 16
    or eax, ebx

    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx

    movzx ebx, byte [pci_function]
    shl ebx, 8
    or eax, ebx
    
    mov ebx, eax
    call pci_read

    cmp ax, 0xffff
    je .skip

    push ax
    mov al, [pci_bus]
    stosb
    mov al, [pci_device]
    stosb
    mov al, [pci_function]
    stosb
    xor al, al
    stosb       ;padding
    pop ax

    stosd

    push eax

    mov ecx, ebx
    mov eax, ebx
    or eax, 0x08
    call pci_read
    
    stosd
    mov byte [edi], 0x0a
    inc edi

    pop edx
    ;ECX = PCI address
    ;EDX: bits 0-15 = vendor ID, bits 16-31 = device ID
    call load_driver

    mov ebx, eax
    mov eax, ecx

    ;class
    mov edx, ebx
    shr edx, 24

    cmp dl, 0x0c
    je .serial_bus_controller

    jmp .skip
.serial_bus_controller:
    mov edx, ebx
    shr edx, 16
    cmp dl, 0x03
    je .usb

    jmp .skip
.usb:
    mov edx, ebx
    shr edx, 8
    cmp dl, 0
    je .uhci
    cmp dl, 0x10
    je .ohci
    cmp dl, 0x20
    je .ehci
    cmp dl, 0x30
    je .xhci
    jmp .next_device

.uhci:
    jmp .next_device
.ohci:
    cmp byte [ohci_found], 1
    je .skip

    call get_pci_addr

    call read_bar0
    and eax, 0xfffffff0
    mov [ohci_base], eax
    
    push ebx
    push ecx
    mov ebx, 0x2000
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_RW | PAGE_CACHE_DIS
    call map_region
    pop ecx
    pop ebx

    mov eax, ecx
    add eax, 4

    call pci_read
    mov ebx, eax
    and bx, 0xfdff  ;rm Bit 10 (Interrupt Disable)

    mov eax, ecx
    add eax, 4
    call pci_write

    ;get IRQ
    mov eax, ecx
    add eax, 0x3c
    call pci_read

    add al, 0x20
    movzx ebx, al
    mov eax, ohci_interrupt_handler
    call set_irq

    mov ah, 0x0a
    mov edx, DIR_DRIVERS_ADDR
    mov edi, OHCI_DRIVER_ADDR
    mov esi, file_ohci_sys
    mov bl, [drive_number]
    int 0x33
    jc .skip_ohci

    mov eax, [ohci_base]
    call dword OHCI_DRIVER_ADDR
    cmp ah, 0
    je .skip_ohci

    mov [usb_devices], ah

    mov [usb_keybuffer], ebx

    mov [usb_keyboard_tdptr], edi
    mov [usb_keyboard_edptr], esi

    ;get USB devices
    mov esi, USB_DEVICE_LIST
    movzx edx, ah
.loop_usb_ohci:
    lodsb
    cmp al, 1
    je .keyboard_ohci
    cmp al, 3
    je .usb_stick_ohci

    cmp al, 0xee
    je .skip_ohci
    add esi, USB_LIST_ENTRY-1

    dec dx
    jnz .loop_usb_ohci

    jmp .skip_ohci

.keyboard_ohci:
    mov byte [usb_keyboard_used], 1
    add esi, USB_LIST_ENTRY-1
    dec dx
    jnz .loop_usb_ohci

    jmp .skip_ohci
.usb_stick_ohci:
    movzx edi, byte [avail_disks]
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    ;copy vendor name
    push esi
    push edi
    mov ecx, 8
    rep movsb
    pop edi
    pop esi

    mov byte [edi+8], 0x10      ;OHCI
    mov byte [edi+9], 0xbe      ;USB

    mov eax, [ohci_base]
    mov [edi+12], eax

    mov ax, [esi+32]
    mov [edi+10], ax

    mov eax, [esi+24]           ;max LBA
    mov [edi+32], eax
    mov eax, [esi+28]           ;block size
    mov [edi+36], eax

    push esi
    add edi, 16
    add esi, 8
    mov ecx, 16
    rep movsb
    pop esi

    inc byte [avail_disks]
    add esi, USB_LIST_ENTRY-1
    dec dx
    jnz .loop_usb_ohci


.skip_ohci:
    mov byte [ohci_found], 1
    jmp .next_device
.ehci:
    jmp .next_device
.xhci:
    jmp .next_device

.next_device:
    inc byte [pci_device]
    jmp .device_loop
.skip:
    inc byte [pci_function]
    jmp .function_loop
.next_bus:
    inc byte [pci_bus]
    jmp .bus_loop
.done:
    mov byte [edi], '$'
    mov byte [ide_running], 0
    ret

;######################################################################################
;################################# PCI FUNCTIONS ######################################
;######################################################################################
pci_read:
    ;EAX = PCI adress
    mov dx, 0xcf8
    out dx, eax
    mov dx, 0xcfc
    in eax, dx
    ret
pci_write:
    ;EAX = PCI adress
    ;EBX = content
    mov dx, 0xcf8
    out dx, eax

    mov dx, 0xcfc
    mov eax, ebx
    out dx, eax
    ret
read_bar4:
    mov eax, 0x80000000
    movzx ebx, byte [pci_bus]
    shl ebx, 16
    or eax, ebx

    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx

    movzx ebx, byte [pci_function]
    shl ebx, 8
    or eax, ebx

    or eax, 0x20
    call pci_read

    test eax, 1
    jnz .io
    xor eax, eax
    ret
.io:
    and eax, 0xfffffffc
    mov [bm_base], eax
    mov [bm_base4], ax
    ret

read_bar5:
    mov eax, 0x80000000
    movzx ebx, byte [pci_bus]
    shl ebx, 16
    or eax, ebx

    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx

    movzx ebx, byte [pci_function]
    shl ebx, 8
    or eax, ebx

    or eax, 0x24
    call pci_read

    and eax, 0xfffffff0     ;remove flags
    mov [abar], eax         ;AHCI Base Address Register

    push ebx
    push ecx
    mov ebx, 0x2000
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_RW | PAGE_CACHE_DIS
    call map_region
    pop ecx
    pop ebx

    ;activate global AHCI interrupts
    mov eax, [abar]
    mov ebx, [eax+4]
    or ebx, (1 << 1)
    mov [eax+4], ebx

    ret
read_bar0:
    ;outputs value in EAX
    add eax, 0x10
    call pci_read
    ret


get_pci_addr:
    ;Output: ECX / EAX = PCI Address
    mov eax, 0x80000000
    movzx ebx, byte [pci_bus]
    shl ebx, 16
    or eax, ebx

    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx

    movzx ebx, byte [pci_function]
    shl ebx, 8
    or eax, ebx

    mov ecx, eax
    ret


load_driver:
    ;ECX = PCI Address
    ;EDX: bits 0-15 = vendor ID, bits 16-31 = device ID
    pusha
    movzx eax, dx
    shr edx, 16
    mov ebx, edx
    call search_driver_file
    jc .error

    ;get file information
    mov edx, ecx
    xor ah, ah
    mov edi, DIR_DRIVERS_ADDR
    mov bl, [drive_number]
    int 0x33
    jc .error2

    push esi
    mov ah, 0x0a
    int 0x35

    ;load file
    mov edi, esi
    pop esi
    push edx
    mov edx, DIR_DRIVERS_ADDR
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    pop ecx
    jc .error2

    push ecx
    call load_coff_obj
    pop ecx

    ;read command register
    mov eax, ecx
    add eax, 4
    call pci_read

    and eax, ~(1 << 10)
    or eax, (1 << 2)
    or eax, (1 << 0)
    mov ebx, eax
    mov eax, ecx
    add eax, 4
    call pci_write

    ;BAR1
    mov ebx, .driver_buffer
    mov eax, ecx
    add eax, 0x14
    call pci_read
    mov [ebx], eax

    ;BAR2
    mov ebx, .driver_buffer
    mov eax, ecx
    add eax, 0x18
    call pci_read
    mov [ebx+4], eax

    ;BAR3
    mov ebx, .driver_buffer
    mov eax, ecx
    add eax, 0x1c
    call pci_read
    mov [ebx+8], eax

    ;BAR4
    mov ebx, .driver_buffer
    mov eax, ecx
    add eax, 0x20
    call pci_read
    mov [ebx+12], eax

    ;BAR5
    mov ebx, .driver_buffer
    mov eax, ecx
    add eax, 0x24
    call pci_read
    mov [ebx+16], eax


    mov eax, ecx
    add eax, 0x10
    call pci_read

    push ecx
    push ebp
    call edi
    pop ebp
    pop ecx

    cmp ah, 0
    jne .error

    cmp ebp, 1
    je .net
    cmp ebp, 2
    je .graphic
    cmp ebp, 3
    je .sound
    cmp ebp, 4
    je .usb
    jmp .error

;######################################################################################
;#################################### NETWORK #########################################
;######################################################################################
.net:
    push edx
    mov eax, ecx
    add eax, 0x3c
    call pci_read
    and eax, 0xff
    add eax, 0x20
    mov ebx, eax
    pop edx

    push edx
    mov eax, [edx+4]
    call set_irq
    pop edx

    mov eax, [edx]
    mov [ip_packet], eax
    mov eax, edx
    add eax, 38
    mov [ip_packet+4], eax
    mov eax, [edx+42]
    mov [ip_packet+14], eax

    mov edi, ip_packet+8
    mov esi, edx
    add esi, 32
    mov ecx, 6
    rep movsb

    ; mov edi, [edx+12]
    ; mov [packet_stats], edi
    ; mov edi, [edx+16]
    ; mov [packet_stats+4], edi
    ; mov edi, [edx+20]
    ; mov [packet_stats+8], edi
    ; mov edi, [edx+24]
    ; mov [packet_stats+12], edi

    cmp byte [net_stack_loaded], 1
    je .skip_netstack

    call load_network_stack
.skip_netstack:
    jmp .done
.graphic:
    jmp .done
.sound:
    jmp .done
.usb:
    jmp .done
.done:
    popa
    clc
    ret
.error:
    popa
    stc
    ret
.error2:
    mov esi, edi
    mov ah, 0x0b
    int 0x35
    popa
    stc
    ret
.driver_buffer: times 5 dd 0
    
search_driver_file:
    ;AX = vendor ID
    ;BX = device ID

    ;returns:
    ;if CF = 0:
    ;ESI: pointer to buffer with filename
    ;EBP: type of driver
    ;   0x01: network card driver
    ;   0x02: graphics card driver
    ;   0x03: sound card driver
    ;   0x04: USB
    ;if CF is 1, it means no driver was found

    pusha
    mov esi, [drvrlist_addr]
    xor ebp, ebp

    mov cx, ax
    mov dx, bx
.main_loop:
    lodsb
    cmp al, '~'
    je .error
    cmp al, 0
    je .error
    cmp al, '#'
    je .skip_comment
    cmp al, '\'
    je .set_drivermode
    cmp al, '%'
    je .check_vendor

    jmp .main_loop
.check_vendor:
    push ecx
    push esi

    mov ecx, 4
    call string_to_hex

    mov eax, esi
    pop esi
    pop ecx

    cmp ax, cx
    jne .main_loop

.loop2:
    lodsb
    cmp al, 0x0a
    je .main_loop
    cmp al, 0
    je .error
    cmp al, '~'
    je .error
    cmp al, '#'
    je .skip_comment
    cmp al, '$'
    je .check_device
    jmp .loop2

.check_device:
    push ecx
    push esi

    mov ecx, 4
    call string_to_hex

    mov eax, esi
    pop esi
    pop ecx

    cmp ax, dx
    jne .main_loop

    ;driver was found
.loop3:
    lodsb
    cmp al, 0x0a
    je .main_loop
    cmp al, 0
    je .error
    cmp al, '~'
    je .error
    cmp al, '#'
    je .skip_comment
    cmp al, '*'
    je .get_file
    jmp .loop3

.get_file:
    push ecx
    push esi

    mov edi, .filename_buffer
    xor ecx, ecx
    call parse_arg_loop

    pop esi
    pop ecx

    mov esi, .filename_buffer
    mov [.tmp1], esi
    mov [.tmp2], ebp

    popa

    mov esi, [.tmp1]
    mov ebp, [.tmp2]
    clc
    ret
.skip_comment:
    lodsb
    cmp al, 0x0a
    je .main_loop
    cmp al, 0
    je .error
    cmp al, '~'
    je .error
    jmp .skip_comment
.set_drivermode:

    push esi
    push ecx
    mov ebp, 1
    mov edi, .net
    mov ecx, 3
    rep cmpsb
    pop ecx
    pop esi
    je .main_loop

    push esi
    push ecx
    mov ebp, 2
    mov edi, .graphic
    mov ecx, 7
    rep cmpsb
    pop ecx
    pop esi
    je .main_loop

    push esi
    push ecx
    mov ebp, 3
    mov edi, .sound
    mov ecx, 5
    rep cmpsb
    pop ecx
    pop esi
    je .main_loop

    push esi
    push ecx
    mov ebp, 4
    mov edi, .usb
    mov ecx, 3
    rep cmpsb
    pop ecx
    pop esi
    je .main_loop

    xor ebp, ebp
    jmp .main_loop

.error:
    popa
    stc
    ret

.net: db 'NET'
.graphic: db 'GRAPHIC'
.sound: db 'SOUND'
.usb: db 'USB'
.filename_buffer: times 11 db 0
.tmp1: dd 0
.tmp2: dd 0

load_driver_assets:
    ;load drivers directory
    mov esi, dir_drivers_str
    mov edi, DIR_DRIVERS_ADDR
    mov edx, root_addr
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .drivers_dir_err

    xor ah, ah
    mov esi, file_drvrlist_txt
    mov edi, DIR_DRIVERS_ADDR
    mov bl, [drive_number]
    int 0x33
    jc .drivers_dir_err

    mov ah, 0x0a
    int 0x35
    mov [drvrlist_addr], esi
    mov [drvrlist_filesize], ecx

    mov esi, file_drvrlist_txt
    mov edi, [drvrlist_addr]
    mov edx, DIR_DRIVERS_ADDR
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .drivers_dir_err

    clc
    ret

.drivers_dir_err:
    call print_newline
    mov esi, .error_load_drivers
    mov ebx, COLOR_RED
    call print_string
    call print_newline
    stc
    ret
.error_load_drivers: db 'Error loading Drivers directory (either not found or disk error), ', 0x0a, 
                     db 'Keyboard, and other devices might not work. Restart the PC. If this keeps continuing,', 0x0a, 
                     db 'the directory is missing or the filesystem could be damaged', 0