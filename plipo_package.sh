# if you want to bring this to your tweak - pre requisites:

# xcode 12 installed and selected via xcode-select
# xcode 11 toolchain (https://archive.quiprr.dev/developer/toolchains/Xcode.xctoolchain.tar.xz) at $THEOS/toolchains/Xcode11.xctoolchain

# plipo: patched up version of lipo by Matchstic (see: https://github.com/theos/theos/issues/563#issuecomment-759609420)
# Rename it from lipo to plipo and put it into /usr/local/bin

# Your Makefile needs to set the prefix based on XCODE_12_SLICE (see CCSupport Makefile for an example)
# Note: if you export PREFIX (instead of setting it without export), it will automatically apply to all subprojects

# If you want to check if this worked, extract the deb and use the "file" command on a dylib and see whether it has two arm64e slices
# Example output (+exclusive path leak):
# file /Users/opa334/Desktop/com.opa334.choicy_1.3.2_iphoneos-arm/data/Library/MobileSubstrate/DynamicLibraries/\ \ \ Choicy.dylib
# /Users/opa334/Desktop/com.opa334.choicy_1.3.2_iphoneos-arm/data/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib: Mach-O universal binary with 3 architectures: [arm64:Mach-O 64-bit dynamically linked shared library arm64] [arm64e:Mach-O 64-bit dynamically linked shared library arm64e] [arm64e:Mach-O 64-bit dynamically linked shared library arm64e]
# /Users/opa334/Desktop/com.opa334.choicy_1.3.2_iphoneos-arm/data/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib (for architecture arm64):	Mach-O 64-bit dynamically linked shared library arm64
# /Users/opa334/Desktop/com.opa334.choicy_1.3.2_iphoneos-arm/data/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib (for architecture arm64e):	Mach-O 64-bit dynamically linked shared library arm64e
# /Users/opa334/Desktop/com.opa334.choicy_1.3.2_iphoneos-arm/data/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib (for architecture arm64e):	Mach-O 64-bit dynamically linked shared library arm64e

PLIPO_TMP="./plipo_tmp"

populatePlipoTmp () {
	fileOutput=$(file $1)
	if [[ $fileOutput == *"dynamically linked shared library"* ]]; then
		if [[ $1 != *"/arm64e/"* ]]; then
			plipo_tmp_file=./$PLIPO_TMP/$(basename $1)
			cp $1 $plipo_tmp_file
		fi
	fi
}

consumePlipoTmp () {
	fileOutput=$(file $1)
	if [[ $fileOutput == *"dynamically linked shared library"* ]]; then
		if [[ $1 != *"/arm64e/"* ]] && [[ $1 != *"/arm64/"* ]] && [[ $1 != *"/armv7s/"* ]] && [[ $1 != *"/armv7/"* ]]; then
			plipo_tmp_file=./$PLIPO_TMP/$(basename $1)
			plipo $1 $plipo_tmp_file -output $1 -create
		fi
	fi
}

make clean
echo "Building Xcode 12 slice..."
make FINALPACKAGE=1 XCODE_12_SLICE=1
mkdir $PLIPO_TMP

find ./.theos/obj -print0 | while IFS= read -r -d '' file; do populatePlipoTmp "$file"; done

make clean
echo "Building other slices..."
make FINALPACKAGE=1 XCODE_12_SLICE=0

echo "Combining..."
find ./.theos/obj -print0 | while IFS= read -r -d '' file; do consumePlipoTmp "$file"; done

rm -rf plipo_tmp
echo "Packaging..."

# just running make package works because theos detects that the dylib
# already exists so it just uses that to package instead of recompiling

if [ "$1" == "install" ]; then
make package FINALPACKAGE=1 install
else
make package FINALPACKAGE=1
fi