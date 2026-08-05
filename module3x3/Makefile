include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CleanCCBG3x3
CleanCCBG3x3_FILES = ../module/CleanCCBG2x2.m ../shared/CCBGMediaCatalog.m
CleanCCBG3x3_FRAMEWORKS = UIKit AVFoundation AVKit CoreImage QuartzCore ImageIO
CleanCCBG3x3_CFLAGS = -fobjc-arc -I../shared -DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG3x3ViewController -DCCBG_MODULE_CLASS=CleanCCBG3x3Module -DCCBG_MODULE_SLOT=4 -DCCBG_DEFAULT_GRID_WIDTH=3 -DCCBG_DEFAULT_GRID_HEIGHT=3
CleanCCBG3x3_INSTALL_PATH = /Library/ControlCenter/Bundles
CleanCCBG3x3_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
