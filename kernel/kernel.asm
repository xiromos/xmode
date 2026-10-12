[org 0x8000]
bits 16

start:
    cli
    xor ax, ax
    mov es, ax
    mov ds, ax

    mov [drive_number], dl
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
    mov ax, 0x7500
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

    call bios_load_drivers

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
    mov esi, 0x75000
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
    mov eax, cr0
    and eax, ~(1 << 16)     ;remove write protect bit
    mov cr0, eax

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

    ;map window packet area as "read-only"
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_CACHE_DIS | PAGE_USER
    mov eax, [win_packet_base]
    mov ebx, 4096
    call map_region
    
    mov edi, [win_packet_base]
    mov ecx, [max_window_packets]
    imul ecx, WIN_PACKET_SIZE
    shr ecx, 2
    xor eax, eax
    rep stosd

    mov eax, [global_key_buffers]
    mov ebx, 0x1000
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_CACHE_DIS | PAGE_USER
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

    mov ecx, [real_width]
    mov edx, [real_height]
    imul ecx, edx
    movzx edx, byte [bpp]
    imul ecx, edx
    mov ah, 0x0a
    int 0x35
    mov [frame_buffer_copy], esi

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

    mov ebp, esp
    mov esi, [idle_task_stack]
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

    inc word [task_count]
    mov edi, tasks_esp
    add edi, TASK_SIZE      ;task 1 - shell
    mov esi, shell_task_str
    mov ecx, 11
    rep movsb

    mov ebx, init_system  
    mov esi, program_init_sys
    mov ah, 0x13
    int 0x35

    call scan_disk_pci
    call search_boot_device
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

    call load_driver_assets
    jc .skip_drivers
    call scan_pci_driver
.skip_drivers:

    call load_drivers
    mov edx, [bm_base]
    call print_hex8

    ; mov ebx, init_system  
    ; mov esi, program_init_sys
    ; mov ah, 0x13
    ; int 0x35
    
    mov al, 0x20
    call print_char

    mov edx, [abar]
    call print_hex8

    mov al, 0x20
    call print_char

    mov edx, [ohci_base]
    call print_hex8
    call print_newline

    call load_configs
    jc .config_err

    mov byte [boot_done], 1
    int 0x20

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
    ;inc word [task_count]
    jmp .init_first_task

.config_err:
    mov esi, configs_load_err
    mov ebx, COLOR_RED
    call print_string
    call print_newline
.init_first_task:
    ; mov edi, tasks_esp
    ; add edi, TASK_SIZE      ;task 1 - shell
    ; mov esi, shell_task_str
    ; mov ecx, 11
    ; rep movsb

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

search_boot_device:
    pusha
    mov ah, 0x0a
    mov ecx, 512
    int 0x35

    xor edx, edx
.loop:
    cmp dl, [avail_disks]
    ja .error

    push edx
    mov dh, 0x0b
    mov ax, 1
    mov edi, esi
    xor ecx, ecx
    call read_drive
    pop edx
    jc .skip

    push esi
    push edi
    mov esi, volume_label
    add edi, 0x2b
    mov ecx, 11
    repe cmpsb
    pop edi
    pop esi
    jne .skip

    mov ecx, [volume_id]
    cmp [edi+0x27], ecx
    jne .skip

    mov byte [boot_drive], dl
    mov byte [drive_number], dl

    mov ah, 0x0b
    mov ecx, 512
    int 0x35
    popa
    ret
.skip:
    inc dl
    jmp .loop
.error:
    mov byte [boot_drive], 2
    mov byte [drive_number], 2

    mov ah, 0x0b
    mov ecx, 512
    int 0x35
    popa
    ret

init_system:
    cmp byte [boot_done], 1
    je .done

    int 0x20
    jmp init_system
.done:
    mov ah, 0x05
    int 0x35
    ret

load_configs:
    ;load configs directory
    mov esi, dir_configs_str
    mov edi, CONFIG_DIR_BUFFER
    mov edx, root_addr
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc rsod

    mov ah, 0x0a
    mov ecx, 0x8000
    int 0x35

    push esi
    mov ah, 0x0a
    mov edx, CONFIG_DIR_BUFFER
    mov edi, esi
    mov esi, file_default_fnt
    mov bl, [drive_number]
    int 0x33
    jc rsod

    pop esi
    mov [font8x16], esi

    mov eax, esi
    mov ebx, 0x8000
    xor ecx, ecx
    or ecx, PAGE_PRESENT | PAGE_USER
    call map_region

    xor ah, ah
    mov edi, CONFIG_DIR_BUFFER
    mov esi, file_mouse_bmp
    mov bl, [drive_number]
    int 0x33
    jc .error

    mov ah, 0x0a
    int 0x35

    mov dword [ps2_mouse_handler.mouse_bmp], esi

    ;load MOUSE.BMP from configs directory
    mov edx, CONFIG_DIR_BUFFER
    mov edi, esi
    mov esi, file_mouse_bmp
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .error

    ;load BGCOLOR.CFG from configs directory
    mov edx, CONFIG_DIR_BUFFER          ;from where to load
    mov edi, CONFIGS_FILE_BUFFER        ;where to load
    mov esi, file_bgcolor_cfg           ;what to load
    mov bl, [drive_number]
    mov ah, 0x0a
    int 0x33
    jc .error

    mov esi, CONFIGS_FILE_BUFFER
    mov edi, .loop
.loop:
    lodsb
    cmp al, '#'
    je .skip_comment
    cmp al, 0x20
    je .loop
    cmp al, 0x0a
    je .loop
    cmp al, 0
    je .error

    sub esi, 1
    push esi
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

    ;get color for window border
    mov edi, .loop_winb
    pop esi
    add esi, 6

.loop_winb:
    lodsb
    cmp al, '#'
    je .skip_comment
    cmp al, 0x20
    je .loop
    cmp al, 0x0a
    je .loop
    cmp al, 0
    je .done

    sub esi, 1
    call string_to_hex6
    mov [win_border_color], esi
.done:
    ret
.skip_comment:
    lodsb
    cmp al, 0x0a
    jne .skip_comment
    cmp al, 0
    je .done
    jmp edi

.error:
    mov dword [bgcolor], 0x0014C4BE
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
    call .check_sb16_soundcard
    call .check_ps2_mouse
    ret
;     ;load drivers directory
;     mov esi, dir_drivers_str
;     mov edi, DIR_DRIVERS_ADDR
;     mov edx, root_addr
;     mov bl, [drive_number]
;     mov ah, 0x0a
;     int 0x33
;     jc .drivers_dir_err

; .loop:
;     cmp byte [ohci_found], 1
;     je .found_ohci
;     cmp byte [intel_hd_audio], 1
;     ;je .found_intel_audiodev
;     cmp byte [rtl8139_found], 1
;     je .found_rtl8139

;     cmp byte [net_card_found], 1
;     jne .skip_net

;     call load_network_stack
; .skip_net:
;     ret
; ;######################################################################################
; ;################################ OHCI CONTROLLER #####################################
; ;######################################################################################
; .found_ohci:
;     mov byte [ohci_found], 0
;     mov esi, file_ohci_sys
;     mov edi, OHCI_DRIVER_ADDR
;     mov edx, DIR_DRIVERS_ADDR
;     mov ah, 0x0a
;     mov bl, [drive_number]
;     int 0x33

;     mov eax, [ohci_base]
;     call dword OHCI_DRIVER_ADDR
;     cmp ah, 0
;     je .loop

;     mov [usb_devices], ah

;     mov [usb_keybuffer], ebx

;     mov [usb_keyboard_tdptr], edi
;     mov [usb_keyboard_edptr], esi

;     ;get USB devices
;     mov esi, USB_DEVICE_LIST
;     movzx edx, ah
; .loop_usb:
;     lodsb
;     cmp al, 1
;     je .keyboard
;     cmp al, 3
;     je .usb_stick

;     cmp al, 0xee
;     je .loop
;     add esi, USB_LIST_ENTRY-1

;     dec dx
;     jnz .loop_usb

;     mov byte [ohci_found], 0
;     jmp .loop

; .keyboard:
;     mov byte [usb_keyboard_used], 1
;     add esi, USB_LIST_ENTRY-1
;     dec dx
;     jnz .loop_usb

;     mov byte [ohci_found], 0
;     jmp .loop
; .usb_stick:
;     movzx edi, byte [avail_disks]
;     imul edi, DRIVE_LIST_ENTRY
;     add edi, DRIVE_LIST_ADDR

;     ;copy vendor name
;     push esi
;     push edi
;     mov ecx, 8
;     rep movsb
;     pop edi
;     pop esi

;     mov byte [edi+8], 0x10      ;OHCI
;     mov byte [edi+9], 0xbe      ;USB

;     mov eax, [ohci_base]
;     mov [edi+12], eax

;     mov ax, [esi+32]
;     mov [edi+10], ax

;     mov eax, [esi+24]           ;max LBA
;     mov [edi+32], eax
;     mov eax, [esi+28]           ;block size
;     mov [edi+36], eax

;     push esi
;     add edi, 16
;     add esi, 8
;     mov ecx, 16
;     rep movsb
;     pop esi

;     inc byte [avail_disks]
;     add esi, USB_LIST_ENTRY-1
;     dec dx
;     jnz .loop_usb

;     mov byte [ohci_found], 0
;     jmp .loop
; ;######################################################################################
; ;############################## INTEL HD AUDIO ########################################
; ;######################################################################################
; .found_intel_audiodev:
;     mov esi, file_intl_aud_sys
;     call load_driver_file
;     jc .skip_intel_audiodev

;     mov eax, [intel_audiodev_base]
;     call edi
; .skip_intel_audiodev:
;     mov byte [intel_hd_audio], 0
;     jmp .loop

; ;######################################################################################
; ;############################# RTL8139 ################################################
; ;######################################################################################
; .found_rtl8139:
;     mov esi, file_rtl8139_sys
;     call load_driver_file
;     jc .skip_rtl8139

;     mov eax, [rtl8139_base]
;     call edi

;     push edx
;     mov eax, [edx+4]
;     movzx ebx, byte [rtl8139_irq]
;     call set_irq
;     pop edx

;     mov eax, [edx]
;     mov [ip_packet], eax
;     mov eax, edx
;     add eax, 38
;     mov [ip_packet+4], eax
;     mov eax, [edx+42]
;     mov [ip_packet+14], eax

;     mov edi, ip_packet+8
;     mov esi, edx
;     add esi, 32
;     mov ecx, 6
;     rep movsb

;     ; mov edi, [edx+12]
;     ; mov [packet_stats], edi
;     ; mov edi, [edx+16]
;     ; mov [packet_stats+4], edi
;     ; mov edi, [edx+20]
;     ; mov [packet_stats+8], edi
;     ; mov edi, [edx+24]
;     ; mov [packet_stats+12], edi


;     mov byte [net_card_found], 1
; .skip_rtl8139:
;     mov byte [rtl8139_found], 0
;     jmp .loop

; ;#################### END OF DRIVER INITIALIZATION ####################################
; ;######################################################################################
; ; Error loading drivers directory
; .drivers_dir_err:
;     call print_newline
;     mov esi, .error_load_drivers
;     mov ebx, COLOR_RED
;     call print_string
;     call print_newline
;     ret
; .error_load_drivers: db 'Error loading Drivers directory (either not found or disk error), ', 0x0a, 
;                      db 'Keyboard, and other devices might not work. Restart the PC. If this keeps continuing,', 0x0a, 
;                      db 'the directory is missing or the filesystem could be damaged', 0

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

.check_ps2_mouse:
    ;load driver file
    mov esi, file_ps2mouse_sys
    call load_driver_file
    jc .no_ps2_mouse

    call edi
    jc .no_ps2_mouse

    cli
    mov byte [ps2_mouse_active], 1
    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35
    mov [ps2_mouse_handler.prev_bg], esi

    mov edi, esi
    mov esi, [frame_buffer]
    mov eax, [ps2_mouse_handler.m_cur_x]
    movzx ecx, byte [bpp]
    imul eax, ecx
    add esi, eax

    mov eax, [ps2_mouse_handler.m_cur_y]
    imul eax, dword [pitch]
    add esi, eax

    mov edx, 16
    imul ecx, 8
.loop_buffer:
    push ecx
    rep movsb
    pop ecx

    sub esi, ecx
    add esi, dword [pitch]

    dec edx
    jnz .loop_buffer
.no_ps2_mouse:
    sti
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

;######################################################################################
;############################# LOAD BOOT DRIVER FILES #################################
;######################################################################################

