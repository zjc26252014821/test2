#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import "CCBGMediaCatalog.h"

#ifndef CCBG_VIEW_CONTROLLER_CLASS
#define CCBG_VIEW_CONTROLLER_CLASS CleanCCBG2x2ViewController
#endif
#ifndef CCBG_MODULE_CLASS
#define CCBG_MODULE_CLASS CleanCCBG2x2Module
#endif
#ifndef CCBG_MODULE_SLOT
#define CCBG_MODULE_SLOT 0
#endif
#ifndef CCBG_DEFAULT_GRID_WIDTH
#define CCBG_DEFAULT_GRID_WIDTH 2
#endif
#ifndef CCBG_DEFAULT_GRID_HEIGHT
#define CCBG_DEFAULT_GRID_HEIGHT 2
#endif

static NSDictionary<NSString *, id> *CCBGModulePreferenceSnapshot;
static BOOL CCBGLastKnownLayoutLandscape = NO;
static BOOL CCBGHasKnownLayoutOrientation = NO;
static NSString *const CCBGModuleLayoutOrientationDidChangeNotification = @"com.zjc.cleanccbg2x2.module-layout-orientation";

static BOOL CCBGHasVisibleOverlappingSiblingAbove(UIView *view) {
    UIView *parent = view.superview;
    if (!parent) return NO;
    NSUInteger index = [parent.subviews indexOfObjectIdenticalTo:view];
    if (index == NSNotFound || index + 1 >= parent.subviews.count) return NO;
    for (NSUInteger siblingIndex = index + 1; siblingIndex < parent.subviews.count; siblingIndex++) {
        UIView *sibling = parent.subviews[siblingIndex];
        if (sibling.hidden || sibling.alpha < 0.01 || sibling.layer.hidden || sibling.layer.opacity < 0.01f) continue;
        if (CGRectIntersectsRect(view.frame, sibling.frame)) return YES;
    }
    return NO;
}

typedef struct {
    NSUInteger width;
    NSUInteger height;
} CCUILayoutSize;
static NSString *CCBGLastRuntimeSizeLogSignature;
static BOOL CCBGHasCachedRuntimeGridSize = NO;
static BOOL CCBGCachedRuntimeGridHadDomain = NO;
static NSUInteger CCBGCachedRuntimeGridWidth = CCBG_DEFAULT_GRID_WIDTH;
static NSUInteger CCBGCachedRuntimeGridHeight = CCBG_DEFAULT_GRID_HEIGHT;
static NSTimeInterval CCBGLastRuntimeGridReadAt = 0;
static BOOL CCBGHasCachedCCAsterGridSizes = NO;
static NSDictionary<NSString *, id> *CCBGCachedCCAsterGridSizes;
static NSTimeInterval CCBGLastCCAsterGridReadAt = 0;
// CCAster creates this shield inside each module while its own long-press
// edit mode owns resize handles. Clean must not claim that same touch.
static NSInteger const kCCBGCCAsterEditShieldTag = 181017;

static BOOL CCBGIsCCAsterEditModeActive(UIView *view) {
    if (!view) return NO;
    UIView *moduleShield = [view viewWithTag:kCCBGCCAsterEditShieldTag];
    if (moduleShield && !moduleShield.hidden && moduleShield.alpha > 0.01 && moduleShield.userInteractionEnabled) return YES;
    UIWindow *window = view.window;
    UIView *overlayShield = [window viewWithTag:181021];
    return overlayShield && !overlayShield.hidden && overlayShield.alpha > 0.01 && overlayShield.userInteractionEnabled;
}

// AVPlayerViewController owns the transport controls, but its content view
// should still allow Clean's module-level gestures. Only hand touches on a
// scrubber/button back to the native player; the video surface remains ours.
static BOOL CCBGTouchIsNativeTransportControl(UITouch *touch, UIView *nativeView) {
    if (!touch || !nativeView) return NO;
    for (UIView *view = touch.view; view && view != nativeView; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UISlider.class]) return YES;
        NSString *className = NSStringFromClass(view.class);
        if ([className localizedCaseInsensitiveContainsString:@"transport"] ||
            [className localizedCaseInsensitiveContainsString:@"scrubber"] ||
            [className localizedCaseInsensitiveContainsString:@"playbackcontrol"]) return YES;
    }
    return NO;
}

static char CCBGAppliedGaussianBlurKey;
static char CCBGAppliedGaussianBlurFilterKey;

// Keep every media surface on the same continuous rounded-rect geometry as
// the module.  Player layers are often inset for safe framing, so their
// radius must be reduced by that inset instead of reusing the outer radius.
static CGFloat CCBGMediaInsetForFrame(UIView *moduleView, CGRect frame) {
    if (!moduleView) return 0.0;
    CGRect bounds = moduleView.bounds;
    return MAX(0.0, MIN(MIN(CGRectGetMinX(frame), CGRectGetMinY(frame)),
                         MIN(CGRectGetMaxX(bounds) - CGRectGetMaxX(frame),
                             CGRectGetMaxY(bounds) - CGRectGetMaxY(frame))));
}

// Match Control Center's continuous corner geometry (also used by CCAster)
// instead of using one fixed radius for every grid size.
static CGFloat CCBGContinuousCornerRadiusForSize(CGSize size) {
    CGFloat minimum = MIN(size.width, size.height);
    if (minimum <= 0.0) return 0.0;
    BOOL isOneByOne = fabs(size.width - size.height) <= 3.0 && minimum <= 76.0;
    if (isOneByOne) return minimum * 0.5;
    return MIN(32.0, MAX(22.0, minimum * 0.5 - 6.0));
}

static void CCBGApplyMediaSubviewCorners(UIView *moduleView, UIView *mediaView) {
    if (!moduleView || !mediaView) return;
    CGFloat radius = MAX(0.0, moduleView.layer.cornerRadius - CCBGMediaInsetForFrame(moduleView, mediaView.frame));
    mediaView.layer.cornerRadius = radius;
    mediaView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) mediaView.layer.cornerCurve = kCACornerCurveContinuous;
}

static void CCBGApplyMatchedMediaCorners(UIView *moduleView, CALayer *mediaLayer, UIView *mediaView) {
    if (!moduleView) return;
    CGFloat outerRadius = MAX(0.0, moduleView.layer.cornerRadius);
    CGFloat inset = 0.0;
    if (mediaLayer) {
        CGRect frame = mediaLayer.frame;
        inset = CCBGMediaInsetForFrame(moduleView, frame);
        CGFloat radius = MAX(0.0, outerRadius - inset);
        mediaLayer.cornerRadius = radius;
        mediaLayer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) mediaLayer.cornerCurve = kCACornerCurveContinuous;
    }
    if (mediaView) {
        CGFloat radius = MAX(0.0, outerRadius - inset);
        mediaView.layer.cornerRadius = radius;
        mediaView.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) mediaView.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static void CCBGApplyAllMediaCorners(UIView *moduleView, NSArray<UIView *> *mediaViews, CALayer *mediaLayer, UIView *nativeView) {
    CCBGApplyMatchedMediaCorners(moduleView, mediaLayer, nativeView);
    for (UIView *view in mediaViews) CCBGApplyMediaSubviewCorners(moduleView, view);
}

static void CCBGAnimateCornerRadiusForLayers(NSArray<CALayer *> *layers, CGFloat fromRadius, CGFloat toRadius, NSTimeInterval duration) {
    if (!layers.count || UIAccessibilityIsReduceMotionEnabled() || fabs(fromRadius - toRadius) <= 0.01) return;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
    animation.fromValue = @(fromRadius);
    animation.toValue = @(toRadius);
    animation.duration = MIN(0.30, MAX(0.12, duration));
    animation.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1.0 :0.32 :1.0];
    for (CALayer *layer in layers) {
        if (!layer) continue;
        [layer removeAnimationForKey:@"ccbg.cornerRadius"];
        [layer addAnimation:animation forKey:@"ccbg.cornerRadius"];
    }
}

static void CCBGApplyGaussianBlurToLayer(CALayer *layer, CGFloat intensity) {
    if (!layer) return;
    intensity = MIN(1.0, MAX(0.0, intensity));
    // A pan can deliver dozens of sub-percent updates per frame. The visual
    // result is unchanged below one percentage point, but rebuilding three
    // private CAFilter instances for every update is expensive on SpringBoard.
    intensity = round(intensity * 100.0) / 100.0;
    NSNumber *applied = objc_getAssociatedObject(layer, &CCBGAppliedGaussianBlurKey);
    id appliedFilter = objc_getAssociatedObject(layer, &CCBGAppliedGaussianBlurFilterKey);
    BOOL filterStateMatches = intensity <= 0.001
        ? layer.filters.count == 0
        : layer.filters.count == 1 && appliedFilter && layer.filters.firstObject == appliedFilter;
    if (applied && fabs(applied.doubleValue - intensity) <= 0.001 && filterStateMatches) return;
    if (intensity <= 0.001) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.filters = nil;
        [CATransaction commit];
        objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurKey, @0.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurFilterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    Class filterClass = objc_getClass("CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithType:");
    SEL setValue = NSSelectorFromString(@"setValue:forKey:");
    if (!filterClass || ![filterClass respondsToSelector:factory]) return;
    // CAFilter is a private Core Animation object. Reusing an instance can
    // leave the layer visually stuck at its previous inputRadius on some
    // SpringBoard builds, even though setValue: succeeds. Recreate it when
    // the intensity changes so the gesture always produces a visible update.
    id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, factory, @"gaussianBlur");
    if (!filter) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(filter, setValue, @(intensity * 32.0), @"inputRadius");
    ((void (*)(id, SEL, id, id))objc_msgSend)(filter, setValue, @YES, @"inputNormalizeEdges");
    // CAFilter arrays can retain the previous private filter when a layer is
    // reused by AVPlayerViewController during an expansion. Replace the array
    // atomically so repeated blur adjustments never compound.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.filters = nil;
    layer.filters = @[filter];
    [CATransaction commit];
    objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurKey, @(intensity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurFilterKey, filter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CCBGRefreshModulePreferenceSnapshot(void) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in CCBGModuleConfigurationKeys()) {
        [keys addObject:CCBGPreferenceKeyForModule(key, CCBG_MODULE_SLOT)];
    }
    [keys addObject:CCBGPreferenceKeyForModule(@"currentMedia", CCBG_MODULE_SLOT)];
    [keys addObject:CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", CCBG_MODULE_SLOT)];
    [keys addObject:@"pluginEnabled"];
    [keys addObject:@"fiveModulePresentationRecoveryGeneration"];
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesAppSynchronize(domain);
    CFDictionaryRef values = CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
                                                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CCBGModulePreferenceSnapshot = CFBridgingRelease(values) ?: @{};
}

static void CCBGSetCachedModulePreference(NSString *key, id value) {
    if (!CCBGModulePreferenceSnapshot) return;
    NSMutableDictionary *updated = [CCBGModulePreferenceSnapshot mutableCopy];
    NSString *scopedKey = CCBGPreferenceKeyForModule(key, CCBG_MODULE_SLOT);
    if (value) updated[scopedKey] = value;
    else [updated removeObjectForKey:scopedKey];
    CCBGModulePreferenceSnapshot = updated;
}

static id CCBGModulePreference(NSString *key, id fallback) {
    if (!CCBGModulePreferenceSnapshot) return CCBGReadModulePreference(key, CCBG_MODULE_SLOT, fallback);
    id value = CCBGModulePreferenceSnapshot[CCBGPreferenceKeyForModule(key, CCBG_MODULE_SLOT)];
    return value ?: fallback;
}

static id CCBGModuleGlobalPreference(NSString *key, id fallback) {
    if (!CCBGModulePreferenceSnapshot) return CCBGReadPreference(key, fallback);
    id value = CCBGModulePreferenceSnapshot[key];
    return value ?: fallback;
}

static BOOL CCBGPresentationItemsEqual(NSDictionary *left, NSDictionary *right) {
    if (left == right) return YES;
    if (!left || !right) return NO;
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"fileName", @"mute", @"loop", @"playbackRate", @"startTime", @"endTime",
            @"contentMode", @"blurIntensity", @"dim", @"saturation", @"contrast", @"opacity",
            @"focalX", @"focalY", @"imageDuration", @"videoAdvancePolicy", @"videoPlayCount",
            @"compactContentMode", @"expandedContentMode", @"compactFocalX", @"compactFocalY",
            @"expandedFocalX", @"expandedFocalY", @"compactCropZoom", @"expandedCropZoom",
            @"portraitContentMode", @"landscapeContentMode", @"portraitFocalX", @"portraitFocalY",
            @"landscapeFocalX", @"landscapeFocalY", @"autoColor",
        ];
    });
    for (NSString *key in keys) {
        id a = left[key] ?: NSNull.null;
        id b = right[key] ?: NSNull.null;
        if (![a isEqual:b]) return NO;
    }
    return YES;
}

@protocol CCUIContentModule <NSObject>
@property(nonatomic, readonly) UIViewController *contentViewController;
@property(nonatomic, readonly) UIViewController *backgroundViewController;
@optional
- (BOOL)_canShowWhileLocked;
- (void)controlCenterModuleDidReceiveTap;
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation;
@end

static void CCBGRecordModuleLayoutOrientation(int orientation) {
    BOOL landscape = orientation == 1 || orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
    BOOL changed = !CCBGHasKnownLayoutOrientation || CCBGLastKnownLayoutLandscape != landscape;
    CCBGHasKnownLayoutOrientation = YES;
    CCBGLastKnownLayoutLandscape = landscape;
    if (!changed) return;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"module-layout-orientation", @{ @"orientation": @(orientation), @"landscape": @(landscape) });
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CCBGModuleLayoutOrientationDidChangeNotification object:nil];
    });
}

static BOOL CCBGReadCCAsterGridSize(id controller, CCUILayoutSize *size) {
    if (!controller || !size) return NO;
    NSString *identifier = nil;
    @try {
        id module = [controller valueForKey:@"moduleOwner"];
        id context = [module valueForKey:@"contentModuleContext"];
        id value = [context valueForKey:@"moduleIdentifier"];
        if ([value isKindOfClass:NSString.class]) identifier = value;
    } @catch (__unused NSException *exception) {}
    if (!identifier.length) {
        NSArray<NSString *> *fallbacks = @[
            @"com.zjc.cleanccbg2x2.module", @"com.zjc.cleanccbg2x2.module1x2",
            @"com.zjc.cleanccbg2x2.module2x3", @"com.zjc.cleanccbg2x2.module3x2",
            @"com.zjc.cleanccbg2x2.module3x3",
        ];
        if (CCBG_MODULE_SLOT >= 0 && CCBG_MODULE_SLOT < (NSInteger)fallbacks.count) identifier = fallbacks[CCBG_MODULE_SLOT];
    }
    if (!identifier.length) return NO;
    CFStringRef domain = CFSTR("com.futur3sn0w.ccaster.preferences");
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    // CCAster writes continuously only while its resize shield is active.
    // Outside that deliberate edit gesture, avoid having each Clean module
    // synchronize the external preference domain on every layout burst.
    UIView *controllerView = [(UIViewController *)controller viewIfLoaded];
    NSTimeInterval cacheInterval = CCBGIsCCAsterEditModeActive(controllerView) ? 0.10 : 2.0;
    if (!CCBGHasCachedCCAsterGridSizes || now - CCBGLastCCAsterGridReadAt >= cacheInterval) {
        // CCAster is written by the settings app but read from SpringBoard.
        // Keep a short cache because Control Center asks for module size many
        // times per layout pass, while size-reload notifications invalidate it
        // immediately after a Clean setting changes.
        CFPreferencesAppSynchronize(domain);
        CFPropertyListRef sizesRef = CFPreferencesCopyAppValue(CFSTR("ModuleGridSizes"), domain);
        CCBGCachedCCAsterGridSizes = CFBridgingRelease(sizesRef) ?: @{};
        CCBGHasCachedCCAsterGridSizes = YES;
        CCBGLastCCAsterGridReadAt = now;
    }
    NSDictionary *sizes = CCBGCachedCCAsterGridSizes;
    NSArray *custom = [sizes[identifier] isKindOfClass:NSArray.class] ? sizes[identifier] : nil;
    if (custom.count < 2) return NO;
    NSInteger width = MIN(4, MAX(1, [custom[0] integerValue]));
    NSInteger height = MIN(4, MAX(1, [custom[1] integerValue]));
    if (width < 1 || height < 1) return NO;
    *size = (CCUILayoutSize){(NSUInteger)width, (NSUInteger)height};
    return YES;
}

static CCUILayoutSize CCBGRuntimeModuleSize(int orientation) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    // Clean's own size writes send CCBGSizeReloadCallback and invalidate this
    // cache immediately, so normal Control Center layout does not need to
    // cross the preference boundary more than once every two seconds.
    if (!CCBGHasCachedRuntimeGridSize || now - CCBGLastRuntimeGridReadAt >= 2.0) {
        NSArray<NSString *> *keys = @[
            CCBGPreferenceKeyForModule(@"gridWidth", CCBG_MODULE_SLOT),
            CCBGPreferenceKeyForModule(@"gridHeight", CCBG_MODULE_SLOT),
        ];
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesAppSynchronize(domain);
        CFDictionaryRef valuesRef = CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        BOOL hadDomain = valuesRef != NULL;
        NSDictionary *preferences = CFBridgingRelease(valuesRef) ?: @{};
        NSNumber *configuredWidth = preferences[CCBGPreferenceKeyForModule(@"gridWidth", CCBG_MODULE_SLOT)];
        NSNumber *configuredHeight = preferences[CCBGPreferenceKeyForModule(@"gridHeight", CCBG_MODULE_SLOT)];
        CCBGCachedRuntimeGridWidth = (NSUInteger)MIN(4, MAX(1, configuredWidth ? configuredWidth.integerValue : CCBG_DEFAULT_GRID_WIDTH));
        CCBGCachedRuntimeGridHeight = (NSUInteger)MIN(4, MAX(1, configuredHeight ? configuredHeight.integerValue : CCBG_DEFAULT_GRID_HEIGHT));
        CCBGCachedRuntimeGridHadDomain = hadDomain;
        CCBGHasCachedRuntimeGridSize = YES;
        CCBGLastRuntimeGridReadAt = now;
    }
    NSUInteger width = CCBGCachedRuntimeGridWidth;
    NSUInteger height = CCBGCachedRuntimeGridHeight;
    BOOL landscape = orientation == 1 || orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
    CCBGRecordModuleLayoutOrientation(orientation);
    NSString *signature = [NSString stringWithFormat:@"%d|%lu|%lu|%d", orientation, (unsigned long)width, (unsigned long)height, CCBGCachedRuntimeGridHadDomain];
    if (![signature isEqualToString:CCBGLastRuntimeSizeLogSignature]) {
        CCBGLastRuntimeSizeLogSignature = [signature copy];
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"size", @{@"orientation": @(orientation), @"width": @(width), @"height": @(height), @"hasDomain": @(CCBGCachedRuntimeGridHadDomain)});
    }
    return landscape ? (CCUILayoutSize){height, width} : (CCUILayoutSize){width, height};
}

static BOOL CCBGCurrentInterfaceIsLandscape(UIView *view) {
    // Control Center can report a stale scene orientation while it is
    // re-laying out. A mounted window's bounds are the current visual truth.
    CGRect windowBounds = view.window.bounds;
    if (CGRectGetWidth(windowBounds) > 1.0 && CGRectGetHeight(windowBounds) > 1.0 &&
        fabs(CGRectGetWidth(windowBounds) - CGRectGetHeight(windowBounds)) > 1.0) {
        return CGRectGetWidth(windowBounds) > CGRectGetHeight(windowBounds);
    }
    if (@available(iOS 13.0, *)) {
        UIInterfaceOrientation orientation = view.window.windowScene.interfaceOrientation;
        if (UIInterfaceOrientationIsLandscape(orientation)) return YES;
        if (UIInterfaceOrientationIsPortrait(orientation)) return NO;
    }
    if (CCBGHasKnownLayoutOrientation) return CCBGLastKnownLayoutLandscape;
    UIDeviceOrientation deviceOrientation = UIDevice.currentDevice.orientation;
    if (UIDeviceOrientationIsLandscape(deviceOrientation)) return YES;
    if (UIDeviceOrientationIsPortrait(deviceOrientation)) return NO;
    return CGRectGetWidth(UIScreen.mainScreen.bounds) > CGRectGetHeight(UIScreen.mainScreen.bounds);
}

static BOOL CCBGSystemIsLocked(void) {
    for (NSString *className in @[@"SBLockScreenManager", @"SBCoverSheetPresentationManager"]) {
        Class cls = objc_getClass(className.UTF8String);
        SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
        if (!cls || ![cls respondsToSelector:sharedSelector]) continue;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSelector);
        for (NSString *selectorName in @[@"isUILocked", @"isLocked", @"isLockScreenVisible", @"isCoverSheetPresented"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([manager respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector)) return YES;
        }
    }
    return !UIApplication.sharedApplication.protectedDataAvailable;
}

static NSDictionary *CCBGSceneContextForModule(UIView *view) {
    return CCBGSceneRuntimeContext(view);
}

static float CCBGEffectivePlaybackRate(NSDictionary *item) {
    return MIN(2.0, MAX(0.5, [item[@"playbackRate"] floatValue]));
}

static BOOL CCBGUsesAdaptiveExpandedSize(void) {
    return [CCBGModulePreference(@"adaptiveExpandedSizeEnabled", @YES) boolValue];
}

static CGSize CCBGConfiguredExpandedMaximumSize(void) {
    CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGFloat screenHeight = CGRectGetHeight(UIScreen.mainScreen.bounds);
    // The expanded surface should use the available Control Center canvas.
    // 360x360 made portrait clips collapse to a narrow 220x360 card even
    // though the host had substantially more vertical room.
    CGFloat width = MIN(MAX(220.0, [CCBGModulePreference(@"expandedWidth", @430) doubleValue]), screenWidth - 24.0);
    CGFloat height = MIN(MAX(220.0, [CCBGModulePreference(@"expandedHeight", @600) doubleValue]), screenHeight - 100.0);
    return CGSizeMake(round(width), round(height));
}

static CGSize CCBGExpandedSizeForNaturalSize(CGSize naturalSize) {
    CGSize maximum = CCBGConfiguredExpandedMaximumSize();
    if (!CCBGUsesAdaptiveExpandedSize()) return maximum;
    if (naturalSize.width <= 0 || naturalSize.height <= 0) return maximum;
    CGFloat aspect = naturalSize.width / naturalSize.height;
    CGFloat width = maximum.width;
    CGFloat height = width / MAX(0.01, aspect);
    if (height > maximum.height) {
        height = maximum.height;
        width = height * aspect;
    }
    // The expanded module contains its own control strip. Keep a stable
    // minimum height so portrait/landscape media cannot collapse the preview
    // into a thin band above the controls.
    CGFloat minimumHeight = MIN(maximum.height, 300.0);
    return CGSizeMake(round(MAX(220.0, MIN(maximum.width, width))),
                      round(MAX(minimumHeight, MIN(maximum.height, height))));
}

static dispatch_queue_t CCBGThumbnailQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.module-thumbnails", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSCache<NSString *, UIImage *> *CCBGModuleThumbnailMemoryCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 96;
        cache.totalCostLimit = 8 * 1024 * 1024;
    });
    return cache;
}

static UIImage *CCBGPlaceholderImageForItem(NSDictionary *item) {
    NSString *fileName = item[@"fileName"] ?: @"";
    return [UIImage systemImageNamed:CCBGIsVideoName(fileName) ? @"video.fill" : @"photo.fill"];
}

static NSString *CCBGCachedThumbnailPath(NSDictionary *item, CGSize size) {
    NSString *fileName = item[@"fileName"] ?: @"";
    NSString *safeName = [[fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    NSString *cacheName = [NSString stringWithFormat:@"%@-%.0fx%.0f-%llu-%.0f-%.1f.jpg",
        safeName, size.width, size.height, [item[@"fileSize"] unsignedLongLongValue],
        [item[@"fileModifiedAt"] doubleValue], [item[@"coverFrameTime"] doubleValue]];
    return [@"/var/mobile/Library/CleanCCBG2x2/Thumbnails" stringByAppendingPathComponent:cacheName];
}

static UIImage *CCBGThumbnailForItem(NSDictionary *item, CGSize size) {
    NSString *path = CCBGPathForItem(item);
    NSString *fileName = item[@"fileName"] ?: @"";
    NSString *cacheDirectory = @"/var/mobile/Library/CleanCCBG2x2/Thumbnails";
    NSString *cachePath = CCBGCachedThumbnailPath(item, size);
    UIImage *memoryCached = [CCBGModuleThumbnailMemoryCache() objectForKey:cachePath];
    if (memoryCached) return memoryCached;
    UIImage *cached = [UIImage imageWithContentsOfFile:cachePath];
    if (cached) {
        [CCBGModuleThumbnailMemoryCache() setObject:cached forKey:cachePath cost:(NSUInteger)(cached.size.width * cached.size.height * 4.0)];
        return cached;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    UIImage *source = nil;
    if (CCBGIsVideoName(fileName)) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(size.width * 2.0, size.height * 2.0);
        generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
        generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
        NSTimeInterval coverFrameTime = [item[@"coverFrameTime"] doubleValue];
        NSArray<NSNumber *> *times = coverFrameTime > 0
            ? @[@(coverFrameTime), @(MAX(0.05, [item[@"startTime"] doubleValue])), @1.0, @2.0, @0.1]
            : @[@(MAX(0.05, [item[@"startTime"] doubleValue])), @1.0, @2.0, @0.1];
        for (NSNumber *secondsValue in times) {
            CGImageRef frame = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(secondsValue.doubleValue, 600) actualTime:nil error:nil];
            if (frame) {
                source = [UIImage imageWithCGImage:frame];
                CGImageRelease(frame);
                break;
            }
        }
    } else {
        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], nil);
        if (imageSource) {
            NSDictionary *options = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(size.width, size.height) * 2.0),
            };
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
            if (thumbnail) {
                source = [UIImage imageWithCGImage:thumbnail];
                CGImageRelease(thumbnail);
            }
            CFRelease(imageSource);
        }
    }
    if (!source) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor secondarySystemGroupedBackgroundColor] setFill];
        UIRectFill((CGRect){CGPointZero, size});
        CGFloat sourceRatio = source.size.width / MAX(1.0, source.size.height);
        CGFloat targetRatio = size.width / MAX(1.0, size.height);
        CGRect drawRect = CGRectZero;
        if (sourceRatio > targetRatio) {
            CGFloat width = size.height * sourceRatio;
            drawRect = CGRectMake((size.width - width) / 2.0, 0, width, size.height);
        } else {
            CGFloat height = size.width / MAX(0.01, sourceRatio);
            drawRect = CGRectMake(0, (size.height - height) / 2.0, size.width, height);
        }
        [source drawInRect:drawRect];
    }];
    NSData *jpeg = UIImageJPEGRepresentation(scaled, 0.78);
    if (jpeg) [jpeg writeToFile:cachePath atomically:YES];
    [CCBGModuleThumbnailMemoryCache() setObject:scaled forKey:cachePath cost:(NSUInteger)(scaled.size.width * scaled.size.height * 4.0)];
    return scaled;
}

#define CCBG_JOIN_INNER(left, right) left##right
#define CCBG_JOIN(left, right) CCBG_JOIN_INNER(left, right)

@interface CCBG_JOIN(CCBG_VIEW_CONTROLLER_CLASS, MountProbeView) : UIView
@property(nonatomic, copy) void (^windowChanged)(BOOL attached);
@end

@implementation CCBG_JOIN(CCBG_VIEW_CONTROLLER_CLASS, MountProbeView)
- (void)didMoveToWindow {
    [super didMoveToWindow];
    void (^handler)(BOOL) = self.windowChanged;
    if (handler) handler(self.window != nil);
}
@end

