include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CleanCCBG2x3
CleanCCBG2x3_FILES = ../module/CleanCCBG2x2.m ../shared/CCBGMediaCatalog.m
CleanCCBG2x3_FRAMEWORKS = UIKit AVFoundation AVKit CoreImage QuartzCore ImageIO
CleanCCBG2x3_CFLAGS = -fobjc-arc -I../shared -DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG2x3ViewController -DCCBG_MODULE_CLASS=CleanCCBG2x3Module -DCCBG_MODULE_SLOT=2 -DCCBG_DEFAULT_GRID_WIDTH=2 -DCCBG_DEFAULT_GRID_HEIGHT=3
CleanCCBG2x3_INSTALL_PATH = /Library/ControlCenter/Bundles
CleanCCBG2x3_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
