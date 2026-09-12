;=========================================================
;System API
;AH = 0x00:
;   BH = 0x01: get system information                                                                      ;EDI = pointer to 128B buffer
;   BH = 0x02: reboot system
;AH = 0x01: Freeze System (debug)
;AH = 0x02: start a foreground task (that means the task has control over keyboard and screen)          ;EBX = pointer to directory, ESI = pointer to taskname, EDI = pointer to filename       Output: CF on Error, AH = Error code (0x00 = fs error, 0x01 = COFF error)
;AH = 0x03: start a background task                                                                     ;EBX = pointer to directory, ESI = pointer to taskname, EDI = pointer to filename       Output: CF on Error, AH = Error code (0x00 = fs error, 0x01 = COFF error)
;AH = 0x04: terminate a task (not the caller)                                                           ;EBX = PID or ESI = Taskname (if one is set, other should be zero)  CF on error
;   Error ist set if the PID is 0 or 1 or if the task is a kernel task
;AH = 0x05: terminate the process which called the syscall
;AH = 0x06: terminate the caller process but skip the part where freeing the tasks heap
;AH = 0x07: change task state
;   AL = 0x01: task state = sleeping
;AH = 0x0A: allocate heap                                                                               ;Input: ECX = size         Output: ESI = pointer to heap chunk
;AH = 0x0B: free heap                                                                                   ;Input: ESI = pointer to allocated chunk, ECX = size

;AH = 0x12: start already loaded task in foreground                                                     ;EBX = Address in Memory of Task, ESI = pointer to Taskname
;AH = 0x13: start already loaded task in background                                                     ;EBX = Address in Memory of Task, ESI = pointer to Taskname

;AH = 0x20: functions for playing a WAV file (BH = subfunction)
;   BH = 0x01: play WAV file (expects EDI = start address of file)
;   BH = 0x02: pause playing current WAV file
;   BH = 0x03: resume playing current WAV file
;   BH = 0x04: stop playing WAV file
;AH = 0x21: network functions
;   AL = 0x01: get network stats
;       Input: EDI = pointer to 128B buffer
;       EDI+0: device IPv4 address
;       EDI+4: DNS server IPv4 address
;       EDI+8: router IPv4 address
;       EDI+20: number of successfully transmitted packets
;       EDI+24: number of packets, failed to transmit
;       EDI+28: number of successfully received packets
;       EDO+32: number of packets, failed to receive
;   AL = 0x02: open socket
;       Input: BH = net_interface (0 = IPv4, 1 = IPv6), BL = protocol (0x01 ICMP, 0x02 TCP, 0x03 UDP), DX = port number (if zero then let the OS decide), ESI = buffer address for packets
;       Output: socket number in CX or CF if port number is already used
;   AL = 0x03: send a packet
;       Input: bits 16-31 of EBX = socket number, BX = port (zero if programs uses ICMP), EDX = IPv4 address (big endian), ESI = pointer to packet, ECX = length of packet
;   AL = 0x04: wait for packet
;       Input: CX = socket number
;       If returns, that means a packet was received. The program itself has to check if its the right packet.
;   AL = 0x05: close socket
;       Input: CX = socket number
;   AL = 0x07: resolve domain name (like github.com) into IPv4 address
;       Input: CX = socket number, EDI = pointer to null-terminated ASCII string of domain name
;       Output: EDX = IPv4 address (big endian), EAX = Time to live
;       Socket has to be UDP protocol
;AH = 0x22: timer functions
;   AL = 0x01: sleep X ms
;       Input: EBX = number of miliseconds to sleep
;   AL = 0x02: set counter
;       Input: EBX = pointer to 4 Byte field which is incremented by 1 every 1ms, EDX = time in MS after which the timer expires and gets deleted (e.g. if EDX = 500, then the timer gets deleted after 500ms)
;   AL = 0x03: get current time
;       Output: AL = seconds (0 - 59), AH = minutes (0 - 59), BL = hour (0 - 23), BH = day (1 (monday) - 7 (sunday)), CL = day of month (1 - 31), CH = month (1 - 12), DL = year (0 - 99), DH = century (20)

program_sys_handler:
    cmp ah, 0x00
    je general_system
    cmp ah, 0x01
    je .test_stop
    cmp ah, 0x02
    je start_task_bg
    cmp ah, 0x03
    je start_task_bg
    cmp ah, 0x04
    je kill_task
    cmp ah, 0x05
    je .terminate_process
    cmp ah, 0x06
    je .terminate_process
    cmp ah, 0x07
    je change_task_state
    cmp ah, 0x0a
    je alloc_heap
    cmp ah, 0x0b
    je free_heap
    cmp ah, 0x0c
    je alloc_heap_low
    cmp ah, 0x0d
    je free_heap_low
    cmp ah, 0x12
    je start_task_fg2
    cmp ah, 0x13
    je start_task_bg2
    cmp ah, 0x20
    je play_wav_file
    cmp ah, 0x21
    je network_functions
    cmp ah, 0x22
    je timer_functions

    or dword [esp+8], 1
    iret
.test_stop:
    cli
    hlt
.terminate_process:
    cli

    mov bx, [current_task]
    call free_task_heap

    movzx ecx, word [current_task]
    imul ecx, TASK_SIZE
    mov edi, tasks_esp
    add edi, ecx
    mov byte [edi], 0xe5

    ; cmp ah, 0x06
    ; je .skip

    mov ax, [current_task]
    mov word [current_task], 1
    push ax

    mov esi, [edi+19]       ;start address
    cmp esi, 0xfffffffe
    je .skip_free_heap
    mov ecx, [edi+23]       ;size
    mov ah, 0x0b
    int 0x35

    pop ax
    mov [current_task], ax

.skip_free_heap:
    mov dword [edi+11], 0
    mov dword [edi+19], 0
    mov dword [edi+23], 0

    dec word [task_count]

    mov cx, [current_task]
    cmp word [main_task], cx
    jne .skip

    mov word [main_task], 1
.skip:
    mov edi, tasks_esp
    inc word [current_task]
    movzx ecx, word [max_tasks]
    cmp word [current_task], cx
    jbe .check

    mov word [current_task], 1
    jmp .continue
.check:
    imul ecx, TASK_SIZE
    add edi, ecx
    cmp byte [edi], 0xe5
    je .skip
    cmp byte [edi], 0
    je .skip

.continue:
    xor ecx, ecx
    mov cx, [current_task]
    imul cx, TASK_SIZE
    add ecx, tasks_esp

    mov esp, [ecx+15]

    movzx ecx, word [current_task]
    imul ecx, tasks_kernel_stack_off
    add ecx, tasks_kernel_stack

    mov [tss+4], ecx

    pop gs
    pop fs
    pop es
    pop ds
    popad
    iret
    cli
    hlt


start_task_bg2:
    ;EBX = Task Address
    ;ESI = Task Name
    pusha
    cmp ebx, 0
    je .error
    cmp esi, 0
    je .error

    mov eax, ebx

    push eax
    mov ax, [max_tasks]
    cmp word [task_count], ax
    jae .too_much_tasks

    ;save shell context
    mov eax, 1
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp

    mov dx, [task_slots]
    mov ecx, 2

    mov edi, tasks_esp
    add edi, TASK_SIZE*2     ;skip task 0 + shell
    pop eax
.find_loop:
    cmp byte [edi], 0xe5
    je .found_slot
    cmp byte [edi], 0
    je .found_slot

    add edi, TASK_SIZE

    inc ecx
    dec dx
    jnz .find_loop

    popa
    or dword [esp+8], 1
    iret
.found_slot:
    push esi
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop esi

    mov dword [edi+19], 0xfffffffe  ;program does not use heap memory

    mov [kernel_stack], esp

    mov edx, eax
    mov eax, program_stack_off
    imul eax, ecx
    add eax, program_stack
    mov esp, eax
    mov eax, edx

    ; mov eax, program_addr_off
    ; imul eax, ecx
    ; add eax, program_addr

    push ss
    push esp
    ;pushfd                 ;bug - if program does infinite loop -> freeze
    push dword 0x202        ;enable interrupt flag
    push cs
    push eax

    pushad
    push ds
    push es
    push fs
    push gs

    movzx eax, cx
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp

    inc word [task_count]

    int 0x20
    mov esp, [kernel_stack]

    popa
    and dword [esp+8], 0xfffffffe
    iret
.too_much_tasks:
    popa
    or dword [esp+8], 1
    iret
.error:
    popa
    or dword [esp+8], 1
    iret

start_task_fg2:
    ;EBX = Task Address
    ;ESI = Task Name
    pusha
    cmp ebx, 0
    je .error
    cmp esi, 0
    je .error

    mov eax, ebx

    push eax
    mov ax, [max_tasks]
    cmp word [task_count], ax
    jae .too_much_tasks

    ;save shell context
    mov eax, 1
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp

    mov dx, [task_slots]
    mov ecx, 2

    mov edi, tasks_esp
    add edi, TASK_SIZE*2     ;skip task 0 + shell
    pop eax
.find_loop:
    cmp byte [edi], 0xe5
    je .found_slot
    cmp byte [edi], 0
    je .found_slot

    add edi, TASK_SIZE

    inc ecx
    dec dx
    jnz .find_loop

    popa
    or dword [esp+8], 1
    iret
.found_slot:
    push esi
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop esi

    mov dword [edi+19], 0xfffffffe  ;program does not use heap memory

    mov [kernel_stack], esp

    mov edx, eax
    mov eax, program_stack_off
    imul eax, ecx
    add eax, program_stack
    mov esp, eax
    mov eax, edx

    ; mov eax, program_addr_off
    ; imul eax, ecx
    ; add eax, program_addr

    push ss
    push esp
    ;pushfd                 ;bug - if program does infinite loop -> freeze
    push dword 0x202        ;enable interrupt flag
    push cs
    push eax

    pushad
    push ds
    push es
    push fs
    push gs

    movzx eax, cx
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp

    mov [main_task], cx
    inc word [task_count]

    int 0x20
    mov esp, [kernel_stack]

    popa
    and dword [esp+8], 0xfffffffe
    iret
.too_much_tasks:
    popa
    or dword [esp+8], 1
    iret
.error:
    popa
    or dword [esp+8], 1
    iret
kill_task:
    ;ESI = Taskname or EBX = PID
    ;If Taskname or PID is set, the other register should be zero
    pusha
    cmp ebx, 0
    je .search_taskname
    cmp esi, 0
    je .kill_pid
    jmp .error

.search_taskname:
    cmp esi, 0
    je .error

    mov dx, [max_tasks]
    xor ebx, ebx
.loop:
    mov edi, tasks_esp
    mov ecx, 11
    push edi
    push esi
    repe cmpsb
    pop esi
    pop edi
    je .kill_pid

    add edi, TASK_SIZE
    inc ebx
    dec dx
    jnz .loop
    jmp .error

.kill_pid:
    cmp ebx, 0
    je .error
.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret

.error:
    popa
    or dword [esp+8], 1
    iret


