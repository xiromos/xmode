;=============================================================
;INT 0x34
;Syscall for drawing and deleting a window
;AH = 0x1: draw a window                        ;input: ESI = X, EDI = Y, ECX = width, EDX = height, EBX = background color, EBP = pointer to title         output: EAX = window ID, EBX = CurX, ECX = CurY
;AH = 0x2: remove window                        ;input: EDI = window_packet, bx = window id
;AH = 0x0A: draw a window but let the window manager control it (recommended)       input: EBX = foreground color (text color), ECX = background color, ESI = pointer to max. 17 byte string (or zero the register, then window is untitled)      output: EDI = pointer to window packet, AX = window ID
;AH = 0x0B: remove the window, drawn by the window manager                          input: BX = window ID, EDI = window packet

bits 32

window_functions:
    cli
    cmp ah, 0x01
    je .draw_window
    cmp ah, 0x02
    je .rm_window
    cmp ah, 0x0a
    je wndw_mngr_draw_window
    cmp ah, 0x0b
    je wndw_mngr_rm_window
    iret

.draw_window:
    pusha
    pusha
    xor cx, cx
    mov edi, windows_list
.search_free:
    mov al, [edi]
    cmp al, 0
    je .free_window
    inc cx
    inc edi
    cmp cx, [num_windows]
    jb .search_free
    popa
    popa
    or dword [esp+8], 1
    iret
.free_window:
    mov byte [edi], 1
    mov [window_id], cx
    popa

    mov [win_x], esi
    mov [win_y], edi
    mov [win_width], ecx
    mov [win_height], edx
    mov [win_color], ebx

    mov eax, ecx
    mov ebx, edx
    mul ebx
    movzx ebx, byte [bpp]
    mul ebx

    mov ecx, eax
    mov ah, 0x0a
    int 0x35

    movzx eax, word [window_id]
    imul eax, 8
    add eax, win_buffers_list2
    mov [eax], esi
    mov [eax+4], ecx

    mov edi, esi
    
    ;add X
    mov esi, [frame_buffer]
    mov ecx, [win_x]
    sub ecx, 1
    movzx eax, byte [bpp]
    mul ecx
    add esi, eax

    ;add Y
    mov ecx, [win_y]
    sub ecx, 20
    mov eax, [pitch]
    mul ecx
    add esi, eax

    mov ecx, [win_width]
    add ecx, 2
    movzx eax, byte [bpp]
    mul ecx
    mov ecx, eax

    mov ebx, [win_height]
    add ebx, 21         ;header + last row
.loop1:
    rep movsb

    add esi, [pitch]
    movzx ecx, byte [bpp]
    mov eax, [win_width]
    add eax, 2
    mul ecx
    sub esi, eax

    mov ecx, eax
    dec ebx
    jnz .loop1
;====draw the window====
.loop3:
    push ebp
    mov edi, [frame_buffer]
    xor edx, edx
    mov esi, [win_x]
    sub esi, 1
    movzx eax, byte [bpp]
    mul esi
    add edi, eax

    mov eax, [win_y]
    sub eax, 20
    mov ebx, [pitch]
    mul ebx
    add edi, eax

    mov edx, [win_border_color]
    mov ebx, 20
    movzx eax, byte [bpp]
    mov ecx, [win_width]
    add ecx, 2
.loop4:
    mov [edi], edx
    add edi, eax
    dec ecx
    jnz .loop4

    xor edx, edx
    add edi, [pitch]
    mov ecx, [win_width]
    add ecx, 2
    mul ecx
    sub edi, eax
    movzx eax, byte [bpp]
    mov ecx, [win_width]
    add ecx, 2
    mov edx, [win_border_color]
    dec ebx
    jnz .loop4

    ;title the window
    pop esi

    mov eax, [cur_x]
    push eax
    mov ebx, [cur_y]
    push ebx

    mov eax, [win_x]
    add eax, 1
    mov [cur_x], eax
    mov ebx, [win_y]
    sub ebx, 17
    mov [cur_y], ebx
    
    mov ebx, 0x00ffffff
    cmp byte [esi], 0x80
    jae .untitled
    
    call print_string
    jmp .continue