@interface CCBG_VIEW_CONTROLLER_CLASS : UIViewController <UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UIAdaptivePresentationControllerDelegate>
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UIView *dynamicTintView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerViewController *nativePlayerController;
@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIViewPropertyAnimator *blurAnimator;
@property(nonatomic, strong) UIView *dimView;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) UILabel *captionLabel;
@property(nonatomic, strong) UIView *expandedControlPanel;
@property(nonatomic, strong) UIVisualEffectView *expandedPanelMaterial;
@property(nonatomic) NSUInteger expandedPanelAnimationGeneration;
@property(nonatomic, strong) UIImageView *expandedStateIcon;
@property(nonatomic, strong) UILabel *expandedStateLabel;
@property(nonatomic, copy) NSString *lastExpandedStateText;
@property(nonatomic, copy) NSString *lastExpandedControlsSignature;
@property(nonatomic, copy) NSString *lastExpandedCaptionText;
@property(nonatomic, strong) UIStackView *expandedModeStack;
@property(nonatomic, copy) NSArray<UIButton *> *expandedModeButtons;
@property(nonatomic, strong) UIButton *expandedPresetButton;
@property(nonatomic, strong) UIButton *expandedMediaButton;
@property(nonatomic, strong) UIButton *expandedCompositionButton;
@property(nonatomic, copy) NSString *expandedPresetName;
@property(nonatomic, strong) NSNumber *displayedOpacity;
@property(nonatomic, strong) NSNumber *displayedBlurIntensity;
@property(nonatomic, strong) UISwipeGestureRecognizer *swipeLeft;
@property(nonatomic, strong) UISwipeGestureRecognizer *swipeRight;
@property(nonatomic, strong) UIPanGestureRecognizer *opacityPan;
@property(nonatomic, strong) UITapGestureRecognizer *compactTap;
@property(nonatomic, strong) UITapGestureRecognizer *doubleTap;
@property(nonatomic, strong) UITapGestureRecognizer *tripleTap;
@property(nonatomic, strong) UILongPressGestureRecognizer *actionLongPress;
@property(nonatomic, weak) UIView *gestureHostView;
@property(nonatomic) NSUInteger controlCenterTapCount;
@property(nonatomic) NSUInteger controlCenterTapGeneration;
@property(nonatomic) NSUInteger convergenceGeneration;
@property(nonatomic) BOOL convergenceSchedulePending;
@property(nonatomic, copy) NSString *lastConvergenceScheduleReason;
@property(nonatomic, copy) NSString *lastConvergenceDiagnosticSignature;
@property(nonatomic) NSTimeInterval lastConvergenceDiagnosticAt;
@property(nonatomic) NSTimeInterval lastProtocolTapAt;
@property(nonatomic) CGFloat opacityAtPanStart;
@property(nonatomic) CGFloat blurAtPanStart;
@property(nonatomic) BOOL adjustingBlur;
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaItems;
@property(nonatomic, strong) NSDictionary *currentItem;
@property(nonatomic) NSInteger mediaIndex;
@property(nonatomic, strong) NSTimer *slideTimer;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic, strong) CIContext *ciContext;
@property(nonatomic, strong) UIImpactFeedbackGenerator *hapticGenerator;
@property(nonatomic) BOOL visible;
@property(nonatomic) BOOL handlingVideoBoundary;
@property(nonatomic, strong) NSTimer *environmentTimer;
@property(nonatomic, copy) NSString *environmentSignature;
@property(nonatomic) BOOL environmentChangeScheduled;
@property(nonatomic) BOOL pendingOrientationRefresh;
// Delayed environment convergence is intentionally coalesced. Control
// Center can emit several appearance/orientation notifications during one
// transition; stale delayed blocks only repeat the expensive media reload.
@property(nonatomic) NSUInteger environmentRefreshGeneration;
@property(nonatomic) BOOL expanded;
@property(nonatomic, strong) UIImage *preloadedImage;
@property(nonatomic, strong) AVURLAsset *preloadedAsset;
@property(nonatomic, strong) AVAssetImageGenerator *preloadImageGenerator;
@property(nonatomic, copy) NSString *preloadedFileName;
@property(nonatomic) NSInteger videoBoundaryCount;
@property(nonatomic) NSInteger pendingManualAdvanceOffset;
@property(nonatomic) NSTimeInterval lastRuntimePersistAt;
@property(nonatomic) NSTimeInterval currentVideoDuration;
@property(nonatomic) CGSize adaptiveExpandedSize;
@property(nonatomic, copy) NSString *adaptiveSizeMediaName;
@property(nonatomic, copy) NSArray<NSDictionary *> *pickerItems;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredPickerItems;
@property(nonatomic, strong) UITableViewController *mediaPickerController;
@property(nonatomic, strong) UISearchController *mediaSearchController;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *pickerThumbnailCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingPickerThumbnailCallbacks;
@property(nonatomic) NSUInteger pickerSearchGeneration;
@property(nonatomic, copy) NSString *lastPickerItemsSignature;
@property(nonatomic) BOOL automationOverrideActive;
@property(nonatomic) BOOL hasLoadedPreferences;
@property(nonatomic) BOOL suppressCurrentPersistence;
@property(nonatomic) BOOL didScheduleFirstMountedReload;
@property(nonatomic) NSUInteger mountReloadAttempts;
@property(nonatomic) NSTimeInterval lastPreferencesReloadAt;
@property(nonatomic) NSTimeInterval lastPlayerLayerRecoveryAt;
@property(nonatomic) NSTimeInterval lastVideoStallRecoveryAt;
@property(nonatomic) NSTimeInterval lastObservedPlayerTime;
@property(nonatomic) NSTimeInterval lastVideoProgressAt;
@property(nonatomic) NSUInteger videoStallRecoveryCount;
@property(nonatomic, copy) NSString *videoStallFileName;
@property(nonatomic) NSTimeInterval lastVideoSuspendedAt;
@property(nonatomic) NSUInteger videoFailureRebuildCount;
@property(nonatomic, copy) NSString *videoFailureFileName;
@property(nonatomic, copy) NSString *fallbackAttemptedFileName;
@property(nonatomic) NSUInteger playbackInstallGeneration;
@property(nonatomic, strong) NSTimer *videoWatchdog;
@property(nonatomic) NSTimeInterval lastPresentationRecoveryGeneration;
@property(nonatomic) BOOL didRepairMountedHierarchy;
@property(nonatomic) BOOL reloadScheduled;
@property(nonatomic) BOOL sceneLowPowerCoverActive;
@property(nonatomic) NSUInteger sceneSmartCoverGeneration;
@property(nonatomic) NSTimeInterval mediaPresentationStartedAt;
@property(nonatomic) NSTimeInterval healthPlaybackStartedAt;
@property(nonatomic, copy) NSString *healthPlaybackFileName;
@property(nonatomic) BOOL healthStartRecorded;
@property(nonatomic, copy) NSString *lastStaticAppearanceSignature;
@property(nonatomic) CGRect lastAppearanceBounds;
@property(nonatomic) BOOL hasAppearanceBounds;
@property(nonatomic) BOOL lastAppearanceExpanded;
@property(nonatomic) BOOL hasLaidOutContentFrame;
@property(nonatomic) CGRect lastLaidOutContentFrame;
@property(nonatomic) BOOL hasLaidOutMediaFrame;
@property(nonatomic) CGRect lastLaidOutMediaFrame;
@property(nonatomic, weak) CALayer *lastLaidOutPlayerLayer;
@property(nonatomic, weak) UIView *lastLaidOutNativeView;
@property(nonatomic) BOOL hasLaidOutExpandedPanelFrame;
@property(nonatomic) CGRect lastLaidOutExpandedPanelFrame;
@property(nonatomic) BOOL hasLaidOutExpandedState;
@property(nonatomic) BOOL lastLaidOutExpandedState;
@property(nonatomic, strong) UIButton *resizeButton;
@property(nonatomic, strong) UIPanGestureRecognizer *resizePan;
@property(nonatomic, weak) id moduleOwner;
@property(nonatomic, strong) UILabel *resizeFeedbackLabel;
@property(nonatomic) NSInteger resizeStartWidth;
@property(nonatomic) NSInteger resizeStartHeight;
@property(nonatomic) NSInteger resizePreviewWidth;
@property(nonatomic) NSInteger resizePreviewHeight;
@property(nonatomic) CGRect resizeOriginalFrame;
@property(nonatomic) CGRect resizePreviewFrame;
@property(nonatomic) NSInteger resizePreviewBaseWidth;
@property(nonatomic) NSInteger resizePreviewBaseHeight;
@property(nonatomic) BOOL resizePreviewFrameActive;
@property(nonatomic) BOOL hasObservedGridSize;
@property(nonatomic) NSInteger observedGridWidth;
@property(nonatomic) NSInteger observedGridHeight;
@property(nonatomic) BOOL resizeLayoutUpdateDeferred;
@property(nonatomic) NSUInteger nativePresentationRecoveryGeneration;
@property(nonatomic) BOOL nativePresentationRecoveryArmed;
@property(nonatomic) BOOL expandedContentTransitionActive;
@property(nonatomic) BOOL nativePlayerAttachedForExpandedContent;
// Some iOS builds delay AVPlayerItemStatusReadyToPlay while the item is
// already usable by AVPlayerViewController. After a bounded wait, allow the
// native surface to appear instead of leaving the expanded module blank.
@property(nonatomic) BOOL nativePresentationFallbackVisible;
@property(nonatomic) BOOL hasAppliedNativePresentationFrame;
@property(nonatomic) CGRect lastAppliedNativePresentationFrame;
@property(nonatomic) CGFloat lastAppliedNativePresentationRadius;
@property(nonatomic, weak) UIView *lastAppliedNativePresentationView;
@property(nonatomic, weak) CALayer *lastAppliedNativePresentationPlayerLayer;
@property(nonatomic, copy) AVLayerVideoGravity lastAppliedNativeVideoGravity;
@property(nonatomic, copy) NSString *lastNativePresentationStateSignature;
@property(nonatomic) NSUInteger resizeVisibilityRecoveryGeneration;
@property(nonatomic) NSUInteger resizeLayoutRecoveryGeneration;
- (void)reloadPreferencesAndMedia;
- (void)stopPlayback;
- (BOOL)applyPluginEnabledState;
- (void)convergeMountedPresentation:(NSString *)reason;
- (BOOL)requiresMountedPresentationRecovery;
- (BOOL)repairMountedPresentationHierarchyForFullRecovery:(BOOL)fullRecovery;
- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot;
- (void)scheduleMountedPresentationConvergence:(NSString *)reason;
- (NSArray<NSDictionary *> *)eligibleItems:(NSArray<NSDictionary *> *)catalog;
- (NSArray<NSDictionary *> *)playbackQueueForItems:(NSArray<NSDictionary *> *)items;
- (NSString *)automationSelectionForItems:(NSArray<NSDictionary *> *)items;
- (NSString *)currentEnvironmentSignature;
- (void)environmentDidChange:(NSNotification *)notification;
- (void)scheduleEnvironmentRefresh;
- (void)protectedDataDidBecomeAvailable:(NSNotification *)notification;
- (void)startEnvironmentTimer;
- (void)recoverPlayerLayerSurfaceIfNeededForItem:(AVPlayerItem *)playerItem reason:(NSString *)reason;
- (void)startVideoWatchdogForItem:(AVPlayerItem *)playerItem;
- (void)observeVideoProgressForItem:(AVPlayerItem *)playerItem time:(NSTimeInterval)time;
- (void)recoverVideoPlaybackStallForItem:(AVPlayerItem *)playerItem;
- (BOOL)rebuildVideoAfterExtendedSuspensionIfNeeded;
- (void)handleVideoPlaybackFailureForItem:(AVPlayerItem *)playerItem reason:(NSString *)reason;
- (BOOL)attemptFallbackMediaForFileName:(NSString *)fileName reason:(NSString *)reason;
- (NSInteger)randomMediaIndexExcludingCurrent;
- (void)manualAdvanceBy:(NSInteger)offset;
- (void)commitPendingManualAdvance;
- (void)handleOpacityPan:(UIPanGestureRecognizer *)recognizer;
- (void)installGestureHostIfNeeded;
- (void)handleCompactTap:(UITapGestureRecognizer *)recognizer;
- (void)handleControlCenterTap;
- (void)handleActionLongPress:(UILongPressGestureRecognizer *)recognizer;
- (void)performConfiguredActionForGestureName:(NSString *)gestureName;
- (void)requestExpandedPresentation;
- (void)performHapticFeedback;
- (void)updateExpandedCaption;
- (void)buildExpandedControlsIfNeeded;
- (void)updateExpandedControls;
- (void)expandedModeButtonTapped:(UIButton *)sender;
- (void)expandedPresetButtonTapped:(UIButton *)sender;
- (void)expandedMediaButtonTapped:(UIButton *)sender;
- (void)presentFallbackPickerForFileName:(NSString *)fileName;
- (void)expandedCompositionButtonTapped:(UIButton *)sender;
- (void)setExpandedInteractionEnabled:(BOOL)enabled;
- (void)applyModuleAppearance;
- (void)updateCurrentOpacity:(CGFloat)opacity persist:(BOOL)persist;
- (void)updateCurrentBlur:(CGFloat)blur persist:(BOOL)persist;
- (void)applyBlurIntensity:(CGFloat)blur;
- (void)applyDisplayForItem:(NSDictionary *)item;
- (void)updateNativePlayerPresentation;
- (void)scheduleNativePlayerPresentationRecovery;
- (void)detachNativePlayerForCompactTransition;
- (BOOL)requiresMountedMediaReload;
- (BOOL)requiresMountedPlayerLayerRecovery;
- (void)handleModuleWindowChange:(BOOL)attached;
- (void)resumeVideoPlaybackIfNeeded;
- (void)revealVideoWhenReadyForItem:(AVPlayerItem *)playerItem attempt:(NSUInteger)attempt;
- (void)reloadAfterFirstMountIfNeeded;
- (void)updateAdaptiveExpandedSizeForItem:(NSDictionary *)item;
- (void)preloadNextMedia;
- (void)clearPreloadedNextMedia;
- (void)videoFailed:(NSNotification *)notification;
- (void)videoStalled:(NSNotification *)notification;
- (void)presentMediaSelectionList;
- (void)dismissMediaSelectionList;
- (void)clearMediaSelectionState;
- (void)selectMediaNamed:(NSString *)fileName;
- (void)selectMediaNamed:(NSString *)fileName makeConstant:(BOOL)makeConstant;
- (void)activateSceneLowPowerCoverIfNeeded;
- (void)restoreSceneLowPowerPlaybackIfNeeded;
- (void)generateSceneSmartCoverAtTime:(NSTimeInterval)time;
- (void)recordSuccessfulMediaStartIfNeeded;
- (void)recordActivePlaybackDurationIfNeeded;
- (UIViewController *)presentationHostController;
- (NSArray<NSDictionary *> *)visiblePickerItems;
- (UIImage *)pickerThumbnailForItem:(NSDictionary *)item size:(CGSize)size;
- (void)updateResizeControlVisibility;
- (void)scheduleResizeControlVisibilityRecovery;
- (void)scheduleResizeLayoutRecovery;
- (void)handleResizePan:(UIPanGestureRecognizer *)recognizer;
- (void)showResizeFeedbackForWidth:(NSInteger)width height:(NSInteger)height;
- (void)hideResizeFeedback;
- (void)applyLiveResizePreviewForWidth:(NSInteger)width height:(NSInteger)height;
- (void)applyLiveResizePreviewForTranslation:(CGPoint)translation;
- (void)clearLiveResizePreviewRestoringOriginalFrame:(BOOL)restoreOriginalFrame;
- (void)recordObservedGridSizeWithWidth:(NSInteger)width height:(NSInteger)height;
- (BOOL)isResizeGestureActive;
- (void)handleExternalGridSizeReload;
- (void)requestControlCenterLayoutSizeUpdate;
@end

static void CCBGReloadCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFNotificationName name,
    const void *object,
    CFDictionaryRef userInfo
) {
    CCBG_VIEW_CONTROLLER_CLASS *controller = (__bridge CCBG_VIEW_CONTROLLER_CLASS *)observer;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"reload-notification", @{@"name": (__bridge NSString *)name ?: @""});
    CCBGInvalidatePreferenceReadCache();
    @synchronized (controller) {
        if (controller.reloadScheduled) return;
        controller.reloadScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        CCBGHasCachedRuntimeGridSize = NO;
        CCBGHasCachedCCAsterGridSizes = NO;
        CCBGInvalidateSceneRuntimeCaches();
        controller.reloadScheduled = NO;
        [controller reloadPreferencesAndMedia];
        [controller reloadAfterFirstMountIfNeeded];
        [controller convergeMountedPresentation:@"reload-notification"];
        [controller scheduleMountedPresentationConvergence:@"reload-notification"];
    });
}

static UIColor *CCBGBlendModuleColor(UIColor *baseColor, UIColor *tintColor, CGFloat strength) {
    if (!tintColor) return baseColor;
    strength = MIN(1.0, MAX(0.0, strength));
    CGFloat br = 0, bg = 0, bb = 0, ba = 0, tr = 0, tg = 0, tb = 0, ta = 0;
    if (![baseColor getRed:&br green:&bg blue:&bb alpha:&ba] || ![tintColor getRed:&tr green:&tg blue:&tb alpha:&ta]) return tintColor;
    return [UIColor colorWithRed:br + (tr - br) * strength green:bg + (tg - bg) * strength blue:bb + (tb - bb) * strength alpha:ba];
}

static void CCBGSizeReloadCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFNotificationName name,
    const void *object,
    CFDictionaryRef userInfo
) {
    CCBGHasCachedRuntimeGridSize = NO;
    CCBGLastRuntimeGridReadAt = 0;
    CCBGHasCachedCCAsterGridSizes = NO;
    CCBGLastCCAsterGridReadAt = 0;
    // Size writes can originate in the separate preferences app. Invalidate
    // the SpringBoard-side preference cache before the next drag reads its
    // starting grid, otherwise it can begin from a stale width/height.
    CCBGInvalidatePreferenceReadCache();
    CCBG_VIEW_CONTROLLER_CLASS *controller = (__bridge CCBG_VIEW_CONTROLLER_CLASS *)observer;
    // CCSupport also receives this Darwin notification. Let it invalidate its
    // own size cache first, otherwise it can overwrite our targeted request
    // with the previously cached footprint.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [controller handleExternalGridSizeReload];
    });
}

static void CCBGPresentationRecoveryCallback(
    CFNotificationCenterRef center,
    void *observer,
    CFNotificationName name,
    const void *object,
    CFDictionaryRef userInfo
) {
    CCBG_VIEW_CONTROLLER_CLASS *controller = (__bridge CCBG_VIEW_CONTROLLER_CLASS *)observer;
    NSUInteger generation = controller.convergenceGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != controller.convergenceGeneration || !controller.visible || !controller.view.window ||
            controller.view.window.hidden || controller.view.window.alpha <= 0.01 || !CCBGPluginEnabled()) return;
        controller.didRepairMountedHierarchy = NO;
        if (controller.currentItem) [controller applyDisplayForItem:controller.currentItem];
        [controller convergeMountedPresentation:@"utility-collapse"];
        [controller scheduleMountedPresentationConvergence:@"utility-collapse"];
    });
}

@implementation CCBG_VIEW_CONTROLLER_CLASS

- (void)viewDidLoad {
    [super viewDidLoad];
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"view-did-load", nil);
    self.view.backgroundColor = [UIColor colorWithRed:0.10 green:0.24 blue:0.38 alpha:1.0];
    self.view.clipsToBounds = YES;
    self.view.layer.masksToBounds = YES;
    [self recordObservedGridSizeWithWidth:MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", CCBG_MODULE_SLOT, @(CCBG_DEFAULT_GRID_WIDTH)) integerValue]))
                                   height:MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", CCBG_MODULE_SLOT, @(CCBG_DEFAULT_GRID_HEIGHT)) integerValue]))];
    self.view.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) self.view.layer.cornerCurve = kCACornerCurveContinuous;
    self.view.userInteractionEnabled = YES;
    self.ciContext = [CIContext contextWithOptions:nil];
    self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    self.adaptiveExpandedSize = CCBGConfiguredExpandedMaximumSize();
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.backgroundColor = UIColor.clearColor;
    [self.view addSubview:self.imageView];

    self.dynamicTintView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.dynamicTintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dynamicTintView.userInteractionEnabled = NO;
    self.dynamicTintView.hidden = YES;
    [self.view addSubview:self.dynamicTintView];

    self.blurView = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.blurView.frame = self.view.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurView.userInteractionEnabled = NO;
    [self.view addSubview:self.blurView];
    // Prewarm the material without running a long linear animation on the
    // main thread. The animator remains paused; gaussian blur is applied to
    // the media layers only when the configured intensity changes.
    __weak UIVisualEffectView *weakBlurView = self.blurView;
    self.blurAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:0.22 curve:UIViewAnimationCurveEaseOut animations:^{
        weakBlurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    }];
    [self.blurAnimator startAnimation];
    [self.blurAnimator pauseAnimation];
    self.blurAnimator.fractionComplete = 0.0;

    self.dimView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dimView.backgroundColor = UIColor.blackColor;
    self.dimView.userInteractionEnabled = NO;
    [self.view addSubview:self.dimView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.emptyLabel.text = @"暂无素材";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = UIColor.whiteColor;
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.view addSubview:self.emptyLabel];

    self.captionLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, MAX(0, self.view.bounds.size.height - 48), MAX(0, self.view.bounds.size.width - 24), 36)];
    self.captionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.captionLabel.textAlignment = NSTextAlignmentCenter;
    self.captionLabel.textColor = UIColor.whiteColor;
    self.captionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.captionLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.46];
    self.captionLabel.layer.cornerRadius = 12.0;
    self.captionLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.captionLabel.layer.borderWidth = 0.5;
    self.captionLabel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.captionLabel.clipsToBounds = YES;
    self.captionLabel.hidden = YES;
    [self.view addSubview:self.captionLabel];

    // Create the native player with the module, not during the expanded
    // transition. A controller created mid-transition can miss appearance
    // callbacks after SpringBoard relaunch and only become visible after a
    // later Control Center layout pass.
    self.nativePlayerController = [AVPlayerViewController new];
    self.nativePlayerController.updatesNowPlayingInfoCenter = NO;
    self.nativePlayerController.allowsPictureInPicturePlayback = NO;
    self.nativePlayerController.entersFullScreenWhenPlaybackBegins = NO;
    self.nativePlayerController.exitsFullScreenWhenPlaybackEnds = NO;
    self.nativePlayerController.showsPlaybackControls = YES;
    self.nativePlayerController.view.backgroundColor = UIColor.clearColor;
    self.nativePlayerController.view.clipsToBounds = YES;
    self.nativePlayerController.view.hidden = YES;
    self.nativePlayerController.view.userInteractionEnabled = NO;
    [self addChildViewController:self.nativePlayerController];
    [self.view insertSubview:self.nativePlayerController.view belowSubview:self.captionLabel];
    [self.nativePlayerController didMoveToParentViewController:self];

    [self buildExpandedControlsIfNeeded];

    self.resizeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resizeButton.frame = CGRectMake(MAX(4.0, self.view.bounds.size.width - 40.0), MAX(4.0, self.view.bounds.size.height - 40.0), 36.0, 36.0);
    self.resizeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    self.resizeButton.accessibilityLabel = @"调整模块尺寸";
    self.resizeButton.accessibilityHint = @"拖动以实时预览占格大小";
    self.resizeButton.tintColor = UIColor.whiteColor;
    self.resizeButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.76];
    self.resizeButton.layer.cornerRadius = 12.0;
    self.resizeButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.resizeButton.layer.borderWidth = 0.5;
    self.resizeButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
    self.resizeButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.resizeButton.layer.shadowOpacity = 0.20;
    self.resizeButton.layer.shadowRadius = 6.0;
    self.resizeButton.layer.shadowOffset = CGSizeMake(0, 2);
    UIImageSymbolConfiguration *resizeSymbol = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightSemibold];
    [self.resizeButton setPreferredSymbolConfiguration:resizeSymbol forImageInState:UIControlStateNormal];
    [self.resizeButton setImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] forState:UIControlStateNormal];
    self.resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
    self.resizePan.minimumNumberOfTouches = 1;
    self.resizePan.maximumNumberOfTouches = 1;
    self.resizePan.cancelsTouchesInView = YES;
    self.resizePan.delaysTouchesBegan = NO;
    self.resizePan.delegate = self;
    self.resizeButton.exclusiveTouch = YES;
    [self.resizeButton addGestureRecognizer:self.resizePan];
    [self.view addSubview:self.resizeButton];

    CCBG_JOIN(CCBG_VIEW_CONTROLLER_CLASS, MountProbeView) *mountProbe = [CCBG_JOIN(CCBG_VIEW_CONTROLLER_CLASS, MountProbeView) new];
    mountProbe.userInteractionEnabled = NO;
    __weak typeof(self) weakSelf = self;
    mountProbe.windowChanged = ^(BOOL attached) {
        [weakSelf handleModuleWindowChange:attached];
    };
    [self.view addSubview:mountProbe];

    self.swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleExpandedSwipe:)];
    self.swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeft.cancelsTouchesInView = NO;
    self.swipeLeft.delegate = self;
    self.swipeLeft.enabled = NO;
    [self.view addGestureRecognizer:self.swipeLeft];
    self.swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleExpandedSwipe:)];
    self.swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRight.cancelsTouchesInView = NO;
    self.swipeRight.delegate = self;
    self.swipeRight.enabled = NO;
    [self.view addGestureRecognizer:self.swipeRight];
    self.opacityPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleOpacityPan:)];
    self.opacityPan.maximumNumberOfTouches = 1;
    self.opacityPan.cancelsTouchesInView = NO;
    self.opacityPan.delegate = self;
    self.opacityPan.enabled = NO;
    [self.view addGestureRecognizer:self.opacityPan];
    self.compactTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCompactTap:)];
    self.compactTap.numberOfTapsRequired = 1;
    self.compactTap.cancelsTouchesInView = NO;
    self.compactTap.delegate = self;
    self.compactTap.enabled = YES;
    [self.view addGestureRecognizer:self.compactTap];
    self.doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCompactTap:)];
    self.doubleTap.numberOfTapsRequired = 2;
    self.doubleTap.cancelsTouchesInView = NO;
    self.doubleTap.delegate = self;
    [self.view addGestureRecognizer:self.doubleTap];
    self.tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCompactTap:)];
    self.tripleTap.numberOfTapsRequired = 3;
    self.tripleTap.cancelsTouchesInView = NO;
    self.tripleTap.delegate = self;
    [self.view addGestureRecognizer:self.tripleTap];
    [self.compactTap requireGestureRecognizerToFail:self.doubleTap];
    [self.doubleTap requireGestureRecognizerToFail:self.tripleTap];
    self.actionLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleActionLongPress:)];
    self.actionLongPress.minimumPressDuration = 0.45;
    self.actionLongPress.cancelsTouchesInView = NO;
    self.actionLongPress.delegate = self;
    [self.view addGestureRecognizer:self.actionLongPress];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CCBGReloadCallback,
        (__bridge CFStringRef)CCBGReloadNotificationName,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CCBGSizeReloadCallback,
        (__bridge CFStringRef)CCBGSizeReloadNotificationName,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CCBGPresentationRecoveryCallback,
        (__bridge CFStringRef)CCBGPresentationRecoveryNotificationName,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    for (NSString *notificationName in @[
        @"com.apple.interface-style.changed",
        @"com.apple.springboard.interface-style.changed",
        @"com.apple.backboardd.interface-style.changed",
        @"AppleInterfaceThemeChangedNotification",
        @"AppleInterfaceStyleChangedNotification",
        @"com.apple.UIKit.interfaceStyleChanged",
        @"com.apple.UIKit.userInterfaceStyleChanged",
        @"com.apple.donotdisturb.modeconfiguration.changed",
        @"com.apple.donotdisturb.state.changed",
        @"com.apple.springboard.lockstate",
        @"com.apple.springboard.hasBlankedScreen",
    ]) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            CCBGReloadCallback,
            (__bridge CFStringRef)notificationName,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:UIApplicationSignificantTimeChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                  name:UIApplicationDidBecomeActiveNotification object:nil];
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                  name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                  name:CCBGModuleLayoutOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(protectedDataDidBecomeAvailable:)
                                                 name:UIApplicationProtectedDataDidBecomeAvailable object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    self.visible = YES;
    [self reloadPreferencesAndMedia];
}

- (void)buildExpandedControlsIfNeeded {
    if (self.expandedControlPanel) return;

    self.expandedControlPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.expandedControlPanel.backgroundColor = UIColor.clearColor;
    self.expandedControlPanel.layer.cornerRadius = 18.0;
    self.expandedControlPanel.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedControlPanel.layer.borderWidth = 0.35;
    self.expandedControlPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
    self.expandedControlPanel.layer.masksToBounds = YES;
    self.expandedControlPanel.alpha = 0.0;
    self.expandedControlPanel.hidden = YES;
    self.expandedControlPanel.userInteractionEnabled = YES;
    [self.view addSubview:self.expandedControlPanel];

    self.expandedPanelMaterial = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    self.expandedPanelMaterial.frame = self.expandedControlPanel.bounds;
    self.expandedPanelMaterial.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.expandedPanelMaterial.userInteractionEnabled = NO;
    self.expandedPanelMaterial.alpha = 0.76;
    [self.expandedControlPanel addSubview:self.expandedPanelMaterial];

    self.expandedStateIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"power"]];
    self.expandedStateIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    self.expandedStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.expandedControlPanel addSubview:self.expandedStateIcon];

    self.expandedStateLabel = [UILabel new];
    self.expandedStateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    self.expandedStateLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.expandedStateLabel.adjustsFontSizeToFitWidth = YES;
    self.expandedStateLabel.minimumScaleFactor = 0.78;
    self.expandedStateLabel.numberOfLines = 1;
    self.expandedStateLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.expandedStateLabel.textAlignment = NSTextAlignmentLeft;
    [self.expandedControlPanel addSubview:self.expandedStateLabel];

    NSArray<NSString *> *modeTitles = @[@"顺序", @"随机", @"固定"];
    NSArray<NSNumber *> *modeValues = @[@1, @2, @0];
    NSMutableArray<UIButton *> *modeButtons = [NSMutableArray arrayWithCapacity:modeTitles.count];
    for (NSUInteger index = 0; index < modeTitles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = modeValues[index].integerValue;
        [button setTitle:modeTitles[index] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        button.layer.cornerRadius = 9.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.masksToBounds = YES;
        button.layer.borderWidth = 0.0;
        button.layer.borderColor = UIColor.clearColor.CGColor;
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.74] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(expandedModeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [modeButtons addObject:button];
    }
    self.expandedModeButtons = modeButtons;
    self.expandedModeStack = [[UIStackView alloc] initWithArrangedSubviews:modeButtons];
    self.expandedModeStack.axis = UILayoutConstraintAxisHorizontal;
    self.expandedModeStack.spacing = 3.0;
    self.expandedModeStack.distribution = UIStackViewDistributionFillEqually;
    self.expandedModeStack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
    self.expandedModeStack.layer.cornerRadius = 11.0;
    self.expandedModeStack.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedModeStack.layer.borderWidth = 0.35;
    self.expandedModeStack.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
    self.expandedModeStack.layer.masksToBounds = YES;
    [self.expandedControlPanel addSubview:self.expandedModeStack];

    self.expandedPresetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.expandedPresetName = @"标准";
    [self.expandedPresetButton setTitle:@"视觉" forState:UIControlStateNormal];
    self.expandedPresetButton.accessibilityLabel = @"视觉方案";
    [self.expandedPresetButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.86] forState:UIControlStateNormal];
    self.expandedPresetButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.expandedPresetButton.layer.cornerRadius = 9.0;
    self.expandedPresetButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedPresetButton.layer.masksToBounds = YES;
    self.expandedPresetButton.layer.borderWidth = 0.0;
    self.expandedPresetButton.layer.borderColor = UIColor.clearColor.CGColor;
    self.expandedPresetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.055];
    self.expandedPresetButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.78];
    [self.expandedPresetButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    [self.expandedPresetButton addTarget:self action:@selector(expandedPresetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.expandedPresetButton addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.expandedPresetButton addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.expandedControlPanel addSubview:self.expandedPresetButton];

    self.expandedMediaButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.expandedMediaButton setTitle:@"素材" forState:UIControlStateNormal];
    self.expandedMediaButton.accessibilityLabel = @"选择素材";
    [self.expandedMediaButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92] forState:UIControlStateNormal];
    self.expandedMediaButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.expandedMediaButton.layer.cornerRadius = 9.0;
    self.expandedMediaButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedMediaButton.layer.masksToBounds = YES;
    self.expandedMediaButton.layer.borderWidth = 0.0;
    self.expandedMediaButton.layer.borderColor = UIColor.clearColor.CGColor;
    self.expandedMediaButton.backgroundColor = [UIColor colorWithRed:0.16 green:0.46 blue:0.92 alpha:0.72];
    self.expandedMediaButton.tintColor = UIColor.whiteColor;
    [self.expandedMediaButton setImage:[UIImage systemImageNamed:@"photo.on.rectangle"] forState:UIControlStateNormal];
    [self.expandedMediaButton addTarget:self action:@selector(expandedMediaButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.expandedMediaButton addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.expandedMediaButton addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.expandedControlPanel addSubview:self.expandedMediaButton];

    self.expandedCompositionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.expandedCompositionButton setTitle:@"构图" forState:UIControlStateNormal];
    self.expandedCompositionButton.accessibilityLabel = @"构图方式";
    [self.expandedCompositionButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.86] forState:UIControlStateNormal];
    self.expandedCompositionButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.expandedCompositionButton.layer.cornerRadius = 9.0;
    self.expandedCompositionButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedCompositionButton.layer.masksToBounds = YES;
    self.expandedCompositionButton.layer.borderWidth = 0.0;
    self.expandedCompositionButton.layer.borderColor = UIColor.clearColor.CGColor;
    self.expandedCompositionButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.055];
    self.expandedCompositionButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.78];
    [self.expandedCompositionButton setImage:[UIImage systemImageNamed:@"viewfinder"] forState:UIControlStateNormal];
    [self.expandedCompositionButton addTarget:self action:@selector(expandedCompositionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.expandedCompositionButton addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.expandedCompositionButton addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.expandedControlPanel addSubview:self.expandedCompositionButton];
}

- (void)updateExpandedControls {
    if (!self.expandedControlPanel) return;
    NSInteger mode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));
    NSArray<NSString *> *modeNames = @[@"固定", @"顺序", @"随机"];
    NSString *name = self.currentItem ? CCBGDisplayNameForItem(self.currentItem) : @"暂无素材";
    BOOL showName = [CCBGModulePreference(@"showExpandedCaption", @YES) boolValue];
    NSString *state = [NSString stringWithFormat:@"已开启 · %@%@", modeNames[(NSUInteger)mode], showName && name.length ? [NSString stringWithFormat:@" · %@", name] : @""];
    NSString *presetName = self.expandedPresetName.length ? self.expandedPresetName : @"标准";
    NSArray *compositionNames = @[@"自动", @"完整", @"填充"];
    NSInteger composition = MIN(2, MAX(0, [CCBGModulePreference(@"expandedDisplayMode", @0) integerValue]));
    NSString *controlsSignature = [NSString stringWithFormat:@"%ld|%@|%@|%ld|%@", (long)mode, state, presetName, (long)composition, name];
    BOOL controlsChanged = ![self.lastExpandedControlsSignature isEqualToString:controlsSignature];
    if (![self.lastExpandedStateText isEqualToString:state]) {
        BOOL animateState = self.expandedControlPanel.window && !self.expandedControlPanel.hidden &&
            self.expandedControlPanel.alpha > 0.01 && !UIAccessibilityIsReduceMotionEnabled();
        if (animateState) {
            [UIView transitionWithView:self.expandedStateLabel
                              duration:0.14
                               options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                            animations:^{ self.expandedStateLabel.text = state; }
                            completion:nil];
        } else {
            self.expandedStateLabel.text = state;
        }
        self.lastExpandedStateText = state;
    }
    if (controlsChanged) {
        [UIView performWithoutAnimation:^{
            for (UIButton *button in self.expandedModeButtons) {
                BOOL selected = button.tag == mode;
                button.backgroundColor = selected ? [UIColor colorWithRed:0.16 green:0.46 blue:0.92 alpha:0.78] : UIColor.clearColor;
                [button setTitleColor:selected ? UIColor.whiteColor : [UIColor colorWithWhite:1.0 alpha:0.70] forState:UIControlStateNormal];
                button.layer.borderWidth = selected ? 0.35 : 0.0;
                button.layer.borderColor = selected ? [UIColor colorWithWhite:1.0 alpha:0.22].CGColor : UIColor.clearColor.CGColor;
            }
        }];
        [self.expandedPresetButton setAccessibilityValue:presetName];
        [self.expandedCompositionButton setAccessibilityValue:compositionNames[(NSUInteger)composition]];
        [self.expandedMediaButton setAccessibilityValue:name.length ? name : @"暂无素材"];
        self.lastExpandedControlsSignature = controlsSignature;
    }
}

- (void)expandedControlTouchDown:(UIButton *)button {
    if (!button || UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.08
                     delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         button.transform = CGAffineTransformMakeScale(0.965, 0.965);
                         button.alpha = 0.90;
                     }
                     completion:nil];
}

- (void)expandedControlTouchUp:(UIButton *)button {
    if (!button) return;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.14
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         button.transform = CGAffineTransformIdentity;
                         button.alpha = 1.0;
                     }
                     completion:nil];
}

- (void)expandedModeButtonTapped:(UIButton *)sender {
    if (!self.expanded || !sender) return;
    NSInteger mode = MIN(2, MAX(0, sender.tag));
    NSInteger currentMode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));
    if (mode == currentMode) return;
    NSMutableDictionary *changes = [@{ @"playbackMode": @(mode) } mutableCopy];
    if (self.currentItem[@"fileName"]) {
        changes[mode == 0 ? @"selectedMedia" : @"currentMedia"] = self.currentItem[@"fileName"];
    }
    if (mode != 0) changes[@"slideshowEnabled"] = @YES;
    NSMutableDictionary *scopedChanges = [NSMutableDictionary dictionary];
    for (NSString *key in changes) scopedChanges[CCBGPreferenceKeyForModule(key, CCBG_MODULE_SLOT)] = changes[key];
    CCBGApplyQuickConfigurationChanges(scopedChanges, @"修改展开播放方式");
    CCBGSetCachedModulePreference(@"playbackMode", @(mode));
    if (mode != 0) CCBGSetCachedModulePreference(@"slideshowEnabled", @YES);
    if (self.currentItem[@"fileName"]) CCBGSetCachedModulePreference(mode == 0 ? @"selectedMedia" : @"currentMedia", self.currentItem[@"fileName"]);
    [self updateExpandedControls];
    [self performHapticFeedback];
}

- (void)expandedMediaButtonTapped:(UIButton *)sender {
    if (!self.expanded) return;
    [self performHapticFeedback];
    UIViewController *host = [self presentationHostController];
    if (!host || !host.view.window) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"素材快捷操作" message:@"最近和收藏素材会直接应用到当前模块。全部素材可继续搜索。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSInteger mode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));
    BOOL makeConstant = mode == 0;
    __weak typeof(self) weakSelf = self;
    NSArray *recentNames = CCBGModulePreference(@"recentMedia", @[]);
    NSMutableArray *recent = [NSMutableArray array];
    for (id rawName in recentNames) {
        if (![rawName isKindOfClass:NSString.class] || ![rawName length]) continue;
        NSDictionary *item = CCBGMediaItemNamed(self.mediaItems, rawName);
        if (!item || !CCBGMediaItemIsCurrentlyEligible(item) || [recent containsObject:rawName]) continue;
        [recent addObject:rawName];
        if (recent.count >= 5) break;
    }
    for (NSString *name in recent) {
        NSDictionary *item = CCBGMediaItemNamed(self.mediaItems, name);
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"最近：%@", CCBGDisplayNameForItem(item)] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self selectMediaNamed:name makeConstant:makeConstant];
        }]];
    }
    NSMutableArray *favorites = [NSMutableArray array];
    for (NSDictionary *item in self.mediaItems) if ([item[@"favorite"] boolValue] && CCBGMediaItemIsCurrentlyEligible(item)) {
        NSString *name = item[@"fileName"];
        if (name.length && ![favorites containsObject:name]) [favorites addObject:name];
        if (favorites.count >= 5) break;
    }
    for (NSString *name in favorites) {
        NSDictionary *item = CCBGMediaItemNamed(self.mediaItems, name);
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"收藏：%@", CCBGDisplayNameForItem(item)] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self selectMediaNamed:name makeConstant:makeConstant];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"全部素材…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self presentMediaSelectionList];
    }]];
    NSString *currentName = self.currentItem[@"fileName"];
    if (currentName.length) {
        [menu addAction:[UIAlertAction actionWithTitle:@"将当前素材设为失败备用" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self presentFallbackPickerForFileName:currentName];
        }]];
        [menu addAction:[UIAlertAction actionWithTitle:@"清除当前素材备用链" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NSMutableDictionary *chains = [CCBGModulePreference(@"fallbackMediaChains", @{}) mutableCopy] ?: [NSMutableDictionary dictionary];
            [chains removeObjectForKey:currentName];
            CCBGApplyQuickConfigurationChanges(@{CCBGPreferenceKeyForModule(@"fallbackMediaChains", CCBG_MODULE_SLOT): chains}, @"清除备用素材链");
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"撤销最近修改" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        NSString *title = nil;
        if (CCBGUndoLastQuickConfiguration(&title)) {
            [self reloadPreferencesAndMedia];
            [self updateExpandedControls];
            [self applyModuleAppearance];
        }
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.expandedMediaButton;
    menu.popoverPresentationController.sourceRect = self.expandedMediaButton.bounds;
    [host presentViewController:menu animated:YES completion:nil];
}

- (void)presentFallbackPickerForFileName:(NSString *)fileName {
    if (!fileName.length) return;
    UIViewController *host = [self presentationHostController];
    if (!host || !host.view.window) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"选择备用素材" message:@"当前素材解码失败时会自动切换到所选素材。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSUInteger candidateCount = 0;
    for (NSDictionary *item in self.mediaItems) {
        NSString *candidate = item[@"fileName"];
        if (!candidate.length || [candidate isEqualToString:fileName] || !CCBGMediaItemIsCurrentlyEligible(item)) continue;
        [menu addAction:[UIAlertAction actionWithTitle:CCBGDisplayNameForItem(item) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSMutableDictionary *chains = [CCBGModulePreference(@"fallbackMediaChains", @{}) mutableCopy] ?: [NSMutableDictionary dictionary];
            chains[fileName] = @[candidate];
            CCBGApplyQuickConfigurationChanges(@{CCBGPreferenceKeyForModule(@"fallbackMediaChains", CCBG_MODULE_SLOT): chains}, @"设置失败备用素材");
        }]];
        if (++candidateCount >= 12) break;
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.expandedMediaButton;
    menu.popoverPresentationController.sourceRect = self.expandedMediaButton.bounds;
    [host presentViewController:menu animated:YES completion:nil];
}

- (void)expandedCompositionButtonTapped:(UIButton *)sender {
    if (!self.expanded) return;
    UIViewController *host = [self presentationHostController];
    if (!host || !host.view.window) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"展开构图" message:@"自动按素材比例完整显示；填充会裁切画面。" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSArray *titles = @[@"自动（推荐）", @"完整（不裁切）", @"填充（裁切）"];
    for (NSUInteger index = 0; index < titles.count; index++) {
        [menu addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            CCBGApplyQuickConfigurationChanges(@{CCBGPreferenceKeyForModule(@"expandedDisplayMode", CCBG_MODULE_SLOT): @(index)}, @"修改展开构图");
            [self updateExpandedControls];
            [self applyDisplayForItem:self.currentItem];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = sender;
    menu.popoverPresentationController.sourceRect = sender.bounds;
    [host presentViewController:menu animated:YES completion:nil];
}

- (void)expandedPresetButtonTapped:(UIButton *)sender {
    if (!self.expanded) return;
    NSArray<NSDictionary *> *presets = CCBGVisualStylePresets();
    UIViewController *host = [self presentationHostController];
    if (!host || !host.view.window) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"视觉方案" message:@"视觉方案只改变当前模块的透明度、模糊、圆角和边框，不会改变素材或播放方式。" preferredStyle:UIAlertControllerStyleActionSheet];
    if (!presets.count) {
        [menu addAction:[UIAlertAction actionWithTitle:@"暂无视觉方案，请先在 App 中创建" style:UIAlertActionStyleDefault handler:nil]];
    } else {
        __weak typeof(self) weakSelf = self;
        for (NSDictionary *preset in presets) {
            NSString *presetID = preset[@"id"];
            NSString *rawPresetName = [preset[@"name"] isKindOfClass:NSString.class] ? preset[@"name"] : @"";
            NSString *presetName = rawPresetName.length && ![rawPresetName stringByTrimmingCharactersInSet:NSCharacterSet.decimalDigitCharacterSet].length ? [NSString stringWithFormat:@"方案 %@", rawPresetName] : (rawPresetName.length ? rawPresetName : @"未命名方案");
            NSDictionary *values = [preset[@"values"] isKindOfClass:NSDictionary.class] ? preset[@"values"] : @{};
            NSInteger opacity = lround(MIN(1.0, MAX(0.05, [values[@"moduleOpacity"] doubleValue])) * 100.0);
            NSInteger blur = lround(MIN(1.0, MAX(0.0, [values[@"moduleBlurIntensity"] doubleValue])) * 100.0);
            NSInteger radius = lround(MIN(40.0, MAX(0.0, [values[@"moduleCornerRadius"] doubleValue])));
            NSString *actionTitle = [NSString stringWithFormat:@"%@  ·  透明 %ld%%  ·  模糊 %ld%%  ·  圆角 %ld", presetName, (long)opacity, (long)blur, (long)radius];
            [menu addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || !CCBGApplyVisualStylePreset(presetID, CCBG_MODULE_SLOT)) return;
                self.expandedPresetName = presetName;
                [self updateExpandedControls];
                [self applyModuleAppearance];
                [self updateExpandedCaption];
            }]];
        }
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.expandedPresetButton;
    menu.popoverPresentationController.sourceRect = self.expandedPresetButton.bounds;
    [host presentViewController:menu animated:YES completion:nil];
}

- (BOOL)applyPluginEnabledState {
    if ([CCBGModuleGlobalPreference(@"pluginEnabled", @YES) boolValue]) return YES;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"plugin-disabled", nil);
    self.visible = NO;
    [self stopPlayback];
    self.view.hidden = YES;
    self.view.alpha = 0.0;
    self.emptyLabel.hidden = YES;
    return NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"view-will-appear", @{@"window": @(self.view.window != nil)});
    if (![self applyPluginEnabledState]) return;
    self.visible = YES;
    self.mountReloadAttempts = 0;
    self.didScheduleFirstMountedReload = NO;
    [self setExpandedInteractionEnabled:NO];
    if ([self requiresMountedMediaReload] || NSDate.date.timeIntervalSince1970 - self.lastPreferencesReloadAt > 0.35) {
        [self reloadPreferencesAndMedia];
    }
    if (![self rebuildVideoAfterExtendedSuspensionIfNeeded] && self.player && CCBGIsVideoName(self.currentItem[@"fileName"])) {
        [self resumeVideoPlaybackIfNeeded];
    }
    NSInteger mode = [CCBGModulePreference(@"playbackMode", @0) integerValue];
    if (mode != 0 && !self.automationOverrideActive && [CCBGModulePreference(@"randomOnOpen", @NO) boolValue] && self.mediaItems.count > 1) {
        self.mediaIndex = [self randomMediaIndexExcludingCurrent];
        self.currentItem = self.mediaItems[self.mediaIndex];
        self.suppressCurrentPersistence = NO;
        [self showCurrentMediaWithTransition:NO];
    }
    [self startEnvironmentTimer];
    [self convergeMountedPresentation:@"view-will-appear"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"view-did-appear", @{@"window": @(self.view.window != nil)});
    if (![self applyPluginEnabledState]) return;
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    [self reloadAfterFirstMountIfNeeded];
    [self resumeVideoPlaybackIfNeeded];
    [self convergeMountedPresentation:@"view-did-appear"];
    [self scheduleMountedPresentationConvergence:@"view-did-appear"];
}

- (void)handleModuleWindowChange:(BOOL)attached {
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"window-change", @{@"attached": @(attached)});
    if (!attached) return;
    NSUInteger generation = self.convergenceGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.convergenceGeneration || !self.view.window) return;
        if (![self applyPluginEnabledState]) return;
        self.visible = YES;
        self.view.hidden = NO;
        self.view.alpha = 1.0;
        self.mountReloadAttempts = 0;
        self.didScheduleFirstMountedReload = NO;
        [self reloadAfterFirstMountIfNeeded];
        [self resumeVideoPlaybackIfNeeded];
        [self convergeMountedPresentation:@"window-change"];
        NSArray<NSNumber *> *delays = @[@0.05, @0.20, @0.60];
        for (NSNumber *delay in delays) {
            __weak typeof(self) delayedWeakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!delayedWeakSelf || generation != delayedWeakSelf.convergenceGeneration ||
                    ![delayedWeakSelf requiresMountedPresentationRecovery]) return;
                [delayedWeakSelf convergeMountedPresentation:@"window-change-delayed"];
            });
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Delayed convergence blocks from the previous presentation must never
    // resurrect a module while Control Center is closing.
    self.convergenceGeneration += 1;
    self.convergenceSchedulePending = NO;
    self.lastConvergenceScheduleReason = nil;
    [self clearLiveResizePreviewRestoringOriginalFrame:YES];
    self.visible = NO;
    self.didScheduleFirstMountedReload = NO;
    self.mountReloadAttempts = 0;
    [self setExpandedInteractionEnabled:NO];
    self.pendingManualAdvanceOffset = 0;
    [self clearPreloadedNextMedia];
    [self.slideTimer invalidate];
    self.slideTimer = nil;
    [self.environmentTimer invalidate];
    [self.videoWatchdog invalidate];
    self.environmentTimer = nil;
    [self recordActivePlaybackDurationIfNeeded];
    [self.player pause];
    if (CCBGIsVideoName(self.currentItem[@"fileName"])) self.lastVideoSuspendedAt = NSProcessInfo.processInfo.systemUptime;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    CCBGInvalidateSceneRuntimeCaches();
    [self environmentDidChange:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        [self environmentDidChange:nil];
    }];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        NULL,
        NULL
    );
    [UIDevice.currentDevice endGeneratingDeviceOrientationNotifications];
    [self.slideTimer invalidate];
    [self.environmentTimer invalidate];
    [self.blurAnimator stopAnimation:YES];
    for (UIGestureRecognizer *recognizer in @[
        self.swipeLeft, self.swipeRight, self.opacityPan, self.compactTap,
        self.doubleTap, self.tripleTap, self.actionLongPress
    ]) {
        [self.gestureHostView removeGestureRecognizer:recognizer];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopPlayback];
    [self.playerLayer removeFromSuperlayer];
}

- (BOOL)_canShowWhileLocked { return YES; }
- (BOOL)providesOwnPlatter { return YES; }
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation {
    CCUILayoutSize size = {};
    if (CCBGReadCCAsterGridSize(self, &size)) {
        BOOL landscape = orientation == 1 || orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
        return landscape ? (CCUILayoutSize){size.height, size.width} : size;
    }
    return CCBGRuntimeModuleSize(orientation);
}
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return self.adaptiveExpandedSize.width ?: CCBGConfiguredExpandedMaximumSize().width; }
- (CGFloat)preferredExpandedContentHeight {
    CGSize configured = CCBGConfiguredExpandedMaximumSize();
    CGFloat height = self.adaptiveExpandedSize.height ?: configured.height;
    return MAX(MIN(configured.height, 300.0), height);
}
- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    // CCSupport owns the expanded frame. Never carry the temporary compact
    // drag frame into that transition.
    self.expandedContentTransitionActive = YES;
    if (expanded) {
        [self clearLiveResizePreviewRestoringOriginalFrame:YES];
        // CCSupport has not installed the expanded bounds yet. Keep the
        // compact player authoritative until didTransition/layout gives us
        // the final container geometry.
        [self setExpandedInteractionEnabled:expanded];
        [self updateNativePlayerPresentation];
    } else {
        // Hand the current frame back to the compact layer before the host
        // starts shrinking. Leaving the native controller in the hierarchy
        // makes its old expanded frame linger during the collapse animation.
        [self detachNativePlayerForCompactTransition];
        [self setExpandedInteractionEnabled:expanded];
    }
    // On a freshly rebuilt SpringBoard controller the matching didTransition
    // callback can arrive late or be skipped while CCSupport mounts the
    // expanded container. Arm recovery at the first transition boundary too.
    if (expanded) [self scheduleNativePlayerPresentationRecovery];
}

- (void)didTransitionToExpandedContentMode:(BOOL)expanded {
    self.expandedContentTransitionActive = NO;
    // The host has committed the target state now. Clear the guard before
    // updating the module so the native transport controls are attached in
    // this pass instead of waiting for the recovery timer.
    [self setExpandedInteractionEnabled:expanded];
    if (expanded && self.currentItem) [self updateAdaptiveExpandedSizeForItem:self.currentItem];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.expanded != expanded) return;
        [self.view setNeedsLayout];
        // The compact host is still being animated by CCSupport here. A
        // synchronous layout pass on collapse competes with that animation
        // and causes a visible hitch. The native player was already hidden in
        // willTransitionToExpandedContentMode:, so defer its full geometry
        // update to the next expand/recovery boundary.
        if (!expanded) return;
        [self.view layoutIfNeeded];
        [self updateNativePlayerPresentation];
    });
    if (expanded) {
        [self scheduleNativePlayerPresentationRecovery];
    } else {
        // Invalidate every pending expand recovery.  Clearing the armed bit
        // is important: the next expand must be allowed to arm a fresh
        // recovery wave even when this collapse skipped a callback.
        self.nativePresentationRecoveryGeneration += 1;
        self.nativePresentationRecoveryArmed = NO;
        self.nativePresentationFallbackVisible = NO;
    }
    if (!expanded && self.resizeLayoutUpdateDeferred) {
        self.resizeLayoutUpdateDeferred = NO;
        // The system has restored the compact host at this point, so applying
        // the pending grid change cannot stretch the expanded presentation.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.expanded) [self requestControlCenterLayoutSizeUpdate];
        });
    }
}

- (void)handleExpandedSwipe:(UISwipeGestureRecognizer *)recognizer {
    if (!self.expanded || recognizer.state != UIGestureRecognizerStateEnded) return;
    if ([CCBGModulePreference(@"playbackMode", @0) integerValue] == 0) return;
    if ([CCBGModulePreference(@"hapticFeedbackEnabled", @YES) boolValue]) {
        [self performHapticFeedback];
    }
    if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft) [self manualAdvanceBy:1];
    else if (recognizer.direction == UISwipeGestureRecognizerDirectionRight) [self manualAdvanceBy:-1];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.resizePan) {
        return !self.expanded && !CCBGIsCCAsterEditModeActive(self.view) && [CCBGModulePreference(@"controlCenterResizeEnabled", @NO) boolValue];
    }
    if (gestureRecognizer == self.compactTap || gestureRecognizer == self.doubleTap || gestureRecognizer == self.tripleTap || gestureRecognizer == self.actionLongPress) return YES;
    if (gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight) {
        return self.expanded && [CCBGModulePreference(@"playbackMode", @0) integerValue] != 0;
    }
    if (gestureRecognizer != self.opacityPan || !self.expanded || !self.currentItem) return gestureRecognizer != self.opacityPan;
    CGPoint velocity = [self.opacityPan velocityInView:self.view];
    return fabs(velocity.y) > fabs(velocity.x) * 1.15;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.resizePan || otherGestureRecognizer == self.resizePan) return YES;
    BOOL ours = gestureRecognizer == self.compactTap || gestureRecognizer == self.doubleTap || gestureRecognizer == self.tripleTap ||
        gestureRecognizer == self.actionLongPress || gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight || gestureRecognizer == self.opacityPan;
    BOOL otherIsOurs = otherGestureRecognizer == self.compactTap || otherGestureRecognizer == self.doubleTap || otherGestureRecognizer == self.tripleTap ||
        otherGestureRecognizer == self.actionLongPress || otherGestureRecognizer == self.swipeLeft || otherGestureRecognizer == self.swipeRight || otherGestureRecognizer == self.opacityPan;
    if (ours || otherIsOurs) return YES;
    UIView *nativeView = self.nativePlayerController.view;
    BOOL nativePair = nativeView &&
        ((gestureRecognizer.view == nativeView || [gestureRecognizer.view isDescendantOfView:nativeView]) ||
         (otherGestureRecognizer.view == nativeView || [otherGestureRecognizer.view isDescendantOfView:nativeView]));
    BOOL moduleGesture = gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight || gestureRecognizer == self.opacityPan ||
        otherGestureRecognizer == self.swipeLeft || otherGestureRecognizer == self.swipeRight || otherGestureRecognizer == self.opacityPan;
    return nativePair && moduleGesture;
}

- (void)handleCompactTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;
    if (!self.expanded && NSDate.date.timeIntervalSince1970 - self.lastProtocolTapAt < 0.5) return;
    NSString *gestureName = recognizer.numberOfTapsRequired == 3 ? @"TripleTap" : recognizer.numberOfTapsRequired == 2 ? @"DoubleTap" : @"SingleTap";
    [self performConfiguredActionForGestureName:gestureName];
}

- (void)handleControlCenterTap {
    self.lastProtocolTapAt = NSDate.date.timeIntervalSince1970;
    self.controlCenterTapCount = MIN((NSUInteger)3, self.controlCenterTapCount + 1);
    NSUInteger generation = ++self.controlCenterTapGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.controlCenterTapGeneration) return;
        NSUInteger count = self.controlCenterTapCount;
        self.controlCenterTapCount = 0;
        NSString *gestureName = count >= 3 ? @"TripleTap" : count == 2 ? @"DoubleTap" : @"SingleTap";
        [self performConfiguredActionForGestureName:gestureName];
    });
}

- (void)handleActionLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) [self performConfiguredActionForGestureName:@"LongPress"];
}

- (void)performConfiguredActionForGestureName:(NSString *)gestureName {
    NSString *prefix = self.expanded ? @"expanded" : @"compact";
    NSString *key = [prefix stringByAppendingString:gestureName];
    NSInteger fallback = [gestureName isEqualToString:@"SingleTap"] && !self.expanded ? 1 : [gestureName isEqualToString:@"LongPress"] && !self.expanded ? 2 : 0;
    NSInteger action = MIN(4, MAX(0, [CCBGModulePreference([key stringByAppendingString:@"Action"], @(fallback)) integerValue]));
    if (action == 1) [self presentMediaSelectionList];
    else if (action == 2) [self requestExpandedPresentation];
    else if (action == 3) [self manualAdvanceBy:-1];
    else if (action == 4) [self manualAdvanceBy:1];
    BOOL relayed = NO;
    if ([gestureName isEqualToString:@"DoubleTap"]) relayed = CCBGSceneDirectorRelayFromSlotInContext(CCBG_MODULE_SLOT, self.currentItem[@"fileName"] ?: @"", CCBGSceneContextForModule(self.view));
    if (action != 0 || relayed) [self performHapticFeedback];
}

- (void)requestExpandedPresentation {
    if (self.expanded) return;
    NSArray<NSString *> *selectorNames = @[@"expandModule", @"_expandModule", @"requestExpandModule", @"beginTransitionToExpandedContentModule", @"_beginTransitionToExpandedContentModule"];
    NSArray<NSString *> *booleanSelectorNames = @[@"setExpanded:", @"_setExpanded:", @"setExpandedContentModule:"];
    UIResponder *responder = self.view;
    while (responder) {
        for (NSString *selectorName in selectorNames) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([responder respondsToSelector:selector]) {
                ((void (*)(id, SEL))objc_msgSend)(responder, selector);
                return;
            }
        }
        for (NSString *selectorName in booleanSelectorNames) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([responder respondsToSelector:selector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(responder, selector, YES);
                return;
            }
        }
        responder = responder.nextResponder;
    }
}

- (void)performHapticFeedback {
    if (![CCBGModulePreference(@"hapticFeedbackEnabled", @YES) boolValue]) return;
    if (!self.hapticGenerator) self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [self.hapticGenerator prepare];
    [self.hapticGenerator impactOccurredWithIntensity:0.85];
    [self.hapticGenerator prepare];
}

- (void)updateResizeControlVisibility {
    BOOL enabled = [CCBGModulePreference(@"controlCenterResizeEnabled", @NO) boolValue];
    BOOL canShow = enabled && !self.expanded && !CCBGIsCCAsterEditModeActive(self.view) && self.view.window && !self.view.hidden && self.view.alpha >= 0.01;
    self.resizeButton.hidden = !canShow;
    self.resizeButton.userInteractionEnabled = canShow;
    if (canShow && self.view.subviews.lastObject != self.resizeButton) [self.view bringSubviewToFront:self.resizeButton];
    if (!canShow) [self hideResizeFeedback];
}

- (void)scheduleResizeControlVisibilityRecovery {
    NSUInteger generation = ++self.resizeVisibilityRecoveryGeneration;
    NSArray<NSNumber *> *delays = @[@0.0, @0.12, @0.30, @0.60];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayValue in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.resizeVisibilityRecoveryGeneration) return;
            [self updateResizeControlVisibility];
        });
    }
}

- (void)scheduleResizeLayoutRecovery {
    NSUInteger generation = ++self.resizeLayoutRecoveryGeneration;
    NSArray<NSNumber *> *delays = @[@0.04, @0.16, @0.36, @0.70];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayValue in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.resizeLayoutRecoveryGeneration || self.expanded || [self isResizeGestureActive]) return;
            // CCSupport and CCAster may consume the first request while their
            // current page is still inside an interactive layout transaction.
            // Repeating only the size signal lets the whole page settle without
            // rebuilding any video players.
            CCBGHasCachedRuntimeGridSize = NO;
            CCBGHasCachedCCAsterGridSizes = NO;
            CCBGLastRuntimeGridReadAt = 0;
            CCBGLastCCAsterGridReadAt = 0;
            CCBGRequestControlCenterSizeReload();
            [self requestControlCenterLayoutSizeUpdate];
        });
    }
}

- (void)showResizeFeedbackForWidth:(NSInteger)width height:(NSInteger)height {
    if (!self.resizeFeedbackLabel) {
        self.resizeFeedbackLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 72.0, 28.0)];
        self.resizeFeedbackLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        self.resizeFeedbackLabel.textAlignment = NSTextAlignmentCenter;
        self.resizeFeedbackLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
        self.resizeFeedbackLabel.textColor = UIColor.whiteColor;
        self.resizeFeedbackLabel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.82];
        self.resizeFeedbackLabel.layer.cornerRadius = 14.0;
        self.resizeFeedbackLabel.layer.cornerCurve = kCACornerCurveContinuous;
        self.resizeFeedbackLabel.layer.borderWidth = 0.5;
        self.resizeFeedbackLabel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.resizeFeedbackLabel.layer.shadowColor = UIColor.blackColor.CGColor;
        self.resizeFeedbackLabel.layer.shadowOpacity = 0.22;
        self.resizeFeedbackLabel.layer.shadowRadius = 8.0;
        self.resizeFeedbackLabel.layer.shadowOffset = CGSizeMake(0, 2);
        self.resizeFeedbackLabel.hidden = YES;
        [self.view addSubview:self.resizeFeedbackLabel];
    }
    self.resizeFeedbackLabel.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    self.resizeFeedbackLabel.text = [NSString stringWithFormat:@"%ld × %ld", (long)width, (long)height];
    BOOL firstAppearance = self.resizeFeedbackLabel.hidden || self.resizeFeedbackLabel.alpha < 0.01;
    self.resizeFeedbackLabel.alpha = firstAppearance ? 0.0 : 1.0;
    self.resizeFeedbackLabel.transform = firstAppearance && !UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    self.resizeFeedbackLabel.hidden = NO;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.12 : 0.18
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.resizeFeedbackLabel.alpha = 1.0;
        self.resizeFeedbackLabel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideResizeFeedback {
    UILabel *label = self.resizeFeedbackLabel;
    if (!label) return;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.16
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        label.alpha = 0.0;
        label.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        if (self.resizeFeedbackLabel != label) return;
        [label removeFromSuperview];
        self.resizeFeedbackLabel = nil;
    }];
}

- (void)recordObservedGridSizeWithWidth:(NSInteger)width height:(NSInteger)height {
    self.observedGridWidth = MIN(4, MAX(1, width));
    self.observedGridHeight = MIN(4, MAX(1, height));
    self.hasObservedGridSize = YES;
}

- (BOOL)isResizeGestureActive {
    UIGestureRecognizerState state = self.resizePan.state;
    return state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged;
}

- (void)handleExternalGridSizeReload {
    if (!self.isViewLoaded) return;
    NSInteger width = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", CCBG_MODULE_SLOT, @(CCBG_DEFAULT_GRID_WIDTH)) integerValue]));
    NSInteger height = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", CCBG_MODULE_SLOT, @(CCBG_DEFAULT_GRID_HEIGHT)) integerValue]));
    BOOL changed = !self.hasObservedGridSize || self.observedGridWidth != width || self.observedGridHeight != height;
    [self recordObservedGridSizeWithWidth:width height:height];
    CCBGSetCachedModulePreference(@"gridWidth", @(width));
    CCBGSetCachedModulePreference(@"gridHeight", @(height));
    if (!changed) return;
    // A compact-grid update must never resize the system-owned expanded
    // presentation. Remember it and apply it only after the module closes.
    if (self.expanded) {
        self.resizeLayoutUpdateDeferred = YES;
        return;
    }
    if ([self isResizeGestureActive]) {
        self.resizeLayoutUpdateDeferred = YES;
        return;
    }
    [self requestControlCenterLayoutSizeUpdate];
    [self scheduleResizeControlVisibilityRecovery];
}

- (void)requestControlCenterLayoutSizeUpdate {
    id owner = self.moduleOwner;
    NSMutableArray *sources = [NSMutableArray arrayWithObjects:self, nil];
    if (owner) [sources insertObject:owner atIndex:0];
    for (UIResponder *responder = self.view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]) [sources addObject:responder];
    }
    for (id source in sources) {
        id context = nil;
        @try {
            context = [source valueForKey:@"contentModuleContext"];
            if (!context) {
                id module = [source valueForKey:@"module"];
                context = [module valueForKey:@"contentModuleContext"];
            }
        } @catch (__unused NSException *exception) {}
        SEL selector = NSSelectorFromString(@"requestLayoutSizeUpdate");
        if (context && [context respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(context, selector);
        }
    }
    // CCAster keeps a separate in-process grid and its preference callback
    // only reloads settings. Ask its collection controller for the same layout
    // pass that its own resize handle uses, otherwise sibling modules keep the
    // old frames and remain underneath the resized module.
    UIViewController *overlay = self;
    while (overlay.parentViewController) overlay = overlay.parentViewController;
    Class coordinatorClass = NSClassFromString(@"CCAsterCoordinator");
    SEL sharedSelector = NSSelectorFromString(@"shared");
    SEL collectionSelector = NSSelectorFromString(@"moduleCollectionControllerInOverlay:");
    id coordinator = coordinatorClass && [coordinatorClass respondsToSelector:sharedSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(coordinatorClass, sharedSelector) : nil;
    UIViewController *collection = coordinator && [coordinator respondsToSelector:collectionSelector]
        ? ((id (*)(id, SEL, id))objc_msgSend)(coordinator, collectionSelector, overlay) : nil;
    // The context request updates CCSupport's logical grid. Defer the page
    // layout pass one run-loop turn so CCAster can finish its preference
    // reload before UIKit measures every sibling again.
    __weak UIViewController *weakOverlay = overlay;
    __weak UIViewController *weakCollection = collection;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *page = weakOverlay;
        UIViewController *modules = weakCollection;
        [modules.view setNeedsLayout];
        [page.view setNeedsLayout];
        UIView *host = self.view.superview;
        UIView *topHost = host;
        for (NSUInteger depth = 0; host && depth < 8; depth++, host = host.superview) {
            [host setNeedsLayout];
            topHost = host;
        }
        // One layout pass per owning tree is enough. The previous loop forced
        // every ancestor to synchronously lay out, which made a resize drag
        // compete with video compositing and sibling-module placement.
        [modules.view layoutIfNeeded];
        [page.view layoutIfNeeded];
        host = self.view.superview;
        [host layoutIfNeeded];
        [topHost layoutIfNeeded];
    });
}

- (void)applyLiveResizePreviewForWidth:(NSInteger)width height:(NSInteger)height {
    if (self.expanded || CGRectIsEmpty(self.resizeOriginalFrame)) return;
    BOOL landscape = CCBGCurrentInterfaceIsLandscape(self.view);
    NSInteger baseWidth = landscape ? self.resizePreviewBaseHeight : self.resizePreviewBaseWidth;
    NSInteger baseHeight = landscape ? self.resizePreviewBaseWidth : self.resizePreviewBaseHeight;
    NSInteger targetWidth = landscape ? height : width;
    NSInteger targetHeight = landscape ? width : height;
    if (baseWidth < 1 || baseHeight < 1) return;
    CGRect preview = self.resizeOriginalFrame;
    CGFloat widthUnit = preview.size.width / (CGFloat)baseWidth;
    CGFloat heightUnit = preview.size.height / (CGFloat)baseHeight;
    preview.size.width = MAX(widthUnit, round(widthUnit * MAX(1, targetWidth)));
    preview.size.height = MAX(heightUnit, round(heightUnit * MAX(1, targetHeight)));
    self.resizePreviewFrame = preview;
    self.resizePreviewFrameActive = YES;
    [UIView performWithoutAnimation:^{
        self.view.frame = preview;
        [self.view setNeedsLayout];
    }];
}

- (void)applyLiveResizePreviewForTranslation:(CGPoint)translation {
    if (self.expanded || CGRectIsEmpty(self.resizeOriginalFrame)) return;
    CGRect preview = self.resizeOriginalFrame;
    BOOL landscape = CCBGCurrentInterfaceIsLandscape(self.view);
    NSInteger visualBaseWidth = landscape ? self.resizePreviewBaseHeight : self.resizePreviewBaseWidth;
    NSInteger visualBaseHeight = landscape ? self.resizePreviewBaseWidth : self.resizePreviewBaseHeight;
    CGFloat widthUnit = self.resizeOriginalFrame.size.width / MAX(1, visualBaseWidth);
    CGFloat heightUnit = self.resizeOriginalFrame.size.height / MAX(1, visualBaseHeight);
    CGFloat deltaWidth = landscape ? translation.y : translation.x;
    CGFloat deltaHeight = landscape ? translation.x : translation.y;
    CGFloat maximumWidth = widthUnit * 4.0;
    CGFloat maximumHeight = heightUnit * 4.0;
    UIView *host = self.view.superview;
    CGRect hostBounds = host ? host.bounds : CGRectZero;
    if (host && !CGRectIsEmpty(hostBounds)) {
        maximumWidth = MIN(maximumWidth, MAX(widthUnit, CGRectGetMaxX(hostBounds) - CGRectGetMinX(self.resizeOriginalFrame)));
        maximumHeight = MIN(maximumHeight, MAX(heightUnit, CGRectGetMaxY(hostBounds) - CGRectGetMinY(self.resizeOriginalFrame)));
    }
    CGFloat nextWidth = MIN(maximumWidth, MAX(widthUnit, preview.size.width + deltaWidth));
    CGFloat nextHeight = MIN(maximumHeight, MAX(heightUnit, preview.size.height + deltaHeight));
    preview.size = CGSizeMake(round(nextWidth), round(nextHeight));
    if (host && !CGRectIsEmpty(hostBounds)) {
        CGFloat maxOriginX = MAX(CGRectGetMinX(hostBounds), CGRectGetMaxX(hostBounds) - widthUnit);
        CGFloat maxOriginY = MAX(CGRectGetMinY(hostBounds), CGRectGetMaxY(hostBounds) - heightUnit);
        preview.origin.x = MIN(MAX(preview.origin.x, CGRectGetMinX(hostBounds)), maxOriginX);
        preview.origin.y = MIN(MAX(preview.origin.y, CGRectGetMinY(hostBounds)), maxOriginY);
        preview.size.width = MIN(preview.size.width, MAX(widthUnit, CGRectGetMaxX(hostBounds) - preview.origin.x));
        preview.size.height = MIN(preview.size.height, MAX(heightUnit, CGRectGetMaxY(hostBounds) - preview.origin.y));
    }
    self.resizePreviewFrame = preview;
    self.resizePreviewFrameActive = YES;
    [UIView performWithoutAnimation:^{
        self.view.frame = preview;
        [self.view setNeedsLayout];
    }];
}

- (void)clearLiveResizePreviewRestoringOriginalFrame:(BOOL)restoreOriginalFrame {
    if (!self.resizePreviewFrameActive) return;
    CGRect originalFrame = self.resizeOriginalFrame;
    if (restoreOriginalFrame && !CGRectIsEmpty(originalFrame)) {
        [UIView performWithoutAnimation:^{
            self.view.frame = originalFrame;
            [self.view setNeedsLayout];
        }];
    }
    self.resizePreviewFrameActive = NO;
    self.resizeOriginalFrame = CGRectZero;
    self.resizePreviewFrame = CGRectZero;
    self.resizePreviewBaseWidth = 0;
    self.resizePreviewBaseHeight = 0;
}

- (void)handleResizePan:(UIPanGestureRecognizer *)recognizer {
    if (self.expanded || CCBGIsCCAsterEditModeActive(self.view) || ![CCBGModulePreference(@"controlCenterResizeEnabled", @NO) boolValue]) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
                self.resizeButton.transform = CGAffineTransformMakeScale(0.94, 0.94);
            } completion:nil];
        }
        self.resizeStartWidth = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", CCBG_MODULE_SLOT, @2) integerValue]));
        self.resizeStartHeight = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", CCBG_MODULE_SLOT, @2) integerValue]));
        self.resizePreviewWidth = self.resizeStartWidth;
        self.resizePreviewHeight = self.resizeStartHeight;
        // A previous drag may still be waiting for CCSupport's layout pass.
        // Start from the frame currently on screen so consecutive drags cannot
        // reuse stale grid units or later restore an old compact frame.
        self.resizeOriginalFrame = self.view.frame;
        self.resizePreviewFrame = CGRectZero;
        self.resizePreviewBaseWidth = self.resizeStartWidth;
        self.resizePreviewBaseHeight = self.resizeStartHeight;
        self.resizePreviewFrameActive = NO;
        [self showResizeFeedbackForWidth:self.resizePreviewWidth height:self.resizePreviewHeight];
        [self performHapticFeedback];
        return;
    }
    CGPoint translation = [recognizer translationInView:self.view.window ?: self.view];
    // The preview frame changes while this recognizer is active. Keep the
    // threshold anchored to the frame at gesture start, otherwise enlarging a
    // module also enlarges the distance needed to reach the next grid size.
    CGFloat baseWidth = CGRectGetWidth(self.resizeOriginalFrame);
    CGFloat baseHeight = CGRectGetHeight(self.resizeOriginalFrame);
    BOOL landscape = CCBGCurrentInterfaceIsLandscape(self.view);
    CGFloat visualWidthStep = MAX(18.0, (baseWidth > 1.0 ? baseWidth : self.view.bounds.size.width) * 0.18);
    CGFloat visualHeightStep = MAX(18.0, (baseHeight > 1.0 ? baseHeight : self.view.bounds.size.height) * 0.18);
    CGFloat logicalWidthStep = landscape ? visualHeightStep : visualWidthStep;
    CGFloat logicalHeightStep = landscape ? visualWidthStep : visualHeightStep;
    CGFloat widthTranslation = landscape ? translation.y : translation.x;
    CGFloat heightTranslation = landscape ? translation.x : translation.y;
    NSInteger width = MIN(4, MAX(1, self.resizeStartWidth + (NSInteger)lround(widthTranslation / logicalWidthStep)));
    NSInteger height = MIN(4, MAX(1, self.resizeStartHeight + (NSInteger)lround(heightTranslation / logicalHeightStep)));
    if (recognizer.state == UIGestureRecognizerStateChanged) [self applyLiveResizePreviewForTranslation:translation];
    if (width != self.resizePreviewWidth || height != self.resizePreviewHeight) {
        self.resizePreviewWidth = width;
        self.resizePreviewHeight = height;
        [self showResizeFeedbackForWidth:width height:height];
        [self performHapticFeedback];
    }
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        BOOL sizeChanged = self.resizePreviewWidth != self.resizeStartWidth || self.resizePreviewHeight != self.resizeStartHeight;
        if (sizeChanged) {
            // Writing only after the finger lifts avoids a CCSupport reflow
            // cancelling this recognizer partway through the drag.
            CCBGWriteModulePreferences(@{ @"gridWidth": @(width), @"gridHeight": @(height) }, CCBG_MODULE_SLOT);
            CCBGSetCachedModulePreference(@"gridWidth", @(width));
            CCBGSetCachedModulePreference(@"gridHeight", @(height));
            [self recordObservedGridSizeWithWidth:width height:height];
        }
        // The temporary frame is only for finger-following feedback. Return
        // ownership to CCSupport before asking it to lay out the committed
        // footprint, otherwise the old preview origin can remain misaligned
        // with neighboring modules when the host reflows asynchronously.
        [self clearLiveResizePreviewRestoringOriginalFrame:YES];
        BOOL needsDeferredLayout = self.resizeLayoutUpdateDeferred;
        self.resizeLayoutUpdateDeferred = NO;
        if (sizeChanged || needsDeferredLayout) {
            [self requestControlCenterLayoutSizeUpdate];
        }
        if (sizeChanged) [self scheduleResizeLayoutRecovery];
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.resizeButton.transform = CGAffineTransformIdentity;
        } completion:nil];
        [self scheduleResizeControlVisibilityRecovery];
        [self hideResizeFeedback];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        BOOL sizeChanged = self.resizePreviewWidth != self.resizeStartWidth || self.resizePreviewHeight != self.resizeStartHeight;
        if (sizeChanged) {
            [self applyLiveResizePreviewForWidth:self.resizeStartWidth height:self.resizeStartHeight];
            CCBGWriteModulePreferences(@{ @"gridWidth": @(self.resizeStartWidth), @"gridHeight": @(self.resizeStartHeight) }, CCBG_MODULE_SLOT);
            CCBGSetCachedModulePreference(@"gridWidth", @(self.resizeStartWidth));
            CCBGSetCachedModulePreference(@"gridHeight", @(self.resizeStartHeight));
            [self recordObservedGridSizeWithWidth:self.resizeStartWidth height:self.resizeStartHeight];
        }
        BOOL needsDeferredLayout = self.resizeLayoutUpdateDeferred;
        self.resizeLayoutUpdateDeferred = NO;
        if (sizeChanged || needsDeferredLayout) {
            [self requestControlCenterLayoutSizeUpdate];
        }
        [self scheduleResizeControlVisibilityRecovery];
        [self clearLiveResizePreviewRestoringOriginalFrame:NO];
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.resizeButton.transform = CGAffineTransformIdentity;
        } completion:nil];
        [self hideResizeFeedback];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!touch.view || !self.view.window || self.view.hidden || self.view.alpha < 0.01) return NO;
    if (gestureRecognizer == self.resizePan && CCBGIsCCAsterEditModeActive(self.view)) return NO;
    BOOL customTap = gestureRecognizer == self.compactTap || gestureRecognizer == self.doubleTap ||
        gestureRecognizer == self.tripleTap || gestureRecognizer == self.actionLongPress;
    UIView *nativePlayerView = self.nativePlayerController.view;
    BOOL touchTargetsNativePlayer = self.expanded && !nativePlayerView.hidden &&
        (touch.view == nativePlayerView || [touch.view isDescendantOfView:nativePlayerView]);
    if (customTap && touchTargetsNativePlayer) return NO;
    if ((gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight || gestureRecognizer == self.opacityPan) &&
        touchTargetsNativePlayer && CCBGTouchIsNativeTransportControl(touch, nativePlayerView)) return NO;
    if (self.expandedControlPanel &&
        (touch.view == self.expandedControlPanel || [touch.view isDescendantOfView:self.expandedControlPanel])) return NO;
    if (gestureRecognizer != self.resizePan && self.resizeButton &&
        (touch.view == self.resizeButton || [touch.view isDescendantOfView:self.resizeButton])) return NO;
    CGPoint point = [touch locationInView:self.view];
    return CGRectContainsPoint(self.view.bounds, point);
}

- (void)installGestureHostIfNeeded {
    UIView *candidate = self.view.window ?: self.view;
    if (self.gestureHostView == candidate) return;
    self.gestureHostView = candidate;
    for (UIGestureRecognizer *recognizer in @[
        self.swipeLeft, self.swipeRight, self.opacityPan, self.compactTap,
        self.doubleTap, self.tripleTap, self.actionLongPress
    ]) {
        [candidate addGestureRecognizer:recognizer];
    }
}

- (void)handleOpacityPan:(UIPanGestureRecognizer *)recognizer {
    if (!self.expanded || !self.currentItem) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.adjustingBlur = [recognizer locationInView:self.view].x < CGRectGetMidX(self.view.bounds);
        BOOL independentExpanded = [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue];
        NSString *blurKey = independentExpanded ? @"expandedBlurIntensity" : @"moduleBlurIntensity";
        NSString *opacityKey = independentExpanded ? @"expandedOpacity" : @"moduleOpacity";
        self.opacityAtPanStart = MIN(1.0, MAX(0.05, [CCBGModulePreference(opacityKey, @1.0) doubleValue]));
        self.blurAtPanStart = MIN(1.0, MAX(0.0, [CCBGModulePreference(blurKey, @0.0) doubleValue]));
        self.captionLabel.hidden = NO;
        if ([CCBGModulePreference(@"hapticFeedbackEnabled", @YES) boolValue]) {
            [self performHapticFeedback];
        }
        return;
    }
    CGFloat travel = MAX(140.0, self.view.bounds.size.height * 0.8);
    CGFloat value = (self.adjustingBlur ? self.blurAtPanStart : self.opacityAtPanStart) - [recognizer translationInView:self.view].y / travel;
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        if (self.adjustingBlur) [self updateCurrentBlur:value persist:NO];
        else [self updateCurrentOpacity:value persist:NO];
    } else if (recognizer.state == UIGestureRecognizerStateEnded) {
        if (self.adjustingBlur) [self updateCurrentBlur:value persist:YES];
        else [self updateCurrentOpacity:value persist:YES];
        self.captionLabel.hidden = ![CCBGModulePreference(@"showExpandedCaption", @YES) boolValue];
    } else if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        if (self.adjustingBlur) [self updateCurrentBlur:self.blurAtPanStart persist:NO];
        else [self updateCurrentOpacity:self.opacityAtPanStart persist:NO];
        self.captionLabel.hidden = ![CCBGModulePreference(@"showExpandedCaption", @YES) boolValue];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.view.clipsToBounds = YES;
    self.view.layer.masksToBounds = YES;
    // A frame change from CCSupport means its real grid layout has arrived;
    // drop our temporary compact preview without writing another frame.
    if (self.resizePreviewFrameActive && !CGRectEqualToRect(self.view.frame, self.resizePreviewFrame)) {
        BOOL dragStillActive = self.resizePan.state == UIGestureRecognizerStateBegan ||
            self.resizePan.state == UIGestureRecognizerStateChanged;
        if (dragStillActive) {
            [UIView performWithoutAnimation:^{
                self.view.frame = self.resizePreviewFrame;
            }];
        } else {
            [self clearLiveResizePreviewRestoringOriginalFrame:NO];
        }
    }
    BOOL appearanceGeometryChanged = !self.hasAppearanceBounds ||
        !CGRectEqualToRect(self.lastAppearanceBounds, self.view.bounds) ||
        self.lastAppearanceExpanded != self.expanded;
    if (appearanceGeometryChanged) [self applyModuleAppearance];
    CGFloat inset = MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue]));
    CGRect contentFrame = CGRectInset(self.view.bounds, inset, inset);
    CGRect mediaFrame = contentFrame;
    CGRect expandedPanelFrame = CGRectZero;
    if (self.expanded) {
        CGFloat gap = 8.0;
        CGFloat panelHeight = MIN(154.0, MAX(126.0, CGRectGetHeight(contentFrame) * 0.34));
        CGFloat minimumMediaHeight = 168.0;
        if (CGRectGetHeight(contentFrame) - panelHeight - gap < minimumMediaHeight) {
            panelHeight = MAX(116.0, CGRectGetHeight(contentFrame) - gap - minimumMediaHeight);
        }
        mediaFrame.size.height = MAX(0.0, CGRectGetHeight(contentFrame) - panelHeight - gap);
        expandedPanelFrame = CGRectMake(CGRectGetMinX(contentFrame),
                                        CGRectGetMaxY(mediaFrame) + gap,
                                        CGRectGetWidth(contentFrame),
                                        panelHeight);
    }
    BOOL contentFrameChanged = !self.hasLaidOutContentFrame || !CGRectEqualToRect(self.lastLaidOutContentFrame, contentFrame);
    BOOL expandedStateChanged = !self.hasLaidOutExpandedState || self.lastLaidOutExpandedState != self.expanded;
    self.hasLaidOutExpandedState = YES;
    self.lastLaidOutExpandedState = self.expanded;
    if (contentFrameChanged) {
        self.hasLaidOutContentFrame = YES;
        self.lastLaidOutContentFrame = contentFrame;
    }
    // The expanded panel shares the same outer module but owns the lower
    // controls. Keep the media surfaces in the upper frame so the native
    // AVPlayer controls never sit underneath the mode buttons.
    BOOL mediaFrameChanged = !self.hasLaidOutMediaFrame ||
        !CGRectEqualToRect(self.lastLaidOutMediaFrame, mediaFrame);
    BOOL playerLayerChanged = self.lastLaidOutPlayerLayer != self.playerLayer;
    BOOL nativeViewChanged = self.lastLaidOutNativeView != self.nativePlayerController.view;
    if (mediaFrameChanged) {
        self.imageView.frame = mediaFrame;
        self.dynamicTintView.frame = mediaFrame;
        self.blurView.frame = mediaFrame;
        self.dimView.frame = mediaFrame;
    }
    if (mediaFrameChanged || playerLayerChanged) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (contentFrameChanged || expandedStateChanged || !self.expanded) [self.playerLayer setAffineTransform:CGAffineTransformIdentity];
        self.playerLayer.frame = mediaFrame;
        self.playerLayer.masksToBounds = YES;
        [CATransaction commit];
    }
    // The compact AVPlayerLayer owns the compact geometry.  A native
    // AVPlayerViewController is only a mounted expanded surface; writing its
    // frame during compact layout (or while it is being detached) leaves a
    // stale expanded child in the hierarchy and can make the player vanish
    // on the following expand.
    if (self.expanded && self.nativePlayerController && (mediaFrameChanged || nativeViewChanged)) {
        self.nativePlayerController.view.frame = mediaFrame;
    }
    self.hasLaidOutMediaFrame = YES;
    self.lastLaidOutMediaFrame = mediaFrame;
    self.lastLaidOutPlayerLayer = self.playerLayer;
    self.lastLaidOutNativeView = self.nativePlayerController.view;
    // Apply masks after every media surface has its final frame. UIKit can
    // retain the old corner geometry when a view is resized in-place.
    if (mediaFrameChanged || expandedStateChanged || playerLayerChanged || nativeViewChanged) {
        CCBGApplyAllMediaCorners(self.view, @[self.imageView, self.dynamicTintView, self.blurView, self.dimView], self.playerLayer, self.nativePlayerController.view);
    }
    if (self.currentItem && (contentFrameChanged || expandedStateChanged)) [self applyDisplayForItem:self.currentItem];
    if (self.expandedControlPanel) {
        BOOL panelFrameChanged = !self.hasLaidOutExpandedPanelFrame ||
            !CGRectEqualToRect(self.lastLaidOutExpandedPanelFrame, expandedPanelFrame);
        if (panelFrameChanged) {
            self.expandedControlPanel.frame = expandedPanelFrame;
            CGFloat panelWidth = CGRectGetWidth(expandedPanelFrame);
            self.expandedStateIcon.frame = CGRectMake(12.0, 11.0, 18.0, 18.0);
            self.expandedStateLabel.frame = CGRectMake(38.0, 8.0, MAX(0.0, panelWidth - 50.0), 24.0);
            self.expandedModeStack.frame = CGRectMake(12.0, 39.0, MAX(0.0, panelWidth - 24.0), 36.0);
            CGFloat actionY = CGRectGetHeight(expandedPanelFrame) - 43.0;
            CGFloat actionWidth = MAX(0.0, (panelWidth - 36.0) / 3.0);
            self.expandedPresetButton.frame = CGRectMake(12.0, actionY, actionWidth, 32.0);
            self.expandedCompositionButton.frame = CGRectMake(18.0 + actionWidth, actionY, actionWidth, 32.0);
            self.expandedMediaButton.frame = CGRectMake(24.0 + actionWidth * 2.0, actionY, actionWidth, 32.0);
            self.hasLaidOutExpandedPanelFrame = YES;
            self.lastLaidOutExpandedPanelFrame = expandedPanelFrame;
        }
        if (self.view.subviews.lastObject != self.expandedControlPanel) [self.view bringSubviewToFront:self.expandedControlPanel];
        if (panelFrameChanged || expandedStateChanged) [self updateExpandedControls];
    }
    [self updateResizeControlVisibility];
    [self installGestureHostIfNeeded];
    BOOL playbackPassNeeded = contentFrameChanged || mediaFrameChanged || expandedStateChanged ||
        playerLayerChanged || nativeViewChanged || !self.visible;
    [self updateNativePlayerPresentation];
    // Layout callbacks can arrive dozens of times while Control Center is
    // settling. A healthy player does not need to be re-presented on every
    // pass; keep recovery tied to a real geometry/layer change so AVKit does
    // not compete with the host's animation.
    if (playbackPassNeeded || !self.didScheduleFirstMountedReload) [self reloadAfterFirstMountIfNeeded];
    if (playbackPassNeeded) [self resumeVideoPlaybackIfNeeded];
}

- (void)reloadAfterFirstMountIfNeeded {
    if (!self.visible) return;
    if (!self.view.window) return;
    BOOL needsMediaReload = [self requiresMountedMediaReload];
    BOOL needsLayerRecovery = [self requiresMountedPlayerLayerRecovery];
    // A healthy mounted surface only needs one resume pass. Keep the guard
    // conditional so a later detached layer or missing media can still enter
    // the recovery queue without waiting for a new viewWillAppear callback.
    if (self.didScheduleFirstMountedReload && !needsMediaReload && !needsLayerRecovery) return;
    if (!needsMediaReload) {
        if (!needsLayerRecovery) {
            self.view.hidden = NO;
            self.view.alpha = 1.0;
            [self resumeVideoPlaybackIfNeeded];
            self.didScheduleFirstMountedReload = YES;
            return;
        }
    }
    self.didScheduleFirstMountedReload = YES;
    NSUInteger generation = self.convergenceGeneration;
    NSTimeInterval delay = self.mountReloadAttempts == 0 ? 0.0 : MIN(2.0, 0.25 * self.mountReloadAttempts);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.convergenceGeneration) return;
        self.didScheduleFirstMountedReload = NO;
        if (!self.view.window) {
            return;
        }
        self.view.hidden = NO;
        self.view.alpha = 1.0;
        self.mountReloadAttempts += 1;
        BOOL needsMediaReload = [self requiresMountedMediaReload];
        BOOL needsLayerRecovery = [self requiresMountedPlayerLayerRecovery];
        if (needsMediaReload) {
            [self reloadPreferencesAndMedia];
        } else if (needsLayerRecovery) {
            [self recoverPlayerLayerSurfaceIfNeededForItem:self.player.currentItem reason:@"mounted-layer-recovery"];
        }
        [self resumeVideoPlaybackIfNeeded];
        if (([self requiresMountedMediaReload] || [self requiresMountedPlayerLayerRecovery]) && self.mountReloadAttempts < 45) [self reloadAfterFirstMountIfNeeded];
    });
}

- (void)protectedDataDidBecomeAvailable:(NSNotification *)notification {
    [self reloadPreferencesAndMedia];
    if (CCBGIsVideoName(self.currentItem[@"fileName"])) {
        self.lastVideoSuspendedAt = NSProcessInfo.processInfo.systemUptime - 600.0;
        [self rebuildVideoAfterExtendedSuspensionIfNeeded];
    }
    [self reloadAfterFirstMountIfNeeded];
    [self resumeVideoPlaybackIfNeeded];
}

- (BOOL)rebuildVideoAfterExtendedSuspensionIfNeeded {
    if (!self.player.currentItem || !CCBGIsVideoName(self.currentItem[@"fileName"])) return NO;
    NSTimeInterval suspendedAt = self.lastVideoSuspendedAt;
    if (suspendedAt <= 0 || NSProcessInfo.processInfo.systemUptime - suspendedAt < 300.0) return NO;
    NSString *path = CCBGPathForItem(self.currentItem);
    self.lastVideoSuspendedAt = 0;
    CCBGInvalidateVideoOnlyAssetMemoryCache(path);
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-rebuild-after-suspension", @{
        @"current": self.currentItem[@"fileName"] ?: @"",
        @"suspendedSeconds": @(MAX(0.0, NSProcessInfo.processInfo.systemUptime - suspendedAt)),
    });
    [self showCurrentMediaWithTransition:NO];
    return YES;
}

