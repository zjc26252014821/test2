include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CleanCCBGSystemOverlays
CleanCCBGSystemOverlays_FILES = CleanCCBGSystemOverlays.m ../shared/CCBGMediaCatalog.m
CleanCCBGSystemOverlays_FRAMEWORKS = UIKit AVFoundation QuartzCore Network ImageIO
CleanCCBGSystemOverlays_CFLAGS = -fobjc-arc -I../shared

include $(THEOS_MAKE_PATH)/tweak.mk