.untitled:
    mov esi, untitled_str
    call print_string
.continue:
    pop ebx
    mov [cur_y], ebx
    pop eax
    mov [cur_x], eax


    mov ecx, [win_width]
    xor edx, edx
    mov esi, [win_x]
    movzx eax, byte [bpp]
    mul esi
    mov edi, [frame_buffer]
    add edi, eax
    mov eax, [win_y]
    mov ebx, [pitch]
    mul ebx
    add edi, eax
    mov edx, [win_color]
    mov ebx, [win_height]
    movzx eax, byte [bpp]
    sub edi, eax
    push edx
    mov edx, [win_border_color]
    mov [edi], edx
    add edi, eax
    mov esi, [win_border_color]
    pop edx
.loop5:
    mov [edi], edx
    add edi, eax
    dec ecx
    jnz .loop5

    mov [edi], esi

    xor edx, edx
    add edi, [pitch]
    mov ecx, [win_width]
    mul ecx
    sub edi, eax
    movzx eax, byte [bpp]
    mov ecx, [win_width]
    mov edx, [win_color]
    sub edi, eax
    push edx
    mov edx, [win_border_color]
    mov [edi], edx
    add edi, eax
    pop edx
    dec ebx
    jnz .loop5

    mov esi, [win_border_color]
    movzx eax, byte [bpp]
    mov ecx, [win_width]
.loop6:
    mov [edi], esi
    add edi, eax
    dec ecx
    jnz .loop6
    popa
    mov ax, [window_id]
    iret

.rm_window:
    pusha
    mov eax, [edi+8]
    mov [win_width], eax
    mov eax, [edi+12]
    mov [win_height], eax
    mov eax, [edi+24]
    mov [win_x], eax
    mov eax, [edi+28]
    mov [win_y], eax

    movzx eax, bx
    mov edi, windows_list
    add edi, eax     ;add window ID
    mov byte [edi], 0

    movzx eax, bx
    imul eax, 8
    add eax, win_buffers_list2
    mov esi, [eax]
    mov ecx, [eax+4]
    mov ah, 0x0b
    int 0x35        ;free buffer

    mov edi, [frame_buffer]
    mov eax, [win_x]
    sub eax, 1
    movzx ebx, byte [bpp]
    mul ebx
    add edi, eax

    mov eax, [win_y]
    sub eax, 20
    mov ebx, [pitch]
    mul ebx
    add edi, eax

    mov ebx, [win_height]
    add ebx, 21         ;header + last row

    mov ecx, [win_width]
    add ecx, 2
    movzx eax, byte [bpp]
    mul ecx
    mov ecx, eax

.rm_loop:
    rep movsb

    add edi, [pitch]
    mov ecx, [win_width]
    add ecx, 2
    movzx eax, byte [bpp]
    mul ecx
    sub edi, eax
    mov ecx, eax

    dec ebx
    jnz .rm_loop
    popa
    iret



win_buffers_list:
    ;max 10 windows at a time
    ;window ID = Index of this list
    ;list contains addresses to buffers

    ;dd buffer_size
    ;dd *buffer
    ;dd *window_packet
    ;dw 0       ;0 = free
    ;times 18 db 0      (window title)

    times 10*32 dd 0

win_buffers_list2: times 10*10 db 0
max_win_buffers: dw 10
frame_buffer_copy: dd 0
num_displayed_win: dw 0     ;number of displayed windows
WIN_BUFFERLIST_SIZE equ 32


wndw_mngr_draw_window:
    ;look for free place in win_buffer_list
    pusha
    cli
    mov edx, ecx
    movzx eax, word [current_task]
    mov edi, win_buffers_list
    mov ecx, [max_win_buffers]
    cmp esi, 0xffffffff
    je .loop
    cmp esi, 0
    jne .loop
    mov esi, 0xffffffff
