;===========================================================================================
;driver for Floppy Disc Controller
;Copyright (C) 2026 Technodon
;===========================================================================================

section .text
start:
    mov [stack], esp

    ;check if a FDC exists
    mov dx, 0x3f4
    in al, dx
    cmp al, 0xff
    je .error
    cmp al, 0
    je .error

    mov ah, 0x22
    mov al, 2
    mov ebx, timer
    mov edx, 40
    int 0x35

    mov dx, 0x3f4
.wait_fdc:
    in al, dx
    and al, 0xc0
    test al, 0x80
    jnz .fdc_ready

    cmp dword [ebx], 40
    jb .wait_fdc
    jmp .error

.fdc_ready:
    mov dx, 0x3f5
    mov al, 0x10
    out dx, al

    in al, 0x80
    in al, 0x80
    in al, 0x80
    in al, 0x80

    in al, dx
    test al, 0x80

    jz .error

    ;reset FDC
    xor al, al
    mov dx, 0x3f2
    out dx, al

    mov al, 0x0c    ;set Reset-Bit (bit 2) and DMA & Interrupt Enable bit to 1
    out dx, al

    ;quit sense interrupt
    mov ecx, 4
.quit_interrupts:
    mov dx, 0x3f5
    mov al, 0x08
    out dx, al

    ;read status bytes
    in al, dx
    in al, dx

    dec ecx
    jnz .quit_interrupts

    ;specify parameters
    mov al, 0x03
    out dx, al

    ;bits 4-7: step rate time
    ;bits 0-3: head unload time

    mov al, 0xdf
    out dx, al

    ;bits 1-7: head load time
    ;bit 0: 0 = DMA mode, 1 = PIO mode

    mov al, 0x02
    out dx, al

    ;get number of connected floppy drives
    mov dx, 0x70
    mov al, 0x10
    out dx, al

    mov dx, 0x71
    in al, dx

    mov ah, al
    shr al, 4       ;AL = bits 4-7 (A:)
    and ah, 0x0f    ;AH = bits 0-3 (B:)

    mov [kernel_packet+12], al
    mov [kernel_packet+14], ah

    ;calibrate drives
    push ax
    cmp al, 0
    je .drive_b

    mov dx, 0x3f2
    mov al, 0x1c
    out dx, al

    ;wait for the motor to spin up
    mov ah, 0x22
    mov al, 1
    mov ebx, 500    ;sleep 500ms
    int 0x35

.drive_b:
    pop ax
    push ax
    cmp ah, 0
    je .done_spin_motor

    mov dx, 0x3f2
    mov al, 0x2d
    out dx, al

    ;wait for the motor to spin up
    mov ah, 0x22
    mov al, 1
    mov ebx, 500    ;sleep 500ms
    int 0x35

.done_spin_motor:
    pop ax
    push ax

    cmp al, 0
    je .calibrate_b

    ;select drive 0 (A:)
    mov dx, 0x3f2
    mov al, 0x1c
    out dx, al

.retry_a2:
    cmp byte [retry], 2
    jae .calibrate_b

    mov dx, 0x3f5
    mov al, 0x07
    out dx, al

    xor al, al  ;drive 0 (A:)
    out dx, al

    ;wait for status bytes
    mov dx, 0x3f4
.wait_loop:
    in al, dx
    and al, 0xc0
    cmp al, 0x80
    jne .wait_loop

    inc byte [retry]

    mov dx, 0x3f5
    mov al, 0x08
    out dx, al
    in al, dx
    in al, dx
    cmp al, 0
    jne .retry_a2

    ;shut motor off
    mov dx, 0x3f2
    mov al, 0x0c
    out dx, al

.calibrate_b:
    pop ax
    mov byte [retry], 0

    cmp ah, 0
    je .done_calibrate

    ;select drive 1 (B:)
    mov dx, 0x3f2
    mov al, 0x2d
    out dx, al

.retry_b2:
    cmp byte [retry], 2
    jae .done_calibrate

    mov dx, 0x3f5
    mov al, 0x07
    out dx, al

    mov al, 1    ;drive 1 (B:)
    out dx, al

    ;wait for status bytes
    mov dx, 0x3f4
.wait_loop2:
    in al, dx
    and al, 0xc0
    cmp al, 0x80
    jne .wait_loop2

    inc byte [retry]

    mov dx, 0x3f5
    mov al, 0x08
    out dx, al
    in al, dx
    in al, dx
    cmp al, 0
    jne .retry_b2

    ;shut motor off
    mov dx, 0x3f2
    mov al, 0x0d
    out dx, al

.done_calibrate:
    mov edx, kernel_packet
    mov dword [edx], read_sectors
    mov dword [edx+4], write_sectors
    mov dword [edx+8], fdc_handler

    xor ah, ah
    ret

.error:
    mov esp, [stack]
    mov ah, 0x01
    ret


read_sectors:
    ;BL = drive number (0x00 or 0x01)
    ;BH = floppy type
    ;EDI = address
    ;AX = number of 512B sectors
    ;CX = LBA

    pusha
    cli

    cmp bl, 2
    jae .error2
    cmp bh, 5
    ja .error2
    cmp bh, 0
    je .error2

    sti
    jmp .wait
.error2:
    mov byte [fd_running], 0
    popa
    sti
    stc
    ret

.wait:
    hlt
    cmp byte [fd_running], 1
    je .wait

    cli
    mov byte [fd_running], 1
    sti

    mov [lba], cx
    mov [flp_type], bh

    movzx ecx, ax

    push cx
    mov cl, bl
    or bl, (1 << 2) ;set reset bit
    or bl, (1 << 3) ;allow DMA and IRQs

    mov bh, (1 << 4)
    shl bh, cl
    or bl, bh
    mov bh, cl
    pop cx

    ;turn motor on
    mov al, bl
    mov dx, 0x3f2
    out dx, al

    ;wait for the motor to spin up
    push ebx
    mov ah, 0x22
    mov al, 1
    mov ebx, 500    ;sleep 500ms
    int 0x35
    pop ebx

    mov byte [calibrate_done], 0

    ;recalibrate
    mov dx, 0x3f5
    mov al, 0x07
    out dx, al

    mov al, bh  ;drive number
    out dx, al

.loop:
    int 0x20
    cmp byte [calibrate_done], 1
    jne .loop

    ;read status bytes
    in al, dx
    in al, dx
    cmp al, 0
    jne .error

    ;reset flip-flop register of DMA controller
    xor al, al
    out 0x0c, al        ;write any byte to port 0x0C to reset byte-pointer

    ;set mode byte
    ;bits 0-1: channel select (0-3)
    ;bits 2-3: transfer type (0b10 = Write Transfer, 0b01: Read Transfer)
    ;bit 4: autoinitialize (repeats transfer again and again)
    ;bit 5: address increment/decrement (0 = memory address increments, 1 = memory address decrements)
    ;bits 6-7: mode select 
    mov al, 0x46
    out 0x0b, al

    ;request heap from low memory area
    push ecx
    mov ecx, 0xffff
    mov ah, 0x0c
    int 0x35
    pop ecx
    jc .error

    mov [num_sectors], cx
    
    mov eax, esi
    out 0x04, al
    mov al, ah
    out 0x04, al

    shr eax, 16
    out 0x81, al

    mov byte [error], 0

    ;get CHS values
    cmp byte [flp_type], 1
    je .flp1
    cmp byte [flp_type], 2
    je .flp2
    cmp byte [flp_type], 3
    je .flp3
    cmp byte [flp_type], 4
    je .flp4
    cmp byte [flp_type], 5
    je .flp5
    jmp .error
.flp1:
    mov word [sectors_per_track], 9
    mov word [num_heads], 2
    mov word [cylinders], 40
    
    mov dx, 0x3f7
    mov al, 1   ;300kbps
    out dx, al

    jmp .continue
.flp2:
    mov word [sectors_per_track], 15
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 1   ;300kbps
    out dx, al

    jmp .continue
.flp3:
    mov word [sectors_per_track], 9
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 2   ;250kbps
    out dx, al
    jmp .continue
.flp4:
    mov word [sectors_per_track], 18
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    xor al, al      ;500kbps
    out dx, al

    jmp .continue
.flp5:
    mov word [sectors_per_track], 36
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 0x03    ;1Mbps
    out dx, al
.continue:
    cmp byte [error], 2
    ja .error

    mov ax, [lba]
    call lba_to_chs

    mov ax, [sectors_per_track]
    movzx dx, byte [absolute_sector]
    sub ax, dx
    inc ax

    cmp ax, word [num_sectors]
    jb .read_all

    mov ax, [num_sectors]
.read_all:

    mov bp, ax
    imul ax, 512
    dec ax

    out 0x05, al
    mov al, ah
    out 0x05, al

    ;unmask DMA channel
    ;bits 0-1: channel number
    ;bit2: 0 = active, 1 = masked

    mov al, 0x02
    out 0x0a, al

    call fdc_wait_ready
    mov dx, 0x3f5
    mov al, 0x46    ;READ DATA
    out dx, al     ;send command byte

    call fdc_wait_ready
    mov al, bh       ;bits 0-1: drive number
    mov ah, [absolute_head]
    shl ah, 2
    or al, ah
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_track]
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_head]
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_sector]
    out dx, al

    call fdc_wait_ready
    mov al, 0x02        ;sector size: 128 x 2² = 512
    out dx, al

    call fdc_wait_ready
    movzx ax, byte [absolute_sector]
    add ax, bp
    out dx, al

    call fdc_wait_ready
    mov al, 0x1b
    cmp byte [flp_type], 2
    ja .skip
    mov al, 0x2a
.skip:
    out dx, al

    ;data length (if sector size is set, send 0xff)
    call fdc_wait_ready
    cli
    mov al, 0xff
    out dx, al

    ;get current PID
    mov ah, 0x08
    int 0x35
    mov [task], ax

    ;put the task to sleep
    mov ah, 0x07
    mov al, 1
    int 0x35

    mov byte [current_command], 1
    sti

    int 0x20
    cmp byte [error], 1
    jae .continue


    movzx ecx, bp
    imul ecx, 512
    mov eax, ecx
    shr ecx, 2      ;/4

    push esi
    rep movsd
    pop esi


    add word [lba], bp

    mov ax, [num_sectors]
    sub ax, bp
    cmp ax, 0
    je .done

    jmp .continue
.done:
    ;free heap
    mov ecx, 0xffff
    mov ah, 0x0d
    int 0x35

    mov al, bh
    or al, (1 << 2) | (1 << 3)  ;reset bit & DMA/IRQ bit = 1
    mov dx, 0x3f2
    out dx, al

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35
    mov byte [fd_running], 0
    popa
    clc
    ret

.error:
    mov ecx, 0xffff
    mov ah, 0x0d
    int 0x35

    mov al, bh
    or al, (1 << 2) | (1 << 3)  ;reset bit & DMA/IRQ bit = 1
    mov dx, 0x3f2
    out dx, al

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35
    mov byte [fd_running], 0

    popa
    stc
    ret

write_sectors:
    ;BL = drive number (0x00 or 0x01)
    ;BH = floppy type
    ;ESI = address
    ;AX = number of 512B sectors
    ;CX = LBA

    pusha
    cli

    cmp bl, 2
    jae .error2
    cmp bh, 5
    ja .error2
    cmp bh, 0
    je .error2

    sti
    jmp .wait

.error2:
    mov byte [fd_running], 0
    popa
    sti
    stc
    ret

.wait:
    hlt
    cmp byte [fd_running], 1
    je .wait

    cli
    mov byte [fd_running], 1
    sti

    mov [lba], cx
    mov [flp_type], bh

    movzx ecx, ax

    push cx
    mov cl, bl
    or bl, (1 << 2) ;set reset bit
    or bl, (1 << 3) ;allow DMA and IRQs

    mov bh, (1 << 4)
    shl bh, cl
    or bl, bh
    mov bh, cl
    pop cx

    ;turn motor on
    mov al, bl
    mov dx, 0x3f2
    out dx, al

    ;wait for the motor to spin up
    push ebx
    mov ah, 0x22
    mov al, 1
    mov ebx, 500    ;sleep 500ms
    int 0x35
    pop ebx

    mov byte [calibrate_done], 0

    ;recalibrate
    mov dx, 0x3f5
    mov al, 0x07
    out dx, al

    mov al, bh  ;drive number
    out dx, al

