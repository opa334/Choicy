INSTALL_TARGET_PROCESSES = SpringBoard

export TARGET = iphone:clang:13.0:8.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 0_Choicy

0_Choicy_FILES = $(wildcard *.x)
0_Choicy_CFLAGS = -fobjc-arc
0_Choicy_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
