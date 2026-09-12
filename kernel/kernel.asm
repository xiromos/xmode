[org 0x8000]
bits 16

start:
    cli
    xor ax, ax
    mov es, ax
    mov ds, ax


    mov eax, [0x7c00+28]
    mov [hidden_sectors], eax

    mov ax, 0x4F02
    mov bx, 0x4118   ; 1024x768x24bit
    int 0x10
    ;mov ax, 0x03
    ;int 0x10

    mov ax, 0x4f01
    mov cx, 0x118
    mov di, vbe_info
    int 0x10
    mov dx, [vbe_info+0x10]     ;pitch (bytes per scanline)
    mov [pitch], dx
    mov ax, [vbe_info+0x12]     ;width
    mov bx, [vbe_info+0x14]     ;height
    mov cl, [vbe_info+0x19]     ;bits per pixel
    mov edx, [vbe_info+0x28]
    mov [frame_buffer], edx
    movzx eax, cl
    shr eax, 3
    mov [bpp], al               ;should be 3

    ;get memory map
    mov ax, 0x7000
    mov es, ax
    xor di, di
    xor eax, eax
    xor ebx, ebx
    xor si, si
.next:
    mov eax, 0xe820
    mov edx, 0x534D4150
    mov ecx, 24
    int 0x15
    jc .done

    cmp eax, 0x534D4150
    jne .done
    mov [mmap_entries], ecx
    add di, cx
    inc si
    cmp ebx, 0
    jne .next
.done:
    mov [main.memmap_entrysize], cx
    mov [main.memmap_entries], si

    mov ax, tss
    shr ax, 16
    mov byte [gdt_start.descriptor+4], al
    mov byte [gdt_start.descriptor+7], ah
    lgdt [gdt_descriptor]   ;load GDT
    mov eax, cr0
    or eax, 1        ;set PE
    mov cr0, eax
    jmp far code_off:main

    frame_buffer: dd 0
gdt_start:
    dq 0

    ;code segment
    dw 0xffff
    dw 0x0000
    db 0x00
    db 0b10011010   ;access byte
    db 0b11001111   ;flags
    db 0x00

    dw 0xffff
    dw 0x0000
    db 0x00
    db 0b10010010
    db 0b11001111
    db 0x00

    dw 0xffff
    dw 0x0000
    db 0x00
    db 0b11110010
    db 0b11001111
    db 0x00

    dw 0xffff
    dw 0x0000
    db 0x00
    db 0b11111010
    db 0b11001111
    db 0x00
.descriptor:
    dw tss.end - tss - 1
    dw tss
    db 0
    db 0b10001001
    db 0
    db 0
.end:

gdt_descriptor: dw gdt_start.end - gdt_start - 1
                dd gdt_start

; extern kmain
; global main
times 250 -($ - start) db 0
bits 64
uefi:
    cli
    mov [rel frame_buffer], edx
    mov [rel bpp], cl
    mov [rel real_width], ebx
    mov [rel real_height], edi

    mov eax, [rsi+8]
    mov word [rel main.memmap_entries], ax
    mov ebx, [rsi+12]
    mov word [rel main.memmap_entrysize], bx
    mov word [rel mmap_entries], bx

    lea eax, [rel tss]
    shr eax, 16
    mov byte [rel gdt_start.descriptor+4], al
    mov byte [rel gdt_start.descriptor+7], ah
    lgdt [rel gdt_descriptor]

    mov rax, cr0
    btr rax, 31
    mov cr0, rax

    mov ecx, 0xC0000080
    rdmsr
    btr eax, 8
    wrmsr

    mov rax, cr0
    or rax, 1
    mov cr0, rax
bits 32
[cpu 386]
    jmp far code_off:uefi2
uefi2:
    mov eax, [real_width]
    movzx ebx, byte [bpp]
    mul ebx
    mov [pitch], eax
;     mov ecx, 10000
;     mov eax, 0x00ffffff
;     mov edi, [frame_buffer]
;     movzx ebx, byte [bpp]
; .loop:
;     mov [edi], eax
;     add edi, ebx
;     dec ecx
;     jnz .loop
    ;hlt
