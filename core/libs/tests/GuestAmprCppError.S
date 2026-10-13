.cfi_sections .eh_frame
.text
.globl GuestCatch
GuestCatch:
    .cfi_startproc
    .cfi_personality 0x00, __gxx_personality_v0_nid_postfix
    .cfi_lsda 0x00, .Lcatch_lsda
    pushq %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register %rbp
    subq $16, %rsp
.Lcatch_call:
    call _ZSt16_Throw_Cpp_errori_nid_postfix
.Lcatch_call_end:
    ud2
.Lcatch_landing:
    cmpq $2, %rdx
    jne .Lcatch_bad
    movq %rax, %rdi
    call __cxa_begin_catch_nid_postfix
    movq %rax, %rdi
    call FixtureInspect
    call __cxa_end_catch_nid_postfix
    leave
    .cfi_def_cfa %rsp, 8
    ret
.Lcatch_bad:
    movl $1, %edi
    call FixtureFail
    ud2
    .cfi_endproc
.section .rdata,"dr"
.Lcatch_lsda:
    .byte 0xff, 0x80
    .uleb128 .Lcatch_types_end-.Lcatch_types_offset
.Lcatch_types_offset:
    .byte 0x01
    .uleb128 .Lcatch_calls_end-.Lcatch_calls
.Lcatch_calls:
    .uleb128 .Lcatch_call-GuestCatch
    .uleb128 .Lcatch_call_end-.Lcatch_call
    .uleb128 .Lcatch_landing-GuestCatch
    .uleb128 1
.Lcatch_calls_end:
    .byte 1, 1, 2, 0
    .quad FixtureCatchType
    .quad FixtureOtherType
.Lcatch_types_end:
