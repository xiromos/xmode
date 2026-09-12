;============================================================================================
;Program that sends a DHCP request to the router to ask for an IP address
;Copyright (C) 2026 Technodon
;============================================================================================

section .text
start:
    mov ah, 0x0a
    mov ecx, 0x2000
    int 0x35

    mov [heap], esi

    mov ah, 0x21    ;network functions
    mov al, 0x02    ;open socket
    xor bh, bh      ;IPv4
    mov bl, 3       ;UDP
    mov dx, 68
    int 0x35
    jc error

.dora:
    movzx ebx, cx
    shl ebx, 16

    push cx

    mov ah, 0x21
    mov al, 0x03
    mov bx, 67
    mov edx, 0xffffffff
    mov esi, ip_packet
    mov ecx, 244
    int 0x35

    pop cx
    push cx
.wait:
    ;wait for packet
    mov ah, 0x21
    mov al, 0x04
    int 0x35
    ;jc .timed_out

    call check_packet
    jc .wait

    mov esi, [net_interface]
    mov edx, [ip_addr]
    mov [esi], edx      ;store IPv4 address in big endian format
    mov edx, [dns]
    mov [esi+4], edx
    mov edx, [gateway]
    mov [esi+8], edx
    mov edx, [subnet_mask]
    mov [esi+60], edx

    call print_configs
    pop cx
    push cx

    movzx ebx, cx
    shl ebx, 16

    mov ah, 0x21
    mov al, 0x03
    ; mov bx, [router_port]
    ; mov edx, [router_ip]
    mov bx, 67
    mov edx, 0xffffffff

    mov esi, ip_packet
    mov dword [esi+4], 'DHCP'   ;xid
    mov byte [esi+236], 99
    mov byte [esi+237], 130
    mov byte [esi+238], 83
    mov byte [esi+239], 99
    mov byte [esi+240], 53  ;option 53
    mov byte [esi+241], 1   ;length
    mov byte [esi+242], 3   ;message type
    mov byte [esi+243], 50  ;option 50
    mov byte [esi+244], 4   ;length
    mov edx, [ip_addr]
    mov [esi+245], edx
    mov byte [esi+249], 54
    mov byte [esi+250], 4
    mov edx, [gateway]
    mov [esi+251], edx
    mov byte [esi+255], 0xff
    mov ecx, 256
    int 0x35

    pop cx
    push cx
.wait2:
    mov ah, 0x21
    mov al, 0x04
    int 0x35

    call check_packet2
    jc .check_error

    pop cx

    ;close socket
    mov ah, 0x21
    mov al, 0x05
    int 0x35
    
    mov ecx, 0x2000
    mov esi, [heap]

    mov ah, 0x0b
    int 0x35

    mov ah, 0x05
    int 0x35

    ret

.check_error:
    pop cx

    cmp ah, 0
    je .wait2

    mov esi, ip_packet
    mov word [esi], 0x0101
    mov byte [esi+2], 6
    mov dword [esi+4], 'DHCP'
    mov word [esi+8], 0
    mov word [esi+10], 0x0080
    mov dword [esi+12], 0
    mov dword [esi+16], 0
    mov dword [esi+20], 0
    mov dword [esi+24], 0
    mov dword [esi+28], 0
    mov word [esi+32], 0
    mov byte [esi+236], 0x63
    mov byte [esi+237], 0x82
    mov byte [esi+238], 0x53
    mov byte [esi+239], 0x63
    mov byte [esi+240], 53
    mov word [esi+241], 0x0101
    mov byte [esi+243], 0xff

    jmp .dora

.timed_out:
    cmp byte [time_out], 1
    je .error

    mov esi, timed_out_str
    mov ebx, 0x00ffffff
    mov ah, 0x01
    int 0x30

    pop cx
    mov byte [time_out], 1
    jmp .dora

.error:
    pop cx

    ;close socket
    mov ah, 0x21
    mov al, 0x05
    int 0x35
    
    mov ecx, 0x2000
    mov esi, [heap]

    mov ah, 0x0b
    int 0x35

    mov ah, 0x05
    int 0x35

    ret
check_packet:
    mov esi, [heap]
    mov edx, [esi]
    mov [router_ip], edx
    mov dx, [esi+4]
    mov [router_port], dx
    add esi, 12

    cmp byte [esi], 2   ;message type: boot reply
    jne .error
    
    cmp dword [esi+4], 'DHCP'
    jne .error

    mov edx, [esi+16]   ;Your IP Address (big endian)
    mov [ip_addr], edx
    mov edx, [esi+24]   ;Gateway
    mov [giaddr], edx

    add esi, 236+4      ;after magic cookie

.loop:
    lodsb
    cmp al, 0
    je .loop
    cmp al, 0xff
    je .done

    cmp al, 0x01
    je .subnet_mask
    cmp al, 0x06
    je .dns
    cmp al, 0x33
    je .lease_time
    cmp al, 0x03
    je .gateway

    lodsb
    movzx ecx, al
    add esi, ecx
    jmp .loop
.done:
    clc
    ret
