#!/bin/sh
set -eu

: "${GEN_CLANG:?Set GEN_CLANG to the absolute path of the musttail-capable Clang}"
: "${LEGACY_SDKROOT:?Set LEGACY_SDKROOT to the absolute path of the patched SDK 13.7}"
for path in "$GEN_CLANG" "$LEGACY_SDKROOT"; do
	case "$path" in
		/*) ;;
		*) echo 'GEN_CLANG and LEGACY_SDKROOT must be absolute paths.' >&2; exit 1 ;;
	esac
done
if [ "$#" -ne 0 ] || [ ! -f "$GEN_CLANG" ] || [ ! -x "$GEN_CLANG" ] || [ ! -d "$LEGACY_SDKROOT" ]; then
	echo 'Use legacy_build.sh with a prepared GEN_CLANG and LEGACY_SDKROOT.' >&2
	exit 1
fi

CDPATH= cd -P "$(dirname "$0")"
if [ -L .theos ]; then
	echo 'The project .theos directory must not be a symlink.' >&2
	exit 1
fi
mkdir -p .theos
rm -f gen.armv7.s gen.arm64.s gen.arm64e.s
scratch=$(mktemp -d .theos/gen-asm.XXXXXXXX)
trap 'rm -rf "$scratch"' 0
trap 'exit 1' HUP INT TERM

generate() {
	arch=$1
	minimum=$2
	shift 2
	"$GEN_CLANG" -isysroot "$LEGACY_SDKROOT" -arch "$arch" -miphoneos-version-min="$minimum" \
		-Werror=unknown-attributes -Werror=ignored-attributes -Werror=unused-command-line-argument \
		-O2 -S "$@" gen.c -o "$scratch/gen.$arch.s"
	test -s "$scratch/gen.$arch.s"
}

generate armv7 10.0
generate arm64 10.0
generate arm64e 12.0 -fno-ptrauth-abi-version
mv "$scratch/gen.armv7.s" "$scratch/gen.arm64.s" "$scratch/gen.arm64e.s" .