change_task_state:
    cli
    pusha
    cmp al, 0x01
    je .sleep
    cmp al, 0x02

    popa
    or dword [esp+8], 1
    iret
.sleep:
    movzx ecx, word [current_task]
    imul ecx, TASK_SIZE
    add ecx, tasks_esp
    mov dword [ecx+11], 0x0000b100  ;sleeping
.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret
;#################################################################
;#################### ALLOCATE AND FREE PAGES ####################
;#################################################################

alloc_page:
    ;BX = PID
    cli
    pusha
    mov edi, [heap_start_ptr]
    xor ecx, ecx
    mov edx, [max_heap_entries]
.loop:
    mov ax, [edi]
    cmp ax, 0
    je .found_free

    add edi, 2
    inc ecx
    dec edx
    jnz .loop

    ;no free heap
    popa
    or dword [esp+8], 1
    iret
.found_free:
    mov [edi], bx

    mov esi, ecx
    imul esi, HEAP_CHUNK_SIZE
    add esi, dword [heap_start_ptr]
    mov [.tmp], esi
    popa
    mov esi, [.tmp]
    ;call map_address
    and dword [esp+8], 0xfffffffe
    iret
.tmp: dd 0
free_page:
    cli
    pusha
    mov eax, esi
    sub eax, dword [heap_start_ptr]
    xor edx, edx
    mov ebx, HEAP_CHUNK_SIZE
    div ebx

    mov edi, [heap_table]
    add edi, eax
    mov ax, [edi]
    cmp ax, word [current_task]
    jne .error
    mov word [edi], 0
    popa
    and dword [eax+8], 0xfffffffe
    iret
.error:
    popa
    or dword [eax+8], 1
    iret

free_task_heap:
    ;BX = PID
    pusha
    mov esi, [heap_table]
    mov ecx, [max_heap_entries]
.loop:
    mov ax, [esi]
    cmp ax, bx
    jne .next
    mov word [esi], 0
.next:
    add esi, 2
    dec ecx
    jnz .loop

    popa
    ret


map_page:
    ret

;#################################################################


;#################################################################
;############### ALLOCATE HEAP MEMORY ############################
;#################################################################

alloc_heap:
    ;Input: ECX = size of requested heap
    ;Output: ESI = pointer to heap start
    cli
    pusha
    xor edx, edx
    mov eax, ecx
    add eax, HEAP_CHUNK_SIZE-1
    mov ebx, HEAP_CHUNK_SIZE
    div ebx
    ;EAX = number of pages

    movzx ebx, word [current_task]
    mov edi, [heap_table]
    xor ecx, ecx
    mov ebp, [max_heap_entries]
.loop:
    mov dx, [edi]
    cmp dx, 0
    jne .reset

    inc ecx
    cmp ecx, eax
    je .found
    add edi, 2
    dec ebp
    jnz .loop
.reset:
    xor ecx, ecx
    add edi, 2
    dec ebp
    jnz .loop

    movzx ebx, word [current_task]
    cmp ebx, 1
    je .critical_error

    mov ah, 0x04
    int 0x35

    ;create window with error message: low memory
    ;...

    popa
    or dword [esp+8], 1
    iret

.found:
    mov edx, eax
    dec edx
    shl edx, 1
    sub edi, edx
    mov esi, edi

    mov ecx, eax
    mov eax, ebx
    rep stosw

    sub esi, dword [heap_table]
    shr esi, 1
    imul esi, HEAP_CHUNK_SIZE
    add esi, dword [heap_start_ptr]

    mov [.tmp], esi
    popa
    mov esi, [.tmp]
    and dword [esp+8], 0xfffffffe
    iret
.tmp: dd 0
.error_msg: db 'Low Memory. Shell Tried To Search Free Memory But Failed.', 0x0a
            db 'Try To Install More RAM. If You Installed Enough RAM, Maybe There Is A Memory Leak', 0 
.critical_error:
    mov esi, .error_msg
    call rsod
    ;call reboot
    cli
    hlt
;#################################################################
;################### FREE HEAP MEMORY ############################
;#################################################################

free_heap:
    ;Input: ESI = pointer to heap start
    ;       ECX = size of allocated heap
    cli
    pusha
    sub esi, dword [heap_start_ptr]
    mov eax, esi
    mov ebx, HEAP_CHUNK_SIZE
    xor edx, edx
    div ebx

    imul eax, 2
    mov edi, [heap_table]
    add edi, eax

    xor edx, edx
    mov eax, ecx
    add eax, HEAP_CHUNK_SIZE-1
    mov ebx, HEAP_CHUNK_SIZE
    div ebx

    mov ecx, eax
.loop:
    mov ax, [edi]
    cmp ax, word [current_task]
    jne .error
    mov word [edi], 0
    dec ecx
    jnz .loop

    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret

; Heap memory starts at 0x1000000. There is a list at address 0x750000 which lists all free and used heap blocks.
; Low heap memory starts at 0xc00000 and the low heap list which lists free and used heap blocks sits at address 0x850000.
; A heap chunk in low heap memory is 0x10000 bytes.

heap_start_ptr dd 0x1000000
max_memory: dd 0    ;maximum of available memory
HEAP_CHUNK_SIZE     equ 4096

heap_table: dd 0x750000     ;4096 entries -> 1 entry = 1 4KB page = 4096*4096 = max. 16MB free heap
max_heap_entries: dd 4096

low_heap_table: dd 0x850000
max_lowheap_entries: dd 128
LOW_HEAP_CHUNK      equ 0x10000
low_heapmem_start: dd 0xc00000
;##############################
;Initialization

