;=====================================================================
;RTL8139 (network card) driver
;Copyright (C) 2026 Technodon
;=====================================================================

;Buffers for network card and for ip.obj are always 0x3000 bytes wide
section .text
start:
    jmp short init
    ;magic string
    db 'NET '   ;network card
init:
    test eax, (1 << 0)
    jnz .use_io

    mov byte [mmio], 1
    and eax, 0xfffffffe
    mov [mmio_addr], eax

.use_io:
    and ax, 0xfffe
    mov [io_port], ax

    ;power card on
    xor al, al
    mov ebx, 0x52
    call write8

    ;software reset to clear buffers and registers
    mov al, 0x10
    mov ebx, 0x37
    call write8

.wait_reset:
    mov ebx, 0x37
    call read8
    and al, 0x10
    cmp al, 0
    jne .wait_reset

    mov ecx, 0x2000+16
    mov ah, 0x0a
    int 0x35
    mov [buffer_addr], esi

    ;initialize multicast registers
    xor eax, eax
    mov ebx, 0x08
    call write32
    xor eax, eax
    mov ebx, 0x0c
    call write32

    ;send address of receive buffer start location
    mov eax, esi
    mov ebx, 0x30
    call write32

    ;mark buffer as 8kib+16 bytes wide
    mov ebx, 0x44
    call read32

    and eax, ~(1 << 11)
    and eax, ~(1 << 12)

    or eax, (7 << 8)
    or eax, (7 << 13)   ;set max. DMA Burst size to unlimited

    mov al, 0x0a        ;Accept Broadcast and Acceppt Physical Match
    or al, (1 << 7)
    mov ebx, 0x44
    call write32

    ;init CAPR register
    mov ax, 0xfff0
    mov ebx, 0x38
    call write16

    mov ax, 5       ;set TOK and ROK bits
    mov ebx, 0x3c
    call write16
    mov ax, 0xffff  ;write one to clear
    mov ebx, 0x3e
    call write16

    mov al, 0x0c    ;set RE (receiver enabled) and TE (transmitter enabled) bits
    mov ebx, 0x37
    call write8

    mov ah, 0x0a
    mov ecx, 0x3000
    int 0x35

    mov [destination_buffer_addr], esi
    mov [current_buffer_addr], esi
    mov [copy_addr], esi

    mov edi, esi
    xor eax, eax
    mov ecx, 0x3000/4
    rep stosd

    ;read MAC address
    xor ebx, ebx
    call read8
    mov [mac_addr], al

    mov ebx, 1
    call read8
    mov [mac_addr+1], al

    mov ebx, 2
    call read8
    mov [mac_addr+2], al

    mov ebx, 3
    call read8
    mov [mac_addr+3], al

    mov ebx, 4
    call read8
    mov [mac_addr+4], al

    mov ebx, 5
    call read8
    mov [mac_addr+5], al

    mov esi, mac_addr

    ;call get_ip_addr

    mov edi, kernel_packet+32
    mov esi, mac_addr
    mov ecx, 6
    rep movsb

    mov edx, kernel_packet
    mov edi, interrupt_handler
    mov [edx+4], edi
    mov edi, transmit_packet
    mov [edx], edi
    mov edi, packet_size
    mov [edx+42], edi

    mov edi, transmit_error_count
    mov [edx+12], edi
    mov edi, transmit_success_count
    mov [edx+16], edi
    mov edi, receive_error_count
    mov [edx+20], edi
    mov edi, receive_success_count
    mov [edx+24], edi

    xor ah, ah  ;error code = 0
    ret



;#################### FUNCTIONS ####################
write8:
    ;AL = byte to write;EBX = Offset
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    out dx, al
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov [edx], al
    pop edx

    ret

write16:
;AX = word to write
;EBX = Offset
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    out dx, ax
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov [edx], ax
    pop edx

    ret

write32:
    ;EAX = dword to write
    ;EBX = Offset
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    out dx, eax
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov [edx], eax
    pop edx

    ret

read8:
    ;EBX = Offset
    ;Output: EAX
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    in al, dx
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov al, [edx]
    pop edx

    ret

read16:
    ;EBX = Offset
    ;Output: EAX
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    in ax, dx
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov ax, [edx]
    pop edx

    ret

read32:
    ;EBX = Offset
    ;Output: EAX
    cmp byte [mmio], 1
    je .use_mmio

    push edx
    movzx edx, word [io_port]
    add edx, ebx
    in eax, dx
    pop edx

    ret

.use_mmio:
    push edx
    mov edx, [mmio_addr]
    add edx, ebx
    mov eax, [edx]
    pop edx

    ret

;##################### SEND PACKETS #####################
transmit_packet:
    ;EAX = size (max. 1792)
    ;EDI = physical address of packet to transmit
    cli
    pusha
    cmp eax, 1792
    ja .error

    mov ecx, eax

    mov ebx, 0x58
    call read8
    test al, (1 << 2)       ;link bad (bit 2) is set, that means there is no physical ethernet cabel connection
    jnz .error

    mov eax, ecx

    movzx ebx, byte [current_tx]
    imul ebx, REG_OFFSET
    add ebx, TX_REG_START

    push eax
    mov eax, edi
    call write32
    pop eax

    movzx ebx, byte [current_tx]
    imul ebx, REG_OFFSET
    add ebx, TX_REG_STATUS

    and eax, ~(1 << 13)
    call write32

    inc byte [current_tx]
    cmp byte [current_tx], 4
    jb .skip

    mov byte [current_tx], 0

.skip:
    popa
    sti
    clc
    ret
.error:
    popa
    sti
    stc
    ret

get_mac_addr:
    ;EDX = IPv4 addr
    pusha
    mov ecx, 64
    mov ah, 0x0a
    int 0x35

    push esi
    push ecx

    ;header
    mov dword [esi], 0xffffffff     ;destination MAC address
    mov word [esi+4], 0xffff        ;destination MAC address
    mov eax, [mac_addr]
    mov [esi+6], eax                ;source MAC address
    mov ax, [mac_addr+4]
    mov [esi+10], ax                ;source MAC address

    mov eax, 0x0806
    call swap
    mov [esi+12], ax                ;ARP-Packet

    ;ARP data
    mov word [esi+14], 0x0100            ;hardware type: ethernet (0x0001 but big endian)
    mov word [esi+16], 0x0008            ;protocol type: IPv4 (0x0800 but big endian)

    mov byte [esi+18], 0x06
    mov byte [esi+19], 0x04
    mov word [esi+20], 0x0100            ;request
    mov al, [mac_addr]
    mov [esi+22], al
    mov al, [mac_addr+1]
    mov [esi+23], al
    mov al, [mac_addr+2]
    mov [esi+24], al
    mov al, [mac_addr+3]
    mov [esi+25], al
    mov al, [mac_addr+4]
    mov [esi+26], al
    mov al, [mac_addr+5]
    mov [esi+27], al

    popa
    ret

;############################## INTERRUPT HANDLER ##############################
interrupt_handler:
    pusha
    mov ebx, 0x3e
    call read16
    test ax, ax
    jz .done    ;shared IRQ



    test ax, (1 << 0)
    jz .packet_received_err

    call handle_received_packet
.packet_received_err:
    test ax, (1 << 1)
    jz .transmit_ok

    call handle_receive_err

.transmit_ok:
    test ax, (1 << 2)
    jz .transmit_error

    call transmit_okay

.transmit_error:
    test ax, (1 << 3)
    jz .buffer_overflow

    call handle_transmit_error

.buffer_overflow:
    test ax, (1 << 4)
    jz .done

    call handle_buffer_overflow

.done:

    mov ebx, 0x3e
    call write16
    popa
    ret

handle_received_packet:
    push eax
    xor ecx, ecx
    mov ebx, 0x38
    call read16

    add ax, 16
    movzx edx, ax
    mov edi, [buffer_addr]
    add edi, edx

    mov esi, edi
    add esi, 4      ;skip status bits and buffer size
    movzx ecx, word [edi+2]
    call copy_buffer

    movzx ecx, word [edi+2]
    add edx, ecx
    add dx, 4

    add edx, 3
    and edx, 0xfffffffc

    cmp dx, 0x2000
    jb .skip

    sub dx, 0x2000

.skip:
    sub edx, 16
    mov ax, dx

    mov ebx, 0x38
    call write16
    pop eax


    inc dword [receive_success_count]
    mov edx, [receive_success_count]
    mov edi, kernel_packet
    mov [edi+24], edx

    ret

