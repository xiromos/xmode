## README file

**Xiromos-X32** is a 32Bit operating system, entirely written in x86 Assembly.<br>
It is designed to be compatible with old hardware but at the same time support modern features. <br>


## Main Features

- FAT16 filesystem
- BIOS VBE and GOP supported, GOP: choose any available video mode, BIOS: XGA resolution (1024x768)
- windows / window manager
- preemptive multitasking
- PCI Busmastering (U)DMA driver for ATA devices
- multi-disk support
- OHCI / UHCI drivers for keyboard and USB Stick
- support of Win32 COFF files as program format
- AHCI driver with Native Command Queuing
- Sound Blaster 16 driver - play any WAV file and listen music
- PS/2 mouse driver
- allocating and freeing heap memory via syscalls
- RTL8139 network card driver
- system calls for sending UDP and ICMP packets over the internet
- UTF-8 support (only the first 2048 characters of Unicode)

## Minimal Hardware Requirements

- Processor: i386
- RAM: ~25MB recommended
- Disk Space: < 1MB

## Commands

See docs/commands.md

## TODO

- SMP
- APIC support
- TCP protocol
- write assembler and compiler
- EHCI driver


## How to build
```bash
git clone https://github.com/xiromos/xmode.git
cd xmode
chmod +x buildx.sh
./buildx.sh

# Note: the build script copies OVMF (Open Virtual Machine Files) from the /usr/share/OVMF/ directory
# If you dont have OVMF installed, then delete these lines in the build script
```

## Required packages to build
```bash
# Arch Linux
sudo pacman -S nasm qemu-full mtools edk2-ovmf

# Linux Mint / Ubuntu
sudo apt install nasm qemu mtools ovmf
```