#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <ImageIO/ImageIO.h>
#import <Network/Network.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <math.h>
#import <stdlib.h>
#import "CCBGMediaCatalog.h"

typedef NS_ENUM(NSInteger, CCBGSystemOverlayKind) {
    CCBGSystemOverlayKindConnectivity = 1,
    CCBGSystemOverlayKindMusic = 2,
    CCBGSystemOverlayKindBrightness = 3,
    CCBGSystemOverlayKindVolume = 4,
};

typedef NS_ENUM(NSInteger, CCBGConnectivityState) {
    CCBGConnectivityStateOffline = 0,
    CCBGConnectivityStateWiFi = 1,
    CCBGConnectivityStateCellular = 2,
    CCBGConnectivityStateOther = 3,
};

static UIImage *CCBGPlaceholderImageForItem(NSDictionary *item) {
    NSString *fileName = item[@"fileName"] ?: @"";
    return [UIImage systemImageNamed:CCBGIsVideoName(fileName) ? @"video.fill" : @"photo.fill"];
}

// AVPlayerViewController's scrubber and transport buttons must keep their
// touches. All other horizontal drags belong to the module-level media
// switch gesture, matching the five-module implementation.
static BOOL CCBGTouchIsNativeTransportControl(UITouch *touch, UIView *nativeView) {
    if (!touch || !nativeView) return NO;
    for (UIView *view = touch.view; view && view != nativeView; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UISlider.class]) return YES;
        NSString *className = NSStringFromClass(view.class).lowercaseString;
        for (NSString *blocked in @[@"transport", @"scrubber", @"playbackcontrol", @"seekbar"]) {
            if ([className containsString:blocked]) return YES;
        }
    }
    return NO;
}

@interface CCBGSystemOverlayView : UIView <UIGestureRecognizerDelegate>
@property(nonatomic) CCBGSystemOverlayKind kind;
@property(nonatomic, strong) UIView *mediaContainerView;
@property(nonatomic, strong) UIImageView *imageView;
// Keep the video layer in a real view hierarchy.  A CALayer sublayer of the
// container renders below all UIKit subviews, so the cover/blur views could
// otherwise obscure the video after an expanded takeover was mounted.
@property(nonatomic, strong) UIView *playerSurfaceView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
// Expanded takeover surfaces use the same native transport surface as the
// five custom modules. Keep one controller per overlay and reuse it across
// compact/expanded transitions instead of rebuilding AVKit on every layout.
@property(nonatomic, strong) AVPlayerViewController *nativePlayerController;
@property(nonatomic) BOOL nativePlayerPresentationFallbackVisible;
// AVKit may mount the controller before Control Center settles the takeover
// hierarchy. Keep a bounded recovery wave, matching the five-module player,
// so the first expansion after a SpringBoard rebuild cannot stay on a cover.
@property(nonatomic) NSUInteger nativePresentationRecoveryGeneration;
@property(nonatomic) BOOL nativePresentationRecoveryArmed;
@property(nonatomic) BOOL nativePlayerAttachedForExpandedContent;
@property(nonatomic, copy) NSString *lastNativePresentationStateSignature;
@property(nonatomic) NSUInteger playbackGeneration;
@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIView *dimView;
@property(nonatomic, strong) UIImage *dynamicArtwork;
@property(nonatomic, copy) NSString *configurationSignature;
@property(nonatomic) float playbackRate;
@property(nonatomic) NSTimeInterval lastConfigurationCheck;
@property(nonatomic) BOOL expandedPresentation;
@property(nonatomic, strong) NSDictionary *currentItem;
@property(nonatomic) CGFloat targetOpacity;
@property(nonatomic) BOOL adjustingBlur;
@property(nonatomic) CGFloat appearanceOpacityAtPanStart;
@property(nonatomic) CGFloat appearanceBlurAtPanStart;
@property(nonatomic, weak) UIImageView *suppressedArtworkView;
@property(nonatomic) CGFloat suppressedArtworkAlpha;
@property(nonatomic) float suppressedArtworkShadowOpacity;
@property(nonatomic) BOOL suppressedArtworkHidden;
@property(nonatomic, weak) UIView *suppressedArtworkContainer;
@property(nonatomic) float suppressedContainerShadowOpacity;
@property(nonatomic, strong) UIColor *suppressedContainerBackgroundColor;
@property(nonatomic, weak) UIViewController *hostController;
// The native module view stays the suppression target even when the Clean
// takeover overlay is reparented to the Control Center root while expanded.
@property(nonatomic, weak) UIView *nativeHostView;
@property(nonatomic, weak) UIView *gestureHostView;
@property(nonatomic, weak) UIView *layoutHostView;
// Expanded takeover is mounted on the Control Center root. Keep a sibling
// surface below it so the other modules cannot remain visible or interactive
// behind the expanded Clean module.
@property(nonatomic, strong) UIView *takeoverBackdrop;
@property(nonatomic, weak) UIView *takeoverBackdropHost;
@property(nonatomic, weak) UITapGestureRecognizer *takeoverOutsideTap;
@property(nonatomic, weak) UITapGestureRecognizer *takeoverRootTap;
@property(nonatomic, strong) UISwipeGestureRecognizer *swipeLeft;
@property(nonatomic, strong) UISwipeGestureRecognizer *swipeRight;
@property(nonatomic, strong) UIPanGestureRecognizer *appearancePan;
@property(nonatomic, strong) UITapGestureRecognizer *stateTap;
@property(nonatomic) BOOL genericUsesPresentationMedia;
@property(nonatomic) BOOL genericUsesCustomExpansion;
@property(nonatomic) BOOL hasNativePreferredContentSize;
@property(nonatomic) CGSize nativePreferredContentSize;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *suppressedNativeViewStates;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *suppressedNativeGestureStates;
@property(nonatomic, weak) UIView *suppressedNativeHostView;
@property(nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property(nonatomic) CGSize naturalVideoSize;
@property(nonatomic) NSUInteger handledFailureGeneration;
@property(nonatomic) NSUInteger consecutiveFailureSkips;
@property(nonatomic) NSUInteger configuredSelectionFailureRetries;
@property(nonatomic, copy) NSString *lastRecordedRecentName;
@property(nonatomic) NSUInteger dismissalGeneration;
@property(nonatomic) NSTimeInterval mediaPresentationStartedAt;
@property(nonatomic) NSTimeInterval healthPlaybackStartedAt;
@property(nonatomic, copy) NSString *healthPlaybackFileName;
@property(nonatomic) BOOL healthStartRecorded;
@property(nonatomic) BOOL sceneLowPowerCoverActive;
@property(nonatomic) NSUInteger sceneSmartCoverGeneration;
@property(nonatomic) CGFloat sceneBaseFocalX;
@property(nonatomic) CGFloat sceneBaseFocalY;
@property(nonatomic) NSInteger sceneContentMode;
@property(nonatomic) CGFloat sceneCropZoom;
@property(nonatomic) BOOL cachedAdaptiveCompositionEnabled;
@property(nonatomic) BOOL adaptiveExpandedFrameEnabled;
@property(nonatomic) CGSize preferredExpandedFrameSize;
@property(nonatomic) NSUInteger visibilityGeneration;
@property(nonatomic) BOOL hasPresented;
@property(nonatomic, strong) UIViewPropertyAnimator *visibilityAnimator;
@property(nonatomic) BOOL hasVisibilityTarget;
@property(nonatomic) BOOL visibilityTargetVisible;
@property(nonatomic) NSUInteger windowAttachmentGeneration;
@property(nonatomic) BOOL sceneEnvironmentRefreshScheduled;
@property(nonatomic) BOOL pendingSceneOrientationRefresh;
@property(nonatomic) BOOL readinessCheckActive;
@property(nonatomic, strong) UIViewPropertyAnimator *frameAnimator;
// Set only for an expanded -> compact takeover transition.  The overlay is
// reparented to the native compact host, but keeps its converted expanded
// frame until applyAdaptiveFrameForHostView: animates it into place.
@property(nonatomic) BOOL collapseAnimationPending;
@property(nonatomic, strong) UIViewPropertyAnimator *takeoverBackdropAnimator;
@property(nonatomic, copy) NSString *lastCompositionSignature;
@property(nonatomic) CGRect lastSceneLayoutBounds;
@property(nonatomic) CGRect lastSceneLayoutMediaBounds;
@property(nonatomic) BOOL lastSceneLayoutExpanded;
@property(nonatomic) BOOL hasSceneLayoutGeometry;
@property(nonatomic, strong) UIView *expandedControlPanel;
@property(nonatomic, strong) UIVisualEffectView *expandedPanelMaterial;
@property(nonatomic, strong) UILabel *expandedStateLabel;
@property(nonatomic, strong) UIStackView *expandedModeStack;
@property(nonatomic, strong) NSArray<UIButton *> *expandedModeButtons;
@property(nonatomic, strong) UIButton *expandedPresetButton;
@property(nonatomic, strong) UIButton *expandedCompositionButton;
@property(nonatomic, strong) UIButton *expandedMediaButton;
@property(nonatomic, copy) NSString *lastExpandedControlsSignature;
// A compact presentation must not reuse the expanded video's last rendered
// frame as a placeholder while the host is finishing its collapse.
@property(nonatomic) BOOL suppressRetainedVisualOnNextReload;
@property(nonatomic) BOOL reusePlayerItemOnNextReload;
- (void)reloadIfNeeded:(BOOL)force;
- (void)reloadIfNeeded:(BOOL)force resolvedMediaName:(NSString *)resolvedMediaName;
- (void)reloadAfterPreferenceChange;
- (void)setPlaybackVisible:(BOOL)visible;
- (void)suspendForInactiveControlCenterPresentation;
- (void)pausePlaybackPreservingPresentation;
- (void)restoreSuppressedArtwork;
- (void)suppressNativeContentInHostView:(UIView *)hostView;
- (void)restoreSuppressedNativeContent;
- (void)startPlaybackWhenReady;
- (void)schedulePlaybackReadinessCheck:(NSUInteger)generation attempt:(NSUInteger)attempt;
- (void)installInteractionsOnHostView:(UIView *)hostView controller:(UIViewController *)controller;
- (void)advanceVideoBy:(NSInteger)offset;
- (void)advanceVideoBy:(NSInteger)offset feedback:(BOOL)feedbackEnabled;
- (void)advanceAutomaticallyBy:(NSInteger)offset random:(BOOL)random;
- (void)handleAppearancePan:(UIPanGestureRecognizer *)recognizer;
- (void)handleTakeoverOutsideTap:(UITapGestureRecognizer *)recognizer;
- (void)presentVideoSelection;
- (void)applyAdaptiveFrameForHostView:(UIView *)hostView;
- (NSInteger)playbackMode;
- (void)recordRecentVideoName:(NSString *)fileName;
- (void)handlePlaybackFailure;
- (NSArray<NSDictionary *> *)automaticVideoItems;
- (void)applyVideoName:(NSString *)fileName clearFailure:(BOOL)clearFailure;
- (void)recordSuccessfulMediaStartIfNeeded;
- (void)recordActivePlaybackDurationIfNeeded;
- (void)applySceneLowPowerPolicy;
- (void)generateSceneSmartCoverAtTime:(NSTimeInterval)time;
- (void)applyCachedSceneComposition;
- (CGRect)expandedFrameForHostView:(UIView *)hostView module:(NSDictionary *)genericModule;
- (void)buildExpandedControlsIfNeeded;
- (void)updateExpandedControls;
- (BOOL)shouldShowExpandedControls;
- (void)applyExpandedMediaOpacity:(CGFloat)opacity;
- (void)attachNativePlayerControllerToHost:(UIViewController *)host;
- (void)updateNativePlayerPresentation;
- (void)scheduleNativePlayerPresentationRecovery;
- (void)detachNativePlayerForCompactPresentation;
// iOS 16's Control Center C2 transition asks every mounted module surface for
// its animation container. BetterCC enables that path for third-party modules,
// so a plain custom UIView must provide the same compatibility entry point or
// the first Control Center presentation raises an unrecognized-selector
// exception. Returning the overlay itself keeps its media surface in the same
// transition as the native module without creating another animation host.
- (UIView *)c2AnimationContainerView;
- (UIView *)caAnimationContainerView;
@end

static NSHashTable<CCBGSystemOverlayView *> *CCBGOverlayViews;
static NSMutableSet<NSString *> *CCBGHookedClasses;
static NSMutableSet<NSString *> *CCBGHookedControlCenterPresentationClasses;
static NSMutableSet<NSString *> *CCBGHookedModuleClasses;
static BOOL CCBGPrewarmInFlight;
static NSTimeInterval CCBGPrewarmLastCompletedAt;

static NSObject *CCBGPrewarmStateLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}
static NSMutableSet<NSString *> *CCBGHookedGenericContainerClasses;
static NSMutableDictionary<NSNumber *, NSDictionary *> *CCBGGenericModulesByKind;
// Native third-party modules can replace their content controller during an
// expansion transition. Keep the takeover state by module kind so the new
// controller cannot reset Clean's presentation to compact for one layout pass.
static NSMutableDictionary<NSNumber *, NSNumber *> *CCBGGenericExpandedStates;
// Controllers can remain mounted while the master switch detaches our media
// view. Keep a weak registry so enabling the switch can rebind those existing
// controllers without depending on another viewWillAppear: callback.
static NSMapTable<UIViewController *, NSNumber *> *CCBGTrackedOverlayControllers;
static NSUInteger CCBGTrackedOverlayRefreshGeneration;
static __weak UIViewController *CCBGLastPresentationRoot;
static void *CCBGOverlayAssociationKey = &CCBGOverlayAssociationKey;
static void *CCBGOverlayRebindAttemptKey = &CCBGOverlayRebindAttemptKey;
static void *CCBGSliderUpdateTimestampKey = &CCBGSliderUpdateTimestampKey;
static void *CCBGGenericOverlayKindAssociationKey = &CCBGGenericOverlayKindAssociationKey;
static void *CCBGGenericExpandedStateAssociationKey = &CCBGGenericExpandedStateAssociationKey;
static void *CCBGGenericModuleControllerAssociationKey = &CCBGGenericModuleControllerAssociationKey;
static void *CCBGGenericControllerOwnerAssociationKey = &CCBGGenericControllerOwnerAssociationKey;
static nw_path_monitor_t CCBGNetworkMonitor;
static CCBGConnectivityState CCBGCurrentConnectivityState = CCBGConnectivityStateOffline;
static NSMutableDictionary<NSString *, AVAsset *> *CCBGPreloadedOverlayAssets;
static NSCache<NSString *, NSData *> *CCBGPreloadedOverlayFrames;
static NSCache<NSString *, UIImage *> *CCBGPreloadedOverlayImages;
static NSArray<NSDictionary *> *CCBGPreloadedOverlayCatalog;
static NSUInteger CCBGOverlayStartupRefreshPasses;
// Several style/lock Darwin notifications are emitted as one logical state
// change. Coalesce their main-thread recovery work before it reaches the
// overlay/controller and AVFoundation layers.
static BOOL CCBGSystemOverlayReloadScheduled;
// A module controller can keep its view/window after Control Center closes.
// Treat the presentation root, rather than that stale window, as the single
// authority for whether overlay AVFoundation work may remain active.
static BOOL CCBGControlCenterPresentationVisible;
static NSMutableDictionary<NSString *, NSString *> *CCBGLastOverlayDiagnosticValues;
static CGFloat CCBGGenericModuleExpandedDimension(NSDictionary *module, NSString *suffix, CGFloat fallback, BOOL widthDimension);
static NSDictionary *CCBGGenericModuleForContainerController(UIViewController *controller);
static NSString *CCBGOverlayFrameCachePath(NSDictionary *item);
static void CCBGUpdateController(UIViewController *controller, CCBGSystemOverlayKind kind);
static void CCBGRefreshTrackedOverlayControllers(void);
static void CCBGScheduleTrackedOverlayRefreshes(void);
static void CCBGScheduleTrackedOverlayRefreshOnce(void);
static void CCBGSchedulePresentationRootRebind(void);
static void CCBGRebindPresentationRootControllers(UIViewController *root);
static void CCBGUpdateGenericContainerController(UIViewController *controller);
static UIViewController *CCBGViewHostController(UIView *view);
static BOOL CCBGSystemIsLocked(void);
static id CCBGValueForKeyIfAvailable(id object, NSString *key);
static BOOL CCBGControllerIsExpandedPresentation(UIViewController *controller, CCBGSystemOverlayKind kind);
static void CCBGSetGenericExpandedState(UIViewController *controller, BOOL expanded);
static void CCBGClearGenericExpandedState(UIViewController *controller);
static BOOL CCBGGenericExpandedStateForKind(CCBGSystemOverlayKind kind, BOOL *known);
static void CCBGSetGenericExpandedStateForKind(CCBGSystemOverlayKind kind, BOOL expanded);
static void CCBGClearGenericExpandedStateForKind(CCBGSystemOverlayKind kind);
static UIView *CCBGTakeoverRootView(UIViewController *controller);
static UIViewController *CCBGTakeoverRootController(UIViewController *controller, UIView *mountedView);
static void CCBGRemoveTakeoverBackdrop(CCBGSystemOverlayView *overlay);
static CCBGSystemOverlayView *CCBGClaimTakeoverOverlay(UIViewController *controller,
                                                        CCBGSystemOverlayKind kind);
static void CCBGUpdateTakeoverBackdrop(CCBGSystemOverlayView *overlay, UIView *rootHost, BOOL expanded);

// Turning the master switch off must hand the module back to Control Center.
// The takeover normally records every suppressed child view, but a reload can
// race with controller recreation and leave no overlay object to perform that
// restoration. Keep this fallback idempotent and limited to the disable path.
static void CCBGRestoreNativeModuleVisibility(UIViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (!view) return;
    view.hidden = NO;
    view.alpha = 1.0;
    view.userInteractionEnabled = YES;
    view.layer.hidden = NO;
    view.layer.opacity = 1.0;
    // A third-party module often nests its visible tile two or more levels
    // below the controller. Restoring only direct children leaves the tile
    // blank after pluginEnabled is toggled off following a rebind.
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:view];
    NSUInteger remaining = 128;
    while (pending.count && remaining > 0) {
        UIView *candidate = pending.lastObject;
        [pending removeLastObject];
        remaining--;
        if (candidate != view && ![candidate isKindOfClass:CCBGSystemOverlayView.class] &&
            candidate.hidden && candidate.alpha <= 0.01 && candidate.layer.hidden && candidate.layer.opacity <= 0.01) {
            candidate.hidden = NO;
            candidate.alpha = 1.0;
            candidate.userInteractionEnabled = YES;
            candidate.layer.hidden = NO;
            candidate.layer.opacity = 1.0;
        }
        if (candidate.subviews.count && ![candidate isKindOfClass:CCBGSystemOverlayView.class]) {
            [pending addObjectsFromArray:candidate.subviews];
        }
    }
}

static void CCBGCacheOverlayImage(UIImage *image, NSString *key) {
    if (!image || !key.length || !CCBGPreloadedOverlayImages) return;
    CGImageRef cgImage = image.CGImage;
    NSUInteger cost = cgImage ? CGImageGetWidth(cgImage) * CGImageGetHeight(cgImage) * 4 : 0;
    [CCBGPreloadedOverlayImages setObject:image forKey:key cost:cost];
}

// The catalog is cheap metadata and remains useful for the next presentation.
// Decoded covers and AVAssets, however, can keep IOSurface memory resident in
// SpringBoard after Control Center has gone away.
static void CCBGDiscardOverlayTransientMediaCaches(void) {
    @synchronized (CCBGPreloadedOverlayAssets) {
        [CCBGPreloadedOverlayAssets removeAllObjects];
    }
    [CCBGPreloadedOverlayFrames removeAllObjects];
    [CCBGPreloadedOverlayImages removeAllObjects];
}

static char CCBGAppliedGaussianBlurKey;
static char CCBGAppliedGaussianBlurFilterKey;
static NSString *const CCBGOverlayPreferenceSnapshotThreadKey = @"com.zjc.cleanccbg2x2.overlay-preference-snapshot";

static id CCBGOverlayReadPreference(NSString *key, id fallback) {
    NSDictionary *snapshot = NSThread.currentThread.threadDictionary[CCBGOverlayPreferenceSnapshotThreadKey];
    if ([snapshot isKindOfClass:NSDictionary.class]) {
        id value = snapshot[key];
        return value ?: fallback;
    }
    return CCBGReadPreference(key, fallback);
}

static void CCBGWithOverlayPreferenceSnapshot(dispatch_block_t operation) {
    if (!operation) return;
    NSMutableDictionary *storage = NSThread.currentThread.threadDictionary;
    NSDictionary *previous = storage[CCBGOverlayPreferenceSnapshotThreadKey];
    if (!previous) storage[CCBGOverlayPreferenceSnapshotThreadKey] = CCBGReadAllPreferences();
    @try {
        operation();
    } @finally {
        if (previous) storage[CCBGOverlayPreferenceSnapshotThreadKey] = previous;
        else [storage removeObjectForKey:CCBGOverlayPreferenceSnapshotThreadKey];
    }
}

#define CCBGReadPreference CCBGOverlayReadPreference

static void CCBGApplyGaussianBlurToLayer(CALayer *layer, CGFloat intensity) {
    if (!layer) return;
    intensity = MIN(1.0, MAX(0.0, intensity));
    // Slider/pan gestures produce sub-percent changes that are visually
    // indistinguishable but would otherwise rebuild a private CAFilter on
    // every event and compete with video compositing.
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
    id filter = ((id (*)(id, SEL, id))objc_msgSend)(filterClass, factory, @"gaussianBlur");
    if (!filter) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(filter, setValue, @(intensity * 32.0), @"inputRadius");
    ((void (*)(id, SEL, id, id))objc_msgSend)(filter, setValue, @YES, @"inputNormalizeEdges");
    // Reused overlay layers can keep the previous private filter during a
    // host rebuild. Clear before assigning the new one to prevent cumulative
    // blur after repeated visual adjustments.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.filters = nil;
    layer.filters = @[filter];
    [CATransaction commit];
    objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurKey, @(intensity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurFilterKey, filter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static __attribute__((unused)) BOOL CCBGArmSystemOverlayCrashLoopGuard(void) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesAppSynchronize(domain);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval previousLaunch = [CCBGReadPreference(@"systemOverlayLastSpringBoardLoad", @0) doubleValue];
    NSInteger previousCount = [CCBGReadPreference(@"systemOverlayRapidLoadCount", @0) integerValue];
    NSInteger rapidLoadCount = now - previousLaunch <= 45.0 ? previousCount + 1 : 1;
    CFPreferencesSetAppValue(CFSTR("systemOverlayLastSpringBoardLoad"), (__bridge CFNumberRef)@(now), domain);
    CFPreferencesSetAppValue(CFSTR("systemOverlayRapidLoadCount"), (__bridge CFNumberRef)@(rapidLoadCount), domain);
    if (rapidLoadCount >= 3) {
        CFPreferencesSetAppValue(CFSTR("systemOverlayCrashGuardTriggeredAt"), (__bridge CFNumberRef)@(now), domain);
    }
    CFPreferencesAppSynchronize(domain);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(75.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesSetAppValue(CFSTR("systemOverlayRapidLoadCount"), (__bridge CFNumberRef)@0, domain);
        CFPreferencesSetAppValue(CFSTR("systemOverlayLastSpringBoardLoad"), (__bridge CFNumberRef)@0, domain);
        CFPreferencesAppSynchronize(domain);
    });
    // NOTE: This intentionally always returns NO. systemOverlayCrashGuardTriggeredAt
    // is diagnostic telemetry only (see findings.md Phase 15) -- the actual infinite
    // safe-mode root cause was an unsafe isSubclassOfClass: runtime scan, since fixed.
    // Do not turn this into a circuit breaker without updating validate_source.py's
    // explicit "return NO;" / "rapidLoadCount >= 3" contract assertions.
    return NO;
}

static NSString *CCBGOverlayPrefix(CCBGSystemOverlayKind kind) {
    NSDictionary *genericModule = CCBGGenericModulesByKind[@(kind)];
    if (genericModule[@"prefix"]) return genericModule[@"prefix"];
    switch (kind) {
        case CCBGSystemOverlayKindConnectivity: return @"connectivityOverlay";
        case CCBGSystemOverlayKindMusic: return @"musicOverlay";
        case CCBGSystemOverlayKindBrightness: return @"brightnessOverlay";
        case CCBGSystemOverlayKindVolume: return @"volumeOverlay";
    }
    return @"systemOverlay";
}

static NSInteger CCBGGenericOverlayKindForIdentifier(NSString *identifier) {
    NSData *data = [[identifier lowercaseString] dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    uint32_t hash = 2166136261U;
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= bytes[index];
        hash *= 16777619U;
    }
    return 100 + (NSInteger)(hash & 0x3fffffffU);
}

static NSString *CCBGOverlayKey(CCBGSystemOverlayKind kind, NSString *suffix) {
    NSString *prefix = CCBGOverlayPrefix(kind);
    return [prefix stringByAppendingString:suffix];
}

static BOOL CCBGSystemIsLocked(void) {
    for (NSString *className in @[@"SBLockScreenManager", @"SBLockStateAggregator", @"SBCoverSheetPresentationManager"]) {
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

static NSString *CCBGEnabledKey(CCBGSystemOverlayKind kind) {
    return CCBGOverlayKey(kind, @"Enabled");
}

static NSString *CCBGMediaKey(CCBGSystemOverlayKind kind, BOOL expanded) {
    return CCBGOverlayKey(kind, expanded ? @"ExpandedMedia" : @"CompactMedia");
}

static BOOL CCBGGenericModuleUsesPresentationMedia(CCBGSystemOverlayKind kind) {
    NSDictionary *module = CCBGGenericModulesByKind[@(kind)];
    if (!module) return NO;
    if ([module[@"identifier"] isEqualToString:@"netskao.ccswitchdatamodule"]) return YES;
    if ([CCBGReadPreference(CCBGOverlayKey(kind, @"SupportsExpanded"), @NO) boolValue]) return YES;
    NSDictionary *runtime = CCBGReadPreference(CCBGOverlayKey(kind, @"LastRuntimeMatch"), @{});
    if ([runtime isKindOfClass:NSDictionary.class] && [runtime[@"expanded"] boolValue]) return YES;
    return [CCBGReadPreference(CCBGOverlayKey(kind, @"MediaAboveNative"), @NO) boolValue];
}

static BOOL CCBGGenericModuleUsesCustomExpansion(CCBGSystemOverlayKind kind) {
    NSDictionary *module = CCBGGenericModulesByKind[@(kind)];
    BOOL takeoverEnabled = [CCBGReadPreference(CCBGOverlayKey(kind, @"MediaAboveNative"), @NO) boolValue];
    if ((!module && (kind < CCBGSystemOverlayKindConnectivity || kind > CCBGSystemOverlayKindVolume)) || !takeoverEnabled) return NO;
    // MediaAboveNative is an explicit opt-in to full Clean ownership. Once it
    // is enabled, the original module's expansion capability and identifier
    // no longer affect the presentation or interaction path.
    return YES;
}

static BOOL CCBGGenericModuleUsesCleanTakeover(CCBGSystemOverlayKind kind) {
    BOOL knownModule = CCBGGenericModulesByKind[@(kind)] != nil ||
        (kind >= CCBGSystemOverlayKindConnectivity && kind <= CCBGSystemOverlayKindVolume);
    return knownModule && [CCBGReadPreference(CCBGOverlayKey(kind, @"MediaAboveNative"), @NO) boolValue];
}

static BOOL CCBGOverlayUsesCleanTakeover(CCBGSystemOverlayView *overlay) {
    return overlay && (overlay.genericUsesCustomExpansion || CCBGGenericModuleUsesCleanTakeover(overlay.kind));
}

static CGSize CCBGCleanExpandedMaximumSize(void) {
    CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGFloat screenHeight = CGRectGetHeight(UIScreen.mainScreen.bounds);
    CGFloat width = MIN(MAX(220.0, [CCBGReadPreference(@"expandedWidth", @430) doubleValue]), screenWidth - 24.0);
    CGFloat height = MIN(MAX(220.0, [CCBGReadPreference(@"expandedHeight", @600) doubleValue]), screenHeight - 100.0);
    return CGSizeMake(round(width), round(height));
}

static CGSize CCBGCleanExpandedSizeForNaturalSize(CGSize naturalSize) {
    CGSize maximum = CCBGCleanExpandedMaximumSize();
    if (![CCBGReadPreference(@"adaptiveExpandedSizeEnabled", @YES) boolValue] ||
        naturalSize.width <= 0.0 || naturalSize.height <= 0.0) return maximum;
    CGFloat aspect = naturalSize.width / naturalSize.height;
    CGFloat width = maximum.width;
    CGFloat height = width / MAX(0.01, aspect);
    if (height > maximum.height) {
        height = maximum.height;
        width = height * aspect;
    }
    CGFloat minimumHeight = MIN(maximum.height, 300.0);
    return CGSizeMake(round(MAX(220.0, MIN(maximum.width, width))),
                      round(MAX(minimumHeight, MIN(maximum.height, height))));
}

static NSString *CCBGGenericStateMediaName(CCBGSystemOverlayKind kind, UIView *view) {
    if (!CCBGGenericModulesByKind[@(kind)] || CCBGGenericModuleUsesPresentationMedia(kind)) return @"";
    NSString *prefix = CCBGOverlayPrefix(kind);
    NSString *state = CCBGReadPreference(CCBGOverlayKey(kind, @"StateStatus"), @"");
    if (![state isKindOfClass:NSString.class] || !state.length) state = [CCBGReadPreference(CCBGOverlayKey(kind, @"StateActive"), @NO) boolValue] ? @"on" : @"off";
    NSDictionary *sceneContext = CCBGSceneRuntimeContext(view);
    NSString *sceneName = CCBGSceneDirectorStateMediaForTarget(prefix, state, sceneContext);
    if (!sceneName.length) sceneName = CCBGSceneDirectorStateMediaForTarget(@"generic", state, sceneContext);
    if (sceneName.length) return sceneName;
    if ([state isEqualToString:@"loading"] || [state isEqualToString:@"unavailable"]) {
        NSString *tracked = CCBGReadPreference(CCBGOverlayKey(kind, [NSString stringWithFormat:@"State%@Media", state.capitalizedString]), @"");
        if ([tracked isKindOfClass:NSString.class] && tracked.length) return tracked;
    }
    BOOL active = [CCBGReadPreference(CCBGOverlayKey(kind, @"StateActive"), @NO) boolValue];
    NSString *name = CCBGReadPreference(CCBGOverlayKey(kind, active ? @"StateOnMedia" : @"StateOffMedia"), @"");
    return [name isKindOfClass:NSString.class] ? name : @"";
}

static NSInteger CCBGOverlayPlaybackMode(CCBGSystemOverlayKind kind, BOOL expanded) {
    NSString *suffix = expanded ? @"ExpandedPlaybackMode" : @"CompactPlaybackMode";
    id value = CCBGReadPreference(CCBGOverlayKey(kind, suffix), nil);
    if (!value && expanded) value = CCBGReadPreference(CCBGOverlayKey(kind, @"CompactPlaybackMode"), @0);
    return MIN(2, MAX(0, [value integerValue]));
}

static NSString *CCBGCurrentMediaKey(CCBGSystemOverlayKind kind, BOOL expanded) {
    NSInteger mode = CCBGOverlayPlaybackMode(kind, expanded);
    NSString *presentation = expanded ? @"Expanded" : @"Compact";
    NSString *modeName = mode == 2 ? @"Random" : @"Sequential";
    return CCBGOverlayKey(kind, [NSString stringWithFormat:@"%@%@CurrentMedia", presentation, modeName]);
}

static NSString *CCBGFixedMediaKey(CCBGSystemOverlayKind kind, BOOL expanded) {
    if (kind == CCBGSystemOverlayKindConnectivity && expanded &&
        [CCBGReadPreference(CCBGOverlayKey(kind, @"FollowNetwork"), @NO) boolValue]) {
        if (CCBGCurrentConnectivityState == CCBGConnectivityStateWiFi) return CCBGOverlayKey(kind, @"WiFiMedia");
        if (CCBGCurrentConnectivityState == CCBGConnectivityStateCellular) return CCBGOverlayKey(kind, @"CellularMedia");
        if (CCBGCurrentConnectivityState == CCBGConnectivityStateOffline) return CCBGOverlayKey(kind, @"OfflineMedia");
    }
    return CCBGMediaKey(kind, expanded);
}

static NSString *CCBGInteractiveMediaKey(CCBGSystemOverlayKind kind, BOOL expanded) {
    return CCBGOverlayPlaybackMode(kind, expanded) == 0
        ? CCBGFixedMediaKey(kind, expanded)
        : CCBGCurrentMediaKey(kind, expanded);
}

static NSString *CCBGOpacityKey(CCBGSystemOverlayKind kind) {
    return CCBGOverlayKey(kind, @"Opacity");
}

static NSString *CCBGPresentationKey(CCBGSystemOverlayKind kind, BOOL expanded, NSString *suffix) {
    return CCBGOverlayKey(kind, [NSString stringWithFormat:@"%@%@", expanded ? @"Expanded" : @"Compact", suffix]);
}

static NSArray<NSString *> *CCBGStringArrayPreference(NSString *key) {
    id value = CCBGReadPreference(key, @[]);
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in (NSArray *)value) {
        if (![entry isKindOfClass:NSString.class] || ![entry length] || [seen containsObject:entry]) continue;
        [seen addObject:entry];
        [strings addObject:entry];
    }
    return strings;
}

static void CCBGSetPreferenceValue(NSString *key, id value) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(domain);
}