- (BOOL)requiresMountedMediaReload {
    if (!CCBGMediaDirectoryIsReadable()) return YES;
    if (!self.currentItem || !self.hasLoadedPreferences) return YES;
    return NO;
}

- (void)resumeVideoPlaybackIfNeeded {
    if (!self.visible) return;
    if (!self.view.window || !self.player.currentItem || !CCBGIsVideoName(self.currentItem[@"fileName"])) return;
    if ([self shouldUseSceneLowPowerCover]) {
        [self activateSceneLowPowerCoverIfNeeded];
        return;
    }
    [self restoreSceneLowPowerPlaybackIfNeeded];
    BOOL privacyPaused = CCBGSystemIsLocked()
        && [CCBGModulePreference(@"privacyEnabled", @NO) boolValue]
        && [CCBGModulePreference(@"privacyPauseVideo", @YES) boolValue];
    if (privacyPaused) return;
    self.visible = YES;
    if (self.healthStartRecorded && self.healthPlaybackStartedAt <= 0) {
        self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
        self.healthPlaybackFileName = [self.currentItem[@"fileName"] copy];
    }
    [self updateNativePlayerPresentation];
    BOOL playbackActive = self.player.rate > 0.01 ||
        self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying ||
        self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
    if (!playbackActive) {
        [self.player playImmediatelyAtRate:CCBGEffectivePlaybackRate(self.currentItem)];
        [self startVideoPlaybackWhenReadyForItem:self.player.currentItem attempt:0];
    }
    if (!self.videoWatchdog) [self startVideoWatchdogForItem:self.player.currentItem];
}

- (BOOL)requiresMountedPlayerLayerRecovery {
    return CCBGIsVideoName(self.currentItem[@"fileName"]) &&
        (!self.player.currentItem || self.playerLayer.superlayer != self.view.layer);
}

- (BOOL)requiresMountedPresentationRecovery {
    if (!self.view.window) return NO;
    UIView *parent = self.view.superview;
    BOOL presentationHidden = self.view.hidden || self.view.alpha < 0.01 ||
        self.view.layer.hidden || self.view.layer.opacity < 0.01f;
    BOOL hierarchyMissing = !parent || parent.subviews.lastObject != self.view;
    BOOL nativePlayerMissing = self.expanded && CCBGIsVideoName(self.currentItem[@"fileName"]) &&
        (!self.nativePlayerController || self.nativePlayerController.player != self.player ||
         self.nativePlayerController.view.hidden || self.nativePlayerController.view.superview != self.view);
    return presentationHidden || hierarchyMissing ||
        nativePlayerMissing || [self requiresMountedMediaReload] || [self requiresMountedPlayerLayerRecovery];
}

- (void)convergeMountedPresentation:(NSString *)reason {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf convergeMountedPresentation:reason];
        });
        return;
    }
    if (!self.visible || !self.view.window) return;
    if (![self applyPluginEnabledState]) return;
    NSTimeInterval recoveryGeneration = [CCBGModuleGlobalPreference(@"fiveModulePresentationRecoveryGeneration", @0) doubleValue];
    BOOL explicitHierarchyRecovery = [reason hasPrefix:@"manual-advance"] || [reason hasPrefix:@"select-media"] ||
        [reason hasPrefix:@"reload"] || [reason hasPrefix:@"environment-change"];
    BOOL shouldRepairHierarchy = !self.didRepairMountedHierarchy || recoveryGeneration > self.lastPresentationRecoveryGeneration || explicitHierarchyRecovery;
    UIView *parentView = self.view.superview;
    BOOL hierarchyPassNeeded = shouldRepairHierarchy ||
        (parentView && parentView.subviews.lastObject != self.view) ||
        (self.playerLayer && self.playerLayer.superlayer != self.view.layer);
    BOOL repairedHierarchy = hierarchyPassNeeded
        ? [self repairMountedPresentationHierarchyForFullRecovery:shouldRepairHierarchy]
        : NO;
    if (shouldRepairHierarchy) {
        self.didRepairMountedHierarchy = YES;
        self.lastPresentationRecoveryGeneration = recoveryGeneration;
    }
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.layer.hidden = NO;
    self.view.layer.opacity = 1.0;
    if (hierarchyPassNeeded) {
        [self.view.superview setNeedsLayout];
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }
    if (self.playerLayer && self.playerLayer.superlayer != self.view.layer) {
        [self.playerLayer removeFromSuperlayer];
        [self.view.layer insertSublayer:self.playerLayer atIndex:0];
    }
    if (self.currentItem) {
        [self applyDisplayForItem:self.currentItem];
    }
    [self updateNativePlayerPresentation];
    [self resumeVideoPlaybackIfNeeded];
    NSString *diagnosticSignature = [NSString stringWithFormat:@"%@|%@|%d|%d|%ld|%.0f",
        NSStringFromCGRect(self.view.bounds), self.currentItem[@"fileName"] ?: @"",
        self.view.hidden, self.playerLayer.readyForDisplay, (long)self.player.currentItem.status, recoveryGeneration];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    BOOL shouldRecordDiagnostic = repairedHierarchy ||
        ![diagnosticSignature isEqualToString:self.lastConvergenceDiagnosticSignature] ||
        now - self.lastConvergenceDiagnosticAt >= 2.0;
    if (!shouldRecordDiagnostic) return;
    self.lastConvergenceDiagnosticSignature = diagnosticSignature;
    self.lastConvergenceDiagnosticAt = now;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"presentation-converged", @{
        @"reason": reason ?: @"",
        @"bounds": NSStringFromCGRect(self.view.bounds),
        @"hidden": @(self.view.hidden),
        @"alpha": @(self.view.alpha),
        @"layerHidden": @(self.view.layer.hidden),
        @"playerLayerHidden": @(self.playerLayer.hidden),
        @"playerLayerReady": @(self.playerLayer.readyForDisplay),
        @"playerStatus": @(self.player.currentItem.status),
        @"playerTime": @(CMTimeGetSeconds(self.player.currentTime)),
        @"hasPlayerItem": @(self.player.currentItem != nil),
        @"current": self.currentItem[@"fileName"] ?: @"",
        @"hierarchyRepaired": @(repairedHierarchy),
        @"hierarchyRepairRequested": @(shouldRepairHierarchy),
        @"recoveryGeneration": @(recoveryGeneration),
        @"hierarchy": [self mountedPresentationHierarchySnapshot]
    });
}

- (BOOL)repairMountedPresentationHierarchyForFullRecovery:(BOOL)fullRecovery {
    if (!self.visible || !self.view.window) return NO;
    BOOL repaired = NO;
    UIView *parent = self.view.superview;
    if (parent && parent.subviews.lastObject != self.view) {
        [parent bringSubviewToFront:self.view];
        repaired = YES;
    }
    if (!fullRecovery) {
        [parent setNeedsLayout];
        [parent layoutIfNeeded];
        [self.view.layer setNeedsDisplay];
        [self.playerLayer setNeedsDisplay];
        return repaired;
    }
    NSUInteger depth = 0;
    for (UIView *ancestor = parent; ancestor && ancestor != self.view.window && depth < 8; ancestor = ancestor.superview, depth++) {
        if (ancestor.hidden) {
            ancestor.hidden = NO;
            repaired = YES;
        }
        if (ancestor.alpha < 0.01) {
            ancestor.alpha = 1.0;
            repaired = YES;
        }
        if (ancestor.layer.hidden) {
            ancestor.layer.hidden = NO;
            repaired = YES;
        }
        if (ancestor.layer.opacity < 0.01f) {
            ancestor.layer.opacity = 1.0f;
            repaired = YES;
        }
        if (CCBGHasVisibleOverlappingSiblingAbove(ancestor)) {
            [ancestor.superview bringSubviewToFront:ancestor];
            repaired = YES;
        }
        [ancestor setNeedsLayout];
    }
    [parent layoutIfNeeded];
    [self.view.layer setNeedsDisplay];
    [self.playerLayer setNeedsDisplay];
    return repaired;
}

- (void)scheduleMountedPresentationConvergence:(NSString *)reason {
    NSString *scheduleReason = reason.length ? reason : @"mounted";
    if (self.convergenceSchedulePending && [self.lastConvergenceScheduleReason isEqualToString:scheduleReason]) return;
    self.convergenceSchedulePending = YES;
    self.lastConvergenceScheduleReason = scheduleReason;
    NSUInteger generation = ++self.convergenceGeneration;
    for (NSNumber *delay in @[@0.05, @0.25, @0.75]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!weakSelf || generation != weakSelf.convergenceGeneration) return;
            BOOL finalPass = delay.doubleValue >= 0.75;
            BOOL needsRecovery = [weakSelf requiresMountedPresentationRecovery];
            if (!needsRecovery) {
                if (finalPass) weakSelf.convergenceSchedulePending = NO;
                // Preserve the original fast path: if (!needsRecovery) return;
                return;
            }
            if (weakSelf.view.window && !weakSelf.view.window.hidden && weakSelf.view.window.alpha > 0.01 &&
                [CCBGModuleGlobalPreference(@"pluginEnabled", @YES) boolValue]) {
                weakSelf.visible = YES;
                [weakSelf reloadAfterFirstMountIfNeeded];
                [weakSelf resumeVideoPlaybackIfNeeded];
                if (CCBGIsVideoName(weakSelf.currentItem[@"fileName"]) &&
                    weakSelf.player.currentItem && !weakSelf.playerLayer.readyForDisplay) {
                    [weakSelf recoverPlayerLayerSurfaceIfNeededForItem:weakSelf.player.currentItem reason:@"mounted-presentation-delayed"];
                }
            }
            [weakSelf convergeMountedPresentation:[NSString stringWithFormat:@"%@-delayed", scheduleReason]];
            if (finalPass) weakSelf.convergenceSchedulePending = NO;
        });
    }
}

- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot {
    NSMutableArray<NSDictionary *> *snapshot = [NSMutableArray array];
    UIView *view = self.view;
    NSUInteger depth = 0;
    while (view && depth < 9) {
        UIView *parent = view.superview;
        NSUInteger siblingIndex = parent ? [parent.subviews indexOfObjectIdenticalTo:view] : NSNotFound;
        [snapshot addObject:@{
            @"class": NSStringFromClass(view.class) ?: @"",
            @"frame": NSStringFromCGRect(view.frame),
            @"bounds": NSStringFromCGRect(view.bounds),
            @"hidden": @(view.hidden),
            @"alpha": @(view.alpha),
            @"layerHidden": @(view.layer.hidden),
            @"layerOpacity": @(view.layer.opacity),
            @"siblingIndex": siblingIndex == NSNotFound ? @(-1) : @(siblingIndex),
            @"siblingCount": @(parent.subviews.count),
        }];
        if (view == self.view.window) break;
        view = parent;
        depth += 1;
    }
    return snapshot;
}

- (void)setExpandedInteractionEnabled:(BOOL)enabled {
    BOOL expandedStateChanged = self.expanded != enabled;
    CGFloat previousCornerRadius = self.view.layer.cornerRadius;
    CGFloat previousMediaRadius = MAX(0.0, previousCornerRadius - CCBGMediaInsetForFrame(self.view, self.imageView.frame));
    self.expanded = enabled;
    if (!enabled) [self clearPreloadedNextMedia];
    NSDictionary *sceneContext = CCBGSceneContextForModule(self.view);
    if (CCBGSceneDirectorBreathingGridEnabled(sceneContext)) CCBGSceneDirectorSetExpandedSlot(enabled ? CCBG_MODULE_SLOT : -1);
    [self applyFallbackColor];
    [self applyModuleAppearance];
    CGFloat nextCornerRadius = self.view.layer.cornerRadius;
    if (expandedStateChanged && fabs(previousCornerRadius - nextCornerRadius) > 0.01 && self.view.window && !UIAccessibilityIsReduceMotionEnabled()) {
        CABasicAnimation *cornerAnimation = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        cornerAnimation.fromValue = @(previousCornerRadius);
        cornerAnimation.toValue = @(nextCornerRadius);
        cornerAnimation.duration = enabled ? 0.24 : 0.16;
        cornerAnimation.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1.0 :0.32 :1.0];
        [self.view.layer addAnimation:cornerAnimation forKey:@"ccbg.cornerRadius"];
    }
    CGFloat nextMediaRadius = MAX(0.0, nextCornerRadius - CCBGMediaInsetForFrame(self.view, self.imageView.frame));
    // Do not construct an NSArray literal with optional layers. During
    // disappearance the player layer may not exist yet, and NSArray rejects
    // nil objects before the animation helper can filter them.
    NSMutableArray<CALayer *> *mediaLayers = [NSMutableArray arrayWithCapacity:6];
    if (self.imageView.layer) [mediaLayers addObject:self.imageView.layer];
    if (self.dynamicTintView.layer) [mediaLayers addObject:self.dynamicTintView.layer];
    if (self.blurView.layer) [mediaLayers addObject:self.blurView.layer];
    if (self.dimView.layer) [mediaLayers addObject:self.dimView.layer];
    if (self.playerLayer) [mediaLayers addObject:self.playerLayer];
    if (self.nativePlayerController.isViewLoaded && self.nativePlayerController.view.layer) {
        [mediaLayers addObject:self.nativePlayerController.view.layer];
    }
    if (expandedStateChanged) {
        CCBGAnimateCornerRadiusForLayers(mediaLayers, previousMediaRadius, nextMediaRadius, enabled ? 0.24 : 0.16);
    }
    self.view.userInteractionEnabled = YES;
    if (expandedStateChanged) {
        self.compactTap.enabled = YES;
        self.doubleTap.enabled = YES;
        self.tripleTap.enabled = YES;
        self.actionLongPress.enabled = YES;
        self.swipeLeft.enabled = enabled;
        self.swipeRight.enabled = enabled;
        self.opacityPan.enabled = enabled;
    }
    // The expanded status row now carries the media name and playback mode.
    // Keep the legacy caption out of the video surface so it cannot cover
    // AVPlayer's transport controls or flash during a collapse.
    BOOL shouldShowCaption = NO;
    BOOL captionCurrentlyVisible = !self.captionLabel.hidden && self.captionLabel.alpha > 0.01;
    if (shouldShowCaption != captionCurrentlyVisible) {
        if (shouldShowCaption) {
            self.captionLabel.hidden = NO;
            self.captionLabel.alpha = 0.0;
            self.captionLabel.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
        }
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.16 : 0.22
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.captionLabel.alpha = shouldShowCaption ? 1.0 : 0.0;
            self.captionLabel.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            if (!shouldShowCaption) self.captionLabel.hidden = YES;
        }];
    }
    if (self.expandedControlPanel) {
        [self updateExpandedControls];
        if (expandedStateChanged) {
            NSUInteger animationGeneration = ++self.expandedPanelAnimationGeneration;
            BOOL wasHidden = self.expandedControlPanel.hidden || self.expandedControlPanel.alpha < 0.01;
            BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
            CGAffineTransform entranceTransform = reduceMotion
                ? CGAffineTransformIdentity
                : CGAffineTransformConcat(CGAffineTransformMakeScale(0.985, 0.985), CGAffineTransformMakeTranslation(0.0, 8.0));
            CGAffineTransform exitTransform = reduceMotion
                ? CGAffineTransformIdentity
                : CGAffineTransformConcat(CGAffineTransformMakeScale(0.985, 0.985), CGAffineTransformMakeTranslation(0.0, 6.0));
            if (enabled) {
                self.expandedControlPanel.hidden = NO;
                if (wasHidden) {
                    self.expandedControlPanel.alpha = 0.0;
                    self.expandedPanelMaterial.alpha = 0.0;
                    self.expandedControlPanel.transform = entranceTransform;
                }
            }
            // Entering gets a little more time to materialize; leaving is
            // deliberately shorter so a collapse never feels like it lingers.
            NSTimeInterval panelDuration = reduceMotion ? 0.14 : (enabled ? 0.28 : 0.17);
            void (^panelAnimations)(void) = ^{
                self.expandedControlPanel.alpha = enabled ? 1.0 : 0.0;
                self.expandedPanelMaterial.alpha = enabled ? 0.76 : 0.0;
                self.expandedControlPanel.transform = enabled ? CGAffineTransformIdentity : exitTransform;
            };
            void (^panelCompletion)(BOOL) = ^(BOOL finished) {
                if (animationGeneration != self.expandedPanelAnimationGeneration) return;
                if (!enabled && !self.expanded) self.expandedControlPanel.hidden = YES;
            };
            if (enabled && !reduceMotion) {
                [UIView animateWithDuration:panelDuration
                                      delay:0.0
                     usingSpringWithDamping:1.0
                      initialSpringVelocity:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                                 animations:panelAnimations
                                 completion:panelCompletion];
            } else {
                [UIView animateWithDuration:panelDuration
                                      delay:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                                 animations:panelAnimations
                                 completion:panelCompletion];
            }
        }
    }
    [self updateResizeControlVisibility];
    [self updateNativePlayerPresentation];
    [self updateExpandedCaption];
    if (self.currentItem) [self applyDisplayForItem:self.currentItem];
}

- (void)applyModuleAppearance {
    self.lastAppearanceBounds = self.view.bounds;
    self.hasAppearanceBounds = YES;
    self.lastAppearanceExpanded = self.expanded;
    BOOL independentExpanded = self.expanded && [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue];
    CGFloat configuredRadius = [CCBGModulePreference(independentExpanded ? @"expandedCornerRadius" : @"moduleCornerRadius", @0) doubleValue];
    if (independentExpanded && configuredRadius <= 0.0) configuredRadius = [CCBGModulePreference(@"moduleCornerRadius", @0) doubleValue];
    CGFloat defaultRadius = CCBGContinuousCornerRadiusForSize(self.view.bounds.size);
    if (defaultRadius <= 0.0) defaultRadius = self.expanded ? 24.0 : 18.0;
    CGFloat cornerRadius = configuredRadius > 0 ? MIN(40.0, configuredRadius) : defaultRadius;
    CGFloat configuredBorderWidth = MIN(6.0, MAX(0.0, [CCBGModulePreference(independentExpanded ? @"expandedBorderWidth" : @"moduleBorderWidth", @0) doubleValue]));
    if (independentExpanded && configuredBorderWidth <= 0.0) configuredBorderWidth = MIN(6.0, MAX(0.0, [CCBGModulePreference(@"moduleBorderWidth", @0) doubleValue]));
    NSString *borderHex = CCBGModulePreference(@"moduleBorderColor", @"#FFFFFF");
    BOOL foregroundTint = [CCBGModulePreference(@"foregroundAppTintEnabled", @NO) boolValue];
    BOOL wallpaperTint = [CCBGModulePreference(@"wallpaperTintEnabled", @NO) boolValue];
    NSInteger tintTarget = MIN(2, MAX(0, [CCBGModulePreference(@"dynamicTintTarget", @0) integerValue]));
    CGFloat tintStrength = MIN(1.0, MAX(0.0, [CCBGModulePreference(@"dynamicTintStrength", @0.65) doubleValue]));
    unsigned borderValue = 0xffffff;
    [[NSScanner scannerWithString:[borderHex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&borderValue];
    UIColor *borderColor = [UIColor colorWithRed:((borderValue >> 16) & 0xff) / 255.0 green:((borderValue >> 8) & 0xff) / 255.0 blue:(borderValue & 0xff) / 255.0 alpha:0.75];
    if (!foregroundTint && !wallpaperTint) {
        NSString *signature = [NSString stringWithFormat:@"%.3f|%.3f|%.3f|%.3f|%@|%d|%d", cornerRadius, configuredBorderWidth, [CCBGModulePreference(independentExpanded ? @"expandedBlurIntensity" : @"moduleBlurIntensity", @0) doubleValue], [CCBGModulePreference(independentExpanded ? @"expandedOpacity" : @"moduleOpacity", @1) doubleValue], borderHex ?: @"", self.expanded, independentExpanded];
        BOOL layerStateMatches = fabs(self.view.layer.cornerRadius - cornerRadius) <= 0.001 &&
            fabs(self.view.layer.borderWidth - configuredBorderWidth) <= 0.001 &&
            self.view.layer.borderColor && CGColorEqualToColor(self.view.layer.borderColor, borderColor.CGColor) &&
            self.dynamicTintView.hidden && self.dynamicTintView.alpha <= 0.001;
        if ([signature isEqualToString:self.lastStaticAppearanceSignature] && layerStateMatches) {
            // Media corner geometry is refreshed by viewDidLayoutSubviews and
            // updateNativePlayerPresentation when frames or surfaces change.
            // Avoid rewriting every media layer on an unchanged layout pass.
            return;
        }
        self.lastStaticAppearanceSignature = signature;
    } else {
        self.lastStaticAppearanceSignature = nil;
    }
    self.view.layer.cornerRadius = cornerRadius;
    self.view.layer.masksToBounds = YES;
    UIColor *dynamicColor = CCBGResolvedDynamicPaletteColor(self.view, foregroundTint, wallpaperTint);
    if (dynamicColor && (tintTarget == 0 || tintTarget == 2)) borderColor = CCBGBlendModuleColor(borderColor, dynamicColor, tintStrength);
    BOOL dynamicTintEnabled = (foregroundTint || wallpaperTint) && dynamicColor;
    self.view.layer.borderWidth = dynamicTintEnabled && (tintTarget == 0 || tintTarget == 2) ? MAX(2.0, configuredBorderWidth) : configuredBorderWidth;
    self.view.layer.borderColor = borderColor.CGColor;
    BOOL tintMedia = dynamicTintEnabled && (tintTarget == 1 || tintTarget == 2);
    self.dynamicTintView.backgroundColor = dynamicColor;
    self.dynamicTintView.alpha = tintMedia ? 0.08 + tintStrength * 0.18 : 0.0;
    self.dynamicTintView.hidden = !tintMedia;
    CCBGApplyAllMediaCorners(self.view, @[self.imageView, self.dynamicTintView, self.blurView, self.dimView], self.playerLayer, self.nativePlayerController.view);
}

- (void)presentMediaSelectionList {
    if (self.presentedViewController || self.mediaPickerController) return;
    NSArray *catalog = CCBGMediaItemsForModule(CCBGLoadMediaCatalog(), CCBG_MODULE_SLOT);
    NSMutableArray *eligible = [NSMutableArray array];
    for (NSDictionary *item in catalog) if (CCBGMediaItemIsCurrentlyEligible(item)) [eligible addObject:item];
    self.pickerItems = eligible;
    self.filteredPickerItems = nil;
    if (!self.pickerThumbnailCache) {
        self.pickerThumbnailCache = [NSCache new];
        self.pickerThumbnailCache.countLimit = 96;
    }
    if (!self.pendingPickerThumbnailCallbacks) self.pendingPickerThumbnailCallbacks = [NSMutableDictionary dictionary];
    [self.pendingPickerThumbnailCallbacks removeAllObjects];
    UITableViewController *picker = [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.title = @"选择素材";
    picker.tableView.dataSource = self;
    picker.tableView.delegate = self;
    picker.tableView.rowHeight = 72;
    if (self.automationOverrideActive) {
        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 1, 72)];
        hint.text = @"当前有自动化或隐私规则覆盖播放；临时选择可能会在条件结束前被替换。";
        hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        hint.textColor = UIColor.secondaryLabelColor;
        hint.numberOfLines = 0;
        hint.textAlignment = NSTextAlignmentCenter;
        picker.tableView.tableHeaderView = hint;
    }
    self.mediaSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.mediaSearchController.searchResultsUpdater = self;
    self.mediaSearchController.obscuresBackgroundDuringPresentation = NO;
    self.mediaSearchController.searchBar.placeholder = @"搜索素材";
    self.mediaSearchController.searchBar.scopeButtonTitles = @[@"全部", @"收藏", @"视频", @"图片"];
    picker.navigationItem.searchController = self.mediaSearchController;
    picker.navigationItem.hidesSearchBarWhenScrolling = NO;
    picker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismissMediaSelectionList)];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.modalInPresentation = NO;
    navigation.presentationController.delegate = self;
    if (@available(iOS 15.0, *)) {
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        navigation.sheetPresentationController.prefersGrabberVisible = YES;
    }
    self.mediaPickerController = picker;
    UIViewController *host = [self presentationHostController];
    if (host.presentedViewController || !host.view.window) {
        self.mediaPickerController = nil;
        self.pickerItems = nil;
        self.filteredPickerItems = nil;
        self.mediaSearchController = nil;
        return;
    }
    [host presentViewController:navigation animated:YES completion:nil];
}

- (void)dismissMediaSelectionList {
    UINavigationController *navigation = self.mediaPickerController.navigationController;
    if (navigation) {
        [navigation dismissViewControllerAnimated:YES completion:^{ [self clearMediaSelectionState]; }];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ [self clearMediaSelectionState]; }];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self clearMediaSelectionState];
}

- (void)clearMediaSelectionState {
    self.mediaPickerController = nil;
    self.mediaSearchController = nil;
    self.pickerItems = nil;
    self.filteredPickerItems = nil;
    [self.pendingPickerThumbnailCallbacks removeAllObjects];
}

- (UIViewController *)presentationHostController {
    UIViewController *host = self;
    UIResponder *responder = self.view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) {
            host = (UIViewController *)responder;
            break;
        }
        responder = responder.nextResponder;
    }
    if (!host.view.window && self.view.window.rootViewController) host = self.view.window.rootViewController;
    while (host.presentedViewController) host = host.presentedViewController;
    return host;
}

- (NSArray<NSDictionary *> *)visiblePickerItems { return self.filteredPickerItems ?: self.pickerItems ?: @[]; }

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    NSInteger scope = searchController.searchBar.selectedScopeButtonIndex;
    NSArray<NSDictionary *> *items = self.pickerItems ?: @[];
    if (!query.length && scope == 0) {
        self.filteredPickerItems = nil;
    } else {
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *item in items) {
            NSString *name = item[@"fileName"] ?: @"";
            BOOL scopeMatch = scope == 0 ||
                (scope == 1 && [item[@"favorite"] boolValue]) ||
                (scope == 2 && CCBGIsVideoName(name)) ||
                (scope == 3 && !CCBGIsVideoName(name));
            BOOL textMatch = !query.length ||
                [CCBGDisplayNameForItem(item) localizedCaseInsensitiveContainsString:query] ||
                [name localizedCaseInsensitiveContainsString:query] ||
                [item[@"group"] localizedCaseInsensitiveContainsString:query];
            if (scopeMatch && textMatch) [filtered addObject:item];
        }
        self.filteredPickerItems = filtered;
    }
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%lu|%@|%ld|",
        (unsigned long)self.visiblePickerItems.count, query, (long)scope];
    for (NSDictionary *item in self.visiblePickerItems) {
        [signature appendFormat:@"%@|", item[@"fileName"] ?: @""];
    }
    if ([signature isEqualToString:self.lastPickerItemsSignature]) return;
    self.lastPickerItemsSignature = signature.copy;
    NSUInteger generation = ++self.pickerSearchGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.pickerSearchGeneration) return;
        [self.mediaPickerController.tableView reloadData];
    });
}

- (UIImage *)pickerThumbnailForItem:(NSDictionary *)item size:(CGSize)size {
    NSString *name = item[@"fileName"] ?: @"";
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.0fx%.0f-%.2f", name, size.width, size.height, [item[@"coverFrameTime"] doubleValue]];
    return [self.pickerThumbnailCache objectForKey:cacheKey];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.visiblePickerItems.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mediaPicker"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mediaPicker"];
    NSArray<NSDictionary *> *items = self.visiblePickerItems;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)items.count) {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessibilityIdentifier = nil;
        return cell;
    }
    NSDictionary *item = items[(NSUInteger)indexPath.row];
    cell.textLabel.text = CCBGDisplayNameForItem(item);
    cell.detailTextLabel.text = [item[@"group"] length] ? item[@"group"] : (CCBGIsVideoName(item[@"fileName"]) ? @"视频" : @"图片");
    CGSize thumbnailSize = CGSizeMake(58, 58);
    NSString *name = item[@"fileName"] ?: @"";
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.0fx%.0f-%.2f", name, thumbnailSize.width, thumbnailSize.height, [item[@"coverFrameTime"] doubleValue]];
    UIImage *thumbnail = [self.pickerThumbnailCache objectForKey:cacheKey];
    cell.imageView.image = thumbnail ?: CCBGPlaceholderImageForItem(item);
    cell.accessibilityIdentifier = cacheKey;
    if (!thumbnail) {
        NSDictionary *snapshot = [item copy];
        __weak typeof(self) weakSelf = self;
        __weak UITableViewCell *weakCell = cell;
        void (^updateCell)(UIImage *) = [^(UIImage *loaded) {
            UITableViewCell *strongCell = weakCell;
            if (!loaded || ![strongCell.accessibilityIdentifier isEqualToString:cacheKey]) return;
            [weakSelf.pickerThumbnailCache setObject:loaded forKey:cacheKey];
            strongCell.imageView.image = loaded;
            [strongCell setNeedsLayout];
        } copy];
        NSMutableArray *callbacks = self.pendingPickerThumbnailCallbacks[cacheKey];
        if (callbacks) {
            [callbacks addObject:updateCell];
        } else {
            self.pendingPickerThumbnailCallbacks[cacheKey] = [NSMutableArray arrayWithObject:updateCell];
            dispatch_async(CCBGThumbnailQueue(), ^{
                UIImage *loaded = CCBGThumbnailForItem(snapshot, thumbnailSize);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    NSArray *finishedCallbacks = [strongSelf.pendingPickerThumbnailCallbacks[cacheKey] copy];
                    [strongSelf.pendingPickerThumbnailCallbacks removeObjectForKey:cacheKey];
                    for (id callback in finishedCallbacks) {
                        void (^block)(UIImage *) = callback;
                        block(loaded);
                    }
                });
            });
        }
    }
    cell.accessoryType = [item[@"fileName"] isEqualToString:self.currentItem[@"fileName"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSDictionary *> *items = self.visiblePickerItems;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)items.count) return;
    NSString *fileName = items[(NSUInteger)indexPath.row][@"fileName"];
    if (![fileName isKindOfClass:NSString.class] || !fileName.length) return;
    BOOL makeConstant = [CCBGModulePreference(@"playbackMode", @0) integerValue] == 0;
    UINavigationController *navigation = self.mediaPickerController.navigationController;
    void (^finishSelection)(void) = ^{
        [self clearMediaSelectionState];
        [self selectMediaNamed:fileName makeConstant:makeConstant];
    };
    if (navigation) [navigation dismissViewControllerAnimated:YES completion:finishSelection];
    else [self dismissViewControllerAnimated:YES completion:finishSelection];
}

