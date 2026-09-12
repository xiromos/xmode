;================================================================
;syscall for disk I/O like Int 0x13
;INT 0x32
;ATA driver
;AH = 0x02: read sectors into memory            (EBX = sector count, EDI = adress in memory, ECX = LBA)
;AH = 0x03: write sectors to the disk           (EBX = sector count, ESI = buffer, ECX = LBA)
;AH = 0x04: get drive information
;AH = 0x0A: read a sector from the disk with extended LBA       (EBX = sector count, EDI = adress in memory, ECX = pointer to LBA struct)
;AH = 0x0B: write a sector to the disk with extended LBA        (EBX = sector count, EDI = pointer to buffer in memory, ECX = pointer to LBA)
;AH = 0x12: read sectors with DMA                               (BL = sector count, EDI = buffer, ECX = LBA)
;AH = 0x13: write sectors with DMA                              (BL = sector count, EDI = buffer, ECX = LBA)
;----------------------------------------------------------------
;0x1F0 = Data
;0x1F2 = Sector count
;0x1F3 = LBA 0–7
;0x1F4 = LBA 8–15
;0x1F5 = LBA 16–23
;0x1F6 = Drive + LBA high
;0x1F7 = Status / Command
;----------------------------------------------------------------
;Copyright (C) 2026 Technodon
;================================================================
diskio_handler:
    cmp ah, 0x02
    je .read_sectors
    cmp ah, 0x03
    je .write_sectors
    cmp ah, 0x04
    je .get_drive_info
    cmp ah, 0x0a
    je .read_sectors
    cmp ah, 0x0b
    je .write_sectors
    cmp ah, 0x12
    je read_dma
    cmp ah, 0x13
    je write_dma
    stc
    iret

.read_sectors:
    pusha
    cmp ebx, 0
    je .reset_disk
.wait:
    mov dx, 0x1f7
    in al, dx
    test al, 0x80
    jnz .wait
    cmp ah, 0x0a
    je .lba48
    jmp .disk_ok
.reset_disk:
    call reset_ata
    jmp .read_done
.disk_ok:
    cmp ebx, 256
    jb .last_read

    mov dx, 0x1f2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    mov dx, 0x1f3       ;lba bits 0-7
    mov al, cl
    out dx, al

    mov dx, 0x1f4       ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    mov dx, 0x1f5       ;lba bits 16-23
    out dx, al

    mov dx, 0x1f6       ;drive + lba high
    mov al, 0xe0
    or al, ah
    out dx, al

    mov dx, 0x1f7
    mov al, 0x20        ;read command
    out dx, al
    push ecx
    mov ecx, 256
.read_loop:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .read_loop

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.read_word:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .read_word
    loop .read_loop
    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .disk_ok

.last_read:
    cmp bl, 0
    je .read_done

    mov dx, 0x1f2       ;sector count
    mov al, bl
    out dx, al

    mov dx, 0x1f3       ;lba bits 0-7
    mov al, cl
    out dx, al

    mov dx, 0x1f4       ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    mov dx, 0x1f5       ;lba bits 16-23
    out dx, al

    mov dx, 0x1f6       ;drive + lba high
    mov al, 0xe0
    or al, ah
    out dx, al

    mov dx, 0x1f7
    mov al, 0x20        ;read command
    out dx, al

    mov ecx, ebx
.read_loop_last:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .read_loop_last

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.read_word_last:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .read_word_last
    loop .read_loop_last
.read_done:
    popa
    and dword [esp+8], 0xfffffffe       ;remove carry flag from the stack
    ;or dword [esp+8], 1               ;set carry flag
    iret

.lba48:
    cmp ebx, 256
    jb .ext_last_read

    mov dx, 0x1f2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    mov dx, 0x1f3
    mov al, [ecx+3]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+4]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+5]
    out dx, al

    mov dx, 0x1f2
    mov al, bl
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+1]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+2]
    out dx, al

    mov dx, 0x1f6
    mov al, 0x40        ;LBA mode
    out dx, al

    mov dx, 0x1f7
    mov al, 0x24        ;read 48bit
    out dx, al

    push ecx
    mov ecx, 256
.ext_read_loop:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .ext_read_loop

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.ext_read_word:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .ext_read_word
    loop .ext_read_loop
    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .lba48

.ext_last_read:
    cmp bl, 0
    je .ext_read_done

    mov dx, 0x1f2       ;sector count
    mov al, bh
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx+3]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+4]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+5]
    out dx, al

    mov dx, 0x1f2
    mov al, bl
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+1]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+2]
    out dx, al

    mov dx, 0x1f6
    mov al, 0x40        ;LBA mode
    out dx, al

    mov dx, 0x1f7
    mov al, 0x24        ;read 48bit
    out dx, al

    mov ecx, ebx
.ext_read_loop_last:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .ext_read_loop_last

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.ext_read_word_last:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .ext_read_word_last
    loop .ext_read_loop_last
.ext_read_done:
    popa
    and dword [esp+8], 0xfffffffe       ;remove carry flag from the stack
    ;or dword [esp+8], 1               ;set carry flag
    iret


.write_sectors:
    pusha
    cmp ebx, 0
    je .write_done
._wait:
    mov dx, 0x1f7
    in al, dx
    test al, 0x80
    jnz ._wait
    cmp ah, 0x0b
    je .write_lba48
.disk_ready:

    cmp ebx, 256
    jb .last_write

    mov dx, 0x1f2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    mov dx, 0x1f3       ;lba bits 0-7
    mov al, cl
    out dx, al

    mov dx, 0x1f4       ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    mov dx, 0x1f5       ;lba bits 16-23
    out dx, al

    mov dx, 0x1f6       ;drive + lba high
    mov al, 0xe0
    or al, ah
    out dx, al

    mov dx, 0x1f7
    mov al, 0x30        ;write command
    out dx, al
    push ecx
    mov ecx, 256
.write_loop:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .write_loop

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.write_word:
    push ax
    lodsw
    out dx, ax
    add esi, 2
    pop ax
    dec ax
    push ax
    push dx
    mov al, 0xE7
    mov dx, 0x1f7
    out dx, al
    pop dx
    pop ax
    jnz .write_word
    loop .write_loop
    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .disk_ready

.last_write:
    cmp bl, 0
    je .write_done

    mov dx, 0x1f2       ;sector count
    mov al, bl
    out dx, al

    mov dx, 0x1f3       ;lba bits 0-7
    mov al, cl
    out dx, al

    mov dx, 0x1f4       ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    mov dx, 0x1f5       ;lba bits 16-23
    out dx, al

    mov dx, 0x1f6       ;drive + lba high
    mov al, 0xe0
    or al, ah
    out dx, al

    mov dx, 0x1f7
    mov al, 0x30        ;write command
    out dx, al

    mov ecx, ebx
.write_loop_last:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .write_loop_last

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.write_word_last:
    push ax
    mov ax, [esi]
    out dx, ax
    pop ax
    add esi, 2
    dec ax
    push ax
    mov al, 0xE7
    push dx
    mov dx, 0x1f7
    out dx, al       ;flush cache
    pop dx
    pop ax
    jnz .write_word_last
    loop .write_loop_last

.write_done:
    popa
    and dword [esp+8], 0xfffffffe       ;remove carry flag from the stack
    ;or dword [esp+8], 1               ;set carry flag
    iret
.write_lba48:
    cmp ebx, 256
    jb .ext_last_write

    mov dx, 0x1f2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    mov dx, 0x1f3
    mov al, [ecx+3]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+4]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+5]
    out dx, al

    mov dx, 0x1f2
    mov al, bl
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+1]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+2]
    out dx, al

    mov dx, 0x1f6
    mov al, 0x40        ;LBA mode
    out dx, al

    mov dx, 0x1f7
    mov al, 0x34        ;write 48bit
    out dx, al

    push ecx
    mov ecx, 256
.ext_write_loop:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .ext_write_loop

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.ext_write_word:
    mov dx, 0x1f0
    push ax
    mov ax, [esi]
    out dx, ax
    add esi, 2
    pop ax
    dec ax
    push ax
    mov al, 0xE7
    mov dx, 0x1f7
    out dx, al
    pop ax
    jnz .ext_write_word
    loop .ext_write_loop
    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .write_lba48

.ext_last_write:
    cmp bl, 0
    je .ext_write_done

    mov dx, 0x1f2       ;sector count
    mov al, bh
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx+3]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+4]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+5]
    out dx, al

    mov dx, 0x1f2
    mov al, bl
    out dx, al

    mov dx, 0x1f3
    mov al, [ecx]
    out dx, al

    mov dx, 0x1f4
    mov al, [ecx+1]
    out dx, al

    mov dx, 0x1f5
    mov al, [ecx+2]
    out dx, al

    mov dx, 0x1f6
    mov al, 0x40        ;LBA mode
    out dx, al

    mov dx, 0x1f7
    mov al, 0x34        ;write 48bit
    out dx, al

    mov ecx, ebx
.ext_write_loop_last:
    mov dx, 0x1f7
    in al, dx
    test al, 0x08
    jz .ext_write_loop_last

    mov dx, 0x1f0
    mov ax, 256     ;512 bytes
.ext_write_word_last:
    mov dx, 0x1f0
    push ax
    mov ax, [esi]
    out dx, ax
    add esi, 2
    pop ax
    dec ax
    push ax
    mov al, 0xE7
    mov dx, 0x1f7
    out dx, al
    pop ax
    jnz .ext_write_word_last
    loop .ext_write_loop_last
.ext_write_done:
    popa
    and dword [esp+8], 0xfffffffe       ;remove carry flag from the stack
    ;or dword [esp+8], 1               ;set carry flag
    iret

.get_drive_info:
    iret
reset_ata:
    push eax
    mov al, 4
    out dx, al
    xor eax, eax
    out dx, al
    in al, dx
    in al, dx
    in al, dx
    in al, dx
.rdylp:
    in al, dx
    and al, 0xc0
    cmp al, 0x40
    jne .rdylp
    pop eax
    ret
;================================================================
;BL = sector count, ECX = LBA, EDI = buffer
read_dma:
    pusha
    sti
.wait:
    hlt
    cmp byte [ide_running], 1
    je .wait

    mov byte [ide_running], 1   ;block IDE controller
    
    ;set PRDT
    mov [prdt], edi

    push ebx
    xor bh, bh
    mov ax, 512
    mul bx
    mov [prdt+4], ax
    pop ebx

    mov dx, [bm_base4]
    add dx, 4
    mov eax, prdt
    out dx, eax

    ;set READ bit
    mov dx, [bm_base4]
    mov al, 0x08        ;READ
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 2
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f
    or al, 0xe0

    mov dx, 0x1f6
    out dx, al      ;Master + LBA

    mov dx, 0x1f2
    mov al, bl           ;sector count
    out dx, al

    mov dx, 0x1f3
    mov al, cl
    out dx, al

    mov dx, 0x1f4
    mov al, ch
    out dx, al

    shr ecx, 16

    mov dx, 0x1f5
    mov al, cl
    out dx, al

    mov dx, 0x1f7   ;set command
    mov al, 0xc8    ;read DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    mov al, 0x09
    out dx, al

    popa
    iret

;================================================================
;BL = sector count, ECX = LBA, EDI = buffer
write_dma:
    pusha
    sti
    ;check if a DMA transfer is currently active

.wait:
    hlt
    cmp byte [ide_running], 1
    je .wait

    mov byte [ide_running], 1   ;block IDE controller
    
    ;set PRDT
    mov [prdt], edi

    push ebx
    xor bh, bh
    mov ax, 512
    mul bx
    mov [prdt+4], ax
    pop ebx

    mov dx, [bm_base4]
    add dx, 4
    mov eax, prdt
    out dx, eax

    ;set WRITE bit
    mov dx, [bm_base4]
    xor al, al
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 2
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f
    or al, 0xe0

    mov dx, 0x1f6
    out dx, al      ;Master + LBA

    mov dx, 0x1f2
    mov al, bl           ;sector count
    out dx, al

    mov dx, 0x1f3
    mov al, cl
    out dx, al

    mov dx, 0x1f4
    mov al, ch
    out dx, al

    shr ecx, 16

    mov dx, 0x1f5
    mov al, cl
    out dx, al

    mov dx, 0x1f7   ;set command
    mov al, 0xca    ;write DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    mov al, 0x01    ;write
    out dx, al
    
    popa
    iret


;====================================================
;AHCI

ahci_init:
    pusha
    cmp dword [abar], 0                 ;no AHCI controller
    je .no_ahci
    mov eax, [abar]

    mov ebx, [eax+4]
    or ebx, (1 << 31)                   ;set Bit 31 (AHCI Enable) to set Controller into AHCI mode (not legacy IDE)
    mov [eax+4], ebx

    or dword [eax+4], (1 << 0)          ;set Bit 0 to reset the controller
.wait_reset:
    mov ebx, [eax+4]
    test ebx, (1 << 0)
    jnz .wait_reset

    mov ebx, [eax+4]
    or ebx, (1 << 31)                   ;set AHCI mode again because it might be deleted after reset
    mov [eax+4], ebx

    mov ebx, [eax+0xc]                  ;Ports Implemented
    xor ecx, ecx
.loop:
    cmp ecx, 32
    jae .done

    bt ebx, ecx
    jnc .next

    jmp .found_port
.next:
    inc ecx
    jmp .loop
.done:
    mov eax, [abar]
    mov dword [eax+0x10], 0xffffffff
    mov dword [eax+0x08], 0xffffffff
    or dword [eax+4], (1 << 1)          ;enable global interrupts
    popa
    ret

.found_port:
    ;EAX = ABAR
    mov edi, eax
    add edi, 0x100

    mov edx, ecx
    imul edx, 0x80

    ;check if port is emtpy
    add edi, edx
    mov edx, [edi+0x28]     ;PxSSTS
    and edx, 0x0f
    cmp edx, 3
    jne .empty_port

    ; mov edx, [edi+0x28]
    ; shr edx, 8
    ; and edx, 0x0f
    ; cmp edx, 1
    ; jne .empty_port

    mov edx, [edi+0x24]     ;PxSIG
    test edx, edx
    jz .empty_port

    ; mov [esi+10], edx        ;0x00000101 = SATA, 0xEB140101 = ATAPI

    mov ebx, edx
    ;store port data in global strucure DRIVE_LIST
    movzx edx, byte [avail_disks]
    imul edx, DRIVE_LIST_ENTRY
    add edx, DRIVE_LIST_ADDR
    mov [edx], eax      ;ABAR
    mov [edx+4], edi    ;Port Address
    mov [edx+8], cl     ;Port Number
    mov [edx+9], 0xaa   ;Drive Type
    mov [edx+10], ebx
    inc byte [avail_disks]

    push ebx
    ;stop port
    mov ebx, [edi+0x18]
    and ebx, ~(1 << 0)
    and ebx, ~(1 << 4)
    mov [edi+0x18], ebx

    ;wait for port
.wait:
    mov ebx, [edi+0x18]
    test ebx, (1 << 15)
    jnz .wait
    test ebx, (1 << 14)
    jnz .wait

    pop ebx

    ;set command lists
    push edi
    mov edi, AHCI_PORT_MEM_OFF
    imul edi, ecx
    add edi, AHCI_MEM_BASE
    mov edx, edi           ;address of Command List
    pop edi

    mov [edi], edx          ;PxCLB
    mov dword [edi+4], 0    ;PxCLBU

    push edi
    push ecx
    push eax

    mov edi, [edi]      ;Command List Base
    imul ecx, 32
    add edi, ecx

    xor eax, eax
    mov ecx, 1024/4
    rep stosd

    pop eax
    pop ecx
    pop edi

    push edi
    mov edi, AHCI_PORT_MEM_OFF
    imul edi, ecx
    add edi, AHCI_MEM_BASE
    add edi, CMD_LIST_SIZE
    mov edx, edi            ;address of Reveived FIS

    push ecx
    push eax

    xor eax, eax
    mov ecx, RECEIVED_FIS_SIZE/4
    rep stosd

    pop eax
    pop ecx

    push ecx
    push eax

    ;clear command tables
    mov edi, AHCI_PORT_MEM_OFF
    imul edi, ecx
    add edi, AHCI_MEM_BASE
    add edi, CMD_LIST_SIZE
    add edi, RECEIVED_FIS_SIZE

    mov ecx, 256*32/4
    xor eax, eax
    rep stosd

    pop eax
    pop ecx
    pop edi

    mov [edi+0x8], edx      ;PxFB
    mov dword [edi+12], 0   ;PxFBU

    mov dword [edi+0x30], 0xffffffff        ;clear PxSERR
    mov dword [edi+0x10], 0xffffffff        ;clear Interrupt Status

    push ebx

    mov ebx, [edi+0x18]
    or ebx, (1 << 4)        ;FIS Receive Enable
    mov [edi+0x18], ebx

.wait_fre:
    test dword [edi+0x18], (1 << 14)
    jz .wait_fre

    mov ebx, [edi+0x18]
    or ebx, (1 << 0)        ;ST
    or ebx, (1 << 1)        ;SUD
    or ebx, (1 << 28)       ;set active bit
    mov [edi+0x18], ebx
.wait_start:
    test dword [edi+0x18], (1 << 15)
    jz .wait_start

    pop ebx

    ; ## SKIPPING ATAPI ##
    cmp dword [edi+0x24], 0xeb140101
    je .next                          ;skip IDENTIFY because device is an ATAPI device

    push eax
    mov al, cl
    call identify_ahci
    pop eax

    mov dword [edi+0x30], 0xffffffff        ;clear PxSERR
    mov dword [edi+0x10], 0xffffffff        ;clear Interrupt Status
    mov dword [eax+0x08], 0xffffffff

    jc .port_err

    mov dword [edi+0x14], 0x4000002d        ;activate interrupts
.empty_port:
    jmp .next
.no_ahci:
    popa
    ret
.port_err:
    ;remove device from drive list
    dec byte [avail_disks]
    movzx edx, byte [avail_disks]
    imul edx, DRIVE_LIST_ENTRY
    add edx, DRIVE_LIST_ADDR

    mov dword [edx], 0
    mov dword [edx+4], 0
    mov dword [edx+8], 0
    mov dword [edx+12], 0

    jmp .next

identify_ahci:
    pusha
    ;AL = AHCI Port
    ;EDI = port address
    ;EBX = port index (for example bit 8 set for 9th port)

    ; Px + 0x00  CLB   (Command List Base)
    ; Px + 0x04  CLBU
    ; Px + 0x08  FB    (FIS Base)
    ; Px + 0x0C  FBU
    ; Px + 0x10  IS    (Interrupt Status)
    ; Px + 0x14  IE    (Interrupt Enable)
    ; Px + 0x18  CMD   (Command and Status)
    ; Px + 0x1C  reserved
    ; Px + 0x20  TFD   (Task File Data)
    ; Px + 0x24  SIG   (Signature)
    ; Px + 0x28  SSTS  (SATA Status)
    ; Px + 0x2C  SCTL
    ; Px + 0x30  SERR
    ; Px + 0x34  SACT
    ; Px + 0x38  CI    (Command Issue)

    movzx ebp, al
    mov eax, edi

    mov ebx, [eax+0x38]
    ;or ebx, [eax+0x34]
    not ebx
    bsf ecx, ebx
    ;jz .no_free_slot

    mov edi, [eax]
    mov edx, ecx
    shl edx, 5      ;*32
    add edi, edx
    ; Command Header
    ; DWORD 0: flags + PRDT length
    ; DWORD 1: PRDT base addr low
    ; DWORD 2: PRDT base addr high
    ; DWORD 3: reserved

    mov edx, ebp      ;port number
    mov esi, AHCI_MEM_BASE
    imul edx, AHCI_PORT_MEM_OFF
    add esi, edx
    add esi, CMD_LIST_SIZE
    add esi, RECEIVED_FIS_SIZE
    mov edx, CMD_TABLES_SIZE
    imul edx, ecx       ;slot number
    add esi, edx        ;address of command table

    push esi
    push edi
    push eax
    push ecx

    xor eax, eax
    mov edi, esi
    mov ecx, 256/4
    rep stosd

    pop ecx
    pop eax
    pop edi
    pop esi

    ;set Command Header
    mov dword [edi], 0x00010005         ;FIS length + PRDT entries
    mov dword [edi+4], 0
    mov dword [edi+8], esi
    mov dword [edi+12], 0

    ;set PRDT
    push esi
    push eax
    push ecx

    mov ecx, 512
    mov ah, 0x0a
    int 0x35

    mov ebx, esi

    pop ecx
    pop eax
    pop esi

    push ebx

    mov dword [esi+0x80], ebx           ;low address
    mov dword [esi+0x84], 0             ;high address
    mov dword [esi+0x88], 0             ;reserved
    ;mov ebx, (1 << 31)
    or ebx, 511
    mov dword [esi+0x8c], ebx           ;byte count + interrupt on completion

    ;set FIS
    mov byte [esi], 0x27
    mov byte [esi+1], 0x80
    mov byte [esi+2], 0xec      ;IDENTIFY Command
    mov byte [esi+3], 0         ;features byte
    mov byte [esi+4], 0         ;LBA 0
    mov byte [esi+5], 0         ;LBA 1
    mov byte [esi+6], 0         ;LBA 2

    mov byte [esi+7], 0xe0      ;device byte

    mov byte [esi+8], 0         ;LBA 3
    mov byte [esi+9], 0         ;LBA 4
    mov byte [esi+10], 0        ;LBA 5

    mov byte [esi+12], 0        ;sector count 1
    mov byte [esi+13], 0        ;sector count 2

    mov dword [eax+0x30], 0xffffffff    ;clear errors
    mov dword [eax+0x10], 0xffffffff    ;interrupt status
    mov ebx, 1
    shl ebx, cl

.wait_busy:
    mov ecx, [eax+0x20]
    test ecx, 0x88      ;check if Bit 3 and Bit 7 are 0 (busy and data request)
    jnz .wait_busy

    mov edx, [eax+0x38]
    or edx, ebx
    mov [eax+0x38], edx     ;set PxCI
.wait_command:
    mov ecx, [eax+0x20]
    test ecx, 1
    jnz .error

    mov ecx, [eax+0x30]
    test ecx, ecx
    jnz .serr

    mov edx, [eax+0x38]
    test edx, ebx
    jnz .wait_command

    ;get data from buffer
    pop esi

    movzx edi, byte [avail_disks]
    dec edi
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    test dword [esi+0xa6], (1 << 10)
    jnz .lba48
.lba28:
    mov eax, [esi+0x78]
    mov [edi+14], eax
    mov dword [edi+18], 0
    jmp .get_sector_size

.lba48:
    test dword [esi+0xa6], (1 << 14)
    jz .lba28
    test dword [esi+0xa6], (1 << 15)
    jnz .lba28

    mov eax, [esi+0xc8]
    mov [edi+14], eax
    mov eax, [esi+0xcc]
    mov [edi+18], eax
.get_sector_size:
    test dword [esi+0xd4], (1 << 12)
    jz .sector512

    mov eax, [esi+0xea]
    imul eax, 2
    mov dword [edi+22], eax

    ;4KiB sectores are not supported
    mov ecx, 512
    mov ah, 0x0b
    int 0x35
    popa
    stc
    ret
.sector512:
    mov dword [edi+22], 512

.get_modelname:
    push esi
    push edi

    add esi, 0x14
    add edi, 26
    mov ecx, 7
.loop1:
    lodsw
    xchg al, ah
    stosw
    dec ecx
    jnz .loop1

    pop edi
    pop esi

    push edi
    push esi

    add esi, 0x36
    add edi, 40
    mov ecx, 10
.loop2:
    lodsw
    xchg al, ah
    stosw
    dec ecx
    jnz .loop2

    pop esi
    pop edi

    mov edi, ebp      ;port number
    imul edi, AHCI_PORT_MEM_OFF
    add edi, AHCI_MEM_BASE
    add edi, AHCI_TASK_STRUCT_OFF

    xor eax, eax
    mov ecx, 64/4
    rep stosd

    popa
    clc
    ret
.serr:
    mov [eax+0x30], ecx
.error:
    pop esi
    mov ecx, 512
    mov ah, 0x0b
    int 0x35
    popa
    stc
    ret

; #### READ AHCI ####

read_ahci:
    ;AL = port number (0 - 31)
    ;ECX = low LBA
    ;DX = high LBA
    ;BX = sector count
    ;EDI = destination buffer
    ;ESI = device type (SATA / ATAPI)

    ; ! EXPECTS 512 BYTES SECTORS
    pusha
    cmp bx, 0
    je .error
    cmp al, 32
    jae .error
    push edi

    movzx edi, al
    movzx ebp, al
    imul edi, 0x80
    add edi, 0x100
    add edi, dword [abar]

    push ecx
    push edx
    push ebx

    cli
.cmd_slot:
    mov ebx, [edi+0x38]
    mov ecx, [edi+0x34]

    or ebx, ecx
    not ebx
    test ebx, ebx
    jz .no_slot

    bsf ebx, ebx        ;EBX = number of free slot (0 - 31) in command list

    mov [.device_type], esi

    mov edx, [edi]
    mov eax, ebx
    shl eax, 5
    add edx, eax


    mov ecx, AHCI_PORT_MEM_OFF
    imul ecx, ebp
    add ecx, AHCI_MEM_BASE
    add ecx, CMD_LIST_SIZE

    push edi
    push ecx
    push eax
    mov edi, ecx
    mov ecx, 0xff/4
    xor eax, eax
    rep stosd
    pop eax
    pop ecx
    pop edi

    add ecx, RECEIVED_FIS_SIZE

    mov eax, ebx
    imul eax, CMD_TABLES_SIZE
    add ecx, eax

    mov eax, ebp
    mov [.port], al
    mov ebp, ebx            ;EBP = slot index in command list

    pop ebx
    push ebx
    movzx eax, bx
    shr eax, 13     ;EAX / 8192

    and ebx, 8191
    jz .zero

    inc eax
.zero:
    cmp eax, 0
    jne .skip

    mov eax, 1
.skip:
    mov byte [.prdt_entry], al
    shl eax, 16
    or eax, 5
    mov [edx], eax     ;FIS length of 20 bytes + number of PRDT entries
    mov dword [edx+4], 0
    mov dword [edx+8], ecx
    mov dword [edx+12], 0

    mov edx, ecx

    mov byte [edx], 0x27
    mov byte [edx+1], 0x80
    mov byte [edx+2], 0x60        ;READ FPDMA QUEUED

    pop ebx                       ;sector count
    mov [edx+3], bl
    mov [edx+11], bh
    mov byte [edx+7], 0x40

    mov eax, ebp
    shl eax, 3
    mov [edx+12], al              ;set NCQ tag

    pop eax
    pop ebx

    mov [edx+4], bl
    shr ebx, 8
    mov [edx+5], bl
    shr ebx, 8
    mov [edx+6], bl
    shr ebx, 8
    mov [edx+8], bl

    mov [edx+9], al
    mov [edx+10], ah

    pop ebx

    push edi
    push edx
    mov edi, ebx

    xor ebx, ebx
    mov bl, [edx+3]
    mov bh, [edx+11]
    movzx eax, byte [.prdt_entry]
    add edx, 0x80
.loop:
    mov [edx], edi
    mov dword [edx+4], 0
    mov dword [edx+8], 0

    mov ecx, ebx
    cmp ecx, 0x2000
    jb .skip2

    mov ecx, 0x2000
.skip2:
    imul ecx, 512
    dec ecx
    cmp eax, 1
    je .last

    mov [edx+12], ecx
    jmp .next
.last:
    or ecx, (1 << 31)       ;interrupt on completion
    mov [edx+12], ecx
    jmp .send_command
.next:
    dec eax
    add edi, 0x2000
    sub ebx, 0x2000
    add edx, 16
    jmp .loop
.send_command:
    pop edx
    pop edi

    mov ebx, 1
    mov ecx, ebp
    shl ebx, ecx
    or dword [edi+0x34], ebx
    or dword [edi+0x38], ebx

    movzx eax, word [current_task]
    movzx edi, byte [.port]
    imul edi, AHCI_PORT_MEM_OFF
    add edi, AHCI_MEM_BASE
    add edi, AHCI_TASK_STRUCT_OFF

    mov edx, ebp
    shl edx, 1 ;*2
    add edi, edx
    mov [edi], ax
    imul eax, TASK_SIZE
    add eax, tasks_esp
    mov dword [eax+11], TASK_FLAG_SLEEPING
    sti
    int 0x20

    popa
    clc
    ret
.error:
    popa
    stc
    ret
.no_slot:
    sti
    hlt
    jmp .cmd_slot
.device_type: dd 0
.prdt_entry: db 0
.port: db 0

; #### WRITE AHCI ####

write_ahci:
    ;AL = port number (0 - 31)
    ;ECX = low LBA
    ;DX = high LBA
    ;BX = sector count
    ;EDI = source buffer
    ;ESI = device type (SATA / ATAPI)

    ; ! EXPECTS 512 BYTES SECTORS
    pusha
    cmp bx, 0
    je .error
    cmp al, 32
    jae .error
    push edi

    movzx edi, al
    movzx ebp, al
    imul edi, 0x80
    add edi, 0x100
    add edi, dword [abar]

    push ecx
    push edx
    push ebx

    cli
.cmd_slot:
    mov ebx, [edi+0x38]
    mov ecx, [edi+0x34]

    or ebx, ecx
    not ebx
    test ebx, ebx
    jz .no_slot

    bsf ebx, ebx        ;EBX = number of free slot (0 - 31) in command list

    mov [.device_type], esi

    mov edx, [edi]
    mov eax, ebx
    shl eax, 5
    add edx, eax


    mov ecx, AHCI_PORT_MEM_OFF
    imul ecx, ebp
    add ecx, AHCI_MEM_BASE
    add ecx, CMD_LIST_SIZE

    push edi
    push ecx
    push eax
    mov edi, ecx
    mov ecx, 0xff/4
    xor eax, eax
    rep stosd
    pop eax
    pop ecx
    pop edi

    add ecx, RECEIVED_FIS_SIZE

    mov eax, ebx
    imul eax, CMD_TABLES_SIZE
    add ecx, eax

    mov eax, ebp
    mov [.port], al
    mov ebp, ebx            ;EBP = slot index in command list

    pop ebx
    push ebx
    movzx eax, bx
    shr eax, 13     ;EAX / 8192

    and ebx, 8191
    jz .zero

    inc eax
.zero:
    cmp eax, 0
    jne .skip

    mov eax, 1
.skip:
    mov byte [.prdt_entry], al
    shl eax, 16
    or eax, 5
    or eax, (1 << 6)
    mov [edx], eax     ;FIS length of 20 bytes + number of PRDT entries
    mov dword [edx+4], 0
    mov dword [edx+8], ecx
    mov dword [edx+12], 0

    mov edx, ecx

    mov byte [edx], 0x27
    mov byte [edx+1], 0x80
    mov byte [edx+2], 0x61        ;READ FPDMA QUEUED

    pop ebx                       ;sector count
    mov [edx+3], bl
    mov [edx+11], bh
    mov byte [edx+7], 0x40

    mov eax, ebp
    shl eax, 3
    mov [edx+12], al              ;set NCQ tag

    pop eax
    pop ebx

    mov [edx+4], bl
    shr ebx, 8
    mov [edx+5], bl
    shr ebx, 8
    mov [edx+6], bl
    shr ebx, 8
    mov [edx+8], bl

    mov [edx+9], al
    mov [edx+10], ah

    pop ebx

    push edi
    push edx
    mov edi, ebx

    xor ebx, ebx
    mov bl, [edx+3]
    mov bh, [edx+11]
    movzx eax, byte [.prdt_entry]
    add edx, 0x80
.loop:
    mov [edx], edi
    mov dword [edx+4], 0
    mov dword [edx+8], 0

    mov ecx, ebx
    cmp ecx, 0x2000
    jb .skip2

    mov ecx, 0x2000
.skip2:
    imul ecx, 512
    dec ecx
    cmp eax, 1
    je .last

    mov [edx+12], ecx
    jmp .next
.last:
    or ecx, (1 << 31)       ;interrupt on completion
    mov [edx+12], ecx
    jmp .send_command
.next:
    dec eax
    add edi, 0x2000
    sub ebx, 0x2000
    add edx, 16
    jmp .loop
.send_command:
    pop edx
    pop edi

    mov ebx, 1
    mov ecx, ebp
    shl ebx, ecx
    or dword [edi+0x34], ebx
    or dword [edi+0x38], ebx

    movzx eax, word [current_task]
    movzx edi, byte [.port]
    imul edi, AHCI_PORT_MEM_OFF
    add edi, AHCI_MEM_BASE
    add edi, AHCI_TASK_STRUCT_OFF

    mov edx, ebp
    shl edx, 1 ;*2
    add edi, edx
    mov [edi], ax
    imul eax, TASK_SIZE
    add eax, tasks_esp
    mov dword [eax+11], TASK_FLAG_SLEEPING
    sti
    int 0x20

    popa
    clc
    ret
.error:
    popa
    stc
    ret
.no_slot:
    sti
    hlt
    jmp .cmd_slot
.device_type: dd 0
.prdt_entry: db 0
.port: db 0
; Drive List in Memory at 0x8a700

; AHCI
; DWORD 1: ABAR
; DWORD 2: Port Address
; BYTE 1:  Port Number
; BYTE 2:  0xAA (Drive Type)
; DWORD 3: Signature (device type), (SATA or SATAPI), (0x00000101 = SATA, 0xEB140101 = SATAPI)
; QWORD 1: Max. LBA
; DWORD 1: Block size
; 14 BYTES: serial number
; 20 BYTES: model name
; 40 BYTES: MBR partition information

; IDE
; DWORD 1: Busmaster Address (if 0 then DMA is not supported)
; BYTE 1:  Master / Slave
; BYTE 2:  Primary / Secondary  (1 = primary, 2 = secondary)
; WORD 1:  Base Channel
; BYTE 3:  ATA / ATAPI (0x00 = ATA, 0xaf = ATAPI)
; BYTE 4:  0xDE (Drive Type)
; BYTE 5:  Busmastering DMA supported (1 = yes, 0 = no)
; QWORD 1: Max. LBA
; DWORD 1: Block size
; 32 BYTES: Vendor + Product name
; 40 BYTES: MBR partition information

; USB
; 8 BYTES: Vendor ID
; BYTE 1: Host Controller Interface (0x10 = OHCI, 0x15 = UHCI, 0x20 = EHCI, 0x30 = XHCI)
; BYTE 2: 0xBE (Drive Type)
; WORD 1: USB Address
; DWORD 1: Base (OHCI_BASE)
; 16 BYTES: Product name
; DWORD 2: max. LBA
; DWORD 3: block size
; 40 BYTES: MBR partition information
ide_init:
    pusha
    ; PCI
    ; BAR0	Primary Command Base
    ; BAR1	Primary Control Base
    ; BAR2	Secondary Command Base
    ; BAR3	Secondary Control Base
    ; BAR4	Busmaster IDE Base

    mov dx, 0x3f6
    xor al, al
    out dx, al

    mov dx, 0x376
    xor al, al
    out dx, al
    ;test primary master
    mov dx, 0x1f0
    mov al, 0xa0
    call identify_ata
    jc .device2

    mov dx, 0x1f0
    movzx edi, byte [avail_disks]
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    mov byte [edi+4], 0xa0
    mov byte [edi+5], 1
    mov word [edi+6], dx
    mov [edi+11], eax       ;low LBA
    mov [edi+15], ebp       ;high LBA
    mov [edi+19], ebx       ;block size

    push edi
    add edi, 23
    mov ecx, 32
    mov esi, .name_buffer
    rep movsb
    pop edi

    cmp cl, 0xaf
    jne .ata1

    mov byte [edi+8], 0xaf
    inc byte [avail_disks]
    jmp .device2
.ata1:
    mov byte [edi+9], 0xde

    inc byte [avail_disks]
    cmp word [bm_base], 0
    je .device2
    mov eax, [bm_base]
    mov [edi], eax
    mov [edi+10], bl        ;DMA supported y/n

.device2:
    mov dx, 0x1f0
    mov al, 0xb0
    call identify_ata
    jc .device3

    mov dx, 0x1f0
    movzx edi, byte [avail_disks]
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    mov byte [edi+4], 0xb0
    mov byte [edi+5], 1
    mov word [edi+6], dx
    mov [edi+11], eax       ;low LBA
    mov [edi+15], ebp       ;high LBA
    mov [edi+19], ebx       ;block size

    push edi
    add edi, 23
    mov ecx, 32
    mov esi, .name_buffer
    rep movsb
    pop edi

    cmp cl, 0xaf
    jne .ata2

    mov byte [edi+8], 0xaf
    inc byte [avail_disks]
    jmp .device3
.ata2:
    mov byte [edi+9], 0xde

    inc byte [avail_disks]
    cmp word [bm_base], 0
    je .device3
    mov eax, [bm_base]
    mov [edi], eax
    mov [edi+10], bl

.device3:
    mov dx, 0x170
    mov al, 0xa0
    call identify_ata
    jc .device4

    mov dx, 0x170
    movzx edi, byte [avail_disks]
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    mov byte [edi+4], 0xa0
    mov byte [edi+5], 2
    mov word [edi+6], dx
    mov [edi+11], eax       ;low LBA
    mov [edi+15], ebp       ;high LBA
    mov [edi+19], ebx       ;block size

    push edi
    add edi, 23
    mov ecx, 32
    mov esi, .name_buffer
    rep movsb
    pop edi

    cmp cl, 0xaf
    jne .ata3

    mov byte [edi+8], 0xaf
    inc byte [avail_disks]
    jmp .device4
.ata3:
    mov byte [edi+9], 0xde

    inc byte [avail_disks]
    cmp word [bm_base], 0
    je .device4
    mov eax, [bm_base]
    mov [edi], eax
    mov [edi+10], bl

.device4:
    mov dx, 0x170
    mov al, 0xb0
    call identify_ata
    jc .done

    mov dx, 0x170
    movzx edi, byte [avail_disks]
    imul edi, DRIVE_LIST_ENTRY
    add edi, DRIVE_LIST_ADDR

    mov byte [edi+4], 0xb0
    mov byte [edi+5], 2
    mov word [edi+6], dx
    mov [edi+11], eax       ;low LBA
    mov [edi+15], ebp       ;high LBA
    mov [edi+19], ebx       ;block size

    push edi
    add edi, 23
    mov ecx, 32
    mov esi, .name_buffer
    rep movsb
    pop edi

    cmp cl, 0xaf
    jne .ata4

    mov byte [edi+8], 0xaf
    inc byte [avail_disks]
    jmp .done
.ata4:
    mov byte [edi+9], 0xde

    inc byte [avail_disks]
    cmp word [bm_base], 0
    je .done
    mov eax, [bm_base]
    mov [edi], eax
    mov [edi+10], bl
.done:
    popa
    ret
.name_buffer: times 32 db 0


identify_ata:
    ;DX = 1. Channel

    mov bx, dx
    add dx, 6
    out dx, al

    mov cx, 4
.loop:
    in al, dx
    dec cx
    jnz .loop

    xor al, al
    mov dx, bx
    add dx, 2
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al

    add dx, 2
    mov al, 0xec
    out dx, al

    in al, dx
    cmp al, 0
    je .no_device

.wait:
    in al, dx
    test al, 0x80
    jnz .wait

    test al, 1
    jnz .error

    test al, 0x08
    jz .wait

    mov edi, 0x200000
    mov ecx, 256
    sub dx, 7
.loop2:
    in ax, dx
    stosw
    loop .loop2

    ;check if busmastering DMA is supported
    mov ax, [0x200000+98]
    test ax, 0x0100
    jz .no_dma

    mov bl, 1       ;DMA supported
    jmp .end
.no_dma:
    xor bl, bl      ;DMA not supported
.end:
    mov ecx, 16
    mov esi, 0x200000+54
    mov edi, ide_init.name_buffer
.end1:
    lodsw
    xchg al, ah
    stosw
    dec ecx
    jnz .end1

    mov esi, 0x200000

    mov ebx, 512
    test word [esi+212], (1 << 12)
    jz .skip_read_blocksize

    mov ebx, [esi+234]
    shl ebx, 1          ;block size
.skip_read_blocksize:
    test word [esi+166], (1 << 10)
    jnz .lba48

    mov eax, [esi+120]  ;max LBA
    xor ebp, ebp
.done:
    xor cl, cl
    clc
    ret
.no_device:
    stc
    ret
.lba48:
    mov eax, [esi+200]      ;low LBA
    movzx ebp, word [esi+204]
    jmp .done
.error:
    ;check if its an ATAPI device
    mov dx, bx
    add dx, 4
    in al, dx
    mov ah, al
    inc dx
    in al, dx
    cmp ah, 0x14    ;LBA1
    jne .no_device
    cmp al, 0xeb
    jne .no_device
    
    mov al, 0xa1
    mov dx, bx
    add dx, 7
    out dx, al

    in al, dx
    cmp al, 0
    je .no_device

.wait2:
    in al, dx
    test al, 0x80
    jnz .wait2

    test al, 0x08
    jz .wait2

    mov cx, 256
    sub dx, 7
.loop3:
    in ax, dx
    loop .loop3

    clc
    mov cl, 0xaf
    ret



get_drive_information:
    ;DL = Drive Number
    ret
read_drive:
;=========================================
;Read a specific amount of sectors into memory
;Expects following Arguments
;If you read with extended LBA, pass into ECX a ext_lba structure
;When reading sectors give EDI the address of your buffer
;<> Arguments <>
    ;DL = Drive Number
    ;DH = EXT_LBA READ (0x0a = yes, 0x0b = no)
    ;AX = Sectors
    ;EDI = Buffer
    ;ECX = LBA / pointer to LBA struct
;<> LBA struct <>
; ext_lba_struct:
;     db 0
;     db 0
;     db 0
;     db 0
;     db 0
;     db 0
    pusha
    movzx esi, dl
    imul esi, DRIVE_LIST_ENTRY
    add esi, DRIVE_LIST_ADDR

    cmp byte [esi+9], 0xaa     ;AHCI
    je .ahci
    cmp byte [esi+9], 0xde     ;IDE
    je .ide
    cmp byte [esi+9], 0xbe
    je .usb
.error:
    ;no drive found
    popa
    stc
    ret
.ide:
    cmp dh, 0x0a
    je .ide_ext_lba

    cmp dh, 0x0b
    jne .error

    cmp byte [esi+10], 1
    je .ide_dma

    mov ebx, eax        ;sectors in EBX
    mov dx, [esi+6]     ;Base Channel
    mov al, [esi+4]     ;Master / Slave

    call read_ide_sectors
    jc .error
    jmp .done

.ide_ext_lba:
    mov dx, [esi+6]         ;base channel
    mov ebx, eax
    mov al, [esi+4]         ;Master / Slave

    call read_ide_sectors_ext
    jc .error
    jmp .done
.ide_dma:
    mov ebx, eax
    mov al, [esi+4]
    mov ah, [esi+5]
    mov dx, [esi]
    mov si, [esi+6]

    call read_ide_dma
    jc .error
    jmp .done

.ahci:
    mov bx, ax
    mov al, [esi+8]
    mov esi, [esi+10]

    mov ah, dh
    xor edx, edx
    cmp ah, 0x0b
    je .read_ahci

    movzx edx, word [ecx+4]
    mov ecx, [ecx]
.read_ahci:
    call read_ahci
    jc .error
    jmp .done


.usb:
    mov al, [esi+8]
    cmp al, 0x10
    je .ohci
    cmp al, 0x15
    je .uhci
    cmp al, 0x20
    je .ehci
    cmp al, 0x30
    je .xhci

    jmp .error

.ohci:
    ; call dword [ohci_read_sectors]
    ; jc .error
    ; jmp .done
    jmp .error
.uhci:
    call dword [uhci_read_sectors]
    jc .error
    jmp .done
.ehci:
    call dword [ehci_read_sectors]
    jc .error
    jmp .done
.xhci:
    call dword [xhci_read_sectors]
    jc .error
.done:
    popa
    clc
    ret


write_drive:
    ;DL = Drive Number
    ;DH = EXT_LBA READ (0x0a = yes, 0x0b = no)
    ;AX = sectors
    ;ESI = Buffer
    ;ECX = LBA / pointer to lba_struct
    pusha
    mov edi, esi
    movzx esi, dl
    imul esi, DRIVE_LIST_ENTRY
    add esi, DRIVE_LIST_ADDR

    cmp byte [esi+9], 0xaa     ;AHCI
    je .ahci
    cmp byte [esi+9], 0xde     ;IDE
    je .ide
    cmp byte [esi+9], 0xbe
    je .usb

.error:
    popa
    stc
    ret
.ide:
    cmp dh, 0x0a
    je .ide_ext_lba

    cmp dh, 0x0b
    jne .error

    cmp byte [esi+10], 1
    je .ide_dma

    mov ebx, eax        ;sectors in EBX
    mov dx, [esi+6]     ;Base Channel
    mov al, [esi+4]     ;Master / Slave
    mov esi, edi

    call write_ide_sectors
    jc .error
    jmp .done

.ide_ext_lba:
    mov ebx, eax
    mov dx, [esi+6]         ;base channel
    mov al, [esi+4]         ;Master / Slave
    mov esi, edi

    call write_ide_sectors_ext
    jc .error
    jmp .done
.ide_dma:
    mov ebx, eax
    mov dx, [esi]
    mov ah, [esi+5]
    mov al, [esi+4]
    mov si, [esi+6]
    call write_ide_dma
    popa
    clc
    ret
.ahci:
    mov bx, ax
    mov al, [esi+8]
    mov esi, [esi+10]

    mov ah, dh
    xor edx, edx
    cmp ah, 0x0b
    je .write_ahci

    movzx edx, word [ecx+4]
    mov ecx, [ecx]
.write_ahci:

    call write_ahci
    jc .error
    popa
    clc
    ret
.usb:
    popa
    clc
    ret
.done:
    popa
    clc
    ret

;===========================================ATA PIO MODE===============================================0
read_ide_sectors:
    cmp ebx, 0
    je .reset_disk

    mov [base_channel], dx
    add dx, 7
    movzx esi, al       ;store drive (0xa0 / 0xb0)
.wait:
    in al, dx
    test al, 0x80
    jnz .wait
    jmp .disk_ok
.reset_disk:
    call reset_ata
    jmp .read_done
.disk_ok:
    cmp ebx, 256
    jb .last_read

    mov dx, [base_channel]
    add dx, 2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    inc dx
    mov al, cl           ;lba bits 0-7
    out dx, al

    inc dx               ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    inc dx       ;lba bits 16-23
    out dx, al

    mov dx, si
    mov al, dl
    and al, 0x10

    or al, 0xe0
    or al, ah
    mov dx, [base_channel]
    add dx, 6
    out dx, al          ;drive + lba high

    inc dx
    mov al, 0x20        ;read command
    out dx, al

    push ecx
    mov ecx, 256
    mov dx, [base_channel]
    add dx, 7
.read_loop:
    in al, dx
    test al, 0x08
    jz .read_loop

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.read_word:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .read_word
    pop dx
    loop .read_loop
    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .disk_ok

.last_read:
    cmp ebx, 0
    je .read_done

    mov dx, [base_channel]
    add dx, 2           ;sector count
    mov al, bl
    out dx, al

    inc dx              ;lba bits 0-7
    mov al, cl
    out dx, al

    inc dx              ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    inc dx             ;lba bits 16-23
    out dx, al

    mov dx, si
    mov al, dl
    and al, 0x10

    or al, 0xe0
    or al, ah
    mov dx, [base_channel]
    add dx, 6
    out dx, al          ;drive + lba high

    inc dx
    mov al, 0x20        ;read command
    out dx, al

    mov ecx, ebx
    mov dx, [base_channel]
    add dx, 7
.read_loop_last:
    in al, dx
    test al, 0x08
    jz .read_loop_last

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.read_word_last:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .read_word_last
    pop dx
    loop .read_loop_last

    mov dx, [base_channel]
    add dx, 7
    in al, dx

    test al, 0x01
    jnz .error
.read_done:
    clc
    ret
.error:
    stc
    ret

read_ide_sectors_ext:
    cmp ebx, 0
    je .error

    mov [base_channel], dx
    add dx, 7
    
    movzx esi, al       ;store drive (0xa0 / 0xb0)
.wait:
    in al, dx
    test al, 0x80
    jnz .wait
.read_ext:
    cmp ebx, 256
    jb .ext_last_read

    mov dx, [base_channel]
    add dx, 2            ;sector count
    xor al, al
    out dx, al           ;256 sectors

    inc dx
    mov al, [ecx+3]
    out dx, al

    inc dx
    mov al, [ecx+4]
    out dx, al

    inc dx
    mov al, [ecx+5]
    out dx, al

    mov dx, [base_channel]
    add dx, 2
    xor al, al
    out dx, al

    inc dx
    mov al, [ecx]
    out dx, al

    inc dx
    mov al, [ecx+1]
    out dx, al

    inc dx
    mov al, [ecx+2]
    out dx, al

    mov dx, si
    mov al, dl

    or al, 0x40         ;Bit 6 - LBA Mode
    mov dx, [base_channel]
    add dx, 6
    out dx, al

    mov dx, [base_channel]
    add dx, 7
    mov al, 0x24        ;read 48bit
    out dx, al

    mov dx, [base_channel]
    add dx, 7

    push ecx
    mov ecx, 256
.ext_read_loop:
    mov dx, [base_channel]
    add dx, 7

    in al, dx
    test al, 0x08
    jz .ext_read_loop

    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.ext_read_word:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .ext_read_word
    loop .ext_read_loop
    pop ecx
    sub ebx, 256
    add dword [ecx], 256
    adc dword [ecx+4], 0
    jmp .read_ext

.ext_last_read:
    cmp ebx, 0
    je .ext_read_done

    mov dx, [base_channel]
    add dx, 2       ;sector count
    mov al, bh
    out dx, al

    inc dx
    mov al, [ecx+3]
    out dx, al

    inc dx
    mov al, [ecx+4]
    out dx, al

    inc dx
    mov al, [ecx+5]
    out dx, al

    mov dx, [base_channel]
    add dx, 2
    mov al, bl
    out dx, al

    inc dx
    mov al, [ecx]
    out dx, al

    inc dx
    mov al, [ecx+1]
    out dx, al

    inc dx
    mov al, [ecx+2]
    out dx, al

    mov dx, si
    mov al, dl

    or al, 0x40         ;Bit 6 - LBA Mode
    mov dx, [base_channel]
    add dx, 6
    out dx, al

    inc dx
    mov al, 0x24        ;read 48bit
    out dx, al

    mov dx, [base_channel]
    add dx, 7
    mov ecx, ebx
.ext_read_loop_last:
    mov dx, [base_channel]
    add dx, 7

    in al, dx
    test al, 0x08
    jz .ext_read_loop_last

    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.ext_read_word_last:
    push ax
    in ax, dx
    stosw
    pop ax
    dec ax
    jnz .ext_read_word_last
    loop .ext_read_loop_last

    mov dx, [base_channel]
    add dx, 7
    in al, dx

    test al, 0x01
    jnz .error
.ext_read_done:
    clc
    ret
.error:
    stc
    ret








write_ide_sectors:
    cmp ebx, 0
    je .error
    cmp ebx, 256        ;loading much sectors doesnt work
    jae .error

    movzx edi, al
    mov [base_channel], dx
    add dx, 7
.wait:
    in al, dx
    test al, 0x80
    jnz .wait

.disk_ready:
    cmp ebx, 256
    jb .last_write

    mov dx, [base_channel]
    add dx, 2            ;sector count
    xor al, al
    out dx, al           ;256 sectors

    inc dx               ;lba bits 0-7
    mov al, cl
    out dx, al

    inc dx               ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    inc dx              ;lba bits 16-23
    out dx, al

    inc dx              ;drive + lba high
    push dx
    mov dx, di
    mov al, dl

    or al, 0xe0
    or al, ah

    pop dx
    out dx, al

    inc dx
    mov al, 0x30        ;write command
    out dx, al
    push ecx
    mov ecx, 256

    mov dx, [base_channel]
    add dx, 7
.write_loop:
    in al, dx
    test al, 0x08
    jz .write_loop

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.write_word:
    push ax
    lodsw
    out dx, ax
    pop ax
    dec ax

    jnz .write_word
    pop dx
    loop .write_loop

    pop ecx
    sub ebx, 256
    add ecx, 256
    jmp .disk_ready

.last_write:
    cmp ebx, 0
    je .write_done

    mov dx, [base_channel]
    add dx, 2           ;sector count
    mov al, bl
    out dx, al

    inc dx              ;lba bits 0-7
    mov al, cl
    out dx, al

    inc dx              ;lba bits 8-15
    mov al, ch
    out dx, al

    mov eax, ecx
    shr eax, 16

    inc dx              ;lba bits 16-23
    out dx, al

    inc dx              ;drive + lba high
    push dx
    mov dx, di
    mov al, dl

    or al, 0xe0
    or al, ah
    pop dx
    out dx, al

    inc dx
    mov al, 0x30        ;write command
    out dx, al

    mov dx, [base_channel]
    add dx, 7
    mov ecx, ebx
.write_loop_last:
    in al, dx
    test al, 0x08
    jz .write_loop_last

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.write_word_last:
    push ax
    lodsw
    out dx, ax
    pop ax

    dec ax
    jnz .write_word_last
    pop dx
    loop .write_loop_last

    mov dx, [base_channel]
    add dx, 7
    in al, dx

    test al, 0x01
    jnz .error

    mov dx, [base_channel]
    add dx, 7
    mov al, 0xe7
    out dx, al
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush
.write_done:
    clc
    ret

.error:
    stc
    ret


write_ide_sectors_ext:
    cmp ebx, 0
    je .error
    cmp ebx, 256
    jae .error

    movzx edi, al
    mov [base_channel], dx
    add dx, 7

.wait:
    in al, dx
    test al, 0x80
    jnz .wait
.ext_write:
    cmp ebx, 256
    jb .ext_last_write

    mov dx, [base_channel]
    add dx, 2       ;sector count
    xor al, al
    out dx, al           ;256 sectors

    inc dx
    mov al, [ecx+3]
    out dx, al

    inc dx
    mov al, [ecx+4]
    out dx, al

    inc dx
    mov al, [ecx+5]
    out dx, al

    mov dx, [base_channel]
    add dx, 2
    mov al, bl
    out dx, al

    inc dx
    mov al, [ecx]
    out dx, al

    inc dx
    mov al, [ecx+1]
    out dx, al

    inc dx
    mov al, [ecx+2]
    out dx, al

    inc dx
    push dx
    mov dx, di
    mov al, dl

    and al, 0x10
    or al, 0x40         ;Bit 6 - LBA Mode
    pop dx
    out dx, al

    inc dx
    mov al, 0x34        ;write 48bit
    out dx, al

    push ecx
    mov ecx, 256
    mov dx, [base_channel]
    add dx, 7
.ext_write_loop:
    in al, dx
    test al, 0x08
    jz .ext_write_loop

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.ext_write_word:
    push ax
    lodsw
    out dx, ax
    pop ax

    dec ax
    jnz .ext_write_word
    pop dx
    loop .ext_write_loop
    pop ecx

    sub ebx, 256
    add dword [ecx], 256
    adc dword [ecx+4], 0
    jmp .ext_write

.ext_last_write:
    cmp ebx, 0
    je .ext_write_done

    mov dx, [base_channel]
    add dx, 2       ;sector count
    mov al, bh
    out dx, al

    inc dx
    mov al, [ecx+3]
    out dx, al

    inc dx
    mov al, [ecx+4]
    out dx, al

    inc dx
    mov al, [ecx+5]
    out dx, al

    mov dx, [base_channel]
    add dx, 2
    mov al, bl
    out dx, al

    inc dx
    mov al, [ecx]
    out dx, al

    inc dx
    mov al, [ecx+1]
    out dx, al

    inc dx
    mov al, [ecx+2]
    out dx, al

    inc dx
    push dx
    mov dx, di
    mov al, dl

    and al, 0x10
    or al, 0x40         ;Bit 6 - LBA Mode
    pop dx
    out dx, al

    mov dx, [base_channel]
    add dx, 7
    mov al, 0x34        ;write 48bit
    out dx, al

    mov ecx, ebx
    mov dx, [base_channel]
    add dx, 7
.ext_write_loop_last:
    in al, dx
    test al, 0x08
    jz .ext_write_loop_last

    push dx
    mov dx, [base_channel]
    mov ax, 256     ;512 bytes
.ext_write_word_last:
    push ax
    mov ax, [esi]
    out dx, ax
    add esi, 2
    pop ax

    dec ax
    jnz .ext_write_word_last
    pop dx
    loop .ext_write_loop_last

    mov dx, [base_channel]
    add dx, 7
    mov al, 0xe7
    out dx, al
.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush
.ext_write_done:
    clc
    ret
.error:
    stc
    ret



;=====================================READ BUSMASTERING DMA============================================
read_ide_dma:
    cmp ebx, 127
    ja .error

    sti
.wait:
    hlt
    cmp byte [ide_running], 1
    je .wait

    cli
    mov [bm_base4], dx          ;base register
    mov [base_channel], si
    movzx esi, al               ;drive

    mov byte [ide_running], 1   ;block IDE controller
    sti

    ;set PRDT
    mov [prdt], edi

    push ax
    push ebx
    xor bh, bh
    mov ax, 512
    mul bx
    mov [prdt+4], ax
    pop ebx
    pop ax

    cmp ah, 2
    je .secondary

    mov dx, [bm_base4]
    add dx, 4
    mov eax, prdt
    out dx, eax

    ;set READ bit
    mov dx, [bm_base4]
    mov al, 0x08        ;READ
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 2
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f

    push ebx
    mov bx, si
    and bl, 0x10
    or al, bl
    pop ebx

    or al, 0xe0
    mov dx, [base_channel]
    add dx, 6
    out dx, al      ;Master + LBA

    mov dx, [base_channel]
    add dx, 2
    mov al, bl           ;sector count
    out dx, al

    inc dx
    mov al, cl
    out dx, al

    inc dx
    mov al, ch
    out dx, al

    shr ecx, 16

    inc dx
    mov al, cl
    out dx, al

    mov dx, [base_channel]
    add dx, 7       ;set command
    mov al, 0xc8    ;read DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    mov al, 0x09
    out dx, al

.end:
    cli
    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    add eax, tasks_esp

    mov dword [eax+11], 0x0000df00      ;set attribute: waiting for drive
    sti
    int 0x20
; .wait_loop:
;     cmp byte [ide_done], 1
;     je .done
;     int 0x20
;     jmp .wait_loop
; .done:
    clc
    ret
.error:
    stc
    ret

.secondary:
    mov dx, [bm_base4]
    add dx, 12
    mov eax, prdt
    out dx, eax

    ;set READ bit
    mov dx, [bm_base4]
    add dx, 8
    mov al, 0x08        ;READ
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 10
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f

    push ebx
    mov bx, si
    and bl, 0x10
    or al, bl
    pop ebx

    or al, 0xe0
    mov dx, [base_channel]
    add dx, 6
    out dx, al      ;Master + LBA

    mov dx, [base_channel]
    add dx, 2
    mov al, bl           ;sector count
    out dx, al

    inc dx
    mov al, cl
    out dx, al

    inc dx
    mov al, ch
    out dx, al

    shr ecx, 16

    inc dx
    mov al, cl
    out dx, al

    mov dx, [base_channel]
    add dx, 7       ;set command
    mov al, 0xc8    ;read DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    add dx, 8
    mov al, 0x09
    out dx, al

    jmp .end

write_ide_dma:
    cmp ebx, 127
    ja .error

    sti
    ;check if a DMA transfer is currently active
.wait:
    hlt
    cmp byte [ide_running], 1
    je .wait

    cli
    mov [bm_base4], dx
    mov [base_channel], si
    movzx esi, al
    mov byte [ide_running], 1   ;block IDE controller
    sti

    ;set PRDT
    mov [prdt], edi

    push ax
    push ebx
    xor bh, bh
    mov ax, 512
    mul bx
    mov [prdt+4], ax
    pop ebx
    pop ax

    cmp ah, 2
    je .secondary

    mov dx, [bm_base4]
    add dx, 4
    mov eax, prdt
    out dx, eax

    ;set WRITE bit
    mov dx, [bm_base4]
    xor al, al
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 2
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f

    push ebx
    mov bx, si
    and bl, 0x10
    or al, bl
    pop ebx

    or al, 0xe0
    mov dx, [base_channel]
    add dx, 6
    out dx, al      ;Master + LBA

    mov dx, [base_channel]
    add dx, 2
    mov al, bl           ;sector count
    out dx, al

    inc dx
    mov al, cl
    out dx, al

    inc dx
    mov al, ch
    out dx, al

    shr ecx, 16

    inc dx
    mov al, cl
    out dx, al

    mov dx, [base_channel]
    add dx, 7       ;set command
    mov al, 0xca    ;write DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    mov al, 0x01    ;write
    out dx, al

    cli
    movzx eax, word [current_task]
    imul eax, TASK_SIZE
    add eax, tasks_esp

    mov dword [eax+11], 0x0000df00      ;set attribute: waiting for drive
    sti
    int 0x20

    clc
    ret

.error:
    stc
    ret

.secondary:
    mov dx, [bm_base4]
    add dx, 12
    mov eax, prdt
    out dx, eax

    ;set WRITE bit
    mov dx, [bm_base4]
    add dx, 8
    xor al, al
    out dx, al

    ;clear status
    mov dx, [bm_base4]
    add dx, 10
    in al, dx
    or al, 0x06
    out dx, al

    mov eax, ecx
    shr eax, 24
    and al, 0x0f

    push ebx
    mov bx, si
    and bl, 0x10
    or al, bl
    pop ebx

    or al, 0xe0
    mov dx, [base_channel]
    add dx, 6
    out dx, al      ;Master + LBA

    mov dx, [base_channel]
    add dx, 2
    mov al, bl           ;sector count
    out dx, al

    inc dx
    mov al, cl
    out dx, al

    inc dx
    mov al, ch
    out dx, al

    shr ecx, 16

    inc dx
    mov al, cl
    out dx, al

    mov dx, [base_channel]
    add dx, 7       ;set command
    mov al, 0xca    ;write DMA 28bit LBA
    out dx, al

    mov dx, [bm_base4]
    add dx, 8
    mov al, 0x01    ;write
    out dx, al

    clc
    ret