static NSString *CCBGSelectedOverlayMediaName(CCBGSystemOverlayKind kind, BOOL expanded, UIView *view) {
    NSString *sceneTarget = [NSString stringWithFormat:@"%@%@", CCBGOverlayPrefix(kind), expanded ? @"Expanded" : @"Compact"];
    NSString *sceneMedia = CCBGSceneDirectorMediaForTarget(sceneTarget, CCBGSceneRuntimeContext(view));
    if (sceneMedia.length) return sceneMedia;
    NSString *stateName = CCBGGenericStateMediaName(kind, view);
    if (stateName.length) return stateName;
    NSString *fixedName = CCBGReadPreference(CCBGFixedMediaKey(kind, expanded), @"");
    if (CCBGOverlayPlaybackMode(kind, expanded) == 0 && fixedName.length) return fixedName;
    NSString *currentName = CCBGReadPreference(CCBGCurrentMediaKey(kind, expanded), @"");
    if ([currentName isKindOfClass:NSString.class] && currentName.length) return currentName;
    if (!expanded && (kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume) &&
        [fixedName isKindOfClass:NSString.class]) return fixedName;
    // MediaAboveNative creates a Clean-owned expanded surface even for a
    // module that never had native expanded media configured. Do not turn a
    // valid compact video into an empty expanded card in that case.
    if (expanded && CCBGGenericModuleUsesCleanTakeover(kind)) {
        return CCBGSelectedOverlayMediaName(kind, NO, view);
    }
    return @"";
}

static NSArray<NSDictionary *> *CCBGAvailableOverlayItems(void) {
    NSMutableArray<NSDictionary *> *available = [NSMutableArray array];
    for (NSDictionary *item in CCBGMediaItemsForModule(CCBGLoadMediaCatalog(), -1)) {
        if (![item[@"enabled"] boolValue]) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) continue;
        [available addObject:item];
    }
    return available;
}

@interface CCBGOverlayMediaPickerController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSArray<NSDictionary *> *allItems;
@property(nonatomic, copy) NSArray<NSDictionary *> *playlistItems;
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredItems;
@property(nonatomic, copy) NSString *selectedName;
@property(nonatomic, copy) void (^selectionHandler)(NSString *fileName);
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) UISegmentedControl *scopeControl;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property(nonatomic, strong) NSMutableSet<NSString *> *thumbnailRequests;
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items playlistItems:(NSArray<NSDictionary *> *)playlistItems selectedName:(NSString *)selectedName selectionHandler:(void (^)(NSString *fileName))selectionHandler;
- (NSString *)overlayPickerThumbnailKeyForItem:(NSDictionary *)item;
- (UIImage *)cachedOverlayPickerThumbnailForItem:(NSDictionary *)item;
- (void)loadOverlayPickerThumbnailForItem:(NSDictionary *)item;
@end

static UIImage *CCBGOverlayPickerThumbnailForItem(NSDictionary *item) {
    NSData *frameData = [NSData dataWithContentsOfFile:CCBGOverlayFrameCachePath(item)];
    UIImage *frame = frameData.length ? [UIImage imageWithData:frameData] : nil;
    if (frame) return frame;
    NSString *fileName = item[@"fileName"] ?: @"";
    if (!CCBGIsVideoName(fileName)) {
        NSURL *url = [NSURL fileURLWithPath:CCBGPathForItem(item) ?: @""];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (source) {
            NSDictionary *options = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @160,
                (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
            };
            CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            CFRelease(source);
            if (image) {
                UIImage *thumbnail = [UIImage imageWithCGImage:image];
                CGImageRelease(image);
                return thumbnail;
            }
        }
    }
    return [UIImage systemImageNamed:CCBGIsVideoName(fileName) ? @"video.fill" : @"photo.fill"];
}

@implementation CCBGOverlayMediaPickerController
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items playlistItems:(NSArray<NSDictionary *> *)playlistItems selectedName:(NSString *)selectedName selectionHandler:(void (^)(NSString *fileName))selectionHandler {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _allItems = [items copy] ?: @[];
    _playlistItems = [playlistItems copy] ?: @[];
    _items = _allItems;
    _selectedName = [selectedName copy] ?: @"";
    _selectionHandler = [selectionHandler copy];
    _thumbnailCache = [NSCache new];
    _thumbnailCache.countLimit = 48;
    _thumbnailCache.totalCostLimit = 12 * 1024 * 1024;
    _thumbnailRequests = [NSMutableSet set];
    self.title = @"选择视频";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 56.0;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelSelection)];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"搜索视频";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"全部", @"列表", @"收藏", @"最近"]];
    self.scopeControl.selectedSegmentIndex = self.playlistItems.count ? 1 : 0;
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    self.scopeControl.frame = CGRectMake(16, 8, MAX(280, CGRectGetWidth(self.tableView.bounds) - 32), 32);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 48)];
    self.scopeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.scopeControl];
    self.tableView.tableHeaderView = header;
    NSUInteger playlistSelectedIndex = [self.playlistItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
        return [item[@"fileName"] isEqualToString:self.selectedName];
    }];
    if (self.selectedName.length && playlistSelectedIndex == NSNotFound) {
        self.scopeControl.selectedSegmentIndex = 0;
    }
    [self scopeChanged:self.scopeControl];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.searchController.isActive) [self scrollToSelectedItemIfNeeded];
}

- (NSArray<NSDictionary *> *)itemsForNames:(NSArray<NSString *> *)names {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSString *name in names) {
        for (NSDictionary *item in self.allItems) {
            if ([item[@"fileName"] isEqualToString:name]) { [result addObject:item]; break; }
        }
    }
    return result;
}

- (void)scopeChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 1) self.items = self.playlistItems.count ? self.playlistItems : self.allItems;
    else if (sender.selectedSegmentIndex == 2) self.items = [self itemsForNames:CCBGStringArrayPreference(@"systemOverlayFavoriteMedia")];
    else if (sender.selectedSegmentIndex == 3) self.items = [self itemsForNames:CCBGStringArrayPreference(@"systemOverlayRecentMedia")];
    else self.items = self.allItems;
    self.filteredItems = nil;
    self.searchController.searchBar.text = @"";
    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)visibleItems { return self.filteredItems ?: self.items; }

- (NSString *)overlayPickerThumbnailKeyForItem:(NSDictionary *)item {
    NSString *fileName = [item[@"fileName"] isKindOfClass:NSString.class] ? item[@"fileName"] : @"";
    return [NSString stringWithFormat:@"%@|%.3f", fileName, [item[@"startTime"] doubleValue]];
}

- (UIImage *)cachedOverlayPickerThumbnailForItem:(NSDictionary *)item {
    return [self.thumbnailCache objectForKey:[self overlayPickerThumbnailKeyForItem:item]];
}

- (void)loadOverlayPickerThumbnailForItem:(NSDictionary *)item {
    NSString *key = [self overlayPickerThumbnailKeyForItem:item];
    if (!key.length || [self.thumbnailCache objectForKey:key] || [self.thumbnailRequests containsObject:key]) return;
    [self.thumbnailRequests addObject:key];
    NSDictionary *snapshot = [item copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *thumbnail = CCBGOverlayPickerThumbnailForItem(snapshot);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.thumbnailRequests removeObject:key];
            if (thumbnail) {
                CGImageRef image = thumbnail.CGImage;
                NSUInteger cost = image ? CGImageGetWidth(image) * CGImageGetHeight(image) * 4 : 0;
                [self.thumbnailCache setObject:thumbnail forKey:key cost:cost];
            }
            NSMutableArray<NSIndexPath *> *visibleMatches = [NSMutableArray array];
            for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows ?: @[]) {
                if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.visibleItems.count) continue;
                NSDictionary *visibleItem = self.visibleItems[(NSUInteger)indexPath.row];
                if ([[self overlayPickerThumbnailKeyForItem:visibleItem] isEqualToString:key]) [visibleMatches addObject:indexPath];
            }
            if (visibleMatches.count) [self.tableView reloadRowsAtIndexPaths:visibleMatches withRowAnimation:UITableViewRowAnimationNone];
        });
    });
}

- (void)scrollToSelectedItemIfNeeded {
    if (!self.selectedName.length) return;
    NSUInteger itemIndex = [self.visibleItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
        return [item[@"fileName"] isEqualToString:self.selectedName];
    }];
    if (itemIndex == NSNotFound) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)itemIndex inSection:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath.row < [self.tableView numberOfRowsInSection:0]) {
            [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        }
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleItems.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"overlayVideo"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"overlayVideo"];
    NSDictionary *item = self.visibleItems[(NSUInteger)indexPath.row];
    NSString *fileName = item[@"fileName"] ?: @"";
    cell.textLabel.text = CCBGDisplayNameForItem(item);
    cell.detailTextLabel.text = fileName;
    UIImage *thumbnail = [self cachedOverlayPickerThumbnailForItem:item];
    if (!thumbnail) {
        [self loadOverlayPickerThumbnailForItem:item];
        thumbnail = [UIImage systemImageNamed:CCBGIsVideoName(fileName) ? @"video.fill" : @"photo.fill"];
    }
    cell.imageView.image = thumbnail;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 7.0;
    cell.accessoryType = [fileName isEqualToString:self.selectedName] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *fileName = self.visibleItems[(NSUInteger)indexPath.row][@"fileName"];
    void (^handler)(NSString *) = self.selectionHandler;
    [self dismissViewControllerAnimated:YES completion:^{ if (fileName.length && handler) handler(fileName); }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *fileName = self.visibleItems[(NSUInteger)indexPath.row][@"fileName"] ?: @"";
    NSMutableArray<NSString *> *favorites = [CCBGStringArrayPreference(@"systemOverlayFavoriteMedia") mutableCopy];
    BOOL favorite = [favorites containsObject:fileName];
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:favorite ? @"取消收藏" : @"收藏" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSMutableArray<NSString *> *updated = [CCBGStringArrayPreference(@"systemOverlayFavoriteMedia") mutableCopy];
        if ([updated containsObject:fileName]) [updated removeObject:fileName];
        else if (fileName.length) [updated insertObject:fileName atIndex:0];
        CCBGSetPreferenceValue(@"systemOverlayFavoriteMedia", updated);
        if (self.scopeControl.selectedSegmentIndex == 2) [self scopeChanged:self.scopeControl];
        completionHandler(YES);
    }];
    action.backgroundColor = favorite ? UIColor.systemGrayColor : UIColor.systemYellowColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) {
        self.filteredItems = nil;
    } else {
        NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
        for (NSDictionary *item in self.items) {
            NSString *displayName = CCBGDisplayNameForItem(item);
            NSString *fileName = item[@"fileName"] ?: @"";
            if ([displayName localizedCaseInsensitiveContainsString:query] || [fileName localizedCaseInsensitiveContainsString:query]) [matches addObject:item];
        }
        self.filteredItems = matches;
    }
    [self.tableView reloadData];
}

- (void)cancelSelection { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

static NSArray<NSDictionary *> *CCBGFastOverlayItems(void) {
    NSArray<NSDictionary *> *preloadedItems = nil;
    @synchronized (CCBGPreloadedOverlayAssets) {
        preloadedItems = [CCBGPreloadedOverlayCatalog copy];
    }
    if (preloadedItems.count) return preloadedItems;
    return CCBGMediaItemsForModule(CCBGLoadMediaCatalog(), -1);
}

static NSString *CCBGOverlayAssetCacheKey(NSDictionary *item) {
    return [NSString stringWithFormat:@"%@|%.3f", CCBGPathForItem(item) ?: @"", [item[@"startTime"] doubleValue]];
}

static NSString *CCBGOverlayFrameCachePath(NSDictionary *item) {
    NSString *name = item[@"fileName"] ?: @"media";
    NSString *safeName = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    NSString *directory = @"/var/mobile/Library/CleanCCBG2x2/OverlayFrames";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%lld.jpg", safeName, llround([item[@"startTime"] doubleValue] * 1000.0)]];
}

static void CCBGPrewarmOverlayMedia(void) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (CCBGPrewarmStateLock()) {
        if (CCBGPrewarmInFlight) return;
        if (CCBGPrewarmLastCompletedAt > 0.0 && now - CCBGPrewarmLastCompletedAt < 20.0) return;
        CCBGPrewarmInFlight = YES;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<NSDictionary *> *catalog = CCBGAvailableOverlayItems();
        @synchronized (CCBGPreloadedOverlayAssets) { CCBGPreloadedOverlayCatalog = [catalog copy]; }
        // SpringBoard used to pre-export every media item referenced by every
        // possible module state here. AVFoundation does that work in helper
        // processes, which keeps backboardd/xpcproxy busy even while Control
        // Center is closed. Keep the catalog hot, but let each visible overlay
        // decode only its currently displayed item on demand.
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (CCBGPrewarmStateLock()) {
                CCBGPrewarmInFlight = NO;
                CCBGPrewarmLastCompletedAt = NSProcessInfo.processInfo.systemUptime;
            }
            NSArray<CCBGSystemOverlayView *> *views = nil;
            @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
            for (CCBGSystemOverlayView *overlay in views) {
                BOOL needsRecovery = CCBGControlCenterPresentationVisible && overlay.window && !overlay.hidden && !overlay.player.currentItem;
                if (!needsRecovery) continue;
                overlay.configurationSignature = nil;
                [overlay reloadAfterPreferenceChange];
                [overlay setPlaybackVisible:YES];
            }
        });
    });
}

static void CCBGScheduleStartupOverlayRefreshes(void) {
    // One delayed catalog retry is enough for protected-data startup. Repeated
    // media warmups multiply AVFoundation/XPC work without improving the
    // first Control Center presentation.
    NSArray<NSNumber *> *delays = @[@2.0];
    for (NSNumber *delayValue in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (CCBGOverlayStartupRefreshPasses >= delays.count) return;
            CCBGOverlayStartupRefreshPasses++;
            CCBGPrewarmOverlayMedia();
        });
    }
}

static void CCBGFindArtwork(UIView *view, UIView *excluded, UIImage **bestImage, CGFloat *bestScore) {
    if (view == excluded || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        UIImage *image = imageView.image;
        CGFloat width = CGRectGetWidth(imageView.bounds);
        CGFloat height = CGRectGetHeight(imageView.bounds);
        CGFloat ratio = height > 0 ? width / height : 0;
        CGFloat score = width * height;
        if (image && width >= 48 && height >= 48 && ratio >= 0.72 && ratio <= 1.38 && score > *bestScore) {
            *bestImage = image;
            *bestScore = score;
        }
    }
    for (UIView *subview in view.subviews) CCBGFindArtwork(subview, excluded, bestImage, bestScore);
}

static UIImage *CCBGArtworkInView(UIView *root, UIView *excluded) {
    UIImage *bestImage = nil;
    CGFloat bestScore = 0;
    CCBGFindArtwork(root, excluded, &bestImage, &bestScore);
    return bestImage;
}

static void CCBGFindArtworkView(UIView *view, UIView *excluded, UIImageView **bestView, CGFloat *bestScore) {
    if (view == excluded || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        CGFloat width = CGRectGetWidth(imageView.bounds);
        CGFloat height = CGRectGetHeight(imageView.bounds);
        CGFloat ratio = height > 0 ? width / height : 0;
        CGFloat score = width * height;
        if (imageView.image && width >= 48 && height >= 48 && ratio >= 0.72 && ratio <= 1.38 && score > *bestScore) {
            *bestView = imageView;
            *bestScore = score;
        }
    }
    for (UIView *subview in view.subviews) CCBGFindArtworkView(subview, excluded, bestView, bestScore);
}

static UIImageView *CCBGArtworkViewInView(UIView *root, UIView *excluded) {
    UIImageView *bestView = nil;
    CGFloat bestScore = 0;
    CCBGFindArtworkView(root, excluded, &bestView, &bestScore);
    return bestView;
}

@implementation CCBGSystemOverlayView
- (UIView *)c2AnimationContainerView {
    return self;
}

// BetterCC uses the legacy spelling on some iOS 16 builds. Keep both
// selectors available because the transition path is dynamically dispatched.
- (UIView *)caAnimationContainerView {
    return self;
}

- (instancetype)initWithKind:(CCBGSystemOverlayKind)kind {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _kind = kind;
    _playbackRate = 1.0;
    _targetOpacity = 0.0;
    _adaptiveExpandedFrameEnabled = YES;
    _hasPresented = NO;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.opaque = NO;
    self.alpha = 0.0;
    self.hidden = YES;
    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.06];
    self.layer.borderWidth = 0.6;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.layer.shadowOpacity = 0.0;
    if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
    _mediaContainerView = [[UIView alloc] initWithFrame:self.bounds];
    _mediaContainerView.userInteractionEnabled = NO;
    _mediaContainerView.clipsToBounds = YES;
    _mediaContainerView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];
    if (@available(iOS 13.0, *)) _mediaContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    _mediaContainerView.layer.borderWidth = 0.55;
    _mediaContainerView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [self addSubview:_mediaContainerView];
    _imageView = [[UIImageView alloc] initWithFrame:_mediaContainerView.bounds];
    _imageView.hidden = YES;
    [_mediaContainerView addSubview:_imageView];
    _playerSurfaceView = [[UIView alloc] initWithFrame:_mediaContainerView.bounds];
    _playerSurfaceView.userInteractionEnabled = NO;
    _playerSurfaceView.backgroundColor = UIColor.clearColor;
    _playerSurfaceView.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) _playerSurfaceView.layer.cornerCurve = kCACornerCurveContinuous;
    [_mediaContainerView addSubview:_playerSurfaceView];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    _blurView.frame = _mediaContainerView.bounds;
    [_mediaContainerView addSubview:_blurView];
    _dimView = [[UIView alloc] initWithFrame:_mediaContainerView.bounds];
    _dimView.backgroundColor = UIColor.blackColor;
    [_mediaContainerView addSubview:_dimView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:@"com.zjc.cleanccbg2x2.module-layout-orientation" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(environmentDidChange:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    return self;
}

- (BOOL)shouldShowExpandedControls {
    return self.expandedPresentation &&
        CCBGOverlayUsesCleanTakeover(self) &&
        CGRectGetHeight(self.bounds) >= 220.0;
}

- (void)buildExpandedControlsIfNeeded {
    if (self.expandedControlPanel) return;
    self.expandedControlPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.expandedControlPanel.backgroundColor = UIColor.clearColor;
    self.expandedControlPanel.layer.cornerRadius = 16.0;
    if (@available(iOS 13.0, *)) self.expandedControlPanel.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedControlPanel.layer.borderWidth = 0.35;
    self.expandedControlPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    self.expandedControlPanel.layer.masksToBounds = YES;
    self.expandedControlPanel.hidden = YES;
    self.expandedControlPanel.userInteractionEnabled = YES;
    [self addSubview:self.expandedControlPanel];

    self.expandedPanelMaterial = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    self.expandedPanelMaterial.alpha = 0.82;
    self.expandedPanelMaterial.userInteractionEnabled = NO;
    [self.expandedControlPanel addSubview:self.expandedPanelMaterial];

    self.expandedStateLabel = [UILabel new];
    self.expandedStateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    self.expandedStateLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.expandedStateLabel.adjustsFontSizeToFitWidth = YES;
    self.expandedStateLabel.minimumScaleFactor = 0.78;
    self.expandedStateLabel.numberOfLines = 1;
    self.expandedStateLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.expandedControlPanel addSubview:self.expandedStateLabel];

    NSArray<NSString *> *modeTitles = @[@"顺序", @"随机", @"固定"];
    NSArray<NSNumber *> *modeValues = @[@1, @2, @0];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:modeTitles.count];
    for (NSUInteger index = 0; index < modeTitles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = modeValues[index].integerValue;
        [button setTitle:modeTitles[index] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        button.layer.cornerRadius = 9.0;
        if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.masksToBounds = YES;
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.74] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(expandedModeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [buttons addObject:button];
    }
    self.expandedModeButtons = buttons;
    self.expandedModeStack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    self.expandedModeStack.axis = UILayoutConstraintAxisHorizontal;
    self.expandedModeStack.spacing = 3.0;
    self.expandedModeStack.distribution = UIStackViewDistributionFillEqually;
    self.expandedModeStack.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
    self.expandedModeStack.layer.cornerRadius = 11.0;
    if (@available(iOS 13.0, *)) self.expandedModeStack.layer.cornerCurve = kCACornerCurveContinuous;
    self.expandedModeStack.layer.masksToBounds = YES;
    [self.expandedControlPanel addSubview:self.expandedModeStack];

    self.expandedPresetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.expandedPresetButton setTitle:@"视觉" forState:UIControlStateNormal];
    [self.expandedPresetButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    self.expandedPresetButton.accessibilityLabel = @"视觉方案";
    self.expandedCompositionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.expandedCompositionButton setTitle:@"构图" forState:UIControlStateNormal];
    [self.expandedCompositionButton setImage:[UIImage systemImageNamed:@"crop"] forState:UIControlStateNormal];
    self.expandedCompositionButton.accessibilityLabel = @"构图方式";
    self.expandedMediaButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.expandedMediaButton setTitle:@"素材" forState:UIControlStateNormal];
    [self.expandedMediaButton setImage:[UIImage systemImageNamed:@"photo.on.rectangle"] forState:UIControlStateNormal];
    self.expandedMediaButton.accessibilityLabel = @"选择素材";
    NSArray<UIButton *> *actionButtons = @[self.expandedPresetButton, self.expandedCompositionButton, self.expandedMediaButton];
    NSArray<NSString *> *actions = @[
        NSStringFromSelector(@selector(expandedPresetButtonTapped:)),
        NSStringFromSelector(@selector(expandedCompositionButtonTapped:)),
        NSStringFromSelector(@selector(expandedMediaButtonTapped:)),
    ];
    for (NSUInteger index = 0; index < actionButtons.count; index++) {
        UIButton *button = actionButtons[index];
        button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        button.layer.cornerRadius = 9.0;
        if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.masksToBounds = YES;
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:index == 2 ? 0.12 : 0.055];
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.88] forState:UIControlStateNormal];
        [button setTintColor:[UIColor colorWithWhite:1.0 alpha:0.78]];
        [button addTarget:self action:NSSelectorFromString(actions[index]) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(expandedControlTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(expandedControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self.expandedControlPanel addSubview:button];
    }
}

- (void)updateExpandedControls {
    if (!self.expandedControlPanel) return;
    BOOL visible = [self shouldShowExpandedControls];
    self.expandedControlPanel.hidden = !visible;
    self.userInteractionEnabled = visible || CCBGGenericModuleUsesCleanTakeover(self.kind);
    if (!visible) return;
    NSDictionary *module = CCBGGenericModulesByKind[@(self.kind)];
    self.expandedStateLabel.text = module[@"name"] ?: (@[@"连接", @"音乐", @"亮度", @"音量"][(NSUInteger)MAX(0, MIN(3, self.kind - 1))]);
    NSInteger mode = [self playbackMode];
    NSString *contentKey = CCBGOverlayKey(self.kind, self.expandedPresentation ? @"ExpandedContentMode" : @"CompactContentMode");
    NSInteger contentMode = MIN(1, MAX(0, [CCBGReadPreference(contentKey, @1) integerValue]));
    NSString *signature = [NSString stringWithFormat:@"%ld|%ld|%@", (long)mode, (long)contentMode, self.currentItem[@"fileName"] ?: @""];
    if ([signature isEqualToString:self.lastExpandedControlsSignature]) return;
    for (UIButton *button in self.expandedModeButtons) {
        BOOL selected = button.tag == mode;
        button.backgroundColor = selected ? [UIColor colorWithRed:0.16 green:0.46 blue:0.92 alpha:0.78] : UIColor.clearColor;
        [button setTitleColor:selected ? UIColor.whiteColor : [UIColor colorWithWhite:1.0 alpha:0.70] forState:UIControlStateNormal];
    }
    self.expandedCompositionButton.backgroundColor = contentMode == 0 ? [UIColor colorWithWhite:1.0 alpha:0.12] : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.lastExpandedControlsSignature = signature;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL cleanTakeover = CCBGOverlayUsesCleanTakeover(self);
    if (!cleanTakeover && (![self shouldShowExpandedControls] || self.expandedControlPanel.hidden)) return nil;
    if (cleanTakeover) {
        CGPoint panelPoint = [self.expandedControlPanel convertPoint:point fromView:self];
        if (self.expandedPresentation) {
            if (!self.expandedControlPanel.hidden && [self.expandedControlPanel pointInside:panelPoint withEvent:event]) {
                return [super hitTest:point withEvent:event] ?: self;
            }
            CGPoint mediaPoint = [self.mediaContainerView convertPoint:point fromView:self];
            if (![self.mediaContainerView pointInside:mediaPoint withEvent:event]) {
                // The expanded card does not own the margins around itself.
                // Returning nil lets the full-screen backdrop receive the
                // touch and collapse the takeover.
                return nil;
            }
            return [super hitTest:point withEvent:event] ?: self;
        }
        // Compact takeover consumes the whole native tile so the original
        // module cannot be activated underneath the Clean surface.
        return self;
    }
    CGPoint panelPoint = [self.expandedControlPanel convertPoint:point fromView:self];
    if (![self.expandedControlPanel pointInside:panelPoint withEvent:event]) return nil;
    return [super hitTest:point withEvent:event];
}

- (void)applyExpandedMediaOpacity:(CGFloat)opacity {
    CGFloat clamped = MIN(1.0, MAX(0.05, opacity));
    // Match the five-module contract: opacity belongs to the rendered media
    // layers, never to the card or its controls. Applying alpha to the whole
    // container makes the dark takeover backdrop read as a brightness filter.
    self.mediaContainerView.alpha = 1.0;
    self.imageView.alpha = clamped;
    self.playerLayer.opacity = clamped;
    if (self.nativePlayerController && !self.nativePlayerController.view.hidden) {
        self.nativePlayerController.view.alpha = clamped;
    }
}

- (void)attachNativePlayerControllerToHost:(UIViewController *)host {
    AVPlayerViewController *native = self.nativePlayerController;
    if (!native || !host) return;
    if (native.parentViewController == host) return;
    UIViewController *oldParent = native.parentViewController;
    if (oldParent) {
        [native willMoveToParentViewController:nil];
        [native.view removeFromSuperview];
        [native removeFromParentViewController];
    }
    [host addChildViewController:native];
    [self.mediaContainerView addSubview:native.view];
    [native didMoveToParentViewController:host];
}

- (UIViewController *)nativePlayerPresentationHost {
    // The overlay is reparented between the module controller and the
    // Control Center presentation root during expansion. The AVPlayer view
    // must be a child of the controller that owns its current superview, not
    // necessarily the module controller that owns the original native tile.
    // A takeover overlay can be moved from the compact module's view onto
    // Control Center's root canvas. Attach AVKit to the controller that owns
    // that canvas, not to an intermediate responder that may vanish midway
    // through the transition. This mirrors the five-module child-controller
    // relationship while keeping generic takeover reparenting valid.
    if (CCBGOverlayUsesCleanTakeover(self) && self.expandedPresentation) {
        // In third-party modules the expanded takeover is mounted on the
        // Control Center root canvas, which is not always in the original
        // module controller's parent chain. Resolve the owner from the
        // actual mounted root first; otherwise AVKit remains detached forever
        // even though the overlay itself is visible.
        UIView *mountedRoot = CCBGTakeoverRootView(self.hostController);
        UIViewController *mountedRootHost = CCBGViewHostController(mountedRoot);
        if (mountedRootHost && mountedRootHost.isViewLoaded &&
            [self isDescendantOfView:mountedRootHost.view]) return mountedRootHost;
        UIViewController *mountedHost = CCBGTakeoverRootController(self.hostController, self);
        if (mountedHost) return mountedHost;
    }
    UIViewController *responderHost = CCBGViewHostController(self.superview);
    if (responderHost && responderHost.isViewLoaded && [self isDescendantOfView:responderHost.view]) {
        return responderHost;
    }
    UIViewController *fallbackHost = self.hostController;
    if (fallbackHost.isViewLoaded && [self isDescendantOfView:fallbackHost.view]) return fallbackHost;
    return nil;
}

- (void)updateNativePlayerPresentation {
    BOOL hasVideo = CCBGOverlayUsesCleanTakeover(self) && self.expandedPresentation && self.currentItem &&
        CCBGIsVideoName(self.currentItem[@"fileName"]) && self.player && self.player.currentItem;
    AVPlayerItem *playerItem = self.player.currentItem;
    BOOL ready = hasVideo && (playerItem.status == AVPlayerItemStatusReadyToPlay ||
                              self.nativePlayerPresentationFallbackVisible);
    UIViewController *host = [self nativePlayerPresentationHost];
    // Control Center can reparent the takeover view before its new owner is
    // present in the responder/controller chain. AVKit must stay detached in
    // that gap: adding its view without an owning child controller corrupts
    // UIKit containment and can crash SpringBoard during the next transition.
    if (hasVideo && !host) {
        // Control Center briefly has no owning controller while it reparents
        // the takeover view. Keep AVKit attached to its last valid parent and
        // let the recovery pass retry once the new host is mounted. Treating
        // this transient gap as compact would cancel the recovery generation
        // and leave the native controls permanently absent.
        [self scheduleNativePlayerPresentationRecovery];
        return;
    }
    if (hasVideo && !self.nativePlayerController) {
        AVPlayerViewController *controller = [AVPlayerViewController new];
        controller.updatesNowPlayingInfoCenter = NO;
        controller.allowsPictureInPicturePlayback = NO;
        controller.entersFullScreenWhenPlaybackBegins = NO;
        controller.exitsFullScreenWhenPlaybackEnds = NO;
        controller.showsPlaybackControls = YES;
        controller.view.backgroundColor = UIColor.clearColor;
        controller.view.clipsToBounds = YES;
        self.nativePlayerController = controller;
    }
    AVPlayerViewController *native = self.nativePlayerController;
    if (!native) return;
    CGRect frame = self.mediaContainerView.bounds;
    CGFloat expectedNativeAlpha = ready ? MIN(1.0, MAX(0.05, self.targetOpacity)) : 0.0;
    UIView *nativeView = native.view;
    BOOL nativeStateStable = hasVideo && host && native.parentViewController == host &&
        native.player == self.player && nativeView.superview == self.mediaContainerView &&
        !nativeView.hidden && nativeView.userInteractionEnabled == ready &&
        fabs(nativeView.alpha - expectedNativeAlpha) <= 0.01 &&
        CGRectEqualToRect(nativeView.frame, frame) && native.showsPlaybackControls &&
        [native.videoGravity isEqualToString:(self.playerLayer.videoGravity ?: AVLayerVideoGravityResizeAspectFill)] &&
        self.mediaContainerView.userInteractionEnabled == ready &&
        self.playerLayer.hidden == ready && self.imageView.hidden == ready;
    NSString *presentationSignature = [NSString stringWithFormat:@"%p|%p|%p|%@|%@|%d|%d|%d|%.3f",
        native, self.player, host, NSStringFromCGRect(frame),
        NSStringFromCGRect(self.mediaContainerView.bounds), ready,
        nativeView.hidden, nativeView.userInteractionEnabled, nativeView.alpha];
    if (nativeStateStable && [presentationSignature isEqualToString:self.lastNativePresentationStateSignature]) return;
    // Detach any stale UIKit parent before touching the transport view. The
    // host can be temporarily nil while Control Center is rebuilding its
    // responder chain, but the old parent must still be removed in that
    // window or UIKit can validate the moved view against the wrong host.
    if (hasVideo) [self attachNativePlayerControllerToHost:host];
    if (hasVideo) {
        if (native.view.superview != self.mediaContainerView) {
            [native.view removeFromSuperview];
            [self.mediaContainerView addSubview:native.view];
        }
        if (native.player != self.player) native.player = self.player;
        native.videoGravity = self.playerLayer.videoGravity ?: AVLayerVideoGravityResizeAspectFill;
        if (!CGRectEqualToRect(native.view.frame, frame)) native.view.frame = frame;
        native.showsPlaybackControls = YES;
        native.view.hidden = NO;
        native.view.userInteractionEnabled = ready;
        native.view.alpha = ready ? MIN(1.0, MAX(0.05, self.targetOpacity)) : 0.0;
        self.mediaContainerView.userInteractionEnabled = ready;
        // Keep the cover/player-layer visible until AVKit has a ready item;
        // then make AVPlayerViewController the single rendered surface.
        self.playerLayer.hidden = ready;
        self.imageView.hidden = ready;
        self.nativePlayerAttachedForExpandedContent = YES;
        [self.mediaContainerView bringSubviewToFront:native.view];
        [self.mediaContainerView bringSubviewToFront:self.blurView];
        [self.mediaContainerView bringSubviewToFront:self.dimView];
        [self.mediaContainerView bringSubviewToFront:native.view];
        self.lastNativePresentationStateSignature = [NSString stringWithFormat:@"%p|%p|%p|%@|%@|%d|%d|%d|%.3f",
            native, self.player, host, NSStringFromCGRect(frame),
            NSStringFromCGRect(self.mediaContainerView.bounds), ready,
            native.view.hidden, native.view.userInteractionEnabled, native.view.alpha];
        return;
    }
    [self detachNativePlayerForCompactPresentation];
}

- (void)scheduleNativePlayerPresentationRecovery {
    if (!CCBGOverlayUsesCleanTakeover(self) || !self.expandedPresentation ||
        !self.currentItem || !CCBGIsVideoName(self.currentItem[@"fileName"]) ||
        !self.player.currentItem || !CCBGControlCenterPresentationVisible) return;
    if (self.nativePresentationRecoveryArmed) return;
    self.nativePresentationRecoveryArmed = YES;
    NSUInteger generation = ++self.nativePresentationRecoveryGeneration;
    NSArray<NSNumber *> *delays = @[@0.0, @0.05, @0.18, @0.45, @0.80, @1.20, @1.80, @2.80];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayValue in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.nativePresentationRecoveryGeneration || !CCBGControlCenterPresentationVisible) return;
            if (!self.expandedPresentation || !CCBGOverlayUsesCleanTakeover(self) ||
                !self.player.currentItem || !self.currentItem ||
                !CCBGIsVideoName(self.currentItem[@"fileName"])) {
                self.nativePresentationRecoveryArmed = NO;
                return;
            }
            AVPlayerItem *item = self.player.currentItem;
            if (delayValue.doubleValue >= 0.45 && item.status != AVPlayerItemStatusFailed) {
                self.nativePlayerPresentationFallbackVisible = YES;
            }
            UIViewController *presentationHost = [self nativePlayerPresentationHost];
            if (!presentationHost) {
                if (delayValue.doubleValue >= 2.80) self.nativePresentationRecoveryArmed = NO;
                return;
            }
            UIView *expectedHost = self.mediaContainerView;
            CGRect expectedFrame = expectedHost.bounds;
            AVPlayerViewController *native = self.nativePlayerController;
            BOOL nativeControlsReady = item.status == AVPlayerItemStatusReadyToPlay ||
                self.nativePlayerPresentationFallbackVisible;
            CGFloat expectedAlpha = nativeControlsReady ? MIN(1.0, MAX(0.05, self.targetOpacity)) : 0.0;
            BOOL needsRepair = !native || native.player != self.player ||
                native.view.superview != expectedHost ||
                !CGRectEqualToRect(native.view.frame, expectedFrame) ||
                native.view.hidden != NO ||
                native.view.userInteractionEnabled != nativeControlsReady ||
                fabs(native.view.alpha - expectedAlpha) > 0.01;
            if (needsRepair) [self updateNativePlayerPresentation];
            native = self.nativePlayerController;
            if (native) {
                [self attachNativePlayerControllerToHost:presentationHost];
                if (native.parentViewController != presentationHost) return;
                if (native.player != self.player) native.player = self.player;
                if (native.view.superview != expectedHost) {
                    [native.view removeFromSuperview];
                    [expectedHost addSubview:native.view];
                }
                native.view.frame = expectedFrame;
                native.view.hidden = NO;
                native.view.userInteractionEnabled = nativeControlsReady;
                native.view.alpha = expectedAlpha;
                native.showsPlaybackControls = YES;
                [expectedHost bringSubviewToFront:native.view];
            }
            if (delayValue.doubleValue >= 2.80) self.nativePresentationRecoveryArmed = NO;
        });
    }
}

- (void)detachNativePlayerForCompactPresentation {
    self.nativePresentationRecoveryGeneration += 1;
    self.nativePresentationRecoveryArmed = NO;
    self.nativePlayerAttachedForExpandedContent = NO;
    self.lastNativePresentationStateSignature = nil;
    AVPlayerViewController *native = self.nativePlayerController;
    if (!native) return;
    native.showsPlaybackControls = NO;
    native.view.userInteractionEnabled = NO;
    native.view.hidden = YES;
    native.view.alpha = 0.0;
    // The overlay moves from the root takeover canvas back to the compact
    // module. Detach its real AVKit child before moving the visual surface so
    // UIKit cannot retain a stale parent/controller pairing.
    if (native.parentViewController) {
        [native willMoveToParentViewController:nil];
        [native.view removeFromSuperview];
        [native removeFromParentViewController];
    }
    self.mediaContainerView.userInteractionEnabled = NO;
    self.nativePlayerPresentationFallbackVisible = NO;
    if (self.player.currentItem && self.currentItem && CCBGIsVideoName(self.currentItem[@"fileName"])) {
        self.playerLayer.hidden = NO;
        self.imageView.hidden = self.playerLayer.readyForDisplay;
    }
}

- (void)expandedModeButtonTapped:(UIButton *)button {
    NSString *suffix = self.expandedPresentation ? @"ExpandedPlaybackMode" : @"CompactPlaybackMode";
    CCBGWritePreference(CCBGOverlayKey(self.kind, suffix), @(MIN(2, MAX(0, button.tag))));
    self.configurationSignature = nil;
    [self reloadIfNeeded:YES];
    [self setPlaybackVisible:YES];
    [self updateExpandedControls];
}

- (void)expandedPresetButtonTapped:(UIButton *)button {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"视觉方案" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *presets = @{
        @"标准": @{ @"Opacity": @0.65, @"Blur": @0.0, @"Dim": @0.03 },
        @"柔和": @{ @"Opacity": @0.52, @"Blur": @0.22, @"Dim": @0.08 },
        @"清晰": @{ @"Opacity": @0.82, @"Blur": @0.0, @"Dim": @0.0 },
    };
    for (NSString *title in @[ @"标准", @"柔和", @"清晰" ]) {
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSDictionary *values = presets[title];
            CCBGWritePreferences(@{
                CCBGOverlayKey(self.kind, @"Opacity"): values[@"Opacity"],
                CCBGOverlayKey(self.kind, @"Blur"): values[@"Blur"],
                CCBGOverlayKey(self.kind, @"Dim"): values[@"Dim"],
            });
            self.configurationSignature = nil;
            [self reloadIfNeeded:YES];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self.hostController presentViewController:menu animated:YES completion:nil];
}

- (void)expandedCompositionButtonTapped:(UIButton *)button {
    NSString *key = CCBGOverlayKey(self.kind, self.expandedPresentation ? @"ExpandedContentMode" : @"CompactContentMode");
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"构图方式" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSArray *option in @[ @[ @"完整", @0 ], @[ @"填充", @1 ] ]) {
        [menu addAction:[UIAlertAction actionWithTitle:option[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            CCBGWritePreference(key, option[1]);
            self.configurationSignature = nil;
            [self reloadIfNeeded:YES];
            [self updateExpandedControls];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self.hostController presentViewController:menu animated:YES completion:nil];
}

- (void)expandedMediaButtonTapped:(UIButton *)button {
    [self presentVideoSelection];
}

- (void)expandedControlTouchDown:(UIButton *)button {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.08 animations:^{ button.transform = CGAffineTransformMakeScale(0.965, 0.965); button.alpha = 0.90; }];
}

- (void)expandedControlTouchUp:(UIButton *)button {
    [UIView animateWithDuration:0.16 animations:^{ button.transform = CGAffineTransformIdentity; button.alpha = 1.0; }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.clipsToBounds = YES;
    self.layer.masksToBounds = YES;
    [self buildExpandedControlsIfNeeded];
    BOOL cleanTakeover = CCBGOverlayUsesCleanTakeover(self);
    if (cleanTakeover) [self suppressNativeContentInHostView:self.nativeHostView ?: self.superview];
    else [self restoreSuppressedNativeContent];
    // Compact tiles should remain edge-to-edge. Expanded cards get a small,
    // stable breathing margin so the media reads as a surface inside the
    // native module instead of an opaque full-bleed rectangle.
    CGFloat shortestSide = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    CGFloat mediaInset = 0.0;
    if (self.expandedPresentation && shortestSide > 140.0) {
        mediaInset = MIN(12.0, MAX(7.0, shortestSide * 0.035));
    }
    BOOL showControls = [self shouldShowExpandedControls];
    CGFloat controlsHeight = showControls ? 108.0 : 0.0;
    CGRect mediaFrame = CGRectInset(self.bounds, mediaInset, mediaInset);
    if (showControls) {
        mediaFrame.size.height = MAX(1.0, mediaFrame.size.height - controlsHeight - 8.0);
    }
    BOOL sliderOverlay = self.kind == CCBGSystemOverlayKindBrightness || self.kind == CCBGSystemOverlayKindVolume;
    self.mediaContainerView.frame = mediaFrame;
    self.opaque = NO;
    self.backgroundColor = cleanTakeover
        ? UIColor.clearColor
        : (self.expandedPresentation && !sliderOverlay
            ? [UIColor colorWithWhite:0.0 alpha:0.06]
            : UIColor.clearColor);
    self.layer.borderWidth = cleanTakeover ? 0.0 : (self.expandedPresentation && !sliderOverlay ? 0.45 : 0.0);
    self.mediaContainerView.backgroundColor = cleanTakeover
        ? UIColor.clearColor
        : (self.expandedPresentation && !sliderOverlay
            ? [UIColor colorWithWhite:0.0 alpha:0.08]
            : UIColor.clearColor);
    if (cleanTakeover && self.expandedPresentation && self.visibilityTargetVisible) {
        // Keep the card and its controls fully hittable. Opacity belongs to
        // the rendered media layers, just like the five-module implementation.
        self.alpha = 1.0;
        [self applyExpandedMediaOpacity:self.targetOpacity];
    }
    self.mediaContainerView.layer.borderWidth = cleanTakeover ? 0.0 : (self.expandedPresentation && !sliderOverlay ? 0.35 : 0.0);
    CGFloat mediaRadius = MAX(0.0, self.layer.cornerRadius - mediaInset);
    self.mediaContainerView.layer.cornerRadius = mediaRadius;
    self.mediaContainerView.layer.masksToBounds = YES;
    self.imageView.layer.cornerRadius = mediaRadius;
    self.imageView.layer.masksToBounds = YES;
    self.imageView.frame = self.mediaContainerView.bounds;
    self.playerSurfaceView.frame = self.mediaContainerView.bounds;
    self.playerSurfaceView.layer.cornerRadius = mediaRadius;
    self.playerSurfaceView.layer.masksToBounds = YES;
    self.blurView.frame = self.mediaContainerView.bounds;
    self.dimView.frame = self.mediaContainerView.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = self.playerSurfaceView.bounds;
    self.playerLayer.cornerRadius = mediaRadius;
    self.playerLayer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) self.playerLayer.cornerCurve = kCACornerCurveContinuous;
    [CATransaction commit];
    [self updateNativePlayerPresentation];
    if (self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self) &&
        self.player.currentItem && self.currentItem && CCBGIsVideoName(self.currentItem[@"fileName"])) {
        [self scheduleNativePlayerPresentationRecovery];
    }
    BOOL sceneLayoutGeometryChanged = !self.hasSceneLayoutGeometry ||
        !CGRectEqualToRect(self.lastSceneLayoutBounds, self.bounds) ||
        !CGRectEqualToRect(self.lastSceneLayoutMediaBounds, self.mediaContainerView.bounds) ||
        self.lastSceneLayoutExpanded != self.expandedPresentation;
    if (sceneLayoutGeometryChanged) {
        [self applyCachedSceneComposition];
        self.lastSceneLayoutBounds = self.bounds;
        self.lastSceneLayoutMediaBounds = self.mediaContainerView.bounds;
        self.lastSceneLayoutExpanded = self.expandedPresentation;
        self.hasSceneLayoutGeometry = YES;
    }
    if (showControls) {
        self.expandedControlPanel.hidden = NO;
        self.expandedControlPanel.frame = CGRectMake(mediaInset + 4.0,
                                                      CGRectGetHeight(self.bounds) - controlsHeight - mediaInset,
                                                      MAX(1.0, CGRectGetWidth(self.bounds) - (mediaInset + 4.0) * 2.0),
                                                      controlsHeight);
        self.expandedPanelMaterial.frame = self.expandedControlPanel.bounds;
        CGFloat panelWidth = CGRectGetWidth(self.expandedControlPanel.bounds);
        self.expandedStateLabel.frame = CGRectMake(12.0, 8.0, MAX(0.0, panelWidth - 24.0), 22.0);
        self.expandedModeStack.frame = CGRectMake(12.0, 34.0, MAX(0.0, panelWidth - 24.0), 30.0);
        CGFloat actionWidth = MAX(0.0, (panelWidth - 36.0) / 3.0);
        CGFloat actionY = controlsHeight - 38.0;
        self.expandedPresetButton.frame = CGRectMake(12.0, actionY, actionWidth, 30.0);
        self.expandedCompositionButton.frame = CGRectMake(18.0 + actionWidth, actionY, actionWidth, 30.0);
        self.expandedMediaButton.frame = CGRectMake(24.0 + actionWidth * 2.0, actionY, actionWidth, 30.0);
        [self updateExpandedControls];
        [self bringSubviewToFront:self.expandedControlPanel];
    } else {
        self.expandedControlPanel.hidden = YES;
        self.userInteractionEnabled = cleanTakeover;
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSUInteger generation = ++self.windowAttachmentGeneration;
    // A compact overlay can receive controller disappearance callbacks while
    // another module expands. Keep its player alive in that case; only stop
    // playback when this overlay actually leaves the window.
    // The compact dismissal path remains equivalent to: if (!self.window && !self.expandedPresentation).
    if (!self.window && (!self.expandedPresentation || CCBGGenericModuleUsesCleanTakeover(self.kind))) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.windowAttachmentGeneration || self.window) return;
            // Reparenting during a takeover expansion briefly removes the
            // overlay from its old host. The native module is still mounted
            // in that case, so keep the Clean expansion state intact.
            if (self.expandedPresentation && self.hostController.viewIfLoaded.window) return;
            if (self.expandedPresentation && CCBGGenericModuleUsesCleanTakeover(self.kind)) {
                CCBGClearGenericExpandedState(self.hostController);
                self.expandedPresentation = NO;
                // The overlay is about to be detached from the window and
                // may be claimed by a replacement native controller. Break
                // the old AVPlayerViewController containment first.
                [self detachNativePlayerForCompactPresentation];
                [self restoreSuppressedNativeContent];
            }
            [self pausePlaybackPreservingPresentation];
            // Leaving the window is also the point at which a reused
            // Control Center host can have finished replacing this module's
            // controller.  Re-scan the host after the reparenting settles so
            // a detached overlay cannot remain missing for the next open.
            if (CCBGPluginEnabled() && (self.hostController.viewIfLoaded.window || CCBGLastPresentationRoot.viewIfLoaded.window)) {
                CCBGScheduleTrackedOverlayRefreshOnce();
            }
        });
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection && previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    CCBGInvalidateSceneRuntimeCaches();
    self.configurationSignature = nil;
    if (!CCBGControlCenterPresentationVisible) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CCBGControlCenterPresentationVisible) return;
        [weakSelf reloadIfNeeded:YES];
    });
}

- (CGRect)expandedFrameForHostView:(UIView *)hostView module:(NSDictionary *)genericModule {
    BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(self.kind);
    if (!hostView || (!genericModule && !cleanTakeover)) return hostView.bounds;
    CGRect bounds = hostView.bounds;
    UIEdgeInsets safeInsets = hostView.safeAreaInsets;
    CGRect availableBounds = UIEdgeInsetsInsetRect(bounds, safeInsets);
    if (CGRectGetWidth(availableBounds) < 1.0 || CGRectGetHeight(availableBounds) < 1.0) availableBounds = bounds;
    // A takeover module must use the same canvas as the five custom modules;
    // its native ExpandedWidth/ExpandedHeight and capability are deliberately
    // ignored while the switch is enabled.
    CGSize cleanMaximum = CCBGCleanExpandedMaximumSize();
    CGFloat width = cleanTakeover ? cleanMaximum.width : CCBGGenericModuleExpandedDimension(genericModule, @"ExpandedWidth", 420.0, YES);
    CGFloat height = cleanTakeover ? cleanMaximum.height : CCBGGenericModuleExpandedDimension(genericModule, @"ExpandedHeight", 480.0, NO);
    CGSize naturalSize = self.naturalVideoSize;
    if (cleanTakeover && [CCBGReadPreference(@"adaptiveExpandedSizeEnabled", @YES) boolValue]) {
        CGSize adaptiveSize = CCBGCleanExpandedSizeForNaturalSize(naturalSize);
        width = adaptiveSize.width;
        height = adaptiveSize.height;
    } else if (!cleanTakeover && self.adaptiveExpandedFrameEnabled && naturalSize.width > 1.0 && naturalSize.height > 1.0) {
        CGFloat aspect = fabs(naturalSize.width / naturalSize.height);
        // Keep extreme camera ratios readable without allowing a one-pixel
        // sliver to become the module's expanded surface.
        aspect = MIN(2.0, MAX(0.5, aspect));
        if (width / height > aspect) width = height * aspect;
        else height = width / aspect;
        if (width < 220.0 && CGRectGetWidth(availableBounds) >= 244.0) {
            width = MIN(220.0, CGRectGetWidth(availableBounds) - 24.0);
            height = width / aspect;
        }
        if (height < 220.0 && CGRectGetHeight(availableBounds) >= 244.0) {
            height = MIN(220.0, CGRectGetHeight(availableBounds) - 24.0);
            width = height * aspect;
        }
    }
    self.preferredExpandedFrameSize = CGSizeMake(width, height);
    width = MIN(width, MAX(1.0, CGRectGetWidth(availableBounds) - 24.0));
    height = MIN(height, MAX(1.0, CGRectGetHeight(availableBounds) - 24.0));
    if (cleanTakeover) self.preferredExpandedFrameSize = CGSizeMake(width, height);
    return CGRectMake(CGRectGetMinX(availableBounds) + floor((CGRectGetWidth(availableBounds) - width) * 0.5),
                      CGRectGetMinY(availableBounds) + floor((CGRectGetHeight(availableBounds) - height) * 0.5),
                      width,
                      height);
}

- (void)applyAdaptiveFrameForHostView:(UIView *)hostView {
    if (!hostView) return;
    NSDictionary *genericModule = CCBGGenericModulesByKind[@(self.kind)];
    BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(self.kind);
    CGRect previousFrame = self.frame;
    CGRect targetFrame = hostView.bounds;
    if ((genericModule || cleanTakeover) && self.expandedPresentation) {
        targetFrame = [self expandedFrameForHostView:hostView module:genericModule];
    }
    // Reload/layout callbacks can arrive again while the collapse animator is
    // running. Let that animator own the frame until completion; otherwise a
    // harmless media readiness pass would write hostView.bounds and re-create
    // the same one-frame snap this transition is meant to remove.
    if (!self.collapseAnimationPending && !self.expandedPresentation && cleanTakeover &&
        self.frameAnimator.state == UIViewAnimatingStateActive) {
        return;
    }
    BOOL frameChanged = !CGRectEqualToRect(previousFrame, targetFrame);
    BOOL animateCollapse = self.collapseAnimationPending && !self.expandedPresentation &&
        self.window && self.hasPresented && frameChanged;
    if (animateCollapse) {
        self.collapseAnimationPending = NO;
        if (self.frameAnimator.state == UIViewAnimatingStateActive) {
            [self.frameAnimator stopAnimation:YES];
            [self.frameAnimator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
        }
        // CCBGPlaceOverlay: preserves the converted expanded frame while it
        // moves the surface back into the compact host. Keep that frame as
        // the first animation sample; assigning hostView.bounds before the
        // animator starts is the snap that made outside dismissal feel hard.
        CGRect collapseStartFrame = self.frame;
        BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        __weak typeof(self) weakSelf = self;
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
            initWithDuration:(reduceMotion ? 0.12 : 0.24)
            curve:(reduceMotion ? UIViewAnimationCurveEaseOut : UIViewAnimationCurveEaseInOut)
            animations:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.frame = targetFrame;
            [self setNeedsLayout];
            [self layoutIfNeeded];
        }];
        // Reassert the preserved frame after creating the animator. UIKit can
        // perform a layout pass while the host is being reparented, and that
        // pass must not move the surface to compact bounds before startAnimation.
        self.frame = collapseStartFrame;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        [animator addCompletion:^(UIViewAnimatingPosition position) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.frameAnimator != animator) return;
            self.frame = targetFrame;
            self.frameAnimator = nil;
        }];
        self.frameAnimator = animator;
        [animator startAnimation];
        return;
    }
    if (frameChanged) {
        BOOL animateFrame = (genericModule || cleanTakeover) && self.expandedPresentation && self.window && self.hasPresented &&
            !UIAccessibilityIsReduceMotionEnabled();
        if (animateFrame) {
            if (self.frameAnimator.state == UIViewAnimatingStateActive) {
                [self.frameAnimator stopAnimation:YES];
                [self.frameAnimator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
            }
            __weak typeof(self) weakSelf = self;
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
                initWithDuration:0.18 curve:UIViewAnimationCurveEaseOut animations:^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.frame = targetFrame;
                [self setNeedsLayout];
                [self layoutIfNeeded];
            }];
            [animator addCompletion:^(UIViewAnimatingPosition position) {
                __strong typeof(weakSelf) self = weakSelf;
                if (self.frameAnimator == animator) self.frameAnimator = nil;
            }];
            self.frameAnimator = animator;
            [animator startAnimation];
            return;
        }
        if ((!genericModule && !cleanTakeover) || !self.expandedPresentation) self.frame = hostView.bounds;
        else self.frame = targetFrame;
    }
    if (!frameChanged) return;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

static BOOL CCBGHasOverlayPreferenceSnapshot(void) {
    return [NSThread.currentThread.threadDictionary[CCBGOverlayPreferenceSnapshotThreadKey] isKindOfClass:NSDictionary.class];
}

- (void)dealloc {
    [self recordActivePlaybackDurationIfNeeded];
    if (self.frameAnimator.state == UIViewAnimatingStateActive) [self.frameAnimator stopAnimation:YES];
    self.frameAnimator = nil;
    self.playbackGeneration++;
    self.readinessCheckActive = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.gestureHostView removeGestureRecognizer:self.swipeLeft];
    [self.gestureHostView removeGestureRecognizer:self.swipeRight];
    [self.gestureHostView removeGestureRecognizer:self.appearancePan];
    [self.gestureHostView removeGestureRecognizer:self.stateTap];
    [self.gestureHostView removeGestureRecognizer:self.longPress];
    CCBGRemoveTakeoverBackdrop(self);
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    UIViewController *nativeParent = self.nativePlayerController.parentViewController;
    if (nativeParent) {
        [self.nativePlayerController willMoveToParentViewController:nil];
        [self.nativePlayerController.view removeFromSuperview];
        [self.nativePlayerController removeFromParentViewController];
    } else {
        [self.nativePlayerController.view removeFromSuperview];
    }
    self.nativePlayerController = nil;
    [self.playerLayer removeFromSuperlayer];
}

- (void)recordSuccessfulMediaStartIfNeeded {
    if (self.healthStartRecorded || !self.currentItem[@"fileName"]) return;
    self.healthStartRecorded = YES;
    self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
    self.healthPlaybackFileName = [self.currentItem[@"fileName"] copy];
    CCBGRecordMediaPlaybackStart(self.healthPlaybackFileName, -1, MAX(0.0, self.healthPlaybackStartedAt - self.mediaPresentationStartedAt));
}

- (void)recordActivePlaybackDurationIfNeeded {
    NSString *fileName = self.healthPlaybackFileName;
    NSTimeInterval startedAt = self.healthPlaybackStartedAt;
    self.healthPlaybackFileName = nil;
    self.healthPlaybackStartedAt = 0;
    if (fileName.length && startedAt > 0) {
        CCBGRecordMediaPlaybackDuration(fileName, NSProcessInfo.processInfo.systemUptime - startedAt);
    }
}

- (void)mediaMemoryWarning:(NSNotification *)notification {
    @synchronized (CCBGPreloadedOverlayAssets) {
        [CCBGPreloadedOverlayAssets removeAllObjects];
        CCBGPreloadedOverlayCatalog = nil;
    }
    [CCBGPreloadedOverlayFrames removeAllObjects];
    [CCBGPreloadedOverlayImages removeAllObjects];
    if (self.currentItem[@"fileName"]) {
        CCBGRecordMediaMemoryPressure(self.currentItem[@"fileName"]);
    }
}

- (void)environmentDidChange:(NSNotification *)notification {
    BOOL orientationRefresh = [notification.name isEqualToString:UIDeviceOrientationDidChangeNotification] ||
        [notification.name isEqualToString:@"com.zjc.cleanccbg2x2.module-layout-orientation"];
    // Retained module views continue receiving system notifications after the
    // Control Center has dismissed.  Record that their configuration is stale,
    // but defer AVFoundation/layout work until the next real presentation.
    if (!CCBGControlCenterPresentationVisible) {
        self.lastConfigurationCheck = 0.0;
        self.pendingSceneOrientationRefresh = NO;
        self.sceneEnvironmentRefreshScheduled = NO;
        return;
    }
    @synchronized (self) {
        self.pendingSceneOrientationRefresh = self.pendingSceneOrientationRefresh || orientationRefresh;
        if (self.sceneEnvironmentRefreshScheduled) return;
        self.sceneEnvironmentRefreshScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL needsOrientationRefresh = NO;
        @synchronized (self) {
            self.sceneEnvironmentRefreshScheduled = NO;
            needsOrientationRefresh = self.pendingSceneOrientationRefresh;
            self.pendingSceneOrientationRefresh = NO;
        }
        if (!CCBGControlCenterPresentationVisible) {
            self.lastConfigurationCheck = 0.0;
            return;
        }
        CCBGInvalidateSceneRuntimeCaches();
        self.lastConfigurationCheck = 0;
        [self reloadIfNeeded:NO];
        [self applyCachedSceneComposition];
        [self applySceneLowPowerPolicy];
        if (needsOrientationRefresh) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self environmentDidChange:nil];
            });
        }
    });
}

- (void)applyCachedSceneComposition {
    CGFloat focalX = self.sceneBaseFocalX;
    CGFloat focalY = self.sceneBaseFocalY;
    if (self.cachedAdaptiveCompositionEnabled && self.window && self.sceneContentMode != 0) {
        CGRect windowBounds = self.window.bounds;
        CGRect moduleRect = [self convertRect:self.bounds toView:self.window];
        if (CGRectGetWidth(windowBounds) > 1.0 && CGRectGetHeight(windowBounds) > 1.0) {
            focalX = MIN(1.0, MAX(0.0, CGRectGetMidX(moduleRect) / CGRectGetWidth(windowBounds)));
            focalY = MIN(1.0, MAX(0.0, CGRectGetMidY(moduleRect) / CGRectGetHeight(windowBounds)));
        }
    }
    CGAffineTransform transform = CGAffineTransformIdentity;
    if (self.sceneContentMode != 0 || self.sceneCropZoom > 1.001) {
        // AVPlayerLayer's aspect-fill already performs the primary crop.
        // Keep the composition nudge restrained so system and third-party
        // tiles do not lose another 12% of the frame by default.
        CGFloat dx = (0.5 - focalX) * self.mediaContainerView.bounds.size.width * 0.10;
        CGFloat dy = (0.5 - focalY) * self.mediaContainerView.bounds.size.height * 0.10;
        CGFloat scale = (self.sceneContentMode != 0 ? 1.06 : 1.0) * MAX(1.0, self.sceneCropZoom);
        transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), CGAffineTransformMakeTranslation(dx, dy));
    }
    NSString *signature = [NSString stringWithFormat:@"%.4f|%.4f|%ld|%.4f|%d|%@|%@|%@",
        focalX, focalY, (long)self.sceneContentMode, self.sceneCropZoom,
        self.cachedAdaptiveCompositionEnabled, NSStringFromCGRect(self.mediaContainerView.bounds),
        NSStringFromCGRect(self.bounds), NSStringFromCGAffineTransform(transform)];
    if ([signature isEqualToString:self.lastCompositionSignature]) return;
    self.lastCompositionSignature = signature;
    [UIView performWithoutAnimation:^{
        self.imageView.transform = transform;
    }];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.playerLayer setAffineTransform:transform];
    [CATransaction commit];
}

- (void)generateSceneSmartCoverAtTime:(NSTimeInterval)time {
    NSDictionary *item = [self.currentItem copy];
    AVAsset *asset = self.player.currentItem.asset;
    if (!asset || !CCBGIsVideoName(item[@"fileName"])) return;
    NSUInteger generation = ++self.sceneSmartCoverGeneration;
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

- (void)applySceneLowPowerPolicy {
    BOOL shouldCover = NSProcessInfo.processInfo.lowPowerModeEnabled && CCBGIsVideoName(self.currentItem[@"fileName"]) && CCBGSceneDirectorLowPowerStatic(CCBGSceneRuntimeContext(self));
    if (shouldCover) {
        NSTimeInterval position = CMTimeGetSeconds(self.player.currentTime);
        if (!isfinite(position)) position = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
        if (!self.sceneLowPowerCoverActive) {
            self.sceneLowPowerCoverActive = YES;
            [self recordActivePlaybackDurationIfNeeded];
            [self generateSceneSmartCoverAtTime:position];
        }
        [self.player pause];
        self.playerLayer.hidden = YES;
        self.imageView.hidden = NO;
        return;
    }
    if (!self.sceneLowPowerCoverActive) return;
    self.sceneLowPowerCoverActive = NO;
    self.playerLayer.hidden = NO;
    if (!self.healthStartRecorded) self.mediaPresentationStartedAt = NSProcessInfo.processInfo.systemUptime;
    if (self.healthStartRecorded) {
        self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
        self.healthPlaybackFileName = [self.currentItem[@"fileName"] copy];
    }
    if (!self.hidden) {
        [self startPlaybackWhenReady];
        if (self.player.currentItem &&
            (self.player.currentItem.status != AVPlayerItemStatusReadyToPlay || !self.playerLayer.readyForDisplay)) {
            [self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0];
        }
    }
}

- (NSArray<NSDictionary *> *)availableVideoItems {
    NSArray<NSDictionary *> *items = nil;
    @synchronized (CCBGPreloadedOverlayAssets) { items = [CCBGPreloadedOverlayCatalog copy]; }
    if (!items.count) items = CCBGAvailableOverlayItems();
    NSMutableArray<NSDictionary *> *videos = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item[@"enabled"] boolValue] || !CCBGIsVideoName(item[@"fileName"])) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) continue;
        [videos addObject:item];
    }
    NSArray<NSString *> *playlist = CCBGStringArrayPreference(CCBGPresentationKey(self.kind, self.expandedPresentation, @"Playlist"));
    if (!playlist.count) return videos;
    NSMutableArray<NSDictionary *> *ordered = [NSMutableArray array];
    for (NSString *name in playlist) {
        for (NSDictionary *item in videos) {
            if ([item[@"fileName"] isEqualToString:name]) { [ordered addObject:item]; break; }
        }
    }
    return ordered;
}

- (NSInteger)playbackMode {
    return CCBGOverlayPlaybackMode(self.kind, self.expandedPresentation);
}

- (NSArray<NSDictionary *> *)automaticVideoItems {
    NSDictionary *stored = CCBGReadPreference(CCBGOverlayKey(self.kind, @"FailureCounts"), @{});
    NSDictionary *counts = [stored isKindOfClass:NSDictionary.class] ? stored : @{};
    NSMutableArray<NSDictionary *> *healthy = [NSMutableArray array];
    for (NSDictionary *item in [self availableVideoItems]) {
        if ([counts[item[@"fileName"]] integerValue] == 0) [healthy addObject:item];
    }
    return healthy;
}

- (void)recordRecentVideoName:(NSString *)fileName {
    if (!fileName.length) return;
    self.consecutiveFailureSkips = 0;
    self.configuredSelectionFailureRetries = 0;
    if ([fileName isEqualToString:self.lastRecordedRecentName]) return;
    self.lastRecordedRecentName = fileName;
    CCBGRecordSystemOverlayPlaybackSuccess(fileName, CCBGOverlayKey(self.kind, @"FailureCounts"));
}

- (void)applyInteractiveVideoName:(NSString *)fileName {
    if (CCBGGenericModulesByKind[@(self.kind)] && !CCBGGenericModuleUsesPresentationMedia(self.kind)) {
        BOOL active = [CCBGReadPreference(CCBGOverlayKey(self.kind, @"StateActive"), @NO) boolValue];
        NSString *mediaKey = CCBGOverlayKey(self.kind, active ? @"StateOnMedia" : @"StateOffMedia");
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetValue((__bridge CFStringRef)mediaKey, (__bridge CFStringRef)(fileName ?: @""), domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSetValue((__bridge CFStringRef)CCBGEnabledKey(self.kind), (__bridge CFPropertyListRef)@YES, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(domain);
        self.configurationSignature = nil;
        [self reloadIfNeeded:YES];
        [self setPlaybackVisible:YES];
        return;
    }
    [self applyVideoName:fileName clearFailure:YES];
}

- (void)applyVideoName:(NSString *)fileName clearFailure:(BOOL)clearFailure {
    if (!fileName.length) return;
    NSString *currentName = CCBGSelectedOverlayMediaName(self.kind, self.expandedPresentation, self);
    if ([currentName isEqualToString:fileName] && self.player.currentItem && self.player.currentItem.status != AVPlayerItemStatusFailed) {
        [self startPlaybackWhenReady];
        return;
    }
    NSString *mediaKey = CCBGInteractiveMediaKey(self.kind, self.expandedPresentation);
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetValue((__bridge CFStringRef)mediaKey, (__bridge CFStringRef)fileName, domain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue((__bridge CFStringRef)CCBGEnabledKey(self.kind), (__bridge CFPropertyListRef)@YES, domain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (clearFailure) {
        NSString *failureKey = CCBGOverlayKey(self.kind, @"FailureCounts");
        NSDictionary *stored = CCBGReadPreference(failureKey, @{});
        if ([stored isKindOfClass:NSDictionary.class] && stored[fileName]) {
            NSMutableDictionary *counts = [stored mutableCopy];
            [counts removeObjectForKey:fileName];
            CFPreferencesSetValue((__bridge CFStringRef)failureKey, (__bridge CFDictionaryRef)counts, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        }
    }
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(domain);
    self.configurationSignature = nil;
    if (CCBGGenericModulesByKind[@(self.kind)] && !CCBGGenericModuleUsesPresentationMedia(self.kind) &&
        ![CCBGReadPreference(CCBGOverlayKey(self.kind, @"StateStatus"), @"") isEqualToString:@"loading"]) CCBGSetPreferenceValue(CCBGOverlayKey(self.kind, @"StateStatus"), @"loading");
    [self reloadIfNeeded:YES];
    [self setPlaybackVisible:YES];
}

- (void)advanceVideoBy:(NSInteger)offset {
    [self advanceVideoBy:offset feedback:YES];
}

- (void)advanceVideoBy:(NSInteger)offset feedback:(BOOL)feedbackEnabled {
    // A Clean takeover is an interactive surface even when its automatic
    // playback mode is fixed. In that mode a swipe changes the fixed media
    // preference; ordinary system overlays retain their old fixed behavior.
    if ([self playbackMode] == 0 && !CCBGGenericModuleUsesCleanTakeover(self.kind)) return;
    NSArray<NSDictionary *> *videos = [self availableVideoItems];
    if (videos.count < 2 || offset == 0) return;
    NSString *currentName = CCBGSelectedOverlayMediaName(self.kind, self.expandedPresentation, self);
    NSInteger currentIndex = NSNotFound;
    for (NSUInteger index = 0; index < videos.count; index++) {
        if ([videos[index][@"fileName"] isEqualToString:currentName]) { currentIndex = (NSInteger)index; break; }
    }
    if (currentIndex == NSNotFound) currentIndex = offset > 0 ? -1 : 0;
    NSInteger nextIndex = (currentIndex + offset + (NSInteger)videos.count) % (NSInteger)videos.count;
    if (feedbackEnabled && [CCBGReadPreference(CCBGOverlayKey(self.kind, @"HapticsEnabled"), @YES) boolValue]) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    [self applyInteractiveVideoName:videos[(NSUInteger)nextIndex][@"fileName"]];
}

- (void)advanceAutomaticallyBy:(NSInteger)offset random:(BOOL)random {
    NSArray<NSDictionary *> *videos = [self automaticVideoItems];
    if (!videos.count) return;
    NSString *currentName = self.currentItem[@"fileName"] ?: CCBGSelectedOverlayMediaName(self.kind, self.expandedPresentation, self);
    NSDictionary *nextItem = nil;
    if (random) {
        NSMutableArray<NSDictionary *> *choices = [videos mutableCopy];
        NSIndexSet *currentIndexes = [choices indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return [item[@"fileName"] isEqualToString:currentName];
        }];
        [choices removeObjectsAtIndexes:currentIndexes];
        if (choices.count) nextItem = choices[arc4random_uniform((uint32_t)choices.count)];
    } else {
        NSInteger currentIndex = NSNotFound;
        for (NSUInteger index = 0; index < videos.count; index++) {
            if ([videos[index][@"fileName"] isEqualToString:currentName]) { currentIndex = (NSInteger)index; break; }
        }
        if (currentIndex == NSNotFound) currentIndex = offset > 0 ? -1 : 0;
        NSInteger nextIndex = (currentIndex + offset + (NSInteger)videos.count) % (NSInteger)videos.count;
        if (![videos[(NSUInteger)nextIndex][@"fileName"] isEqualToString:currentName]) nextItem = videos[(NSUInteger)nextIndex];
    }
    if (nextItem) [self applyVideoName:nextItem[@"fileName"] clearFailure:NO];
}

- (void)handleOverlaySwipe:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded || self.hidden ||
        ([self playbackMode] == 0 && !CCBGGenericModuleUsesCleanTakeover(self.kind)) ||
        (!CCBGGenericModuleUsesCleanTakeover(self.kind) &&
         ![CCBGReadPreference(CCBGOverlayKey(self.kind, @"SwipeEnabled"), @YES) boolValue])) return;
    [self advanceVideoBy:recognizer.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1];
}

- (void)handleAppearancePan:(UIPanGestureRecognizer *)recognizer {
    if (!CCBGOverlayUsesCleanTakeover(self) || !self.expandedPresentation || !self.currentItem) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // Resolve the side in the rendered media coordinate space. The
        // expanded card can be inset from the overlay (and can be reparented
        // to the Control Center root), so using the overlay midpoint makes
        // the two controls appear swapped on some module sizes.
        CGPoint startPoint = [recognizer locationInView:self.mediaContainerView];
        self.adjustingBlur = startPoint.x < CGRectGetMidX(self.mediaContainerView.bounds);
        self.appearanceOpacityAtPanStart = MIN(1.0, MAX(0.05,
            [CCBGReadPreference(CCBGOverlayKey(self.kind, @"Opacity"), @0.65) doubleValue]));
        self.appearanceBlurAtPanStart = MIN(1.0, MAX(0.0,
            [CCBGReadPreference(CCBGOverlayKey(self.kind, @"Blur"), @0.0) doubleValue]));
        return;
    }
    CGPoint translation = [recognizer translationInView:self];
    // Horizontal switching is handled by the dedicated swipe recognizers,
    // exactly like the five-module implementation. This pan only changes
    // opacity or blur on a vertical drag.
    CGFloat travel = MAX(140.0, CGRectGetHeight(self.bounds) * 0.8);
    CGFloat value = (self.adjustingBlur ? self.appearanceBlurAtPanStart : self.appearanceOpacityAtPanStart) - translation.y / travel;
    value = self.adjustingBlur ? MIN(1.0, MAX(0.0, value)) : MIN(1.0, MAX(0.05, value));
    CGFloat opacity = self.adjustingBlur ? self.appearanceOpacityAtPanStart : value;
    CGFloat blur = self.adjustingBlur ? value : self.appearanceBlurAtPanStart;
    BOOL persist = recognizer.state == UIGestureRecognizerStateEnded;
    if (recognizer.state == UIGestureRecognizerStateCancelled || recognizer.state == UIGestureRecognizerStateFailed) {
        opacity = self.appearanceOpacityAtPanStart;
        blur = self.appearanceBlurAtPanStart;
        persist = NO;
    }
    NSDictionary *item = self.currentItem;
    CGFloat itemOpacity = MIN(1.0, MAX(0.05, [item[@"opacity"] doubleValue] ?: 1.0));
    self.targetOpacity = opacity * itemOpacity;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!self.hidden) {
        if (self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self)) {
            self.alpha = 1.0;
            [self applyExpandedMediaOpacity:self.targetOpacity];
        } else {
            self.alpha = self.targetOpacity;
        }
    }
    [CATransaction commit];
    CCBGApplyGaussianBlurToLayer(self.imageView.layer, blur);
    CCBGApplyGaussianBlurToLayer(self.playerLayer, blur);
    // CAFilter is not rendered consistently by AVPlayerLayer across iOS
    // releases. Keep a visible UIKit material fallback in sync with the
    // gesture value so blur adjustment is observable on every device.
    self.blurView.alpha = self.expandedPresentation ? MIN(0.90, MAX(0.0, blur)) : 0.0;
    if (persist) {
        CCBGSetPreferenceValue(CCBGOverlayKey(self.kind, @"Opacity"), @(opacity));
        CCBGSetPreferenceValue(CCBGOverlayKey(self.kind, @"Blur"), @(blur));
        self.configurationSignature = nil;
    }
}

- (void)handleTakeoverOutsideTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded || !CCBGOverlayUsesCleanTakeover(self)) return;
    if (recognizer == self.takeoverRootTap) {
        // The root fallback recognizer intentionally receives every root
        // touch. It must ignore touches inside the expanded card and only act
        // as the outside-dismiss path when the backdrop was not hit-tested.
        CGPoint point = [recognizer locationInView:self];
        if (CGRectContainsPoint(self.bounds, point)) return;
    }
    // The overlay can be one layout pass behind the root host while Control
    // Center is reparenting it. Make dismissal idempotent instead of dropping
    // a valid outside tap because expandedPresentation is stale for a frame.
    CCBGSetGenericExpandedStateForKind(self.kind, NO);
    UIViewController *controller = self.hostController;
    BOOL controllerIsMounted = controller && controller.isViewLoaded && controller.view.window;
    if (controllerIsMounted) {
        CCBGSetGenericExpandedState(controller, NO);
        CCBGUpdateController(controller, self.kind);
        return;
    }
    // A native module can discard its old controller before the compact one
    // is attached. Collapse the root surface immediately, then let the
    // tracked-controller refresh bind the visible compact host.
    self.expandedPresentation = NO;
    [self detachNativePlayerForCompactPresentation];
    CCBGRemoveTakeoverBackdrop(self);
    UIView *nativeHost = self.nativeHostView;
    if (nativeHost.superview && self.superview) {
        self.frame = [nativeHost.superview convertRect:nativeHost.frame toView:self.superview];
    }
    [self setNeedsLayout];
    CCBGScheduleTrackedOverlayRefreshes();
}

- (void)handleOverlayLongPress:(UILongPressGestureRecognizer *)recognizer {
    BOOL customExpansion = CCBGGenericModuleUsesCustomExpansion(self.kind);
    // Takeover mode owns the five-module-style expansion contract. Its long
    // press must remain available even if the ordinary media-selection switch
    // was disabled for this module.
    if (recognizer.state != UIGestureRecognizerStateBegan || self.hidden ||
        (!customExpansion && ![CCBGReadPreference(CCBGOverlayKey(self.kind, @"LongPressEnabled"), @YES) boolValue])) return;
    if (customExpansion && self.hostController) {
        // The overlay has the last resolved presentation state. The controller
        // probe can return its unknown sentinel (-1), which is truthy when
        // coerced to BOOL and would make the first long press collapse instead
        // of expand.
        BOOL expanded = self.expandedPresentation;
        CCBGSetGenericExpandedState(self.hostController, !expanded);
        // Takeover expansion is owned by Clean. Do not call the native module
        // collection: some third-party modules have no native expanded state.
        CCBGUpdateController(self.hostController, self.kind);
        return;
    }
    [self presentVideoSelection];
}

- (void)handleGenericStateTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded || self.hidden ||
        !CCBGGenericModulesByKind[@(self.kind)] || CCBGGenericModuleUsesPresentationMedia(self.kind)) return;
    NSString *stateKey = CCBGOverlayKey(self.kind, @"StateActive");
    BOOL active = ![CCBGReadPreference(stateKey, @NO) boolValue];
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetValue((__bridge CFStringRef)stateKey, (__bridge CFPropertyListRef)@(active), domain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue((__bridge CFStringRef)CCBGOverlayKey(self.kind, @"LastManualToggle"), (__bridge CFPropertyListRef)@{
        @"active": @(active),
        @"time": @(NSProcessInfo.processInfo.systemUptime),
        @"host": self.hostController ? NSStringFromClass(self.hostController.class) : @"",
    }, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(domain);
    self.configurationSignature = nil;
    [self reloadIfNeeded:YES];
    [self setPlaybackVisible:YES];
}

- (void)presentVideoSelection {
    UIViewController *presenter = self.hostController;
    if (!presenter.view.window || presenter.presentedViewController) return;
    NSArray<NSDictionary *> *allVideos = nil;
    @synchronized (CCBGPreloadedOverlayAssets) { allVideos = [CCBGPreloadedOverlayCatalog copy]; }
    if (!allVideos.count) allVideos = CCBGAvailableOverlayItems();
    NSMutableArray<NSDictionary *> *videoItems = [NSMutableArray array];
    for (NSDictionary *item in allVideos) if ([item[@"enabled"] boolValue] && CCBGIsVideoName(item[@"fileName"]) && [[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) [videoItems addObject:item];
    if (!videoItems.count) return;
    NSArray<NSDictionary *> *playlistVideos = [self availableVideoItems];
    NSString *selectedName = CCBGSelectedOverlayMediaName(self.kind, self.expandedPresentation, self);
    __weak typeof(self) weakSelf = self;
    CCBGOverlayMediaPickerController *picker = [[CCBGOverlayMediaPickerController alloc] initWithItems:videoItems playlistItems:playlistVideos selectedName:selectedName selectionHandler:^(NSString *fileName) {
        [weakSelf applyInteractiveVideoName:fileName];
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}

- (void)installInteractionsOnHostView:(UIView *)hostView controller:(UIViewController *)controller {
    self.hostController = controller;
    BOOL genericModule = CCBGGenericModulesByKind[@(self.kind)] != nil;
    BOOL usesPresentationMedia = genericModule && CCBGGenericModuleUsesPresentationMedia(self.kind);
    // During Control Center reparenting the preference snapshot and the
    // already-visible takeover surface can briefly disagree. Keep the
    // mounted takeover's recognizers until the normal disable path removes
    // it, otherwise the expanded surface becomes visible but inert.
    BOOL customExpansion = CCBGGenericModuleUsesCustomExpansion(self.kind) || self.genericUsesCustomExpansion;
    BOOL expectedStateTap = genericModule && !customExpansion && !usesPresentationMedia;
    BOOL gesturesAttached = (customExpansion
        ? (self.swipeLeft.view == hostView && self.swipeRight.view == hostView && self.appearancePan.view == hostView && self.longPress.view == hostView)
        : (self.swipeLeft.view == hostView && self.swipeRight.view == hostView && self.longPress.view == hostView)) &&
        (!expectedStateTap || self.stateTap.view == hostView);
    if (!hostView || (self.gestureHostView == hostView &&
                      self.genericUsesPresentationMedia == usesPresentationMedia &&
                      self.genericUsesCustomExpansion == customExpansion && gesturesAttached)) return;
    [self.gestureHostView removeGestureRecognizer:self.swipeLeft];
    [self.gestureHostView removeGestureRecognizer:self.swipeRight];
    [self.gestureHostView removeGestureRecognizer:self.appearancePan];
    [self.gestureHostView removeGestureRecognizer:self.stateTap];
    [self.gestureHostView removeGestureRecognizer:self.longPress];
    self.gestureHostView = hostView;
    self.genericUsesPresentationMedia = usesPresentationMedia;
    self.genericUsesCustomExpansion = customExpansion;

    self.swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleOverlaySwipe:)];
    self.swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    self.swipeLeft.cancelsTouchesInView = NO;
    self.swipeLeft.delaysTouchesBegan = NO;
    self.swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleOverlaySwipe:)];
    self.swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    self.swipeRight.cancelsTouchesInView = NO;
    self.swipeRight.delaysTouchesBegan = NO;
    self.appearancePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleAppearancePan:)];
    self.appearancePan.maximumNumberOfTouches = 1;
    self.appearancePan.cancelsTouchesInView = NO;
    self.appearancePan.delaysTouchesBegan = NO;
    self.longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleOverlayLongPress:)];
    self.longPress.minimumPressDuration = 0.42;
    self.longPress.cancelsTouchesInView = NO;
    self.longPress.delaysTouchesBegan = NO;
    NSMutableArray<UIGestureRecognizer *> *recognizers = customExpansion
        ? [@[self.swipeLeft, self.swipeRight, self.longPress, self.appearancePan] mutableCopy]
        : [@[self.swipeLeft, self.swipeRight, self.longPress] mutableCopy];
    if (usesPresentationMedia && !customExpansion) {
        [recognizers removeAllObjects];
    } else if (genericModule && !customExpansion) {
        self.stateTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGenericStateTap:)];
        self.stateTap.numberOfTapsRequired = 1;
        self.stateTap.cancelsTouchesInView = NO;
        [recognizers addObject:self.stateTap];
    }
    for (UIGestureRecognizer *recognizer in recognizers) {
        recognizer.delegate = self;
        recognizer.delaysTouchesBegan = NO;
        recognizer.cancelsTouchesInView = recognizer == self.longPress && !genericModule;
        [hostView addGestureRecognizer:recognizer];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (self.hidden) return NO;
    if (self.genericUsesPresentationMedia && !self.genericUsesCustomExpansion && !CCBGOverlayUsesCleanTakeover(self)) return NO;
    if (gestureRecognizer == self.takeoverOutsideTap) {
        return CCBGGenericModuleUsesCleanTakeover(self.kind) && self.expandedPresentation &&
            (touch.view == self.takeoverBackdrop || [touch.view isDescendantOfView:self.takeoverBackdrop]);
    }
    if (gestureRecognizer == self.takeoverRootTap) {
        if (!CCBGGenericModuleUsesCleanTakeover(self.kind) || !self.expandedPresentation) return NO;
        // The root recognizer is the lifecycle fallback for hosts that wrap
        // or replace the backdrop. It receives every root touch; the handler
        // checks the converted point so a wrapper view cannot make outside
        // dismissal disappear from UIKit's hit-test chain.
        return YES;
    }
    BOOL takeover = CCBGOverlayUsesCleanTakeover(self);
    BOOL expandedTakeover = takeover && self.expandedPresentation;
    if (takeover) {
        CGPoint surfacePoint = [touch locationInView:self];
        if (!CGRectContainsPoint(self.bounds, surfacePoint)) return NO;
        if (expandedTakeover && self.expandedControlPanel && !self.expandedControlPanel.hidden) {
            CGPoint panelPoint = [self.expandedControlPanel convertPoint:surfacePoint fromView:self];
            if ([self.expandedControlPanel pointInside:panelPoint withEvent:nil] &&
                (gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight ||
                 gestureRecognizer == self.appearancePan || gestureRecognizer == self.longPress)) return NO;
        }
    }
    if (gestureRecognizer == self.appearancePan) {
        if (!CCBGOverlayUsesCleanTakeover(self) || !self.expandedPresentation) return NO;
        CGPoint point = [touch locationInView:self];
        if (self.expandedControlPanel && !self.expandedControlPanel.hidden) {
            CGPoint panelPoint = [self.expandedControlPanel convertPoint:point fromView:self];
            if ([self.expandedControlPanel pointInside:panelPoint withEvent:nil]) return NO;
        }
    }
    UIView *nativePlayerView = self.nativePlayerController.view;
    BOOL touchTargetsNativePlayer = self.expandedPresentation && nativePlayerView &&
        !nativePlayerView.hidden && (touch.view == nativePlayerView || [touch.view isDescendantOfView:nativePlayerView]);
    if ((gestureRecognizer == self.appearancePan || gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight) &&
        touchTargetsNativePlayer && CCBGTouchIsNativeTransportControl(touch, nativePlayerView)) return NO;
    if (gestureRecognizer == self.stateTap && CCBGGenericModulesByKind[@(self.kind)] != nil) return YES;
    if (gestureRecognizer == self.longPress &&
        !self.genericUsesCustomExpansion && !CCBGOverlayUsesCleanTakeover(self) &&
        ![CCBGReadPreference(CCBGOverlayKey(self.kind, @"LongPressEnabled"), @YES) boolValue]) return NO;
    if ((gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight) &&
        (([self playbackMode] == 0 && !CCBGOverlayUsesCleanTakeover(self)) ||
         (!CCBGOverlayUsesCleanTakeover(self) &&
          ![CCBGReadPreference(CCBGOverlayKey(self.kind, @"SwipeEnabled"), @YES) boolValue]))) return NO;
    BOOL genericLongPress = gestureRecognizer == self.longPress &&
        (CCBGGenericModulesByKind[@(self.kind)] != nil || CCBGOverlayUsesCleanTakeover(self));
    UIView *candidate = touch.view;
    while (candidate && candidate != self.gestureHostView) {
        if (!genericLongPress) {
            if ([candidate isKindOfClass:UIControl.class]) return NO;
            NSString *className = NSStringFromClass(candidate.class).lowercaseString;
            for (NSString *blocked in @[@"button", @"slider", @"scrubber", @"transport", @"volume", @"route"]) {
                if ([className containsString:blocked]) return NO;
            }
        }
        candidate = candidate.superview;
    }
    return candidate == self.gestureHostView;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.appearancePan) return YES;
    if (!CCBGOverlayUsesCleanTakeover(self) || !self.expandedPresentation) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
    // Horizontal movement belongs to the dedicated swipe recognizers. Require
    // a clear vertical intent before claiming the pan for opacity/blur.
    return fabs(velocity.y) > fabs(velocity.x) * 1.15 && fabs(velocity.y) > 2.0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ((gestureRecognizer == self.longPress || otherGestureRecognizer == self.longPress) &&
        (CCBGGenericModulesByKind[@(self.kind)] != nil || CCBGGenericModuleUsesCleanTakeover(self.kind))) return YES;
    if ((gestureRecognizer == self.stateTap || otherGestureRecognizer == self.stateTap) &&
        CCBGGenericModulesByKind[@(self.kind)] != nil) return YES;
    if (gestureRecognizer == self.appearancePan || otherGestureRecognizer == self.appearancePan) return YES;
    if (gestureRecognizer == self.longPress || otherGestureRecognizer == self.longPress) return NO;
    return YES;
}

- (void)reloadIfNeeded:(BOOL)force { [self reloadIfNeeded:force resolvedMediaName:nil]; }
- (void)reloadIfNeeded:(BOOL)force resolvedMediaName:(NSString *)resolvedMediaName {
    if (!CCBGHasOverlayPreferenceSnapshot()) {
        CCBGWithOverlayPreferenceSnapshot(^{
            [self reloadIfNeeded:force resolvedMediaName:resolvedMediaName];
        });
        return;
    }
    BOOL suppressRetainedVisual = self.suppressRetainedVisualOnNextReload;
    self.suppressRetainedVisualOnNextReload = NO;
    BOOL allowPlayerReuse = self.reusePlayerItemOnNextReload;
    self.reusePlayerItemOnNextReload = NO;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!force && self.configurationSignature.length && now - self.lastConfigurationCheck < 1.0) return;
    self.lastConfigurationCheck = now;
    CCBGMigrateLegacyAutomationPreferences();
    NSArray<NSDictionary *> *catalog = CCBGFastOverlayItems();
    NSString *selectedName = resolvedMediaName ?: CCBGSelectedOverlayMediaName(self.kind, self.expandedPresentation, self);
    if (!selectedName.length && [self playbackMode] != 0) {
        NSArray<NSDictionary *> *videos = [self availableVideoItems];
        if (videos.count) {
            NSString *retainedName = self.currentItem[@"fileName"];
            for (NSDictionary *video in videos) {
                if (retainedName.length && [video[@"fileName"] isEqualToString:retainedName]) {
                    selectedName = retainedName;
                    break;
                }
            }
            NSString *presentation = self.expandedPresentation ? @"Expanded" : @"Compact";
            NSString *legacyCurrentKey = CCBGOverlayKey(self.kind, [presentation stringByAppendingString:@"CurrentMedia"]);
            NSArray *fallbackNames = @[CCBGReadPreference(legacyCurrentKey, @"")];
            if (!selectedName.length) {
                for (id fallbackValue in fallbackNames) {
                    if (![fallbackValue isKindOfClass:NSString.class] || ![fallbackValue length]) continue;
                    NSString *fallbackName = fallbackValue;
                    for (NSDictionary *video in videos) {
                        if ([video[@"fileName"] isEqualToString:fallbackName]) {
                            selectedName = fallbackName;
                            break;
                        }
                    }
                    if (selectedName.length) break;
                }
            }
            if (!selectedName.length) {
                NSUInteger index = [self playbackMode] == 2 ? arc4random_uniform((uint32_t)videos.count) : 0;
                selectedName = videos[index][@"fileName"] ?: @"";
            }
            if (selectedName.length) CCBGSetPreferenceValue(CCBGCurrentMediaKey(self.kind, self.expandedPresentation), selectedName);
        }
    }
    NSDictionary *item = CCBGMediaItemNamed(catalog, selectedName);
    if (![item[@"enabled"] boolValue] || ![[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) item = nil;
    NSDictionary *previousItem = self.currentItem;
    self.currentItem = item;
    BOOL useArtwork = self.kind == CCBGSystemOverlayKindMusic
        && [CCBGReadPreference(CCBGOverlayKey(self.kind, @"UseArtwork"), @YES) boolValue]
        && self.dynamicArtwork
        && !item;
    CGFloat overlayOpacity = MIN(1.0, MAX(0.1, [CCBGReadPreference(CCBGOpacityKey(self.kind), @0.65) doubleValue]));
    NSString *presentationPrefix = self.expandedPresentation ? @"Expanded" : @"Compact";
    BOOL genericModule = CCBGGenericModulesByKind[@(self.kind)] != nil;
    BOOL genericPresentationMedia = genericModule && CCBGGenericModuleUsesPresentationMedia(self.kind);
    // Presentation-aware third-party modules have independent compact and
    // expanded framing preferences. Expanded media defaults to aspect-fit so
    // a portrait or cinematic clip is not silently cropped on first use.
    NSNumber *legacyContentMode = CCBGReadPreference(CCBGOverlayKey(self.kind, @"ContentMode"),
                                                      self.expandedPresentation && genericPresentationMedia ? @0 : @1);
    NSString *genericModeSuffix = genericPresentationMedia
        ? [presentationPrefix stringByAppendingString:@"ContentMode"]
        : @"ContentMode";
    id genericContentMode = genericModule
        ? CCBGReadPreference(CCBGOverlayKey(self.kind, genericModeSuffix), legacyContentMode)
        : CCBGReadPreference(CCBGOverlayKey(self.kind, self.expandedPresentation ? @"ExpandedContentMode" : @"CompactContentMode"), legacyContentMode);
    NSInteger contentMode = [genericContentMode integerValue];
    id presentationModeValue = item[self.expandedPresentation ? @"expandedContentMode" : @"compactContentMode"];
    NSInteger presentationMode = [presentationModeValue respondsToSelector:@selector(integerValue)] ? [presentationModeValue integerValue] : -1;
    if (presentationMode >= 0) contentMode = MIN(1, MAX(0, presentationMode));
    id configuredMode = CCBGReadPreference(CCBGOverlayKey(self.kind, [presentationPrefix stringByAppendingString:@"ContentMode"]), nil);
    if ([configuredMode respondsToSelector:@selector(integerValue)]) contentMode = MIN(1, MAX(0, [configuredMode integerValue]));
    self.sceneContentMode = contentMode;
    id presentationXValue = item[self.expandedPresentation ? @"expandedFocalX" : @"compactFocalX"];
    id presentationYValue = item[self.expandedPresentation ? @"expandedFocalY" : @"compactFocalY"];
    id presentationZoomValue = item[self.expandedPresentation ? @"expandedCropZoom" : @"compactCropZoom"];
    CGFloat presentationX = [presentationXValue respondsToSelector:@selector(doubleValue)] ? [presentationXValue doubleValue] : -1;
    CGFloat presentationY = [presentationYValue respondsToSelector:@selector(doubleValue)] ? [presentationYValue doubleValue] : -1;
    CGFloat presentationZoom = [presentationZoomValue respondsToSelector:@selector(doubleValue)] ? MIN(2.5, MAX(1.0, [presentationZoomValue doubleValue])) : 1.0;
    id configuredX = CCBGReadPreference(CCBGOverlayKey(self.kind, [presentationPrefix stringByAppendingString:@"FocalX"]), nil);
    id configuredY = CCBGReadPreference(CCBGOverlayKey(self.kind, [presentationPrefix stringByAppendingString:@"FocalY"]), nil);
    id configuredZoom = CCBGReadPreference(CCBGOverlayKey(self.kind, [presentationPrefix stringByAppendingString:@"CropZoom"]), nil);
    if ([configuredX respondsToSelector:@selector(doubleValue)]) presentationX = [configuredX doubleValue];
    if ([configuredY respondsToSelector:@selector(doubleValue)]) presentationY = [configuredY doubleValue];
    if ([configuredZoom respondsToSelector:@selector(doubleValue)]) presentationZoom = MIN(2.5, MAX(1.0, [configuredZoom doubleValue]));
    CGFloat blur = MIN(1.0, MAX(0.0, [CCBGReadPreference(CCBGOverlayKey(self.kind, @"Blur"), @0.0) doubleValue]));
    CGFloat dim = MIN(0.85, MAX(0.0, [CCBGReadPreference(CCBGOverlayKey(self.kind, @"Dim"), @0.0) doubleValue]));
    NSDictionary *sceneContext = CCBGSceneRuntimeContext(self);
    self.cachedAdaptiveCompositionEnabled = [CCBGSceneDirectorResolvedScene(sceneContext)[@"adaptiveCompositionEnabled"] boolValue];
    self.adaptiveExpandedFrameEnabled = [CCBGReadPreference(CCBGOverlayKey(self.kind, @"AdaptiveExpandedFrame"), @YES) boolValue];
    NSString *signature = [NSString stringWithFormat:@"%d|%@|resolved=%d|art=%p|state=%ld|overlay=%.3f|mode=%ld|blur=%.3f|dim=%.3f|opacity=%.3f|start=%.3f|end=%.3f|rate=%.3f|adaptive=%d|focal=%.3f,%.3f|zoom=%.3f",
        self.expandedPresentation,
        item[@"fileName"] ?: selectedName ?: @"", item != nil, useArtwork ? (void *)self.dynamicArtwork.CGImage : NULL, (long)CCBGCurrentConnectivityState,
        overlayOpacity, (long)contentMode, blur, dim, [item[@"opacity"] doubleValue],
        [item[@"startTime"] doubleValue], [item[@"endTime"] doubleValue], [item[@"playbackRate"] doubleValue], self.adaptiveExpandedFrameEnabled,
        presentationX, presentationY, presentationZoom];
    if (!force && [signature isEqualToString:self.configurationSignature]) return;
    BOOL hadConfiguration = self.configurationSignature.length > 0;
    BOOL canReusePlayerItem = allowPlayerReuse && item && previousItem &&
        CCBGIsVideoName(item[@"fileName"]) &&
        [item[@"fileName"] isEqualToString:previousItem[@"fileName"]] &&
        self.player && self.playerLayer && self.player.currentItem &&
        self.player.currentItem.status != AVPlayerItemStatusFailed;
    BOOL mediaChanged = ![item[@"fileName"] isEqualToString:previousItem[@"fileName"]];
    self.configurationSignature = signature;
    if (hadConfiguration && mediaChanged && !suppressRetainedVisual) {
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionFade;
        transition.duration = UIAccessibilityIsReduceMotionEnabled() ? 0.08 : 0.20;
        transition.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :1.0 :0.36 :1.0];
        [self.mediaContainerView.layer addAnimation:transition forKey:@"ccbg.mediaTransition"];
    }
    UIImage *retainedVisual = suppressRetainedVisual ? nil : self.imageView.image;
    if (!canReusePlayerItem) {
        if (self.player.currentItem) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.player.currentItem];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.player.currentItem];
        }
        [self recordActivePlaybackDurationIfNeeded];
        self.playbackGeneration++;
        self.readinessCheckActive = NO;
        self.mediaPresentationStartedAt = NSProcessInfo.processInfo.systemUptime;
        self.healthStartRecorded = NO;
        self.sceneLowPowerCoverActive = NO;
        self.sceneSmartCoverGeneration++;
        self.nativePlayerPresentationFallbackVisible = NO;
        self.handledFailureGeneration = NSNotFound;
        self.naturalVideoSize = CGSizeZero;
        [self.player pause];
        [self.player replaceCurrentItemWithPlayerItem:nil];
        self.playerLayer.hidden = YES;
    } else {
        // Expanded and compact presentations share the same selected video.
        // Keep the item and its decoded frame alive so the host can animate
        // the geometry without a synchronous AVPlayer teardown/rebuild.
        [self.playerLayer removeAnimationForKey:@"ccbg.playerReveal"];
        self.playerLayer.hidden = NO;
        self.playerLayer.opacity = 1.0;
    }
    BOOL hasVisual = item || useArtwork;
    BOOL sliderOverlay = self.kind == CCBGSystemOverlayKindBrightness || self.kind == CCBGSystemOverlayKindVolume;
    BOOL expandedMaterial = self.expandedPresentation && !sliderOverlay && hasVisual;
    self.blurView.effect = expandedMaterial
        ? [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]
        : nil;
    // Keep the material restrained: it separates native controls from bright
    // media without turning the selected video into a permanently blurred card.
    self.blurView.alpha = expandedMaterial ? MIN(0.90, MAX(0.0, blur)) : 0.0;
    CCBGApplyGaussianBlurToLayer(self.imageView.layer, hasVisual ? blur : 0.0);
    CCBGApplyGaussianBlurToLayer(self.playerLayer, hasVisual ? blur : 0.0);
    // A small baseline scrim in expanded mode keeps native labels and controls
    // readable over bright video while preserving the user's configured dim.
    CGFloat presentationDim = self.expandedPresentation ? MAX(dim, 0.03) : dim;
    self.dimView.alpha = hasVisual ? presentationDim : 0.0;
    self.targetOpacity = hasVisual ? overlayOpacity * (item ? MIN(1.0, MAX(0.05, [item[@"opacity"] doubleValue])) : 1.0) : 0.0;
    self.sceneBaseFocalX = item ? MIN(1.0, MAX(0.0, [item[@"focalX"] doubleValue])) : 0.5;
    self.sceneBaseFocalY = item ? MIN(1.0, MAX(0.0, [item[@"focalY"] doubleValue])) : 0.5;
    if (presentationX >= 0) self.sceneBaseFocalX = MIN(1.0, presentationX);
    if (presentationY >= 0) self.sceneBaseFocalY = MIN(1.0, presentationY);
    self.sceneCropZoom = presentationZoom;
    [self applyCachedSceneComposition];
    self.imageView.contentMode = contentMode == 0 ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    if (useArtwork) {
        if (self.kind == CCBGSystemOverlayKindMusic) {
            CCBGRecordRuntimeDiagnostic(@"musicOverlayPlaybackState", @"reason=usingSystemArtwork");
        }
        self.imageView.image = self.dynamicArtwork;
        self.imageView.hidden = NO;
        self.playerLayer.hidden = YES;
        [self detachNativePlayerForCompactPresentation];
        return;
    }
    if (!item) {
        self.imageView.image = nil;
        self.imageView.hidden = YES;
        self.playerLayer.hidden = YES;
        [self detachNativePlayerForCompactPresentation];
        if (self.kind == CCBGSystemOverlayKindMusic) {
            NSString *state = [NSString stringWithFormat:@"reason=itemMissing|selected=%@", selectedName ?: @""];
            CCBGRecordRuntimeDiagnostic(@"musicOverlayPlaybackState", state);
        }
        return;
    }
    NSString *path = CCBGPathForItem(item);
    if (!CCBGIsVideoName(item[@"fileName"])) {
        self.imageView.image = [UIImage imageWithContentsOfFile:path] ?: CCBGPlaceholderImageForItem(item);
        self.imageView.hidden = NO;
        self.playerLayer.hidden = YES;
        [self detachNativePlayerForCompactPresentation];
        if (self.imageView.image) [self recordSuccessfulMediaStartIfNeeded];
        return;
    }
    NSString *assetCacheKey = CCBGOverlayAssetCacheKey(item);
    AVAsset *preloadedAsset = nil;
    @synchronized (CCBGPreloadedOverlayAssets) { preloadedAsset = CCBGPreloadedOverlayAssets[assetCacheKey]; }
    UIImage *cover = [CCBGPreloadedOverlayImages objectForKey:assetCacheKey];
    self.imageView.image = cover ?: retainedVisual ?: CCBGPlaceholderImageForItem(item);
    self.imageView.hidden = NO;
    if (!cover) {
        NSDictionary *coverItem = [item copy];
        NSUInteger coverGeneration = self.playbackGeneration;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (!CCBGControlCenterPresentationVisible) return;
            NSData *coverFrameData = [CCBGPreloadedOverlayFrames objectForKey:assetCacheKey];
            if (!coverFrameData.length) coverFrameData = [NSData dataWithContentsOfFile:CCBGOverlayFrameCachePath(coverItem)];
            UIImage *decodedCover = coverFrameData.length ? [UIImage imageWithData:coverFrameData] : nil;
            if (!CCBGControlCenterPresentationVisible) return;
            CCBGCacheOverlayImage(decodedCover, assetCacheKey);
            if (!decodedCover) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || coverGeneration != self.playbackGeneration || self.playerLayer.readyForDisplay ||
                    ![self.currentItem[@"fileName"] isEqualToString:coverItem[@"fileName"]]) return;
                self.imageView.image = decodedCover;
                self.imageView.hidden = NO;
            });
        });
    }
    if (canReusePlayerItem) {
        self.playbackRate = MIN(2.0, MAX(0.5, [item[@"playbackRate"] floatValue]));
        self.playerLayer.videoGravity = contentMode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
        self.playerLayer.frame = self.playerSurfaceView.bounds;
        self.playerLayer.cornerRadius = self.mediaContainerView.layer.cornerRadius;
        [self applyCachedSceneComposition];
        if (self.playerLayer.readyForDisplay) {
            self.imageView.image = nil;
            self.imageView.hidden = YES;
        }
        [self applySceneLowPowerPolicy];
        if (!self.sceneLowPowerCoverActive) [self startPlaybackWhenReady];
        // The first expanded layout can run before the reused AVPlayerItem is
        // attached. Once the item is reused, explicitly remount AVKit here;
        // a ready item may skip the readiness timer and otherwise leave the
        // native transport controller detached for the whole presentation.
        if (self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self)) {
            [self updateNativePlayerPresentation];
            [self scheduleNativePlayerPresentationRecovery];
        }
        if (!self.playerLayer.readyForDisplay) {
            [self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0];
        }
        return;
    }
    NSTimeInterval start = MAX(0.0, [item[@"startTime"] doubleValue]);
    NSTimeInterval end = MAX(0.0, [item[@"endTime"] doubleValue]);
    NSUInteger installGeneration = self.playbackGeneration;
    __weak typeof(self) weakSelfForInstall = self;
    void (^installVideoOnlyAsset)(AVAsset *, NSError *) = ^(AVAsset *videoOnlyAsset, NSError *error) {
        __strong typeof(weakSelfForInstall) self = weakSelfForInstall;
        if (!self || installGeneration != self.playbackGeneration) return;
        if (!videoOnlyAsset) {
            [self handlePlaybackFailure];
            return;
        }
        AVAssetTrack *track = [videoOnlyAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        CGSize size = track ? CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform) : CGSizeZero;
        size = CGSizeMake(fabs(size.width), fabs(size.height));
        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:videoOnlyAsset];
        if (end > start) playerItem.forwardPlaybackEndTime = CMTimeMakeWithSeconds(end, 600);
        if (!self.player) self.player = [AVPlayer playerWithPlayerItem:nil];
        self.player.muted = YES;
        self.player.volume = 0.0;
        self.player.allowsExternalPlayback = NO;
        self.player.preventsDisplaySleepDuringVideoPlayback = NO;
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        self.player.automaticallyWaitsToMinimizeStalling = NO;
        if (!self.playerLayer) {
            self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
            [self.playerSurfaceView.layer addSublayer:self.playerLayer];
        }
        BOOL revealPlayerLayer = self.playerLayer.hidden || self.playerLayer.opacity <= 0.01;
        [self.playerLayer removeAnimationForKey:@"ccbg.playerReveal"];
        self.playerLayer.hidden = NO;
        self.playerLayer.videoGravity = contentMode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
        self.playerLayer.frame = self.playerSurfaceView.bounds;
        self.playerLayer.masksToBounds = YES;
        self.playerLayer.cornerRadius = self.mediaContainerView.layer.cornerRadius;
        if (@available(iOS 13.0, *)) self.playerLayer.cornerCurve = kCACornerCurveContinuous;
        self.playerLayer.contentsScale = UIScreen.mainScreen.scale;
        self.playerLayer.backgroundColor = UIColor.clearColor.CGColor;
        if (revealPlayerLayer) {
            self.playerLayer.opacity = 0.0;
            CABasicAnimation *reveal = [CABasicAnimation animationWithKeyPath:@"opacity"];
            reveal.fromValue = @0.0;
            reveal.toValue = @1.0;
            reveal.duration = UIAccessibilityIsReduceMotionEnabled() ? 0.08 : 0.14;
            reveal.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [self.playerLayer addAnimation:reveal forKey:@"ccbg.playerReveal"];
            self.playerLayer.opacity = 1.0;
        }
        self.naturalVideoSize = size;
        [self applyAdaptiveFrameForHostView:self.layoutHostView ?: self.superview ?: self.gestureHostView];
        self.playbackRate = MIN(2.0, MAX(0.5, [item[@"playbackRate"] floatValue]));
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStalled:) name:AVPlayerItemPlaybackStalledNotification object:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
        __weak typeof(self) weakSelf = self;
        void (^startPlayback)(BOOL) = ^(BOOL finished) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !finished || self.hidden || self.player.currentItem != playerItem) return;
            [self startPlaybackWhenReady];
        };
        if (start > 0) {
            [self.player seekToTime:CMTimeMakeWithSeconds(start, 600)
                     toleranceBefore:kCMTimeZero
                      toleranceAfter:kCMTimeZero
                   completionHandler:startPlayback];
        } else {
            startPlayback(YES);
        }
        // AVPlayerItem installation is asynchronous and often completes
        // without causing another Control Center layout pass. Reconcile the
        // native player immediately after the item and AVPlayerLayer exist,
        // instead of relying on the readiness probe to do it by accident.
        if (self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self)) {
            [self updateNativePlayerPresentation];
            [self scheduleNativePlayerPresentationRecovery];
        }
        // A healthy, already-rendered overlay does not need another 12-second
        // readiness probe on every Control Center visibility refresh. Keep the
        // probe for incomplete layers, pending items, or a stale placeholder.
        // A ready layer can remove its cover synchronously.  Starting another
        // delayed probe just because the cover is still present adds needless
        // main-queue work every time Control Center reattaches the overlay.
        if (self.playerLayer.readyForDisplay) {
            self.imageView.image = nil;
            self.imageView.hidden = YES;
        }
        BOOL needsReadinessCheck = !self.player.currentItem ||
            self.player.currentItem.status != AVPlayerItemStatusReadyToPlay ||
            !self.playerLayer.readyForDisplay;
        if (needsReadinessCheck) [self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0];
    };
    if (preloadedAsset) installVideoOnlyAsset(preloadedAsset, nil);
    else CCBGLoadVideoOnlyAsset(path, installVideoOnlyAsset);
}

- (void)reloadAfterPreferenceChange {
    self.lastConfigurationCheck = 0;
    [self reloadIfNeeded:NO];
}

- (void)startPlaybackWhenReady {
    if (!CCBGControlCenterPresentationVisible) return;
    if (self.hidden || !self.player || self.player.currentItem.status != AVPlayerItemStatusReadyToPlay) return;
    if (NSProcessInfo.processInfo.lowPowerModeEnabled && CCBGSceneDirectorLowPowerStatic(CCBGSceneRuntimeContext(self))) {
        [self applySceneLowPowerPolicy];
        return;
    }
    if (CCBGGenericModulesByKind[@(self.kind)] && !CCBGGenericModuleUsesPresentationMedia(self.kind)) {
        BOOL active = [CCBGReadPreference(CCBGOverlayKey(self.kind, @"StateActive"), @NO) boolValue];
        NSString *status = active ? @"on" : @"off";
        if (![CCBGReadPreference(CCBGOverlayKey(self.kind, @"StateStatus"), @"") isEqualToString:status]) CCBGSetPreferenceValue(CCBGOverlayKey(self.kind, @"StateStatus"), status);
    }
    [self.player playImmediatelyAtRate:self.playbackRate];
}

- (void)schedulePlaybackReadinessCheck:(NSUInteger)generation attempt:(NSUInteger)attempt {
    if (generation != self.playbackGeneration || !self.player) return;
    if (!CCBGControlCenterPresentationVisible) {
        self.readinessCheckActive = NO;
        return;
    }
    if (self.hidden) {
        self.readinessCheckActive = NO;
        return;
    }
    if (self.sceneLowPowerCoverActive) {
        self.readinessCheckActive = NO;
        return;
    }
    if (attempt == 0) {
        if (self.readinessCheckActive) return;
        self.readinessCheckActive = YES;
    }
    if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
        self.readinessCheckActive = NO;
        [self handlePlaybackFailure];
        return;
    }
    BOOL itemReady = self.player.currentItem.status == AVPlayerItemStatusReadyToPlay;
    BOOL layerReady = self.playerLayer.readyForDisplay;
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentTime);
    NSTimeInterval startTime = MAX(0.0, [self.currentItem[@"startTime"] doubleValue]);
    BOOL playbackAdvanced = isfinite(currentTime) && currentTime > startTime + 0.03;
    if (itemReady) [self startPlaybackWhenReady];
    if (attempt >= 5 && self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self) &&
        self.player.currentItem.status != AVPlayerItemStatusFailed) {
        self.nativePlayerPresentationFallbackVisible = YES;
    }
    [self updateNativePlayerPresentation];
    if (self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self) &&
        self.player.currentItem && self.currentItem && CCBGIsVideoName(self.currentItem[@"fileName"])) {
        [self scheduleNativePlayerPresentationRecovery];
    }
    if (layerReady || playbackAdvanced) {
        [self recordSuccessfulMediaStartIfNeeded];
        self.imageView.image = nil;
        self.imageView.hidden = YES;
    }
    if (playbackAdvanced) {
        [self recordRecentVideoName:self.currentItem[@"fileName"]];
    }
    if (self.kind == CCBGSystemOverlayKindMusic && (attempt == 0 || attempt == 10 || attempt == 30)) {
        NSString *state = [NSString stringWithFormat:@"status=%ld|timeControl=%ld|rate=%.3f|time=%.3f|ready=%d|advanced=%d|layerHidden=%d",
            (long)self.player.currentItem.status, (long)self.player.timeControlStatus, self.player.rate, currentTime,
            layerReady, playbackAdvanced, self.playerLayer.hidden];
        CCBGRecordRuntimeDiagnostic(@"musicOverlayPlaybackState", state);
    }
    if ((itemReady && (layerReady || playbackAdvanced)) || attempt >= 120) {
        self.readinessCheckActive = NO;
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf schedulePlaybackReadinessCheck:generation attempt:attempt + 1];
    });
}

- (void)playbackStalled:(NSNotification *)notification {
    if (notification.object != self.player.currentItem || self.hidden) return;
    [self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0];
}

- (void)playbackFailed:(NSNotification *)notification {
    if (notification.object == self.player.currentItem) [self handlePlaybackFailure];
}

- (void)handlePlaybackFailure {
    NSUInteger generation = self.playbackGeneration;
    if (self.handledFailureGeneration == generation) return;
    self.handledFailureGeneration = generation;
    self.lastRecordedRecentName = nil;
    NSString *failedPath = CCBGPathForItem(self.currentItem);
    if (failedPath.length) {
        @synchronized (CCBGPreloadedOverlayAssets) {
            [CCBGPreloadedOverlayAssets removeObjectForKey:CCBGOverlayAssetCacheKey(self.currentItem)];
        }
        CCBGInvalidateVideoOnlyAssetCache(failedPath);
    }
    if (self.currentItem[@"fileName"]) {
        CCBGRecordMediaPlaybackFailure(self.currentItem[@"fileName"], @"系统模块视频无法解码");
    }
    [self recordActivePlaybackDurationIfNeeded];
    if (CCBGGenericModulesByKind[@(self.kind)] && !CCBGGenericModuleUsesPresentationMedia(self.kind)) {
        CCBGSetPreferenceValue(CCBGOverlayKey(self.kind, @"StateStatus"), @"unavailable");
    }
    BOOL preserveConfiguredSelection = [self playbackMode] == 0 || !self.expandedPresentation || CCBGGenericModulesByKind[@(self.kind)] != nil;
    if (preserveConfiguredSelection) {
        if (self.configuredSelectionFailureRetries >= 2) return;
        self.configuredSelectionFailureRetries++;
        NSUInteger failedGeneration = self.playbackGeneration;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.hidden || weakSelf.playbackGeneration != failedGeneration) return;
            weakSelf.configurationSignature = nil;
            [weakSelf reloadIfNeeded:YES];
            [weakSelf setPlaybackVisible:YES];
        });
        return;
    }
    NSString *fileName = self.currentItem[@"fileName"] ?: @"";
    NSString *failureKey = CCBGOverlayKey(self.kind, @"FailureCounts");
    NSDictionary *stored = CCBGReadPreference(failureKey, @{});
    NSMutableDictionary *counts = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    counts[fileName] = @([counts[fileName] integerValue] + 1);
    CCBGSetPreferenceValue(failureKey, counts);
    if ([CCBGReadPreference(CCBGOverlayKey(self.kind, @"AutoSkipFailures"), @YES) boolValue] && [self availableVideoItems].count > 1) {
        if (self.consecutiveFailureSkips >= 3 || [self automaticVideoItems].count == 0) return;
        self.consecutiveFailureSkips++;
        NSUInteger failedGeneration = self.playbackGeneration;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakSelf.playbackGeneration == failedGeneration && !weakSelf.hidden) [weakSelf advanceAutomaticallyBy:1 random:NO];
        });
    }
}

- (void)videoEnded:(NSNotification *)notification {
    if (notification.object != self.player.currentItem) return;
    AVPlayerItem *endedItem = notification.object;
    NSInteger mode = [self playbackMode];
    if (mode == 1 && [self automaticVideoItems].count > 1) {
        [self advanceAutomaticallyBy:1 random:NO];
        return;
    }
    if (mode == 2 && [self automaticVideoItems].count > 1) {
        [self advanceAutomaticallyBy:1 random:YES];
        return;
    }
    NSDictionary *item = self.currentItem;
    NSTimeInterval start = MAX(0.0, [item[@"startTime"] doubleValue]);
    [self.player seekToTime:CMTimeMakeWithSeconds(start, 600) completionHandler:^(BOOL finished) {
        if (finished && !self.hidden && self.player.currentItem == endedItem) {
            [self.player playImmediatelyAtRate:self.playbackRate];
        }
    }];
}

- (void)pausePlaybackPreservingPresentation {
    [self recordActivePlaybackDurationIfNeeded];
    self.readinessCheckActive = NO;
    [self.player pause];
}

- (void)stopVisibilityAnimationPreservingPresentation {
    UIViewPropertyAnimator *animator = self.visibilityAnimator;
    if (!animator) return;
    if (animator.state == UIViewAnimatingStateActive) [animator stopAnimation:YES];
    if (animator.state == UIViewAnimatingStateStopped) {
        [animator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
    }
    self.visibilityAnimator = nil;
}

- (void)setPlaybackVisible:(BOOL)visible {
    BOOL targetChanged = !self.hasVisibilityTarget || self.visibilityTargetVisible != visible;
    CGFloat visualAlpha = visible ? MIN(1.0, MAX(0.0, self.targetOpacity)) : 0.0;
    BOOL mediaOpacityPresentation = visible && self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self);
    CGFloat cardAlpha = mediaOpacityPresentation ? 1.0 : visualAlpha;
    BOOL presentationMatches = (visible ? !self.hidden : self.hidden) &&
        fabs(self.alpha - cardAlpha) <= 0.01;
    if (visible && mediaOpacityPresentation) {
        CGFloat expectedMediaAlpha = visualAlpha;
        presentationMatches = presentationMatches && fabs(self.imageView.alpha - expectedMediaAlpha) <= 0.01;
        presentationMatches = presentationMatches && fabs(self.playerLayer.opacity - expectedMediaAlpha) <= 0.01;
    }
    // This must precede the presentation convergence return. A covered module
    // can already look visible after Control Center reparents it even though
    // AVKit's child view was detached during that same transition.
    if (visible && self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self)) {
        [self updateNativePlayerPresentation];
        [self scheduleNativePlayerPresentationRecovery];
    }
    if (!targetChanged && presentationMatches) return;
    self.hasVisibilityTarget = YES;
    self.visibilityTargetVisible = visible;
    NSUInteger generation = ++self.visibilityGeneration;
    BOOL wasAnimating = self.visibilityAnimator != nil;
    [self stopVisibilityAnimationPreservingPresentation];
    if (visible) {
        BOOL wasHidden = self.hidden || self.alpha <= 0.01;
        self.hidden = NO;
        BOOL animate = self.window != nil && (wasAnimating || (self.hasPresented && wasHidden));
        [self.layer removeAnimationForKey:@"ccbg.visibility"];
        if (animate) {
            BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
            if (!wasAnimating) {
                self.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.985, 0.985);
                self.alpha = 0.0;
                self.mediaContainerView.alpha = 1.0;
                self.playerLayer.opacity = 0.0;
                self.imageView.alpha = 0.0;
            }
            __weak typeof(self) weakSelf = self;
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
                initWithDuration:(reduceMotion ? 0.12 : 0.22)
                curve:UIViewAnimationCurveEaseOut
                animations:^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.transform = CGAffineTransformIdentity;
                self.alpha = cardAlpha;
                self.mediaContainerView.alpha = 1.0;
                self.playerLayer.opacity = mediaOpacityPresentation ? visualAlpha : 1.0;
                self.imageView.alpha = mediaOpacityPresentation ? visualAlpha : 1.0;
            }];
            [animator addCompletion:^(UIViewAnimatingPosition position) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.visibilityGeneration) return;
                self.visibilityAnimator = nil;
            }];
            self.visibilityAnimator = animator;
            [animator startAnimation];
        } else {
            self.transform = CGAffineTransformIdentity;
            self.alpha = cardAlpha;
            self.mediaContainerView.alpha = 1.0;
            self.playerLayer.opacity = mediaOpacityPresentation ? visualAlpha : 1.0;
            self.imageView.alpha = mediaOpacityPresentation ? visualAlpha : 1.0;
        }
        if (!animate) {
            self.mediaContainerView.alpha = 1.0;
            self.playerLayer.opacity = mediaOpacityPresentation ? visualAlpha : 1.0;
            self.imageView.alpha = mediaOpacityPresentation ? visualAlpha : 1.0;
        }
        // The disable path hides the player layer after its fade-out. The
        // view can be reused when the master switch is enabled again, so the
        // visibility state must be restored explicitly before playback starts.
        self.playerLayer.hidden = NO;
        self.hasPresented = YES;
        [self applySceneLowPowerPolicy];
        if (self.healthStartRecorded && self.healthPlaybackStartedAt <= 0 && !self.sceneLowPowerCoverActive) {
            self.healthPlaybackStartedAt = NSProcessInfo.processInfo.systemUptime;
            self.healthPlaybackFileName = [self.currentItem[@"fileName"] copy];
        }
        if (self.player.currentItem && !self.sceneLowPowerCoverActive) {
            BOOL playbackActive = self.player.rate > 0.01 ||
                self.player.timeControlStatus == AVPlayerTimeControlStatusPlaying ||
                self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate;
            if (!playbackActive) {
                [self.player playImmediatelyAtRate:self.playbackRate];
            } else if (fabs(self.player.rate - self.playbackRate) > 0.01) {
                self.player.rate = self.playbackRate;
            }
        }
        // A healthy, already-rendered overlay does not need another 12-second
        // readiness probe on every Control Center visibility refresh. Keep the
        // probe for incomplete layers, pending items, or a stale placeholder.
        BOOL needsReadinessCheck = !self.player.currentItem ||
            self.player.currentItem.status != AVPlayerItemStatusReadyToPlay ||
            !self.playerLayer.readyForDisplay;
        if (needsReadinessCheck) [self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0];
    } else {
        [self recordActivePlaybackDurationIfNeeded];
        self.readinessCheckActive = NO;
        [self.player pause];
        [self detachNativePlayerForCompactPresentation];
        if (self.hidden && self.alpha <= 0.01) return;
        self.hidden = NO;
        if (!wasAnimating) {
            self.mediaContainerView.alpha = 1.0;
            self.playerLayer.opacity = 1.0;
        }
        BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        __weak typeof(self) weakSelf = self;
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
            initWithDuration:(reduceMotion ? 0.09 : 0.17)
             curve:UIViewAnimationCurveEaseOut
            animations:^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.985, 0.985);
            self.alpha = 0.0;
            self.mediaContainerView.alpha = 0.0;
            self.playerLayer.opacity = 0.0;
            self.imageView.alpha = 0.0;
        }];
        [animator addCompletion:^(UIViewAnimatingPosition position) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.visibilityGeneration) return;
            self.visibilityAnimator = nil;
            self.hidden = YES;
            self.transform = CGAffineTransformIdentity;
            self.playerLayer.hidden = YES;
            self.playerLayer.opacity = 0.0;
            self.mediaContainerView.alpha = 1.0;
            self.imageView.alpha = 0.0;
        }];
        self.visibilityAnimator = animator;
        [animator startAnimation];
    }
}

- (void)suspendForInactiveControlCenterPresentation {
    // Merely pausing leaves AVPlayerItem's decoder and IOSurface allocations
    // owned by mediaserverd.  Control Center can retain its module views after
    // dismissal, so release the item explicitly and force a clean reload on
    // the next real presentation.
    self.visibilityGeneration++;
    self.playbackGeneration++;
    self.readinessCheckActive = NO;
    self.nativePresentationRecoveryGeneration++;
    self.nativePresentationRecoveryArmed = NO;
    [self stopVisibilityAnimationPreservingPresentation];
    [self recordActivePlaybackDurationIfNeeded];
    AVPlayerItem *activeItem = self.player.currentItem;
    if (activeItem) {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:activeItem];
        [center removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:activeItem];
        [center removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:activeItem];
    }
    [self.player pause];
    [self detachNativePlayerForCompactPresentation];
    self.nativePlayerController.player = nil;
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.playerLayer.hidden = YES;
    self.playerLayer.opacity = 0.0;
    self.imageView.image = nil;
    self.imageView.hidden = YES;
    self.dynamicArtwork = nil;
    self.naturalVideoSize = CGSizeZero;
    self.configurationSignature = nil;
    self.lastConfigurationCheck = 0.0;
    self.hidden = YES;
    self.alpha = 0.0;
    self.hasVisibilityTarget = NO;
}

- (void)restoreSuppressedArtwork {
    if (self.suppressedArtworkView) {
        self.suppressedArtworkView.alpha = self.suppressedArtworkAlpha;
        self.suppressedArtworkView.hidden = self.suppressedArtworkHidden;
        self.suppressedArtworkView.layer.shadowOpacity = self.suppressedArtworkShadowOpacity;
    }
    if (self.suppressedArtworkContainer) {
        self.suppressedArtworkContainer.layer.shadowOpacity = self.suppressedContainerShadowOpacity;
        self.suppressedArtworkContainer.backgroundColor = self.suppressedContainerBackgroundColor;
    }
    self.suppressedArtworkView = nil;
    self.suppressedArtworkContainer = nil;
}

- (void)restoreSuppressedNativeContent {
    for (NSDictionary *state in [self.suppressedNativeViewStates copy]) {
        UIView *view = state[@"view"];
        if (![view isKindOfClass:UIView.class]) continue;
        view.hidden = [state[@"hidden"] boolValue];
        view.alpha = [state[@"alpha"] doubleValue];
        view.userInteractionEnabled = [state[@"userInteractionEnabled"] boolValue];
        view.layer.hidden = [state[@"layerHidden"] boolValue];
        view.layer.opacity = [state[@"layerOpacity"] floatValue];
    }
    [self.suppressedNativeViewStates removeAllObjects];
    for (NSDictionary *state in [self.suppressedNativeGestureStates copy]) {
        UIGestureRecognizer *gesture = state[@"gesture"];
        if ([gesture isKindOfClass:UIGestureRecognizer.class]) gesture.enabled = [state[@"enabled"] boolValue];
    }
    [self.suppressedNativeGestureStates removeAllObjects];
    self.suppressedNativeHostView = nil;
}

- (BOOL)nativeSuppressionMatchesHostView:(UIView *)hostView {
    if (!hostView || self.suppressedNativeHostView != hostView) return NO;
    for (UIView *view in hostView.subviews) {
        if (view == self || [view isKindOfClass:CCBGSystemOverlayView.class]) continue;
        NSDictionary *state = nil;
        for (NSDictionary *candidate in self.suppressedNativeViewStates) {
            if (candidate[@"view"] == view) { state = candidate; break; }
        }
        if (!state || !view.hidden || view.alpha > 0.01 || view.userInteractionEnabled ||
            !view.layer.hidden || view.layer.opacity > 0.01f) return NO;
    }
    for (UIGestureRecognizer *gesture in hostView.gestureRecognizers) {
        if (gesture == self.swipeLeft || gesture == self.swipeRight || gesture == self.stateTap || gesture == self.longPress ||
            [gesture isKindOfClass:UILongPressGestureRecognizer.class]) continue;
        NSDictionary *state = nil;
        for (NSDictionary *candidate in self.suppressedNativeGestureStates) {
            if (candidate[@"gesture"] == gesture) { state = candidate; break; }
        }
        if (!state || gesture.enabled) return NO;
    }
    return YES;
}

- (void)suppressNativeContentInHostView:(UIView *)hostView {
    if (!CCBGGenericModuleUsesCleanTakeover(self.kind) || !hostView) {
        [self restoreSuppressedNativeContent];
        return;
    }
    if (self.suppressedNativeHostView != hostView) {
        [self restoreSuppressedNativeContent];
        self.suppressedNativeHostView = hostView;
    }
    if ([self nativeSuppressionMatchesHostView:hostView]) return;
    if (!self.suppressedNativeViewStates) self.suppressedNativeViewStates = [NSMutableArray array];
    if (!self.suppressedNativeGestureStates) self.suppressedNativeGestureStates = [NSMutableArray array];
    for (UIView *view in [hostView.subviews copy]) {
        if (view == self || [view isKindOfClass:CCBGSystemOverlayView.class]) continue;
        BOOL alreadySuppressed = NO;
        for (NSDictionary *state in self.suppressedNativeViewStates) {
            if (state[@"view"] == view) { alreadySuppressed = YES; break; }
        }
        if (!alreadySuppressed) {
            [self.suppressedNativeViewStates addObject:@{
                @"view": view,
                @"hidden": @(view.hidden),
                @"alpha": @(view.alpha),
                @"userInteractionEnabled": @(view.userInteractionEnabled),
                @"layerHidden": @(view.layer.hidden),
                @"layerOpacity": @(view.layer.opacity),
            }];
        }
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        view.layer.hidden = YES;
        view.layer.opacity = 0.0;
    }
    for (UIGestureRecognizer *gesture in [hostView.gestureRecognizers copy]) {
        if (gesture == self.swipeLeft || gesture == self.swipeRight || gesture == self.stateTap || gesture == self.longPress ||
            [gesture isKindOfClass:UILongPressGestureRecognizer.class]) continue;
        // ReplayKit and several third-party Control Center modules attach their
        // real expansion entry point to the host view. The Clean overlay stays
        // visually and interactively on top, but this system long press must
        // remain enabled so its lifecycle callback can drive the takeover.
        BOOL alreadySuppressed = NO;
        for (NSDictionary *state in self.suppressedNativeGestureStates) {
            if (state[@"gesture"] == gesture) { alreadySuppressed = YES; break; }
        }
        if (!alreadySuppressed) {
            [self.suppressedNativeGestureStates addObject:@{
                @"gesture": gesture,
                @"enabled": @(gesture.enabled),
            }];
        }
        gesture.enabled = NO;
    }
}
@end

static NSUInteger CCBGOverlayInsertionIndex(UIView *view, UIView *excluded) {
    NSUInteger index = 0;
    NSUInteger logicalIndex = 0;
    CCBGSystemOverlayView *overlay = [excluded isKindOfClass:CCBGSystemOverlayView.class] ? (CCBGSystemOverlayView *)excluded : nil;
    BOOL mediaAboveNative = overlay && [CCBGReadPreference(CCBGOverlayKey(overlay.kind, @"MediaAboveNative"), @NO) boolValue];
    for (UIView *subview in view.subviews) {
        if (subview == excluded) continue;
        NSString *className = NSStringFromClass(subview.class);
        if ([className localizedCaseInsensitiveContainsString:@"material"] ||
            [className localizedCaseInsensitiveContainsString:@"background"]) {
            index = logicalIndex + 1;
        }
        logicalIndex++;
    }
    // zPosition changes rendering but UIKit hit-testing still walks the
    // subview array from the end. A Clean takeover must therefore be the last
    // subview as well, otherwise the native module can consume the long press.
    if (overlay && CCBGGenericModuleUsesCleanTakeover(overlay.kind)) return logicalIndex;
    if (mediaAboveNative) return logicalIndex;
    // When a host has no named backdrop, index zero is intentional: native
    // icons, labels, and controls remain above the additive media layer. A
    // takeover overlay suppresses those siblings and consumes touches after
    // insertion, while the normal path preserves the host's native behavior.
    return MIN(index, logicalIndex);
}

static void CCBGPlaceOverlay(UIView *overlay, UIView *host) {
    if (!overlay || !host) return;
    NSUInteger desiredIndex = CCBGOverlayInsertionIndex(host, overlay);
    NSUInteger currentIndex = overlay.superview == host ? [host.subviews indexOfObjectIdenticalTo:overlay] : NSNotFound;
    NSUInteger logicalCurrentIndex = currentIndex;
    if (currentIndex != NSNotFound) {
        logicalCurrentIndex = 0;
        for (NSUInteger candidate = 0; candidate < currentIndex; candidate++) {
            if (host.subviews[candidate] != overlay) logicalCurrentIndex++;
        }
    }
    if (overlay.superview == host && logicalCurrentIndex == desiredIndex) return;
    UIView *oldHost = overlay.superview;
    CGRect oldFrame = overlay.frame;
    BOOL isReparenting = oldHost && oldHost != host;
    CGRect convertedFrame = isReparenting ? [oldHost convertRect:oldFrame toView:host] : oldFrame;
    [overlay removeFromSuperview];
    [host insertSubview:overlay atIndex:MIN(desiredIndex, host.subviews.count)];
    if (isReparenting && !CGRectIsNull(convertedFrame) && !CGRectIsInfinite(convertedFrame)) {
        overlay.frame = convertedFrame;
    }
}

static void CCBGKeepTakeoverOverlayOnTop(CCBGSystemOverlayView *overlay) {
    if (!overlay || !CCBGGenericModuleUsesCleanTakeover(overlay.kind) || !overlay.superview) return;
    // A host may append native controls after CCBGPlaceOverlay returns. Keep
    // the takeover surface last so UIKit's reverse subview hit-test order
    // remains aligned with the visual z-order.
    [overlay.superview bringSubviewToFront:overlay];
}

