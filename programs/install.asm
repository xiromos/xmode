;==================================================================================
;program to install Xiromos-X32 to a drive
;==================================================================================

section .text
start:
    xor ebx, ebx
    mov ecx, 0xffffff
    mov esi, window_title
    call init_window

.start:
    mov esi, language_str
    xor ebx, ebx
    call print_string

    mov edi, input_buffer
    mov ecx, 1
.get_input1:
    mov byte [edi], 0

    call get_input
    cmp byte [edi], 'q'
    je .exit
    cmp byte [edi], 'Q'
    je .exit
    cmp byte [edi], '2'
    jbe .get_drive

.lang_err:
    cmp byte [edi], 0
    je .get_input1

    call rm_char
    jmp .get_input1

.get_drive:
    cmp byte [edi], '0'
    jb .lang_err

    mov al, [edi]
    sub al, '0'
    mov [lang_index], al

    call print_newline
    call print_newline

    mov ah, 0x21
    int 0x33
    mov [cur_drive], al

    mov ah, [lang_index]
    mov al, 1                   ;current drive string
    call print_string_lang

    mov al, [cur_drive]
    add al, 0x41
    xor ah, ah
    xor ebx, ebx
    call print_char
    call print_newline

    mov ah, [lang_index]
    mov al, 0                   ;chose drive string
    call print_string_lang

    mov ecx, 140
    mov ah, 0x0a
    int 0x35

    mov ah, 0x23
    mov al, 10
    mov edi, esi
    int 0x33

    cmp al, 0
    je .exit

    cmp al, 10
    jbe .skip

    mov al, 10
.skip:
    push esi
    movzx ecx, al
    call print_drives
    pop esi

    mov ecx, 140
    mov ah, 0x0b
    int 0x35

    mov ax, '>'
    xor ebx, ebx
    call print_char
    mov ax, ' '
    call print_char

    mov edi, input_buffer
    mov ecx, 1
.get_input2:
    mov byte [edi], 0
    call get_input

    cmp byte [edi], 0
    je .get_input2

    cmp byte [edi], 0x61
    jb .skip2

    sub byte [edi], 0x20
.skip2:
    cmp byte [edi], 'Q'
    je .exit

    cmp byte [edi], 'B'
    ja .check_drive

    call rm_char
    jmp .get_input2

.check_drive:
    mov al, [edi]
    mov ebx, 10
    mov esi, drive_list
.loop:
    cmp byte [esi], al
    je .valid_drive

    inc esi
    dec ebx
    jnz .loop

    call rm_char
    jmp .get_input2
.valid_drive:
    push ax
    sub ax, 0x41
    cmp al, [cur_drive]
    jne .skip3
    pop ax

    mov esi, already_installed
    call show_window

    call rm_char
    jmp .get_input2
.skip3:
    pop ax
    call print_newline

    push ax
    mov ah, [lang_index]
    mov al, 2       ;all data will be deleted string
    call print_string_lang
    pop ax

    mov ecx, 1
    mov edi, input_buffer
.get_input3:
    mov byte [edi], 0
    call get_input

    cmp byte [edi], 'y'
    je .install
    cmp byte [edi], 'Y'
    je .install
    cmp byte [edi], 'n'
    je .abort
    cmp byte [edi], 'N'
    je .abort

    call rm_char
    jmp .get_input3

.abort:
    call clear_window
    jmp .start
.install:
    call print_newline
    push ax
    mov ah, [lang_index]
    mov al, 3                   ;format disk
    call print_string_lang
    pop ax

    sub al, 0x41
    mov [drive_number], al
    mov bx, 20480       ;10MB
    mov ah, 0x22
    int 0x33
    jnc .continue

.error:
    mov esi, error_str
    call show_window

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35

    xor ah, ah
    int 0x31
    call clear_window
    jmp .start
.continue:
    push ax
    mov ah, [lang_index]
    mov al, 4                   ;done
    call print_string_lang
    mov ah, [lang_index]
    mov al, 6                   ;copy files
    call print_string_lang
    pop ax

    call print_newline
    mov ax, '['
    xor ebx, ebx
    call print_char

    ;/EFI/BOOT/BOOTX64.EFI
    mov ah, 0x07
    mov esi, bootx64_efi
    mov edi, bootx64_efi
    mov al, [drive_number]
    int 0x33
    jc .error

    mov ax, '#'
    xor ebx, ebx
    call print_char

    ;/XMODE.BIN
    mov ah, 0x07
    mov esi, xmode_bin
    mov edi, xmode_bin
    mov al, [drive_number]
    int 0x33
    jc .error

    mov ax, '#'
    xor ebx, ebx
    call print_char

    ;/XCONFIGS/DEFAULT.FNT
    mov ah, 0x07
    mov esi, default_fnt
    mov edi, default_fnt
    mov al, [drive_number]
    int 0x33
    jc .error

    mov ax, '#'
    xor ebx, ebx
    call print_char

    mov ax, ']'
    xor ebx, ebx
    call print_char
    call print_newline

    mov ah, [lang_index]
    mov al, 7               ;installation completed
    call print_string_lang

    xor ah, ah
    int 0x31

    call clear_window

    mov esi, header
    xor ebx, ebx
    call print_string

    mov ah, [lang_index]
    mov al, 8       ;current time
    call print_string_lang

    mov ecx, 2
    mov edi, input_buffer
.get_input4:
    mov word [edi], 0
    call get_input

    cmp byte [edi], '0'
    jb .not_valid
    cmp byte [edi+1], '0'
    jb .not_valid

    cmp byte [edi], '9'
    ja .not_valid
    cmp byte [edi+1], '9'
    ja .not_valid
    jmp .correct_time

.not_valid:
    call rm_char
    cmp byte [edi+1], 0
    je .get_input4

    call rm_char
    jmp .get_input4

.correct_time:
    mov ax, [edi]
    mov [utc_offset], ax

    call print_newline

    mov ah, [lang_index]
    mov al, 9           ;username
    call print_string_lang

    mov ecx, 31
    mov edi, input_buffer
    push edi
    push ecx
    mov al, 0
    rep stosb
    pop ecx
    pop edi
    call get_input

    mov esi, input_buffer
    mov edi, username
    mov ecx, 31
    rep movsb

    call print_newline
    mov ah, [lang_index]
    mov al, 10           ;done
    call print_string_lang

    xor ah, ah
    int 0x31

.exit:
    call end_program
    mov ah, 0x05
    int 0x35

print_string_lang:
    ;AH = language index
    ;AL = string index

    push ebx
    push esi

    cmp ah, 1
    je .rus
    cmp ah, 2
    je .bel

    mov esi, eng_table
    jmp .offset
.rus:
    mov esi, rus_table
    jmp .offset
.bel:
    mov esi, bel_table
.offset:
    movzx eax, al
    shl eax, 2
    add esi, eax
    mov esi, [esi]

    xor ebx, ebx
    call print_string
    pop esi
    pop ebx
    ret

get_input:
    ;EDI = pointer to buffer
    ;ECX = buffer length
    pusha
    xor ebx, ebx
.loop:
    xor ah, ah
    int 0x31
    cmp al, 0
    je .loop

    cmp al, 0x08
    je .backspace
    cmp al, 0x0d
    je .done

    cmp ebx, ecx
    jae .loop

    push ebx
    mov ebx, COLOR_GREEN
    xor ah, ah
    call print_char
    pop ebx

    inc ebx
    stosb
    jmp .loop

.backspace:
    cmp ebx, 0
    je .loop
    dec ebx
    dec edi
    mov byte [edi], 0

    push ebx
    mov ax, 0x08
    call print_char

    mov ax, 0x20
    call print_char

    mov ax, 0x08
    call print_char
    pop ebx
    jmp .loop
.done:
    popa
    ret

rm_char:
    mov ax, 0x08
    xor ebx, ebx
    call print_char
    mov ax, 0x20
    call print_char
    mov ax, 0x08
    call print_char
    ret
print_drives:
    ;EDI = *buffer
    ;ECX = number of drives
    movzx ax, byte [edi]
    ;skip floppy disks
    cmp al, 'A'
    je .next
    cmp al, 'B'
    je .next

    xor ebx, ebx
    call print_char
    mov ax, ':'
    call print_char
    mov ax, ' '
    call print_char

    cmp byte [edi+1], 0xaa
    je .ahci
    cmp byte [edi+1], 0xde
    je .ide
    cmp byte [edi+1], 0xbe
    je .usb
    cmp byte [edi+1], 0xee
    je .nvme

.next:
    add edi, 14
    dec ecx
    jnz print_drives
    ret
.ahci:
    mov esi, ahci_str
    call print_string
    jmp .size
.ide:
    mov esi, ide_str
    call print_string
    jmp .size
.usb:
    mov esi, usb_str
    call print_string
    jmp .size
.nvme:
    mov esi, nvme_str
    call print_string
.size:
    mov al, [edi]
    mov ebx, drive_list
    add ebx, dword [drive_list_off]
    mov [ebx], al
    add dword [drive_list_off], 1

    mov ax, '('
    xor ebx, ebx
    call print_char

    ;64bit LBA not supported yet
    mov eax, [edi+2]
    imul eax, dword [edi+10]

    xor edx, edx
    mov ebx, 1000
    div ebx

    call print_dec

    mov ax, 'K'
    xor ebx, ebx
    call print_char
    mov ax, 'B'
    call print_char
    mov ax, ')'
    call print_char
    call print_newline
    jmp .next

show_window:
    ;ESI = *string

    pusha
    push esi
    mov ah, 0x05
    int 0x34

    shr eax, 1
    sub eax, 125
    mov esi, eax    ;X

    mov dword [win_packet+16], eax
    mov dword [win_packet+24], eax

    shr ebx, 1
    sub ebx, 45
    mov edi, ebx    ;Y

    mov dword [win_packet+20], ebx
    mov dword [win_packet+28], ebx

    mov ecx, 250
    mov edx, 90
    mov ebx, 0x00ffffff
    mov ebp, info_msg
    mov ah, 0x01
    int 0x34
    pop esi
    mov [id], ax

    mov edi, win_packet
    mov ah, 0x0a
    int 0x30

    mov edi, win_packet
    mov ah, 0x0c
    int 0x30
    mov edi, win_packet
    mov ah, 0x0c
    int 0x30

    mov esi, exit_str
    mov edi, win_packet
    mov ah, 0x0a
    int 0x30

    mov ah, 0x22
    mov al, 1
    mov ebx, 500
    int 0x35

    xor ah, ah
    int 0x31

    mov edi, win_packet
    mov ah, 0x02
    mov bx, [id]
    int 0x34
    popa
    ret

print_dec:
    pusha
    xor ecx, ecx
    mov ebx, 10
.div_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    cmp eax, 0
    jne .div_loop
.print_loop:
    pop eax
    add al, '0'
    xor ah, ah
    push ebx
    xor ebx, ebx
    call print_char
    pop ebx
    loop .print_loop
    popa
    ret

%include "includes/stdfunc.inc"
section .data
window_title: db 'Setup', 0
lang_index: db 0
;0 = english
;1 = russian
input_buffer: times 32 db 0
cur_drive: db 0
drive_list: times 10 db 0
drive_list_off: dd 0
drive_number: db 0
utc_offset: dw 0
username: times 32 db 0

info_msg: db 'Info', 0
already_installed: db 'Already installed to this disk', 0
exit_str: db '(Press any key to close window)', 0
error_str: db 'An error occured. Try again', 0
header: db '+- Settings', 0x0a, 0


ahci_str: db 'SATA Device ', 0
ide_str: db 'IDE Device ', 0
usb_str: db 'USB Mass Storage Device ', 0
nvme_str: db 'NVME SSD ', 0

bootx64_efi: db '/efi/boot/bootx64.efi', 0
xmode_bin: db '/xmode.bin', 0
default_fnt: db '/xconfigs/default.fnt', 0

language_str: db 'Выберите язык (Choose a language)', 0x0a,
              db '(0 = eng, 1 = рус, 2 = бел): ', 0

