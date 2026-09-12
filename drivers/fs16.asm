;=====================================================================
;INT 0x33
;AH = 0x00: get file information                            input: EDI = pointer to directory, ESI = filename               output: ECX = size, EAX = flags, EBX = first cluster
;AH = 0x01: get file list of the current directory          input: EDI = buffer for file list, ESI = pointer to directory   output: filled buffer with file names
; X AH = 0x02: read a file into memory                      input: EDI = buffer in memory, ESI = filename                   output: no CF if successful, length of file in ECX
; X AH = 0x03: write a file to disk                         input: ESI = filename, ECX = filesize (bytes), EDI = buffer     output: CF if error
; X AH = 0x04: rename a file                                input: ESI = old filename, EDI = new filename                   output: CF if error
; X AH = 0x05: delete a file                                input: ESI = filename                                           output: CF if error
;AH = 0x06: copy file from one dir to another dir           input: ESI = path to file, EDI = path to destination directory where to copy    output: CF if error
;AH = 0x07: copy file to another disk
; X AH = 0x08: load program into memory                     input: ESI = program name, EDI = address in memory              output: CF if error
;AH = 0x09: format a drive / partition with FAT16           input: AL  = drive number, BL = partition number (0-3)          output: CF if error

;AH = 0x0A: load file from not-root directory               input: ESI = file name, EDI = address where to load, EDX = address from where to load (directory), BL = drive number       output: CF if error
;AH = 0x0B: save file from not-root directory               input: ESI = file name, EDI = where to save (address of loaded directory), EDX = address of file, ECX = file size, BL = drive number       output: CF if error
;AH = 0x0C: rename file in not-root directory               input: ESI = old file name, EDI = new file name, EDX = pointer to directory, BL = drive number      output: CF if error
;AH = 0x0D: delete file from not-root directory             input: ESI = file name, EDI = pointer to directory, BL = drive number   output: CF if error
;AH = 0x20: change drive - load MBR of new drive and change parameters      input: ESI = pointer to argument with drive number and partition (eg. 1.1 / 2.3), output: CL = drive number
; Drive Numbers:
;     0 = First Floppy
;     1 = Second Floppy
;     2 = First HDD / SSD / USB Flash Drive
;     3 = Second HDD / SSD / USB Flash Drive
;     ...
;     128 = CD
;     0xFF = Boot Drive
; Size of directories are limited to 4KiB
;---------------------------------------------------------------------
;Copyright (C) 2026 Technodon
;=====================================================================

cluster_to_sec:
;FirstSectorOfCluster = (cluster - 2) * BPB_SectorsPerCluster + DataStartSector
    sub ax, 2
    xor cx, cx
    mov cl, [sec_per_cluster]
    mul cx
    add ax, [data_start]
    ret

fs16_write_root:
    pusha

    xor dx, dx
    mov ax, [root_sectors]
    movzx bx, byte [sec_per_cluster]
    div bx
    movzx edx, ax
    movzx ecx, word [root_start]
    mov esi, root_addr
.loop:
    movzx ebx, byte [sec_per_cluster]
    mov ah, 0x03
    int 0x32
    jc .error

    push edx
    mov eax, 512
    movzx edx, byte [sec_per_cluster]
    imul eax, edx
    add esi, eax
    pop edx

    movzx eax, byte [sec_per_cluster]
    add ecx, eax
    dec edx
    jnz .loop

    popa
    clc
    ret
.error:
    popa
    stc
    ret
fs16_write_fat:
    pusha
    xor dx, dx
    mov ax, [fat_size]
    xor ebx, ebx
    movzx bx, byte [sec_per_cluster]
    div bx
    movzx edx, ax

    movzx ecx, word [reserved_sectors]
    mov esi, fat_addr
.loop:
    movzx ebx, byte [sec_per_cluster]
    mov ah, 0x03
    int 0x32
    jc .error

    push edx
    xor eax, eax
    mov eax, 512
    movzx edx, byte [sec_per_cluster]
    imul eax, edx
    add esi, eax
    pop edx

    movzx ax, byte [sec_per_cluster]
    add cx, ax
    dec edx
    jnz .loop

    popa
    clc
    ret
.error:
    popa
    stc
    ret



fs16_handler:
    cmp ah, 0
    je fs16_get_file_information
    cmp ah, 0x01
    je fs16_get_file_list
    ; cmp ah, 0x02
    ; je fs16_read_file
    ; cmp ah, 0x03
    ; je fs16_write_file
    ; cmp ah, 0x04
    ; je fs16_rename_file
    ; cmp ah, 0x05
    ; je fs16_delete_file
    cmp ah, 0x06
    je fs16_copy_file
    cmp ah, 0x08
    je fs16_load_program
    cmp ah, 0x09
    je fs16_format_drive
    cmp ah, 0x0a
    je fs16_load_file
    cmp ah, 0x0b
    je fs16_write_file2
    cmp ah, 0x0c
    je fs16_rename_file2
    cmp ah, 0x0d
    je fs16_delete_file2
    cmp ah, 0x20
    je fs16_change_drive
    or dword [esp+8], 1
    iret
 
fs16_get_file_list:
    pusha
.loop:
    mov al, [esi]
    cmp al, 0x00
    je .done
    cmp al, 0xe5
    je .free_entry

    mov ecx, 8
    push esi
    rep movsb
    mov byte [edi], '.'
    inc edi

    mov ecx, 3
    rep movsb
    pop esi

    cmp byte [esi+0xb], 0x10
    je .dir
    cmp byte [esi+0xb], 0x24
    je .system
    cmp byte [esi+0xb], 0x08
    je .vol_label

    mov al, '#'
    stosb
    jmp .continue
.system:
    mov al, '%'
    stosb
    mov al, 0x0a
    stosb
    jmp .free_entry
.vol_label:
    mov al, 0x08
    stosb
    mov al, 0x0a
    stosb
    jmp .free_entry
.dir:
    mov al, '*'
    stosb
.continue:
    mov eax, [esi+0x1c]
    stosd

    mov al, 0x0a
    stosb
.free_entry:
    add esi, 32
    jmp .loop
.done:
    mov byte [edi], '$'
    popa
    iret


;=======================read a file into memory===============================
fs16_read_file:
    pusha
    push edi
    mov edi, root_addr
    mov dx, [root_entries]
.loop:
    mov ecx, 11
    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32
    dec dx
    jnz .loop

    pop edi
    popa
    or dword [esp+8], 1         ;set carry flag
    iret

.found:
    mov ax, [edi+0x1a]
    mov [cluster16], ax
    mov ecx, [edi+0x1c]         ;file size
    pop edi
    mov [esp+24], ecx           ;save ECX to the stack
.load:
    mov ax, [cluster16]
    call cluster_to_sec
    movzx ecx, ax

    mov ah, 0x02
    movzx ebx, byte [sec_per_cluster]
    int 0x32

    mov eax, 512
    mul ebx
    add edi, eax

    mov bx, [cluster16]
    shl bx, 1
    mov ax, [fat_addr+bx]
    mov [cluster16], ax
    cmp ax, 2
    jb .invalid_cluster
    cmp ax, 0xfff8
    jb .load
    popa
    and dword [esp+8], 0xfffffffe
    iret
.invalid_cluster:
    popa
    or dword [esp+8], 1         ;set carry flag
    iret

;======================write file======================================
fs16_write_file:
    pusha
    push edi
    mov [file_size16], ecx
    mov [argument], esi
    mov edi, root_addr
    mov dx, [root_entries]
.search_loop:
    mov al, [edi]
    cmp al, 0x00
    je .free_entry
    cmp al, 0xe5
    je .free_entry

    add edi, 32
    dec dx
    jnz .search_loop

    pop edi
    popa
    or dword [esp+8], 1
    iret

.free_entry:
    mov eax, edi
    pop edi
    mov ecx, [file_size16]
    push eax        ;save root adress

    mov eax, 512
    movzx ebx, byte [sec_per_cluster]
    imul eax, ebx

    add ecx, eax
    dec ecx

    mov ebx, ecx
    mov ecx, eax
    mov eax, ebx

    xor edx, edx
    div ecx
    mov ecx, eax

    mov ebx, 2       ;cluster 0 and 1 are reserved
    push edi         ;save buffer for later
    mov edx, [fat_size]
    mov eax, 512
    imul edx, eax    ;set limit
    shr edx, 1
.first_cluster:
    mov edi, fat_addr
    mov eax, ebx
    shl bx, 1
    cmp [edi+ebx], 0
    je .found_first_cluster
    mov ebx, eax
    inc ebx
    dec edx
    jnz .first_cluster
.found_first_cluster:
    mov [first_cluster16], ax
    mov [prev_cluster16], ax
    dec ecx
    jz .one_cluster
    inc ecx
.loop:
    mov bx, ax
    shl bx, 1
    cmp [edi+ebx], 0
    je .next_cluster
    inc ax
    dec edx
    jnz .loop
    jmp .error
.next_cluster:
    mov bx, [prev_cluster16]
    shl bx, 1
    mov [edi+ebx], ax
    mov [prev_cluster16], ax

    pop edi
    push eax
    push ecx
    push ebx
    call cluster_to_sec
    mov ecx, eax
    movzx ebx, byte [sec_per_cluster]
    mov esi, edi
    mov ah, 0x03
    int 0x32

    imul ebx, 512
    add edi, ebx

    pop ebx
    pop ecx
    pop eax

    push edi
    mov edi, fat_addr
    jc .error
    inc ax
    dec ecx
    jnz .loop
    jmp .last_cluster
.one_cluster:
    mov word [edi+ebx], 0xfff8
    movzx eax, word [first_cluster16]
    call cluster_to_sec
    movzx ecx, ax
    movzx ebx, byte [sec_per_cluster]
    pop edi
    mov esi, edi
    mov ah, 0x03
    int 0x32
    jnc .done
.error:
    pop eax
    popa
    or dword [esp+8], 1
    iret
.last_cluster:
    mov bx, [prev_cluster16]
    shl bx, 1
    mov word [fat_addr+bx], 0xfff8
    pop edi
.done:
    mov esi, [argument]
    pop eax
    mov edi, eax
    call fs16_write_fat

    mov ecx, 11
    push edi
    rep movsb
    pop edi

    mov byte [edi+0x0b], 0x20       ;archive
    mov ax, [first_cluster16]
    mov [edi+0x1a], ax
    mov ecx, [file_size16]
    mov [edi+0x1c], ecx
    call fs16_write_root
    popa
    and dword [esp+8], 0xfffffffe
    iret
;======================delete a file===================================
fs16_delete_file:
    pusha
    mov edi, root_addr
    mov dx, [root_entries]
.search_loop:
    mov ecx, 11
    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32
    dec dx
    jnz .search_loop

    popa
    or dword [esp+8], 1
    iret

.found:
    mov ax, [edi+0x1a]
    mov [cluster16], ax
    mov byte [edi], 0xe5        ;mark file as deleted

.del_loop:
    shl ax, 1
    mov bx, ax
    mov ax, [fat_addr+bx]
    mov word [fat_addr+bx], 0x0000
    cmp ax, 0xfff8
    jb .del_loop

    call fs16_write_fat
    jc .error
    call fs16_write_root
    jc .error

    popa
    and dword [esp+8], 0xfffffffe
    iret

.error:
    popa
    or dword [esp+8], 1
    iret

;==========================rename a file===========================
fs16_rename_file:
    pusha
    push edi
    mov edi, root_addr
    mov dx, [root_entries]
.search_loop:
    mov ecx, 11
    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32
    dec dx
    jnz .search_loop

    pop edi
    popa
    or dword [esp+8], 1
    iret

.found:
    mov edx, edi
    pop edi
    mov esi, edi
    mov edi, edx
    mov ecx, 11
    rep movsb

    call fs16_write_root

    popa
    and dword [esp+8], 0xfffffffe
    iret

