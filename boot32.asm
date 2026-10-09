;=========================================================================
;32-Bit Bootloader for xmode OS
;stored in the directory /EFI/BOOT/
;-------------------------------------------------------------------------
;Copyright (C) 2026 Technodon
;=========================================================================

section .text
    global _efi_main

_efi_main:
    mov eax, 0
    ret
section .data