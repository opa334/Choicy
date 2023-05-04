ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:16.2:15.0
else
TARGET = iphone:clang:13.7:8.0
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ChoicyPrefs

ChoicyPrefs_FILES = $(wildcard *.m) $(wildcard *.x) ../Shared.m ../ChoicyPrefsMigrator.m
ChoicyPrefs_INSTALL_PATH = /Library/PreferenceBundles
ChoicyPrefs_FRAMEWORKS = UIKit
ChoicyPrefs_PRIVATE_FRAMEWORKS = Preferences MobileCoreServices
ChoicyPrefs_EXTRA_FRAMEWORKS = AltList
ChoicyPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ifneq ($(THEOS_PACKAGE_SCHEME),rootless)
ChoicyPrefs_CFLAGS += -DXINA_SUPPORT
endif

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ChoicyPrefs.plist$(ECHO_END)
