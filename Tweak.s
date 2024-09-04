.globl _dlopen_hook
_dlopen_hook:
#ifdef __arm64__
	cbz x0, L_orig_tail_ret_nostack
#ifdef __arm64e__
	pacibsp
#endif // __arm64e__
	sub sp, sp, #0x20
	stp x29, x30, [sp]
	stp x0, x1, [sp, #0x8]
	bl _should_load_dylib
	cbnz x0, L_orig_tail_ret

	ldp x0, x1, [sp, #0x8]
	ldp x29, x30, [sp]
	add sp, sp, #0x20
	mov x0, #0
#ifdef __arm64e__
	retab
#else // !__arm64e__
	ret
#endif // __arm64e__

L_orig_tail_ret:
	ldp x0, x1, [sp, #0x8]
	ldp x29, x30, [sp]
	add sp, sp, #0x20
L_orig_tail_ret_nostack:
	adrp x8, _dlopen_orig@PAGE
	add x8, x8, _dlopen_orig@PAGEOFF
	ldr x8, [x8]
#ifdef __arm64e__
	braaz x8
#else // !__arm64e__
	br x8
#endif // __arm64e__
#else // !__arm64__
	bx lr
#endif