;==========================copy file===============================
fs16_copy_file:
    pusha
    push edi
    mov edi, root_addr
    mov dx, [root_entries]
.search_loop:
    mov ecx, 11
    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32
    dec dx
    jnz .search_loop

    pop edi
    popa
    or dword [esp+8], 1
    iret
.found:
    mov esi, edi
    mov edi, file_buffer
    mov ecx, 32
.loop:
    lodsb
    stosb
    dec ecx
    jnz .loop

    ;load the directory...
    pop edi
    popa
    and dword [esp+8], 0xfffffffe
    iret

;============load program=====================
fs16_load_program:
    pusha
    push edi
    mov edi, root_addr
    mov dx, [root_entries]
.search_loop:
    mov ecx, 11
    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32
    dec dx
    jnz .search_loop

    pop edi
    popa
    or dword [esp+8], 1
    iret
.found:
    mov ax, [edi+0x1a]
    mov [cluster16], ax

    pop edi
.loop:
    movzx eax, word [cluster16]
    call cluster_to_sec
    mov ecx, eax
    movzx ebx, byte [sec_per_cluster]
    mov ah, 0x02
    int 0x32
    jc .error

    mov eax, 512
    imul eax, ebx
    add edi, eax

    mov ax, [cluster16]
    shl ax, 1
    movzx ebx, ax
    mov eax, [fat_addr+ebx]
    mov [cluster16], ax

    cmp ax, 2
    jb .error
    cmp ax, 0xfff8
    jb .loop

    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret


;############################################################
;################## SWITCH CURRENT DRIVE ####################
;############################################################

fs16_change_drive:
    pusha
    mov edx, [esi]  ;get drive number
    movzx ebp, dl

    mov dh, 0x0b    ;No extended LBA
    mov eax, 1      ;read 1 sector
    xor ecx, ecx    ;LBA 0
    mov edi, 0x7c00
    call read_drive
    xor ah, ah
    jc .error

    ; mov esi, dword [0x7c00]
    ; cli
    ; hlt

    ; cmp byte [esi+1], '.'
    ; je .switch_partition

.get_fs:
    mov ah, 0x01
    mov esi, .fat16_str
    mov edi, 0x7c00+54
    mov ecx, 8
    repe cmpsb
    jne .error

    mov edi, 0x7c00

    mov ax, [edi+11]
    mov [bytes_per_sec], ax
    mov al, [edi+13]
    mov [sec_per_cluster], al
    mov ax, [edi+14]
    mov [reserved_sectors], ax
    mov al, [edi+16]
    mov [fat_num], al
    mov ax, [edi+17]
    mov [root_entries], ax
    mov ax, [edi+19]
    mov [total_sectors], ax
    mov ax, [edi+22]
    mov [fat_size], ax
    mov eax, [edi+28]
    mov [hidden_sectors], eax
    mov eax, [edi+32]
    mov [total_sectors32], eax
    
    push ecx
    push eax
    push edi
    mov ecx, 0x3000/4
    mov edi, 0x4000
    xor eax, eax
    rep stosd

    pop edi
    pop eax
    pop ecx

    movzx eax, word [fat_size]
    cmp eax, 25
    jbe .next
    mov eax, 25     ;load only the first 25 sectors of the FAT
.next:
    movzx ecx, word [reserved_sectors]
    add ecx, [hidden_sectors]
    mov edx, ebp
    mov dh, 0x0b
    mov edi, 0x4000
    call read_drive
    xor ah, ah
    jc .error
    
    xor edx, edx
    movzx eax, word [root_entries]
    imul eax, 32
    movzx ebx, word [bytes_per_sec]
    div ebx
    mov [root_sectors], ax

    movzx ebx, word [reserved_sectors]
    movzx ecx, byte [fat_num]
    imul cx, [fat_size]
    add ecx, ebx
    add ecx, [hidden_sectors]
    mov [root_start], ecx

    push ecx
    push eax
    push edi
    mov ecx, 0x4000/4
    mov edi, root_addr
    xor eax, eax
    rep stosd

    pop edi
    pop eax
    pop ecx

    mov edi, root_addr
    mov edx, ebp
    mov dh, 0x0b
    call read_drive
    xor ah, ah
    jc .error

    mov eax, [root_start]
    movzx ebx, word [root_sectors]
    add eax, ebx
    mov [data_start], eax

    popa
    and dword [esp+8], 0xfffffffe
    iret

