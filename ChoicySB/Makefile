INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChoicySB

ChoicySB_FILES = $(wildcard *.x) $(wildcard *.m) ../Shared.m ../ChoicyPrefsMigrator.m
ChoicySB_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
ChoicySB_FRAMEWORKS = UIKit QuartzCore
ChoicySB_PRIVATE_FRAMEWORKS = BackBoardServices
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ChoicySB_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk
