ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_COMPRESSION_TYPE = gzip
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk
SUBPROJECTS += module module1x2 module2x3 module3x2 module3x3 utilitymodule utilitytoggle utilitytheme systemoverlay prefs app
include $(THEOS_MAKE_PATH)/aggregate.mk
