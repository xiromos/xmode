# How to create programs

```asm
;basic program template

section .text
start:
    mov esi, hello_msg      ;move pointer to null-terminated into ESI
    mov ebx, 0x00ffffff     ;store color in EBX
    mov ah, 0x01            ;function number in AH
    int 0x30                ;call video API

    mov ah, 0x05            ;function for terminating the program
    int 0x35                ;call system API

section .data
hello_msg: db 'Hello World!', 0x0a, 0       ;string with newline character
```

Assemble it then with following command (linux):

```bash
nasm -f win32 hello.asm -o hello.obj
```

Copy it to disk image:

```bash
mcopy -i build/disk.img hello.obj ::HELLO.OBJ
```

Supported formats are only Win32 COFF executables   <br>
You can also use C as programming language:

```c
// test.c
void _start() {
    __asm__ volatile (
        "movb $5, %ah\n\t"
        "int $0x35\n\t"
    );
}
```

Then compile it with MinGW:

```bash
i686-w64-mingw32-gcc -ffreestanding -nostdlib -c test.c -o test.obj
```

And copy it to disk image:

```bash
mcopy -i build/disk.img test.obj ::TEST.OBJ
```