.loop:
    int 0x20
    cmp byte [calibrate_done], 1
    jne .loop

    ;read status bytes
    in al, dx
    in al, dx
    cmp al, 0
    jne .error2

    ;reset flip-flop register of DMA controller
    xor al, al
    out 0x0c, al        ;write any byte to port 0x0C to reset byte-pointer

    ;set mode byte
    ;bits 0-1: channel select (0-3)
    ;bits 2-3: transfer type (0b10 = Write Transfer, 0b01: Read Transfer)
    ;bit 4: autoinitialize (repeats transfer again and again)
    ;bit 5: address increment/decrement (0 = memory address increments, 1 = memory address decrements)
    ;bits 6-7: mode select 
    mov al, 0x4A
    out 0x0b, al

    ;request heap from low memory area
    push ecx
    push esi
    mov ecx, 0xffff
    mov ah, 0x0c
    int 0x35
    mov edi, esi
    pop esi
    pop ecx
    jc .error2

    mov [num_sectors], cx
    
    mov eax, edi
    out 0x04, al
    mov al, ah
    out 0x04, al

    shr eax, 16
    out 0x81, al

    mov byte [error], 0

    ;get CHS values
    cmp byte [flp_type], 1
    je .flp1
    cmp byte [flp_type], 2
    je .flp2
    cmp byte [flp_type], 3
    je .flp3
    cmp byte [flp_type], 4
    je .flp4
    cmp byte [flp_type], 5
    je .flp5
    jmp .error
.flp1:
    mov word [sectors_per_track], 9
    mov word [num_heads], 2
    mov word [cylinders], 40
    
    mov dx, 0x3f7
    mov al, 1   ;300kbps
    out dx, al

    jmp .continue
.flp2:
    mov word [sectors_per_track], 15
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 1   ;300kbps
    out dx, al

    jmp .continue
.flp3:
    mov word [sectors_per_track], 9
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 2   ;250kbps
    out dx, al
    jmp .continue
.flp4:
    mov word [sectors_per_track], 18
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    xor al, al      ;500kbps
    out dx, al

    jmp .continue
.flp5:
    mov word [sectors_per_track], 36
    mov word [num_heads], 2
    mov word [cylinders], 80

    mov dx, 0x3f7
    mov al, 0x03    ;1Mbps
    out dx, al
.continue:
    cmp byte [error], 2
    ja .error

    mov ax, [lba]
    call lba_to_chs

    mov ax, [sectors_per_track]
    movzx dx, byte [absolute_sector]
    sub ax, dx
    inc ax

    cmp ax, word [num_sectors]
    jb .read_all

    mov ax, [num_sectors]
.read_all:

    mov bp, ax
    imul ax, 512
    dec ax

    out 0x05, al
    mov al, ah
    out 0x05, al

    ;unmask DMA channel
    ;bits 0-1: channel number
    ;bit2: 0 = active, 1 = masked

    mov al, 0x02
    out 0x0a, al

    ;copy data into DMA buffer
    movzx ecx, bp
    imul ecx, 512
    mov eax, ecx
    shr ecx, 2      ;/4

    push edi
    rep movsd
    pop edi

    call fdc_wait_ready
    mov dx, 0x3f5
    mov al, 0x45    ;WRITE DATA
    out dx, al     ;send command byte

    call fdc_wait_ready
    mov al, bh       ;bits 0-1: drive number
    mov ah, [absolute_head]
    shl ah, 2
    or al, ah
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_track]
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_head]
    out dx, al

    call fdc_wait_ready
    mov al, [absolute_sector]
    out dx, al

    call fdc_wait_ready
    mov al, 0x02        ;sector size: 128 x 2² = 512
    out dx, al

    call fdc_wait_ready
    movzx ax, byte [absolute_sector]
    add ax, bp
    out dx, al

    call fdc_wait_ready
    mov al, 0x1b
    cmp byte [flp_type], 2
    ja .skip
    mov al, 0x2a
