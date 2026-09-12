# INT 0x30
## Video Output

### supported color format in EBX: 0x00RRGGBB

### AH = 0x01:
- print a null-terminated string to screen
- ESI: pointer to null terminated string
- EBX: color
- this function should not be used and will be (hopefully) deleted soon because <br>
  programs should use function 0x0A and print string into their window

### AH = 0x02:
- print a single char to the screen
- AL: ASCII Char
- EBX: color
- should also not be used

### AH = 0x03:
- add [cur_y] 8, next char/string will be printed in a new line
- no arguments needed
- should also not be used and will be removed soon, use function 0x0c instead

### AH = 0x04
- print a number in white in decimal format
- EBX: number
- use function 0x0d

### AH = 0x0A
- prints a string into a custom window (for example into a 400x200px window)
- ESI: pointer to null-terminated string
- EDI: pointer to window packet (special structure with widht/height/cur_x/cur_y/color/...)

### AH = 0x0B
- prints a single char into a window
- AL: character
- EDI: pointer to window packet

### AH = 0x0C
- adds +8 to cur_y in the window packet (sets a newline)
- EDI: window packet

### AH = 0x0D
- prints a decimal value in ASCII chars
- EBX: number
- EFI: window packet

### AH = 0x0E
- clears window (fill window in a specific color)
- EDI: window packet (offset +4B = bgcolor)

## Syscalls

1. Program / shell puts into AH function number
2. passes arguments into other registers
3. calls syscall via interrupt (e.g. 'int 0x30' for Video)
4. waits for syscall-exit and stores return value and checks if error happend (carry flag)

# INT 0x31
## Keyboard

Currently there is only one function available and its maybe going to be moved to INT 0x35 (System API)

### AH = 0x00
- wait for keypress
- output: 
    - AL: ASCII character of pressed key or scancode
    - AH: scancode (PS/2 Scancode set 1 or USB Scancodes)
    - EDX: pointer to 8 bytes with all pressed scancodes (USB Keyboards only)



# INT 0x33
## Filesystem (FAT16)

### AH = 0x00
- get file information (size, first cluster number, attributes)
- ESI: pointer to filename (8.3 format)
- EDI: pointer to loaded directory in memory (if 0 it means the file is in root directory)
- output:
    - ECX: size in bytes
    - EAX: directory attributes
    - EBX: first cluster number


# INT 0x34
## Windows

> Functions 0x01 and 0x02 are deprecated and shouldnt be used

### AH = 0x01
Draw a window

- ESI: X-coordinate
- EDI: Y-coordinate
- ECX: width of window
- EDX: height of window
- EBX: background color
- EBP: pointer to window title
- output:
  - AX: window ID
  - EBX: X-coordinate of cursor
  - ECX: Y-coordinate of cursor

### AH = 0x02
Delete a window
- EDI: pointer to window packet
- BX: window ID

### AH = 0x0A
Draw a window but let the window manager decide its position and size

- output:
  - EDI: pointer to window packet
  - AX: window ID

### AH = 0x0B
Remove a window, created by the window manager

- EDI: pointer to window packet
- BX: window ID

# INT 0x35
## System API

### AH = 0x01
Halt the system. This is used for debugging.

### AH = 0x02
Load and start a foreground task

- ESI: pointer to taskname
- EDI: pointer to filename in directory
- EBX: pointer to loaded directory

### AH = 0x03
Load and start a background task

- ESI: pointer to taskname
- EDI: pointer to filename in directory
- EBX: pointer to loaded directory

This function is very similar to function 0x02 except that a background task doesnt have control over keyboard and screen

### AH = 0x05
Terminate current task

It frees all heap allocated by the task and marks task in task structure as deleted (0xe5)

### AH = 0x0A
Allocate a heap chunk

- ECX: size of needed memory
- Output: ESI = pointer to allocated heap

Note: the allocated memory is always 4KiB aligned, that means if you need 3500 Bytes you get 4096 bytes

### AH = 0x0B
Free a heap chunk

- ESI: pointer to heap chunk
- ECX: size of allocated memory

Note: If the pointer is wrong or the size is too big, the function will set a Carry Flag. Tasks also cant free other tasks memory <br>
      If the tasks terminates without freeing its allocated heap, the terminate_task() function will do that automatically, but it is still recommended to free the heap in the program

### AH = 0x12
Start an already loaded task in foreground

