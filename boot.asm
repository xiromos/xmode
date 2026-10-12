;=========================================================================
;64-Bit Bootloader for xmode OS
;stored in the directory /EFI/BOOT/
;-------------------------------------------------------------------------
;Copyright (C) 2026 Technodon
;=========================================================================

section .text
    global _efi_main

_efi_main:
    mov [rel image_handle], rcx
    mov [rel system_table], rdx
    ; mov r15, rdx

    ; ;get boot drive information
    ; push rbp
    ; mov rbp, rsp
    ; sub rsp, 48

    ; lea rdx, [rel loaded_image_guid]
    ; lea r8, [rel loaded_image_ptr]
    ; mov r9, rcx

    ; xor rax, rax
    ; mov [rsp+32], rax
    ; mov dword [rsp+40], 1

    ; mov rsi, [r15+SYSTEM_TABLE.BOOT_SERVICES]
    ; call qword [rsi+280]    ;OpenProtocol

    ; mov rsp, rbp
    ; pop rbp

    ; test rax, rax
    ; jnz .failed

    ; mov rbx, [rel loaded_image_ptr]
    ; mov rcx, [rbx+24]

    ; push rbp
    ; mov rbp, rsp
    ; sub rsp, 48

    ; lea rdx, [rel device_path_guid]
    ; lea r8, [rel device_path]
    ; mov r9, [rel image_handle]

    ; xor rax, rax
    ; mov [rsp+32], rax
    ; mov dword [rsp+40], 1
    ; mov rsi, [r15+SYSTEM_TABLE.BOOT_SERVICES]
    ; call qword [rsi+280]

    ; mov rsp, rbp
    ; pop rbp

    ; test rax, rax
    ; jnz .failed

    ; mov rbx, [rel device_path]
    ; cli
    ; hlt

    mov rax, [rdx+SYSTEM_TABLE.BOOT_SERVICES]
    lea rcx,[rel gop_guid]
    xor rdx, rdx
    lea r8, [rel gop]

    sub rsp, 40
    call qword [rax+BOOT_SERVICES.LOCATE_PROTOCOL]
    add rsp, 40
    test rax, rax
    jnz .failed

    mov rbx, [rel gop]
    mov rbx, [rbx+0x18]

    mov rax, [rbx+24]     ;frame buffer base
    mov [rel recom_frame_buffer], rax

    mov rdx, [rbx+8]
    mov eax, [rdx+4]
    mov [rel recom_width], eax

    mov eax, [rdx+8]
    mov [rel recom_height], eax

    mov eax, [rdx+32]
    mov [rel recom_pitch], eax

    mov rcx, 2000
    mov rdi, [rel recom_frame_buffer]
    mov eax, [rel recom_width]
    mov ebx, [rel recom_height]
.loop:
    mov [rdi], dword 0x000000ff
    add rdi, 4
    dec rcx
    jnz .loop

    ; #### open file /XCONFIGS/BOOT.CFG to check, if to ask for screen resolution yes or no ####
    mov rax, [rel system_table]
    mov rax, [rax+SYSTEM_TABLE.BOOT_SERVICES]       ;BootServices
    lea rcx, [rel sfs_guid]
    xor rdx, rdx
    lea r8, [rel simple_fs]

    sub rsp, 40
    call qword [rax+BOOT_SERVICES.LOCATE_PROTOCOL]
    add rsp, 40

    test rax, rax
    jnz .no_bootservices

    ;open root
    mov rcx, [rel simple_fs]
    lea rdx, [rel root]

    sub rsp, 40
    call qword [rcx+8]
    add rsp, 40

    test rax, rax
    jnz .root_failed

    mov rcx, [rel root]
    lea rdx, [rel cfg_file]
    lea r8, [rel cfg_bin]
    mov r9, 1       ;EFI_FILE_MODE_READ

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jnz .no_file_found

    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel cfg_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jnz .no_file_found

    mov rax, [rel file_info+8]
    mov [rel cfg_size], rax

    mov rcx, [rel cfg_file]
    lea rdx, [rel cfg_size]
    mov r8, 0x8000      ;buffer - load file at 0x8000

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40

    mov rsi, 0x8000
    call parse_cfg_file

    cmp ah, 1
    jne .xga_res

    ; #### list all screen resolutions ####

    lea rsi, [rel resolution_str]
    call print_string

    mov rbx, [rel gop]
    mov rax, [rbx+24]       ;mode

    mov ecx, [rax]          ;max mode
    xor esi, esi
    mov r15, 'a'
    lea rdi, [rel res_buffer]
