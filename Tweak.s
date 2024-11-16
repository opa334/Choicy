// We need to compile fucking old ABI with Xcode 13
// Xcode 11 however does not fucking support __attribute__((musttail))
// So we must hand roll our own assembly :(

/*
void *dlopen_hook(const char *path, int mode)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	__attribute__((musttail)) return dlopen_orig(path, mode);
}
*/
.globl _dlopen_hook
_dlopen_hook:
#ifdef __arm64__
	cbz x0, L_dlopen_hook_orig_tail_ret_no_restore
#ifdef __arm64e__
	pacibsp
#endif // __arm64e__
	sub sp, sp, #0x20
	stp x29, x30, [sp]
	stp x0, x1, [sp, #0x10]
	bl _should_load_dylib
	cbnz x0, L_dlopen_hook_orig_tail_ret

	ldp x29, x30, [sp]
	add sp, sp, #0x20
	mov x0, #0
#ifdef __arm64e__
	retab
#else // !__arm64e__
	ret
#endif // __arm64e__

L_dlopen_hook_orig_tail_ret:
	ldp x0, x1, [sp, #0x10]
	ldp x29, x30, [sp]
	add sp, sp, #0x20
L_dlopen_hook_orig_tail_ret_no_restore:
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

/*
void *dyld_dlopen_hook(const void *dyld, const char *path, int mode)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	__attribute__((musttail)) return dyld_dlopen_orig(dyld, path, mode);
}
*/
.globl _dyld_dlopen_hook
_dyld_dlopen_hook:
#ifdef __arm64__
	cbz x0, L_dyld_dlopen_hook_orig_tail_ret_no_restore
#ifdef __arm64e__
	pacibsp
#endif // __arm64e__
	sub sp, sp, #0x30
	stp x29, x30, [sp]
	stp x0, x1,   [sp, #0x10]
	str x2,       [sp, #0x20]
	bl _should_load_dylib
	cbnz x0, L_dyld_dlopen_hook_orig_tail_ret

	ldp x29, x30, [sp]
	add sp, sp, #0x30
	mov x0, #0
#ifdef __arm64e__
	retab
#else // !__arm64e__
	ret
#endif // __arm64e__

L_dyld_dlopen_hook_orig_tail_ret:
	ldr x2,       [sp, #0x20]
	ldp x0, x1,   [sp, #0x10]
	ldp x29, x30, [sp]
	add sp, sp, #0x30
L_dyld_dlopen_hook_orig_tail_ret_no_restore:
	adrp x8, _dyld_dlopen_orig@PAGE
	add x8, x8, _dyld_dlopen_orig@PAGEOFF
	ldr x8, [x8]
#ifdef __arm64e__
	braaz x8
#else // !__arm64e__
	br x8
#endif // __arm64e__
#else // !__arm64__
	bx lr
#endif

