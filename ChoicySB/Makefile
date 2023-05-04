INSTALL_TARGET_PROCESSES = SpringBoard

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:16.2:15.0
else
TARGET = iphone:clang:13.7:8.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChoicySB

ChoicySB_FILES = $(wildcard *.x) $(wildcard *.m) ../Shared.m ../ChoicyPrefsMigrator.m
ChoicySB_CFLAGS = -fobjc-arc -Wno-unguarded-availability-new
ChoicySB_PRIVATE_FRAMEWORKS = BackBoardServices
ifneq ($(THEOS_PACKAGE_SCHEME),rootless)
ChoicySB_CFLAGS += -DXINA_SUPPORT
endif

include $(THEOS_MAKE_PATH)/tweak.mk
