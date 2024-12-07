// Include the right generated assembly file based on the architecture

#if !__has_include("gen.arm64e.s") || !__has_include("gen.arm64.s") || !__has_include("gen.armv7.s")
#error "Generated asssembly files not found, please run gen_asm.sh with a recent enough clang to support __attribute__((musttail))"
#endif

#ifdef __arm64__

#ifdef __arm64e__
#include "gen.arm64e.s"
#else
#include "gen.arm64.s"
#endif

#else

#include "gen.armv7.s"

#endif