.search_loop:
    cmp esi, ecx
    jge .ask

    mov rcx, [rel gop]
    mov edx, esi
    lea r8, [rel info_size]
    lea r9, [rel info_ptr]

    push rdi
    mov rdi, rcx

    sub rsp, 40
    call qword [rcx]
    add rsp, 40

    mov rcx, rdi
    pop rdi

    test rax, rax
    jnz .next_mode

    push rsi
    push rcx

    mov rax, r15
    call print_char
    mov ax, ':'
    call print_char

    mov rdx, [rel info_ptr]
    push rdx
    mov eax, [rdx+4]            ;width
    stosd
    push rdi
    call print_dec

    mov ax, 'x'
    call print_char
    pop rdi
    pop rdx
    push rdi

    mov eax, [rdx+8]            ;height
    pop rdi
    stosd
    push rdi
    call print_dec

    mov ax, 0x0a
    call print_char
    mov ax, 0x0d
    call print_char

    pop rdi
    pop rcx
    pop rsi

    cmp r15, 'z'
    jne .skip

    mov r15, 'A'
    dec r15
.skip:
    inc r15

    jmp .next_mode
.ask:
    ;get keypress
    push r15
    sub rsp, 40

    ;clear key buffer
    mov rax, [rel system_table]
    mov rcx, [rax+48]
    xor rdx, rdx
    call qword [rcx]
    add rsp, 40

.wait_loop:
    sub rsp, 40
    mov rax, [rel system_table]
    mov rcx, [rax+48]
    lea rdx, [rel efi_input_key]
    call qword [rcx+8]
    add rsp, 40

    test rax, rax
    jnz .wait_loop

    movzx rax, word [rel efi_input_key+2]   ;char
    pop r15

    cmp rax, 0x0d
    je .xga_res

    cmp rax, 0x41
    jb .ask
    cmp rax, 0x5a
    ja .check_little

    sub rax, 0x41
    jmp .table

.check_little:
    cmp rax, 0x7a
    ja .ask

    sub rax, 0x61
    add rax, 26

.table:
    lea rbx, [rel keymap]
    movzx rbx, byte [rbx+rax]
    mov esi, ebx

    mov rcx, [rel gop]
    mov edx, esi

    mov rdi, rcx

    sub rsp, 40
    call qword [rcx+8]          ;SetMode
    add rsp, 40

    mov rcx, rdi

.get_video_data:
    mov rbx, [rel gop]
    mov rbx, [rbx+24]

    mov rax, [rbx+24]
    mov [rel frame_buffer], rax

    mov rdx, [rbx+8]
    mov eax, [rdx+4]
    mov [rel width], eax
    mov eax, [rdx+8]
    mov [rel height], eax
    mov eax, [rdx+12]       ;PixelFormat (BBGGRRXX)
    imul eax, 4             ;bytes per pixel
    mov [rel bpp], eax


    mov rdi, [rel frame_buffer]
    mov rcx, 2000
.loop2:
    mov [rdi], dword 0x00ff0000
    add rdi, 4
    dec rcx
    jnz .loop2

    lea rsi, [rel graphic_success]
    call print_string

    call get_vendor

    mov rax, [rel system_table]
    mov rax, [rax+SYSTEM_TABLE.BOOT_SERVICES]       ;BootServices
    lea rcx, [rel sfs_guid]
    xor rdx, rdx
    lea r8, [rel simple_fs]

    sub rsp, 40
    call qword [rax+BOOT_SERVICES.LOCATE_PROTOCOL]
    add rsp, 40

    test rax, rax
    jnz .no_bootservices

    ;open root
    mov rcx, [rel simple_fs]
    lea rdx, [rel root]

    sub rsp, 40
    call qword [rcx+8]
    add rsp, 40

    test rax, rax
    jnz .root_failed

    mov rcx, [rel root]
    lea rdx, [rel xmode_file]
    lea r8, [rel xmode_bin]
    mov r9, 1       ;EFI_FILE_MODE_READ

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jnz .no_file_found

    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel xmode_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jnz .no_file_found

    mov rax, [rel file_info+8]
    mov [rel xmode_size], rax

    mov rcx, [rel xmode_file]
    lea rdx, [rel xmode_size]
    mov r8, 0x8000      ;buffer - kernel is loaded at 0x00008000

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40

    lea rsi, [rel kernel_found_str]
    call print_string

    call load_drivers

