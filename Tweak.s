#if defined(__arm64e__)
#define CHOICY_HOOK_ASSEMBLY "gen.arm64e.s"
#elif defined(__arm64__) && defined(__LP64__)
#define CHOICY_HOOK_ASSEMBLY "gen.arm64.s"
#elif defined(__arm__) && defined(__ARM_ARCH_7A__) && !defined(__ARM_ARCH_7S__) && !defined(__ARM_ARCH_7K__)
#define CHOICY_HOOK_ASSEMBLY "gen.armv7.s"
#else
#error "Unsupported architecture for Choicy legacy hook assembly"
#endif

#ifdef CHOICY_HOOK_ASSEMBLY
#if __has_include(CHOICY_HOOK_ASSEMBLY)
#include CHOICY_HOOK_ASSEMBLY
#else
#error "Missing generated hook assembly for this architecture. Run legacy_build.sh."
#endif
#endif