static void CCBGRemoveTakeoverBackdrop(CCBGSystemOverlayView *overlay) {
    if (!overlay) return;
    if (overlay.takeoverBackdropAnimator) {
        if (overlay.takeoverBackdropAnimator.state == UIViewAnimatingStateActive) {
            [overlay.takeoverBackdropAnimator stopAnimation:YES];
        }
        overlay.takeoverBackdropAnimator = nil;
    }
    [overlay.takeoverBackdrop removeFromSuperview];
    [overlay.takeoverRootTap.view removeGestureRecognizer:overlay.takeoverRootTap];
    overlay.takeoverOutsideTap = nil;
    overlay.takeoverRootTap = nil;
    overlay.takeoverBackdrop = nil;
    overlay.takeoverBackdropHost = nil;
}

static void CCBGUpdateTakeoverBackdrop(CCBGSystemOverlayView *overlay, UIView *rootHost, BOOL expanded) {
    if (!overlay || !CCBGGenericModuleUsesCleanTakeover(overlay.kind)) {
        CCBGRemoveTakeoverBackdrop(overlay);
        return;
    }
    if (!expanded) {
        UIView *backdrop = overlay.takeoverBackdrop;
        if (!backdrop) return;
        // Keep the dimming surface alive for the same frame as the compact
        // reparent/resize animation. Removing it synchronously exposes a
        // one-frame jump from the expanded canvas to the native tile.
        if (overlay.takeoverBackdropAnimator) return;
        backdrop.userInteractionEnabled = NO;
        BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        __weak CCBGSystemOverlayView *weakOverlay = overlay;
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc]
            initWithDuration:(reduceMotion ? 0.10 : 0.20)
            curve:UIViewAnimationCurveEaseOut
            animations:^{ backdrop.alpha = 0.0; }];
        [animator addCompletion:^(UIViewAnimatingPosition position) {
            CCBGSystemOverlayView *strongOverlay = weakOverlay;
            if (!strongOverlay || strongOverlay.takeoverBackdrop != backdrop || strongOverlay.expandedPresentation) return;
            strongOverlay.takeoverBackdropAnimator = nil;
            CCBGRemoveTakeoverBackdrop(strongOverlay);
        }];
        overlay.takeoverBackdropAnimator = animator;
        [animator startAnimation];
        return;
    }
    if (!rootHost) {
        CCBGRemoveTakeoverBackdrop(overlay);
        return;
    }
    if (overlay.takeoverBackdropAnimator) {
        if (overlay.takeoverBackdropAnimator.state == UIViewAnimatingStateActive) {
            [overlay.takeoverBackdropAnimator stopAnimation:YES];
        }
        overlay.takeoverBackdropAnimator = nil;
    }
    if (!overlay.takeoverBackdrop || overlay.takeoverBackdropHost != rootHost) {
        CCBGRemoveTakeoverBackdrop(overlay);
        UIView *backdrop = [[UIView alloc] initWithFrame:rootHost.bounds];
        // The takeover owns the whole Control Center canvas while expanded;
        // a material surface hides native/other modules without turning a
        // media-opacity adjustment into an apparent brightness adjustment.
        backdrop.backgroundColor = UIColor.clearColor;
        backdrop.userInteractionEnabled = YES;
        backdrop.accessibilityElementsHidden = YES;
        backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        backdrop.layer.zPosition = 900.0;
        UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        material.frame = backdrop.bounds;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        material.userInteractionEnabled = NO;
        [backdrop addSubview:material];
        UITapGestureRecognizer *outsideTap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(handleTakeoverOutsideTap:)];
        outsideTap.cancelsTouchesInView = NO;
        // This recognizer lives only on the full-screen backdrop, so every
        // touch it receives is already outside the Clean surface. Do not run
        // it through the overlay's hit-test delegate: Control Center can
        // wrap the backdrop in a private hosting view, making the delegate's
        // descendant check reject an otherwise valid outside tap.
        [backdrop addGestureRecognizer:outsideTap];
        overlay.takeoverOutsideTap = outsideTap;
        overlay.takeoverBackdrop = backdrop;
        overlay.takeoverBackdropHost = rootHost;
        UITapGestureRecognizer *rootTap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(handleTakeoverOutsideTap:)];
        rootTap.cancelsTouchesInView = NO;
        rootTap.delaysTouchesBegan = NO;
        rootTap.delegate = overlay;
        [rootHost addGestureRecognizer:rootTap];
        overlay.takeoverRootTap = rootTap;
    }
    UIView *backdrop = overlay.takeoverBackdrop;
    if (backdrop.superview != rootHost) [rootHost addSubview:backdrop];
    backdrop.frame = rootHost.bounds;
    backdrop.alpha = 1.0;
    backdrop.userInteractionEnabled = YES;
    // Reassert ordering on every Control Center layout pass. Native modules
    // can append subviews after the first expansion callback.
    [rootHost bringSubviewToFront:backdrop];
    [rootHost bringSubviewToFront:overlay];
}

static void CCBGFindLargestSliderView(UIView *view, UIView **bestView, CGFloat *bestArea, NSUInteger *remaining) {
    if (!view || !bestView || !bestArea || !remaining || *remaining == 0) return;
    *remaining -= 1;
    NSString *className = NSStringFromClass(view.class);
    if ([className localizedCaseInsensitiveContainsString:@"ContinuousSliderView"]) {
        CGFloat area = CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds);
        if (area > *bestArea && CGRectGetWidth(view.bounds) > 24.0 && CGRectGetHeight(view.bounds) > 24.0) {
            *bestArea = area;
            *bestView = view;
        }
    }
    for (UIView *subview in view.subviews) {
        CCBGFindLargestSliderView(subview, bestView, bestArea, remaining);
        if (*remaining == 0) break;
    }
}

static UIView *CCBGPrimarySliderView(UIView *rootView) {
    UIView *bestView = nil;
    CGFloat bestArea = 0.0;
    NSUInteger remaining = 96;
    CCBGFindLargestSliderView(rootView, &bestView, &bestArea, &remaining);
    return bestView;
}

static UIView *CCBGTakeoverRootView(UIViewController *controller) {
    if (!controller) return nil;
    UIWindow *window = controller.viewIfLoaded.window;
    UIViewController *fallback = controller;
    UIViewController *candidate = controller;
    while (candidate) {
        UIView *view = candidate.viewIfLoaded;
        if (view) fallback = candidate;
        NSString *name = NSStringFromClass(candidate.class).lowercaseString;
        BOOL isControlCenterRoot = [name containsString:@"overlay"] ||
            [name containsString:@"modularcontrolcenter"] ||
            [name containsString:@"controlcenterviewcontroller"] ||
            [name containsString:@"controlcenterroot"];
        if (isControlCenterRoot && view && (!window || view.window == window)) return view;
        candidate = candidate.parentViewController;
    }
    UIViewController *top = fallback;
    while (top.parentViewController) top = top.parentViewController;
    UIView *topView = top.viewIfLoaded;
    if (topView && (!window || topView.window == window)) return topView;
    if (window.rootViewController.viewIfLoaded) return window.rootViewController.view;
    return controller.viewIfLoaded;
}

static UIViewController *CCBGTakeoverRootController(UIViewController *controller, UIView *mountedView) {
    if (!controller || !mountedView) return nil;
    UIWindow *window = mountedView.window ?: controller.viewIfLoaded.window;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        UIView *candidateView = candidate.viewIfLoaded;
        if (!candidateView || (window && candidateView.window != window)) continue;
        // This is the containment invariant AVKit needs: its child controller
        // must belong to a controller whose view actually owns the expanded
        // overlay, not the compact module controller it was reparented from.
        if ([mountedView isDescendantOfView:candidateView]) return candidate;
    }
    UIViewController *windowRoot = window.rootViewController;
    if (windowRoot.isViewLoaded && [mountedView isDescendantOfView:windowRoot.view]) return windowRoot;
    return nil;
}

static UIView *CCBGOverlayHostView(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (CCBGGenericModuleUsesCleanTakeover(kind)) {
        // Legacy behavior was: if (CCBGGenericModuleUsesCleanTakeover(kind)) return controller.view;
        // That compact-only host is retained as the collapsed fallback.
        // Clean takeover does not ask the native module to expand. Reparenting
        // the overlay to the Control Center root gives unsupported third-party
        // modules the same canvas as the five custom modules.
        if (CCBGControllerIsExpandedPresentation(controller, kind)) {
            UIView *rootView = CCBGTakeoverRootView(controller);
            if (rootView) return rootView;
        }
        return controller.view;
    }
    if (kind == CCBGSystemOverlayKindMusic &&
        [NSStringFromClass(controller.class) isEqualToString:@"MRUControlCenterViewController"] &&
        controller.view.subviews.count > 2) {
        return controller.view.subviews[2];
    }
    if (kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume) {
        UIView *sliderView = CCBGPrimarySliderView(controller.viewIfLoaded);
        if (sliderView) return sliderView;
    }
    return controller.view;
}

static CCBGSystemOverlayKind CCBGSliderKindFromText(NSString *text) {
    NSString *value = text.lowercaseString;
    if ([value containsString:@"brightness"] || [value containsString:@"sun"] || [value containsString:@"亮度"]) return CCBGSystemOverlayKindBrightness;
    if ([value containsString:@"volume"] || [value containsString:@"speaker"] || [value containsString:@"audio"] || [value containsString:@"音量"]) return CCBGSystemOverlayKindVolume;
    return 0;
}

static CCBGSystemOverlayKind CCBGSliderKindInView(UIView *view, NSUInteger *remaining) {
    if (!view || !remaining || *remaining == 0) return 0;
    *remaining -= 1;
    for (NSString *text in @[
        NSStringFromClass(view.class) ?: @"", view.accessibilityIdentifier ?: @"",
        view.accessibilityLabel ?: @"", view.accessibilityHint ?: @"", view.accessibilityValue ?: @""
    ]) {
        CCBGSystemOverlayKind kind = CCBGSliderKindFromText(text);
        if (kind) return kind;
    }
    for (UIView *subview in view.subviews) {
        CCBGSystemOverlayKind kind = CCBGSliderKindInView(subview, remaining);
        if (kind) return kind;
        if (*remaining == 0) break;
    }
    return 0;
}

static CCBGSystemOverlayKind CCBGSharedSliderOverlayKind(UIViewController *controller) {
    NSArray<NSString *> *sharedSliderClasses = @[
        @"CCUIContinuousSliderViewController",
        @"CCUIContinuousSliderModuleViewController",
        @"CCUIControlCenterSliderViewController",
    ];
    NSString *controllerName = NSStringFromClass(controller.class);
    if (![sharedSliderClasses containsObject:controllerName] &&
        ![controllerName localizedCaseInsensitiveContainsString:@"Slider"]) return 0;

    NSSet<NSString *> *knownOwners = [NSSet setWithArray:@[
        @"CCUIBrightnessModuleViewController", @"CCUIBrightnessModuleContentViewController",
        @"CCUIBrightnessSliderViewController", @"CCUIBrightnessExpandedViewController",
        @"CCUIBrightnessModuleExpandedContentViewController",
        @"CCUIVolumeModuleViewController", @"CCUIVolumeModuleContentViewController",
        @"CCUIVolumeSliderViewController", @"CCUIVolumeExpandedViewController",
        @"CCUIVolumeModuleExpandedContentViewController", @"CCUIAudioModuleViewController",
        @"CCUIAudioModuleContentViewController", @"CCUIAudioModuleExpandedContentViewController",
    ]];
    for (UIViewController *candidate = controller.parentViewController; candidate; candidate = candidate.parentViewController) {
        NSString *name = NSStringFromClass(candidate.class);
        if ([knownOwners containsObject:name]) return 0;
        if ([name localizedCaseInsensitiveContainsString:@"Brightness"]) return CCBGSystemOverlayKindBrightness;
        if ([name localizedCaseInsensitiveContainsString:@"Volume"] ||
            [name localizedCaseInsensitiveContainsString:@"AudioModule"]) return CCBGSystemOverlayKindVolume;
    }
    CCBGSystemOverlayKind restorationKind = CCBGSliderKindFromText(controller.restorationIdentifier ?: @"");
    if (restorationKind) return restorationKind;
    NSUInteger remaining = 48;
    CCBGSystemOverlayKind viewKind = CCBGSliderKindInView(controller.viewIfLoaded, &remaining);
    if (viewKind) return viewKind;
    return 0;
}

static NSInteger CCBGExpandedStateFromObject(id object) {
    if (!object) return -1;
    NSNumber *associatedState = objc_getAssociatedObject(object, CCBGGenericExpandedStateAssociationKey);
    if ([associatedState isKindOfClass:NSNumber.class]) return associatedState.boolValue ? 1 : 0;
    for (NSString *selectorName in @[@"isExpanded", @"_isExpanded", @"isPresentationExpanded", @"isExpandedContentMode", @"expanded"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:selector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) ? 1 : 0;
        }
    }
    return -1;
}

static NSInteger CCBGCCSwitchExpandedState(UIViewController *controller, CCBGSystemOverlayKind kind) {
    NSDictionary *module = CCBGGenericModulesByKind[@(kind)];
    if (![module[@"identifier"] isEqualToString:@"netskao.ccswitchdatamodule"]) return -1;
    BOOL sawCompactState = NO;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        NSNumber *candidateAssociatedState = objc_getAssociatedObject(candidate, CCBGGenericExpandedStateAssociationKey);
        if ([candidateAssociatedState isKindOfClass:NSNumber.class]) return candidateAssociatedState.boolValue ? 1 : 0;
        id owner = objc_getAssociatedObject(candidate, CCBGGenericControllerOwnerAssociationKey);
        if (!owner) owner = CCBGValueForKeyIfAvailable(candidate, @"contentModule");
        if (!owner) owner = CCBGValueForKeyIfAvailable(candidate, @"_contentModule");
        if (!owner) owner = CCBGValueForKeyIfAvailable(candidate, @"module");
        if (!owner) owner = CCBGValueForKeyIfAvailable(candidate, @"_module");
        if (owner) {
            NSInteger ownerState = CCBGExpandedStateFromObject(owner);
            if (ownerState >= 0) return ownerState;
            SEL capabilitySelector = NSSelectorFromString(@"shouldBeginTransitionToExpandedContentModule");
            if ([owner respondsToSelector:capabilitySelector]) sawCompactState = YES;
        }
        NSInteger candidateState = CCBGExpandedStateFromObject(candidate);
        if (candidateState == 1) return 1;
        if (candidateState == 0) sawCompactState = YES;
    }
    return sawCompactState ? 0 : -1;
}

static CCBGSystemOverlayKind CCBGGenericKindForController(UIViewController *controller) {
    if (!controller) return 0;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        NSNumber *associatedKind = objc_getAssociatedObject(candidate, CCBGGenericOverlayKindAssociationKey);
        if (associatedKind.integerValue > 0) return (CCBGSystemOverlayKind)associatedKind.integerValue;
        CCBGSystemOverlayView *overlay = objc_getAssociatedObject(candidate, CCBGOverlayAssociationKey);
        if (overlay.kind > 0) return overlay.kind;
    }
    return 0;
}

static BOOL CCBGGenericExpandedStateForKind(CCBGSystemOverlayKind kind, BOOL *known) {
    if (known) *known = NO;
    if (kind <= 0 || !CCBGGenericExpandedStates) return NO;
    NSNumber *value = nil;
    @synchronized (CCBGGenericExpandedStates) { value = CCBGGenericExpandedStates[@(kind)]; }
    if (!value) return NO;
    if (known) *known = YES;
    return value.boolValue;
}

static void CCBGClearGenericExpandedStateForKind(CCBGSystemOverlayKind kind) {
    if (kind <= 0 || !CCBGGenericExpandedStates) return;
    @synchronized (CCBGGenericExpandedStates) { [CCBGGenericExpandedStates removeObjectForKey:@(kind)]; }
}

static void CCBGClearGenericExpandedState(UIViewController *controller) {
    CCBGSystemOverlayKind kind = CCBGGenericKindForController(controller);
    CCBGClearGenericExpandedStateForKind(kind);
    if (!controller) return;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        objc_setAssociatedObject(candidate, CCBGGenericExpandedStateAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id owner = objc_getAssociatedObject(controller, CCBGGenericControllerOwnerAssociationKey);
    if (owner) objc_setAssociatedObject(owner, CCBGGenericExpandedStateAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CCBGSetGenericExpandedState(UIViewController *controller, BOOL expanded) {
    CCBGSystemOverlayKind kind = CCBGGenericKindForController(controller);
    if (kind > 0) CCBGSetGenericExpandedStateForKind(kind, expanded);
    if (!controller) return;
    NSNumber *value = @(expanded);
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        objc_setAssociatedObject(candidate, CCBGGenericExpandedStateAssociationKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id owner = objc_getAssociatedObject(controller, CCBGGenericControllerOwnerAssociationKey);
    if (owner) objc_setAssociatedObject(owner, CCBGGenericExpandedStateAssociationKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CCBGSetGenericExpandedStateForKind(CCBGSystemOverlayKind kind, BOOL expanded) {
    if (kind <= 0 || !CCBGGenericExpandedStates) return;
    @synchronized (CCBGGenericExpandedStates) {
        CCBGGenericExpandedStates[@(kind)] = @(expanded);
    }
}

static BOOL CCBGControllerIsExpandedPresentation(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (CCBGGenericModuleUsesCleanTakeover(kind)) {
        // Clean takeover owns expansion state completely. Native modules can
        // report transient or contradictory states while rebuilding their
        // content controller, so never let those callbacks drive our frame.
        BOOL hasGlobalState = NO;
        BOOL globalState = CCBGGenericExpandedStateForKind(kind, &hasGlobalState);
        if (hasGlobalState) return globalState;
        for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
            NSNumber *state = objc_getAssociatedObject(candidate, CCBGGenericExpandedStateAssociationKey);
            if ([state isKindOfClass:NSNumber.class]) return state.boolValue;
        }
        objc_setAssociatedObject(controller, CCBGGenericExpandedStateAssociationKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    NSArray<NSString *> *expandedClasses = nil;
    NSArray<NSString *> *compactClasses = nil;
    NSInteger sliderState = -1;
    NSInteger controllerState = -1;
    NSInteger ccSwitchState = CCBGCCSwitchExpandedState(controller, kind);
    if (ccSwitchState >= 0) return ccSwitchState == 1;
    switch (kind) {
        case CCBGSystemOverlayKindConnectivity:
            expandedClasses = @[@"CCUIConnectivityExpandedViewController"];
            compactClasses = @[@"CCUIConnectivityModuleViewController", @"CCUIConnectivityModuleContentViewController"];
            break;
        case CCBGSystemOverlayKindMusic:
            expandedClasses = @[@"MediaControlsPanelViewController"];
            compactClasses = @[@"MRUControlCenterViewController", @"MediaControlsViewController"];
            break;
        case CCBGSystemOverlayKindBrightness:
            expandedClasses = @[@"CCUIBrightnessExpandedViewController", @"CCUIBrightnessModuleExpandedContentViewController"];
            compactClasses = @[@"CCUIBrightnessModuleViewController", @"CCUIBrightnessModuleContentViewController", @"CCUIBrightnessSliderViewController", @"CCUIDisplayModuleViewController"];
            break;
        case CCBGSystemOverlayKindVolume:
            expandedClasses = @[@"CCUIVolumeExpandedViewController", @"CCUIVolumeModuleExpandedContentViewController", @"CCUIAudioModuleExpandedContentViewController"];
            compactClasses = @[@"CCUIVolumeModuleViewController", @"CCUIVolumeModuleContentViewController", @"CCUIVolumeSliderViewController", @"CCUIAudioModuleViewController", @"CCUIAudioModuleContentViewController", @"MRUVolumeViewController"];
            break;
    }
    if (kind == CCBGSystemOverlayKindMusic) {
        BOOL sawRuntimeState = NO;
        for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
            NSString *className = NSStringFromClass(candidate.class);
            if ([expandedClasses containsObject:className] || [className localizedCaseInsensitiveContainsString:@"Expanded"]) return YES;
            NSInteger runtimeState = CCBGExpandedStateFromObject(candidate);
            if (runtimeState == 1) return YES;
            if (runtimeState == 0) sawRuntimeState = YES;
        }
        if (sawRuntimeState) return NO;
    }
    if (kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume) {
        for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
            NSString *className = NSStringFromClass(candidate.class);
            if ([expandedClasses containsObject:className] || [className localizedCaseInsensitiveContainsString:@"Expanded"]) return YES;
        }
        NSUInteger parentDepth = 0;
        for (UIViewController *candidate = controller.parentViewController; candidate && parentDepth < 3; candidate = candidate.parentViewController, parentDepth++) {
            if (CCBGExpandedStateFromObject(candidate) == 1) return YES;
        }
        UIView *primarySlider = CCBGPrimarySliderView(controller.viewIfLoaded);
        sliderState = CCBGExpandedStateFromObject(primarySlider);
        controllerState = CCBGExpandedStateFromObject(controller);
        if (sliderState == 1 || controllerState == 1) return YES;
    }
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        NSString *className = NSStringFromClass(candidate.class);
        if ([expandedClasses containsObject:className] || [className localizedCaseInsensitiveContainsString:@"Expanded"]) return YES;
    }
    CGSize size = controller.view.bounds.size;
    CGSize screenSize = controller.view.window.screen.bounds.size;
    CGFloat shortScreenSide = MIN(screenSize.width, screenSize.height);
    CGFloat expandedThreshold = MAX(200.0, shortScreenSide * 0.54);
    if (size.width >= expandedThreshold && size.height >= expandedThreshold) return YES;
    if ((kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume) &&
        (sliderState == 0 || controllerState == 0)) return NO;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        if ([compactClasses containsObject:NSStringFromClass(candidate.class)]) return NO;
    }
    return NO;
}

static CGFloat CCBGOverlayCornerRadius(UIView *view, BOOL expanded, CCBGSystemOverlayKind kind) {
    NSString *hostClassName = NSStringFromClass(view.class);
    // Only the native brightness/volume slider uses a true capsule. Generic
    // third-party modules can expose the same private class name while still
    // being square grid tiles; applying half-height here turns those tiles
    // into circles and makes their media mask visibly wrong.
    BOOL isSliderOverlay = kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume;
    if (isSliderOverlay && [hostClassName localizedCaseInsensitiveContainsString:@"ContinuousSliderView"]) {
        return floor(MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5);
    }
    CGFloat radius = view.layer.cornerRadius;
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class);
        if ([className localizedCaseInsensitiveContainsString:@"material"] ||
            [className localizedCaseInsensitiveContainsString:@"background"]) {
            radius = MAX(radius, subview.layer.cornerRadius);
        }
    }
    if (radius > 0.0) return radius;
    CGFloat minimum = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds));
    if (minimum <= 0.0) return expanded ? 28.0 : 18.0;
    BOOL isOneByOne = fabs(CGRectGetWidth(view.bounds) - CGRectGetHeight(view.bounds)) <= 3.0 && minimum <= 76.0;
    if (isOneByOne) return minimum * 0.5;
    return MIN(32.0, MAX(22.0, minimum * 0.5 - 6.0));
}

static CGFloat CCBGAdjustedOverlayCornerRadius(UIView *hostView, UIView *overlay,
                                               BOOL expanded, CCBGSystemOverlayKind kind) {
    if (!hostView || !overlay) return 0.0;
    CGFloat radius = CCBGOverlayCornerRadius(hostView, expanded, kind);
    CGFloat shortest = MIN(CGRectGetWidth(overlay.bounds), CGRectGetHeight(overlay.bounds));
    if (expanded && shortest > 1.0) {
        // A resized expanded card should keep a calm, proportional radius
        // instead of inheriting the much larger radius of its host container.
        radius = MIN(radius, MAX(18.0, MIN(30.0, shortest * 0.18)));
    }
    return MIN(radius, MAX(0.0, shortest * 0.5));
}

static BOOL CCBGControllerShouldOwnOverlay(UIViewController *controller, CCBGSystemOverlayKind kind) {
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        NSNumber *genericKind = objc_getAssociatedObject(candidate, CCBGGenericOverlayKindAssociationKey);
        if (genericKind.integerValue == kind && CCBGGenericModulesByKind[@(kind)]) return YES;
    }
    NSDictionary *matchedGenericModule = CCBGGenericModuleForContainerController(controller);
    if ([matchedGenericModule[@"kind"] integerValue] == kind) return YES;
    if (CCBGSharedSliderOverlayKind(controller) == kind) return YES;
    NSString *className = NSStringFromClass(controller.class);
    NSArray<NSString *> *classes = nil;
    switch (kind) {
        case CCBGSystemOverlayKindConnectivity: classes = @[@"CCUIConnectivityModuleViewController", @"CCUIConnectivityModuleContentViewController", @"CCUIConnectivityExpandedViewController"]; break;
        case CCBGSystemOverlayKindMusic: classes = @[@"MRUControlCenterViewController", @"MediaControlsPanelViewController", @"MediaControlsViewController"]; break;
        case CCBGSystemOverlayKindBrightness: classes = @[@"CCUIBrightnessModuleViewController", @"CCUIBrightnessModuleContentViewController", @"CCUIBrightnessSliderViewController", @"CCUIBrightnessExpandedViewController", @"CCUIBrightnessModuleExpandedContentViewController", @"CCUIDisplayModuleViewController"]; break;
        case CCBGSystemOverlayKindVolume: classes = @[@"CCUIVolumeModuleViewController", @"CCUIVolumeModuleContentViewController", @"CCUIVolumeSliderViewController", @"CCUIVolumeExpandedViewController", @"CCUIVolumeModuleExpandedContentViewController", @"CCUIAudioModuleViewController", @"CCUIAudioModuleContentViewController", @"CCUIAudioModuleExpandedContentViewController", @"MRUVolumeViewController"]; break;
    }
    if ([classes containsObject:className]) return YES;
    if (![className localizedCaseInsensitiveContainsString:@"ViewController"]) return NO;
    BOOL controlCenterClass = [className hasPrefix:@"CCUI"] && ([className localizedCaseInsensitiveContainsString:@"Module"] || [className localizedCaseInsensitiveContainsString:@"Slider"]);
    if (kind == CCBGSystemOverlayKindBrightness) return controlCenterClass && [className localizedCaseInsensitiveContainsString:@"Brightness"];
    if (kind == CCBGSystemOverlayKindVolume) return controlCenterClass && ([className localizedCaseInsensitiveContainsString:@"Volume"] || [className localizedCaseInsensitiveContainsString:@"AudioModule"]);
    return NO;
}

static void CCBGRecordOverlayDiagnostic(UIViewController *controller, CCBGSystemOverlayKind kind, BOOL expanded, NSString *selectedName) {
    NSString *prefix = CCBGOverlayPrefix(kind);
    NSString *effectiveKey = CCBGInteractiveMediaKey(kind, expanded);
    NSString *value = [NSString stringWithFormat:@"%@|%@|%.0fx%.0f|%@=%@",
        NSStringFromClass(controller.class), expanded ? @"expanded" : @"compact",
        controller.view.bounds.size.width, controller.view.bounds.size.height,
        effectiveKey, selectedName.length ? selectedName : @"默认"];
    NSString *key = [prefix stringByAppendingString:@"LastPresentation"];
    @synchronized (CCBGLastOverlayDiagnosticValues) {
        if ([CCBGLastOverlayDiagnosticValues[key] isEqualToString:value]) return;
        CCBGLastOverlayDiagnosticValues[key] = value;
    }
    CCBGRecordRuntimeDiagnostic(key, value);
}

static void CCBGHideController(UIViewController *controller);

static CCBGSystemOverlayView *CCBGExpandedTakeoverOverlay(NSArray<CCBGSystemOverlayView *> *views) {
    for (CCBGSystemOverlayView *candidate in views) {
        if (!candidate || !candidate.window || candidate.hidden || !candidate.expandedPresentation) continue;
        if (CCBGOverlayUsesCleanTakeover(candidate)) return candidate;
    }
    return nil;
}

static void CCBGShowOverlayWithPresentationArbitration(CCBGSystemOverlayView *overlay) {
    if (!overlay) return;
    if (!CCBGControlCenterPresentationVisible) {
        [overlay suspendForInactiveControlCenterPresentation];
        return;
    }
    NSArray<CCBGSystemOverlayView *> *views = nil;
    @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
    CCBGSystemOverlayView *expandedTakeover = CCBGExpandedTakeoverOverlay(views);
    if (overlay.expandedPresentation && CCBGOverlayUsesCleanTakeover(overlay)) {
        // The Clean takeover is mounted above the whole Control Center canvas.
        // Pausing every obscured Clean surface removes unnecessary concurrent
        // hardware decode without changing normal system-module expansion.
        for (CCBGSystemOverlayView *candidate in views) {
            if (candidate != overlay && !candidate.expandedPresentation) [candidate setPlaybackVisible:NO];
        }
        [overlay setPlaybackVisible:YES];
        return;
    }
    if (expandedTakeover && expandedTakeover != overlay) {
        [overlay setPlaybackVisible:NO];
        return;
    }
    if (overlay.expandedPresentation) {
        for (CCBGSystemOverlayView *candidate in views) {
            if (candidate != overlay && candidate.kind == overlay.kind && !candidate.expandedPresentation) {
                [candidate setPlaybackVisible:NO];
            }
        }
    } else {
        for (CCBGSystemOverlayView *candidate in views) {
            if (candidate != overlay && candidate.kind == overlay.kind && candidate.expandedPresentation &&
                candidate.window && !candidate.hidden) {
                [overlay setPlaybackVisible:NO];
                return;
            }
        }
    }
    [overlay setPlaybackVisible:YES];
    // A collapsed takeover leaves its compact peers mounted but paused. Resume
    // only the already-configured compact surfaces; disabled/detached modules
    // never regain visibility through this recovery pass.
    if (!CCBGExpandedTakeoverOverlay(views)) {
        for (CCBGSystemOverlayView *candidate in views) {
            if (candidate == overlay || candidate.expandedPresentation || !candidate.window ||
                !candidate.superview || !candidate.configurationSignature.length) continue;
            [candidate setPlaybackVisible:YES];
        }
    }
}

static void CCBGDetachOverlayViewNow(CCBGSystemOverlayView *overlay) {
    if (!overlay) return;
    overlay.dismissalGeneration++;
    if (overlay.hasNativePreferredContentSize && overlay.hostController) {
        overlay.hostController.preferredContentSize = overlay.nativePreferredContentSize;
        overlay.hasNativePreferredContentSize = NO;
    }
    // Hide the Clean surface before restoring native content. Restoring the
    // native hierarchy first briefly exposes it underneath the still-visible
    // video layer, producing a one-frame double-render during dismissal.
    [overlay setPlaybackVisible:NO];
    overlay.hidden = YES;
    overlay.alpha = 0.0;
    CCBGRemoveTakeoverBackdrop(overlay);
    [overlay restoreSuppressedArtwork];
    [overlay restoreSuppressedNativeContent];
    [overlay.layer removeAllAnimations];
    for (CALayer *sublayer in overlay.layer.sublayers) {
        [sublayer removeAllAnimations];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [overlay removeFromSuperview];
    [CATransaction commit];
}

static void CCBGScheduleOverlayDetachAfterDismissal(CCBGSystemOverlayView *overlay) {
    if (!overlay) return;
    NSUInteger generation = ++overlay.dismissalGeneration;
    UIView *hostView = overlay.superview;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.42 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != overlay.dismissalGeneration) return;
        if (overlay.hasNativePreferredContentSize && overlay.hostController) {
            overlay.hostController.preferredContentSize = overlay.nativePreferredContentSize;
            overlay.hasNativePreferredContentSize = NO;
        }
        // Complete the media fade before handing the native hierarchy back.
        [overlay setPlaybackVisible:NO];
        overlay.hidden = YES;
        overlay.alpha = 0.0;
        CCBGRemoveTakeoverBackdrop(overlay);
        [overlay restoreSuppressedArtwork];
        [overlay restoreSuppressedNativeContent];
        [overlay.layer removeAllAnimations];
        for (CALayer *sublayer in overlay.layer.sublayers) [sublayer removeAllAnimations];
        if (overlay.superview != hostView) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [overlay removeFromSuperview];
        [CATransaction commit];
    });
}