- EBX: address of task
- ESI: pointer to taskname (8.3 format)

A foreground task has control over keyboard and screen

### AH = 0x13
Start an already loaded task in background

- EBX: address of task
- ESI: pointer to taskname (8.3 format)

This is useful if you want to create multiple subtasks in a program. You can pass into EBX the label of a function you want to execute and call this function to create a subtask.

### AH = 0x20
Functions for playing a WAV file

**Subfunctions**:
  - BH = 0x01: start playing a loaded WAV file  <br>
      Input: EDI = startaddress of file
  - BH = 0x02: pause the playing of current playing WAV file  <br>
      Output: Carry flag if there currently is no active WAV file
  - BH = 0x03: resume to play the paused WAV file <br>
      Output: Carry flag if there currently is no active WAV file
  - BH = 0x04: stop completly the play of the current WAV file  <br>
  > When calling function 'BH 0x03' after this function it will set the carry flag because function 0x04 sets status of currently playing a WAV file to 'not active'  <br>
  > You should call this function if you want to play another WAV file instead of the current one

### AH = 0x21
Network functions <br>
*Note: If there is no internet connection then all functions will set a carry flag and fill all registers with value 0xffffffff* 

**Subfunctions**:
  - AL = 0x01: get stats about network traffic    <br>
      Input: EDI = pointer to 128B buffer <br>
      Output: filled buffer               <br>
      +0: count of successfully sent packets      <br>
      +4: count of how many sent packets lost     <br>
      +8: count of successfully received packets  <br>
      +12: count of errors while receiving packets<br>

  - AL = 0x02: open socket  <br>
    Input: <br>
           **BH** = IP version (0 = IPv4, 1 = IPv6)                       <br>
           **BL** = protocol (1 ICMP, 2 TCP, 3 UDP)                       <br>
           **DX** = port number                                           <br>
           **ESI** = pointer to buffer (in which packets get stored)      <br>
    Output: CX = Socket number                                            <br>
    Note: If you set DX to zero then OS decides the port number. Also, IPv6 is not supported so these sockets will not work <br>

  - AL = 0x03: send a packet
    Input: <br>
           **Bits 16-31 of EBX** = socket number  <br>
           **BX** = port number (if it was set by the program)  <br>
           **EDX** = IPv4 address, to which you want to send the packet <br>
           **ESI** = pointer to packet  <br>
           **ECX** = length of packet <br>

  - AL = 0x04: wait for packet
    Input: <br>
           **CX** = socket number

    Note: Halts the program until a packet was received which was addressed to the program. Then the program wakes up and can <br>
          check its buffer. <br>

  - AL = 0x05: close socket <br>
    Input: <br>
           **CX** = socket number <br>
    Output: sets a carry flag if the program tries to close a socket which doesnt exist or belongs to an other task <br>

  - AL = 0x07: resolve domain name  <br>
    Input: <br>
           **CX**: socket number    <br>
           **EDI**: pointer to null-terminated string with domain name  <br>
    Output: <br>
            **EDX**: IPv4 address of server with this domain <br>
            **EAX**: Time To Live of the IPv4 address (how long it takes until the IP address changes) in seconds <br>
    Note: to send a DNS Request the socket has to be UDP socket <br>

### AH = 0x22
Timer Functions

**Subfunctions**
  - AL = 0x01: sleep X ms <br>
    Input: <br>
           **EBX** = number of milliseconds to sleep  <br>

  - AL = 0x02: set counter  <br>
    Input: <br>
           **EBX** = pointer to 4 byte field which is incremented every 1ms <br>
           **EDX** = number of ms until the function should stop to count <br>
    Note: This function increments a variable given by the program every 1ms, while the program isnt put to sleep. This is useful for network functions, which are waiting for packets. <br>
    It can set a timer of 2000ms (2 sec) and check in this 2 seconds if a packet was received. If the timer expires the function returns with an error. <br>

  - AL = 0x03: get current time <br>
    Output: <br>
            **AL** = seconds (0 - 59) <br>
            **AH** = minutes (0 - 59) <br>
            **BL** = hours (0 - 23)   <br>
            **BH** = day of the week (1 = monday, 7 = sunday) <br>
            **CL** = day of month (1 - 31)  <br>
            **CH** = month (1 - 12) <br>
            **DL** = year (0 - 99)  <br>
            **DH** = century (should be 20) <br>