rus_table:
    dd drive_rus
    dd cur_drive_rus
    dd warning_rus
    dd format_rus
    dd done_rus
    dd error_rus
    dd copy_files_rus
    dd done_install_rus
    dd time_rus
    dd username_rus
    dd done_program_rus

bel_table:
    dd drive_bel
    dd cur_drive_bel
    dd warning_bel
    dd format_bel
    dd done_bel
    dd error_bel
    dd copy_files_bel
    dd done_install_bel
    dd time_bel
    dd username_bel
    dd done_program_bel

eng_table:
    dd drive_eng
    dd cur_drive_eng
    dd warning_eng
    dd format_eng
    dd done_eng
    dd error_eng
    dd copy_files_eng
    dd done_install_eng
    dd time_eng
    dd username_eng
    dd done_program_eng

drive_rus: db 'Выберите диск на котором вы хотите установить OC:', 0x0a, 0
cur_drive_rus: db 'Текущий диск: ', 0
warning_rus: db 'Внимание: Все ваши данные на этом диске будут удалены. Продолжать? (y/n): ', 0
format_rus: db 'Форматирование диска (это может занять некоторое время)...', 0
done_rus: db 'Готово', 0x0a, 0
error_rus: db 'Ошибка. Нажмите любую клавишу', 0
copy_files_rus: db 'Копирование файлов...', 0
done_install_rus: db 'Всё установлено! Нажмите любую клавишу чтобы продолжить', 0
time_rus: db '|', 0x0a
          db '+- Ваше смещние от всемирного координированного времени: ', 0
username_rus: db ' |', 0x0a,
              db ' +- Введите своё имя пользователя: ', 0
done_program_rus: db '  |', 0x0a,
                  db '  +- Всё готово! Нажмите любую клавишу чтобы продолжить.', 0


drive_bel: db 'Абярыце дыск на якім вы хочаце ўсталяваць OC:', 0x0a, 0
cur_drive_bel: db 'Бягучы дыск: ', 0
warning_bel: db 'Увага: усе вашыя дадзеныя на гэтым дыску будуць выдаленыя. Працягнуць? (y/n): ', 0
format_bel: db 'Фарматаванне дыска (гэта можа заняць некаторы час)...', 0
done_bel: db 'Гатова', 0x0a, 0
error_bel: db 'Памылка. Націсніце любую клавішу', 0
copy_files_bel: db 'Капіраванне файлаў...', 0
done_install_bel: db 'Усё ўстаноўлена! Націсніце любую клавішу каб працягнуць', 0
time_bel: db '|', 0x0a
          db '+- Ваша зрухі ад сусветнага каардынаванага часу: ', 0
username_bel: db ' |', 0x0a,
              db ' +- Увядзіце сваё імя карыстальніка: ', 0
done_program_bel: db '  |', 0x0a,
                  db '  +- Усё гатова! Націсніце любую клавішу, каб працягнуць', 0


drive_eng: db 'Choose a drive to install on:', 0x0a, 0
cur_drive_eng: db 'Current drive: ', 0
warning_eng: db 'Warning: All data on this drive will be deleted. Continue? (y/n): ', 0
format_eng: db 'Formatting drive (this might take a while)... ', 0
done_eng: db 'Done', 0x0a, 0
error_eng: db 'Error. Press any key', 0
copy_files_eng: db 'Copying files...', 0
done_install_eng: db 'Installation completed! Press a key to continue', 0
time_eng: db '|', 0x0a,
          db '+- Your time offset from UTC: ', 0
username_eng: db ' |', 0x0a,
              db ' +- Enter your username: ', 0
done_program_eng: db '  |', 0x0a,
                  db '  +- Everything was set up successfully! Press a key to continue', 0

win_packet:
    dd 0            ;foreground color
    dd 0x00ffffff   ;background color
    dd 250          ;width
    dd 90           ;height
    dd 0            ;CurX
    dd 0            ;CurY
    dd 0            ;original CurX
    dd 0            ;original CurY

id: dw 0