.loop:
    cmp word [edi+12], ax
    je .error

    add edi, WIN_BUFFERLIST_SIZE
    dec ecx
    jnz .loop

    movzx eax, word [max_win_buffers]
    mov edi, win_buffers_list
    xor ecx, ecx
.loop1:
    cmp word [edi+12], 0
    je .found_entry

    add edi, WIN_BUFFERLIST_SIZE
    inc ecx
    dec eax
    jnz .loop1
    jmp .error

.found_entry:
    movzx eax, word [current_task]
    mov [edi+12], ax ;mark as used
    sti
    push esi
    movzx ebp, cx   ;store window ID

    push ebx
    push edx

    xor edx, edx
    mov eax, [real_width]
    mov ebx, 8
    div ebx

    mov ecx, eax
    mov eax, [real_height]
    mov ebx, 16
    div ebx

    pop edx
    pop ebx

    imul eax, ecx
    mov ecx, eax
    shl ecx, 1      ;*2, because of UTF-16 characters
    mov ah, 0x0a
    int 0x35

    push edi
    push ecx
    mov edi, esi
    xor eax, eax
    shr ecx, 2      ;/4
    rep stosd
    pop ecx
    pop edi

    mov [edi], ecx
    mov [edi+4], esi    ;store buffer address

    ;make window packet ready
    mov esi, [win_packet_base]
    mov ecx, [max_window_packets]
.loop2:
    cmp dword [esi+8], 0
    je .free_window_packet

    add esi, WIN_PACKET_SIZE
    dec ecx
    jnz .loop2

    ;free heap and terminate program
    mov ecx, [edi]
    mov esi, [edi+4]
    mov dword [edi], 0
    mov dword [edi+4], 0
    mov word [edi+12], 0

    mov ah, 0x0b
    int 0x35

    mov ah, 0x05
    int 0x35
.free_window_packet:
    cmp dword [esi+12], 0
    jne .loop2

    push edi
    mov edi, esi
    mov ecx, WIN_PACKET_SIZE
    xor eax, eax
    rep stosb
    pop edi

    mov [edi+8], esi
    mov dword [esi], ebx    ;foreground color
    mov dword [esi+4], edx  ;background color

    cli
    inc byte [num_displayed_win]
    movzx eax, byte [num_displayed_win]
    cmp eax, 1
    jne .skip

    call store_back_window
    cli
.skip:
    mov edx, esi
    pop esi

    ;copy title
    push edi
    push eax

    add edi, 14
    mov ecx, 17
    cmp esi, 0xffffffff
    jne .loop3

    mov esi, untitled_str
.loop3:
    lodsb
    cmp al, 0
    je .copy_done
    stosb
    dec ecx
    jnz .loop3
    xor al, al
.copy_done:
    stosb
    pop eax
    pop edi

    sti
    call win_mngr_draw_window

    cli
    mov [.win_packet], edx
    mov [.win_id], bp

    popa
    and dword [esp+8], 0xfffffffe
    mov edi, [.win_packet]
    mov ax, [.win_id]

    iret

.win_packet: dd 0
.win_id: dw 0

.error:
    popa
    or dword [esp+8], 1
    iret


copy_back_window:
    pusha
    mov esi, [frame_buffer_copy]
    mov edi, [frame_buffer]
    mov ecx, [real_width]
    imul ecx, dword [real_height]
    movzx eax, byte [bpp]
    imul ecx, eax

    rep movsb

    popa
    ret

store_back_window:
    pusha
    mov esi, [frame_buffer]
    mov edi, [frame_buffer_copy]
    mov ecx, [real_width]
    imul ecx, dword [real_height]
    movzx eax, byte [bpp]
    imul ecx, eax

    rep movsb

    popa
    ret



