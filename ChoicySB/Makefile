INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChoicySB

ChoicySB_FILES = $(wildcard *.x) ../Shared.x
ChoicySB_CFLAGS = -fobjc-arc
ChoicySB_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk
