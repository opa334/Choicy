#!/bin/sh
set -eu

fail() {
	printf 'Legacy Rootful: %s\n' "$1" >&2
	exit 1
}

[ "$#" -eq 0 ] || fail 'set the documented environment variables and run sh ./legacy_build.sh with no arguments'
[ -z "${THEOS_PACKAGE_SCHEME:-}" ] || fail 'unset THEOS_PACKAGE_SCHEME before running the Legacy Rootful build'
: "${THEOS:?Set THEOS to the absolute path of the prepared Theos checkout}"
: "${LEGACY_PREFIX:?Set LEGACY_PREFIX to the absolute path of Xcode 11.7 toolchain usr/bin/}"
: "${LEGACY_SDKROOT:?Set LEGACY_SDKROOT to the absolute path of the patched SDK 13.7}"
: "${GEN_CLANG:?Set GEN_CLANG to the absolute path of the musttail-capable Clang}"
for path in "$THEOS" "$LEGACY_PREFIX" "$LEGACY_SDKROOT" "$GEN_CLANG"; do
	case "$path" in /*) ;; *) fail "expected an absolute path: $path" ;; esac
done

CDPATH= cd -P "$(dirname "$0")"
for directory in .theos artifacts artifacts/legacy; do
	[ ! -L "$directory" ] || fail "$directory must not be a symlink"
done
THEOS=$(CDPATH= cd -P "$THEOS" && pwd) || fail 'THEOS directory not found'
LEGACY_PREFIX=$(CDPATH= cd -P "$LEGACY_PREFIX" && pwd)/ || fail 'LEGACY_PREFIX directory not found'
LEGACY_SDKROOT=$(CDPATH= cd -P "$LEGACY_SDKROOT" && pwd) || fail 'LEGACY_SDKROOT directory not found'
theos_sdk=$(CDPATH= cd -P "$THEOS/sdks/iPhoneOS13.7.sdk" && pwd) || fail 'prepare iPhoneOS13.7.sdk under THEOS/sdks'
[ "$theos_sdk" = "$LEGACY_SDKROOT" ] || fail 'LEGACY_SDKROOT must resolve to THEOS/sdks/iPhoneOS13.7.sdk'

for tool in clang clang++ ld strip; do
	[ -f "${LEGACY_PREFIX}$tool" ] && [ -x "${LEGACY_PREFIX}$tool" ] || fail "missing executable ${LEGACY_PREFIX}$tool"
done
[ -f "$GEN_CLANG" ] && [ -x "$GEN_CLANG" ] || fail "missing generator executable $GEN_CLANG"
[ "$GEN_CLANG" != "${LEGACY_PREFIX}clang" ] || fail 'GEN_CLANG must be a separate musttail-capable compiler'
for tool in make python3 dpkg-deb ldid lipo otool codesign ar; do
	command -v "$tool" >/dev/null || fail "install or expose $tool on PATH before building"
done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || fail 'Python 3.9 or newer is required'
make_version=$(make --version)
case "$make_version" in 'GNU Make '*) ;; *) fail 'make must be GNU Make' ;; esac
clang_version=$("${LEGACY_PREFIX}clang" --version)
case "$clang_version" in 'Apple clang version 11.'*) ;; *) fail 'LEGACY_PREFIX must select the prepared Xcode 11.7 compiler' ;; esac

export THEOS LEGACY_PREFIX LEGACY_SDKROOT GEN_CLANG
printf 'Theos: %s\nSDK: %s\nMain compiler: %sclang\n%s\nGenerator: %s\n' \
	"$THEOS" "$LEGACY_SDKROOT" "$LEGACY_PREFIX" "$clang_version" "$GEN_CLANG"
"$GEN_CLANG" --version
dpkg-deb --version
printf '%s\n' 'Legacy Rootful target iphone:clang:13.7:10.0, armv7 arm64 arm64e (arm64e iOS 12.0)'
python3 scripts/package-legacy.py preflight "$THEOS" "$LEGACY_SDKROOT"

# Keep inherited make options from overriding the standalone build invocation.
unset MAKEFLAGS GNUMAKEFLAGS MFLAGS MAKEOVERRIDES MAKEFILES THEOS_BUILD_DIR THEOS_STAGING_DIR
mkdir -p artifacts/legacy
tools=$(mktemp -d "$PWD/artifacts/legacy/.toolchain.XXXXXXXX")
trap 'rm -rf "$tools"' 0
trap 'exit 1' HUP INT TERM
cp scripts/legacy-clang.sh "$tools/clang"
chmod +x "$tools/clang"
ln -s clang "$tools/clang++"
ln -s "${LEGACY_PREFIX}ld" "$tools/ld"
ln -s "${LEGACY_PREFIX}strip" "$tools/strip"

legacy_make() {
	make "$@" THEOS="$THEOS" THEOS_PACKAGE_SCHEME= CHOICY_LEGACY=1 \
		TARGET=iphone:clang:13.7:10.0 ARCHS='armv7 arm64 arm64e' \
		CHOICY_LEGACY_TOOL_PREFIX="$tools/" PREFIX="$tools/"
}

legacy_make clean FINALPACKAGE=1
sh ./gen_asm.sh
legacy_make legacy-package FINALPACKAGE=1
