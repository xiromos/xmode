# Driver Interface

### How kernel and drivers interact
First the kernel scans the PCI bus for devices. When one is found, it looks the Vendor and Device ID in file 'drvrlist.txt' up and loads the fitting driver.    <br>
After the driver initialized the device, it gives the kernel in EDX a pointer to the "kernel_packet", which contains functions the driver provide and information.  <br>


### What the kernel gives the driver
**EAX**: BAR0       <br>
**EBX**: pointer to following structure
```asm
driver_packet:
    dd BAR1
    dd BAR2
    dd BAR3
    dd BAR4
    dd BAR5
```

## What the driver returns
**AH**: Error code (0x00 = successfully initialized device, everything is okay, 0x01: error while initializing device, kernel ignores the device)<br>
**EDX**: pointer to kernel_packet structure, where pointers to different functions are stored

### Network kernel_packet
dd *transmit_packet()   <br>
dd *interrupt_handler()

dd 0

dd *transmit_error_count        ;pointer to variable    <br>
dd *transmit_success_count      ;pointer to variable

dd *receive_error_count         ;pointer to variable    <br>
dd *receive_success_count       ;pointer to variable

dd packet_receive_buffer_addr   <br>
times 6 db mac_addr

dd 0    <br>
dd 0

### Sound kernel_packet
*Now defined yet*

### Graphic kernel_packet
*Now defined yet*

### USB kernel_packet
*Now defined yet*

### Devices, which are not listed in PCI
Right now, the drivers for these devices are loaded in a kernel function called 'load_drivers'. The kernel first checks, if the device is connected and if yes, <br>
it loads the driver.

**How it should be in the future**: <br>
The drivers should be executed by the user in the shell. It should also be possible to write the loading command into a auto-execution file.


### Boot critical drivers
Drivers are boot critical, when they are needed for loading other drivers and files

The 
- IDE Driver,
- AHCI Driver,
- NVME Driver,
- USB Drivers (OHCI, UHCI, EHCI, XHCI USB Sticks),
- Floppy Disc Driver,
- SD Card Driver,

are boot critical drivers. They are either loaded by the UEFI Bootloader or by the kernel, when it is in 16bit Real Mode.
After, the kernel searches scans the PCI Bus for various controllers, like IDE, AHCI...
When found, it just executes the right driver without having to load it.