main:
    mov ax, data_off
    mov es, ax
    mov ds, ax
    mov ss, ax
    mov esp, 0x90000
    mov fs, ax
    mov gs, ax

    call set_idt
    lidt [idt_descriptor]
    call remap_pic
    ; mov al, 0xfc
    ; out 0x21, al
    xor al, al
    out 0xa1, al
    out 0x21, al

    ;check amount of available memory
    mov edi, mmap_buffer
    movzx edx, word [.memmap_entrysize]
    movzx ecx, word [.memmap_entries]

    push ecx
    push edx
    push edi

    imul ecx, edx
    mov esi, 0x70000
    rep movsb

    pop edi
    pop edx
    pop ecx

    cmp ecx, 0
    je .continue1
.loop_mem:
    mov eax, [edi+16]
    cmp eax, 1
    jne .skip_entry

    cmp dword [edi+4], 0
    jne .overflow
    cmp dword [edi+12], 0
    jne .overflow

    mov eax, [edi+8]
    add dword [.usable_mem], eax
    mov ebx, [edi]
    add ebx, eax
    mov [.max_addr], ebx
.skip_entry:
    add edi, edx
    dec ecx
    jnz .loop_mem
    jmp .continue1
.overflow:
    mov dword [.usable_mem], 0xffffffff ;over 4GB
.continue1:
    call set_pages

    mov eax, [real_width]
    movzx ecx, byte [bpp]
    imul eax, ecx
    mov ebx, [real_height]
    imul eax, ebx

    mov ebx, eax
    inc ebx
    mov eax, [frame_buffer]
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_RW | PAGE_CACHE_DIS | PAGE_USER
    call map_region

    mov eax, rtc_handler
    mov ebx, 0x28
    call set_idt_entry

    call init_rtc

    sti

    mov eax, [frame_buffer]
    mov [cur], eax
    mov dword [bgcolor], 0x0014c4be
    mov edi, [frame_buffer]
    mov ecx, width*height
    movzx eax, byte [bpp]
.loop:
    add edi, eax
    mov dword [edi], 0x0014c4be
    loop .loop

    call init_heap

    ;0xFFFFFFFF = white
    ;0x00FF0000 = red
    ;0x11111111 = dark gray
    ;call kmain
    mov ebx, 0x00FFFFFF
    mov esi, gdt_loaded_msg
    call print_string
    call print_newline

    mov esi, idt_loaded_msg
    call print_string
    call print_newline

    mov esi, cur_bmbase_str
    mov ebx, 0x00ffffff
    call print_string

    call scan_disk_pci
    mov edx, [bm_base]
    call print_hex8

    ; INIT FIRST TASK (SLOT 0)
    mov edi, tasks_esp
    cli
    ; init idle task
    push edi
    mov esi, idle_task_str
    mov ecx, 11
    rep movsb
    pop edi

    mov dword [edi+19], 0xfffffffe

    mov ah, 0x0a
    mov ecx, 128
    int 0x35

    mov ebp, esp
    mov esp, esi

    push ss
    push esp
    push dword 0x202
    push cs
    push dword idle_task

    pushad
    push ds
    push es
    push fs
    push gs

    mov dword [edi+15], esp

    mov esp, ebp
    sti

    mov ebx, init_system
    mov esi, program_init_sys
    mov ah, 0x13
    int 0x35
    
    mov al, 0x20
    call print_char

    mov edx, [abar]
    call print_hex8

    mov al, 0x20
    call print_char

    mov edx, [ohci_base]
    call print_hex8
    call print_newline

    call search_boot_device

    ;test write with DMA
    mov edi, 0x8000
    mov ebx, 4
    mov ecx, 100
    mov ah, 0x13
    ;int 0x32

    call get_bpb_data

    mov ax, [root_entries]
    mov bx, 32
    mul bx

    mov bx, 512
    add ax, bx
    dec ax
    xor dx, dx
    div bx

    mov [root_sectors], ax

    ;calculate root dir start
    ;ReservedAreaCnt + (NumberOfFATs * FATSz16)

    xor ax, ax
    mov al, [fat_num]
    mov bx, [fat_size]
    mul bx
    add ax, [reserved_sectors]
    add ax, [hidden_sectors]
    mov [root_start], ax

    ;calculate data start sector
    xor ax, ax
    mov ax, [root_start]
    add ax, [root_sectors]
    mov [data_start], ax

    call load_root
    call load_fat

    movzx eax, byte [sec_per_cluster]
    movzx ebx, word [bytes_per_sec]
    mul ebx 

    mov ebx, 32
    div ebx
    mov [subdir_entries], ax

    call load_drivers

    call load_configs
    jc .config_err

    mov ebx, 0x00FFFFFF
    mov esi, gdt_loaded_msg
    call print_string
    call print_newline

    mov esi, idt_loaded_msg
    call print_string
    call print_newline

    mov esi, cur_bmbase_str
    mov ebx, 0x00ffffff
    call print_string

    mov edx, [bm_base]
    call print_hex8

    mov al, 0x20
    call print_char

    mov edx, [abar]
    call print_hex8

    mov al, 0x20
    call print_char

    mov edx, [ohci_base]
    call print_hex8
    call print_newline

    mov esi, ahci_initialized
    mov ebx, 0x00ffffff
    call print_string
    call print_newline

    mov esi, fs_loading_str
    mov ebx, 0x00ffffff
    call print_string
    call print_newline

    mov ebx, 0x00ffffff
    mov esi, start_msg
    mov ah, 0x01
    int 0x30
    call print_newline
    inc word [task_count]
    jmp .init_first_task

