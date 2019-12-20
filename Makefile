export TARGET = iphone:clang:13.0:8.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 000_Choicy

000_Choicy_FILES = $(wildcard *.x)
000_Choicy_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN # <- this makes theos not link against anything by default (we do not want to link UIKit cause we inject system wide)
000_Choicy_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
SUBPROJECTS += ChoicySB
include $(THEOS_MAKE_PATH)/aggregate.mk