.get_mmap:
    ;get memory map
    mov rax, [rel system_table]
    mov rax, [rax+SYSTEM_TABLE.BOOT_SERVICES]

    lea rcx, [rel mmap_size]
    mov rdx, [rel mmap]
    lea r8, [rel map_key]
    lea r9, [rel desc_size]

    sub rsp, 48
    lea r10, [rel desc_ver]
    mov [rsp+32], r10
    call qword [rax+BOOT_SERVICES.GET_MEMORY_MAP]
    add rsp, 48

    test rax, rax
    jnz .get_mmap

    call .copy_mmap

    mov rax, [rel system_table]
    mov rax, [rax+SYSTEM_TABLE.BOOT_SERVICES]
    mov rcx, [rel image_handle]
    mov rdx, [rel map_key]

    sub rsp, 40
    call qword [rax+BOOT_SERVICES.EXIT_BOOT_SERVICES]
    add rsp, 40

    test rax, rax
    jnz .exit_fail

    jmp exit_boot
    cli
    hlt
.copy_mmap:
    xor rdx, rdx
    mov rax, [rel mmap_size]
    mov rcx, [rel desc_size]
    div rcx
    mov rcx, rax

    xor rbx, rbx

    mov rsi, [rel mmap]
    mov rdi, MEM_MAP_ADDR
    mov rdx, [rel desc_size]
.loop_copy:
    mov eax, [rsi]
    cmp eax, 0
    jne .no_nullentry

    add rsi, rdx
    dec rcx
    jnz .loop_copy
    jmp .done_copy
.no_nullentry:
    movzx rax, dword [rsi]          ;type
    cmp eax, 7
    je .free_mem
    cmp eax, 3
    je .free_mem
    cmp eax, 4
    je .free_mem

    mov dword [rdi+16], 2
.continue_copy:
    mov rax, [rsi+8]        ;start address
    mov [rdi], rax

    mov rax, [rsi+24]       ;size in 4Kib pages
    shl rax, 12
    mov [rdi+8], rax

    add rdi, 20
    add rsi, rdx

    inc rbx
    dec rcx
    jnz .loop_copy

.done_copy:
    lea rsi, [rel kernel_packet]
    mov [rsi+8], ebx
    ret
.free_mem:
    mov dword [rdi+16], 1
    jmp .continue_copy
.next_mode:
    inc rsi
    jmp .search_loop
.next_mode2:
    inc rsi
    jmp .search_loop2
.xga_res:
    mov rbx, [rel gop]
    mov rax, [rbx+24]       ;mode

    mov ecx, [rax]          ;max mode
    xor esi, esi
.search_loop2:
    cmp esi, ecx
    jge .no_xga

    mov rcx, [rel gop]
    mov edx, esi
    lea r8, [rel info_size]
    lea r9, [rel info_ptr]

    mov rdi, rcx

    sub rsp, 40
    call qword [rcx]
    add rsp, 40

    mov rcx, rdi

    test rax, rax
    jnz .next_mode2

    mov rdx, [rel info_ptr]
    mov eax, [rdx+4]            ;width
    cmp eax, 1024               ;search for XGA resolution
    jne .next_mode2

    mov eax, [rdx+8]            ;height
    cmp eax, 768
    jne .next_mode2

    ;found
    mov rcx, [rel gop]
    mov edx, esi

    mov rdi, rcx

    sub rsp, 40
    call qword [rcx+8]          ;SetMode
    add rsp, 40

    mov rcx, rdi

    test rax, rax
    jnz .no_xga
    jmp .get_video_data
.failed:
    mov ecx, 0xaaaaaaaa         ;debug
    mov ebx, 0x77777777
    cli
    hlt
.no_xga:
    lea rsi, [rel no_xga_str]
    call print_string
    cli
    hlt
.no_bootservices:
    lea rsi, [rel bootservices_fail]
    call print_string
    cli
    hlt
.root_failed:
    lea rsi, [rel root_failed_str]
    call print_string
    cli
    hlt
.no_file_found:
    lea rsi, [rel file_not_found]
    call print_string
    cli
    hlt
.mmap_fail:
    lea rsi, [rel mmap_error]
    call print_string
    cli
    hlt
.exit_fail:
    lea rsi, [rel exit_error]
    call print_string
    cli
    hlt