static void CCBGRemoveStaleOverlaysForHost(UIView *hostView,
                                           CCBGSystemOverlayKind kind,
                                           CCBGSystemOverlayView *keep,
                                           UIViewController *controller) {
    if (!hostView || kind <= 0) return;
    BOOL takeover = CCBGGenericModuleUsesCleanTakeover(kind);
    NSArray<CCBGSystemOverlayView *> *views = nil;
    @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
    for (CCBGSystemOverlayView *candidate in views) {
        if (!candidate || candidate == keep || candidate.kind != kind) continue;
        // A takeover overlay may live on the Control Center root while the
        // newly discovered controller is still compact. Remove stale layers
        // across hosts, otherwise presentation arbitration can hide the new
        // module behind an old controller's expanded surface.
        if (!takeover && candidate.superview != hostView) continue;
        if (candidate.hostController == controller) continue;
        // A compact and expanded state for the same controller is represented
        // by one view. Any second view belongs to an old controller instance
        // and would compound blur/opacity on every reload.
        UIViewController *oldController = candidate.hostController;
        CCBGDetachOverlayViewNow(candidate);
        if (oldController) objc_setAssociatedObject(oldController, CCBGOverlayAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @synchronized (CCBGOverlayViews) { [CCBGOverlayViews removeObject:candidate]; }
    }
}

static CCBGSystemOverlayView *CCBGClaimTakeoverOverlay(UIViewController *controller,
                                                        CCBGSystemOverlayKind kind) {
    if (!controller || kind <= 0 || !CCBGGenericModuleUsesCleanTakeover(kind)) return nil;
    NSArray<CCBGSystemOverlayView *> *views = nil;
    @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
    for (CCBGSystemOverlayView *candidate in views) {
        if (!candidate || candidate.kind != kind || candidate.hostController == controller) continue;
        if (!candidate.genericUsesCustomExpansion || (!candidate.superview && !candidate.window)) continue;
        UIViewController *oldController = candidate.hostController;
        // The takeover surface may be moved from the old native module to a
        // freshly-created Control Center controller in the same run-loop
        // turn. Detach AVPlayerViewController before changing either host so
        // its old child relationship cannot outlive the view reparenting.
        // Waiting for the scheduled recovery wave is too late: UIKit can
        // validate the old parent during the intervening layout pass.
        [candidate detachNativePlayerForCompactPresentation];
        if (oldController) objc_setAssociatedObject(oldController, CCBGOverlayAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, CCBGOverlayAssociationKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        candidate.hostController = controller;
        // The root backdrop and recognizer belong to the takeover surface,
        // not to the transient native controller. They are revalidated by
        // CCBGUpdateTakeoverBackdrop on the next layout pass.
        return candidate;
    }
    return nil;
}

static void CCBGTrackOverlayController(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (!controller || kind <= 0 || !CCBGTrackedOverlayControllers) return;
    @synchronized (CCBGTrackedOverlayControllers) {
        [CCBGTrackedOverlayControllers setObject:@(kind) forKey:controller];
    }
}

static void CCBGUpdateController(UIViewController *controller, CCBGSystemOverlayKind kind) {
    CCBGTrackOverlayController(controller, kind);
    CCBGWithOverlayPreferenceSnapshot(^{
    if (!controller.isViewLoaded) return;
    if (![CCBGReadPreference(@"pluginEnabled", @YES) boolValue]) {
        CCBGRestoreNativeModuleVisibility(controller);
        CCBGHideController(controller);
        return;
    }
    if (!CCBGControllerShouldOwnOverlay(controller, kind)) {
        CCBGHideController(controller);
        return;
    }
    // Module controllers are commonly retained between Control Center
    // presentations. Do not construct an AVAsset/AVPlayerItem merely because
    // one of those retained controllers receives a layout or preference
    // callback while the Control Center is closed.
    if (!CCBGControlCenterPresentationVisible) {
        CCBGSystemOverlayView *inactiveOverlay = objc_getAssociatedObject(controller, CCBGOverlayAssociationKey);
        [inactiveOverlay suspendForInactiveControlCenterPresentation];
        return;
    }
    BOOL enabled = [CCBGReadPreference(CCBGEnabledKey(kind), @NO) boolValue];
    CCBGSystemOverlayView *overlay = objc_getAssociatedObject(controller, CCBGOverlayAssociationKey);
    if (overlay && overlay.kind != kind) {
        CCBGDetachOverlayViewNow(overlay);
        @synchronized (CCBGOverlayViews) { [CCBGOverlayViews removeObject:overlay]; }
        objc_setAssociatedObject(controller, CCBGOverlayAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        overlay = nil;
    }
    BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(kind);
    BOOL overlayWasTakeover = overlay && overlay.genericUsesCustomExpansion;
    if (!enabled) {
        if (overlay.hasNativePreferredContentSize) {
            controller.preferredContentSize = overlay.nativePreferredContentSize;
            overlay.hasNativePreferredContentSize = NO;
        }
        [overlay restoreSuppressedNativeContent];
        if (overlayWasTakeover) CCBGRestoreNativeModuleVisibility(controller);
        if (CCBGGenericModulesByKind[@(kind)] || cleanTakeover) CCBGClearGenericExpandedState(controller);
        CCBGDetachOverlayViewNow(overlay);
        return;
    }
    NSDictionary *genericModule = CCBGGenericModulesByKind[@(kind)];
    // Clear Clean-only state before probing native presentation state. This
    // makes turning the switch off an immediate handoff back to the module.
    if (!cleanTakeover && (genericModule || overlayWasTakeover)) {
        CCBGClearGenericExpandedState(controller);
        [overlay restoreSuppressedNativeContent];
        if (overlayWasTakeover) CCBGRestoreNativeModuleVisibility(controller);
        // Do not carry Clean's interaction contract into the restored native
        // presentation. The next interaction install must rebuild the normal
        // gesture set in the same update, not one refresh later.
        overlay.genericUsesCustomExpansion = NO;
        if (overlay.hasNativePreferredContentSize) {
            controller.preferredContentSize = overlay.nativePreferredContentSize;
            overlay.hasNativePreferredContentSize = NO;
        }
    }
    BOOL expanded = CCBGControllerIsExpandedPresentation(controller, kind);
    NSString *selectedName = CCBGSelectedOverlayMediaName(kind, expanded, controller.view);
    CCBGRecordOverlayDiagnostic(controller, kind, expanded, selectedName);
    if (!overlay && cleanTakeover) overlay = CCBGClaimTakeoverOverlay(controller, kind);
    if (!overlay) {
        overlay = [[CCBGSystemOverlayView alloc] initWithKind:kind];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(controller, CCBGOverlayAssociationKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @synchronized (CCBGOverlayViews) { [CCBGOverlayViews addObject:overlay]; }
    }
    overlay.dismissalGeneration++;
    UIView *nativeHostView = controller.view;
    UIView *hostView = CCBGOverlayHostView(controller, kind);
    overlay.nativeHostView = nativeHostView;
    CCBGRemoveStaleOverlaysForHost(hostView, kind, overlay, controller);
    UIView *interactionHostView = (genericModule || cleanTakeover) ? controller.view : hostView;
    overlay.layoutHostView = hostView;
    if (!overlay.superview || CGRectIsEmpty(overlay.bounds)) overlay.frame = hostView.bounds;
    BOOL presentationChanged = overlay.expandedPresentation != expanded;
    // Capture the transition before CCBGPlaceOverlay: that helper preserves
    // the old root-frame when reparenting, which gives the collapse animator
    // a real visual starting point instead of the compact bounds.
    if (presentationChanged && !expanded && cleanTakeover && overlay) {
        overlay.collapseAnimationPending = YES;
    } else if (expanded && overlay) {
        overlay.collapseAnimationPending = NO;
    }
    overlay.suppressRetainedVisualOnNextReload = presentationChanged && !expanded;
    overlay.reusePlayerItemOnNextReload = presentationChanged;
    overlay.expandedPresentation = expanded;
    if (!expanded) [overlay detachNativePlayerForCompactPresentation];
    overlay.layer.cornerRadius = CCBGAdjustedOverlayCornerRadius(hostView, overlay, expanded, kind);
    CCBGPlaceOverlay(overlay, hostView);
    CCBGKeepTakeoverOverlayOnTop(overlay);
    CCBGUpdateTakeoverBackdrop(overlay, hostView, cleanTakeover && expanded);
    // Visibility and entry motion are owned by setPlaybackVisible:. Keeping
    // the current hidden/alpha state here makes expansion interruptible
    // instead of snapping the overlay fully visible before its transition.
    // A takeover must remain above native module views in both states. In the
    // compact state this is what guarantees Clean receives the long press
    // instead of a third-party control consuming it first.
    overlay.layer.zPosition = cleanTakeover ? 1000.0 : 0.0;
    if (cleanTakeover) {
        overlay.userInteractionEnabled = YES;
        [overlay suppressNativeContentInHostView:nativeHostView];
    }
    // Match the five-module gesture contract: bind directly to the mounted
    // Clean surface. The overlay owns hit-testing while takeover is enabled,
    // so UIKit delivers swipes and vertical appearance pans consistently even
    // when Control Center's root view also has native recognizers installed.
    UIView *cleanInteractionView = cleanTakeover
        ? overlay
        : interactionHostView;
    [overlay installInteractionsOnHostView:cleanInteractionView controller:controller];
    if (kind == CCBGSystemOverlayKindMusic && selectedName.length) {
        UIImageView *artworkView = overlay.suppressedArtworkView;
        if (!artworkView || ![artworkView isDescendantOfView:controller.view]) {
            artworkView = CCBGArtworkViewInView(controller.view, overlay);
        }
        if (overlay.suppressedArtworkView != artworkView) {
            [overlay restoreSuppressedArtwork];
            overlay.suppressedArtworkView = artworkView;
            overlay.suppressedArtworkAlpha = artworkView.alpha;
            overlay.suppressedArtworkHidden = artworkView.hidden;
            overlay.suppressedArtworkShadowOpacity = artworkView.layer.shadowOpacity;
            UIView *container = artworkView.superview;
            if (container && container != controller.view) {
                overlay.suppressedArtworkContainer = container;
                overlay.suppressedContainerShadowOpacity = container.layer.shadowOpacity;
                overlay.suppressedContainerBackgroundColor = container.backgroundColor;
            }
        }
        artworkView.alpha = 0.0;
        artworkView.hidden = YES;
        artworkView.layer.shadowOpacity = 0.0;
        overlay.suppressedArtworkContainer.layer.shadowOpacity = 0.0;
        overlay.suppressedArtworkContainer.backgroundColor = UIColor.clearColor;
    } else {
        [overlay restoreSuppressedArtwork];
    }
    if (kind == CCBGSystemOverlayKindMusic && !selectedName.length &&
        [CCBGReadPreference(CCBGOverlayKey(kind, @"UseArtwork"), @YES) boolValue]) {
        overlay.dynamicArtwork = CCBGArtworkInView(controller.view, overlay);
    } else {
        overlay.dynamicArtwork = nil;
    }
    [overlay reloadIfNeeded:presentationChanged resolvedMediaName:selectedName];
    if (expanded) [overlay scheduleNativePlayerPresentationRecovery];
    [overlay applyAdaptiveFrameForHostView:hostView];
    // Takeover expansion is purely a Clean overlay presentation. Do not
    // mutate preferredContentSize: that would ask Control Center to run the
    // native expansion path and reintroduce capability-dependent behavior.
    CGSize takeoverFrameSize = overlay.preferredExpandedFrameSize;
    (void)takeoverFrameSize;
    // The old native-host call ([overlay suppressNativeContentInHostView:hostView])
    // is intentionally not used here: hostView is the root canvas while
    // nativeHostView is the individual module that must be hidden.
    if (cleanTakeover && overlay.hasNativePreferredContentSize) {
        controller.preferredContentSize = overlay.nativePreferredContentSize;
        overlay.hasNativePreferredContentSize = NO;
    }
    overlay.layer.cornerRadius = CCBGAdjustedOverlayCornerRadius(hostView, overlay, expanded, kind);
    [overlay setNeedsLayout];
    CCBGShowOverlayWithPresentationArbitration(overlay);
    });
}

static void CCBGLayoutControllerOverlay(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (!controller.isViewLoaded) return;
    CCBGSystemOverlayView *overlay = objc_getAssociatedObject(controller, CCBGOverlayAssociationKey);
    if (!overlay) return;
    BOOL expanded = CCBGControllerIsExpandedPresentation(controller, kind);
    if (overlay.kind != kind || overlay.expandedPresentation != expanded) {
        CCBGUpdateController(controller, kind);
        return;
    }
    UIView *nativeHostView = controller.view;
    UIView *hostView = CCBGOverlayHostView(controller, kind);
    if (!hostView) return;
    NSDictionary *genericModule = CCBGGenericModulesByKind[@(kind)];
    BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(kind);
    overlay.nativeHostView = nativeHostView;
    overlay.layoutHostView = hostView;
    CGRect previousFrame = overlay.frame;
    CCBGPlaceOverlay(overlay, hostView);
    CCBGKeepTakeoverOverlayOnTop(overlay);
    CCBGUpdateTakeoverBackdrop(overlay, hostView, cleanTakeover && expanded);
    BOOL collapseAnimating = cleanTakeover && !expanded &&
        (overlay.collapseAnimationPending || overlay.frameAnimator.state == UIViewAnimatingStateActive);
    if ((genericModule || cleanTakeover) && expanded) {
        CGRect targetFrame = [overlay expandedFrameForHostView:hostView module:genericModule];
        if (!CGRectEqualToRect(overlay.frame, targetFrame)) overlay.frame = targetFrame;
    } else if (!collapseAnimating) {
        if (!CGRectEqualToRect(overlay.frame, hostView.bounds)) overlay.frame = hostView.bounds;
    }
    if (cleanTakeover) {
        [overlay suppressNativeContentInHostView:nativeHostView];
        // Keep the native preferred size untouched during takeover; restoring
        // controller.preferredContentSize is only needed for a stale overlay
        // created by an older process instance.
    }
    UIView *interactionHost = cleanTakeover
        ? overlay
        : (genericModule ? controller.view : hostView);
    [overlay installInteractionsOnHostView:interactionHost controller:controller];
    overlay.layer.zPosition = cleanTakeover ? 1000.0 : 0.0;
    BOOL frameChanged = !CGRectEqualToRect(previousFrame, overlay.frame);
    overlay.layer.cornerRadius = CCBGAdjustedOverlayCornerRadius(hostView, overlay, expanded, kind);
    if (frameChanged) {
        [overlay setNeedsLayout];
        [overlay layoutIfNeeded];
    }
}

static void CCBGUpdateOrLayoutController(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (!controller.isViewLoaded || kind <= 0) return;
    CCBGSystemOverlayView *overlay = objc_getAssociatedObject(controller, CCBGOverlayAssociationKey);
    if (!CCBGControlCenterPresentationVisible) {
        [overlay suspendForInactiveControlCenterPresentation];
        return;
    }
    if (overlay) {
        // A presentation dismissal deliberately drops the AVPlayerItem and
        // removes the overlay from its host.  A geometry-only pass cannot
        // rebuild either; re-enter the full bind path when Control Center
        // opens again so covered modules cannot remain invisible.
        if (CCBGControlCenterPresentationVisible &&
            (!overlay.superview || !overlay.configurationSignature.length)) {
            CCBGUpdateController(controller, kind);
            return;
        }
        CCBGLayoutControllerOverlay(controller, kind);
        return;
    }
    // A removed overlay may be observed by several layout callbacks while
    // Control Center is rebuilding its host. Throttle the expensive creation
    // path; once it succeeds the normal lightweight layout path resumes.
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *lastAttempt = objc_getAssociatedObject(controller, CCBGOverlayRebindAttemptKey);
    if (lastAttempt && now - lastAttempt.doubleValue < 0.30) return;
    objc_setAssociatedObject(controller, CCBGOverlayRebindAttemptKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CCBGUpdateController(controller, kind);
}

static void CCBGRefreshTrackedOverlayControllers(void) {
    if (!CCBGTrackedOverlayControllers || !CCBGPluginEnabled()) return;
    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    @synchronized (CCBGTrackedOverlayControllers) {
        NSEnumerator<UIViewController *> *enumerator = CCBGTrackedOverlayControllers.keyEnumerator;
        for (UIViewController *controller in enumerator) {
            NSNumber *storedKind = [CCBGTrackedOverlayControllers objectForKey:controller];
            if (!controller || !storedKind.integerValue) continue;
            [controllers addObject:controller];
            [kinds addObject:storedKind];
        }
    }
    for (NSUInteger index = 0; index < controllers.count; index++) {
        UIViewController *controller = controllers[index];
        if (!controller.isViewLoaded || !controller.view.window) continue;
        CCBGSystemOverlayKind kind = (CCBGSystemOverlayKind)kinds[index].integerValue;
        if (kind <= 0) continue;
        // Re-enable is a full presentation recovery boundary. Even when the
        // overlay remains attached, its media/player layers may have been
        // hidden by the disable transition; a geometry-only pass cannot
        // restore them. Configuration signatures keep this idempotent.
        CCBGUpdateController(controller, kind);
    }
}

static void CCBGScheduleTrackedOverlayRefreshes(void) {
    NSUInteger generation = ++CCBGTrackedOverlayRefreshGeneration;
    // A recovery boundary only needs an immediate pass and one settling pass.
    // Four full reloads can repeatedly create AVFoundation work for every
    // mounted module during a single toggle or unlock.
    for (NSNumber *delayValue in @[@0.0, @0.35]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != CCBGTrackedOverlayRefreshGeneration || !CCBGPluginEnabled() || !CCBGControlCenterPresentationVisible) return;
            CCBGRefreshTrackedOverlayControllers();
        });
    }
}

static void CCBGScheduleTrackedOverlayRefreshOnce(void) {
    NSUInteger generation = ++CCBGTrackedOverlayRefreshGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != CCBGTrackedOverlayRefreshGeneration || !CCBGPluginEnabled() || !CCBGControlCenterPresentationVisible) return;
        CCBGRefreshTrackedOverlayControllers();
    });
}

// A reused Control Center root may not recreate child module controllers on
// every presentation. Use two bounded discovery passes; preference changes
// still use the fuller refresh schedule below.
static CFTimeInterval CCBGLastPresentationRootRebind;
static NSUInteger CCBGPresentationRootRebindGeneration;
static void CCBGSchedulePresentationRootRebind(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - CCBGLastPresentationRootRebind < 0.45) return;
    CCBGLastPresentationRootRebind = now;
    UIViewController *root = CCBGLastPresentationRoot;
    NSUInteger generation = ++CCBGPresentationRootRebindGeneration;
    // The first pass handles already-tracked overlays and newly-mounted
    // children. A single settling pass catches controllers created during
    // the Control Center transition without running the full refresh wave
    // four times on the opening animation.
    for (NSNumber *delayValue in @[@0.12, @0.42]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != CCBGPresentationRootRebindGeneration || !CCBGPluginEnabled() || !CCBGControlCenterPresentationVisible) return;
            if (!root || !root.isViewLoaded || !root.view.window || root.view.hidden) return;
            if (delayValue.doubleValue <= 0.12) CCBGRefreshTrackedOverlayControllers();
            CCBGRebindPresentationRootControllers(root);
        });
    }
}

static void CCBGHideController(UIViewController *controller) {
    CCBGSystemOverlayView *overlay = objc_getAssociatedObject(controller, CCBGOverlayAssociationKey);
    if (!overlay) return;
    CCBGSystemOverlayKind kind = overlay.kind;
    BOOL wasExpanded = overlay.expandedPresentation;
    BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(kind);
    if (!CCBGPluginEnabled()) {
        if (CCBGGenericModulesByKind[@(kind)] || cleanTakeover) CCBGClearGenericExpandedState(controller);
        CCBGDetachOverlayViewNow(overlay);
        return;
    }
    if (cleanTakeover) {
        // Control Center sends viewWillDisappear while it is rebuilding or
        // reparenting a module. A takeover surface can remain mounted on the
        // root canvas during that callback, so hiding it here would leave a
        // visible-but-inert surface with all gestures apparently broken.
        // didMoveToWindow handles the real dismissal once both views leave
        // the active window.
        if (controller.view.window || overlay.window) return;
        [overlay setPlaybackVisible:NO];
        return;
    }
    if (CCBGGenericModulesByKind[@(kind)]) {
        [overlay setPlaybackVisible:NO];
        return;
    }
    // UIKit sends viewWillDisappear: while Control Center is rearranging
    // modules. The host is still attached at that point, so this is not a
    // real dismissal and must not hide the expanded media surface.
    if (controller.view.window) return;
    // Compact controllers receive transient will/did-disappear callbacks
    // during Control Center layout. Their own didMoveToWindow hook handles
    // the real close; do not pause or hide them because another module is
    // expanding.
    if (!wasExpanded) {
        return;
    }
    [overlay setPlaybackVisible:NO];
    CCBGScheduleOverlayDetachAfterDismissal(overlay);
    if (!CCBGControlCenterPresentationVisible) return;
    NSArray<CCBGSystemOverlayView *> *views = nil;
    @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
    for (CCBGSystemOverlayView *candidate in views) {
        if (candidate != overlay && candidate.kind == overlay.kind && !candidate.expandedPresentation && candidate.window) {
            [candidate reloadIfNeeded:NO];
            [candidate setPlaybackVisible:YES];
        }
    }
}

static BOOL CCBGClassIsSubclassOf(Class cls, Class parent);
static void CCBGUpdateController(UIViewController *controller, CCBGSystemOverlayKind kind);

static void CCBGResetTakeoverPresentationState(UIViewController *presentationController) {
    NSArray<CCBGSystemOverlayView *> *views = nil;
    @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
    for (CCBGSystemOverlayView *overlay in views) {
        if (!overlay) continue;
        UIViewController *hostController = overlay.hostController;
        UIView *presentationView = presentationController.viewIfLoaded;
        // Several Control Center child controllers can disappear while the
        // sheet is still on-screen.  Never let one child's callback suspend
        // a sibling module; only release overlays actually mounted below the
        // dismissed presentation root.
        BOOL belongsToPresentation = !presentationView ||
            hostController == presentationController ||
            (hostController.viewIfLoaded && [hostController.viewIfLoaded isDescendantOfView:presentationView]) ||
            (overlay.superview && [overlay.superview isDescendantOfView:presentationView]);
        if (!belongsToPresentation) continue;
        if (CCBGGenericModulesByKind[@(overlay.kind)] || CCBGGenericModuleUsesCleanTakeover(overlay.kind)) {
            CCBGClearGenericExpandedState(hostController);
            CCBGClearGenericExpandedStateForKind(overlay.kind);
        }
        overlay.expandedPresentation = NO;
        overlay.suppressRetainedVisualOnNextReload = YES;
        // Restore native controls only after the Clean surface is no longer
        // visible; otherwise dismissal shows both surfaces at once.
        [overlay suspendForInactiveControlCenterPresentation];
        CCBGRemoveTakeoverBackdrop(overlay);
        [overlay restoreSuppressedNativeContent];
        [overlay removeFromSuperview];
    }
}

static void CCBGHookControlCenterPresentationClass(Class cls) {
    if (!CCBGClassIsSubclassOf(cls, UIViewController.class)) return;
    NSString *className = NSStringFromClass(cls);
    @synchronized (CCBGHookedControlCenterPresentationClasses) {
        if ([CCBGHookedControlCenterPresentationClasses containsObject:className]) return;
        [CCBGHookedControlCenterPresentationClasses addObject:className];
    }

    SEL selector = @selector(viewWillAppear:);
    Method method = class_getInstanceMethod(cls, selector);
    if (method) {
        IMP original = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        class_addMethod(cls, selector, original, types);
        original = class_getMethodImplementation(cls, selector);
        IMP replacement = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
            ((void (*)(id, SEL, BOOL))original)(controller, selector, animated);
            CCBGControlCenterPresentationVisible = YES;
            CCBGLastPresentationRoot = controller;
            CCBGApplyVisualThemeAutomationIfNeeded(controller.view);
            // The presentation root can be reused without recreating its
            // child module controllers. Rebind Clean surfaces on every open so
            // a previous dismissal cannot leave one overlay missing.
            CCBGSchedulePresentationRootRebind();
        });
        class_replaceMethod(cls, selector, replacement, types);
    }

    // The presentation root can stay alive across lock/unlock. Clear Clean's
    // takeover state at the real dismissal boundary so the next presentation
    // always starts compact instead of inheriting the last expanded module.
    SEL disappearSelector = @selector(viewDidDisappear:);
    Method disappearMethod = class_getInstanceMethod(cls, disappearSelector);
    if (!disappearMethod) return;
    IMP originalDisappear = method_getImplementation(disappearMethod);
    const char *disappearTypes = method_getTypeEncoding(disappearMethod);
    class_addMethod(cls, disappearSelector, originalDisappear, disappearTypes);
    originalDisappear = class_getMethodImplementation(cls, disappearSelector);
    IMP disappearReplacement = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        ((void (*)(id, SEL, BOOL))originalDisappear)(controller, disappearSelector, animated);
        // The hook is installed on more than one Control Center controller
        // class for iOS-version compatibility.  A nested controller can
        // disappear during an in-place transition; only the root recorded at
        // presentation time is allowed to end the shared visibility session.
        if (controller != CCBGLastPresentationRoot) return;
        CCBGControlCenterPresentationVisible = NO;
        CCBGDiscardOverlayTransientMediaCaches();
        CCBGResetTakeoverPresentationState(controller);
    });
    class_replaceMethod(cls, disappearSelector, disappearReplacement, disappearTypes);
}

static UIViewController *CCBGViewHostController(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = [responder nextResponder];
    }
    return nil;
}

static void CCBGUpdateSliderViewHost(UIView *view) {
    if (!view || !view.window) return;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *lastUpdate = objc_getAssociatedObject(view, CCBGSliderUpdateTimestampKey);
    if (lastUpdate && now - lastUpdate.doubleValue < 0.35) return;
    objc_setAssociatedObject(view, CCBGSliderUpdateTimestampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *controller = CCBGViewHostController(view);
    if (!controller || !controller.isViewLoaded) return;
    CCBGSystemOverlayKind kind = CCBGSharedSliderOverlayKind(controller);
    NSString *name = NSStringFromClass(controller.class);
    if (!kind && ([name localizedCaseInsensitiveContainsString:@"DisplayModule"] ||
                  [name localizedCaseInsensitiveContainsString:@"Brightness"])) {
        kind = CCBGSystemOverlayKindBrightness;
    } else if (!kind && ([name localizedCaseInsensitiveContainsString:@"Volume"] ||
                         [name localizedCaseInsensitiveContainsString:@"AudioModule"] ||
                         [name localizedCaseInsensitiveContainsString:@"MRUVolume"])) {
        kind = CCBGSystemOverlayKindVolume;
    }
    if (kind) CCBGUpdateOrLayoutController(controller, kind);
}

static void CCBGHookSliderViewClass(Class cls) {
    if (!cls || !CCBGClassIsSubclassOf(cls, UIView.class)) return;
    NSString *className = NSStringFromClass(cls);
    @synchronized (CCBGHookedClasses) {
        if ([CCBGHookedClasses containsObject:className]) return;
        [CCBGHookedClasses addObject:className];
    }
    SEL layoutSelector = @selector(layoutSubviews);
    Method layoutMethod = class_getInstanceMethod(cls, layoutSelector);
    if (layoutMethod) {
        IMP originalLayout = method_getImplementation(layoutMethod);
        const char *layoutTypes = method_getTypeEncoding(layoutMethod);
        class_addMethod(cls, layoutSelector, originalLayout, layoutTypes);
        originalLayout = class_getMethodImplementation(cls, layoutSelector);
        IMP replacementLayout = imp_implementationWithBlock(^(UIView *view) {
            ((void (*)(id, SEL))originalLayout)(view, layoutSelector);
            CCBGUpdateSliderViewHost(view);
        });
        class_replaceMethod(cls, layoutSelector, replacementLayout, layoutTypes);
    }
    SEL windowSelector = @selector(didMoveToWindow);
    Method windowMethod = class_getInstanceMethod(cls, windowSelector);
    if (windowMethod) {
        IMP originalWindow = method_getImplementation(windowMethod);
        const char *windowTypes = method_getTypeEncoding(windowMethod);
        class_addMethod(cls, windowSelector, originalWindow, windowTypes);
        originalWindow = class_getMethodImplementation(cls, windowSelector);
        IMP replacementWindow = imp_implementationWithBlock(^(UIView *view) {
            ((void (*)(id, SEL))originalWindow)(view, windowSelector);
            CCBGUpdateSliderViewHost(view);
        });
        class_replaceMethod(cls, windowSelector, replacementWindow, windowTypes);
    }
}

static void CCBGHookControllerClass(Class cls, CCBGSystemOverlayKind kind) {
    if (!CCBGClassIsSubclassOf(cls, UIViewController.class)) return;
    NSString *className = NSStringFromClass(cls);
    @synchronized (CCBGHookedClasses) {
        if ([CCBGHookedClasses containsObject:className]) return;
        [CCBGHookedClasses addObject:className];
    }

    SEL layoutSelector = @selector(viewDidLayoutSubviews);
    Method layoutMethod = class_getInstanceMethod(cls, layoutSelector);
    IMP originalLayout = method_getImplementation(layoutMethod);
    const char *layoutTypes = method_getTypeEncoding(layoutMethod);
    class_addMethod(cls, layoutSelector, originalLayout, layoutTypes);
    originalLayout = class_getMethodImplementation(cls, layoutSelector);
    IMP replacementLayout = imp_implementationWithBlock(^(UIViewController *controller) {
        ((void (*)(id, SEL))originalLayout)(controller, layoutSelector);
        CCBGSystemOverlayKind resolvedKind = [objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey) integerValue] ?: kind ?: CCBGSharedSliderOverlayKind(controller);
        if (resolvedKind) CCBGUpdateOrLayoutController(controller, resolvedKind);
    });
    class_replaceMethod(cls, layoutSelector, replacementLayout, layoutTypes);

    SEL willAppearSelector = @selector(viewWillAppear:);
    Method willAppearMethod = class_getInstanceMethod(cls, willAppearSelector);
    IMP originalWillAppear = method_getImplementation(willAppearMethod);
    const char *willAppearTypes = method_getTypeEncoding(willAppearMethod);
    class_addMethod(cls, willAppearSelector, originalWillAppear, willAppearTypes);
    originalWillAppear = class_getMethodImplementation(cls, willAppearSelector);
    IMP replacementWillAppear = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        ((void (*)(id, SEL, BOOL))originalWillAppear)(controller, willAppearSelector, animated);
        CCBGSystemOverlayKind resolvedKind = [objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey) integerValue] ?: kind ?: CCBGSharedSliderOverlayKind(controller);
        if (resolvedKind) CCBGUpdateController(controller, resolvedKind);
    });
    class_replaceMethod(cls, willAppearSelector, replacementWillAppear, willAppearTypes);

    SEL appearSelector = @selector(viewDidAppear:);
    Method appearMethod = class_getInstanceMethod(cls, appearSelector);
    IMP originalAppear = method_getImplementation(appearMethod);
    const char *appearTypes = method_getTypeEncoding(appearMethod);
    class_addMethod(cls, appearSelector, originalAppear, appearTypes);
    originalAppear = class_getMethodImplementation(cls, appearSelector);
    IMP replacementAppear = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        ((void (*)(id, SEL, BOOL))originalAppear)(controller, appearSelector, animated);
        CCBGSystemOverlayKind resolvedKind = [objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey) integerValue] ?: kind ?: CCBGSharedSliderOverlayKind(controller);
        if (resolvedKind) CCBGUpdateController(controller, resolvedKind);
    });
    class_replaceMethod(cls, appearSelector, replacementAppear, appearTypes);

    SEL willDisappearSelector = @selector(viewWillDisappear:);
    Method willDisappearMethod = class_getInstanceMethod(cls, willDisappearSelector);
    IMP originalWillDisappear = method_getImplementation(willDisappearMethod);
    const char *willDisappearTypes = method_getTypeEncoding(willDisappearMethod);
    class_addMethod(cls, willDisappearSelector, originalWillDisappear, willDisappearTypes);
    originalWillDisappear = class_getMethodImplementation(cls, willDisappearSelector);
    IMP replacementWillDisappear = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        CCBGSystemOverlayKind resolvedKind = [objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey) integerValue] ?: kind ?: CCBGSharedSliderOverlayKind(controller);
        BOOL managedMedia = resolvedKind && (CCBGGenericModulesByKind[@(resolvedKind)] != nil ||
                                             CCBGGenericModuleUsesCleanTakeover((CCBGSystemOverlayKind)resolvedKind));
        if (!managedMedia) CCBGHideController(controller);
        ((void (*)(id, SEL, BOOL))originalWillDisappear)(controller, willDisappearSelector, animated);
    });
    class_replaceMethod(cls, willDisappearSelector, replacementWillDisappear, willDisappearTypes);

    SEL disappearSelector = @selector(viewDidDisappear:);
    Method disappearMethod = class_getInstanceMethod(cls, disappearSelector);
    IMP originalDisappear = method_getImplementation(disappearMethod);
    const char *disappearTypes = method_getTypeEncoding(disappearMethod);
    class_addMethod(cls, disappearSelector, originalDisappear, disappearTypes);
    originalDisappear = class_getMethodImplementation(cls, disappearSelector);
    IMP replacementDisappear = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
        CCBGSystemOverlayKind resolvedKind = [objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey) integerValue] ?: kind ?: CCBGSharedSliderOverlayKind(controller);
        ((void (*)(id, SEL, BOOL))originalDisappear)(controller, disappearSelector, animated);
        BOOL managedMedia = resolvedKind && (CCBGGenericModulesByKind[@(resolvedKind)] != nil ||
                                             CCBGGenericModuleUsesCleanTakeover((CCBGSystemOverlayKind)resolvedKind));
        if (!managedMedia) CCBGHideController(controller);
    });
    class_replaceMethod(cls, disappearSelector, replacementDisappear, disappearTypes);
}

static id CCBGValueForKeyIfAvailable(id object, NSString *key) {
    if (!object || !key.length) return nil;
    id value = nil;
    @try { value = [object valueForKey:key]; } @catch (__unused NSException *exception) { value = nil; }
    return value;
}

static const NSUInteger CCBG_GENERIC_IDENTITY_LIMIT = 48;

