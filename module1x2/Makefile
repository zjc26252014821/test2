include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CleanCCBG1x2
CleanCCBG1x2_FILES = ../module/CleanCCBG2x2.m ../shared/CCBGMediaCatalog.m
CleanCCBG1x2_FRAMEWORKS = UIKit AVFoundation AVKit CoreImage QuartzCore ImageIO
CleanCCBG1x2_CFLAGS = -fobjc-arc -I../shared -DCCBG_VIEW_CONTROLLER_CLASS=CleanCCBG1x2ViewController -DCCBG_MODULE_CLASS=CleanCCBG1x2Module -DCCBG_MODULE_SLOT=1 -DCCBG_DEFAULT_GRID_WIDTH=1 -DCCBG_DEFAULT_GRID_HEIGHT=2
CleanCCBG1x2_INSTALL_PATH = /Library/ControlCenter/Bundles
CleanCCBG1x2_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