init_heap:
    push edi
    push eax
    push ecx
    mov edi, [heap_table]
    xor eax, eax
    mov ecx, 0x2000
    rep stosb

    mov edi, [low_heap_table]
    xor eax, eax
    mov ecx, 128
    rep stosb

    pop ecx
    pop eax
    pop edi

    ret

;#################################################################
;#################### ALLOCATE LOW HEAP MEMORY ###################
;#################################################################

alloc_heap_low:
    ;Input: ECX = size of requested heap
    ;Output: ESI = pointer to heap start
    cli
    pusha
    xor edx, edx
    mov eax, ecx
    add eax, LOW_HEAP_CHUNK-1
    mov ebx, LOW_HEAP_CHUNK
    div ebx
    ;EAX = number of chunks

    movzx ebx, word [current_task]
    mov edi, [low_heap_table]
    xor ecx, ecx
    mov ebp, [max_lowheap_entries]
.loop:
    mov dx, [edi]
    cmp dx, 0
    jne .reset

    inc ecx
    cmp ecx, eax
    je .found
    add edi, 2
    dec ebp
    jnz .loop
.reset:
    xor ecx, ecx
    add edi, 2
    dec ebp
    jnz .loop

    popa
    or dword [esp+8], 1
    iret

.found:
    mov edx, eax
    dec edx
    shl edx, 1
    sub edi, edx
    mov esi, edi

    mov ecx, eax
    mov eax, ebx
    rep stosw

    sub esi, dword [low_heap_table]
    shr esi, 1
    imul esi, LOW_HEAP_CHUNK
    add esi, dword [low_heapmem_start]

    mov [.tmp], esi
    popa
    mov esi, [.tmp]
    and dword [esp+8], 0xfffffffe
    iret
.tmp: dd 0

;#################################################################
;################### FREE LOW HEAP MEMORY ########################
;#################################################################

free_heap_low:
    ;Input: ESI = pointer to heap start
    ;       ECX = size of allocated heap
    cli
    pusha
    sub esi, dword [low_heapmem_start]
    mov eax, esi
    mov ebx, LOW_HEAP_CHUNK
    xor edx, edx
    div ebx

    imul eax, 2
    mov edi, [low_heap_table]
    add edi, eax

    xor edx, edx
    mov eax, ecx
    add eax, LOW_HEAP_CHUNK-1
    mov ebx, LOW_HEAP_CHUNK
    div ebx

    mov ecx, eax
    cmp ecx, 0
    je .error
.loop:
    mov ax, [edi]
    cmp ax, word [current_task]
    jne .error
    mov word [edi], 0
    dec ecx
    jnz .loop

    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret


;#################################################################
;####################### START A TASK ############################
;#################################################################
start_task_bg:
    ;ESI = Task Name
    ;EDI = filename
    ;EBX = pointer to directory

    ;0xffffffff = no argument
    ;all arguments have to be null-terminated
    ;ECX = pointer to first argument
    ;EDX = pointer to second argument
    ;EBP = pointer to other arguments (which are stored in a structure for example)

    cli
    pusha
    cmp esi, 0
    je .error
    cmp edi, 0
    je .error

    mov [.task_state], ah

    mov [.first_arg], ecx
    mov [.second_arg], edx
    mov [.other_args], ebp

    push esi
    push ebx
    push edi
    xor ah, ah
    mov esi, edi
    mov edi, ebx
    int 0x33
    pop edi

    mov ax, [max_tasks]
    cmp word [task_count], ax
    jae .too_much_tasks

    mov ebx, ecx        ;amount of heap memory
    mov ah, 0x0a        ;allocate heap memory for program
    int 0x35
    jnc .continue

    pop ebx
    pop esi
    or dword [esp+8], 1
    iret
.continue:
    ;ESI = pointer to heap memory start
    mov [.program_start], esi
    mov [.size], ecx

    pop ebx
    ;load program into memory
    mov ah, 0x0a
    xchg esi, edi
    mov edx, ebx
    mov bl, [drive_number]
    int 0x33

    push esi
    call load_coff_obj
    pop esi
    ;jc .coff_error

    mov eax, edi

    mov dx, [task_slots]
    mov ecx, 2
    pop esi

    mov edi, tasks_esp
    add edi, TASK_SIZE*2     ;skip task 0 + shell
.find_loop:
    cmp byte [edi], 0xe5
    je .found_slot
    cmp byte [edi], 0
    je .found_slot

    add edi, TASK_SIZE

    inc ecx
    dec dx
    jnz .find_loop

    popa
    or dword [esp+8], 1
    iret
.found_slot:

    push esi
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop esi

    mov [kernel_stack], esp

    mov edx, eax
    mov eax, program_stack_off
    imul eax, ecx
    add eax, program_stack
    mov esp, eax
    mov eax, edx

    ;push pointer to arguments
    ;a value of 0xffffffff as pointer means, that there is no argument, the program should check for that

    ;pop esi    ;pointer to 1. argument
    ;pop edi    ;pointer to 2. argument
    ;pop eax    ;pointer to other arguments

    mov esi, [.other_args]
    push esi

    mov esi, [.first_arg]
    mov edi, [.second_arg]
    push edi
    push esi

    push dword (3*8) | 3    ;SS
    push esp
    ;pushfd                 ;bug - if program does infinite loop -> freeze
    push dword 0x202        ;enable interrupt flag
    push dword code_off_user;CS
    push eax

    pushad
    push dword (3*8) | 3    ;DS
    push dword (3*8) | 3    ;ES
    push dword (3*8) | 3    ;FS
    push dword (3*8) | 3    ;GS

    movzx eax, cx
    imul eax, TASK_SIZE
    mov edi, tasks_esp
    add edi, eax
    mov [edi+15], esp
    mov eax, [.program_start]
    mov [edi+19], eax
    mov eax, [.size]
    mov [edi+23], eax

    inc word [task_count]
    cmp byte [.task_state], 0x02
    jne .skip

    mov [main_task], cx