.config_err:
    mov esi, configs_load_err
    mov ebx, COLOR_RED
    call print_string
    call print_newline
.init_first_task:
    mov edi, tasks_esp
    add edi, TASK_SIZE      ;task 1 - shell
    mov esi, shell_task_str
    mov ecx, 11
    rep movsb
    ; write to disk
    ; mov ah, 0x03
    ; mov edi, 0x15000
    ; mov ecx, 100
    ; mov ebx, 255
    ; int 0x32

    ; extended disk write
    ; mov ah, 0x0b
    ; mov esi, 0x15000
    ; mov ecx, 4
    ; mov [disk_lba], ecx
    ; mov ecx, disk_lba
    ; mov ebx, 100
    ; int 0x32
    ; jc disk_error
    ;call clear_screen
    ;====JUMP INTO RING 3====
    cli
    mov word [tss+8], 2*8   ;kernel data
    mov [tss+4], esp
    call flush_tss
    call print_char
    mov ax, (3*8) | 3   ;ring 3 data
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, esp
    push (3*8) | 3  ;data selector
    push user_stack
    pushf
    push (4*8) | 3
    push shell
    sti
    iret
.halt:
    hlt
    jmp .halt
.memmap_entrysize: dw 0
.memmap_entries: dw 0
.usable_mem: dd 0
.max_addr: dd 0


remap_pic:
    push eax
    
    mov al,11h              ; Initialization Command Word (ICW) 1
    out 20h,al              ; Into first PIC
    out 0A0h,al             ; Into casscaded second PIC

    mov al,20h              ; Load starting interrupt 20h (ICW2)
    out 21h,al              ; Into first PIC
    mov al,28h              ; Load starting interrupt 28h
    out 0A1h,al             ; Into second PIC

    mov al,04h              ; ICW3
    out 21h,al              ; First PIC
    mov al,02h              ; ICW3
    out 0A1h,al             ; Second PIC

    mov al,01h              ; ICW4
    out 21h,al              ; First PIC
    out 0A1h,al             ; Second PIC

    ; change PIT frequenzy
    ; push edx
    ; mov dx, 0x43
    ; mov al, 0x36
    ; out dx, al

    ; mov ax, PIT_DIVISOR
    ; mov dx, 0x40
    ; out dx, al
    ; shr ax, 8
    ; out dx, al
    ; pop edx
    pop eax

    ret

flush_tss:
    mov ax, (5 * 8) | 0
    ltr ax
    ret