print_string:
    ;msg in ESI
    mov rax, [rel system_table]
    mov rbx, [rax+64]           ;ConOut
    mov rcx, rbx
    mov rdx, rsi

    sub rsp, 40
    call qword [rbx+8]
    add rsp, 40

    ret

print_char:
    lea rsi, [rel char]
    mov [rsi], ax
    call print_string
    ret
print_dec:
    mov rbp, rsp
    mov rbx, [rel system_table]
    sub rsp, 64

    lea rdi, [rbp-2]
    mov word [rdi], 0
    mov r8, 10
.loop:
    xor rdx, rdx
    div r8
    add dx, '0'
    sub rdi, 2
    mov [rdi], dx
    test rax, rax
    jnz .loop

    mov r12, [rbx+64]
    mov rcx, r12    ;Arg 1
    mov rdx, rdi    ;Arg 2
    call [r12+8]    ;OutputString

    mov rsp, rbp
    ret

parse_cfg_file:
    ;RSI = address of file
    ;returns the number, given in boot.cfg in AH

    lodsb
    cmp al, 0x20
    je parse_cfg_file
    cmp al, 0
    je .done
    cmp al, '#'
    je .skip_comment

    sub al, 0x30
    mov ah, al
    jmp parse_cfg_file
.done:
    ret
.skip_comment:
    lodsb
    cmp al, 0x0a
    je parse_cfg_file
    cmp al, 0
    je .done
    jmp .skip_comment

get_vendor:
    mov rax, [rel system_table]
    mov rsi, [rax+24]           ;FirmwareVendor
    lea rdi, [rel firmware_vendor]
    mov rcx, 16
    rep movsb
    mov ecx, [rax+32]           ;FirmwareRevision

    mov rax,[rel system_table]
    mov rcx,[rax+64]       ; ConOut

    lea rdx,[rel firmware_vendor]

    sub rsp,40
    call qword [rcx+8]     ; OutputString
    add rsp,40

    mov rax,[rel system_table]
    mov rcx,[rax+64]       ; ConOut

    lea rdx,[rel newline]

    sub rsp,40
    call qword [rcx+8]     ; OutputString
    add rsp,40

    ret


exit_boot:
    mov dword [rel kernel_packet+12], 20

    mov rdx, [rel frame_buffer]     ;assumes that the frame buffer is a 32bit address
    lea rsi, [rel firmware_vendor]
    mov [rel kernel_packet], rsi
    mov ecx, [rel bpp]
    mov ebx, [rel width]
    mov edi, [rel height]
    lea rsi, [rel kernel_packet]
    mov rax, 0x8000+250
    jmp rax


