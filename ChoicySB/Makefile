INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChoicySB

ChoicySB_FILES = $(wildcard *.x) $(wildcard *.m) ../Shared.m ../ChoicyPrefsMigrator.m
ChoicySB_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
ChoicySB_CFLAGS += -DXINA_SUPPORT
ChoicySB_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk
