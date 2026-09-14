code_off        equ 0x08
data_off        equ 0x10
code_off_user   equ (4*8) | 3
vidmem          equ 0xb8000
col             equ 80
line            equ 25
COLOR_RED       equ 0x00c21515
COLOR_GREEN     equ 0x001bcc49
cur: dd 0
gdt_loaded_msg: db '> GDT loaded', 0
idt_loaded_msg: db '> IDT loaded', 0
starting_shell_msg: db '> Starting shell...', 0
interupt_msg: db 'Interupt!', 0
start_msg: db '< XiromosX32 Shell >', 0x0a,
           db 'Type "help" for help', 0
prompt_msg: db '# ', 0
argument: dd 0
argument2: dd 0
scan_codes:
    db 0                  ; 0x00
    db 27                 ; ESC

    db '1','2','3','4','5','6','7','8','9','0'
    db '-','=',8          ; Backspace
    db 9                 ; Tab

    db 'q','w','e','r','t','z','u','i','o','p'
    db '[',']',13        ; Enter

    db 0                 ; Ctrl
    db 'a','s','d','f','g','h','j','k','l'
    db ';',"'",'`'

    db 0                 ; Left Shift
    db '\','y','x','c','v','b','n','m'
    db ',', '.', '/'

    db 0                 ; Right Shift
    db '*'              ; Numpad *
    db 0                ; Alt
    db ' '              ; Space
    db 0                ; Caps Lock

    ; F1–F10
    db 0x3b,0x3c,0x3d,0x3e,0x3f,0x40,0x41,0x42,0x43,0x44

    ; More control keys
    db 0                ; Num Lock
    db 0                ; Scroll Lock

    ; Numpad
    db '7','8','9','-'
    db '4','5','6','+'
    db '1','2','3','0'
    db '.'
.keycode_table:
    db KEY_NONE                 ; 0x00
    db KEY_ESC                  ; 0x01
    db KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0 ; 0x02 - 0x0B
    db KEY_NONE, KEY_NONE       ; 0x0C - 0x0D ('-' und '=')
    db KEY_BACKSPACE            ; 0x0E
    db KEY_TAB                  ; 0x0F
    db KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P ; 0x10 - 0x19
    db KEY_NONE, KEY_NONE       ; 0x1A - 0x1B ('[' und ']')
    db KEY_ENTER                ; 0x1C
    db KEY_LCTRL                ; 0x1D
    db KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L ; 0x1E - 0x26
    db KEY_NONE, KEY_NONE, KEY_NONE ; 0x27 - 0x29
    db KEY_LSHIFT               ; 0x2A
    db KEY_NONE                 ; 0x2B
    db KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M ; 0x2C - 0x32
    db KEY_NONE, KEY_NONE, KEY_NONE ; 0x33 - 0x35
    db KEY_RSHIFT               ; 0x36
    db KEY_NONE                 ; 0x37
    db KEY_LALT                 ; 0x38
    db KEY_SPACE                ; 0x39
    db KEY_NONE                 ; 0x3A (Caps Lock)
    db KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10 ; 0x3B - 0x44
    times (0x57 - 0x45) db KEY_NONE
    db KEY_F11                  ; 0x57
    db KEY_F12                  ; 0x58
    
    times (128 - 0x58) db KEY_NONE
keymap_shift:
    db 0, 27, '!','@','#','$','%','^','&','*','(',')','_','+', 8
    db 9
    db 'Q','W','E','R','T','Z','U','I','O','P','{','}', 13
    db 0
    db 'A','S','D','F','G','H','J','K','L',':','"','~'
    db 0
    db '|','Y','X','C','V','B','N','M','<','>','?'
    db 0
    db '*'
    db 0
    db ' '
    db 0                ; Caps Lock

    ; F1–F10
    db 0x8b,0x8c,0x8d,0x8e,0x8f,0x90,0x91,0x92,0x93,0x94

    ; More control keys
    db 0                ; Num Lock
    db 0                ; Scroll Lock

    ; Numpad
    db '7','8','9','-'
    db '4','5','6','+'
    db '1','2','3','0'
    db '.'

key_buffer: times 256 db 0
buf_head:   dd 0
buf_tail:   dd 0
KEY_BUFFER      equ 0x50000
KEY_BUFFER_SIZE equ 256
BUFFER_HEAD     equ 0x57000
BUFFER_TAIL    equ 0x57100
shift: db 0
vbe_info: times 256 db 0
rows: dd 16
width       equ 1024
height      equ 768
max_rows    equ 48      ;768 / 16

real_width: dd 1024
real_height: dd 768

bpp: db 0
pitch: dd 0
cur_x: dd 0
cur_y: dd 0
color: dd 0
bgcolor: dd 0
user_stack  equ 0x9fb00     ;0x91000
program_stack   equ 0x1a0000
program_stack_off   equ 0x1000      ; ~4KB
kernel_stack dd 0
tss:
    dd 0    ; dd prev_tss
    dd 0   ; dd esp0
    dd 0   ; dd ss0
    dd 0   ; dd esp1
    dd 0   ; dd ss1
    dd 0   ; dd esp2
    dd 0   ; dd ss2
    dd 0   ; dd ctr3
    dd 0   ; dd einsp
    dd 0   ; dd extflags
    dd 0   ; dd _eax
    dd 0   ; dd _ecx
    dd 0   ; dd _edx
    dd 0   ; dd _ebx
    dd 0   ; dd _esp
    dd 0   ; dd _ebp
    dd 0   ; dd _esi
    dd 0   ; dd _edi
    dd 0   ; dd _es
    dd 0   ; dd _cs
    dd 0   ; dd _ss
    dd 0   ; dd _ds
    dd 0   ; dd _fs
    dd 0   ; dd _gs
    dd 0   ; dd _ldt
    dw 0   ; dw _trap
    dw 0   ; dw iomap_base
.end:
hex4_out: db '0x0000', 0
hex8_out: db '0x00000000', 0
mmap_buffer     equ 0x1ff000
mmap_entries: dd 0
mmap_str: db 'Memory Map:           1 - Usable / 2 - Reserved', 0
memmap_str: db 'MMAP', 0
mmap_bytes_per_entry: db 'Bytes per Entry: ', 0
;commands
help_msg: db 'In progress...', 0
help_str: db 'HELP', 0
clear_str: db 'CLEAR', 0
ls_str: db 'LS', 0
read_str: db 'READ', 0
del_str: db 'DEL', 0
rename_str: db 'RENAME', 0
write_str: db 'WRITE', 0
tasklist_str: db 'TASKLIST', 0
pci_str: db 'PCI', 0
taskkill_str: db 'TASKKILL', 0
ahci_str: db 'AHCI', 0
lsdisk_str: db 'LSDISK', 0
cdisk_str: db 'CDISK', 0
osdev_discord_str: db 'OSDEVDISCORD', 0
usb_str: db 'USB', 0
bgcolor_str: db 'BGCOLOR', 0
cd_str: db 'CD', 0
meminfo_str: db 'MEMINFO', 0
reboot_str: db 'REBOOT', 0
dhcp_str: db 'DHCP', 0
command_buffer: db 50 dup(0)
setbgcolor_helpmsg: db 'Set Background Color.', 0x0a,
                    db 'Usage: ', 0
setbgcolor_helpmsg2: db 'bgcolor #abcdef', 0
configs_load_err: db '> Error while applying config files. Loaded standard configs', 0
;disk
fs_loading_str: db '> Loading FAT16...', 0
disk_lba:           ;extended read/write needs a structure which points to the LBA
    db 0
    db 0
    db 0
    db 0
    db 0
    db 0
align 4
prdt:
    dd 0x00005000            ;buffer
    dw 512                   ;sector size
    dw 0x8000
pci_bus: db 0
pci_device: db 0
pci_function: db 0
bm_base: dd 0
bm_base4: dw 0

pci_addr     equ 0x8a200
pci_bus_str: db 'BUS ', 0
pci_device_str: db 'DEVICE ', 0
pci_function_str: db 'FUNCTION ', 0
pci_vendorid_str: db 'VENDOR ', 0
pci_deviceid_str: db 'DEVICE ID ', 0
pci_class_str: db 'CLASS ', 0
pci_subclass_str: db 'SUBCLASS ', 0
abar: dd 0
ahci_device_list_addr       equ 0x8a500     ;32 * 16 = max 512 (0x200)
ahci_devices: dw 0
ahci_initialized: db '> AHCI devices initialized', 0
ahci_active: db 0
AHCI_PORT_ENTRY_SIZE            equ 12
ahci_prdt:
    dd 0        ;address low
    dd 0        ;address high
    dw 0        ;byte cound
    dw 0        ;flags

;1 Port (9422B in Memory):
; - 1024B Command list
; - 256B Received FIS
; - 32*256B Command Tables
; - 64B task list structure
; - Alignment (can be used for other information)
AHCI_MEM_BASE           equ 0x100000
AHCI_PORT_MEM_OFF       equ 12288        ;1 Command list (1024B), Received FIS (256B), 32 Command Tables (8192B), 64B = 9536 +  ~2.7KB Alignment
CMD_LIST_SIZE            equ 1024
RECEIVED_FIS_SIZE        equ 256
CMD_TABLES_SIZE          equ 256

AHCI_TASK_STRUCT_OFF     equ 0x2500

DRIVE_LIST_ADDR        equ 0x8a700     ; ~0x300 (768) bytes
DRIVE_LIST_ENTRY       equ 100
USB_LIST_ENTRY         equ 40
avail_disks: db 0
avail_drives_str: db 'Available Drives: ', 0
unknown_drive_str: db 'Unknown Drive Type', 0
sata_device_str: db 'SATA Device', 0
ide_device_str: db 'IDE Hard Disk', 0
usb_storage_str: db 'USB Mass Storage Device', 0


ohci_found: db 0
ahci_found: db 0
ide_found: db 0


ohci_base: dd 0
hcca                    equ 0x162500              ;Host Controller Communications Area
USB_DEVICE_LIST         equ 0x163000
OHCI_DRIVER_ADDR        equ 0x61000
DIR_DRIVERS_ADDR        equ 0x60000
;0x00: Unknown
;0x01: Keyboard
;0x02: Mouse
;0x03: USB Stick
;0x04: USB 1.1 floppy
;0x05: Printer
;0x06: USB Hub
;0x07: Fast External SSD
;0xffffffff: error
;0xeeeeeeee: end of list
usb_list_offset: dd 0
usb_unknown_str: db 'Unknown device', 0
usb_keyboard_str: db 'Keyboard', 0
usb_mouse_str: db 'Mouse', 0
usb_floppy_str: db 'USB 1.1 floppy drive', 0
usb_stick_str: db 'USB Flash Drive', 0
usb_printer_str: db 'Printer', 0
usb_hub_str: db 'USB Hub', 0
usb_extdrive_str: db 'External SSD / HDD', 0
usb_error_str: db 'Error while detecting this device', 0
usb_list_header: db '<> List of detected USB devices <> ', 0
align 16
control_ed:                           ;Endpoint Desciptor
    dd 0    ;control
    dd 0    ;TD queue tail
    dd 0    ;TD queue head
    dd 0    ;Next ED
td_setup:
    dd 0
    dd 0
    dd 0
    dd 0
td_data:
    dd 0
    dd 0
    dd 0
    dd 0
td_status:
    dd 0
    dd 0
    dd 0
    dd 0
td_empty: times 4 dd 0
usb_keyboard_ed: times 4 dd 0
usb_keyboard_td: times 4 dd 0

ohci_setup_packet:
    db 0x80          ; Device to Host
    db 0x06          ; GET_DESCRIPTOR

    dw 0x0100        ; Device Descriptor
    dw 0
    dw 18
set_address_packet:
    db 0x00
    db 0x05
    dw 0             ; Address (off 2)
    dw 0
    dw 0
ohci_descriptor_buffer: times 128 db 0
usb_keyboard_buffer: times 8 db 0
usb_keyboard_used: db 0

usb_keybuffer: dd 0
data_td_ptr: dd 0
status_td_ptr: dd 0
setup_td_ptr: dd 0

usb_keyboard_edptr: dd 0
usb_keyboard_tdptr: dd 0

usb_keymap:
    times 4 db 0
    db 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
    db 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'z', 'y'
    db '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'
    db 0x0d     ;Enter
    db 0x1b     ;ESC
    db 0x08     ;Backspace
    db 0x09     ;TAB
    db 0x20     ;Space
    db '-'
    db '='
    db '['
    db ']'
    db '\'
    db 0
    db ';'
    db 39       ;'
    db '`'
    db ','
    db '.'
    db '/'

    db 0    ;Caps Lock

    db 0x3b,0x3c,0x3d,0x3e,0x3f,0x40,0x41,0x42,0x43,0x44    ;F1 - F12
    dw 0
    db 9 dup(0)
    db 4 dup(0)
    times (256-83) db 0
.shift:
    times 4 db 0
    db 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    db 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Z', 'Y'
    db '!', '@', '#', '$', '%', '^', '&', '*', '(', ')'
    db 0x0d     ;Enter
    db 0x1b     ;ESC
    db 0x08     ;Backspace
    db 0x09     ;TAB
    db 0x20     ;Space
    db '_'
    db '+'
    db '{'
    db '}'
    db '|'
    db 0
    db ':'
    db '"'
    db '~'
    db '<'
    db '>'
    db '?'

    db 0    ;Caps Lock

    db 0x8b,0x8c,0x8d,0x8e,0x8f,0x90,0x91,0x92,0x93,0x94    ;F1 - F12
    dw 0
    db 9 dup(0)
    db 4 dup(0)
    times (256-83) db 0
.keycode_table:
    db KEY_NONE                 ; 0x00: Reserved
    db KEY_NONE                 ; 0x01: ErrorRollOver
    db KEY_NONE                 ; 0x02: POSTFail
    db KEY_NONE                 ; 0x03: ErrorUndefined
    
    ; 0x04 - 0x1D: letters
    db KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H
    db KEY_I, KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P
    db KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X
    db KEY_Y, KEY_Z
    
    ; 0x1E - 0x27: numbers
    db KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0
    
    ; 0x28 - 0x2C: standard control keys
    db KEY_ENTER                ; 0x28
    db KEY_ESC                  ; 0x29
    db KEY_BACKSPACE            ; 0x2A
    db KEY_TAB                  ; 0x2B
    db KEY_SPACE                ; 0x2C
    
    ; 0x2D - 0x39: special keys
    times (0x3A - 0x2D) db KEY_NONE
    
    ; 0x3A - 0x45: function keys
    db KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6
    db KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12

    times (256 - 0x45) db KEY_NONE

;###################################################################
;############################# KEY CODES ###########################
;###################################################################

KEY_NONE        equ 0x00

; letters
KEY_A           equ 0x01
KEY_B           equ 0x02
KEY_C           equ 0x03
KEY_D           equ 0x04
KEY_E           equ 0x05
KEY_F           equ 0x06
KEY_G           equ 0x07
KEY_H           equ 0x08
KEY_I           equ 0x09
KEY_J           equ 0x0A
KEY_K           equ 0x0B
KEY_L           equ 0x0C
KEY_M           equ 0x0D
KEY_N           equ 0x0E
KEY_O           equ 0x0F
KEY_P           equ 0x10
KEY_Q           equ 0x11
KEY_R           equ 0x12
KEY_S           equ 0x13
KEY_T           equ 0x14
KEY_U           equ 0x15
KEY_V           equ 0x16
KEY_W           equ 0x17
KEY_X           equ 0x18
KEY_Y           equ 0x19
KEY_Z           equ 0x1A

; numbers
KEY_1           equ 0x1B
KEY_2           equ 0x1C
KEY_3           equ 0x1D
KEY_4           equ 0x1E
KEY_5           equ 0x1F
KEY_6           equ 0x20
KEY_7           equ 0x21
KEY_8           equ 0x22
KEY_9           equ 0x23
KEY_0           equ 0x24

; control keys
KEY_ENTER       equ 0x25
KEY_ESC         equ 0x26
KEY_BACKSPACE   equ 0x27
KEY_TAB         equ 0x28
KEY_SPACE       equ 0x29
KEY_LSHIFT      equ 0x2A
KEY_RSHIFT      equ 0x2B
KEY_LCTRL       equ 0x2C
KEY_LALT        equ 0x2D

; function keys
KEY_F1          equ 0x2E
KEY_F2          equ 0x2F
KEY_F3          equ 0x30
KEY_F4          equ 0x31
KEY_F5          equ 0x32
KEY_F6          equ 0x33
KEY_F7          equ 0x34
KEY_F8          equ 0x35
KEY_F9          equ 0x36
KEY_F10         equ 0x37
KEY_F11         equ 0x38
KEY_F12         equ 0x39

;###################################################################

ohci_read_sectors: dd 0
uhci_read_sectors: dd 0
ehci_read_sectors: dd 0
xhci_read_sectors: dd 0

ide_running: db 0
dma_done: db 0
base_channel: dw 0
boot_drive: db 0
cur_bmbase_str: db '< Base Addr: ', 0
sec_per_cluster: db 0
reserved_sectors: dw 0
fat_num: db 0
root_entries: dw 0
total_sectors: dw 0
fat_size: dw 0
hidden_sectors: dd 0
total_sectors32: dd 0
bytes_per_sec: dw 0

root_start: dd 0
root_sectors: dw 0
data_start: dd 0
subdir_entries: dw 0

root_addr       equ 0
fat_addr        equ 0x4000
program_addr    equ 0x1000000
program_addr_off equ 0x20000
dir_str: db '<DIR>', 0
sys_str: db '<SYS>', 0
read_buffer equ 0x160000    ;times 13 db 0
read_buffer2: equ 0x161000  ;times 13 db 0
read_buffer3: equ 0x162000  ;times 11 db 0
file_buffer     equ 0x20000
cluster16: dw 0
first_cluster16: dw 0
file_size16: dd 0
prev_cluster16: dw 0
drive_number: db 0
cur_dir_addr: dd 0

no_file_msg: db 'No such file found', 0
fs16_error_msg: db 'FAT16 ERROR: Failed loading MBR, FAT or Root Directory. Please reboot.', 0x0a, 
                db 'If this keeps happening, maybe there is something wrong with your drive', 0

del_success_msg: db 'File deleted', 0
delete_failure_msg: db 'Error while deleting file', 0

ren_prompt: db 'Enter new filename: ', 0
ren_err_msg: db 'Error while renaming file', 0

write_success: db 'File saved!', 0
write_failure: db 'Error while writing file', 0
write_prompt: db 'Enter file content (ESC = save):', 0

disk_changed_str: db 'Drive switched successfully', 0
disk_changed_err: db 'Error while switching drive. Error code: ', 0

no_dir_str: db 'No such directory', 0
drive_read_err: db 'Error while reading from the drive', 0

file_test_txt db        "TEST    TXT"
program_help_obj db     "HELP    OBJ"
shell_task_str db       "SHELL   SYS"
program_init_sys db     "INIT    SYS"

dir_configs_str db      "XCONFIGS   "
file_bgcolor_cfg db     "BGCOLOR CFG"
dir_drivers_str db      "DRIVERS    "
file_ohci_sys db        "OHCI    SYS"
file_sb16_sys db        "SB16    SYS"
file_intl_aud_sys db    "INTL_AUDSYS"
file_rtl8139_sys db     "RTL8139 SYS"
dir_network_str db      "NETWORK    "
file_ip_sys db          "IP      SYS"
file_protocol_sys db    "PROTOCOLSYS"
file_dhcp_sys db        "DHCP    SYS"
dot_dot_entry db        "..         "
idle_task_str db        "IDLE    SYS"

CONFIG_DIR_BUFFER equ   0x20000
CONFIGS_FILE_BUFFER equ 0x20500
osdev_discord_msg: db 'Thanks to the OSDev Discord Server for muting me saying my opinion', 0
;windows and multitasking
windows_list:
    times 10 db 0