.error:
    ;AH = 0x00: Disk Error
    ;AH = 0x01: Not FAT16 formatted
    ;AH = 0x02: not an active partition
    cli
    mov [.error_num], ah
    popa
    or dword [esp+8], 1
    mov ah, [.error_num]
    xor al, al
    sti
    iret
.fat16_str: db "FAT16   "
.drive_number: db 0
.error_num: db 0

.switch_partition:
    mov al, [esi+2]
    sub al, 0x30

    cmp al, 4
    ja .error

    mov edi, 0x7c00+446
    xor ah, ah
    imul ax, 16
    movzx ebx, ax
    add edi, ebx

    mov ah, 0x02
    cmp byte [edi], 0x80
    jne .error

    mov eax, [edi+8]
    mov [hidden_sectors], eax

    mov ecx, eax
    mov dh, 0x0b
    mov dl, [.drive_number]
    mov eax, 1
    mov edi, 0x7c00
    call read_drive
    xor ah, ah
    jc .error

    jmp .get_fs

fs16_load_file:
    pusha
    push edi
    mov edi, edx
    mov dx, [subdir_entries]

    cmp bl, 0xff
    je .boot_drive
    movzx ebp, bl
    jmp .loop
.boot_drive:
    mov bl, [boot_drive]
    movzx ebp, bl
.loop:
    ; mov al, [edi]
    ; cmp al, 0
    ; je .no_file

    push edi
    push esi
    mov ecx, 11
    repe cmpsb
    pop esi
    pop edi
    je .found

    add edi, 32
    dec dx
    jnz .loop

; .no_file
    pop edi
    popa
    or dword [esp+8], 1
    iret

.found:
    pop esi
    mov ax, [edi+0x1a]
    test dword [edi+0xb], 0x08
    jnz .error
    ; test dword [edi+0xb], 0x10
    ; jnz .error

    mov dx, ax
    mov edi, esi
.load_loop:
    movzx eax, dx
    push edx
    call cluster_to_sec

    movzx ecx, ax
    add ecx, dword [hidden_sectors]
    movzx eax, byte [sec_per_cluster]
    mov edx, ebp
    mov dh, 0x0b
    call read_drive
    pop edx
    jc .error

    movzx ebx, word [bytes_per_sec]
    movzx eax, byte [sec_per_cluster]
    imul eax, ebx
    add edi, eax


    movzx eax, dx
    shl eax, 1
    mov esi, fat_addr
    add esi, eax
    mov ax, [esi]
    mov dx, ax

    cmp ax, 0
    je .error

    cmp ax, 0xfff8
    jb .load_loop

    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret

.drive_number: db 0





;############################################################
;################### FORMAT DRIVE FUNCTION ##################
;############################################################


fs16_format_drive:
    pusha
    ;allocate heap

    ;load MBR to set partition and BPB
    popa
    and dword [esp+8], 0xfffffffe
    iret




fs16_get_file_information:
    pusha
.loop:
    mov ecx, 11
    mov al, [edi]
    cmp al, 0
    je .error

    push esi
    push edi
    repe cmpsb
    pop edi
    pop esi
    je .found

    add edi, 32

    jmp .loop
.error:
    popa
    or dword [esp+8], 1
    iret
.found:
    mov [.tmp], edi
    popa
    mov edi, [.tmp]
    mov ecx, [edi+0x1c]
    movzx eax, byte [edi+0x0b]
    movzx ebx, word [edi+0x1a]
    and dword [esp+8], 0xfffffffe
    iret
.tmp: dd 0


;############################################################
;#################### WRITE FILE TO DISK ####################
;############################################################