.skip:
    mov esp, [kernel_stack]
    sti

    int 0x20
    ;mov esp, [kernel_stack]

    popa
    and dword [esp+8], 0xfffffffe
    iret
.too_much_tasks:
    popa
    or dword [esp+8], 1
    iret
.error:
    popa
    or dword [esp+8], 1
    xor ah, ah
    iret
.coff_error:
    pop esi
    popa
    or dword [esp+8], 1
    mov ah, 0x01
    iret
.program_start: dd 0
.size: dd 0
.task_state: db 0       ;foreground / background
.first_arg: dd 0
.second_arg: dd 0
.other_args: dd 0

play_wav_file:
    ;EDI = address of file
    pusha

    cmp dword [wavfile_functions], 0
    je .error

    cmp bh, 0x01
    je .play_wavfile
    cmp bh, 0x02
    je .pause_wavfile
    cmp bh, 0x03
    je .resume_wavfile
    cmp bh, 0x04
    je .stop_wavfile
.play_wavfile:
    cmp edi, dword [low_heapmem_start]
    jb .error

    mov edx, [wavfile_functions]
    cmp dword [edx], 0x100000
    jb .error

    call dword [edx]
    jc .error
    jmp .done
.pause_wavfile:
    mov edx, [wavfile_functions]
    cmp dword [edx+12], 0x100000
    jb .error

    call dword [edx+12]
    jc .error
    jmp .done
.resume_wavfile:
    mov edx, [wavfile_functions]
    cmp dword [edx+16], 0x100000
    jb .error

    call dword [edx+16]
    jc .error
    jmp .done
.stop_wavfile:
    mov edx, [wavfile_functions]
    cmp dword [edx+20], 0x100000
    jb .error

    call dword [edx+20]
    jc .error
.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret
.error:
    popa
    or dword [esp+8], 1
    iret


general_system:
    pusha

    cmp bh, 0x01
    je .get_sys_info
    cmp bh, 0x02
    je .reboot

    popa
    or dword [esp+8], 1
    iret
.reboot:
    mov eax, cr0
    and eax, 0xfffffffe
    mov cr0, eax

[bits 16]
    jmp far 0xffff:0x0000

[bits 32]
.get_sys_info:

    popa
    and dword [esp+8], 0xfffffffe
    iret


network_functions:
    pusha

    cmp byte [net_active], 1
    jne .no_network
    cmp byte [net_stack_loaded], 1
    jne .no_network

    cmp al, 0x01
    je .get_information
    cmp al, 0x02
    je .open_socket
    cmp al, 0x03
    je .send_packet
    cmp al, 0x04
    je .wait_packet
    cmp al, 0x05
    je .close_socket
    cmp al, 0x07
    je .resolve_dns

.error:
    popa
    or dword [esp+8], 1
    iret

.get_information:
    mov esi, NET_INTERFACE
    mov edx, packet_stats
    mov ebx, [edx]
    mov ebx, [ebx]
    mov [edi+20], ebx
    jmp .done
.open_socket:
    cmp bl, 0x03
    ja .error
    cmp bh, 0
    jne .error      ;IPv6 yet not supported

    mov edi, socket_list
    xor ecx, ecx
.loop:
    cmp word [edi], 0
    je .found_free

    inc ecx
    add edi, SOCKET_ENTRY_SIZE
    cmp ecx, 5
    jae .error
    jmp .loop

.found_free:
    mov ax, [current_task]
    mov [edi], ax       ;set PID field

    mov [edi+2], bl
    mov [edi+3], bh

    mov word [edi+4], 0
    mov [edi+6], esi    ;set buffer address

    mov ebp, ecx

    ; cmp bl, 0x01
    ; je .skip_port  ;ICMP doesnt use ports

    cmp dx, 0
    jne .custom_port

    mov edi, socket_list
    mov ecx, MAX_SOCKETS
    mov ax, 50000
.loop2:
    cmp word [edi+4], ax
    je .reset

    add edi, SOCKET_ENTRY_SIZE
    dec ecx
    jnz .loop2
    
    mov edi, ebp
    imul edi, SOCKET_ENTRY_SIZE
    add edi, socket_list
    mov [edi+4], ax

.skip_port:

    mov [.tmp16], bp
    popa

    mov cx, [.tmp16]
    and dword [esp+8], 0xfffffffe
    iret

.reset:
    inc ax
    cmp ax, 50007
    ja .error

    mov edi, socket_list
    mov ecx, MAX_SOCKETS
    jmp .loop2

.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret
.tmp16: dw 0
.custom_port:
    mov [edi+4], dx
    jmp .skip_port

.close_socket:
    movzx edi, cl
    imul edi, SOCKET_ENTRY_SIZE
    add edi, socket_list

    mov ax, [current_task]
    cmp ax, [edi]
    jne .error      ;not our PID

    mov ecx, SOCKET_ENTRY_SIZE
    xor al, al
    rep stosb

    jmp .done


.send_packet:
    push ebx
    shr ebx, 16
    mov bp, bx
    pop ebx

    cmp bp, 0
    je .error
    cmp ecx, 0
    je .error
    cmp ecx, 1500
    ja .error

    movzx edi, bp
    imul edi, SOCKET_ENTRY_SIZE
    add edi, socket_list

    mov al, [edi+2]
    cmp al, 0x01
    je .send_icmp
    cmp al, 0x02
    je .send_tcp
    cmp al, 0x03
    je .send_udp

    jmp .error
