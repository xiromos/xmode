;AH = 0x14: functions for BIN programs
;   AL = 1: start a foreground task of .bin program                                                     ;EBX = pointer to directory, ESI = pointer to taskname, EDI = pointer to filename
;   AL = 2: start a background task of .bin program                                                     ;EBX = pointer to directory, ESI = pointer to taskname, EDI = pointer to filename
;   AL = 3: map a single page                                                                           ;EBX = virtual address, ECX = physical address

bin_prog_functions:
    cmp al, 1
    je .bin_start_task
    cmp al, 2
    je .bin_start_task
    cmp al, 3
    je .map_page

    or dword [esp+8], 1
    iret

.bin_start_task:
    ;ESI = Task Name
    ;EDI = filename
    ;EBX = pointer to directory

    ;0xffffffff = no argument
    ;all arguments have to be null-terminated
    ;ECX = pointer to first argument
    ;EDX = pointer to second argument
    ;EBP = pointer to other arguments (which are stored in a structure for example)

    pusha
    cmp esi, 0
    je .error
    cmp edi, 0
    je .error

.wait:
    cmp byte [.task_state], 0
    jne .wait

    cli
    mov [.task_state], al

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
    jc .error2

    mov ax, [max_tasks]
    cmp word [task_count], ax
    jae .error2

    mov ebx, ecx        ;amount of heap memory
    mov ah, 0x0a        ;allocate heap memory for program
    int 0x35
    jc .error2

    ;ESI = pointer to heap memory start
    mov [.program_start], esi
    mov [.size], ecx

    pop ebx
    pop esi
    mov ebp, esi

    ;load program into memory
    mov ah, 0x0a
    mov edx, ebx
    mov edi, [.program_start]
    mov bl, [drive_number]
    int 0x33
    jc .error

    mov dx, [task_slots]
    ;dec dx                  ;skip PID 1
    mov ecx, 2
    mov esi, ebp

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
    jmp .error
.found_slot:

    push esi
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop esi

    mov [kernel_stack], esp

    ;allocating page directory
    push eax
    push ecx
    mov ax, [current_task]
    push ax
    mov [current_task], cx
    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35
    mov [.page_dir], esi

    mov edi, esi
    xor eax, eax
    mov ecx, 0x1000/4
    rep stosd

    mov eax, BIN_PROG_ADDR
    mov ebx, [.program_start]
    mov ecx, [.size]
    mov esi, [.page_dir]
    call map_region2

    pop ax
    mov [current_task], ax
    pop ecx
    pop eax

    mov eax, program_stack_off
    imul eax, ecx
    add eax, program_stack

    ;map stack
    push eax
    push ecx
    mov ebx, eax
    sub ebx, 0x1000
    mov eax, BIN_STACK-0x1000
    mov ecx, 0x1000
    mov esi, [.page_dir]
    call map_region2

    ;map kernel
    mov eax, 0x8000
    mov ebx, 0x8000
    mov ecx, 0x100000-0x8000
    mov esi, [.page_dir]
    call map_region2
    pop ecx
    pop eax

    mov esp, eax
    mov ebx, BIN_STACK
    sub ebx, 16

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
    push ebx
    push dword 0x202        ;enable interrupt flag
    push dword code_off_user;CS
    push dword BIN_PROG_ADDR

    pushad
    push dword (3*8) | 3    ;DS
    push dword (3*8) | 3    ;ES
    push dword (3*8) | 3    ;FS
    push dword (3*8) | 3    ;GS

    mov eax, BIN_STACK
    sub eax, 80

    movzx edi, cx
    imul edi, TASK_SIZE
    add edi, tasks_esp
    mov [edi+15], eax
    mov eax, [.program_start]
    mov [edi+19], eax
    mov eax, [.size]
    mov [edi+23], eax
    mov eax, [.buffer_start]
    mov [edi+27], eax
    mov eax, [.buffer_size]
    mov [edi+31], eax
    mov dword [edi+35], 0
    or byte [edi+35], TASK_FLAG2_BIN
    mov eax, [.page_dir]
    mov [edi+39], eax

    inc word [task_count]
    cmp byte [.task_state], 1
    jne .skip

    mov [main_task], cx
.skip:
    mov esp, [kernel_stack]
    mov byte [.task_state], 0

    sti

    int 0x20

    popa
    and dword [esp+8], 0xfffffffe
    iret

.error2:
    pop ebx
    pop esi
.error:
    mov byte [.task_state], 0
.error3:
    popa
    or dword [esp+8], 1
    iret

.program_start: dd 0
.size: dd 0
.buffer_start: dd 0     ;address of BSS buffer
.buffer_size: dd 0      ;size of BSS buffer
.page_dir: dd 0
.task_state: db 0       ;foreground / background
.first_arg: dd 0
.second_arg: dd 0
.other_args: dd 0

BIN_STACK   equ 0x3ff000
BIN_KERNEL_STACK    equ 0x400000
BIN_PROG_ADDR       equ 0x400000

.map_page:
    pusha
    mov ah, 0x09
    mov al, 2
    int 0x35

    test al, TASK_FLAG2_BIN
    jz .error3

    mov eax, cr3
    mov esi, eax
    mov eax, ebx
    mov ebx, ecx
    mov ecx, 0x1000
    call map_region2
    popa
    and dword [esp+8], 0xfffffffe
    iret

map_region2:
    ;EAX = virtual address
    ;EBX = physical address
    ;ECX = size in bytes
    ;ESI = poiner to page directory
    pusha
    cmp ecx, 0
    je .error

    push eax
    push ebx
    xor edx, edx
    mov eax, ecx
    add eax, 4095
    mov ebx, 4096
    div ebx
    
    mov ecx, eax    ;number of pages
    pop ebx
    pop eax
.loop:
    ;get page directory index
    mov edx, eax
    shr edx, 22
    imul edx, 4

    mov edi, esi
    add edi, edx

    ;get page table index
    mov edx, eax
    and edx, 0x3fffff
    shr edx, 12
    imul edx, 4

    cmp dword [edi], 0
    jne .skip

    push eax
    push ecx
    push esi

    ;get heap
    mov ah, 0x0a
    mov ecx, 0x1000
    int 0x35
    or esi, PAGE_PRESENT | PAGE_RW | PAGE_USER
    mov [edi], esi

    push edi
    mov edi, esi
    and edi, 0xfffff000

    xor eax, eax
    mov ecx, 0x1000/4
    rep stosd
    pop edi

    pop esi
    pop ecx
    pop eax
.skip:
    mov ebp, [edi]
    and ebp, 0xfffff000
    add ebp, edx

    push ebx
    or ebx, PAGE_PRESENT | PAGE_RW | PAGE_USER
    mov [ebp], ebx
    pop ebx

    add eax, 0x1000
    add ebx, 0x1000
    dec ecx
    jnz .loop

    popa
    clc
    ret

.error:
    stc
    ret

get_physical_address:
    ;EAX = virtual address
    ;ESI = pointer to page directory
    ;Output: EAX = physical address or CF if the page isnt mapped
    pusha

    ;get page directory index
    mov edx, eax
    shr edx, 22
    imul edx, 4

    mov edi, esi
    add edi, edx

    cmp dword [edi], 0
    je .error

    ;get page table index
    mov edx, eax
    and edx, 0x3fffff
    shr edx, 12
    imul edx, 4

    mov ebp, [edi]
    and ebp, 0xfffff000
    add ebp, edx

    mov eax, [ebp]
    and eax, 0xfffff000
    mov [.tmp], eax

    popa
    mov eax, [.tmp]
    ret

.tmp: dd 0
.error:
    popa
    stc
    ret