fs16_write_file2:
    ;ESI = pointer to 8.3 format file name (for example "TEST    TXT")
    ;EDI = where to save (address of loaded directory) (0x00000000 = root dir)
    ;EDX = address of file
    ;ECX = file size
    ;BL = drive number
    cli
    pusha
    mov [.drive_number], bl
    mov [.file_size], ecx
    mov [.dir], edi
    mov ebp, 0x1000/32
    cmp edi, 0
    jne .loop1

    movzx ebp, word [root_entries]
.loop1:
    mov al, [edi]
    cmp al, 0
    je .free_entry
    cmp al, 0xe5
    je .free_entry

    add edi, 32
    dec ebp
    jnz .loop1
    jmp .error
.free_entry:
    ;EDI points now to free directory entry
    mov eax, 512
    movzx ebx, byte [sec_per_cluster]
    imul eax, ebx

    add ecx, eax
    dec ecx

    mov ebx, ecx
    mov ecx, eax
    mov eax, ebx

    mov ebp, esi
    mov esi, edx

    xor edx, edx
    div ecx
    mov ecx, eax

    mov [.dir_entry], edi

    mov ebx, 2  ;cluster 0 and 1 are reserved
    mov edx, [fat_size]
    mov eax, 512
    imul edx, eax    ;set limit
    shr edx, 1

.first_cluster:
    mov edi, fat_addr
    mov eax, ebx
    shl bx, 1
    cmp [edi+ebx], 0
    je .found_first_cluster
    mov ebx, eax
    inc ebx
    dec edx
    jnz .first_cluster
    jmp .error

.found_first_cluster:
    mov [.first_cluster16], ax
    mov [.prev_cluster16], ax
    dec ecx
    jz .one_cluster
    inc ecx
.loop:
    mov bx, ax
    shl bx, 1
    cmp [edi+ebx], 0
    je .next_cluster
    inc ax
    dec edx
    jnz .loop
    jmp .error
.next_cluster:
    mov bx, [.prev_cluster16]
    shl bx, 1
    mov [edi+ebx], ax
    mov [.prev_cluster16], ax

    push eax
    push ecx
    push ebx
    push edx

    call cluster_to_sec
    mov ecx, eax
    clc
    add ecx, dword [hidden_sectors]
    jc .error_write
    movzx eax, byte [sec_per_cluster]
    mov dh, 0x0b
    mov dl, [.drive_number]
    call write_drive
    jc .error_write

    imul eax, 512
    add esi, eax

    pop edx
    pop ebx
    pop ecx
    pop eax

    mov edi, fat_addr
    inc ax
    dec ecx
    jnz .loop
    jmp .last_cluster
.one_cluster:
    mov word [edi+ebx], 0xfff8
    movzx eax, word [.first_cluster16]
    call cluster_to_sec
    movzx ecx, ax
    clc
    add ecx, dword [hidden_sectors]
    jc .error
    movzx eax, byte [sec_per_cluster]
    mov dl, [.drive_number]
    mov dh, 0x0b
    call write_drive
    jc .error
    jmp .done
.error_write:
    pop edx
    pop ebx
    pop ecx
    pop eax
    popa
    or dword [esp+8], 1
    iret
.last_cluster:
    mov bx, [.prev_cluster16]
    shl bx, 1
    mov word [fat_addr+bx], 0xfff8

.done:
    mov esi, ebp
    mov edi, [.dir_entry]
    mov ecx, 11
    push edi
    rep movsb
    pop edi

    mov byte [edi+0x0b], 0x20       ;archive
    mov ax, [.first_cluster16]
    mov [edi+0x1a], ax
    mov ecx, [.file_size]
    mov [edi+0x1c], ecx
    
    cmp dword [.dir], 0
    jne .skip2

    mov ebp, [.drive_number]
    call fs16_write_root2
    jc .error
    call fs16_write_fat2
    jc .error
    popa
    and dword [esp+8], 0xfffffffe
    iret
