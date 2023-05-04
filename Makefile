ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
export TARGET = iphone:clang:16.2:15.0
export ARCHS = arm64 arm64e
else
export TARGET = iphone:clang:13.7:8.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Choicy

Choicy_FILES = Tweak.x Shared.m ChoicyPrefsMigrator.m
Choicy_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN # <- this makes theos not link against anything by default (we do not want to link UIKit cause we inject system wide)
ifneq ($(THEOS_PACKAGE_SCHEME),rootless)
Choicy_CFLAGS += -DXINA_SUPPORT
endif
Choicy_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += ChoicyPrefs
SUBPROJECTS += ChoicySB
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.dylib" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib" $(ECHO_END)
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.plist" $(ECHO_END)