.skip:
    out dx, al

    ;data length (if sector size is set, send 0xff)
    call fdc_wait_ready
    cli
    mov al, 0xff
    out dx, al

    ;get current PID
    mov ah, 0x08
    int 0x35
    mov [task], ax

    ;put the task to sleep
    mov ah, 0x07
    mov al, 1
    int 0x35

    mov byte [current_command], 1
    sti

    int 0x20
    cmp byte [error], 1
    jae .continue


    add word [lba], bp

    mov ax, [num_sectors]
    sub ax, bp
    cmp ax, 0
    je .done

    jmp .continue
.done:
    ;free heap
    mov ecx, 0xffff
    mov ah, 0x0d
    int 0x35

    mov al, bh
    or al, (1 << 2) | (1 << 3)  ;reset bit & DMA/IRQ bit = 1
    mov dx, 0x3f2
    out dx, al

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35
    mov byte [fd_running], 0
    popa
    clc
    ret

.error:
    mov ecx, 0xffff
    mov ah, 0x0d
    int 0x35

    mov al, bh
    or al, (1 << 2) | (1 << 3)  ;reset bit & DMA/IRQ bit = 1
    mov dx, 0x3f2
    out dx, al

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35
    mov byte [fd_running], 0

    popa
    stc
    ret

fdc_wait_ready:
    push edx
    push eax

    mov dx, 0x3f4
.wait_ready:
    in al, dx
    and al, 0xc0
    cmp al, 0x80
    jne .wait_ready

    pop eax
    pop edx
    ret

lba_to_chs:
    ;AX = LBA
    xor edx, edx
    div word [sectors_per_track]
    inc dl
    mov byte [absolute_sector], dl
    xor edx, edx
    div word [num_heads]
    mov byte [absolute_head], dl
    mov word [absolute_track], ax
    ret
;#########################################################################################
;################################## INTERRUPT HANDLER ####################################
;#########################################################################################

fdc_handler:
    pusha

    cmp byte [current_command], 0
    je .recalibrate
    cmp byte [current_command], 1
    je .read_write
    jmp .done

.read_write:
    mov dx, 0x3f5
    in al, dx
    mov ah, al

    in al, dx
    mov bl, al
    in al, dx
    mov bh, al

    in al, dx
    in al, dx
    in al, dx
    in al, dx

    mov byte [current_command], 0

    cli
    push ax
    push bx
    mov ah, 0x07
    mov al, 0x80
    mov bx, [task]
    int 0x35
    pop bx
    pop ax

    test ah, 0x80
    jnz .error
    test ah, 0x40
    jnz .error
    mov byte [error], 0
    jmp .done
.recalibrate:
    mov byte [calibrate_done], 1

    ;send Sense Interrupt
    mov dx, 0x3f5
    mov al, 0x08
    out dx, al

.done:
    mov al, 0x20
    out 0x20, al
    popa
    iret

.error:
    cmp bl, 0
    je .set_data_rate
    inc byte [error]
    jmp .done

.set_data_rate:
    mov dx, 0x3f7
    xor al, al  ;set data rate for 1440KB floppy disk
    out dx, al

    inc byte [error]
    jmp .done

section .data
kernel_packet:
    dd 0        ;*read_sectors()
    dd 0        ;*write_sectors()

    dd 0        ;*fdc_handler()

    ;drive A:
    db 0        ;floppy type
    db 0        ;drive number (0x00)

    ;drive B:
    db 0        ;floppy type
    db 1        ;drive number (0x01)

;floppy types:
;0x00: no drive
;0x01: 360 KB 5.25 Drive
;0x02: 1.2 MB 5.25 Drive
;0x03: 720 KB 3.5 Drive
;0x04: 1.44 MB 3.5 Drive
;0x05: 2.88 MB 3.5 drive


;floppy drive entry:
;QWORD: 0
;BYTE: floppy drive type
;BYTE: 0xFD
;BYTE: drive number (0x00, 0x01)

stack: dd 0
retry: db 0
timer: dd 0

fd_running: db 0
calibrate_done: db 0
lba: dw 0
flp_type: db 0
num_sectors: dw 0

num_heads: dw 0
sectors_per_track: dw 0
cylinders: dw 0

absolute_sector: db 0
absolute_head: db 0
absolute_track: dw 0

error: db 0
task: dw 0

current_command: db 0