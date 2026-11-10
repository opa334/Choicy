#!/bin/sh
set -eu

# Theos calls the PREFIX drivers separately for each architecture. Use the
# iOS 12 floor for arm64e on both assembly/compilation and driver linking.
fail() {
	printf 'Legacy Clang: %s\n' "$1" >&2
	exit 1
}

check_sdk() {
	sdk=$(CDPATH= cd -P "$1" && pwd) || fail "SDK not found: $1"
	[ "$sdk" = "$LEGACY_SDKROOT" ] || fail "unexpected SDK: $sdk (expected $LEGACY_SDKROOT)"
}

arch=
option=
sdk=
for argument do
	case "$option" in
		-arch)
			[ -z "$arch" ] || fail 'expected one -arch per driver invocation'
			arch=$argument
			;;
		-isysroot)
			check_sdk "$argument"
			;;
		'')
			case "$argument" in
				-arch|-isysroot) option=$argument; continue ;;
				-isysroot?*) check_sdk "${argument#-isysroot}" ;;
			esac
			;;
	esac
	option=
done
[ -z "$option" ] || fail "missing value for $option"

case "$arch" in
	armv7|arm64|arm64e)
		[ -n "$sdk" ] || fail 'Theos did not pass its resolved -isysroot'
		;;
	'') ;; # Allow driver version and capability queries.
	*) fail "unsupported architecture: $arch" ;;
esac
if [ "$arch" = arm64e ]; then
	set -- "$@" -miphoneos-version-min=12.0
fi
exec "${LEGACY_PREFIX}${0##*/}" "$@"
