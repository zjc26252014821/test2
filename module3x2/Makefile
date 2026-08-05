include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CleanCCBG3x2
CleanCCBG3x2_FILES = ../module/CleanCCBG2x2.m ../shared/CCBGMediaCatalog.m
CleanCCBG3x2_FRAMEWORKS = UIKit AVFoundation AVKit CoreImage QuartzCore ImageIO
CleanCCBG3x2_CFLAGS = -fobjc-arc -I../shared -DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG3x2ViewController -DCCBG_MODULE_CLASS=CleanCCBG3x2Module -DCCBG_MODULE_SLOT=3 -DCCBG_DEFAULT_GRID_WIDTH=3 -DCCBG_DEFAULT_GRID_HEIGHT=2
CleanCCBG3x2_INSTALL_PATH = /Library/ControlCenter/Bundles
CleanCCBG3x2_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
