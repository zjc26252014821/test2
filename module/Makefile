include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CleanCCBG2x2
CleanCCBG2x2_FILES = CleanCCBG2x2.m ../shared/CCBGMediaCatalog.m
CleanCCBG2x2_FRAMEWORKS = UIKit AVFoundation AVKit CoreImage QuartzCore ImageIO
CleanCCBG2x2_CFLAGS = -fobjc-arc -I../shared -DCCBG_DEFAULT_GRID_WIDTH=2 -DCCBG_DEFAULT_GRID_HEIGHT=2
CleanCCBG2x2_INSTALL_PATH = /Library/ControlCenter/Bundles
CleanCCBG2x2_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