.send_icmp:
    mov ax, [edi+4]
    mov edi, NET_INTERFACE
    call dword [edi+32]
    jc .no_network

    jmp .done
.send_tcp:
    jmp .done
.send_udp:
    ;EAX (bit 16-31): destination port
    ;EAX (bit 0-15): source port
    ;ECX = length of packet
    ;EDX = IPv4 address
    ;ESI = pointer to packet
    mov ax, bx  ;destination port number
    shl eax, 16
    mov ax, [edi+4]
    mov edi, NET_INTERFACE
    call dword [edi+20]     ;add_udp_header()
    jc .no_network

    jmp .done

.wait_packet:
    ;CX = socket number
    movzx edi, cx
    imul edi, SOCKET_ENTRY_SIZE
    add edi, socket_list
    test byte [edi+3], (1 << 7)
    jnz .packet_received

    int 0x20
    jmp .wait_packet

.packet_received:
    and byte [edi+3], ~(1 << 7)
    jmp .done

;     push ecx
;     mov ah, 0x0a
;     mov ecx, 4
;     int 0x35
;     pop ecx

;     xor ebp, ebp

;     mov ebx, esi
;     mov edx, PACKET_WAIT_TIME
;     mov ah, 0x22
;     mov al, 0x02
;     int 0x35
;     jnc .wait_loop

;     mov ebp, 0xffffffff
; .wait_loop:
;     ;CX = socket number
;     movzx edi, cx
;     imul edi, SOCKET_ENTRY_SIZE
;     add edi, socket_list
;     test byte [edi+3], (1 << 7)
;     jnz .packet_received

;     cmp ebp, 0xffffffff
;     je .skip_check_timer

;     cmp dword [ebx], PACKET_WAIT_TIME
;     jae .error_wait
; .skip_check_timer:

;     int 0x20
;     jmp .wait_loop

; .packet_received:
;     and byte [edi+3], ~(1 << 7)

;     mov ecx, 4
;     mov ah, 0x0b
;     int 0x35
;     jmp .done

; .error_wait:
;     and byte [edi+3], ~(1 << 7)
;     mov ecx, 4
;     mov ah, 0x0b
;     int 0x35
;     jmp .error

.no_network:
    popa
    or dword [esp+8], 1
    mov eax, 0xffffffff
    mov ebx, eax
    mov ecx, eax
    mov edx, eax
    mov esi, eax
    mov edi, eax
    iret

.resolve_dns:
    push edi
    push ecx
    imul ecx, SOCKET_ENTRY_SIZE
    mov edi, socket_list
    add edi, ecx
    cmp byte [edi+2], 0x03      ;check if its an UDP socket
    pop ecx
    pop edi
    jne .error

    mov esi, edi
    call string_lowercase

    mov edi, dns_packet
    add edi, 13

    push ecx

    xor ebx, ebx
    mov ecx, 20
.loop_dns1:
    lodsb

    cmp al, 0x2e
    je .done_dns1

    stosb
    inc ebx
    dec ecx
    jnz .loop_dns1

    mov ebp, ecx
    pop ecx

    lodsb
    cmp al, 0x2e
    jne .error

    push ecx
    mov ecx, ebp

.done_dns1:
    mov edi, dns_packet
    mov [edi+12], bl

    add edi, 13     ;skip first 12 bytes + 1 byte length of domain
    add edi, ebx    ;skip domain name
    add edi, 1      ;skip length byte of domain ending
    mov edx, ebx

    xor ebx, ebx
    mov ecx, 5
.loop_dns2:
    lodsb
    cmp al, 0
    je .done_dns2

    stosb
    inc ebx
    dec ecx
    jnz .loop_dns2

    mov ebp, ecx
    pop ecx

    lodsb
    cmp al, 0
    jne .error

    push ecx
    mov ecx, ebp

.done_dns2:
    mov edi, dns_packet
    add edi, 13     ;skip first 12 bytes + 1 byte length of domain name
    add edi, edx    ;skip domain name
    mov [edi], bl   ;set length of ending
    inc edi         ;skip 'ending' byte
    add edi, ebx    ;skip ending

    xor al, al
    stosb           ;set null-termination

    mov word [edi], 0x0100
    mov word [edi+2], 0x0100

    pop ecx
    push ecx

    imul ecx, SOCKET_ENTRY_SIZE
    mov edi, socket_list
    add edi, ecx
    pop ecx

    mov ax, [current_task]
    cmp ax, [edi]
    jne .error

    push ecx

    mov eax, 53
    shl eax, 16
    mov ax, [edi+4]

    mov ecx, 19
    add ecx, ebx
    add ecx, edx
    mov esi, dns_packet

    mov edi, NET_INTERFACE
    mov edx, [edi+4]

    call dword [edi+20]

    pop ecx
    ;[ TODO ]: set timeout for packets of 4 seconds
.wait_packet_dns:
    movzx edi, cx
    imul edi, SOCKET_ENTRY_SIZE
    add edi, socket_list
    test byte [edi+3], (1 << 7)
    jnz .done_dns

    int 0x20
    jmp .wait_packet_dns

.done_dns:
    and byte [edi+3], ~(1 << 7)
    mov esi, [edi+6]

    mov edi, dns_packet
    add edi, 12

    mov ecx, 32/4
    xor eax, eax
    rep stosd

    add esi, 12
    call check_dns_packet
    jc .error_dns

    mov [.tmp_ip], edx
    mov [.tmp_ttl], eax

    popa
    mov edx, [.tmp_ip]
    mov eax, [.tmp_ttl]
    and dword [esp+8], 0xfffffffe
    iret

.error_dns:
    cmp ah, 0xff
    je .wait_packet_dns

    popa
    or dword [esp+8], 1
    iret

.tmp_ttl: dd 0
.tmp_ip: dd 0
check_dns_packet:
    ;ESI = pointer to packet
    ;Output: EDX = IPv4 address, EAX = TTL
    cmp word [esi], 0x7777
    jne .error2

    mov ax, [esi+6]
    xchg al, ah     ;swap bytes to get big endian
    cmp ax, 0
    je .error

    mov edi, esi
    add edi, 12
    ;skip domain name
    movzx eax, byte [edi]
    inc edi
    add edi, eax
    movzx eax, byte [edi]
    inc edi
    add edi, eax
    inc edi         ;skip null byte
    add edi, 4      ;skip QTYPE and QCLASS
    mov al, [edi]

    add edi, 2

    test al, (1 << 7)   ;test if there is the domain name again or just a pointer
    jnz .skip           ;if its just a pointer then skip

    sub edi, 2
    movzx eax, byte [edi]
    inc edi
    add edi, eax
    movzx eax, byte [edi]
    inc edi
    add edi, eax
.skip:
    cmp word [edi], 0x0100
    jne .error  ;no IPv4

    mov eax, [edi+4]     ;get TTL
    call swap

    add edi, 8

    mov bx, [edi]
    xchg bl, bh
    cmp bx, 4
    jne .error

    mov edx, [edi+2]    ;IPv4 address in big endian

    clc
    ret
.error:
    ;error with DNS packet
    xor ah, ah
    stc
    ret
.error2:
    ;it wasnt a DNS packet, wait longer
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

application_packet:
    ;ESI = pointer to packet
    ;ECX = size ## (if bit 15 is set, that means its an ICMP packet)
    ;AX = destination port ## (port of program, which waits for the packet) ## (big endian) ## (if its an ICMP packet, then this is the ID (in little endian))
    ;BX = source port ## (from sender) ## (big endian)
    ;EDX = source IPv4 address ## (from sender) ## (big endian)
    ;copy packet into program packet buffer
    push ecx
    mov edi, socket_list
    mov ecx, MAX_SOCKETS
    xchg al, ah     ;convert from Big Endian to Little Endian
.loop:
    cmp [edi+4], ax
    je .found_socket

    add edi, SOCKET_ENTRY_SIZE
    dec ecx
    jnz .loop

    pop ecx
    stc
    ret
.found_socket:
    mov ebp, edi

    mov edi, [edi+6]
    mov [edi], edx      ;big endian IPv4
    mov [edi+4], bx     ;big endian port
    pop ecx
    mov [edi+6], cx
    mov dword [edi+8], 0
    add edi, 12
    rep movsb

    or dword [ebp+3], (1 << 7)  ;packet received

    ret

;----data----
socket_list:
    ;limited to 5 available sockets

    ;reserved socket
    dw 0xff ;PID
    db 0    ;protocol (0x01 ICMP, 0x02 ARP, 0x03 UDP)
    db 0    ;IPv4 / IPv6, bit 7: 1 = packet received, 0 = no current packet
    dw 50000    ;port number
    dd 0    ;buffer address
    dw 0    ;options

    db 12 dup(0)
    db 12 dup(0)
    db 12 dup(0)
    db 12 dup(0)
    db 12 dup(0)

SOCKET_ENTRY_SIZE   equ 12
MAX_SOCKETS         equ 6
PACKET_WAIT_TIME    equ 4000    ;time in ms after which a packet counts as missing

; If program gets a packet copied in its buffer, it has a following header:
; struc packet_header:
;     dd source_ip      ;IPv4 address which sent the packet (big endian)
;     dw source_port    ;port, from where the packet came (big endian)
;     dw payload_length ;length of user data
;     dd packet_next    ;pointer to next packet if packets are fragmented (not implemented yet)

dns_packet:
    dw 0x7777   ;transaction ID
    dw 0x0001   ;flags, big endian: 0x0100
    dw 0x0100   ;questions count
    times 3 dw 0

    db 0        ;length of domain name (max. 20 bytes)
    times 20 db 0
    db 0        ;length of end (max. 5 bytes)
    times 5 db 0
    db 0        ;end of domain

    dw 0x0100   ;big endian: 0x0001 (ask for IPv4 address)
    dw 0x0100




timer_functions:
    cli
    pusha
    cmp al, 0x01
    je .sleep
    cmp al, 0x02
    je .set_counter
    cmp al, 0x03
    je .get_time

.error:
    popa
    or dword [esp+8], 1
    iret

; #### SLEEP ####
.sleep:
    mov edi, [sleep_timers_list]
    mov ecx, [max_sleep_timers]
.loop_sleep:
    cmp word [edi], 0xffff        ;deleted entry
    je .found_free
    cmp word [edi], 0
    je .found_free

    add edi, 8
    dec ecx
    jnz .loop_sleep
    jmp .error

.found_free:
    mov ax, [current_task]
    mov [edi], ax
    mov eax, ebx
    add eax, dword [system_tick]
    mov [edi+4], eax

    movzx edi, word [current_task]
    imul edi, TASK_SIZE
    add edi, tasks_esp

    mov dword [edi+11], 0x0000b100  ;sleeping
    sti
    int 0x20
    jmp .done

; #### COUNTERS ####
.set_counter:
    cmp edx, 0x80000000
    jae .error

    mov ecx, [max_counters]
    mov edi, [counters_list]
.set_loop:
    cmp dword [edi], 0xffff
    je .found_free_cntr
    cmp dword [edi], 0
    je .found_free_cntr

    add edi, 8
    dec ecx
    jnz .set_loop
    jmp .error

.found_free_cntr:
    mov [edi], ebx
    mov eax, edx
    add eax, dword [system_tick]
    mov [edi+4], eax
    jmp .done

; #### TIME ####
.get_time:
    xor bp, bp

    mov dx, 0x70
    mov al, 0x0b
    out dx, al

    mov dx, 0x71
    in al, dx

    test al, (1 << 2)
    jnz .binary_mode

    mov bp, 1

    mov dx, 0x70
    xor al, al
    out dx, al

    mov dx, 0x71
    in al, dx   ;get seconds
    call bcd_convert_byte

    mov bh, al

    mov dx, 0x70
    mov al, 0x02
    out dx, al

    mov dx, 0x71
    in al, dx   ;get minutes
    call bcd_convert_byte

    mov ah, al
    mov al, bh

    push ax     ;push seconds (AL) and minutes (AH) to stack
    jmp .hour_format

.binary_mode:
    mov dx, 0x70
    xor al, al
    out dx, al

    mov dx, 0x71
    in al, dx   ;get seconds
    mov ah, al

    mov dx, 0x70
    mov al, 0x02
    out dx, al

    mov dx, 0x71
    in al, dx   ;get minutes

    xchg al, ah
    
    push ax     ;push seconds (AL) and minutes (AH) to stack

.hour_format:

    mov dx, 0x70
    mov al, 0x0b
    out dx, al

    mov dx, 0x71
    in al, dx

    test al, (1 << 1)
    jnz .24hour_format

    mov dx, 0x70
    mov al, 0x04
    out dx, al

    mov dx, 0x71
    in al, dx   ;get hour (0 - 23)
    mov bl, al

    test bl, (1 << 7)
    jz .get_month

    and bl, ~(1 << 7)
    add bl, 12

    cmp bl, 24
    jne .get_month

    xor bl, bl
    jmp .get_month
.24hour_format:
    mov dx, 0x70
    mov al, 0x04
    out dx, al

    mov dx, 0x71
    in al, dx   ;get hour (0 - 23)
    mov bl, al

.get_month:
    push bx

    mov dx, 0x70
    mov al, 0x07
    out dx, al

    mov dx, 0x71
    in al, dx

    cmp bp, 1
    jne .not_bcd1

    call bcd_convert_byte
.not_bcd1:
    mov cl, al

    mov dx, 0x70
    mov al, 0x08
    out dx, al

    mov dx, 0x71
    in al, dx

    cmp bp, 1
    jne .not_bcd2

    call bcd_convert_byte
.not_bcd2:
    mov ch, al

    push cx

    mov dx, 0x70
    mov al, 0x09
    out dx, al

    mov dx, 0x71
    in al, dx

    cmp bp, 1
    jne .not_bcd

    call bcd_convert_byte
.not_bcd:
    mov dl, al

    mov dh, 20      ;century
    cmp al, 85
    jb .skip

    mov dh, 19
.skip:

    pop cx
    pop bx

    push bx
    push cx

    mov bl, cl
    mov bh, ch
    movzx ecx, dh
    imul ecx, 100   ;century * 100
    movzx esi, dl
    add ecx, esi

    call get_weekday

    pop cx
    pop bx
    mov bh, al
    pop ax
    cli
    hlt
.done:
    popa
    and dword [esp+8], 0xfffffffe
    iret

check_timers:
    ;check first sleep timers
    mov edi, [sleep_timers_list]
    mov ecx, [max_sleep_timers]
.loop:
    cmp word [edi], 0xffff
    je .skip
    cmp word [edi], 0
    je .done_sleep

    mov eax, [system_tick]
    sub eax, [edi+4]
    js .skip

    movzx esi, word [edi]
    imul esi, TASK_SIZE
    add esi, tasks_esp

    mov dword [esi+11], 0
    mov word [edi], 0xffff
    mov dword [edi+4], 0
.skip:
    add edi, 8
    dec ecx
    jnz .loop

.done_sleep:
    mov edi, [counters_list]
    mov ecx, [max_counters]
.loop2:
    cmp dword [edi], 0xffff
    je .skip2
    cmp dword [edi], 0
    je .done

    mov esi, [edi]
    inc dword [esi]     ;increase counter

    mov eax, [system_tick]
    sub eax, [edi+4]
    js .skip2

    mov dword [edi], 0xffff
    mov dword [edi+4], 0
.skip2:
    add edi, 8
    dec ecx
    jnz .loop2

.done:
    ret


get_weekday:
    ;BL = day (1-31)
    ;BH = month (1-12)
    ;CX = year (for example 2027)

    ;Output: AL = weekday (0 = sunday, 1 = monday...)
    push ebx
    push ecx
    push edx
    push esi
    push edi

    movzx eax, bh
    cmp al, 3
    jge .not_first2
    dec cx
.not_first2:
    movzx edi, cx
    mov eax, edi
    shr eax, 2
    add eax, edi
    mov esi, eax

    mov eax, edi
    xor edx, edx
    mov ecx, 100
    div ecx
    add esi, eax

    movzx eax, bh
    dec eax
    mov edx, t_table
    movzx edx, byte [edx+eax]
    add esi, edx

    movzx eax, bl
    add esi, eax

    mov eax, esi
    xor edx, edx
    mov ecx, 7
    div ecx

    mov al, dl

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
t_table: db 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4