- (void)selectMediaNamed:(NSString *)fileName { [self selectMediaNamed:fileName makeConstant:YES]; }

- (void)selectMediaNamed:(NSString *)fileName makeConstant:(BOOL)makeConstant {
    NSDictionary *selected = CCBGMediaItemNamed(self.mediaItems, fileName);
    if (!selected) {
        NSArray *catalog = CCBGMediaItemsForModule(CCBGLoadMediaCatalog(), CCBG_MODULE_SLOT);
        selected = CCBGMediaItemNamed(catalog, fileName);
        if (selected && CCBGMediaItemIsCurrentlyEligible(selected)) {
            NSMutableArray *queue = [self.mediaItems mutableCopy] ?: [NSMutableArray array];
            [queue addObject:selected];
            self.mediaItems = queue;
        } else {
            selected = nil;
        }
    }
    if (!selected) return;
    self.fallbackAttemptedFileName = nil;
    self.currentItem = selected;
    self.mediaIndex = [self.mediaItems indexOfObject:selected];
    self.suppressCurrentPersistence = NO;
    NSMutableDictionary *changes = [@{CCBGPreferenceKeyForModule(@"currentMedia", CCBG_MODULE_SLOT): fileName} mutableCopy];
    if (makeConstant) {
        changes[CCBGPreferenceKeyForModule(@"playbackMode", CCBG_MODULE_SLOT)] = @0;
        changes[CCBGPreferenceKeyForModule(@"selectedMedia", CCBG_MODULE_SLOT)] = fileName;
    }
    CCBGApplyQuickConfigurationChanges(changes, @"切换模块素材");
    CCBGSetCachedModulePreference(@"currentMedia", fileName);
    if (makeConstant) {
        CCBGSetCachedModulePreference(@"playbackMode", @0);
        CCBGSetCachedModulePreference(@"selectedMedia", fileName);
    }
    self.automationOverrideActive = NO;
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.layer.hidden = NO;
    self.view.layer.opacity = 1.0;
    [self showCurrentMediaWithTransition:YES];
    if (self.visible && self.player) {
        __weak typeof(self) weakSelf = self;
        AVPlayer *selectedPlayer = self.player;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.player != selectedPlayer) return;
            self.playerLayer.hidden = NO;
            [self.player play];
            self.player.rate = CCBGEffectivePlaybackRate(self.currentItem);
            [self convergeMountedPresentation:@"select-media"];
        });
    }
    [self convergeMountedPresentation:@"select-media"];
    [self scheduleMountedPresentationConvergence:@"select-media"];
}

- (BOOL)isCharging {
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

- (NSString *)currentEnvironmentSignature {
    NSArray<NSDictionary *> *items = self.mediaItems ?: @[];
    NSString *selection = [self automationSelectionForItems:items] ?: @"";
    NSDictionary *context = CCBGSceneContextForModule(self.view);
    NSString *sceneID = CCBGSceneDirectorResolvedScene(context)[@"id"] ?: @"";
    NSArray *names = [items valueForKey:@"fileName"] ?: @[];
    return [NSString stringWithFormat:@"%@|scene=%@|dark=%d|focus=%@|low=%d|charging=%d|locked=%d|landscape=%d|items=%@", selection, sceneID,
            [context[@"dark"] boolValue], context[@"focus"] ?: @"", NSProcessInfo.processInfo.lowPowerModeEnabled,
            [context[@"charging"] boolValue], [context[@"locked"] boolValue], [context[@"landscape"] boolValue],
            [names componentsJoinedByString:@","]];
}

- (void)environmentDidChange:(NSNotification *)notification {
    if (!self.visible || !self.view.window || !CCBGPluginEnabled()) return;
    BOOL orientationRefresh = [notification.name isEqualToString:CCBGModuleLayoutOrientationDidChangeNotification] ||
        [notification.name isEqualToString:UIDeviceOrientationDidChangeNotification];
    @synchronized (self) {
        self.pendingOrientationRefresh = self.pendingOrientationRefresh || orientationRefresh;
        if (self.environmentChangeScheduled) return;
        self.environmentChangeScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.visible || !self.view.window || !CCBGPluginEnabled()) return;
        BOOL needsOrientationRefresh = NO;
        @synchronized (self) {
            self.environmentChangeScheduled = NO;
            needsOrientationRefresh = self.pendingOrientationRefresh;
            self.pendingOrientationRefresh = NO;
        }
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        // Playback position is diagnostic/replay metadata, not a transport
        // checkpoint. Keep writes sparse so five visible modules do not
        // contend on the shared preference/analytics queues every few seconds.
        if (self.player.currentItem && now - self.lastRuntimePersistAt >= 30.0) {
            self.lastRuntimePersistAt = now;
            NSTimeInterval position = MAX(0.0, CMTimeGetSeconds(self.player.currentTime));
            NSTimeInterval duration = MAX(0.0, CMTimeGetSeconds(self.player.currentItem.duration));
            if (!isfinite(position)) position = 0; if (!isfinite(duration)) duration = 0;
            CCBGRecordModuleRuntimeState(CCBG_MODULE_SLOT, position, duration);
        }
        CCBGInvalidateSceneRuntimeCaches();
        NSDictionary *scene = CCBGSceneDirectorResolvedScene(CCBGSceneContextForModule(self.view));
        NSString *sceneID = [scene[@"id"] isKindOfClass:NSString.class] ? scene[@"id"] : @"";
        NSString *manualSceneID = CCBGReadPreference(@"sceneDirectorManualSceneID", @"");
        NSString *lastAutomaticSceneID = CCBGReadPreference(@"sceneDirectorLastAutomaticTimelineSceneID", @"");
        BOOL automaticSceneActive = !manualSceneID.length && sceneID.length;
        if (automaticSceneActive && ![sceneID isEqualToString:lastAutomaticSceneID]) {
            CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
            CFPreferencesSetAppValue(CFSTR("sceneDirectorLastAutomaticTimelineSceneID"), (__bridge CFStringRef)sceneID, domain);
            CFPreferencesAppSynchronize(domain);
            CCBGRecordSceneTimelineEvent(@"automatic-scene-hit", @{ @"sceneID": sceneID, @"name": scene[@"name"] ?: @"" });
        } else if (!automaticSceneActive && lastAutomaticSceneID.length) {
            CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
            CFPreferencesSetAppValue(CFSTR("sceneDirectorLastAutomaticTimelineSceneID"), NULL, domain);
            CFPreferencesAppSynchronize(domain);
        }
        NSString *signature = [self currentEnvironmentSignature];
        if ([self requiresMountedMediaReload] || ![signature isEqualToString:self.environmentSignature]) {
            [self reloadPreferencesAndMedia];
            [self reloadAfterFirstMountIfNeeded];
            [self convergeMountedPresentation:@"environment-change"];
            [self scheduleMountedPresentationConvergence:@"environment-change"];
            // A normal state notification is already authoritative. A second
            // full reload is only useful after rotation, when Control Center's
            // layout has not yet reached its final bounds.
            if (needsOrientationRefresh) [self scheduleEnvironmentRefresh];
        }
        if (needsOrientationRefresh) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf environmentDidChange:nil];
            });
        }
    });
}

- (void)scheduleEnvironmentRefresh {
    NSUInteger generation = ++self.environmentRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.environmentRefreshGeneration || !self.visible || !self.view.window || !CCBGPluginEnabled()) return;
        [self reloadPreferencesAndMedia];
        [self reloadAfterFirstMountIfNeeded];
        [self convergeMountedPresentation:@"environment-settled"];
        [self scheduleMountedPresentationConvergence:@"environment-settled"];
    });
}

- (void)startEnvironmentTimer {
    [self.environmentTimer invalidate];
    self.environmentTimer = nil;
    if (!self.visible || !self.view.window || !CCBGPluginEnabled()) return;
    __weak typeof(self) weakSelf = self;
    self.environmentTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.visible || !self.view.window || !CCBGPluginEnabled()) {
            [timer invalidate];
            if (self) self.environmentTimer = nil;
            return;
        }
        [self environmentDidChange:nil];
    }];
    self.environmentTimer.tolerance = 5.0;
}

- (NSArray<NSDictionary *> *)eligibleItems:(NSArray<NSDictionary *> *)catalog {
    BOOL chargingOnlyVideo = [CCBGModulePreference(@"chargingOnlyVideo", @NO) boolValue];
    BOOL lowPowerStatic = [CCBGModulePreference(@"lowPowerStatic", @NO) boolValue];
    BOOL suppressVideo = (chargingOnlyVideo && ![self isCharging]) ||
        ((lowPowerStatic || [CCBGModulePreference(@"performanceMode", @NO) boolValue]) && NSProcessInfo.processInfo.lowPowerModeEnabled);
    BOOL deferFileValidation = !CCBGMediaDirectoryIsReadable();
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *item in CCBGMediaItemsForModule(catalog, CCBG_MODULE_SLOT)) {
        if (!CCBGMediaItemIsCurrentlyEligible(item)) continue;
        if ([CCBGModulePreference(@"favoritesOnly", @NO) boolValue] && ![item[@"favorite"] boolValue]) continue;
        NSString *path = CCBGPathForItem(item);
        if (!deferFileValidation && ![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        if (suppressVideo && CCBGIsVideoName(item[@"fileName"])) continue;
        [result addObject:item];
    }
    return result;
}

- (NSArray<NSDictionary *> *)playbackQueueForItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSDictionary *> *result = [items mutableCopy] ?: [NSMutableArray array];
    NSInteger minutes = [NSCalendar.currentCalendar component:NSCalendarUnitHour fromDate:NSDate.date] * 60
        + [NSCalendar.currentCalendar component:NSCalendarUnitMinute fromDate:NSDate.date];
    NSString *scheduledGroup = nil;
    NSArray *schedules = CCBGModulePreference(@"scheduledPlaylists", @[]);
    if ([schedules isKindOfClass:NSArray.class]) {
        for (NSDictionary *schedule in schedules) {
            if (![schedule isKindOfClass:NSDictionary.class] || ![schedule[@"enabled"] boolValue]) continue;
            NSInteger start = [schedule[@"startMinutes"] integerValue];
            NSInteger end = [schedule[@"endMinutes"] integerValue];
            BOOL active = start <= end ? (minutes >= start && minutes < end) : (minutes >= start || minutes < end);
            if (active && [schedule[@"group"] isKindOfClass:NSString.class]) { scheduledGroup = schedule[@"group"]; break; }
        }
    }
    if (scheduledGroup.length) {
        NSIndexSet *remove = [result indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return ![item[@"group"] isEqualToString:scheduledGroup];
        }];
        [result removeObjectsAtIndexes:remove];
    }
    NSArray *playlist = CCBGModulePreference(@"playlist", @[]);
    if ([playlist isKindOfClass:NSArray.class] && playlist.count) {
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSString *name in playlist) {
            NSDictionary *item = CCBGMediaItemNamed(result, name);
            if (item) [ordered addObject:item];
        }
        return ordered;
    }
    return result;
}

- (NSInteger)randomMediaIndexExcludingCurrent {
    if (!self.mediaItems.count) return NSNotFound;
    NSMutableArray<NSNumber *> *candidateIndexes = [NSMutableArray array];
    double totalWeight = 0.0;
    NSInteger noRepeatCount = MAX(0, [CCBGModulePreference(@"noRepeatCount", @3) integerValue]);
    NSArray *recent = CCBGModulePreference(@"recentMedia", @[]);
    NSSet *blocked = [NSSet setWithArray:[recent isKindOfClass:NSArray.class] ? [recent subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)noRepeatCount, recent.count))] : @[]];
    for (NSUInteger index = 0; index < self.mediaItems.count; index++) {
        if (self.mediaItems.count > 1 && index == self.mediaIndex) continue;
        if ([blocked containsObject:self.mediaItems[index][@"fileName"]]) continue;
        double weight = MIN(10.0, MAX(0.1, [self.mediaItems[index][@"randomWeight"] doubleValue]));
        totalWeight += weight;
        [candidateIndexes addObject:@(index)];
    }
    if (!candidateIndexes.count) {
        for (NSUInteger index = 0; index < self.mediaItems.count; index++) {
            if (self.mediaItems.count == 1 || index != self.mediaIndex) [candidateIndexes addObject:@(index)];
        }
        totalWeight = candidateIndexes.count;
    }
    if (!candidateIndexes.count || totalWeight <= 0.0) return self.mediaIndex;
    double target = ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * totalWeight;
    for (NSNumber *candidate in candidateIndexes) {
        NSInteger index = candidate.integerValue;
        target -= MIN(10.0, MAX(0.1, [self.mediaItems[index][@"randomWeight"] doubleValue]));
        if (target <= 0.0) return index;
    }
    return candidateIndexes.lastObject.integerValue;
}

- (NSString *)automationSelectionForItems:(NSArray<NSDictionary *> *)items {
    NSDictionary *sceneContext = CCBGSceneContextForModule(self.view);
    NSString *sceneMedia = CCBGSceneDirectorMediaForTarget([NSString stringWithFormat:@"module%ld", (long)CCBG_MODULE_SLOT], sceneContext);
    if (CCBGMediaItemNamed(items, sceneMedia)) return sceneMedia;
    BOOL locked = CCBGSystemIsLocked();
    if (locked && [CCBGModulePreference(@"privacyEnabled", @NO) boolValue]) {
        NSString *privacy = CCBGModulePreference(@"privacyMedia", @"");
        if (CCBGMediaItemNamed(items, privacy)) return privacy;
    }
    NSArray *rules = CCBGModulePreference(@"compoundRules", @[]);
    if ([rules isKindOfClass:NSArray.class]) {
        rules = [rules sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"priority"] compare:left[@"priority"]];
        }];
        NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:NSDate.date];
        NSInteger minute = components.hour * 60 + components.minute;
        for (NSDictionary *rule in rules) {
            if (![rule isKindOfClass:NSDictionary.class] || ![rule[@"enabled"] boolValue]) continue;
            NSInteger dark = [rule[@"dark"] integerValue];
            NSInteger charging = [rule[@"charging"] integerValue];
            NSInteger lowPower = [rule[@"lowPower"] integerValue];
            if (dark >= 0 && (BOOL)dark != [sceneContext[@"dark"] boolValue]) continue;
            if (charging >= 0 && (BOOL)charging != [self isCharging]) continue;
            if (lowPower >= 0 && (BOOL)lowPower != NSProcessInfo.processInfo.lowPowerModeEnabled) continue;
            NSArray *weekdays = rule[@"weekdays"];
            if ([weekdays isKindOfClass:NSArray.class] && weekdays.count && ![weekdays containsObject:@(components.weekday)]) continue;
            NSInteger start = [rule[@"startMinutes"] integerValue];
            NSInteger end = [rule[@"endMinutes"] integerValue];
            if (end > 0) {
                BOOL active = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end);
                if (!active) continue;
            }
            NSString *media = rule[@"media"];
            if (CCBGMediaItemNamed(items, media)) return media;
        }
    }
    if ([CCBGModulePreference(@"darkModeAutomationEnabled", @NO) boolValue]) {
        NSString *key = [sceneContext[@"dark"] boolValue] ? @"darkModeMedia" : @"lightModeMedia";
        NSString *name = CCBGModulePreference(key, @"");
        if (CCBGMediaItemNamed(items, name)) return name;
    }
    return CCBGAutomationMediaName(items, [self isCharging], CCBG_MODULE_SLOT);
}

- (void)reloadPreferencesAndMedia {
    self.pendingManualAdvanceOffset = 0;
    NSDictionary *previousItem = self.currentItem;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"reload-start", @{@"hadCurrent": @(previousItem != nil)});
    CCBGRefreshModulePreferenceSnapshot();
    BOOL forcePreferenceMedia = [CCBGModulePreference(@"forcePreferenceMediaOnReload", @NO) boolValue];
    if (forcePreferenceMedia) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", CCBG_MODULE_SLOT), NULL, domain);
        CFPreferencesAppSynchronize(domain);
        CCBGSetCachedModulePreference(@"forcePreferenceMediaOnReload", nil);
    }
    if (![self applyPluginEnabledState]) {
        self.lastPreferencesReloadAt = NSDate.date.timeIntervalSince1970;
        return;
    }
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.layer.hidden = NO;
    self.view.layer.opacity = 1.0;
    CCBGMigrateLegacyAutomationPreferences();
    [self applyModuleAppearance];
    NSString *currentName = self.currentItem[@"fileName"];
    NSArray<NSDictionary *> *catalog = CCBGLoadMediaCatalog();
    if (!CCBGMediaDirectoryIsReadable()) {
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"reload-no-media-directory", nil);
        return;
    }
    if (!catalog.count && self.currentItem && [[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(self.currentItem)]) return;
    NSArray<NSDictionary *> *eligible = [self eligibleItems:catalog];
    // A fixed selection is an explicit module choice, not a playlist item.
    // Applying the playlist filter here used to make a stale one-item playlist
    // win over a newly selected video (most visible on the 3x3 slot), because
    // the later selected/current lookup only searched this already-filtered
    // queue.  Keep playlists for sequential/random playback only.
    NSInteger mode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));
    NSArray<NSDictionary *> *queue = mode == 0 ? eligible : [self playbackQueueForItems:eligible];
    if (!queue.count) queue = eligible;
    if (!queue.count && previousItem) {
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"reload-kept-previous", nil);
        return;
    }
    self.mediaItems = queue;
    self.mediaIndex = 0;
    self.currentItem = nil;

    NSString *selection = nil;
    NSString *automationSelection = [self automationSelectionForItems:eligible];
    NSString *overrideSelection = automationSelection;
    if (!overrideSelection.length) {
        BOOL landscape = CCBGCurrentInterfaceIsLandscape(self.view);
        NSString *orientationMedia = CCBGModulePreference(landscape ? @"landscapeMedia" : @"portraitMedia", @"");
        if (CCBGMediaItemNamed(eligible, orientationMedia)) overrideSelection = orientationMedia;
    }
    self.hasLoadedPreferences = YES;
    self.automationOverrideActive = overrideSelection.length > 0;

    NSString *selectedMedia = CCBGModulePreference(@"selectedMedia", @"");
    NSString *rememberedCurrentMedia = CCBGModulePreference(@"currentMedia", currentName ?: @"");
    NSString *baseSelection = mode == 0 && selectedMedia.length ? selectedMedia : rememberedCurrentMedia;
    selection = overrideSelection.length ? overrideSelection : baseSelection;

    if (mode == 0) {
        if (!overrideSelection.length && !selectedMedia.length && CCBGMediaItemNamed(eligible, rememberedCurrentMedia)) {
            CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
            CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"selectedMedia", CCBG_MODULE_SLOT), (__bridge CFStringRef)rememberedCurrentMedia, domain);
            CFPreferencesAppSynchronize(domain);
            CCBGSetCachedModulePreference(@"selectedMedia", rememberedCurrentMedia);
        }
    }
    if (!selection.length && mode != 0 && forcePreferenceMedia) {
        NSString *preferredCurrentMedia = CCBGModulePreference(@"currentMedia", @"");
        if (CCBGMediaItemNamed(self.mediaItems, preferredCurrentMedia)) selection = preferredCurrentMedia;
    }
    if (!selection.length && mode != 0 && CCBGMediaItemNamed(self.mediaItems, currentName)) selection = currentName;
    if (!selection.length && [CCBGModulePreference(@"rememberLast", @YES) boolValue]) {
        selection = CCBGModulePreference(@"currentMedia", currentName ?: @"");
    }
    if (!selection.length && mode != 0) selection = overrideSelection;
    if (!selection.length) selection = currentName;

    // A direct selection in sequential/random mode may intentionally point
    // outside an older playlist or scheduled group. Keep that explicit item
    // as the current queue entry instead of silently falling back to the
    // queue's first video; the next advance still follows the configured
    // playlist order.
    if (!overrideSelection.length && selection.length && !CCBGMediaItemNamed(self.mediaItems, selection)) {
        NSDictionary *preferred = CCBGMediaItemNamed(eligible, selection);
        if (preferred) {
            NSMutableArray *expandedQueue = [self.mediaItems mutableCopy] ?: [NSMutableArray array];
            [expandedQueue insertObject:preferred atIndex:0];
            self.mediaItems = expandedQueue;
        }
    }

    NSDictionary *selected = CCBGMediaItemNamed(self.mediaItems, selection);
    if (!selected && overrideSelection.length && [selection isEqualToString:overrideSelection]) {
        selected = CCBGMediaItemNamed(eligible, selection);
        if (selected) {
            NSMutableArray *expandedQueue = [self.mediaItems mutableCopy] ?: [NSMutableArray array];
            [expandedQueue insertObject:selected atIndex:0];
            self.mediaItems = expandedQueue;
        }
    }
    if (selected) {
        self.currentItem = selected;
        self.mediaIndex = [self.mediaItems indexOfObject:selected];
    } else if (self.mediaItems.count) {
        self.currentItem = self.mediaItems[0];
    }

    if (self.currentItem) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        BOOL updatedPreferences = NO;
        if (!CCBGModulePreference(@"moduleOpacity", nil)) {
            NSNumber *opacity = @(MIN(1.0, MAX(0.05, [self.currentItem[@"opacity"] doubleValue])));
            CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"moduleOpacity", CCBG_MODULE_SLOT), (__bridge CFPropertyListRef)opacity, domain);
            CCBGSetCachedModulePreference(@"moduleOpacity", opacity);
            updatedPreferences = YES;
        }
        if (!CCBGModulePreference(@"moduleBlurIntensity", nil)) {
            NSNumber *blur = @(MIN(1.0, MAX(0.0, [self.currentItem[@"blurIntensity"] doubleValue])));
            CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"moduleBlurIntensity", CCBG_MODULE_SLOT), (__bridge CFPropertyListRef)blur, domain);
            CCBGSetCachedModulePreference(@"moduleBlurIntensity", blur);
            updatedPreferences = YES;
        }
        if (updatedPreferences) CFPreferencesAppSynchronize(domain);
    }

    [self applyFallbackColor];
    // preferredContentSize belongs to the expanded Control Center host. A
    // compact playlist swap must not change it and trigger a host relayout.
    if (self.currentItem && self.expanded) [self updateAdaptiveExpandedSizeForItem:self.currentItem];
    if (CCBGPresentationItemsEqual(previousItem, self.currentItem) && self.player.currentItem) {
        [self applyDisplayForItem:self.currentItem];
        [self configureSlideshow];
        [self updateNativePlayerPresentation];
        [self updateExpandedCaption];
        [self resumeVideoPlaybackIfNeeded];
    } else {
        [self showCurrentMediaWithTransition:NO];
    }
    self.environmentSignature = [self currentEnvironmentSignature];
    self.lastPreferencesReloadAt = NSDate.date.timeIntervalSince1970;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"reload-finished", @{
        @"catalog": @(catalog.count),
        @"queue": @(queue.count),
        @"hasCurrent": @(self.currentItem != nil),
        @"viewHidden": @(self.view.hidden),
        @"window": @(self.view.window != nil),
        @"forced": @(forcePreferenceMedia),
        @"previous": currentName ?: @"",
        @"selected": self.currentItem[@"fileName"] ?: @"",
        @"preferenceCurrent": CCBGModulePreference(@"currentMedia", @"")
    });
    [self convergeMountedPresentation:@"reload-finished"];
}

- (void)applyFallbackColor {
    NSString *hex = CCBGModulePreference(@"fallbackColor", @"#193d61");
    unsigned value = 0x193d61;
    NSScanner *scanner = [NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]];
    [scanner scanHexInt:&value];
    UIColor *backgroundColor = [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0
                                               green:((value >> 8) & 0xff) / 255.0
                                                blue:(value & 0xff) / 255.0
                                               alpha:1.0];
    NSInteger tintTarget = MIN(2, MAX(0, [CCBGModulePreference(@"dynamicTintTarget", @0) integerValue]));
    if (tintTarget == 1 || tintTarget == 2) {
        UIColor *dynamicColor = CCBGResolvedDynamicPaletteColor(self.view,
            [CCBGModulePreference(@"foregroundAppTintEnabled", @NO) boolValue],
            [CCBGModulePreference(@"wallpaperTintEnabled", @NO) boolValue]);
        backgroundColor = CCBGBlendModuleColor(backgroundColor, dynamicColor,
            [CCBGModulePreference(@"dynamicTintStrength", @0.65) doubleValue]);
    }
    // The original default blue makes expanded media look like a dark frame
    // around a separate black card. Keep explicit user colors intact, but use
    // a restrained glass-neutral surface for the default expanded state.
    NSString *normalizedHex = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] lowercaseString];
    if (self.expanded && self.currentItem &&
        (!normalizedHex.length || [normalizedHex isEqualToString:@"193d61"])) {
        backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.58];
    }
    self.view.backgroundColor = backgroundColor;
}

- (void)applyDisplayForItem:(NSDictionary *)item {
    NSInteger contentMode = [item[@"contentMode"] integerValue];
    NSString *presentationKey = self.expanded ? @"expandedContentMode" : @"compactContentMode";
    id presentationValue = item[presentationKey];
    NSInteger presentationMode = [presentationValue respondsToSelector:@selector(integerValue)] ? [presentationValue integerValue] : -1;
    BOOL hasExplicitPresentationMode = presentationMode >= 0;
    if (hasExplicitPresentationMode) contentMode = MIN(1, MAX(0, presentationMode));
    BOOL landscape = CCBGCurrentInterfaceIsLandscape(self.view);
    NSString *orientationKey = landscape ? @"landscapeContentMode" : @"portraitContentMode";
    id orientationValue = item[orientationKey];
    NSInteger orientationMode = [orientationValue respondsToSelector:@selector(integerValue)] ? [orientationValue integerValue] : -1;
    BOOL hasExplicitOrientationMode = orientationMode >= 0;
    if (hasExplicitOrientationMode) contentMode = MIN(1, MAX(0, orientationMode));
    // Expanded Clean modules use the ios16dao-style complete frame by
    // default. An explicit expanded/orientation mode still wins, so users
    // who intentionally chose fill/crop keep that choice.
    NSInteger configuredExpandedMode = MIN(2, MAX(0, [CCBGModulePreference(@"expandedDisplayMode", @0) integerValue]));
    if (self.expanded && configuredExpandedMode > 0) contentMode = configuredExpandedMode == 2 ? 1 : 0;
    else if (self.expanded && !hasExplicitPresentationMode && !hasExplicitOrientationMode) contentMode = 0;
    self.imageView.contentMode = contentMode == 0 ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    self.playerLayer.videoGravity = contentMode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    self.nativePlayerController.videoGravity = contentMode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    NSString *blurKey = (self.expanded && [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue]) ? @"expandedBlurIntensity" : @"moduleBlurIntensity";
    CGFloat blur = [CCBGModulePreference(@"blurEnabled", @YES) boolValue]
        ? [CCBGModulePreference(blurKey, @0.0) doubleValue] : 0.0;
    if (CCBGSystemIsLocked() && [CCBGModulePreference(@"privacyEnabled", @NO) boolValue]) {
        blur = MAX(blur, [CCBGModulePreference(@"privacyBlur", @0.7) doubleValue]);
    }
    NSDictionary *sceneContext = CCBGSceneContextForModule(self.view);
    self.displayedBlurIntensity = @(MIN(1.0, MAX(0.0, blur)));
    [self applyBlurIntensity:blur];
    CGFloat maskDim = [CCBGModulePreference(@"moduleMaskDim", @0) doubleValue];
    self.dimView.alpha = MIN(0.9, MAX(0.0, [item[@"dim"] doubleValue] + maskDim));
    NSString *opacityKey = (self.expanded && [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue]) ? @"expandedOpacity" : @"moduleOpacity";
    CGFloat opacity = MIN(1.0, MAX(0.05, [CCBGModulePreference(opacityKey, @1.0) doubleValue]));
    NSInteger expandedSlot = CCBGSceneDirectorExpandedSlot();
    if (expandedSlot >= 0 && expandedSlot != CCBG_MODULE_SLOT && CCBGSceneDirectorBreathingGridEnabled(sceneContext)) {
        opacity *= 0.70;
        self.dimView.alpha = MIN(0.9, self.dimView.alpha + 0.16);
    }
    self.displayedOpacity = @(opacity);
    self.imageView.alpha = opacity;
    self.playerLayer.opacity = opacity;
    self.nativePlayerController.view.alpha = opacity;
    CGFloat focalX = MIN(1.0, MAX(0.0, [item[@"focalX"] doubleValue]));
    CGFloat focalY = MIN(1.0, MAX(0.0, [item[@"focalY"] doubleValue]));
    CGFloat orientationX = [item[landscape ? @"landscapeFocalX" : @"portraitFocalX"] doubleValue];
    CGFloat orientationY = [item[landscape ? @"landscapeFocalY" : @"portraitFocalY"] doubleValue];
    if (orientationX >= 0) focalX = MIN(1.0, orientationX);
    if (orientationY >= 0) focalY = MIN(1.0, orientationY);
    CGFloat presentationX = [item[self.expanded ? @"expandedFocalX" : @"compactFocalX"] doubleValue];
    CGFloat presentationY = [item[self.expanded ? @"expandedFocalY" : @"compactFocalY"] doubleValue];
    if (presentationX >= 0) focalX = MIN(1.0, presentationX);
    if (presentationY >= 0) focalY = MIN(1.0, presentationY);
    CGFloat cropZoom = MIN(2.5, MAX(1.0, [item[self.expanded ? @"expandedCropZoom" : @"compactCropZoom"] doubleValue]));
    NSDictionary *scene = CCBGSceneDirectorResolvedScene(sceneContext);
    if ([scene[@"adaptiveCompositionEnabled"] boolValue] && self.view.window && contentMode != 0) {
        CGRect windowBounds = self.view.window.bounds;
        CGRect moduleRect = [self.view convertRect:self.view.bounds toView:self.view.window];
        if (CGRectGetWidth(windowBounds) > 1.0 && CGRectGetHeight(windowBounds) > 1.0) {
            focalX = MIN(1.0, MAX(0.0, CGRectGetMidX(moduleRect) / CGRectGetWidth(windowBounds)));
            focalY = MIN(1.0, MAX(0.0, CGRectGetMidY(moduleRect) / CGRectGetHeight(windowBounds)));
        }
    }
    CGAffineTransform transform = CGAffineTransformIdentity;
    if (contentMode != 0 || cropZoom > 1.001) {
        CGFloat dx = (0.5 - focalX) * self.imageView.bounds.size.width * 0.18;
        CGFloat dy = (0.5 - focalY) * self.imageView.bounds.size.height * 0.18;
        CGFloat scale = (contentMode != 0 ? 1.12 : 1.0) * cropZoom;
        transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), CGAffineTransformMakeTranslation(dx, dy));
    }
    [UIView performWithoutAnimation:^{
        self.imageView.layer.contentsRect = CGRectMake(0, 0, 1, 1);
        self.imageView.transform = transform;
    }];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.contentsRect = CGRectMake(0, 0, 1, 1);
    [self.playerLayer setAffineTransform:transform];
    [CATransaction commit];
}

- (UIImage *)filteredImageAtPath:(NSString *)path item:(NSDictionary *)item {
    UIImage *source = [self.preloadedFileName isEqualToString:item[@"fileName"]] ? self.preloadedImage : nil;
    if (!source && [path.pathExtension.lowercaseString isEqualToString:@"gif"] && ![CCBGModulePreference(@"performanceMode", @NO) boolValue]) {
        CGImageSourceRef sourceRef = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        size_t count = sourceRef ? CGImageSourceGetCount(sourceRef) : 0;
        NSMutableArray *frames = [NSMutableArray array];
        NSTimeInterval duration = 0;
        for (size_t index = 0; index < count; index++) {
            CGImageRef frame = CGImageSourceCreateImageAtIndex(sourceRef, index, NULL);
            if (!frame) continue;
            [frames addObject:[UIImage imageWithCGImage:frame]];
            CGImageRelease(frame);
            duration += 0.1;
        }
        if (sourceRef) CFRelease(sourceRef);
        if (frames.count) source = [UIImage animatedImageWithImages:frames duration:MAX(0.1, duration)];
    }
    if (!source) source = [UIImage imageWithContentsOfFile:path];
    if (!source.CIImage && !source.CGImage) return source;
    CGFloat saturation = [item[@"saturation"] doubleValue];
    CGFloat contrast = [item[@"contrast"] doubleValue];
    if (fabs(saturation - 1.0) < 0.01 && fabs(contrast - 1.0) < 0.01) return source;
    CIImage *input = source.CIImage ?: [CIImage imageWithCGImage:source.CGImage];
    CIFilter *filter = [CIFilter filterWithName:@"CIColorControls"];
    [filter setValue:input forKey:kCIInputImageKey];
    [filter setValue:@(saturation) forKey:kCIInputSaturationKey];
    [filter setValue:@(contrast) forKey:kCIInputContrastKey];
    CIImage *output = filter.outputImage;
    CGImageRef image = [self.ciContext createCGImage:output fromRect:output.extent];
    if (!image) return source;
    UIImage *result = [UIImage imageWithCGImage:image scale:source.scale orientation:source.imageOrientation];
    CGImageRelease(image);
    return result;
}

- (void)stopPlayback {
    [self recordActivePlaybackDurationIfNeeded];
    self.handlingVideoBoundary = NO;
    self.playbackInstallGeneration++;
    self.sceneSmartCoverGeneration++;
    self.sceneLowPowerCoverActive = NO;
    if (self.timeObserver && self.player) {
        [self.player removeTimeObserver:self.timeObserver];
    }
    self.timeObserver = nil;
    [self.videoWatchdog invalidate];
    self.videoWatchdog = nil;
    if (self.player.currentItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.player.currentItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.player.currentItem];
    }
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.nativePlayerController.player = nil;
    self.nativePlayerController.view.hidden = YES;
    self.nativePresentationFallbackVisible = NO;
    self.lastNativePresentationStateSignature = nil;
}

- (void)recordSuccessfulMediaStartIfNeeded {
    if (self.healthStartRecorded || !self.currentItem[@"fileName"]) return;
    self.healthStartRecorded = YES;
    NSString *fileName = [self.currentItem[@"fileName"] copy];
    self.videoFailureFileName = nil;
    self.videoFailureRebuildCount = 0;
    NSTimeInterval latency = MAX(0.0, NSProcessInfo.processInfo.systemUptime - self.mediaPresentationStartedAt);
    self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
    self.healthPlaybackFileName = fileName;
    CCBGRecordMediaPlaybackStart(fileName, CCBG_MODULE_SLOT, latency);
}

- (void)recordActivePlaybackDurationIfNeeded {
    NSString *fileName = self.healthPlaybackFileName;
    NSTimeInterval startedAt = self.healthPlaybackStartedAt;
    self.healthPlaybackStartedAt = 0;
    self.healthPlaybackFileName = nil;
    if (!fileName.length || startedAt <= 0) return;
    NSTimeInterval duration = MAX(0.0, NSProcessInfo.processInfo.systemUptime - startedAt);
    if (duration < 0.25) return;
    CCBGRecordMediaPlaybackDuration(fileName, duration);
}

- (void)mediaMemoryWarning:(NSNotification *)notification {
    [self clearPreloadedNextMedia];
    [self.pickerThumbnailCache removeAllObjects];
    [self.pendingPickerThumbnailCallbacks removeAllObjects];
    NSString *fileName = [self.currentItem[@"fileName"] copy];
    if (!fileName.length) return;
    CCBGRecordMediaMemoryPressure(fileName);
}

- (BOOL)shouldUseSceneLowPowerCover {
    return NSProcessInfo.processInfo.lowPowerModeEnabled &&
        CCBGIsVideoName(self.currentItem[@"fileName"]) &&
        CCBGSceneDirectorLowPowerStatic(CCBGSceneContextForModule(self.view));
}

- (void)generateSceneSmartCoverAtTime:(NSTimeInterval)time {
    NSDictionary *item = [self.currentItem copy];
    if (!CCBGIsVideoName(item[@"fileName"])) return;
    NSUInteger generation = ++self.sceneSmartCoverGeneration;
    AVAsset *asset = self.player.currentItem.asset ?: [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:CCBGPathForItem(item)] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(480, 480);
        generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.12, 600);
        generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.12, 600);
        CGImageRef frame = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(MAX(0.0, time), 600) actualTime:nil error:nil];
        UIImage *cover = frame ? [UIImage imageWithCGImage:frame] : nil;
        if (frame) CGImageRelease(frame);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!cover || generation != self.sceneSmartCoverGeneration || !self.sceneLowPowerCoverActive || ![self.currentItem[@"fileName"] isEqualToString:item[@"fileName"]]) return;
            self.imageView.image = cover;
            self.imageView.hidden = NO;
        });
    });
}

- (void)activateSceneLowPowerCoverIfNeeded {
    if (![self shouldUseSceneLowPowerCover]) return;
    NSTimeInterval position = CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval start = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
    if (!isfinite(position) || position < start) position = start;
    if (!self.sceneLowPowerCoverActive) {
        self.sceneLowPowerCoverActive = YES;
        [self recordActivePlaybackDurationIfNeeded];
        [self generateSceneSmartCoverAtTime:position];
    }
    [self.player pause];
    [self.videoWatchdog invalidate];
    self.videoWatchdog = nil;
    self.playerLayer.hidden = YES;
    self.nativePlayerController.view.hidden = YES;
    self.imageView.hidden = NO;
}

- (void)restoreSceneLowPowerPlaybackIfNeeded {
    if (!self.sceneLowPowerCoverActive || [self shouldUseSceneLowPowerCover]) return;
    self.sceneLowPowerCoverActive = NO;
    self.playerLayer.hidden = NO;
    [self updateNativePlayerPresentation];
    if (!self.healthStartRecorded) self.mediaPresentationStartedAt = NSProcessInfo.processInfo.systemUptime;
    if (self.healthStartRecorded) {
        self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
        self.healthPlaybackFileName = [self.currentItem[@"fileName"] copy];
    }
}

- (void)startVideoPlaybackWhenReadyForItem:(AVPlayerItem *)playerItem attempt:(NSUInteger)attempt {
    if (!playerItem || self.player.currentItem != playerItem) return;
    if ([self shouldUseSceneLowPowerCover]) {
        [self activateSceneLowPowerCoverIfNeeded];
        return;
    }
    if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
        [self.player playImmediatelyAtRate:CCBGEffectivePlaybackRate(self.currentItem)];
        [self revealVideoWhenReadyForItem:playerItem attempt:0];
        return;
    }
    if (playerItem.status == AVPlayerItemStatusFailed) {
        [self handleVideoPlaybackFailureForItem:playerItem reason:playerItem.error.localizedDescription ?: @"视频无法解码"];
        return;
    }
    if (attempt >= 100) {
        [self handleVideoPlaybackFailureForItem:playerItem reason:@"视频准备超时"];
        return;
    }
    NSTimeInterval delay = attempt < 10 ? 0.03 : 0.1;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf startVideoPlaybackWhenReadyForItem:playerItem attempt:attempt + 1];
    });
}

- (void)revealVideoWhenReadyForItem:(AVPlayerItem *)playerItem attempt:(NSUInteger)attempt {
    if (!playerItem || self.player.currentItem != playerItem) return;
    if (self.sceneLowPowerCoverActive) return;
    // In expanded mode AVPlayerViewController sits below the temporary cover
    // image. The compact AVPlayerLayer may stay non-displayable while hidden,
    // so it cannot be the authority for removing that cover.
    // UIKit may hide the child view briefly while Control Center finishes its
    // expansion animation. Player ownership is the stable signal here; the
    // recovery path below makes the native view visible again when ready.
    if (self.expanded && playerItem.status == AVPlayerItemStatusReadyToPlay) {
        // Expansion and AVAsset readiness can complete in either order. Make
        // the native child authoritative here even when it was not created by
        // the earlier transition callback or was temporarily detached.
        [self updateNativePlayerPresentation];
        if (self.nativePlayerController.player == self.player && !self.nativePlayerController.view.hidden) {
            self.imageView.hidden = YES;
            [self recordSuccessfulMediaStartIfNeeded];
            return;
        }
    }
    if (self.playerLayer.readyForDisplay) {
        [self recordSuccessfulMediaStartIfNeeded];
        self.imageView.hidden = YES;
        return;
    }
    self.imageView.hidden = NO;
    if (attempt == 12 || attempt == 28) {
        [self recoverPlayerLayerSurfaceIfNeededForItem:playerItem reason:[NSString stringWithFormat:@"not-ready-%lu", (unsigned long)attempt]];
    }
    if (attempt >= 60) {
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-layer-not-ready", @{
            @"current": self.currentItem[@"fileName"] ?: @"",
            @"status": @(playerItem.status),
            @"time": @(CMTimeGetSeconds(self.player.currentTime)),
            @"bounds": NSStringFromCGRect(self.view.bounds),
        });
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf revealVideoWhenReadyForItem:playerItem attempt:attempt + 1];
    });
}

- (void)recoverPlayerLayerSurfaceIfNeededForItem:(AVPlayerItem *)playerItem reason:(NSString *)reason {
    BOOL forcedStallRecovery = [reason hasPrefix:@"stalled-"];
    BOOL layerAttached = self.playerLayer && self.playerLayer.superlayer == self.view.layer;
    if (!playerItem || self.player.currentItem != playerItem ||
        (layerAttached && self.playerLayer.readyForDisplay && !forcedStallRecovery)) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - self.lastPlayerLayerRecoveryAt < 0.75) return;
    self.lastPlayerLayerRecoveryAt = now;
    CGRect frame = self.playerLayer.frame;
    BOOL hidden = self.playerLayer.hidden;
    float opacity = self.playerLayer.opacity;
    AVLayerVideoGravity gravity = self.playerLayer.videoGravity ?: AVLayerVideoGravityResizeAspectFill;
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = CGRectIsEmpty(frame) ? CGRectInset(self.view.bounds, MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue])), MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue]))) : frame;
    self.playerLayer.masksToBounds = YES;
    CCBGApplyAllMediaCorners(self.view, @[self.imageView, self.dynamicTintView, self.blurView, self.dimView], self.playerLayer, self.nativePlayerController.view);
    self.playerLayer.hidden = hidden;
    self.playerLayer.opacity = opacity;
    self.playerLayer.videoGravity = gravity;
    [self.view.layer insertSublayer:self.playerLayer atIndex:0];
    [self applyDisplayForItem:self.currentItem];
    [self updateNativePlayerPresentation];
    [self resumeVideoPlaybackIfNeeded];
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"player-layer-recovered", @{
        @"reason": reason ?: @"",
        @"current": self.currentItem[@"fileName"] ?: @"",
        @"bounds": NSStringFromCGRect(self.view.bounds),
    });
}

- (void)startVideoWatchdogForItem:(AVPlayerItem *)playerItem {
    [self.videoWatchdog invalidate];
    self.videoWatchdog = nil;
    if (!playerItem || self.player.currentItem != playerItem || !CCBGIsVideoName(self.currentItem[@"fileName"])) return;
    NSString *fileName = self.currentItem[@"fileName"] ?: @"";
    if (![self.videoStallFileName isEqualToString:fileName]) {
        self.videoStallFileName = fileName;
        self.videoStallRecoveryCount = 0;
    }
    self.lastObservedPlayerTime = NAN;
    self.lastVideoProgressAt = NSProcessInfo.processInfo.systemUptime;
    __weak typeof(self) weakSelf = self;
    self.videoWatchdog = [NSTimer scheduledTimerWithTimeInterval:0.75 repeats:YES block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.visible || !self.view.window || self.player.currentItem != playerItem) return;
        [self observeVideoProgressForItem:playerItem time:CMTimeGetSeconds(self.player.currentTime)];
    }];
    self.videoWatchdog.tolerance = 0.15;
}

- (void)observeVideoProgressForItem:(AVPlayerItem *)playerItem time:(NSTimeInterval)time {
    if (!playerItem || self.player.currentItem != playerItem || !isfinite(time)) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    BOOL advanced = !isfinite(self.lastObservedPlayerTime) || fabs(time - self.lastObservedPlayerTime) > 0.015;
    self.lastObservedPlayerTime = time;
    if (advanced) {
        self.lastVideoProgressAt = now;
        if (self.lastVideoStallRecoveryAt <= 0 || now - self.lastVideoStallRecoveryAt >= 1.0) {
            self.videoStallRecoveryCount = 0;
        }
        return;
    }
    BOOL shouldBePlaying = self.player.rate > 0.01 || self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying || self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
    if (shouldBePlaying && now - self.lastVideoProgressAt >= 1.8) [self recoverVideoPlaybackStallForItem:playerItem];
}

- (void)recoverVideoPlaybackStallForItem:(AVPlayerItem *)playerItem {
    if (!self.visible || !self.view.window || self.player.currentItem != playerItem) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - self.lastVideoStallRecoveryAt < 1.5) return;
    self.lastVideoStallRecoveryAt = now;
    self.videoStallRecoveryCount += 1;
    if (self.videoStallRecoveryCount >= 2) {
        NSString *path = CCBGPathForItem(self.currentItem);
        CCBGInvalidateVideoOnlyAssetMemoryCache(path);
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-stall-player-rebuilt", @{
            @"current": self.currentItem[@"fileName"] ?: @"",
            @"position": @(CMTimeGetSeconds(self.player.currentTime)),
        });
        self.videoStallFileName = nil;
        self.videoStallRecoveryCount = 0;
        [self showCurrentMediaWithTransition:NO];
        return;
    }
    NSTimeInterval position = CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval start = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
    if (!isfinite(position) || position < start) position = start;
    [self.player pause];
    __weak typeof(self) weakSelf = self;
    [self.player seekToTime:CMTimeMakeWithSeconds(position, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !finished || !self.visible || !self.view.window || self.player.currentItem != playerItem) return;
        [self recoverPlayerLayerSurfaceIfNeededForItem:playerItem reason:@"stalled-timeout"];
        [self.player playImmediatelyAtRate:CCBGEffectivePlaybackRate(self.currentItem)];
        self.lastVideoProgressAt = NSProcessInfo.processInfo.systemUptime;
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-stall-recovered", @{
            @"current": self.currentItem[@"fileName"] ?: @"",
            @"position": @(position),
            @"layerReady": @(self.playerLayer.readyForDisplay),
        });
    }];
}

- (BOOL)attemptFallbackMediaForFileName:(NSString *)fileName reason:(NSString *)reason {
    if (!fileName.length || [self.fallbackAttemptedFileName isEqualToString:fileName]) return NO;
    NSDictionary *stored = CCBGModulePreference(@"fallbackMediaChains", @{});
    NSArray *chain = [stored isKindOfClass:NSDictionary.class] && [stored[fileName] isKindOfClass:NSArray.class] ? stored[fileName] : @[];
    NSString *replacement = nil;
    for (id rawName in chain) {
        if (![rawName isKindOfClass:NSString.class] || ![rawName length] || [rawName isEqualToString:fileName]) continue;
        NSDictionary *item = CCBGMediaItemNamed(self.mediaItems, rawName);
        if (item && CCBGMediaItemIsCurrentlyEligible(item)) { replacement = rawName; break; }
    }
    if (!replacement.length) return NO;
    self.fallbackAttemptedFileName = fileName;
    self.videoFailureFileName = nil;
    self.videoFailureRebuildCount = 0;
    self.videoStallFileName = nil;
    self.videoStallRecoveryCount = 0;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-fallback-selected", @{
        @"from": fileName, @"to": replacement, @"reason": reason ?: @"视频无法播放"
    });
    NSInteger mode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));
    [self selectMediaNamed:replacement makeConstant:(mode == 0)];
    return YES;
}

- (void)handleVideoPlaybackFailureForItem:(AVPlayerItem *)playerItem reason:(NSString *)reason {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf handleVideoPlaybackFailureForItem:playerItem reason:reason]; });
        return;
    }
    if (playerItem && self.player.currentItem != playerItem) return;
    NSString *fileName = [self.currentItem[@"fileName"] copy];
    if (!fileName.length || !CCBGIsVideoName(fileName)) return;
    if (![self.videoFailureFileName isEqualToString:fileName]) {
        self.videoFailureFileName = fileName;
        self.videoFailureRebuildCount = 0;
    }
    if (self.videoFailureRebuildCount == 0) {
        self.videoFailureRebuildCount = 1;
        CCBGInvalidateVideoOnlyAssetCache(CCBGPathForItem(self.currentItem));
        CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-failure-player-rebuilt", @{
            @"file": fileName,
            @"reason": reason ?: @"视频无法播放",
        });
        [self showCurrentMediaWithTransition:NO];
        return;
    }
    if ([self attemptFallbackMediaForFileName:fileName reason:reason]) return;
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-quarantined", @{
        @"file": fileName,
        @"reason": reason ?: @"视频无法播放",
        @"recoveries": @(self.videoStallRecoveryCount),
    });
    CCBGMarkMediaFailure(fileName, reason.length ? reason : @"视频无法播放");
    [self stopPlayback];
    self.videoStallFileName = nil;
    self.videoStallRecoveryCount = 0;
    self.videoFailureFileName = nil;
    self.videoFailureRebuildCount = 0;
    self.currentItem = nil;
    self.mediaItems = @[];
    [self showCurrentMediaWithTransition:NO];
}

- (void)showCurrentMediaWithTransition:(BOOL)transition {
    [self stopPlayback];
    self.mediaPresentationStartedAt = NSProcessInfo.processInfo.systemUptime;
    self.healthStartRecorded = NO;
    if (!self.currentItem) {
        self.imageView.hidden = NO;
        self.imageView.image = nil;
        self.emptyLabel.hidden = NO;
        [self applyBlurIntensity:0.0];
        self.dimView.alpha = 0;
        self.currentVideoDuration = 0;
        self.adaptiveSizeMediaName = nil;
        self.adaptiveExpandedSize = CCBGConfiguredExpandedMaximumSize();
        [self updateNativePlayerPresentation];
        [self updateExpandedCaption];
        [self configureSlideshow];
        return;
    }

    if (transition && self.view.window) {
        NSInteger style = [CCBGModulePreference(@"transitionStyle", @0) integerValue];
        NSTimeInterval requestedDuration = MIN(0.60, MAX(0.16, [CCBGModulePreference(@"crossfadeDuration", @0.28) doubleValue]));
        NSTimeInterval duration = MIN(0.42, MAX(0.14, requestedDuration));
        NSMutableArray<CALayer *> *mediaLayers = [NSMutableArray array];
        if (self.imageView.layer) [mediaLayers addObject:self.imageView.layer];
        if (self.playerLayer) [mediaLayers addObject:self.playerLayer];
        if (self.nativePlayerController.view.layer) [mediaLayers addObject:self.nativePlayerController.view.layer];
        for (CALayer *layer in mediaLayers) {
            [layer removeAnimationForKey:@"ccbg.transition"];
            [layer removeAnimationForKey:@"ccbg.scale"];
            [layer removeAnimationForKey:@"ccbg.scaleFade"];
        }
        if (style == 2) {
            CASpringAnimation *scale = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
            scale.fromValue = @0.985; scale.toValue = @1.0; scale.duration = duration;
            scale.mass = 1.0; scale.stiffness = 260.0; scale.damping = 24.0; scale.initialVelocity = 0.0;
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @0.70; fade.toValue = @1.0; fade.duration = MIN(0.28, duration);
            fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            for (CALayer *layer in mediaLayers) {
                [layer addAnimation:scale forKey:@"ccbg.scale"];
                [layer addAnimation:fade forKey:@"ccbg.scaleFade"];
            }
        } else {
            CATransition *animation = [CATransition animation];
            animation.type = kCATransitionFade;
            animation.duration = style == 3 ? MIN(0.18, duration) : duration;
            CAMediaTimingFunction *timing = [CAMediaTimingFunction functionWithControlPoints:0.23 :1.0 :0.32 :1.0];
            // Keep the legacy curve available for invalid/legacy preference
            // values; normal UI transitions use the stronger ease-out curve.
            if (style < 0) timing = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            animation.timingFunction = timing;
            for (CALayer *layer in mediaLayers) [layer addAnimation:animation forKey:@"ccbg.transition"];
        }
    }
    [self applyDisplayForItem:self.currentItem];
    self.emptyLabel.hidden = YES;
    [self updateExpandedCaption];
    NSString *path = CCBGPathForItem(self.currentItem);
    NSString *currentName = self.currentItem[@"fileName"];
    BOOL mediaDirectoryReadable = CCBGMediaDirectoryIsReadable();
    if (!mediaDirectoryReadable) {
        self.videoBoundaryCount = 0;
        self.currentVideoDuration = 0;
        [self updateNativePlayerPresentation];
        self.imageView.image = self.imageView.image ?: CCBGPlaceholderImageForItem(self.currentItem);
        self.imageView.hidden = NO;
        [self configureSlideshow];
        return;
    }
    if (self.expanded) [self updateAdaptiveExpandedSizeForItem:self.currentItem];
    self.videoBoundaryCount = 0;
    if (!CCBGIsVideoName(self.currentItem[@"fileName"])) {
        self.currentVideoDuration = 0;
        [self updateNativePlayerPresentation];
        self.imageView.hidden = NO;
        self.imageView.image = [self filteredImageAtPath:path item:self.currentItem];
        if (!self.imageView.image) {
            CCBGMarkMediaFailure(currentName, @"图片无法解码");
            if (self.mediaItems.count > 1) dispatch_async(dispatch_get_main_queue(), ^{ [self advanceBy:1]; });
            return;
        }
        if ([self.currentItem[@"autoColor"] boolValue]) {
            NSString *hex = self.currentItem[@"dominantColor"];
            if (!hex.length) hex = CCBGDominantColorHexForImageAtPath(path);
            unsigned value = 0; [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
            self.view.backgroundColor = [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0 green:((value >> 8) & 0xff) / 255.0 blue:(value & 0xff) / 255.0 alpha:1];
        }
        [self rememberCurrentItem];
        [self configureSlideshow];
        [self preloadNextMedia];
        return;
    }

    BOOL hasPreloadedFrame = [self.preloadedFileName isEqualToString:currentName] && self.preloadedImage;
    CGSize previewSize = CGSizeMake(180, 100);
    UIImage *initialFrame = hasPreloadedFrame ? self.preloadedImage : [UIImage imageWithContentsOfFile:CCBGCachedThumbnailPath(self.currentItem, previewSize)];
    UIImage *retainedCover = initialFrame ?: self.imageView.image ?: CCBGPlaceholderImageForItem(self.currentItem);
    self.imageView.image = retainedCover;
    self.imageView.hidden = NO;
    if (!initialFrame) {
        NSDictionary *thumbnailItem = [self.currentItem copy];
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            UIImage *thumbnail = CCBGThumbnailForItem(thumbnailItem, previewSize);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || !thumbnail || ![self.currentItem[@"fileName"] isEqualToString:thumbnailItem[@"fileName"]]) return;
                NSTimeInterval current = CMTimeGetSeconds(self.player.currentTime);
                NSTimeInterval startTime = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
                if (!isfinite(current) || current <= startTime + 0.02) {
                    self.imageView.image = thumbnail;
                    self.imageView.hidden = NO;
                }
            });
        });
    }
    self.lastObservedPlayerTime = NAN;
    self.lastVideoProgressAt = NSProcessInfo.processInfo.systemUptime;
    self.currentVideoDuration = MAX(1.0, [self.currentItem[@"duration"] doubleValue]);
    CGFloat saturation = [self.currentItem[@"saturation"] doubleValue];
    CGFloat contrast = [self.currentItem[@"contrast"] doubleValue];
    NSUInteger installGeneration = self.playbackInstallGeneration;
    __weak typeof(self) weakSelfForInstall = self;
    CCBGLoadVideoOnlyAsset(path, ^(AVAsset *videoOnlyAsset, NSError *error) {
        __strong typeof(weakSelfForInstall) self = weakSelfForInstall;
        if (!self || installGeneration != self.playbackInstallGeneration) return;
        if (!videoOnlyAsset) {
            CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"video-only-asset-failed", @{@"file": currentName ?: @"", @"error": error.localizedDescription ?: @"unknown"});
            [self handleVideoPlaybackFailureForItem:nil reason:error.localizedDescription ?: @"视频轨道无法解码"];
            return;
        }
        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:videoOnlyAsset];
        if (fabs(saturation - 1.0) >= 0.01 || fabs(contrast - 1.0) >= 0.01) {
            playerItem.videoComposition = [AVVideoComposition videoCompositionWithAsset:videoOnlyAsset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request) {
                CIFilter *filter = [CIFilter filterWithName:@"CIColorControls"];
                [filter setValue:request.sourceImage forKey:kCIInputImageKey];
                [filter setValue:@(saturation) forKey:kCIInputSaturationKey];
                [filter setValue:@(contrast) forKey:kCIInputContrastKey];
                [request finishWithImage:filter.outputImage context:nil];
            }];
        }
        if (!self.player) self.player = [AVPlayer playerWithPlayerItem:nil];
        self.player.automaticallyWaitsToMinimizeStalling = NO;
        self.player.allowsExternalPlayback = NO;
        // These videos are decorative Control Center content. AVPlayer's iOS
        // default is YES, which can keep the device from auto-locking after a
        // notification wakes the screen.
        self.player.preventsDisplaySleepDuringVideoPlayback = NO;
        self.player.muted = YES;
        self.player.volume = 0.0;
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        if (!self.playerLayer) {
            self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
            [self.view.layer insertSublayer:self.playerLayer atIndex:0];
        }
        CGFloat inset = MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue]));
    self.playerLayer.frame = CGRectInset(self.view.bounds, inset, inset);
    self.playerLayer.masksToBounds = YES;
    CCBGApplyAllMediaCorners(self.view, @[self.imageView, self.dynamicTintView, self.blurView, self.dimView], self.playerLayer, self.nativePlayerController.view);
        [self updateNativePlayerPresentation];
        if (self.expanded) [self scheduleNativePlayerPresentationRecovery];
        [self applyDisplayForItem:self.currentItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoStalled:) name:AVPlayerItemPlaybackStalledNotification object:playerItem];

        NSTimeInterval start = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
        NSTimeInterval end = MAX(0.0, [self.currentItem[@"endTime"] doubleValue]);
        if (start > 0) [self.player seekToTime:CMTimeMakeWithSeconds(start, 600)];
        if (end > start) {
            __weak typeof(self) weakSelf = self;
            self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                NSTimeInterval seconds = CMTimeGetSeconds(time);
                [weakSelf observeVideoProgressForItem:playerItem time:seconds];
                if (seconds > start + 0.02) [weakSelf revealVideoWhenReadyForItem:playerItem attempt:0];
                if (seconds >= end) [weakSelf videoReachedBoundary];
            }];
        } else {
            __weak typeof(self) weakSelf = self;
            self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
                NSTimeInterval seconds = CMTimeGetSeconds(time);
                [weakSelf observeVideoProgressForItem:playerItem time:seconds];
                if (seconds > start + 0.02) [weakSelf revealVideoWhenReadyForItem:playerItem attempt:0];
            }];
        }
        BOOL privacyPaused = CCBGSystemIsLocked()
            && [CCBGModulePreference(@"privacyEnabled", @NO) boolValue]
            && [CCBGModulePreference(@"privacyPauseVideo", @YES) boolValue];
        BOOL compactModuleIsMounted = self.view.window != nil;
        if (compactModuleIsMounted && !privacyPaused) {
            [self startVideoPlaybackWhenReadyForItem:playerItem attempt:0];
            [self startVideoWatchdogForItem:playerItem];
        }
        [self rememberCurrentItem];
        [self configureSlideshow];
        [self preloadNextMedia];
    });
}

- (void)preloadNextMedia {
    [self clearPreloadedNextMedia];
    if (!self.visible || !self.view.window || !self.expanded ||
        ![CCBGModulePreference(@"preloadEnabled", @YES) boolValue] ||
        [CCBGModulePreference(@"performanceMode", @NO) boolValue] ||
        self.mediaItems.count < 2) return;
    NSInteger nextIndex = (self.mediaIndex + 1) % self.mediaItems.count;
    NSDictionary *next = self.mediaItems[nextIndex];
    NSUInteger preloadGeneration = self.playbackInstallGeneration;
    __weak typeof(self) weakSelf = self;
    if (CCBGIsVideoName(next[@"fileName"])) {
        self.preloadedAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:CCBGPathForItem(next)] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        [self.preloadedAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^{}];
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:self.preloadedAsset];
        self.preloadImageGenerator = generator;
        generator.appliesPreferredTrackTransform = YES;
        NSString *name = next[@"fileName"];
        [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]] completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
            if (!image) return;
            UIImage *frame = [UIImage imageWithCGImage:image];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || preloadGeneration != self.playbackInstallGeneration || !self.visible || !self.view.window || !self.expanded ||
                    self.mediaItems.count < 2 || ![self.mediaItems[(self.mediaIndex + 1) % self.mediaItems.count][@"fileName"] isEqualToString:name]) return;
                if (self.preloadImageGenerator != generator) return;
                self.preloadImageGenerator = nil;
                self.preloadedAsset = nil;
                self.preloadedFileName = name;
                self.preloadedImage = frame;
            });
        }];
        return;
    }
    NSString *name = next[@"fileName"];
    NSString *path = CCBGPathForItem(next);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || preloadGeneration != self.playbackInstallGeneration || !self.visible || !self.view.window || !self.expanded ||
                self.mediaItems.count < 2 || ![self.mediaItems[(self.mediaIndex + 1) % self.mediaItems.count][@"fileName"] isEqualToString:name]) return;
            self.preloadedFileName = name;
            self.preloadedImage = image;
        });
    });
}

- (void)clearPreloadedNextMedia {
    [self.preloadImageGenerator cancelAllCGImageGeneration];
    self.preloadImageGenerator = nil;
    [self.preloadedAsset cancelLoading];
    self.preloadedAsset = nil;
    self.preloadedImage = nil;
    self.preloadedFileName = nil;
}

- (void)rememberCurrentItem {
    if (self.automationOverrideActive) return;
    if (self.suppressCurrentPersistence) return;
    if (![CCBGModulePreference(@"rememberLast", @YES) boolValue]) return;
    NSString *name = self.currentItem[@"fileName"];
    if (!name.length) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    NSString *currentKey = CCBGPreferenceKeyForModule(@"currentMedia", CCBG_MODULE_SLOT);
    CFPreferencesSetAppValue((__bridge CFStringRef)currentKey, (__bridge CFStringRef)name, domain);
    CFPreferencesAppSynchronize(domain);
    CCBGSetCachedModulePreference(@"currentMedia", name);
}

- (void)updateExpandedCaption {
    if (!self.currentItem) {
        if (![self.lastExpandedCaptionText isEqualToString:@"暂无素材"]) {
            self.captionLabel.text = @"暂无素材";
            self.lastExpandedCaptionText = @"暂无素材";
        }
        return;
    }
    NSString *kind = CCBGIsVideoName(self.currentItem[@"fileName"]) ? @"视频" : @"图片";
    CGFloat opacity = self.displayedOpacity ? self.displayedOpacity.doubleValue : [CCBGModulePreference(@"moduleOpacity", @1.0) doubleValue];
    CGFloat blur = self.displayedBlurIntensity ? self.displayedBlurIntensity.doubleValue : [CCBGModulePreference(@"moduleBlurIntensity", @0.0) doubleValue];
    NSInteger opacityPercent = lround(MIN(1.0, MAX(0.05, opacity)) * 100.0);
    NSInteger blurPercent = lround(MIN(1.0, MAX(0.0, blur)) * 100.0);
    NSString *caption = [NSString stringWithFormat:@"%@ · %@ · 模糊 %ld%% · 透明 %ld%%", CCBGDisplayNameForItem(self.currentItem), kind, (long)blurPercent, (long)opacityPercent];
    if (![self.lastExpandedCaptionText isEqualToString:caption]) {
        self.captionLabel.text = caption;
        self.lastExpandedCaptionText = caption;
    }
}

- (void)updateCurrentOpacity:(CGFloat)opacity persist:(BOOL)persist {
    if (!self.currentItem) return;
    opacity = MIN(1.0, MAX(0.05, opacity));
    BOOL independentExpanded = self.expanded && [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue];
    NSString *preferenceKey = independentExpanded ? @"expandedOpacity" : @"moduleOpacity";
    if (persist) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(preferenceKey, CCBG_MODULE_SLOT), (__bridge CFPropertyListRef)@(opacity), domain);
        CFPreferencesAppSynchronize(domain);
        CCBGSetCachedModulePreference(preferenceKey, @(opacity));
    }
    self.displayedOpacity = @(opacity);
    self.imageView.alpha = opacity;
    self.playerLayer.opacity = opacity;
    self.nativePlayerController.view.alpha = opacity;
    [self updateExpandedCaption];
}

- (void)updateCurrentBlur:(CGFloat)blur persist:(BOOL)persist {
    blur = MIN(1.0, MAX(0.0, blur));
    BOOL independentExpanded = self.expanded && [CCBGModulePreference(@"expandedAppearanceEnabled", @NO) boolValue];
    NSString *preferenceKey = independentExpanded ? @"expandedBlurIntensity" : @"moduleBlurIntensity";
    if (persist) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(preferenceKey, CCBG_MODULE_SLOT), (__bridge CFPropertyListRef)@(blur), domain);
        CFPreferencesAppSynchronize(domain);
        CCBGSetCachedModulePreference(preferenceKey, @(blur));
    }
    self.displayedBlurIntensity = @(blur);
    [self applyBlurIntensity:[CCBGModulePreference(@"blurEnabled", @YES) boolValue] ? blur : 0.0];
    [self updateExpandedCaption];
}

- (void)applyBlurIntensity:(CGFloat)blur {
    blur = MIN(1.0, MAX(0.0, blur));
    if (self.blurView.effect || self.blurView.alpha > 0.001) {
        self.blurView.effect = nil;
        self.blurView.alpha = 0.0;
    }
    CCBGApplyGaussianBlurToLayer(self.imageView.layer, blur);
    CCBGApplyGaussianBlurToLayer(self.playerLayer, blur);
    CCBGApplyGaussianBlurToLayer(self.nativePlayerController.view.layer, blur);
}

- (void)scheduleNativePlayerPresentationRecovery {
    if (!self.expanded) return;
    // A collapse can invalidate an earlier wave while its delayed blocks are
    // still queued.  Always arm against the current expand boundary rather
    // than trusting the previous boolean alone.
    if (self.nativePresentationRecoveryArmed && self.nativePresentationRecoveryGeneration != 0) return;
    self.nativePresentationRecoveryArmed = YES;
    NSUInteger generation = ++self.nativePresentationRecoveryGeneration;
    NSArray<NSNumber *> *delays = @[@0.0, @0.05, @0.18, @0.45, @0.80, @1.20];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayValue in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (generation != self.nativePresentationRecoveryGeneration) return;
            if (!self.expanded || self.sceneLowPowerCoverActive || !self.player.currentItem ||
                !self.currentItem || !CCBGIsVideoName(self.currentItem[@"fileName"])) {
                self.nativePresentationRecoveryArmed = NO;
                return;
            }
            // Some SpringBoard builds omit didTransition. By the time the
            // first settled recovery pass runs, the host has normally landed
            // its expanded bounds, so release the transition guard here.
            if (delayValue.doubleValue >= 0.18) self.expandedContentTransitionActive = NO;
            CGFloat inset = MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue]));
            CGRect expectedFrame = CGRectInset(self.view.bounds, inset, inset);
            CGFloat panelHeight = MIN(154.0, MAX(126.0, CGRectGetHeight(expectedFrame) * 0.34));
            CGFloat gap = 8.0;
            CGFloat minimumMediaHeight = 168.0;
            if (CGRectGetHeight(expectedFrame) - panelHeight - gap < minimumMediaHeight) {
                panelHeight = MAX(116.0, CGRectGetHeight(expectedFrame) - gap - minimumMediaHeight);
            }
            expectedFrame.size.height = MAX(0.0, CGRectGetHeight(expectedFrame) - panelHeight - gap);
            CGFloat expectedOpacity = self.displayedOpacity ? self.displayedOpacity.doubleValue : 1.0;
            AVPlayerViewController *native = self.nativePlayerController;
            if (delayValue.doubleValue >= 0.45 && self.expanded && self.player.currentItem.status != AVPlayerItemStatusFailed) {
                self.nativePresentationFallbackVisible = YES;
            }
            BOOL nativeSurfaceAttached = self.expanded && CCBGIsVideoName(self.currentItem[@"fileName"]);
            BOOL nativeControlsReady = nativeSurfaceAttached &&
                (self.player.currentItem.status == AVPlayerItemStatusReadyToPlay || self.nativePresentationFallbackVisible);
            CGFloat expectedNativeAlpha = nativeControlsReady ? expectedOpacity : 0.0;
            BOOL needsPresentationRepair = !native || native.player != self.player || native.view.hidden != !nativeSurfaceAttached ||
                native.view.superview != self.view || !CGRectEqualToRect(native.view.frame, expectedFrame) ||
                fabs(native.view.alpha - expectedNativeAlpha) > 0.01 || native.view.userInteractionEnabled != nativeControlsReady;
            if (!needsPresentationRepair) {
                // Keep the later passes alive.  AVKit can attach the child
                // before its item becomes ready, and the next pass must still
                // re-check hierarchy/visibility after that asynchronous step.
                if (delayValue.doubleValue >= 1.20) self.nativePresentationRecoveryArmed = NO;
                return;
            }
            [self updateNativePlayerPresentation];
            native = self.nativePlayerController;
            if (!native) {
                if (delayValue.doubleValue >= 1.20) self.nativePresentationRecoveryArmed = NO;
                return;
            }
            if (native.player != self.player) {
                native.player = self.player;
            }
            native.view.hidden = !nativeSurfaceAttached;
            native.view.userInteractionEnabled = nativeControlsReady;
            native.view.alpha = expectedNativeAlpha;
            [native.view setNeedsLayout];
            [native.view.superview setNeedsLayout];
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
            if (delayValue.doubleValue >= 1.20) self.nativePresentationRecoveryArmed = NO;
        });
    }
}

- (void)detachNativePlayerForCompactTransition {
    self.nativePresentationRecoveryGeneration += 1;
    self.nativePresentationRecoveryArmed = NO;
    self.nativePresentationFallbackVisible = NO;
    AVPlayerViewController *native = self.nativePlayerController;
    if (native) {
        native.showsPlaybackControls = NO;
        native.view.userInteractionEnabled = NO;
        native.view.hidden = YES;
        native.view.alpha = 0.0;
    }
    self.nativePlayerAttachedForExpandedContent = NO;
    if (self.playerLayer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.playerLayer.hidden = !(self.player.currentItem && self.currentItem && CCBGIsVideoName(self.currentItem[@"fileName"]));
        self.playerLayer.opacity = 1.0;
        [CATransaction commit];
    }
}

- (void)updateNativePlayerPresentation {
    BOOL hasVideoPlayer = self.player.currentItem && self.currentItem && CCBGIsVideoName(self.currentItem[@"fileName"]);
    // CCSupport may call layout dozens of times while the module is moving.
    // Do not repeatedly detach/reattach AVPlayerViewController in that window;
    // the compact layer is already kept visible by the transition callbacks.
    if (self.expandedContentTransitionActive) return;
    // During willTransition the host still reports compact bounds. Keep the
    // compact AVPlayerLayer visible until didTransition/viewDidLayoutSubviews
    // provide the final expanded geometry.
    BOOL useNativePlayer = hasVideoPlayer && self.expanded && !self.expandedContentTransitionActive;

    CGFloat inset = MIN(24.0, MAX(0.0, [CCBGModulePreference(@"moduleInset", @0) doubleValue]));
    CGRect contentFrame = CGRectInset(self.view.bounds, inset, inset);
    if (self.expanded) {
        CGFloat gap = 8.0;
        CGFloat panelHeight = MIN(154.0, MAX(126.0, CGRectGetHeight(contentFrame) * 0.34));
        CGFloat minimumMediaHeight = 168.0;
        if (CGRectGetHeight(contentFrame) - panelHeight - gap < minimumMediaHeight) {
            panelHeight = MAX(116.0, CGRectGetHeight(contentFrame) - gap - minimumMediaHeight);
        }
        contentFrame.size.height = MAX(0.0, CGRectGetHeight(contentFrame) - panelHeight - gap);
    }
    AVPlayerItem *statePlayerItem = self.player.currentItem;
    UIView *stateNativeView = self.nativePlayerController.view;
    NSString *stateSignature = [NSString stringWithFormat:
        @"%d|%d|%d|%d|%p|%p|%p|%p|%ld|%d|%d|%@|%@|%@|%@|%@|%.3f|%.3f|%d|%d|%d|%d|%d",
        hasVideoPlayer, self.expanded, self.expandedContentTransitionActive,
        self.nativePresentationFallbackVisible,
        statePlayerItem, self.nativePlayerController, stateNativeView, self.playerLayer,
        (long)statePlayerItem.status, self.playerLayer.readyForDisplay,
        useNativePlayer, NSStringFromCGRect(contentFrame),
        NSStringFromCGRect(self.view.bounds), self.playerLayer.videoGravity ?: @"",
        NSStringFromClass(stateNativeView.superview.class) ?: @"", NSStringFromClass(self.view.class) ?: @"",
        self.displayedOpacity.doubleValue, stateNativeView.alpha,
        stateNativeView.hidden, stateNativeView.userInteractionEnabled,
        stateNativeView.superview == self.view, self.nativePlayerController.player == self.player,
        self.playerLayer.hidden];
    if ([stateSignature isEqualToString:self.lastNativePresentationStateSignature]) return;
    if (useNativePlayer && !self.nativePlayerController) {
        AVPlayerViewController *controller = [AVPlayerViewController new];
        controller.updatesNowPlayingInfoCenter = NO;
        controller.allowsPictureInPicturePlayback = NO;
        controller.entersFullScreenWhenPlaybackBegins = NO;
        controller.exitsFullScreenWhenPlaybackEnds = NO;
        controller.view.backgroundColor = UIColor.clearColor;
        controller.view.clipsToBounds = YES;
        [self addChildViewController:controller];
        // Keep the native controls above the cover/blur/dim layers. The title
        // remains the only overlay above the AVPlayerViewController; placing
        // it below the image view could leave the player visually present but
        // untappable during an expanded transition.
        UIView *anchor = self.captionLabel ?: self.imageView;
        if (anchor) [self.view insertSubview:controller.view belowSubview:anchor];
        else [self.view addSubview:controller.view];
        [controller didMoveToParentViewController:self];
        self.nativePlayerController = controller;
    }
    if (useNativePlayer && self.nativePlayerController.view.superview != self.view) {
        // Control Center can temporarily detach child views during an expand
        // animation. Reattach the existing controller instead of creating a
        // second AVPlayerViewController or leaving a hidden orphan behind.
        [self.nativePlayerController.view removeFromSuperview];
        UIView *anchor = self.captionLabel ?: self.imageView;
        if (anchor) [self.view insertSubview:self.nativePlayerController.view belowSubview:anchor];
        else [self.view addSubview:self.nativePlayerController.view];
        self.nativePlayerAttachedForExpandedContent = YES;
    }
    BOOL nativeFrameChanged = !self.hasAppliedNativePresentationFrame ||
        !CGRectEqualToRect(self.lastAppliedNativePresentationFrame, contentFrame);
    if (useNativePlayer && nativeFrameChanged) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.nativePlayerController.view.frame = contentFrame;
        [CATransaction commit];
    }
    // A compact layout pass may have changed contentFrame without touching
    // the expanded AVPlayerViewController. Do not treat that as a native
    // surface mutation or overwrite its settled expanded geometry.
    if (!useNativePlayer) nativeFrameChanged = NO;
    CGFloat moduleRadius = self.view.layer.cornerRadius;
    BOOL nativeSurfaceChanged = nativeFrameChanged ||
        !self.hasAppliedNativePresentationFrame ||
        fabs(self.lastAppliedNativePresentationRadius - moduleRadius) > 0.01 ||
        self.lastAppliedNativePresentationView != self.nativePlayerController.view ||
        self.lastAppliedNativePresentationPlayerLayer != self.playerLayer;
    self.hasAppliedNativePresentationFrame = YES;
    self.lastAppliedNativePresentationFrame = contentFrame;
    self.lastAppliedNativePresentationRadius = moduleRadius;
    self.lastAppliedNativePresentationView = self.nativePlayerController.view;
    self.lastAppliedNativePresentationPlayerLayer = self.playerLayer;
    if (nativeSurfaceChanged) {
        CCBGApplyAllMediaCorners(self.view, @[self.imageView, self.dynamicTintView, self.blurView, self.dimView], self.playerLayer, self.nativePlayerController.view);
    }
    AVLayerVideoGravity desiredNativeVideoGravity = self.playerLayer.videoGravity ?: AVLayerVideoGravityResizeAspectFill;
    if (![self.lastAppliedNativeVideoGravity isEqualToString:desiredNativeVideoGravity]) {
        self.nativePlayerController.videoGravity = desiredNativeVideoGravity;
        self.lastAppliedNativeVideoGravity = desiredNativeVideoGravity;
    }
    AVPlayerItem *playerItem = self.player.currentItem;
    // Keep the AVPlayerViewController mounted for the whole expanded
    // presentation, but expose its controls only after the item is ready (or
    // the bounded fallback pass has elapsed). This prevents a slow decoder
    // from hiding the native player permanently while retaining the cover
    // frame until it is safe to reveal the surface.
    BOOL nativeSurfaceAttached = useNativePlayer;
    BOOL nativeControlsReady = nativeSurfaceAttached &&
        (playerItem.status == AVPlayerItemStatusReadyToPlay || self.nativePresentationFallbackVisible);
    // AVPlayerViewController does real work when its player/control properties
    // are assigned, even when the value is unchanged. Layout can be requested
    // repeatedly during a Control Center collapse, so make every assignment
    // conditional and keep the player attached while the native surface is
    // hidden. This avoids a player teardown/rebuild on an animation frame.
    if (useNativePlayer) {
        if (self.nativePlayerController.player != self.player) {
            self.nativePlayerController.player = self.player;
        }
        if (!self.nativePlayerController.showsPlaybackControls) {
            self.nativePlayerController.showsPlaybackControls = YES;
        }
        BOOL shouldHide = !nativeSurfaceAttached;
        if (self.nativePlayerController.view.userInteractionEnabled != nativeControlsReady) {
            self.nativePlayerController.view.userInteractionEnabled = nativeControlsReady;
        }
        if (self.nativePlayerController.view.hidden != shouldHide) {
            self.nativePlayerController.view.hidden = shouldHide;
        }
        CGFloat opacity = self.displayedOpacity ? self.displayedOpacity.doubleValue : 1.0;
        CGFloat nativeAlpha = nativeControlsReady ? opacity : 0.0;
        if (fabs(self.nativePlayerController.view.alpha - nativeAlpha) > 0.001) {
            self.nativePlayerController.view.alpha = nativeAlpha;
        }
    } else {
        self.hasAppliedNativePresentationFrame = NO;
        self.lastAppliedNativePresentationView = nil;
        self.lastAppliedNativePresentationPlayerLayer = nil;
        self.lastAppliedNativeVideoGravity = nil;
        if (self.nativePlayerController.showsPlaybackControls) {
            self.nativePlayerController.showsPlaybackControls = NO;
        }
        if (self.nativePlayerController.view.userInteractionEnabled) {
            self.nativePlayerController.view.userInteractionEnabled = NO;
        }
        if (!self.nativePlayerController.view.hidden) {
            self.nativePlayerController.view.hidden = YES;
        }
        if (self.nativePlayerController.view.alpha > 0.001) {
            self.nativePlayerController.view.alpha = 0.0;
        }
    }
    self.playerLayer.hidden = !hasVideoPlayer || nativeControlsReady;
    if (useNativePlayer) {
        // Keep the retained thumbnail/cover above an unready native player.
        // AVPlayerViewController may be mounted before decoding completes;
        // hiding the cover at that point exposes a black expanded surface.
        self.imageView.hidden = !nativeControlsReady;
        if (nativeControlsReady) [self.view bringSubviewToFront:self.captionLabel];
    } else if (!hasVideoPlayer || !self.playerLayer.readyForDisplay) {
        self.imageView.hidden = NO;
    }
    // Store the post-update state, not the pre-update snapshot. This makes a
    // stable layout a true no-op on the next callback while still allowing a
    // readiness, frame, hierarchy, or opacity change to re-enter the method.
    UIView *finalNativeView = self.nativePlayerController.view;
    self.lastNativePresentationStateSignature = [NSString stringWithFormat:
        @"%d|%d|%d|%d|%p|%p|%p|%p|%ld|%d|%d|%@|%@|%@|%@|%@|%.3f|%.3f|%d|%d|%d|%d|%d",
        hasVideoPlayer, self.expanded, self.expandedContentTransitionActive,
        self.nativePresentationFallbackVisible,
        self.player.currentItem, self.nativePlayerController, finalNativeView, self.playerLayer,
        (long)self.player.currentItem.status, self.playerLayer.readyForDisplay,
        useNativePlayer, NSStringFromCGRect(contentFrame), NSStringFromCGRect(self.view.bounds),
        self.playerLayer.videoGravity ?: @"", NSStringFromClass(finalNativeView.superview.class) ?: @"",
        NSStringFromClass(self.view.class) ?: @"", self.displayedOpacity.doubleValue, finalNativeView.alpha,
        finalNativeView.hidden, finalNativeView.userInteractionEnabled,
        finalNativeView.superview == self.view, self.nativePlayerController.player == self.player,
        self.playerLayer.hidden];
}

- (void)updateAdaptiveExpandedSizeForItem:(NSDictionary *)item {
    // Never mutate preferredContentSize while the compact host is mounted;
    // CCSupport may treat that write as a live module geometry change.
    if (!self.expanded) return;
    if (!CCBGUsesAdaptiveExpandedSize()) {
        self.adaptiveSizeMediaName = nil;
        self.adaptiveExpandedSize = CCBGConfiguredExpandedMaximumSize();
        self.preferredContentSize = self.adaptiveExpandedSize;
        return;
    }
    NSString *name = item[@"fileName"];
    if (!name.length) return;
    if ([self.adaptiveSizeMediaName isEqualToString:name]) {
        if (self.adaptiveExpandedSize.width > 0.0 && self.adaptiveExpandedSize.height > 0.0) {
            self.preferredContentSize = self.adaptiveExpandedSize;
        }
        return;
    }
    self.adaptiveSizeMediaName = [name copy];
    NSString *path = CCBGPathForItem(item);
    __weak typeof(self) weakSelf = self;
    void (^finish)(CGSize) = ^(CGSize naturalSize) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || ![self.adaptiveSizeMediaName isEqualToString:name]) return;
            CGSize size = CCBGExpandedSizeForNaturalSize(naturalSize);
            if (CGSizeEqualToSize(self.adaptiveExpandedSize, size)) return;
            self.adaptiveExpandedSize = size;
            if (!self.expanded) return;
            self.preferredContentSize = size;
            [self.view setNeedsLayout];
        });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (CCBGIsVideoName(name)) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
                                                   options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
            [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
                AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
                CGSize naturalSize = track ? CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform) : CGSizeZero;
                naturalSize = CGSizeMake(fabs(naturalSize.width), fabs(naturalSize.height));
                NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (self && [self.adaptiveSizeMediaName isEqualToString:name] && isfinite(duration)) self.currentVideoDuration = MAX(1.0, duration);
                });
                finish(naturalSize);
            }];
            return;
        }
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        CGSize naturalSize = CGSizeZero;
        if (source) {
            NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
            naturalSize = CGSizeMake([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],
                                     [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue]);
            CFRelease(source);
        }
        finish(naturalSize);
    });
}

- (void)manualAdvanceBy:(NSInteger)offset {
    if ([CCBGModulePreference(@"playbackMode", @0) integerValue] == 0 || self.automationOverrideActive || self.mediaItems.count < 2) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self manualAdvanceBy:offset]; });
        return;
    }
    self.pendingManualAdvanceOffset += offset;
    [self commitPendingManualAdvance];
}

- (void)commitPendingManualAdvance {
    NSInteger offset = self.pendingManualAdvanceOffset;
    self.pendingManualAdvanceOffset = 0;
    if (offset == 0 || self.automationOverrideActive || self.mediaItems.count < 2) return;
    NSInteger mode = [CCBGModulePreference(@"playbackMode", @0) integerValue];
    if (mode == 2) {
        self.mediaIndex = [self randomMediaIndexExcludingCurrent];
    } else {
        self.mediaIndex = (self.mediaIndex + offset + self.mediaItems.count) % self.mediaItems.count;
    }
    self.currentItem = self.mediaItems[self.mediaIndex];
    self.suppressCurrentPersistence = NO;
    NSString *name = self.currentItem[@"fileName"];
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    NSString *currentKey = CCBGPreferenceKeyForModule(@"currentMedia", CCBG_MODULE_SLOT);
    CFPreferencesSetAppValue((__bridge CFStringRef)currentKey, (__bridge CFStringRef)name, domain);
    CFPreferencesAppSynchronize(domain);
    CCBGSetCachedModulePreference(@"currentMedia", name);
    [self showCurrentMediaWithTransition:NO];
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.layer.hidden = NO;
    self.view.layer.opacity = 1.0;
    [self convergeMountedPresentation:@"manual-advance"];
    [self scheduleMountedPresentationConvergence:@"manual-advance"];
}

- (void)videoReachedBoundary {
    if (self.handlingVideoBoundary || !self.player) return;
    self.handlingVideoBoundary = YES;
    NSInteger mode = [CCBGModulePreference(@"playbackMode", @0) integerValue];
    BOOL autoAdvance = [CCBGModulePreference(@"slideshowEnabled", @NO) boolValue]
        && mode != 0
        && !self.automationOverrideActive
        && self.mediaItems.count > 1;
    self.videoBoundaryCount += 1;
    NSInteger requiredPlays = [self.currentItem[@"videoAdvancePolicy"] integerValue] == 1
        ? MAX(1, [self.currentItem[@"videoPlayCount"] integerValue]) : 1;
    if (autoAdvance && self.videoBoundaryCount >= requiredPlays) {
        self.handlingVideoBoundary = NO;
        [self advanceBy:1];
    } else if (autoAdvance || [self.currentItem[@"loop"] boolValue]) {
        NSTimeInterval start = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
        [self.player seekToTime:CMTimeMakeWithSeconds(start, 600) completionHandler:^(BOOL finished) {
            if (finished && self.visible) {
                [self.player play];
                self.player.rate = CCBGEffectivePlaybackRate(self.currentItem);
            }
            self.handlingVideoBoundary = NO;
        }];
    } else {
        self.handlingVideoBoundary = NO;
    }
}

- (void)videoFailed:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self handleVideoPlaybackFailureForItem:notification.object reason:error.localizedDescription ?: @"视频无法解码"];
}

- (void)videoStalled:(NSNotification *)notification {
    [self recoverVideoPlaybackStallForItem:notification.object];
}

- (void)videoEnded:(NSNotification *)notification {
    [self videoReachedBoundary];
}

- (void)configureSlideshow {
    [self.slideTimer invalidate];
    self.slideTimer = nil;
    NSInteger mode = [CCBGModulePreference(@"playbackMode", @0) integerValue];
    BOOL enabled = [CCBGModulePreference(@"slideshowEnabled", @NO) boolValue];
    if (self.automationOverrideActive || !enabled || mode == 0 || self.mediaItems.count < 2) return;
    NSString *fileName = self.currentItem[@"fileName"];
    if (CCBGIsVideoName(fileName)) return;
    NSTimeInterval configured = [self.currentItem[@"imageDuration"] doubleValue];
    if (configured <= 0 && [fileName.pathExtension.lowercaseString isEqualToString:@"gif"] && self.imageView.image.duration > 0) configured = self.imageView.image.duration;
    NSTimeInterval interval = MIN(3600.0, MAX(2.0, configured > 0 ? configured : [CCBGModulePreference(@"slideshowInterval", @8) doubleValue]));
    __weak typeof(self) weakSelf = self;
    self.slideTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:NO block:^(NSTimer *timer) {
        if (!weakSelf || !weakSelf.visible || !weakSelf.view.window) return;
        [weakSelf advanceBy:1];
    }];
}

- (void)advanceBy:(NSInteger)offset {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self advanceBy:offset]; });
        return;
    }
    if (!self.visible || !self.view.window) return;
    if (!self.mediaItems.count) return;
    NSInteger mode = [CCBGModulePreference(@"playbackMode", @0) integerValue];
    if (mode == 0 || self.automationOverrideActive) return;
    if (mode == 2 && self.mediaItems.count > 1) {
        self.mediaIndex = [self randomMediaIndexExcludingCurrent];
    } else {
        NSInteger nextIndex = self.mediaIndex + offset;
        if (![CCBGModulePreference(@"playlistLoop", @YES) boolValue] && (nextIndex < 0 || nextIndex >= (NSInteger)self.mediaItems.count)) return;
        self.mediaIndex = (nextIndex + self.mediaItems.count) % self.mediaItems.count;
    }
    self.currentItem = self.mediaItems[self.mediaIndex];
    self.suppressCurrentPersistence = NO;
    // A boundary callback can arrive while Control Center is reconciling its
    // compact snapshot. Reassert the mounted state before replacing the
    // player so the new item cannot inherit a transient hidden/zero-alpha
    // surface from the host.
    self.visible = YES;
    self.view.hidden = NO;
    self.view.alpha = 1.0;
    self.view.layer.hidden = NO;
    self.view.layer.opacity = 1.0;
    // The compact Control Center host owns the module frame. Installing a
    // layer transition while an item advances at the video boundary can make
    // the host snapshot the player mid-animation, which looks like the whole
    // module flying out and disappearing. Keep transitions for the expanded
    // surface only; compact auto-advance swaps the player in place.
    [self showCurrentMediaWithTransition:self.expanded];
}

@end

@interface CCBG_MODULE_CLASS : NSObject <CCUIContentModule>
@property(nonatomic, strong) CCBG_VIEW_CONTROLLER_CLASS *controller;
@end

@implementation CCBG_MODULE_CLASS
- (instancetype)init {
    self = [super init];
    if (self) {
        self.controller = [CCBG_VIEW_CONTROLLER_CLASS new];
        self.controller.moduleOwner = self;
    }
    return self;
}
- (UIViewController *)contentViewController {
    CCBGRecordModuleLifecycleEvent(CCBG_MODULE_SLOT, @"content-controller", @{@"loaded": @(self.controller.isViewLoaded)});
    return self.controller;
}
- (UIViewController *)backgroundViewController { return nil; }
- (void)controlCenterModuleDidReceiveTap { [self.controller handleControlCenterTap]; }
- (BOOL)_canShowWhileLocked { return YES; }
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation {
    CCUILayoutSize size = {};
    if (CCBGReadCCAsterGridSize(self.controller, &size)) {
        BOOL landscape = orientation == 1 || orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
        return landscape ? (CCUILayoutSize){size.height, size.width} : size;
    }
    return CCBGRuntimeModuleSize(orientation);
}
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return self.controller.preferredExpandedContentWidth; }
- (CGFloat)preferredExpandedContentHeight { return self.controller.preferredExpandedContentHeight; }
@end
