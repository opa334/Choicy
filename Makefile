export TARGET = iphone:clang:13.4:8.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Choicy

Choicy_FILES = $(wildcard *.x)
Choicy_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN # <- this makes theos not link against anything by default (we do not want to link UIKit cause we inject system wide)
Choicy_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
SUBPROJECTS += ChoicySB
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.dylib" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.dylib" $(ECHO_END)
	$(ECHO_NOTHING)mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/Choicy.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/   Choicy.plist" $(ECHO_END)