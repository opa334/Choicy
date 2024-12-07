// We need to compile fucking old ABI with Xcode 11
// Xcode 11 however does not fucking support __attribute__((musttail))
// So what we do instead is compile this C code into assembly with latest clang using gen_asm.sh
// The right assembly file will then be included in Tweak.s

#include <stdlib.h>
#include <stdbool.h>

extern void *(*dlopen_orig)(const char*, int);
extern void *(*dyld_dlopen_orig)(const void *, const char*, int);

bool should_load_dylib(const char *dylibPath);

void *dlopen_hook(const char *path, int mode)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	__attribute__((musttail)) return dlopen_orig(path, mode);
}

void *dyld_dlopen_hook(const void *dyld, const char *path, int mode)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	__attribute__((musttail)) return dyld_dlopen_orig(dyld, path, mode);
}