disk_error:
    mov esi, disk_error_msg
    call print_string
.halt:
    hlt
    jmp .halt

get_bpb_data:
    push eax

    mov eax, 1  ;read 1 sector
    mov ecx, 0  ;LBA 0
    mov dl, [drive_number]
    mov dh, 0x0b    ;LBA28 read
    mov edi, 0x7c00
    call read_drive

    mov esi, fs16_error_msg
    jc rsod

    mov ax, [0x7c00+11]
    mov [bytes_per_sec], ax
    mov al, [0x7c00+13]
    mov [sec_per_cluster], al
    mov ax, [0x7c00+14]
    mov [reserved_sectors], ax
    mov al, [0x7c00+16]
    mov [fat_num], al
    mov ax, [0x7c00+17]
    mov [root_entries], ax
    mov ax, [0x7c00+19]
    mov [total_sectors], ax
    mov ax, [0x7c00+22]
    mov [fat_size], ax
    mov eax, [0x7c00+28]
    mov [hidden_sectors], eax
    mov eax, [0x7c00+32]
    mov [total_sectors32], eax
    pop eax
    ret
load_root:
    xor edi, edi
    movzx ecx, word [root_start]
    add ecx, dword [hidden_sectors]
    movzx eax, word [root_sectors]
    mov dl, [drive_number]
    mov dh, 0x0b
    call read_drive
    
    mov esi, fs16_error_msg
    jc rsod
    ret
load_fat:
    mov edi, 0x4000
    movzx ecx, word [reserved_sectors]
    add ecx, dword [hidden_sectors]

    movzx eax, word [fat_size]

    cmp eax, 25
    jbe .load

    mov eax, 25
    jmp .load
.load:
    call read_drive
    mov esi, fs16_error_msg
    jc rsod
    ret


scan_disk_pci:
    mov byte [avail_disks], 2
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
    ;push eax
    call pci_read
    ;pop eax

    cmp ax, 0xffff
    je .skip

    cmp ax, 0x10ec  ;Realtek Semiconductor Co., Ltd.
    je .vendor_realtek

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
    ;DX = vendors...

    mov ebx, eax
    mov eax, ecx

    ;class
    mov edx, ebx
    shr edx, 24

    cmp dl, 0x01
    je .ahci_ide

    cmp dl, 0x04
    je .multimedia

    cmp dl, 0x0c
    je .serial_bus_controller

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
.serial_bus_controller:
    mov edx, ebx
    shr edx, 16
    cmp dl, 0x03
    je .usb

    jmp .skip
.multimedia:
    mov edx, ebx
    shr edx, 16
    cmp dl, 0x03        ;audio device
    je .found_audiodev
    jmp .skip
.found_ide:
    cmp byte [ide_found], 1
    je .skip

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
    jmp .next_device
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

    ;call get_ohci_devices
    mov byte [ohci_found], 1
    jmp .next_device
.ehci:
    jmp .next_device
.xhci:
    jmp .next_device
.found_audiodev:
    mov byte [intel_hd_audio], 1

    call get_pci_addr

    call read_bar0
    mov [intel_audiodev_base], eax

    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_RW | PAGE_CACHE_DIS
    mov ebx, 0x1000
    call map_region

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
;################################# PCI VENDORS ########################################
;######################################################################################
.vendor_realtek:
    shr eax, 16
    cmp ax, 0x8139
    je .found_rtl8139
    cmp ax, 0x8169
    je .found_rtl_8169
    jmp .next_device
.found_rtl8139:
    mov byte [rtl8139_found], 1     ;found network card

    call get_pci_addr

    call read_bar0
    ;and eax, 0xfffffffe
    mov [rtl8139_base], eax          ;bit 1 = 1: IO-Port, bit 1 = 0: MMIO
    ; mov ebx, 0x1000
    ; xor ecx, ecx
    ; or ecx, PAGE_PRESENT | PAGE_RW | PAGE_CACHE_DIS
    ; call map_region

    mov eax, ecx
    add eax, 0x04
    call pci_read

    or eax, (1 << 2)        ;activate busmastering bit
    or eax, (1 << 0)        ;activate DMA
    and eax, ~(1 << 10)     ;enable interrupts
    mov ebx, eax
    mov eax, ecx
    add eax, 0x04
    call pci_write

    mov eax, ecx
    add eax, 0x3c
    call pci_read

    add al, 0x20
    mov [rtl8139_irq], al
    jmp .next_device