static void CCBGCollectGenericObjectIdentity(id object, NSMutableSet<NSString *> *identities,
                                             NSMutableSet<NSValue *> *visited, NSUInteger *remaining,
                                             NSUInteger depth) {
    if (!object || depth > 3 || !remaining || *remaining == 0) return;
    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity]) return;
    [visited addObject:identity];
    *remaining -= 1;
    NSString *className = NSStringFromClass([object class]);
    if (className.length) [identities addObject:className];
    NSString *bundleIdentifier = [NSBundle bundleForClass:[object class]].bundleIdentifier;
    if (bundleIdentifier.length) [identities addObject:bundleIdentifier];
    if ([object isKindOfClass:NSString.class]) [identities addObject:object];
    NSArray<NSString *> *identityKeys = depth == 0
        ? @[@"moduleIdentifier", @"_moduleIdentifier", @"contentModule", @"_contentModule"]
        : @[@"moduleIdentifier", @"identifier", @"_moduleIdentifier"];
    for (NSString *key in identityKeys) {
        id value = CCBGValueForKeyIfAvailable(object, key);
        if (!value || value == object) continue;
        if ([value isKindOfClass:NSString.class]) [identities addObject:value];
        else CCBGCollectGenericObjectIdentity(value, identities, visited, remaining, depth + 1);
    }
    if ([object isKindOfClass:UIViewController.class]) {
        UIViewController *controller = object;
        if (controller.restorationIdentifier.length) [identities addObject:controller.restorationIdentifier];
        for (UIViewController *child in controller.childViewControllers) {
            CCBGCollectGenericObjectIdentity(child, identities, visited, remaining, depth + 1);
        }
    }
}

static BOOL CCBGGenericContainerHasDirectOwner(UIViewController *controller, CCBGSystemOverlayKind kind) {
    if (!controller || kind <= 0) return NO;
    NSMutableArray<UIViewController *> *pending = [controller.childViewControllers mutableCopy] ?: [NSMutableArray array];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    while (pending.count) {
        UIViewController *candidate = pending.lastObject;
        [pending removeLastObject];
        NSValue *identity = [NSValue valueWithNonretainedObject:candidate];
        if (!candidate || [visited containsObject:identity]) continue;
        [visited addObject:identity];
        NSNumber *candidateKind = objc_getAssociatedObject(candidate, CCBGGenericOverlayKindAssociationKey);
        if (candidateKind.integerValue == kind) return YES;
        if (visited.count < CCBG_GENERIC_IDENTITY_LIMIT) [pending addObjectsFromArray:candidate.childViewControllers];
    }
    return NO;
}

static BOOL CCBGGenericContainerShouldUseFallback(UIViewController *controller, NSDictionary *module) {
    NSInteger kind = [module[@"kind"] integerValue];
    return !CCBGGenericContainerHasDirectOwner(controller, (CCBGSystemOverlayKind)kind);
}

static void CCBGDetachGenericFallbackOverlaysForDirectController(UIViewController *controller, CCBGSystemOverlayKind kind) {
    for (UIViewController *candidate = controller.parentViewController; candidate; candidate = candidate.parentViewController) {
        CCBGSystemOverlayView *overlay = objc_getAssociatedObject(candidate, CCBGOverlayAssociationKey);
        if (!overlay || overlay.kind != kind) continue;
        CCBGClearGenericExpandedState(candidate);
        CCBGDetachOverlayViewNow(overlay);
        @synchronized (CCBGOverlayViews) { [CCBGOverlayViews removeObject:overlay]; }
        objc_setAssociatedObject(candidate, CCBGOverlayAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSDictionary *CCBGGenericModuleForContainerController(UIViewController *controller) {
    if (!controller || !CCBGGenericModulesByKind.count) return nil;
    NSMutableSet<NSString *> *identities = [NSMutableSet set];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    NSUInteger remaining = CCBG_GENERIC_IDENTITY_LIMIT;
    CCBGCollectGenericObjectIdentity(controller, identities, visited, &remaining, 0);
    for (NSDictionary *module in CCBGGenericModulesByKind.allValues) {
        NSString *identifier = module[@"identifier"];
        NSString *principalClass = module[@"principalClass"];
        if ((identifier.length && [identities containsObject:identifier]) ||
            (principalClass.length && [identities containsObject:principalClass])) {
            return module;
        }
    }
    return nil;
}

static void CCBGRecordGenericModuleMatch(NSDictionary *module, UIViewController *controller) {
    NSString *prefix = module[@"prefix"] ?: @"";
    if (!prefix.length || !controller.isViewLoaded) return;
    BOOL expanded = CCBGControllerIsExpandedPresentation(controller, (CCBGSystemOverlayKind)[module[@"kind"] integerValue]);
    NSDictionary *state = @{
        @"identifier": module[@"identifier"] ?: @"",
        @"principalClass": module[@"principalClass"] ?: @"",
        @"controllerClass": NSStringFromClass(controller.class) ?: @"",
        @"controllerBundle": [NSBundle bundleForClass:controller.class].bundleIdentifier ?: @"",
        @"bounds": NSStringFromCGRect(controller.view.bounds),
        @"expanded": @(expanded),
    };
    NSString *key = [prefix stringByAppendingString:@"LastRuntimeMatch"];
    NSString *supportsExpandedKey = [prefix stringByAppendingString:@"SupportsExpanded"];
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesAppSynchronize(domain);
    NSArray<NSString *> *keys = @[key, supportsExpandedKey];
    CFDictionaryRef storedRef = CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
                                                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *stored = CFBridgingRelease(storedRef) ?: @{};
    BOOL stateChanged = ![stored[key] isEqual:state];
    BOOL supportsExpandedChanged = expanded && ![stored[supportsExpandedKey] boolValue];
    if (stateChanged || supportsExpandedChanged) {
        if (stateChanged) {
            CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFDictionaryRef)state, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        }
        if (supportsExpandedChanged) {
            CFPreferencesSetValue((__bridge CFStringRef)supportsExpandedKey, (__bridge CFPropertyListRef)@YES, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(domain);
    }
}

static void CCBGUpdateGenericContainerController(UIViewController *controller) {
    if (!controller.isViewLoaded) return;
    NSDictionary *module = CCBGGenericModuleForContainerController(controller);
    if (!module || !CCBGGenericContainerShouldUseFallback(controller, module)) return;
    NSInteger kind = [module[@"kind"] integerValue];
    if (kind <= 0) return;
    objc_setAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CCBGRecordGenericModuleMatch(module, controller);
    CCBGUpdateController(controller, (CCBGSystemOverlayKind)kind);
}

static void CCBGRebindGenericContainerController(UIViewController *controller) {
    if (!controller.isViewLoaded) return;
    NSNumber *associatedKind = objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey);
    if (associatedKind.integerValue > 0) {
        // Existing overlays only need a geometry pass during root discovery.
        // Full preference/media reconciliation is reserved for newly-found
        // controllers and explicit reload paths.
        CCBGUpdateOrLayoutController(controller, (CCBGSystemOverlayKind)associatedKind.integerValue);
        return;
    }
    NSDictionary *module = CCBGGenericModuleForContainerController(controller);
    if (!module || !CCBGGenericContainerShouldUseFallback(controller, module)) return;
    NSInteger kind = [module[@"kind"] integerValue];
    if (kind <= 0) return;
    objc_setAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CCBGRecordGenericModuleMatch(module, controller);
    CCBGUpdateController(controller, (CCBGSystemOverlayKind)kind);
}

static void CCBGRebindPresentationRootControllers(UIViewController *root) {
    if (!root || !CCBGPluginEnabled() || !root.isViewLoaded) return;
    NSMutableArray<UIViewController *> *pending = [NSMutableArray arrayWithObject:root];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    NSUInteger remaining = 96;
    NSUInteger cursor = 0;
    while (cursor < pending.count && remaining > 0) {
        UIViewController *controller = pending[cursor++];
        if (!controller) continue;
        NSValue *identity = [NSValue valueWithNonretainedObject:controller];
        if ([visited containsObject:identity]) continue;
        [visited addObject:identity];
        remaining -= 1;
        // A reused presentation root can contain a newly-created module
        // controller that never passed through the previous weak registry.
        // Re-run the existing container matcher for children, then refresh
        // their overlays. Do not match the root itself: the matcher collects
        // descendant identifiers, so claiming the root would install a
        // module overlay over the entire Control Center while children are
        // still being rebuilt.
        if (controller != root) {
            CCBGRebindGenericContainerController(controller);
        }
        NSArray<UIViewController *> *children = controller.childViewControllers;
        if (children.count) [pending addObjectsFromArray:children];
        if (controller.presentedViewController) [pending addObject:controller.presentedViewController];
    }
}

static void CCBGHookGenericContainerClass(Class cls) {
    if (!CCBGClassIsSubclassOf(cls, UIViewController.class)) return;
    NSString *className = NSStringFromClass(cls);
    @synchronized (CCBGHookedGenericContainerClasses) {
        if ([CCBGHookedGenericContainerClasses containsObject:className]) return;
        [CCBGHookedGenericContainerClasses addObject:className];
    }
    SEL layoutSelector = @selector(viewDidLayoutSubviews);
    Method layoutMethod = class_getInstanceMethod(cls, layoutSelector);
    if (layoutMethod) {
        IMP originalLayout = method_getImplementation(layoutMethod);
        const char *layoutTypes = method_getTypeEncoding(layoutMethod);
        class_addMethod(cls, layoutSelector, originalLayout, layoutTypes);
        originalLayout = class_getMethodImplementation(cls, layoutSelector);
        IMP replacementLayout = imp_implementationWithBlock(^(UIViewController *controller) {
            ((void (*)(id, SEL))originalLayout)(controller, layoutSelector);
            NSNumber *kindValue = objc_getAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey);
            if (kindValue.integerValue > 0) CCBGUpdateOrLayoutController(controller, (CCBGSystemOverlayKind)kindValue.integerValue);
        });
        class_replaceMethod(cls, layoutSelector, replacementLayout, layoutTypes);
    }
    SEL appearSelector = @selector(viewDidAppear:);
    Method appearMethod = class_getInstanceMethod(cls, appearSelector);
    if (appearMethod) {
        IMP originalAppear = method_getImplementation(appearMethod);
        const char *appearTypes = method_getTypeEncoding(appearMethod);
        class_addMethod(cls, appearSelector, originalAppear, appearTypes);
        originalAppear = class_getMethodImplementation(cls, appearSelector);
        IMP replacementAppear = imp_implementationWithBlock(^(UIViewController *controller, BOOL animated) {
            ((void (*)(id, SEL, BOOL))originalAppear)(controller, appearSelector, animated);
            CCBGUpdateGenericContainerController(controller);
        });
        class_replaceMethod(cls, appearSelector, replacementAppear, appearTypes);
    }
}

static CGFloat CCBGGenericModuleExpandedDimension(NSDictionary *module, NSString *suffix, CGFloat fallback, BOOL widthDimension) {
    NSString *prefix = [module[@"prefix"] isKindOfClass:NSString.class] ? module[@"prefix"] : @"";
    NSString *key = prefix.length ? [prefix stringByAppendingString:suffix] : @"";
    CGFloat value = key.length ? [CCBGReadPreference(key, @(fallback)) doubleValue] : fallback;
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat limit = MAX(220.0, widthDimension ? MIN(screenSize.width, screenSize.height) - 24.0 : MAX(screenSize.width, screenSize.height) - 100.0);
    return MIN(MAX(220.0, value), limit);
}

static void CCBGRefreshGenericModuleExpansion(id moduleObject, CCBGSystemOverlayKind kind, BOOL expanded) {
    objc_setAssociatedObject(moduleObject, CCBGGenericExpandedStateAssociationKey, @(expanded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *controller = objc_getAssociatedObject(moduleObject, CCBGGenericModuleControllerAssociationKey);
    SEL contentSelector = NSSelectorFromString(@"contentViewController");
    if (![controller isKindOfClass:UIViewController.class] && [moduleObject respondsToSelector:contentSelector]) {
        controller = ((id (*)(id, SEL))objc_msgSend)(moduleObject, contentSelector);
    }
    if (![controller isKindOfClass:UIViewController.class]) return;
    CCBGSetGenericExpandedState(controller, expanded);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *target = controller;
        while (target.parentViewController && !CCBGControllerShouldOwnOverlay(target, kind)) target = target.parentViewController;
        if (target.isViewLoaded) CCBGUpdateController(target, kind);
    });
}

static void CCBGHookGenericExpansionCallback(Class cls, NSString *selectorName, CCBGSystemOverlayKind kind) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) return;
    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    class_addMethod(cls, selector, original, types);
    original = class_getMethodImplementation(cls, selector);
    IMP replacement = imp_implementationWithBlock(^(id object, BOOL expanded) {
        // The system callback is the actual long-press transition contract for
        // modules such as ReplayKit. Never short-circuit it for Clean takeover:
        // doing so leaves the module compact and prevents the replacement
        // player surface from ever receiving an expanded presentation.
        ((void (*)(id, SEL, BOOL))original)(object, selector, expanded);
        objc_setAssociatedObject(object, CCBGGenericExpandedStateAssociationKey, @(expanded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // Synchronize after the native callback. This preserves native module
        // lifecycle work while Clean remains the source of the overlay frame,
        // media selection, and AVKit presentation once the transition settles.
        CCBGRefreshGenericModuleExpansion(object, kind, expanded);
    });
    class_replaceMethod(cls, selector, replacement, types);
}

static void CCBGHookConfiguredModuleClass(Class cls, NSDictionary *module) {
    if (!cls || !module) return;
    NSString *className = NSStringFromClass(cls);
    @synchronized (CCBGHookedModuleClasses) {
        if ([CCBGHookedModuleClasses containsObject:className]) return;
        [CCBGHookedModuleClasses addObject:className];
    }
    SEL selector = NSSelectorFromString(@"contentViewController");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP original = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    class_addMethod(cls, selector, original, types);
    original = class_getMethodImplementation(cls, selector);
    NSInteger kind = [module[@"kind"] integerValue];
    IMP replacement = imp_implementationWithBlock(^UIViewController *(id object) {
        UIViewController *controller = ((id (*)(id, SEL))original)(object, selector);
        if (![controller isKindOfClass:UIViewController.class]) return controller;
        objc_setAssociatedObject(object, CCBGGenericModuleControllerAssociationKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, CCBGGenericControllerOwnerAssociationKey, object, OBJC_ASSOCIATION_ASSIGN);
        NSNumber *expandedState = objc_getAssociatedObject(object, CCBGGenericExpandedStateAssociationKey);
        if (expandedState) objc_setAssociatedObject(controller, CCBGGenericExpandedStateAssociationKey, expandedState, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, CCBGGenericOverlayKindAssociationKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CCBGDetachGenericFallbackOverlaysForDirectController(controller, (CCBGSystemOverlayKind)kind);
        CCBGHookControllerClass(controller.class, 0);
        if (controller.isViewLoaded) CCBGUpdateOrLayoutController(controller, (CCBGSystemOverlayKind)kind);
        return controller;
    });
    class_replaceMethod(cls, selector, replacement, types);
    if (class_getInstanceMethod(cls, NSSelectorFromString(@"willTransitionToExpandedContentMode:"))) {
        CCBGHookGenericExpansionCallback(cls, @"willTransitionToExpandedContentMode:", (CCBGSystemOverlayKind)kind);
    } else {
        CCBGHookGenericExpansionCallback(cls, @"didTransitionToExpandedContentMode:", (CCBGSystemOverlayKind)kind);
    }
}

static void CCBGInstallGenericModuleHooks(void) {
    id stored = CCBGReadPreference(@"customSystemOverlayModules", @[]);
    if (![stored isKindOfClass:NSArray.class]) return;
    [CCBGGenericModulesByKind removeAllObjects];
    for (id value in (NSArray *)stored) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = [value[@"identifier"] isKindOfClass:NSString.class] ? value[@"identifier"] : @"";
        NSString *prefix = [value[@"prefix"] isKindOfClass:NSString.class] ? value[@"prefix"] : @"";
        NSString *principalClass = [value[@"principalClass"] isKindOfClass:NSString.class] ? value[@"principalClass"] : @"";
        if (!identifier.length || !prefix.length) continue;
        NSInteger kind = CCBGGenericOverlayKindForIdentifier(identifier);
        NSMutableDictionary *module = [value mutableCopy];
        module[@"kind"] = @(kind);
        CCBGGenericModulesByKind[@(kind)] = module;
        if (principalClass.length) CCBGHookConfiguredModuleClass(objc_getClass(principalClass.UTF8String), module);
    }
}

static void CCBGInstallHooks(void) {
    for (NSString *className in @[
        @"CCUIModularControlCenterOverlayViewController",
        @"CCUIOverlayViewController",
        @"CCUIModularControlCenterViewController",
        @"CCUIControlCenterViewController",
    ]) {
        CCBGHookControlCenterPresentationClass(objc_getClass(className.UTF8String));
    }
    NSDictionary<NSString *, NSNumber *> *candidates = @{
        @"CCUIConnectivityModuleViewController": @(CCBGSystemOverlayKindConnectivity),
        @"CCUIConnectivityModuleContentViewController": @(CCBGSystemOverlayKindConnectivity),
        @"CCUIConnectivityExpandedViewController": @(CCBGSystemOverlayKindConnectivity),
        @"MRUControlCenterViewController": @(CCBGSystemOverlayKindMusic),
        @"MediaControlsPanelViewController": @(CCBGSystemOverlayKindMusic),
        @"MediaControlsViewController": @(CCBGSystemOverlayKindMusic),
        @"CCUIBrightnessModuleViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIDisplayModuleViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIBrightnessModuleContentViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIBrightnessSliderViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIBrightnessExpandedViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIBrightnessModuleExpandedContentViewController": @(CCBGSystemOverlayKindBrightness),
        @"CCUIVolumeModuleViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIVolumeModuleContentViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIVolumeSliderViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIVolumeExpandedViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIVolumeModuleExpandedContentViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIAudioModuleViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIAudioModuleContentViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIAudioModuleExpandedContentViewController": @(CCBGSystemOverlayKindVolume),
        @"MRUVolumeViewController": @(CCBGSystemOverlayKindVolume),
        @"CCUIContinuousSliderViewController": @0,
        @"CCUIContinuousSliderModuleViewController": @0,
        @"CCUIControlCenterSliderViewController": @0,
    };
    [candidates enumerateKeysAndObjectsUsingBlock:^(NSString *className, NSNumber *kind, BOOL *stop) {
        CCBGHookControllerClass(objc_getClass(className.UTF8String), kind.integerValue);
    }];
    CCBGHookSliderViewClass(objc_getClass("CCUIContinuousSliderView"));
    CCBGHookGenericContainerClass(objc_getClass("CCUIContentModuleContainerViewController"));
    CCBGInstallGenericModuleHooks();
}

static BOOL CCBGClassIsSubclassOf(Class cls, Class parent) {
    if (!cls || !parent) return NO;
    for (Class candidate = cls; candidate; candidate = class_getSuperclass(candidate)) {
        if (candidate == parent) return YES;
    }
    return NO;
}

static NSUInteger CCBGOverlayDiscoveryPasses;
static BOOL CCBGOverlayDiscoveryScheduled;

static void CCBGDiscoverBrightnessVolumeClasses(void) {
    if (CCBGOverlayDiscoveryPasses >= 4) return;
    CCBGOverlayDiscoveryPasses += 1;
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return;
    classCount = objc_getClassList(classes, classCount);
    for (int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        if (!CCBGClassIsSubclassOf(cls, UIViewController.class)) continue;
        NSString *name = NSStringFromClass(cls);
        if (![name localizedCaseInsensitiveContainsString:@"ViewController"]) continue;
        if ([name localizedCaseInsensitiveContainsString:@"Brightness"] ||
            [name localizedCaseInsensitiveContainsString:@"DisplayModule"]) {
            CCBGHookControllerClass(cls, CCBGSystemOverlayKindBrightness);
        } else if ([name localizedCaseInsensitiveContainsString:@"Volume"] ||
                   [name localizedCaseInsensitiveContainsString:@"AudioModule"] ||
                   [name localizedCaseInsensitiveContainsString:@"MRUVolume"]) {
            CCBGHookControllerClass(cls, CCBGSystemOverlayKindVolume);
        } else if ([name hasPrefix:@"CCUI"] && [name localizedCaseInsensitiveContainsString:@"Slider"]) {
            CCBGHookControllerClass(cls, 0);
        }
    }
    free(classes);
}

static void CCBGScheduleBrightnessVolumeDiscovery(void) {
    @synchronized ([CCBGSystemOverlayView class]) {
        if (CCBGOverlayDiscoveryScheduled || CCBGOverlayDiscoveryPasses >= 4) return;
        CCBGOverlayDiscoveryScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized ([CCBGSystemOverlayView class]) { CCBGOverlayDiscoveryScheduled = NO; }
        CCBGDiscoverBrightnessVolumeClasses();
    });
}

static BOOL CCBGHookInstallScheduled;
static NSObject *CCBGHookInstallationLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static void CCBGScheduleHookInstallation(void) {
    BOOL shouldSchedule = NO;
    @synchronized (CCBGHookInstallationLock()) {
        if (!CCBGHookInstallScheduled) {
            CCBGHookInstallScheduled = YES;
            shouldSchedule = YES;
        }
    }
    if (!shouldSchedule) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (CCBGHookInstallationLock()) {
            CCBGHookInstallScheduled = NO;
        }
        CCBGInstallHooks();
    });
}

static void CCBGImageLoaded(const struct mach_header *header, intptr_t slide) {
    CCBGScheduleHookInstallation();
    Dl_info imageInfo = {0};
    if (header && dladdr(header, &imageInfo) != 0 && imageInfo.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:imageInfo.dli_fname].lowercaseString;
        if ([path containsString:@"controlcenter"] || [path containsString:@"brightness"] ||
            [path containsString:@"audiomodule"] || [path containsString:@"volume"]) {
            CCBGScheduleBrightnessVolumeDiscovery();
        }
    }
}

static void CCBGSystemOverlayReload(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (CCBGSystemOverlayReloadScheduled) return;
        CCBGSystemOverlayReloadScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CCBGSystemOverlayReloadScheduled = NO;
        // The master switch is hosted by a separate Control Center bundle on
        // some iOS builds. Invalidate this process' preference cache before
        // resolving the new enabled state from the Darwin notification.
        CCBGInvalidatePreferenceReadCache();
        CCBGWithOverlayPreferenceSnapshot(^{
            CCBGInvalidateSceneRuntimeCaches();
            CCBGInstallGenericModuleHooks();
            BOOL pluginEnabled = CCBGPluginEnabled();
            NSArray<CCBGSystemOverlayView *> *views = nil;
            @synchronized (CCBGOverlayViews) { views = CCBGOverlayViews.allObjects; }
            BOOL locked = CCBGSystemIsLocked();
            BOOL presentationVisible = CCBGControlCenterPresentationVisible;
            // Locking is a real Control Center presentation boundary. Clear
            // takeover expansion before the next unlock so a replacement
            // third-party controller cannot reopen in the stale expanded
            // state left by the previous presentation.
            if (locked) {
                CCBGControlCenterPresentationVisible = NO;
                CCBGDiscardOverlayTransientMediaCaches();
                for (CCBGSystemOverlayView *overlay in views) {
                    if (!overlay) continue;
                    if (CCBGGenericModuleUsesCleanTakeover(overlay.kind)) {
                        CCBGClearGenericExpandedStateForKind(overlay.kind);
                        CCBGClearGenericExpandedState(overlay.hostController);
                    }
                    overlay.expandedPresentation = NO;
                    [overlay suspendForInactiveControlCenterPresentation];
                    CCBGRemoveTakeoverBackdrop(overlay);
                    [overlay restoreSuppressedNativeContent];
                }
            }
            for (CCBGSystemOverlayView *overlay in (locked ? @[] : views)) {
                BOOL configured = CCBGGenericModulesByKind[@(overlay.kind)] || overlay.kind <= CCBGSystemOverlayKindVolume;
                BOOL enabled = configured && [CCBGReadPreference(CCBGEnabledKey(overlay.kind), @NO) boolValue];
                UIViewController *hostController = overlay.hostController;
                if (!pluginEnabled || !enabled) {
                    if ((CCBGGenericModulesByKind[@(overlay.kind)] ||
                         CCBGGenericModuleUsesCleanTakeover(overlay.kind)) && hostController) {
                        CCBGClearGenericExpandedState(hostController);
                    }
                    CCBGDetachOverlayViewNow(overlay);
                    CCBGRestoreNativeModuleVisibility(hostController);
                    continue;
                }
                // SpringBoard keeps many Control Center controllers mounted
                // after the sheet closes. Preference/style notifications can
                // still reach them there; defer their media/layout rebuild to
                // the next real presentation instead of waking AVFoundation
                // and its helper processes while nothing is on screen.
                if (!presentationVisible) {
                    overlay.configurationSignature = nil;
                    overlay.lastConfigurationCheck = 0.0;
                    continue;
                }
                if (hostController.isViewLoaded && (hostController.view.window || hostController.view.superview)) {
                    CCBGUpdateController(hostController, overlay.kind);
                } else if (overlay.window && !overlay.hidden) {
                    [overlay reloadAfterPreferenceChange];
                    CCBGShowOverlayWithPresentationArbitration(overlay);
                }
            }
            if (!pluginEnabled) {
                // An overlay can be detached from the weak table while its
                // native controller remains mounted. Restore those controllers
                // too, so disabling the master switch never leaves a blank tile.
                NSMutableArray<UIViewController *> *trackedControllers = [NSMutableArray array];
                NSMutableArray<NSNumber *> *trackedKinds = [NSMutableArray array];
                @synchronized (CCBGTrackedOverlayControllers) {
                    for (UIViewController *tracked in CCBGTrackedOverlayControllers) {
                        NSNumber *storedKind = [CCBGTrackedOverlayControllers objectForKey:tracked];
                        if (tracked && storedKind.integerValue > 0) {
                            [trackedControllers addObject:tracked];
                            [trackedKinds addObject:storedKind];
                        }
                    }
                }
                for (NSUInteger index = 0; index < trackedControllers.count; index++) {
                    UIViewController *tracked = trackedControllers[index];
                    CCBGSystemOverlayKind kind = (CCBGSystemOverlayKind)trackedKinds[index].integerValue;
                    if (CCBGGenericModulesByKind[@(kind)] || CCBGGenericModuleUsesCleanTakeover(kind)) {
                        CCBGClearGenericExpandedState(tracked);
                        CCBGRestoreNativeModuleVisibility(tracked);
                    }
                }
            }
            // Re-enable is a full presentation recovery boundary. Tracked
            // controllers cover modules seen before the toggle; the root
            // rebind also discovers the currently mounted controllers after a
            // lock/unlock cycle. Without both passes, enabling and disabling
            // the master switch can leave a covered module's native view
            // suppressed with no overlay left to restore it.
            if (pluginEnabled && !locked && presentationVisible) {
                CCBGScheduleTrackedOverlayRefreshes();
                CCBGSchedulePresentationRootRebind();
            }
        });
        });
    });
}

static void CCBGSystemOverlayPresentationRecovery(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CCBGInvalidatePreferenceReadCache();
        if (!CCBGPluginEnabled()) return;
        CCBGInvalidateSceneRuntimeCaches();
        CCBGInstallGenericModuleHooks();
        // The reload notification can arrive while Control Center is still
        // rearranging its host views. Reuse the tracked-controller recovery
        // waves after that host settles instead of forcing synchronous layout.
        CCBGScheduleTrackedOverlayRefreshes();
    });
}

static NSUInteger CCBGFocusRefreshGeneration;
static NSUInteger CCBGFocusStateChangeGeneration;
static NSString *CCBGLastFocusStateSignature;

static void CCBGHandleFocusActivityChange(void) {
    NSUInteger generation = ++CCBGFocusStateChangeGeneration;
    for (NSNumber *delayValue in @[@0.08, @0.35, @0.90]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != CCBGFocusStateChangeGeneration) return;
            CCBGInvalidateSceneRuntimeCaches();
            NSArray<NSString *> *aliases = CCBGCurrentFocusAliases();
            NSString *signature = [aliases componentsJoinedByString:@"|"];
            if (![signature isEqualToString:CCBGLastFocusStateSignature]) {
                CCBGLastFocusStateSignature = [signature copy];
                // The next Control Center presentation resolves the current
                // scene from these refreshed aliases. Avoid waking retained
                // overlay controllers just to redraw an offscreen surface.
                if (CCBGControlCenterPresentationVisible) CCBGPostReload();
            }
        });
    }
}

static void CCBGScheduleFocusRefreshes(void) {
    CCBGObserveFocusActivityChanges(^{ CCBGHandleFocusActivityChange(); });
    NSUInteger generation = ++CCBGFocusRefreshGeneration;
    for (NSNumber *delayValue in @[@0.0, @0.8, @2.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != CCBGFocusRefreshGeneration) return;
            NSArray *modes = CCBGRefreshFocusModeCache();
            CCBGCurrentFocusAliases();
            if (modes.count) CCBGFocusRefreshGeneration++;
        });
    }
}

static void CCBGFocusRefreshCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ CCBGScheduleFocusRefreshes(); });
}

static void CCBGStartNetworkMonitoring(void) {
    CCBGNetworkMonitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(CCBGNetworkMonitor, dispatch_get_main_queue());
    nw_path_monitor_set_update_handler(CCBGNetworkMonitor, ^(nw_path_t path) {
        CCBGConnectivityState state = CCBGConnectivityStateOffline;
        if (nw_path_get_status(path) == nw_path_status_satisfied) {
            if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) state = CCBGConnectivityStateWiFi;
            else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) state = CCBGConnectivityStateCellular;
            else state = CCBGConnectivityStateOther;
        }
        if (state == CCBGCurrentConnectivityState) return;
        CCBGCurrentConnectivityState = state;
        // Store network state immediately, but do not construct or reload an
        // overlay until it can actually be seen.
        if (!CCBGControlCenterPresentationVisible) return;
        @synchronized (CCBGOverlayViews) {
            for (CCBGSystemOverlayView *overlay in CCBGOverlayViews) {
                if (overlay.kind == CCBGSystemOverlayKindConnectivity) [overlay reloadIfNeeded:YES];
            }
        }
    });
    nw_path_monitor_start(CCBGNetworkMonitor);
}

static __attribute__((noinline)) void CCBGSystemOverlayStart(void) {
    CCBGMigrateLegacyAutomationPreferences();
    CCBGOverlayViews = [NSHashTable weakObjectsHashTable];
    CCBGHookedClasses = [NSMutableSet set];
    CCBGHookedControlCenterPresentationClasses = [NSMutableSet set];
    CCBGHookedModuleClasses = [NSMutableSet set];
    CCBGHookedGenericContainerClasses = [NSMutableSet set];
    CCBGGenericModulesByKind = [NSMutableDictionary dictionary];
    CCBGGenericExpandedStates = [NSMutableDictionary dictionary];
    CCBGTrackedOverlayControllers = [NSMapTable weakToStrongObjectsMapTable];
    CCBGTrackedOverlayRefreshGeneration = 0;
    CCBGPreloadedOverlayAssets = [NSMutableDictionary dictionary];
    CCBGPreloadedOverlayFrames = [NSCache new];
    CCBGPreloadedOverlayImages = [NSCache new];
    CCBGLastOverlayDiagnosticValues = [NSMutableDictionary dictionary];
    CCBGPreloadedOverlayFrames.countLimit = 12;
    CCBGPreloadedOverlayImages.countLimit = 12;
    CCBGPreloadedOverlayImages.totalCostLimit = 8 * 1024 * 1024;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCBGSystemOverlayReload,
                                    (__bridge CFStringRef)CCBGReloadNotificationName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCBGSystemOverlayPresentationRecovery,
                                    (__bridge CFStringRef)CCBGPresentationRecoveryNotificationName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    for (NSString *notificationName in @[
        @"com.apple.interface-style.changed",
        @"com.apple.springboard.interface-style.changed",
        @"com.apple.backboardd.interface-style.changed",
        @"AppleInterfaceThemeChangedNotification",
        @"AppleInterfaceStyleChangedNotification",
        @"com.apple.UIKit.interfaceStyleChanged",
        @"com.apple.UIKit.userInterfaceStyleChanged",
        @"com.apple.springboard.lockstate",
        @"com.apple.springboard.hasBlankedScreen",
    ]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCBGSystemOverlayReload,
                                        (__bridge CFStringRef)notificationName, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCBGFocusRefreshCallback,
                                    (__bridge CFStringRef)CCBGFocusRefreshNotificationName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(CCBGImageLoaded);
    CCBGStartNetworkMonitoring();
    CCBGPrewarmOverlayMedia();
    CCBGScheduleStartupOverlayRefreshes();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        CCBGInstallHooks();
    });
    CCBGObserveFocusActivityChanges(^{ CCBGHandleFocusActivityChange(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CCBGScheduleFocusRefreshes();
    });
    CCBGScheduleBrightnessVolumeDiscovery();
}

static void CCBGSystemOverlayRunLoopObserverCallback(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    static BOOL started = NO;
    if (started) return;
    started = YES;
    CCBGSystemOverlayStart();
}

__attribute__((constructor)) static void CCBGSystemOverlayInit(void) {
    // A dylib constructor runs inside dyld's initializer walk. Keep it free of
    // blocks, dispatch calls, and dyld image-registration APIs; defer startup
    // until SpringBoard's main run loop has entered its first cycle.
    CFRunLoopObserverContext context = {0, NULL, NULL, NULL, NULL};
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(
        kCFAllocatorDefault, kCFRunLoopBeforeWaiting, false, 0,
        CCBGSystemOverlayRunLoopObserverCallback, &context);
    if (observer) {
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
        CFRelease(observer);
    }
}
