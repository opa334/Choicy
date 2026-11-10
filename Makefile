CHOICY_LEGACY ?= 0

ifeq ($(CHOICY_LEGACY),1)
ifneq ($(strip $(THEOS_PACKAGE_SCHEME)),)
$(error Legacy Choicy requires an empty THEOS_PACKAGE_SCHEME)
endif
ifneq ($(filter package install do,$(MAKECMDGOALS)),)
$(error Use sh ./legacy_build.sh to build the legacy package)
endif
ifeq ($(strip $(LEGACY_PREFIX)),)
$(error Set LEGACY_PREFIX and run sh ./legacy_build.sh)
endif
ifeq ($(strip $(LEGACY_SDKROOT)),)
$(error Set LEGACY_SDKROOT and run sh ./legacy_build.sh)
endif
ifeq ($(strip $(CHOICY_LEGACY_TOOL_PREFIX)),)
$(error Run sh ./legacy_build.sh to prepare the legacy compiler prefix)
endif

export TARGET = iphone:clang:13.7:10.0
export ARCHS = armv7 arm64 arm64e
export PREFIX = $(CHOICY_LEGACY_TOOL_PREFIX)
export LEGACY_PREFIX LEGACY_SDKROOT
ifneq ($(TARGET),iphone:clang:13.7:10.0)
$(error Legacy Choicy requires TARGET=iphone:clang:13.7:10.0)
endif
ifneq ($(strip $(ARCHS)),armv7 arm64 arm64e)
$(error Legacy Choicy requires ARCHS='armv7 arm64 arm64e')
endif
ifneq ($(PREFIX),$(CHOICY_LEGACY_TOOL_PREFIX))
$(error Legacy Choicy requires the compiler prefix prepared by legacy_build.sh)
endif
choicy_hook_source := Tweak.s
else ifeq ($(CHOICY_LEGACY),0)
ifneq ($(filter legacy-package,$(MAKECMDGOALS)),)
$(error legacy-package requires CHOICY_LEGACY=1 via sh ./legacy_build.sh)
endif
export TARGET = iphone:clang:16.5:15.0
export ARCHS = arm64 arm64e
choicy_hook_source := gen.c
else
$(error CHOICY_LEGACY must be 0 or 1)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Choicy

Choicy_FILES = Tweak.c $(choicy_hook_source) nextstep_plist.c $(wildcard external/litehook/src/*.c)
Choicy_CFLAGS = -DTHEOS_LEAN_AND_MEAN -I./external/litehook/src -I./external/litehook/external/include
# LiteHook's Mach return code can be unused in final builds.
external/litehook/src/litehook.c_CFLAGS += -Wno-error=unused-variable
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Choicy_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += ChoicyPrefs
SUBPROJECTS += ChoicySB
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.dylib" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib" $(ECHO_END)
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.plist" $(ECHO_END)

ifeq ($(CHOICY_LEGACY),1)
.PHONY: legacy-package
legacy-package: all stage
	python3 scripts/package-legacy.py package "$(THEOS_STAGING_DIR)"
endif