.found_rtl_8169:
    jmp .next_device
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
search_boot_device:
    mov byte [boot_drive], 2
    mov byte [drive_number], 2
    ret

init_system:
    mov ecx, 0x1000000
.loop:
    dec ecx
    jnz .loop

    mov ah, 0x05
    int 0x35
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

;######################################################################################
load_configs:
    ;load configs directory
    mov esi, dir_configs_str
    mov edi, CONFIG_DIR_BUFFER
    mov edx, root_addr
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .error

    ;load BGCOLOR.CFG from configs directory
    mov edx, CONFIG_DIR_BUFFER          ;from where to load
    mov edi, CONFIGS_FILE_BUFFER        ;where to load
    mov esi, file_bgcolor_cfg           ;what to load
    mov bl, 0xff
    mov ah, 0x0a
    int 0x33
    jc .error

    mov ecx, 0xfffff
.delay:
    loop .delay

    mov esi, CONFIGS_FILE_BUFFER
.loop:
    lodsb
    cmp al, '#'
    je .skip_comment
    cmp al, 0x20
    je .loop
    cmp al, 0
    je .error

    sub esi, 1
.convert:
    call string_to_hex6
    mov [bgcolor], esi

    ;set background color
    mov dword [cur_x], 0
    mov dword [cur_y], 0

    mov edi, [frame_buffer]
    mov ecx, [real_width]
    imul ecx, [real_height]
    movzx eax, byte [bpp]
.loop1:
    add edi, eax
    mov dword [edi], esi
    loop .loop1

.done:
    ret
.skip_comment:
    lodsb
    cmp al, 0x0a
    jne .skip_comment
    jmp .convert
.error:
    mov [bgcolor], dword 0x0014C4BE
    mov esi, configs_load_err
    mov ebx, COLOR_RED
    call print_string
    call print_newline
    ret


set_pages:
    ;activate identity mapping
    PAGE_PRESENT    equ (1 << 0)
    PAGE_RW         equ (1 << 1)
    PAGE_USER       equ 4
    PAGE_CACHE_DIS  equ (1 << 4)
    PAGES_BASE      equ 0x300000
    PAGE_DIR        equ 0x700000

    cli
    ;clear PAGE_DIR
    mov edi, PAGE_DIR
    xor eax, eax
    mov ecx, 1024
    rep stosd

    mov edi, PAGES_BASE
    mov ecx, 4          ;map 20MB (4 pages)
    mov esi, PAGE_DIR
    xor eax, eax
.loop:
    push ecx
    xor ebx, ebx
    mov ecx, 1024
    push edi
    call .fill_page
    pop edi
    pop ecx

    mov edx, edi
    or edx, PAGE_PRESENT | PAGE_RW | PAGE_USER
    mov [esi], edx

    add esi, 4
    add edi, 0x1000     ;4KB
    loop .loop

    ;remove PAE Bit, set by UEFI
    mov eax, cr4
    and eax, ~(1 << 5)
    mov cr4, eax

    ;load page directory
    mov eax, PAGE_DIR
    mov cr3, eax

    ;enable paging
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    jmp .done   ;flush
.fill_page:
    mov ebx, eax
    or ebx, PAGE_PRESENT | PAGE_RW | PAGE_USER
    mov [edi], ebx

    add eax, 4096
    add edi, 4

    dec ecx
    jnz .fill_page
    ret
.done:
    sti
    ret

map_region:
    ;EAX = address
    ;EBX = size
    ;ECX = flags
    pusha

    cmp ebx, 0
    je .error

    push eax
    xor edx, edx
    mov eax, ebx
    add eax, 4095
    mov ebx, 4096
    div ebx
    
    mov ebx, eax    ;number of pages
    pop eax

