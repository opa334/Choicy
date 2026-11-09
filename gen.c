// Modern Clang compiles these tail-call hooks directly for arm64 and arm64e.
// musttail preserves the caller's return address when forwarding to dyld.

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