win_mngr_draw_window:
    ;EAX = number of displayed windows right now + 1

    pusha
    cmp eax, 1
    je .win1
    cmp eax, 2
    je .win2
    cmp eax, 3
    je .win3
    cmp eax, 4
    je .win4

    popa
    stc
    ret

; ########################
; #### DRAW 1 WINDOW #####
; ########################
.win1:
    cli

    mov edi, win_buffers_list
    mov ecx, [max_win_buffers]
.win1_loop:
    cmp word [edi+12], 0
    jne .win1_found

    add edi, WIN_BUFFERLIST_SIZE
    dec ecx
    jnz .win1_loop

    call copy_back_window
    mov ah, 0x05
    int 0x35
.win1_found:
    cli
    ;draw full sized window at (1|20)
    mov dword [.win_x], 1
    mov dword [.win_y], 20

    mov eax, [real_width]
    sub eax, 2
    mov [.width], eax
    mov eax, [real_height]
    sub eax, 21         ;20 because of header + 1 because of border
    mov [.height], eax

    ;fill window packet
    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30
    sti
    jmp .done

; ########################
; #### DRAW 2 WINDOWS ####
; ########################

.win2:
    call copy_back_window

    cli
    mov edi, win_buffers_list
    mov ecx, [max_win_buffers]
    xor ebx, ebx
    ;search for first window
.win2_loop:
    cmp word [edi+12], 0
    jne .win2_found1

    add edi, WIN_BUFFERLIST_SIZE
    inc ebx
    dec ecx
    jnz .win2_loop
    call copy_back_window
    jmp .done

.win2_found1:
    push edi
    push ecx
    push ebx

    ;draw first window at (1|20)
    mov dword [.win_x], 1
    mov dword [.win_y], 20

    mov eax, [real_width]
    shr eax, 1      ;/2
    sub eax, 2      ;leave space for border
    mov [.width], eax

    mov eax, [real_height]
    sub eax, 21
    mov [.height], eax

    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30

    pop ebx
    pop ecx
    pop edi

    add edi, WIN_BUFFERLIST_SIZE
.win2_loop2:
    cmp word [edi+12], 0
    jne .win2_found2

    add edi, WIN_BUFFERLIST_SIZE
    inc ebx
    dec ecx
    jnz .win2_loop2
    call copy_back_window
    jmp .done
.win2_found2:

    ;draw second window at (width/2|20)
    mov eax, [real_width]
    shr eax, 1  ;width/2
    inc eax     ;1px for border
    mov [.win_x], eax
    mov dword [.win_y], 20

    mov eax, [real_width]
    shr eax, 1      ;/2
    sub eax, 2      ;leave space for border
    mov [.width], eax

    mov eax, [real_height]
    sub eax, 21
    mov [.height], eax

    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30

    jmp .done

; ########################
; #### DRAW 3 WINDOWS ####
; ########################

.win3:
    call copy_back_window

    cli
    mov edi, win_buffers_list
    mov ecx, [max_win_buffers]
    xor ebx, ebx
    ;search for first window
.win3_loop:
    cmp word [edi+12], 0
    jne .win3_found1

    add edi, WIN_BUFFERLIST_SIZE
    inc ebx
    dec ecx
    jnz .win3_loop
    call copy_back_window
    jmp .done

.win3_found1:
    push edi
    push ecx
    push ebx

    ;draw first window at (1|20)
    mov dword [.win_x], 1
    mov dword [.win_y], 20

    mov eax, [real_width]
    shr eax, 1      ;/2
    sub eax, 2      ;leave space for border
    mov [.width], eax

    mov eax, [real_height]
    sub eax, 21
    mov [.height], eax

    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30

    pop ebx
    pop ecx
    pop edi
    
    add edi, WIN_BUFFERLIST_SIZE
.win3_loop2:
    cmp word [edi+12], 0
    jne .win3_found2

    add edi, WIN_BUFFERLIST_SIZE
    inc ebx
    dec ecx
    jnz .win3_loop2
    call copy_back_window
    jmp .done