.subnet_mask:
    lodsb
    movzx ecx, al
    mov edi, subnet_mask
    rep movsb
    jmp .loop
.dns:
    lodsb
    movzx ecx, al
    mov edi, dns
    rep movsb
    jmp .loop
.lease_time:
    lodsb
    movzx ecx, al
    mov edi, lease_time
    rep movsb
    jmp .loop
.gateway:
    lodsb
    movzx ecx, al
    mov edi, gateway
    rep movsb
    jmp .loop
.error:
    stc
    ret
print_configs:
    call print_newline

    mov esi, init_success
    mov ebx, 0x00ffffff
    call print_string

    mov eax, [ip_addr]
    call .print_addr
    call print_newline

    mov esi, gateway_str
    mov ebx, 0x00ffffff
    call print_string

    mov eax, [gateway]
    mov ebx, eax
    call .print_addr
    call print_newline

    mov esi, subnet_mask_str
    mov ebx, 0x00ffffff
    call print_string

    mov eax, [subnet_mask]
    call .print_addr
    call print_newline

    mov esi, dns_str
    mov ebx, 0x00ffffff
    call print_string

    mov eax, [dns]
    call .print_addr
    call print_newline

    mov esi, lease_time_str
    mov ebx, 0x00ffffff
    call print_string

    mov eax, [lease_time]
    call swap

    xor edx, edx
    mov ebx, 60
    div ebx
    mov ebx, 60
    div ebx

    mov ebx, eax
    mov ah, 0x04
    int 0x30

    mov esi, h
    mov ebx, 0x00ffffff
    call print_string
    call print_newline
    ret

.print_addr:
    ;EAX = IP Address
    push ebx
    mov ebx, eax
    call print_dec

    push ebx
    mov esi, str
    mov ebx, 0x00ffffff
    call print_string
    pop ebx

    mov eax, ebx
    shr eax, 8
    and eax, 0xff
    call print_dec

    push ebx
    mov esi, str
    mov ebx, 0x00ffffff
    call print_string
    pop ebx

    mov eax, ebx
    shr eax, 16
    and al, 0xff
    call print_dec

    push ebx
    mov esi, str
    mov ebx, 0x00ffffff
    call print_string
    pop ebx

    mov eax, ebx
    shr eax, 24
    and al, 0xff
    call print_dec

    pop ebx
    ret
print_string:
    mov ah, 0x01
    int 0x30
    ret
print_newline:
    mov ah, 0x03
    int 0x30
    ret
print_dec:
    push ebx
    movzx ebx, al
    mov ah, 0x04
    int 0x30
    pop ebx
    ret

check_packet2:
    ;ESI = packet address
    ;ECX = size of packet

    mov esi, [heap]
    add esi, 12

    cmp dword [esi+4], 'DHCP'
    jne .error

    add esi, 236+4
.loop:
    lodsb
    
    cmp al, 0xff
    je .error
    cmp al, 0
    je .loop

    cmp al, 53
    je .done
    
    lodsb
    movzx ecx, al
    add esi, ecx
    jmp .loop

.done:
    add esi, 1
    lodsb
    cmp al, 5
    jne .error2


    clc
    ret
.error:
    xor ah, ah
    stc
    ret
.error2:
    mov ah, 0xff
    stc
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
error:
    mov esi, internet_err
    mov ebx, 0xe30909
    mov ah, 0x01
    int 0x30

    mov ah, 0x05
    int 0x35

section .data
heap: dd 0

;all IP addresses are big endian
ip_addr: dd 0
giaddr: dd 0
gateway: dd 0
dns: dd 0
subnet_mask: dd 0
net_interface: dd 0x8c000

lease_time: dd 0

ip_packet:
    db 1    ;message type: boot request
    db 1    ;hardware type: ethernet
    db 6    ;hardware address length: 6
    db 0
    dd 'DHCP'       ;transaction ID
    dw 0
    dw 0x0080       ;flags: broadcast
    dd 0            ;client IP (CIADDR)
    dd 0            ;your IP (YIADDR)
    dd 0            ;next server IP (SIADDR)
    dd 0            ;relay Agent IP (GIADDR)

    times 6 db 0    ;client MAC address
    times 10 db 0   ;padding

    times 64 db 0   ;server host name
    times 128 db 0  ;boot file name
    db 0x63, 0x82, 0x53, 0x63   ;magic cookie

    db 53           ;option 53
    db 1            ;length 1
    db 1
    db 0xff         ;end of packet
    times 10 db 0
init_success: db 'DHCP Request successfully sent.', 0x0a,
              db 'Your IPv4 Address: ', 0
gateway_str:  db 'Gateway: ', 0
dns_str: db 'DNS Server: ', 0
subnet_mask_str: db 'Subnet Mask: ', 0
lease_time_str: db 'Lease Time: ', 0
str: db '.', 0
h: db 'h', 0

router_port: dw 0
router_ip: dd 0

internet_err: db 'Error: No Internet Connection', 0x0a, 0
timed_out_str: db 'Error while receiving DHCP packet. Trying again...', 0x0a, 0
time_out: db 0