num_windows: dw 10
window_id: dw 0
win_x: dd 0
win_y: dd 0
win_width: dd 0
win_height: dd 0
win_color: dd 0
win_border_color: dd 0x001015c2
untitled_str: db 'untitled', 0

char_bgcolor: dd 0
win_pitch: dd 0
win_rows: dd 0
cust_height: dd 0
win_buffer_addr: dd 0

task_count: dw 0
max_tasks: dw 4
current_task: dw 1
task_slots: dw 4

main_task: dw 1

tasks_esp:
    times 11 db 0
    times 4 dd 0    ;task 0 (reserved)

    times 11 db 0
    times 4 dd 0    ;task 1 (shell)

    times 11 db 0
    times 4 dd 0    ;task 2

    times 11 db 0
    times 4 dd 0    ;task 3

    times 11 db 0
    times 4 dd 0    ;task 4

    times 11 db 0
    times 4 dd 0    ;4B Flags, 4B ESP, 4B Program start address, 4B program size

tasks_kernel_stack      equ 0x90000
tasks_kernel_stack_off  equ 0x1000      ;every task has ~4KB stack
TASK_SIZE               equ 27
TASK_FLAG_SLEEPING      equ 0x0000b100  ;sleeping flag
task_limit: db 'Maximum amount of tasks achieved!', 0
create_task_err: db 'Error while creating task', 0

switch_tasks_window:
    dd 0            ;foreground color
    dd 0x00ffffff   ;background color
    dd 500          ;width
    dd 200          ;height
    dd 0            ;CurX
    dd 0            ;CurY
    dd 0            ;original CurX
    dd 0            ;original CurY
switch_tasks_str: db 'Switch Tasks - ESC to quit', 0
switch_tasks_win_id: dw 0
switch_tasks_msg: db 'Available Tasks: ', 0
task_not_found: db 'Task not found', 0
task_list_header: db 'PID   Name', 0

SYMBOL_TABLE_ADDR           equ 0xef0000
RELOCATION_TABLE_CONTENTS   equ 0xeffe00

program_address: dd 0
section_text_str: db '.text', 0, 0, 0
coff_load_err: db 'Error while loading COFF File', 0

wavfile_functions: dd 0
;+0: play WAV file (EDI = start address of file)
;+8: interrupt handler of SB16 card
;+12: pause playing of current WAV file
;+16: resume playing of current WAV file
;+20: end playing current WAV file


;network
ip_packet:
    dd 0
    dd 0
    times 3 dw 0
    dw 0


;global structure
NET_INTERFACE       equ 0x8c000
;+0: IPv4 address
;+4: DNS server
;+8: gateway IP
;#### sending a packet
;+12: transmit_packet()     (driver)
;+16: add_ipheader()        (IP)
;+20: add_udp_header()           (protocol)
;+24: add_tcp_header()           (protocol)
;+28: add_arp_header()           (protocol)
;+32: add_icmp_header()          (protocol)
;#### receiving a packet
;+36: process_packet_ip()        (IP)
;+40: process_packet_udp()       (protocol)
;+44: process_packet_tcp()       (protocol)
;+48: process_packet_icmp()      (protocol)
;+52: process_packet_arp()       (protocol)
;+56: application_packet()       (api)
;+60: Subnet Mask
net_active: db 0        ;global variable which indicates if programs can use network or not

packet_stats:
    dd 0    ;pointer to variable transmit_error_count
    dd 0    ;pointer to variable transmit_success_count
    dd 0    ;pointer to variable receive_error_count
    dd 0    ;pointer to variable receive_success_count


sleep_timers_list: dd 0x8b000
max_sleep_timers: dd 0x1000/8
counters_list: dd 0x8d000
max_counters: dd 0x1000/8

; sleep_timer_struct:
;     dw 0                ;PID
;     dw 0                ;padding
;     dd target_tick      ;when does the timer stops (value, set by program + system_tick)

; counters_struct:
;     dd pointer_to_variable      ;variable will be increased by 1 every 1ms
;     dd max_value                ;value_from_program+system_tick, if this value is equal with the value from [pointer_to_variable]+system_tick then this timer gets deleted

system_tick: dd 0         ;global tick value
    