.win3_found2:

    push edi
    push ecx
    push ebx

    ;draw second window at (width/2|20)
    mov eax, [real_width]
    shr eax, 1  ;width/2
    inc eax     ;1px for border
    mov [.win_x], eax
    mov dword [.win_y], 20

    mov eax, [real_width]
    shr eax, 1      ;/2
    sub eax, 2      ;leave space for border
    mov [.width], eax

    mov eax, [real_height]
    shr eax, 1      ;/2
    sub eax, 21
    mov [.height], eax

    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30

    pop ebx
    pop ecx
    pop edi

    add edi, WIN_BUFFERLIST_SIZE
.win3_loop3:
    cmp word [edi+12], 0
    jne .win3_found3

    add edi, WIN_BUFFERLIST_SIZE
    inc ebx
    dec ecx
    jnz .win3_loop3
    call copy_back_window
    jmp .done
.win3_found3:

    ;draw third window at (width/2|height/2-20)
    mov eax, [real_width]
    shr eax, 1  ;width/2
    inc eax     ;1px for border
    mov [.win_x], eax

    mov eax, [real_height]
    shr eax, 1
    add eax, 20
    mov dword [.win_y], eax

    mov eax, [real_width]
    shr eax, 1      ;/2
    sub eax, 2      ;leave space for border
    mov [.width], eax

    mov eax, [real_height]
    shr eax, 1      ;/2
    sub eax, 21
    mov [.height], eax

    call .fill_win_packet
    call .draw_window

    mov esi, [edi+4]    ;*buffer
    mov edi, [edi+8]    ;*window_packet
    mov ah, 0x0a
    int 0x30

    jmp .done

; ########################
; #### DRAW 4 WINDOWS ####
; ########################

.win4:
    jmp .done

.done:
    popa
    clc
    ret

.win_x: dd 0
.win_y: dd 0
.width: dd 0
.height: dd 0

.fill_win_packet:
    ;EDI = pointer to entry in win_buffers_list
    ;returns background color of window in EBX
    ;set ESI to *title

    mov esi, [edi+8]
    mov eax, [.width]
    mov [esi+8], eax
    mov eax, [.height]
    mov [esi+12], eax
    mov eax, [.win_x]
    mov [esi+16], eax
    mov [esi+24], eax
    mov ebx, [.win_y]
    mov [esi+20], ebx
    mov [esi+28], ebx

    mov ebx, [esi+4]    ;color

    mov esi, edi
    add esi, 14
    ret
.draw_window:
    ;expects filled win_x, win_y, widht, height
    ;EBX = color
    ;ESI = *title

    pusha
    push esi
    mov esi, ebx
    mov eax, [.win_x]
    mov ebx, [.win_y]
    mov ecx, [.width]
    mov edx, [.height]
    call draw_rectangle

    mov eax, [.win_x]
    sub eax, 1
    mov ebx, [.win_y]
    sub ebx, 20
    mov ecx, [.width]
    add ecx, 2
    mov edx, 20

    mov esi, [win_border_color]
    call draw_rectangle
    pop esi

    push dword [cur_x]
    push dword [cur_y]

    mov eax, [.win_x]
    add eax, 2
    mov [cur_x], eax

    mov eax, [.win_y]
    sub eax, 17
    mov [cur_y], eax

    mov ebx, 0x00ffffff
    cmp esi, 0xffffffff
    jne .skip

    mov esi, untitled_str
.skip:
    call print_string
    pop eax
    pop ebx
    mov [cur_y], eax
    mov [cur_x], ebx

    mov edi, [frame_buffer]
    movzx eax, byte [bpp]
    mov ebx, [.win_x]
    sub ebx, 1
    imul eax, ebx
    add edi, eax

    mov eax, [.win_y]
    imul eax, dword [pitch]
    add edi, eax

    mov esi, [win_border_color]
    mov eax, [.width]
    movzx ebx, byte [bpp]
    imul eax, ebx

    cmp ebx, 3
    je .bits24

    mov ecx, [.height]
