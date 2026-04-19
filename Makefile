TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

export THEOS_PACKAGE_SCHEME ?= rootless

ADDITIONAL_CFLAGS = -Wno-unused-variable -Wno-unused-parameter

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MediaFloater

MediaFloater_FILES = Tweak.xm
MediaFloater_FRAMEWORKS = UIKit Foundation MediaPlayer
MediaFloater_PRIVATE_FRAMEWORKS = MediaRemote
MediaFloater_CFLAGS = -fobjc-arc -I. $(ADDITIONAL_CFLAGS)
MediaFloater_INFO_PLIST = Info.plist

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"