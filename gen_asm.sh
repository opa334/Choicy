CFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=8.0"

clang $CFLAGS -S -arch armv7  gen.c -o gen.armv7.s
clang $CFLAGS -S -arch arm64  gen.c -o gen.arm64.s
clang $CFLAGS -S -arch arm64e gen.c -o gen.arm64e.s -fno-ptrauth-abi-version