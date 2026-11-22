# Boot Process

## Legacy BIOS
- BIOS loads MBR (Master Boot Record - 1. sector of drive) to address 0x7c00
- executes the bootloader
- bootloader loads Root Directory, FAT and searches for KERNEL.BIN
- if found it gives the file full control and pass some arguments about where the root and data LBA is
- at the start of the kernel, it also loads the DRIVERS/ directory and following files: (O/U/E/X)HCI.SYS, NVME.SYS, FDC.SYS, SDC.SYS

Then Xiromos Kernel does following things:
- initializes Video Mode (Mode 0x12, 640x480, 4Bit colors)
- gets information about drive and filesystem
- prints logo
- counts and initializes drives
- activates A20 Gate
- loads directory SYS and file SYS/AUTOSTRT.SYS
- checks content of the file
- if the first char of the file is '1', Xiromos Kernel loads file XMODE.BIN from Root Directory to address 0x8000
- sets BIOS VBE Mode 0x118 (1024x768, 24bit)
- performs a far jump to 0x8000

## UEFI
- UEFI searches for /EFI/BOOT/BOOTX64.EFI
- executes it
- bootloader searches for video mode 1024x768 (XGA)
- if found it sets that video mode
- then bootloader opens the root directory and searches for XMODE.BIN
- if found UEFI loads it to 0x8000
- it also opens the DRIVERS/ directory and loads (O/U/E/X)HCI.SYS, NVME.SYS, FDC.SYS, SDC.SYS
- then it asks for memory map from UEFI and copies it to address 0x1ff000
- bootloader calls ExitBootservices()
- it passes into registers information about video mode (like address of frame buffer, bytes per pixel,...)
- jumps to 0x8000+250 to skip BIOS code in kernel
- stores information about frame buffer in variables and switches to protected mode, while also disabling paging to load later its own page directory


### After Bootloaders

- kernel loads IDT (interrupt descriptor table) and remaps PIC (Programmable Interrupt Controller) to 0x20
- it activates paging in CR0 (identity mapping) and initializes heap memory
- also the kernel initializes following tasks: IDLE.SYS (task 0) and SHELL.SYS (task 1)
- it first scans the PCI for disk controllers and executes the needed drivers
- then it scans the PCI again, but for other devices and loads a driver for them, but only if the right driver was found in DRVRLIST.TXT
- after that it takes information from the boot sector about filesystem and calculates Root Directory and Data Area start LBAs

This whole process should take ~2-3 seconds. There is a bug where sometimes the kernel just hangs in an infinity loop. Then just restart the VM/PC. <br>
The operating system is now ready to work and waits for commands.