.loop:
    mov [edi], esi
    add edi, ebx
    add edi, eax
    mov [edi], esi

    add edi, dword [pitch]
    sub edi, eax
    sub edi, ebx

    dec ecx
    jnz .loop

    mov ecx, [.width]
    add ecx, 2
.last_row:
    mov [edi], esi
    add edi, ebx
    dec ecx
    jnz .last_row

    popa
    ret


.bits24:
    mov ecx, [.height]
    mov bx, si
    shr esi, 16
    xchg bx, si
.loop2:
    mov [edi], si
    mov [edi+2], bl

    add edi, 3
    add edi, eax
    mov [edi], si
    mov [edi+2], bl

    add edi, dword [pitch]
    sub edi, eax
    sub edi, 3

    dec ecx
    jnz .loop2

    mov ecx, [.width]
    add ecx, 2
.last_row2:
    mov [edi], si
    mov [edi+2], bl
    add edi, 3
    dec ecx
    jnz .last_row2

    sti
    popa
    ret

draw_rectangle:
    ;EAX = X
    ;EBX = Y
    ;ECX = width
    ;EDX = height
    ;ESI = color
    pusha
    cmp ecx, 0
    je .error
    cmp edx, 0
    je .error

    mov edi, [frame_buffer]

    push ecx
    movzx ecx, byte [bpp]
    imul eax, ecx
    pop ecx

    add edi, eax    ;add X

    mov eax, [pitch]
    imul ebx, eax
    
    add edi, ebx    ;add Y

    cmp byte [bpp], 3
    je .bit24

    mov ebp, ecx
    movzx eax, byte [bpp]
.loop:
    mov [edi], esi
    add edi, eax
    dec ecx
    jnz .loop

    mov ecx, ebp
    push eax
    imul eax, ecx
    sub edi, eax
    pop eax

    add edi, dword [pitch]
    dec edx
    jnz .loop

    popa
    clc
    ret

.bit24:
    mov ebp, ecx
    mov eax, 3
    mov bx, si
    shr esi, 16
    xchg bx, si
.loop2:
    mov [edi], si
    mov [edi+2], bl
    add edi, 3
    dec ecx
    jnz .loop2

    mov ecx, ebp
    mov eax, ecx
    imul eax, 3
    sub edi, eax

    add edi, dword [pitch]
    dec edx
    jnz .loop2

    popa
    clc
    ret

.error:
    popa
    stc
    ret


wndw_mngr_rm_window:
;   BX = window ID
;   EDI = window packet

    pusha
    movzx esi, bx
    imul esi, WIN_BUFFERLIST_SIZE
    add esi, win_buffers_list

    mov ax, [current_task]
    cmp [esi+12], ax
    jne .error

    cli
    ;free window buffer
    mov edi, esi
    mov esi, [edi+4]
    mov ecx, [edi]
    mov ah, 0x0b
    int 0x35

    mov dword [edi], 0
    mov dword [edi+4], 0

    ;clear field "PID" and clear window title
    mov word [edi+12], 0
    push edi
    add edi, 12
    xor ax, ax
    mov ecx, 18/2
    rep stosw
    pop edi

    ;free window packet
    mov esi, [edi+8]
    mov dword [edi+8], 0
    mov edi, esi
    mov ecx, WIN_PACKET_SIZE
    xor al, al
    rep stosb

    dec byte [num_displayed_win]
    movzx eax, byte [num_displayed_win]
    cmp eax, 0
    je .no_window

    sti
    call win_mngr_draw_window

    popa
    and dword [esp+8], 0xfffffffe
    iret
.no_window:
    sti
    call copy_back_window
    
    popa
    and dword [esp+8], 0xfffffffe
    iret

.error:
    popa
    or dword [esp+8], 1
    iret