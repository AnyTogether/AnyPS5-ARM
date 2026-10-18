// aps5_host_bridge(GuestState* state, uint64_t target): calls a host (AAPCS64) function with the
// guest's SysV argument registers. rdi, rsi, rdx, rcx, r8, r9 become x0-x5, the guest stack
// arguments 7 and 8 become x6 and x7, and xmm0-7 become q0-q7. x0/x1 return into rax/rdx and
// q0/q1 into xmm0/xmm1. The guest return address is at [rsp], so stack arguments start at rsp + 8.
    .text
    .p2align 2
    .globl _aps5_host_bridge
_aps5_host_bridge:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x16, x1
    add x9, x19, #160
    ldr q0, [x9, #0]
    ldr q1, [x9, #32]
    ldr q2, [x9, #64]
    ldr q3, [x9, #96]
    ldr q4, [x9, #128]
    ldr q5, [x9, #160]
    ldr q6, [x9, #192]
    ldr q7, [x9, #224]
    ldr x10, [x19, #32]
    ldr x6, [x10, #8]
    ldr x7, [x10, #16]
    ldr x0, [x19, #56]
    ldr x1, [x19, #48]
    ldr x2, [x19, #16]
    ldr x3, [x19, #8]
    ldr x4, [x19, #64]
    ldr x5, [x19, #72]
    blr x16
    str x0, [x19, #0]
    str x1, [x19, #16]
    add x9, x19, #160
    str q0, [x9, #0]
    str q1, [x9, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// aps5_enter: a host (AAPCS64) call of a guest function, reached through the fault redirect with the
// translated function in x16. Saves x0-x7 and q0-q7, runs aps5_enter_guest(frame, x16) and returns
// its x0/x1 and q0/q1 to the host caller, whose return address is still in x30.
    .p2align 2
    .globl _aps5_enter
_aps5_enter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #192
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp q0, q1, [sp, #64]
    stp q2, q3, [sp, #96]
    stp q4, q5, [sp, #128]
    stp q6, q7, [sp, #160]
    mov x0, sp
    mov x1, x16
    bl _aps5_enter_guest
    ldp x0, x1, [sp, #0]
    ldp q0, q1, [sp, #64]
    add sp, sp, #192
    ldp x29, x30, [sp], #16
    ret