.loop:
    mov edx, eax
    shr edx, 22     ;page directory index
    mov edi, edx

    shl edi, 12     ;*0x1000
    add edi, PAGES_BASE     ;address in page table

    push ecx

    mov ecx, eax
    shr ecx, 12
    and ecx, 0x3ff  ;page table index

    lea edi, [edi+ecx*4]

    pop ecx
    push edx
    call .map_page
    pop edx

    lea edi, [PAGE_DIR+edx*4]
    test dword [edi], PAGE_PRESENT
    jnz .skip

    mov esi, edx
    shl esi, 12
    add esi, PAGES_BASE

    or esi, ecx
    mov [edi], esi
.skip:
    dec ebx
    jnz .loop

    popa
    clc
    ret
.error:
    popa
    stc
    ret
.map_page:
    mov edx, eax
    and edx, 0xfffff000
    or edx, ecx
    mov [edi], edx

    add eax, 0x1000
    add edi, 4
    ret

idle_task:
    nop
    nop
    int 0x20
    jmp idle_task
; #### configure Realtime Clock ###
init_rtc:
    mov dx, 0x70
    mov al, 0x8a
    out dx, al

    ;little delay
    nop
    nop
    nop
    nop

    mov dx, 0x71
    in al, dx
    mov bl, al

    mov dx, 0x70
    mov al, 0x8a
    out dx, al

    mov al, RTC_DIVISOR
    and bl, 0xf0
    or bl, al
    mov al, bl

    mov dx, 0x71
    out dx, al


    mov dx, 0x70
    mov al, 0x8b
    out dx, al

    nop
    nop
    nop
    nop

    mov dx, 0x71
    in al, dx
    or al, (1 << 6)     ;activate periodic interrupts

    push ax

    mov dx, 0x70
    mov al, 0x8b
    out dx, al

    pop ax

    nop
    nop
    nop
    nop

    mov dx, 0x71
    out dx, al

    mov dx, 0x70
    mov al, 0x0c
    out dx, al

    nop
    nop

    mov dx, 0x71
    in al, dx

    mov edi, [sleep_timers_list]
    mov ecx, 0x1000/4
    xor eax, eax
    rep stosd

    mov edi, [counters_list]
    mov ecx, 0x1000/4
    xor eax, eax
    rep stosd

    ret

load_drivers:
    ;load drivers directory
    mov esi, dir_drivers_str
    mov edi, DIR_DRIVERS_ADDR
    mov edx, root_addr
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .drivers_dir_err

    call .check_sb16_soundcard
.loop:
    cmp byte [ohci_found], 1
    je .found_ohci
    cmp byte [intel_hd_audio], 1
    ;je .found_intel_audiodev
    cmp byte [rtl8139_found], 1
    je .found_rtl8139

    cmp byte [net_card_found], 1
    jne .skip_net

    call load_network_stack
.skip_net:
    ret
;######################################################################################
;################################ OHCI CONTROLLER #####################################
;######################################################################################
.found_ohci:
    mov byte [ohci_found], 0
    mov esi, file_ohci_sys
    mov edi, OHCI_DRIVER_ADDR
    mov edx, DIR_DRIVERS_ADDR
    mov ah, 0x0a
    mov bl, [drive_number]
    int 0x33

    mov eax, [ohci_base]
    call dword OHCI_DRIVER_ADDR
    cmp ah, 0
    je .loop

    mov [usb_devices], ah

    mov [usb_keybuffer], ebx

    mov [usb_keyboard_tdptr], edi
    mov [usb_keyboard_edptr], esi

    ;get USB devices
    mov esi, USB_DEVICE_LIST
    movzx edx, ah
.loop_usb:
    lodsb
    cmp al, 1
    je .keyboard
    cmp al, 3
    je .usb_stick

    cmp al, 0xee
    je .loop
    add esi, USB_LIST_ENTRY-1

    dec dx
    jnz .loop_usb

    mov byte [ohci_found], 0
    jmp .loop