load_drivers:
    ;open directory /DRIVERS/
    mov rcx, [rel root]
    lea rdx, [rel drivers_dir]
    lea r8, [rel drivers_dir_name]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jnz .dir_failed

    mov rcx, [rel drivers_dir]
    lea rdx, [rel ohci_file]
    lea r8, [rel ohci_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .ohci_get_size
    mov rsi, OHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .uhci

.ohci_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel ohci_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .ohci_load

    mov rsi, OHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .uhci
.ohci_load:
    mov rax, [rel file_info+8]
    mov [rel ohci_size], rax

    mov rcx, [rel ohci_file]
    lea rdx, [rel ohci_size]
    mov r8, OHCI_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.uhci:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel uhci_file]
    lea r8, [rel uhci_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .uhci_get_size
    mov rsi, UHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .ehci

.uhci_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel uhci_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .uhci_load

    mov rsi, UHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .ehci
.uhci_load:
    mov rax, [rel file_info+8]
    mov [rel uhci_size], rax

    mov rcx, [rel uhci_file]
    lea rdx, [rel uhci_size]
    mov r8, UHCI_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.ehci:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel ehci_file]
    lea r8, [rel ehci_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .ehci_get_size
    mov rsi, EHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .xhci

.ehci_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel ehci_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .ehci_load

    mov rsi, EHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .xhci
.ehci_load:
    mov rax, [rel file_info+8]
    mov [rel ehci_size], rax

    mov rcx, [rel ehci_file]
    lea rdx, [rel ehci_size]
    mov r8, EHCI_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.xhci:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel xhci_file]
    lea r8, [rel xhci_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .xhci_get_size
    mov rsi, XHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .nvme

.xhci_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel xhci_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .xhci_load

    mov rsi, XHCI_ADDR
    mov dword [rsi], 'FAIL'
    jmp .nvme
.xhci_load:
    mov rax, [rel file_info+8]
    mov [rel xhci_size], rax

    mov rcx, [rel xhci_file]
    lea rdx, [rel xhci_size]
    mov r8, XHCI_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.nvme:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel nvme_file]
    lea r8, [rel nvme_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .nvme_get_size
    mov rsi, NVME_ADDR
    mov dword [rsi], 'FAIL'
    jmp .fdc

.nvme_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel nvme_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .nvme_load

    mov rsi, NVME_ADDR
    mov dword [rsi], 'FAIL'
    jmp .fdc
.nvme_load:
    mov rax, [rel file_info+8]
    mov [rel nvme_size], rax

    mov rcx, [rel nvme_file]
    lea rdx, [rel nvme_size]
    mov r8, NVME_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.fdc:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel fdc_file]
    lea r8, [rel fdc_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .fdc_get_size
    mov rsi, FDC_ADDR
    mov dword [rsi], 'FAIL'
    jmp .sdc

.fdc_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel fdc_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .fdc_load

    mov rsi, FDC_ADDR
    mov dword [rsi], 'FAIL'
    jmp .sdc
.fdc_load:
    mov rax, [rel file_info+8]
    mov [rel fdc_size], rax

    mov rcx, [rel fdc_file]
    lea rdx, [rel fdc_size]
    mov r8, FDC_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.sdc:
    mov rcx, [rel drivers_dir]
    lea rdx, [rel sdc_file]
    lea r8, [rel sdc_sys]
    mov r9, 1

    sub rsp, 56
    mov qword [rsp+32], 0
    call qword [rcx+8]
    add rsp, 56

    test rax, rax
    jz .sdc_get_size
    mov rsi, SDC_ADDR
    mov dword [rsi], 'FAIL'
    jmp .done

.sdc_get_size:
    ;get file size
    mov qword [rel info_size], 256

    mov rcx, [rel sdc_file]
    lea rdx, [rel file_info_guid]
    lea r8, [rel info_size]
    lea r9, [rel file_info]

    sub rsp, 40
    call qword [rcx+64]
    add rsp, 40

    test rax, rax
    jz .sdc_load

    mov rsi, SDC_ADDR
    mov dword [rsi], 'FAIL'
    jmp .done
.sdc_load:
    mov rax, [rel file_info+8]
    mov [rel sdc_size], rax

    mov rcx, [rel sdc_file]
    lea rdx, [rel sdc_size]
    mov r8, SDC_ADDR

    sub rsp, 40
    call qword [rcx+32]
    add rsp, 40
.done:
    ret

.dir_failed:
    lea esi, [rel dir_err]
    push rax
    call print_string
    pop rax
    cli
.loop:
    hlt
    jmp .loop
;----data---- 
section .data
image_handle: dq 0
system_table: dq 0

gop_guid:
    dd 0x9042a9de
    dw 0x23dc
    dw 0x4a38
    db 0x96,0xfb,0x7a,0xde,0xd0,0x80,0x51,0x6a

sfs_guid:
    dd 0x0964e5b22
    dw 0x6459
    dw 0x11d2
    db 0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b

file_info_guid:
    dd 0x09576e92
    dw 0x6d3f
    dw 0x11d2
    db 0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b

loaded_image_guid:
    dd 0x5b1b31a1
    dw 0x9562
    dw 0x11d2
    db 0x8e, 0x3f, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b

device_path_guid:
    dd 0x09576e91
    dw 0x6d3f
    dw 0x11d2
    db 0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b

simple_fs: dq 0
root: dq 0

gop: dq 0
recom_frame_buffer: dq 0
recom_pitch: dd 0
recom_width: dd 0
recom_height: dd 0

info_ptr: dq 0
info_size: dq 0

frame_buffer: dq 0
width: dd 0
height: dd 0
bpp: dd 0
SYSTEM_TABLE.BOOT_SERVICES      equ 96
BOOT_SERVICES.LOCATE_PROTOCOL   equ 320
BOOT_SERVICES.EXIT_BOOT_SERVICES    equ 232
BOOT_SERVICES.GET_MEMORY_MAP    equ 56
GOP_SETMODE     equ 8
GOP_GETMODE     equ 24

GOP_MODE_INFORMATION.WIDTH      equ 4
GOP_MODE_INFORMATION.HEIGHT     equ 8
GOP_MODE_INFORMATION.PITCH      equ 32

firmware_vendor: times 16 db 0
firmware_revision: dd 0
graphic_success: dw 'G','r','a','p','h','i','c',' ','M','o','d','e',' ','f','o','u','n','d', 0x0d, 0x0a, 0
no_xga_str: dw 'N','o',' ','X','G','A',' ','f','o','u','n','d',0
dir_err: dw 'D','r','i','v','e','r',' ','d','i','r','e','c','t','o','r','y',' ','n','o','t',' ','f','o','u','n','d', 0x0d, 0x0a, 0

xmode_bin: dw '\','X','M','O','D','E','.','B','I','N', 0
xmode_file: dq 0
xmode_size: dq 0
drivers_dir_name: dw '\','D','R','I','V','E','R','S', 0
ohci_sys: dw 'O','H','C','I','.','S','Y','S', 0
uhci_sys: dw 'U','H','C','I','.','S','Y','S', 0
ehci_sys: dw 'E','H','C','I','.','S','Y','S', 0
xhci_sys: dw 'X','H','C','I','.','S','Y','S', 0
nvme_sys: dw 'N','V','M','E','.','S','Y','S', 0
fdc_sys: dw 'F','D','C','.','S','Y','S', 0
sdc_sys: dw 'S','D','C','.','S','Y','S', 0

cfg_bin: dw '\','X','C','O','N','F','I','G','S','\','B','O','O','T','.','C','F','G', 0
cfg_file: dq 0
cfg_size: dq 0
bootservices_fail: dw 'N','o',' ','B','o','o','t',' ','S','e','r','v','i', 'c','e','s',' ','f','o','u','n','d',0
root_failed_str: dw 'F','a','i','l','e','d',' ','t','o',' ','o','p','e','n',' ','r','o','o','t',0
file_not_found: dw 'K','e','r','n','e','l',' ','n','o','t',' ','f','o','u','n','d',0
kernel_found_str: dw 'K','e','r','n','e','l',' ','l','o','a','d','e','d', 0
mmap_error: dw 'M','m','a','p',' ','n','o','t',' ','f','o','u','n','d',0
exit_error: dw 'E','r','r','o','r',' ','w','h','i','l','e',' ','j','u','m','p','i','n','g',' ','t','o',' ','k','e','r','n','e','l', 0
resolution_str: dw 'C','h','o','o','s','e',' ','a',' ','r','e','s','o','l','u','t','i','o','n', 0x0a, 0x0d, 0
newline: dw 0x0d, 0x0a, 0

mmap_size dq 65536
mmap      dq 0x100000

map_key         dq 0
desc_size       dq 0
desc_ver        dd 0

MEM_MAP_ADDR            equ 0x75000

keymap:
    db 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36
    db 37, 38, 39, 40, 41, 42, 43, 44, 45, 46
    db 47, 48, 49, 50, 51,

    db 0, 1,  2,  3,  4,  5,  6,  7,  8,  9, 10
    db 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
    db 21, 22, 23, 24, 25,

OHCI_ADDR       equ 0x61000
UHCI_ADDR       equ 0x64000
EHCI_ADDR       equ 0x67000
XHCI_ADDR       equ 0x69000
NVME_ADDR       equ 0x6d000
FDC_ADDR        equ 0x70000
SDC_ADDR        equ 0x72000

section .bss
kernel_packet:
    resq 1        ;pointer to buffer with firmware vendor
    ;memory map
    resd 1        ;memory map entries
    resd 1        ;size of one entry

    ;video output
    resd 1        ;frame buffer
    resd 1        ;width
    resd 1        ;height
    resd 1        ;bytes per pixel

loaded_image_ptr: resq 1
device_path: resq 1

drivers_dir: resq 1
drivers_file: resq 1
drivers_size: resq 1

ohci_file: resq 1
ohci_size: resq 1

uhci_file: resq 1
uhci_size: resq 1

ehci_file: resq 1
ehci_size: resq 1

xhci_file: resq 1
xhci_size: resq 1

nvme_file: resq 1
nvme_size: resq 1

fdc_file: resq 1
fdc_size: resq 1

sdc_file: resq 1
sdc_size: resq 1

char: resd 1
res_buffer: resd 64*8
efi_input_key: resd 1    ;WORD: special keys, WORD: char
event_ptr: resq 1        ;pointer to WaitForKey event
event_index: resq 1
file_info: resb 80