bits 16
bios_load_drivers:
    xor ax, ax
    mov es, ax

    mov word [dap+2], 1
    mov word [dap+4], 0x7c00

    mov ah, 0x42
    mov si, dap
    mov dl, [drive_number]
    int 0x13

    mov cx, 8
    mov si, .fat16_str
    mov di, 0x7c00+0x36
    repe cmpsb
    jne .done

    mov ax, [0x7c00+0x0b]
    mov [.bytes_per_sec], ax
    mov al, [0x7c00+0x0d]
    mov [.sec_per_cluster], al
    mov ax, [0x7c00+0x0e]
    mov [.reserved_sectors], ax
    mov al, [0x7c00+0x10]
    mov [.fat_num], al
    mov ax, [0x7c00+0x11]
    mov [.root_entries], ax
    mov ax, [0x7c00+0x16]
    mov [.fat_size], ax
    mov eax, [0x7c00+0x1c]
    mov [.hidden_sectors], eax

    mov ax, [.root_entries]
    mov bx, 32
    mul bx

    mov bx, 512
    add ax, bx
    dec ax
    xor dx, dx
    div bx

    mov [.root_sectors], ax

    ;calculate root dir start
    ;ReservedAreaCnt + (NumberOfFATs * FATSz16)

    xor eax, eax
    mov al, [.fat_num]
    mov bx, [.fat_size]
    mul bx
    add ax, word [.reserved_sectors]
    add eax, dword [.hidden_sectors]

    mov word [dap+4], 0x500
    mov bx, [.root_sectors]
    mov [dap+2], bx
    mov [dap+8], eax

    add ax, [.root_sectors]
    mov ebp, eax

    mov ah, 0x42
    mov si, dap
    mov dl, [drive_number]
    int 0x13

    mov eax, [.hidden_sectors]
    add ax, [.reserved_sectors]
    mov [dap+8], eax
    mov ax, [.fat_size]
    mov [dap+2], ax
    mov word [dap+4], 0x4000

    mov ah, 0x42
    mov si, dap
    mov dl, [drive_number]
    int 0x13

    ;load drivers directory
    mov eax, DIR_DRIVERS_ADDR
    call .addr_to_seg_off
    mov di, cx
    mov si, .dir_drivers_str
    mov ax, 0x500
    xor dx, dx
    call .load_file

    ;load OHCI.SYS
    mov edi, OHCI_ADDR
    mov si, .file_ohci_sys
    call .load_driver_file
    jnc .uhci

    mov eax, OHCI_ADDR
    call .write_fail

.uhci:
    ;load UHCI.SYS
    mov edi, UHCI_ADDR
    mov si, .file_uhci_sys
    call .load_driver_file
    jnc .ehci

    mov eax, UHCI_ADDR
    call .write_fail

.ehci:
    ;load EHCI.SYS
    mov edi, EHCI_ADDR
    mov si, .file_ehci_sys
    call .load_driver_file
    jnc .xhci

    mov eax, EHCI_ADDR
    call .write_fail

.xhci:
    ;load XHCI.SYS
    mov edi, XHCI_ADDR
    mov si, .file_xhci_sys
    call .load_driver_file
    jnc .nvme

    mov eax, XHCI_ADDR
    call .write_fail

.nvme: 
    ;load NVME.SYS
    mov edi, NVME_ADDR
    mov si, .file_nvme_sys
    call .load_driver_file
    jnc .fdc

    mov eax, NVME_ADDR
    call .write_fail

.fdc:
    ;load FDC.SYS
    mov edi, FDC_ADDR
    mov si, .file_fdc_sys
    call .load_driver_file
    jnc .sdc

    mov eax, FDC_ADDR
    call .write_fail

.sdc:
    ;load SDC.SYS
    mov edi, SDC_ADDR
    mov si, .file_sdc_sys
    call .load_driver_file
    jnc .done

    mov eax, SDC_ADDR
    call .write_fail
.done:
    ret
.fat16_str: db 'FAT16   '
.load_driver_file:
    ;EDI = address
    ;SI = *file
    mov eax, DIR_DRIVERS_ADDR
    call .addr_to_seg_off
    mov dx, bx
    mov ax, cx

    push ax
    mov eax, edi
    call .addr_to_seg_off
    mov di, cx
    pop ax
    call .load_file
    ret
.write_fail:
    ;EAX = addr
    call .addr_to_seg_off
    mov ax, bx
    mov es, ax
    mov di, cx
    mov dword [es:di], 'FAIL'
    ret