.keyboard:
    mov byte [usb_keyboard_used], 1
    add esi, USB_LIST_ENTRY-1
    dec dx
    jnz .loop_usb

    mov byte [ohci_found], 0
    jmp .loop
.usb_stick:
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
    jnz .loop_usb

    mov byte [ohci_found], 0
    jmp .loop

;######################################################################################
;############################# SOUND BLASTER 16 #######################################
;######################################################################################
.check_sb16_soundcard:
    call .check_sb16_card
    cmp al, 0xaa
    jne .done

    mov esi, file_sb16_sys
    call load_driver_file
    jc .done

    ; driver expects in AL IRQ number to use
    xor al, al
    or al, (1 << 1)     ;IRQ 5 (QEMU has a bug which puts the IRQ handler of SB16 always to IRQ5, to be compatible with QEMU i put it there, too)

    call edi

    push edx
    mov eax, [edx+8]
    mov ebx, 0x25
    call set_irq
    pop edx

    mov [wavfile_functions], edx
.done:
    ret
;######################################################################################
;############################## INTEL HD AUDIO ########################################
;######################################################################################
.found_intel_audiodev:
    mov esi, file_intl_aud_sys
    call load_driver_file
    jc .skip_intel_audiodev

    mov eax, [intel_audiodev_base]
    call edi
.skip_intel_audiodev:
    mov byte [intel_hd_audio], 0
    jmp .loop

;######################################################################################
;############################# RTL8139 ################################################
;######################################################################################
.found_rtl8139:
    mov esi, file_rtl8139_sys
    call load_driver_file
    jc .skip_rtl8139

    mov eax, [rtl8139_base]
    call edi

    push edx
    mov eax, [edx+4]
    movzx ebx, byte [rtl8139_irq]
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


    mov byte [net_card_found], 1
.skip_rtl8139:
    mov byte [rtl8139_found], 0
    jmp .loop

;#################### END OF DRIVER INITIALIZATION ####################################
;######################################################################################
; Error loading drivers directory
.drivers_dir_err:
    call print_newline
    mov esi, .error_load_drivers
    mov ebx, COLOR_RED
    call print_string
    call print_newline
    ret
.error_load_drivers: db 'Error loading Drivers directory (either not found or disk error), ', 0x0a, 
                     db 'Keyboard, and other devices might not work. Restart the PC. If this keeps continuing,', 0x0a, 
                     db 'the directory is missing or the filesystem could be damaged', 0
.test_file: db 'TEST    WAV'

.check_sb16_card:
    mov dx, 0x226
    mov al, 1
    out dx, al

    ;delay
    mov dx, 0x80
    in al, dx
    in al, dx
    in al, dx
    in al, dx

    mov dx, 0x226
    xor al, al
    out dx, al

    mov dx, 0x22e
.sb_rdy:
    in al, dx
    test al, (1 << 7)
    jz .sb_rdy

    mov dx, 0x22a
    in al, dx
    ret

load_driver_file:
    ;Input: ESI = filename
    ;Output: EDI = startaddress
    xor ah, ah
    mov edi, DIR_DRIVERS_ADDR
    int 0x33
    jc .error1

    push esi

    mov ah, 0x0a
    int 0x35
    jc .low_mem

    mov [.heap], esi
    mov [.size], ecx

    mov edi, esi
    pop esi
    mov edx, DIR_DRIVERS_ADDR
    mov ah, 0x0a
    mov bl, [drive_number]
    int 0x33
    jc .error

    call load_coff_obj

    clc
    ret
.error1:
    stc
    ret
.error:
    mov esi, [.heap]
    mov ecx, [.size]
    mov ah, 0x0b
    int 0x35

    stc
    ret
.low_mem:
    mov esi, .low_mem_str
    mov ebx, COLOR_RED
    call print_string
    stc
    ret
.heap: dd 0
.size: dd 0
.low_mem_str: db 'Couldnt find free memory to load driver. The system seems to be low on memory', 0x0a, 0


