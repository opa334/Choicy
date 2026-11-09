#!/bin/sh
set -eu

# Use modern Xcode and a RootHide Theos checkout (which also supports the
# default and rootless schemes), with matching AltList development frameworks.
: "${THEOS:?Set THEOS to the prepared RootHide Theos checkout}"

for scheme in rootless roothide ''; do
	make clean THEOS_PACKAGE_SCHEME="$scheme"
	make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$scheme"
done