.load_file:
    ;SI = *filename
    ;BX:DI = where to load
    ;DX:AX = *directory
    push di
    mov di, ax
    mov ax, dx
    mov es, ax
    mov dx, [.root_entries]
.loop1:
    mov cx, 11
    push di
    push si
    rep cmpsb
    pop si
    pop di
    je .found

    add di, 32
    dec dx
    jnz .loop1

    pop di
    xor ax, ax
    mov es, ax
.error_load:
    stc
    ret
.found:
    pop si
    mov [dap+4], si
    mov [dap+6], bx
    movzx ax, byte [.sec_per_cluster]
    mov [dap+2], ax

    mov dword [dap+8], 0

    mov dx, [es:di+0x1a]
    xor ax, ax
    mov es, ax
.loop:
    mov ax, dx
    call .cluster_to_sec

    push dx
    mov [dap+8], ax
    mov ah, 0x42
    mov si, dap
    mov dl, [drive_number]
    int 0x13
    pop dx
    jc .error_load

    movzx ax, byte [.sec_per_cluster]
    mov bx, [.bytes_per_sec]
    mul bx

    clc
    mov cx, [dap+4]
    add cx, ax
    jc .segment
    mov [dap+4], cx
    jmp .cluster
.segment:
    mov [dap+4], cx
    mov ax, [dap+6]
    add ax, 0x1000
    add [dap+6], ax
.cluster:

    mov si, 0x4000
    mov ax, dx
    shl ax, 1
    add si, ax
    mov ax, [si]
    mov dx, ax

    cmp ax, 0
    je .error_load

    cmp ax, 0xfff7
    je .error_load

    cmp ax, 0xfff8
    jb .loop

    clc
    ret
.cluster_to_sec:
    push cx
    sub ax, 2
    movzx cx, byte [.sec_per_cluster]
    mul cx
    add ax, bp
    pop cx
    ret
.addr_to_seg_off:
    ;EAX = 32bit address
    ;Output:
    ;   BX = segment
    ;   CX = offset
    mov ecx, eax
    and ecx, 0x0f
    shr eax, 4
    movzx ebx, ax
    ret

; ## data ##
.dir_drivers_str:   db 'DRIVERS    '
.file_ohci_sys:     db 'OHCI    SYS'
.file_uhci_sys:     db 'UHCI    SYS'
.file_ehci_sys:     db 'EHCI    SYS'
.file_xhci_sys:     db 'XHCI    SYS'
.file_nvme_sys:     db 'NVME    SYS'
.file_fdc_sys:      db 'FDC     SYS'
.file_sdc_sys:      db 'SDC     SYS'

.sec_per_cluster: db 0
.reserved_sectors: dw 0
.fat_num: db 0
.root_entries: dw 0
.total_sectors: dw 0
.fat_size: dw 0
.hidden_sectors: dd 0
.bytes_per_sec: dw 0

.root_start: dd 0
.root_sectors: dw 0
.data_start: dd 0

dap:
    db 0x10
    db 0
    dw 0    ;number of sectors to read
    dw 0    ;offset
    dw 0    ;segment
    dq 0    ;LBA
drive_number: db 0

bits 32
%include "kernel/pci.asm"
%include "data/data.asm"
%include "kernel/stdfunc.asm"
%include "syscalls/output.asm"
%include "syscalls/exceptions.asm"
%include "syscalls/idt.asm"
%include "shell/shell.asm"
%include "drivers/fs16.asm"
%include "syscalls/string.asm"
%include "syscalls/system.asm"
font8x16: dd 0
    ;incbin "data/DEFAULT.FNT"
    ;incbin "build/font_ru_RU.fnt"
disk_error_msg: db 'Disk Read Error', 0
usb_devices: db 0
net_card_found: db 0
net_stack_loaded: db 0
ps2_mouse_active: db 0
drvrlist_addr: dd 0
drvrlist_filesize: dd 0
boot_done: db 0
PIT_DIVISOR     equ 0x2e9c          ;10ms
RTC_DIVISOR     equ 0x06            ;interrupt every 0,976ms
;memory map
;0x0000 - 0x4000:      root directory
;0x4000 - 0x7c00:      FAT
;0x7c00 - 0x8000:      boot sector
;0x8000 - 0x50000:     kernel
;0x200000: programs