;######################################################################################
;################## LOAD NETWORK STACK FROM NETWORK DIRECTORY #########################
;######################################################################################
load_network_stack:
    pusha
    xor eax, eax
    mov edi, NET_INTERFACE
    mov ecx, 25
    rep stosd

    mov ecx, 0x1000
    mov ah, 0x0a
    int 0x35

    mov [.heap], esi
    mov edi, esi
    mov esi, dir_network_str
    xor edx, edx
    mov ah, 0x0a
    mov bl, [drive_number]
    int 0x33
    jc .error

    ;load and execute IP.OBJ first time
    xor ah, ah
    mov esi, file_ip_sys
    int 0x33
    jc .error

    mov ah, 0x0a
    int 0x35
    jc .low_memory

    mov edx, [.heap]
    mov edi, esi
    mov esi, file_ip_sys
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .error

    call load_coff_obj
    mov [.ipobj_addr], edi

    mov eax, ip_packet
    call edi

    mov edi, NET_INTERFACE
    mov [edi+16], edx       ;store pointer to function add_ipheader()

    ;load and execute PROTOCOL.OBJ first time
    xor ah, ah
    mov edi, [.heap]
    mov esi, file_protocol_sys
    int 0x33
    jc .error

    mov ah, 0x0a
    int 0x35
    jc .low_memory

    mov edx, [.heap]
    mov edi, esi
    mov esi, file_protocol_sys
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .error

    call load_coff_obj
    mov [.protocolobj_addr], edi

    ;mov eax, ip_packet
    call edi

    mov edi, NET_INTERFACE
    mov dword [edi+56], application_packet
    add edi, 20
    mov ecx, 4
.loop1:
    mov eax, [edx]
    mov [edi], eax
    add edx, 4
    add edi, 4
    dec ecx
    jnz .loop1

    add edi, 4
    mov ecx, 4
.loop2:
    mov eax, [edx]
    mov [edi], eax
    add edx, 4
    add edi, 4
    dec ecx
    jnz .loop2

    ;execute IP.OBJ second time
    mov ebx, NET_INTERFACE
    call dword [.ipobj_addr]

    ;execute PROTOCOL.OBJ second time
    mov ebx, NET_INTERFACE
    call dword [.protocolobj_addr]
    mov byte [net_active], 0
    mov byte [net_stack_loaded], 1

    mov esi, [.heap]
    mov ecx, 0x1000
    mov ah, 0x0b
    int 0x35
    popa
    clc
    ret

.heap: dd 0
.ipobj_addr: dd 0
.protocolobj_addr: dd 0

.error:
    mov esi, .error_msg
    mov ebx, COLOR_RED
    call print_string
    mov byte [net_active], 0
    popa
    stc
    ret
.low_memory:
    mov esi, load_driver_file.low_mem_str
    mov ebx, COLOR_RED
    call print_string
    mov byte [net_active], 0
    popa
    ret
.error_msg: db 'Error loading network files. Network unavailable', 0x0a, 0

%include "data/data.asm"
%include "kernel/stdfunc.asm"
%include "syscalls/output.asm"
%include "syscalls/exceptions.asm"
%include "syscalls/idt.asm"
%include "shell/shell.asm"
%include "drivers/fs16.asm"
%include "drivers/pci.asm"
%include "syscalls/string.asm"
%include "syscalls/system.asm"
font8x16:
    incbin "data/DEFAULT.FNT"
    ;incbin "build/font_ru_RU.fnt"
disk_error_msg: db 'Disk Read Error', 0
usb_devices: db 0
intel_hd_audio: db 0
intel_audiodev_base: dd 0           ;MMIO Base Address
rtl8139_found: db 0
rtl8139_base: dd 0
rtl8139_irq: db 0
net_card_found: db 0
net_stack_loaded: db 0
PIT_DIVISOR     equ 0x2e9c          ;10ms
RTC_DIVISOR     equ 0x06            ;interrupt every 0,976ms
;memory map
;0x0000 - 0x4000:      root directory
;0x4000 - 0x7c00:      FAT
;0x7c00 - 0x8000:      boot sector
;0x8000 - 0x50000:     kernel
;0x200000: programs