handle_receive_err:
    push eax
    mov ebx, 0x38
    call read16

    add ax, 16
    movzx edx, ax
    mov edi, [buffer_addr]
    add edi, edx
    mov dx, [edi+2]
    add dx, ax
    add dx, 4
    cmp dx, 0x2000+16
    jb .skip

    sub dx, 0x2000

.skip:
    sub dx, 16
    mov ax, dx

    mov ebx, 0x38
    call write16
    pop eax

    inc dword [receive_error_count]
    mov edx, [receive_error_count]
    mov edi, kernel_packet
    mov [edi+20], edx
    ret

transmit_okay:
    inc dword [transmit_success_count]
    mov edx, [transmit_success_count]
    mov edi, kernel_packet
    mov [edi+16], edx
    ret

handle_buffer_overflow:
    push eax
    mov ebx, 0x37
    call read8

    and al, ~(1 << 3)   ;clear receiver enable bit

    ;read buffer...

    mov ebx, 0x3e
    call read16

    or ax, (1 << 4)
    call write16

    mov ebx, 0x37
    call read8
    or al, (1 << 3)     ;set receiver enable bit again
    pop eax
    ret

handle_transmit_error:
    push eax
    mov ebx, 0x10
    call read32
    or eax, (1 << 13) ;set own bitcall write32

    mov ebx, 0x14
    call read32
    or eax, (1 << 13) ;set own bit
    call write32

    mov ebx, 0x18
    call read32
    or eax, (1 << 13) ;set own bit
    call write32

    mov ebx, 0x1c
    call read32
    or eax, (1 << 13) ;set own bit
    call write32

    inc dword [transmit_error_count]
    mov edx, [transmit_error_count]
    mov edi, kernel_packet
    mov [edi+12], edx
    pop eax
    ret

swap:
    ;swap bytes in EAX
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

change_mac:
    ;EAX = bytes 0-3 (big endian!)
    ;BX = bytes 4 and 5 (big endian!)
    push ecx
    push ebx
    mov ecx, 3

    xor ebx, ebx
    call write8

.loop:
    shr eax, 8
    add ebx, 4
    call write8
    dec ecx
    jnz .loop

    pop ebx
    mov ax, bx
    mov ebx, 16
    call write8

    shr ax, 8
    add ebx, 4
    call write8

    pop ecx
    clc
    ret

copy_buffer:
    ;ESI = pointer to packet
    ;ECX = size of packet in bytes
    pusha

    mov [packet_size], cx
    mov edi, [current_buffer_addr]
    cmp edi, dword [copy_addr]
    jne .wait

.copy:
    push ecx
    rep movsb
    pop ecx

    mov eax, [destination_buffer_addr]
    add eax, 0x2000

    add ecx, dword [current_buffer_addr]
    mov [current_buffer_addr], ecx

    cmp ecx, eax
    jb .skip

    mov eax, [destination_buffer_addr]
    mov dword [current_buffer_addr], eax

.skip:
    popa
    ret


.wait:
    hlt
    cmp edi, dword [copy_addr]
    jne .wait

    jmp .copy


section .data
mmio: db 0      ;0 = card uses IO ports, 1 = card uses MMIO
mmio_addr: dd 0
io_port: dw 0
buffer_addr: dd 0
buffer_off: dd 0

REG_OFFSET      equ 4
current_tx: db 0
TX_REG_STATUS   equ 0x10
TX_REG_START    equ 0x20
destination_buffer_addr: dd 0
current_buffer_addr: dd 0
packet_size: dw 0

kernel_packet:
    dd 0        ;transmit_packet()
    dd 0        ;interrupt handler()

    dd 0

    dd 0        ;transmit_error_count
    dd 0        ;transmit_success_count

    dd 0        ;receive_error_count
    dd 0        ;receive_success_count

    dd 0        ;buffer address
    times 3 dw 0    ;mac address

    copy_addr: dd 0
    dd 0        ;packet_size

transmit_error_count: dd 0
transmit_success_count: dd 0
receive_error_count: dd 0
receive_success_count: dd 0
carp_offset: dw 0

snd: db 0

mac_addr:
    dd 0
    dw 0
ip_addr: dd 0
