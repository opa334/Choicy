ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
export TARGET = iphone:clang:16.5:15.0
export ARCHS = arm64 arm64e
else
export TARGET = iphone:clang:13.7:8.0
export ARCHS = armv7 arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Choicy

Choicy_FILES = Tweak.c Tweak.s nextstep_plist.c $(wildcard external/litehook/src/*.c)
Choicy_CFLAGS = -DTHEOS_LEAN_AND_MEAN -I./external/litehook/src -I./external/litehook/external/include
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
