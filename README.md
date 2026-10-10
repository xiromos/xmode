## README file

**Xiromos-X32** is a 32Bit operating system, entirely written in x86 Assembly.<br>
It is designed to be compatible with old hardware but at the same time support modern features. <br>


## Main Features

- FAT16 filesystem
- BIOS VBE and GOP supported, GOP: choose any available video mode, BIOS: XGA resolution (1024x768)
- windows / window manager
- preemptive multitasking
- task states like 'running', 'sleeping', 'waiting for disk'
- PCI Busmastering (U)DMA driver for ATA devices
- multi-disk support (CDISK-Command)
- OHCI USB Keyboard driver
- OHCI USB Stick driver
- COFF program loading (32-Bit)
- AHCI driver with Native Command Queuing
- Sound Blaster 16 driver - play any WAV file and listen music
- PS/2 mouse driver
- allocating and freeing heap memory via syscalls
- RTL8139 network card driver
- system calls for sending UDP and ICMP packets over the internet

## Minimal Hardware Requirements

- Processor: i386
- RAM: 10MB minimum, ~20MB to load drivers execute shell programs, ~25MB with Window Manager
- Disk Space: 1MB

## Commands

See docs/commands.md

## TODO

- SMP
- APIC support
- Internet
- make assembler
- UHCI and EHCI drivers


## How to build
```bash
git clone https://github.com/xiromos/xmode.git
cd xmode
chmod +x buildx.sh
./buildx.sh
```

## Required packages to build
```bash
# Arch Linux
sudo pacman -S nasm qemu-full mtools edk2-ovmf

# Linux Mint / Ubuntu
sudo apt install nasm qemu mtools ovmf
```