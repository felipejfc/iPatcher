.text
.globl _fixture_patch_target
.p2align 2

_fixture_patch_target:
    movz x9, #0x4a11
    movk x9, #0xb2c3, lsl #16
    mov  w0, #0
    ret