.skip2:
    mov esi, [.dir]
    mov edi, .dot_entry
    mov edx, 0x1000/32
.loop2:
    mov ecx, 11
    push edi
    push esi
    rep cmpsb
    pop esi
    pop edi
    je .found_dot

    add esi, 32
    dec edx
    jnz .loop2
    jmp .error
.found_dot:
    movzx eax, word [esi+0x1a]
    mov ebp, eax
    call cluster_to_sec
    clc
    add eax, dword [hidden_sectors]
    jc .error
    mov ecx, eax
    movzx eax, byte [sec_per_cluster]
    mov esi, [.dir]
    mov dl, [.drive_number]
    mov dh, 0x0b
    call write_drive
    jc .error

.loop3:
    mov ebx, ebp    ;cluster number
    mov edi, fat_addr
    shl ebx, 1
    movzx eax, word [edi+ebx]
    cmp ax, 0xfff8
    jae .done2

    mov ebp, eax

    push eax
    movzx eax, word [bytes_per_sec]
    movzx ebx, byte [sec_per_cluster]
    xor edx, edx
    mul ebx
    add esi, eax
    pop eax

    call cluster_to_sec
    mov ecx, eax
    clc
    add ecx, dword [hidden_sectors]
    jc .error
    movzx eax, byte [sec_per_cluster]
    mov dl, [.drive_number]
    mov dh, 0x0b
    call write_drive
    jc .error
    jmp .loop3

.done2:
    mov ebp, [.drive_number]
    call fs16_write_fat2
    jc .error

    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret

.file_size: dd 0
.dir: dd 0
.drive_number: db 0
.dir_entry: dd 0
.first_cluster16: dw 0
.prev_cluster16: dw 0
.dot_entry: db '.          '

;############################################################
;###################### DELETE FILE #########################
;############################################################

fs16_delete_file2:
    ;EDI = pointer to directory
    ;ESI = filename
    ;BL = drive number
    cli
    pusha
    movzx ebp, bl
    push edi
    mov dword [.dir], edi
.loop:
    mov al, [edi]
    cmp al, 0
    je .no_file

    mov ecx, 11
    push edi
    push esi
    rep cmpsb
    pop esi
    pop edi
    je .found_file

    add edi, 32
    jmp .loop

.no_file:
    pop edi
    jmp .error

.found_file:
    pop ebx
    test byte [edi+0x0b], (1 << 0)      ;read-only
    jnz .error
    test byte [edi+0x0b], (1 << 2)      ;system
    jnz .error
    test byte [edi+0x0b], (1 << 4)      ;directory
    jnz .directory

.del:
    mov byte [edi], 0xe5
    movzx eax, word [edi+0x1a]
    mov edi, ebx
.del_loop:
    mov bx, ax
    shl bx, 1
    mov ax, [fat_addr+bx]
    mov word [fat_addr+bx], 0x0000
    cmp ax, 0xfff8
    jb .del_loop

    call fs16_write_fat2
    jc .error
    cmp edi, root_addr
    jne .skip

    call fs16_write_root2
    jc .error
    jmp .done

.skip:
    mov eax, ebp
    mov [.drive_number], al
    mov esi, edi
    mov [.dir], esi
    mov edi, fs16_write_file2.dot_entry
    mov edx, 0x1000/32
.loop2:
    mov ecx, 11
    push edi
    push esi
    rep cmpsb
    pop esi
    pop edi
    je .found_dot

    add esi, 32
    dec edx
    jnz .loop2
    jmp .error
.found_dot:
    movzx eax, word [esi+0x1a]
    mov ebp, eax
    call cluster_to_sec
    clc
    add eax, dword [hidden_sectors]
    jc .error
    mov ecx, eax
    movzx eax, byte [sec_per_cluster]
    mov esi, [.dir]
    mov dl, [.drive_number]
    mov dh, 0x0b
    call write_drive
    jc .error

.loop3:
    mov ebx, ebp    ;cluster number
    mov edi, fat_addr
    shl ebx, 1
    movzx eax, word [edi+ebx]
    cmp ax, 0xfff8
    jae .done

    mov ebp, eax

    push eax
    movzx eax, word [bytes_per_sec]
    movzx ebx, byte [sec_per_cluster]
    xor edx, edx
    mul ebx
    add esi, eax
    pop eax

    call cluster_to_sec
    mov ecx, eax
    clc
    add ecx, dword [hidden_sectors]
    jc .error
    movzx eax, byte [sec_per_cluster]
    mov dl, [.drive_number]
    mov dh, 0x0b
    call write_drive
    jc .error
    jmp .loop3
.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret

.dir: dd 0
.drive_number: db 0


.directory:
    mov [.drive_number], ebp

    pusha
    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35

    xchg esi, edi
    mov edx, [.dir]
    mov ebx, ebp
    mov ah, 0x0a
    int 0x33

    mov esi, edi
    jc .error_dir

    mov ecx, 0x1000/32
.loop5:
    mov al, [esi]
    cmp al, 0
    je .done_dir2
    cmp al, 0xe5
    je .next
    cmp al, '.'
    je .next

    mov esi, edi
    jmp .error_dir
.next:
    add esi, 32
    dec ecx
    jnz .loop5
    jmp .done_dir2
.error_dir:
    mov ah, 0x0b
    mov ecx, 0x1000
    int 0x35

    popa
    jmp .error
.done_dir2:
    mov ah, 0x0b
    mov ecx, 0x1000
    mov esi, edi
    int 0x35

    popa
    jmp .del

fs16_rename_file2:
    pusha
.loop:
    mov al, [edx]
    cmp al, 0
    je .error
    cmp al, 0xe5
    je .skip

    mov ecx, 11
    push esi
    push edi
    mov edi, edx
    rep cmpsb
    pop edi
    pop esi
    je .found

.skip:
    add edx, 32
    jmp .loop

.found:
    mov esi, edi
    mov edi, edx
    mov ecx, 11
    rep movsb

    movzx ebp, bl
    call fs16_write_root
    jc .error

    popa
    and dword [esp+8], 0xfffffffe
    iret

.error:
    popa
    or dword [esp+8], 1
    iret
;############################################################
;#################### WRITE FAT TO DRIVE ####################
;############################################################

fs16_write_fat2:
    ;EBP = drive number
    pusha
    xor dx, dx
    mov ax, [fat_size]
    xor ebx, ebx
    movzx bx, byte [sec_per_cluster]
    div bx
    movzx edx, ax

    movzx ecx, word [reserved_sectors]
    mov esi, fat_addr
.loop:
    push eax
    push edx
    movzx eax, byte [sec_per_cluster]
    mov edx, ebp
    mov dh, 0x0b
    call write_drive
    pop edx
    pop eax
    jc .error

    push edx
    xor eax, eax
    mov eax, 512
    movzx edx, byte [sec_per_cluster]
    imul eax, edx
    add esi, eax
    pop edx

    movzx ax, byte [sec_per_cluster]
    add cx, ax
    dec edx
    jnz .loop

    popa
    clc
    ret
.error:
    popa
    stc
    ret

;############################################################
;#################### WRITE ROOT TO DRIVE ###################
;############################################################

fs16_write_root2:
    ;EBP = drive number
    pusha

    xor dx, dx
    mov ax, [root_sectors]
    movzx bx, byte [sec_per_cluster]
    div bx
    movzx edx, ax
    movzx ecx, word [root_start]
    add ecx, dword [hidden_sectors]
    mov esi, root_addr
.loop:
    push edx
    push eax
    movzx eax, byte [sec_per_cluster]
    mov edx, ebp
    mov dh, 0x0b
    call write_drive
    pop eax
    pop edx
    jc .error

    push edx
    mov eax, 512
    movzx edx, byte [sec_per_cluster]
    imul eax, edx
    add esi, eax
    pop edx

    movzx eax, byte [sec_per_cluster]
    add ecx, eax
    dec edx
    jnz .loop

    popa
    clc
    ret
.error:
    popa
    stc
    ret