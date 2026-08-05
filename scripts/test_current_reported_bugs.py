from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
shared = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
overlay = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")

# iOS 16 C2 transitions (and BetterCC's compatibility path) ask mounted
# module surfaces for this private animation-container entry point. The Clean
# overlay is a custom UIView, so it must answer the selector or the first
# Control Center presentation crashes with an unrecognized selector.
assert "- (UIView *)c2AnimationContainerView;" in overlay
assert "- (UIView *)caAnimationContainerView;" in overlay
overlay_implementation = overlay.split("@implementation CCBGSystemOverlayView", 1)[1]
overlay_animation_method = overlay_implementation.split("- (instancetype)initWithKind:", 1)[0]
assert "- (UIView *)c2AnimationContainerView" in overlay_animation_method
assert "return self;" in overlay_animation_method
assert "- (UIView *)caAnimationContainerView" in overlay

# Covered generic modules must expose the same AVPlayerViewController transport
# surface as the five custom modules while expanded, then hide it cleanly when
# returning to compact mode.
assert "#import <AVKit/AVKit.h>" in overlay
assert "AVPlayerViewController *nativePlayerController" in overlay
assert "nativePlayerPresentationFallbackVisible" in overlay
assert "nativePresentationRecoveryGeneration" in overlay
assert "nativePresentationRecoveryArmed" in overlay
assert "- (void)scheduleNativePlayerPresentationRecovery" in overlay
assert "- (void)attachNativePlayerControllerToHost:(UIViewController *)host" in overlay
assert "- (UIViewController *)nativePlayerPresentationHost" in overlay
assert "CCBGViewHostController(self.superview) ?: self.hostController" in overlay
assert "[native willMoveToParentViewController:nil]" in overlay
assert "[self attachNativePlayerControllerToHost:[self nativePlayerPresentationHost]]" in overlay
assert "[host addChildViewController:controller]" not in overlay
assert "[controller didMoveToParentViewController:host]" not in overlay
assert "nativePlayerHostController" not in overlay
assert "[host addChildViewController:native]" in overlay
assert "[native didMoveToParentViewController:host]" in overlay
assert "CCBGTouchIsNativeTransportControl" in overlay
assert "touchTargetsNativePlayer && CCBGTouchIsNativeTransportControl" in overlay
assert "if (hasVideo) [self attachNativePlayerControllerToHost:host];" in overlay
assert "delayValue.doubleValue >= 0.45" in overlay
assert "delayValue.doubleValue >= 1.20" in overlay
assert "CCBGOverlayUsesCleanTakeover(self) && self.expandedPresentation" in overlay
assert "- (void)updateNativePlayerPresentation" in overlay
assert "- (void)detachNativePlayerForCompactPresentation" in overlay
assert "native.showsPlaybackControls = YES" in overlay
assert "[self detachNativePlayerForCompactPresentation]" in overlay
assert "[native willMoveToParentViewController:nil]" in overlay.rsplit("- (void)detachNativePlayerForCompactPresentation", 1)[1]
assert "[native removeFromParentViewController]" in overlay.rsplit("- (void)detachNativePlayerForCompactPresentation", 1)[1]
assert "if (expanded) [overlay scheduleNativePlayerPresentationRecovery];" in overlay

# A master-switch re-enable must rediscover currently mounted controllers, and
# the disable fallback must restore nested native module views.
assert "CCBGSchedulePresentationRootRebind();" in overlay
assert "NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:view];" in overlay
module = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
director = (ROOT / "app" / "CCBGSceneDirectorController.m").read_text(encoding="utf-8")
advanced = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
visual_features = (ROOT / "app" / "CCBGVisualFeaturesControllers.m").read_text(encoding="utf-8")
settings = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")
root_controller = (ROOT / "app" / "CCBGRootController.m").read_text(encoding="utf-8")
app_delegate = (ROOT / "app" / "CleanCCBG2x2App.m").read_text(encoding="utf-8")
controls = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")

# Native table rows and custom control rows share one rounded material style.
assert "CCBGRoundedAppCells" in controls
assert "method_exchangeImplementations" in controls
assert "CCBGStyleControlCell(self);" in controls
assert "cell.backgroundView = nil;" in controls
assert "cell.layer.cornerRadius = 16.0;" in controls
assert "ccbg_rounded_setHighlighted:animated:" in controls
assert "CCBGAnimateControlCellPress(self, highlighted, animated);" in controls

# The grid picker writes the slot-scoped footprint and immediately re-renders
# only its own row.  Control Center already receives the size notification;
# this keeps the in-app highlighted cells in sync without resetting scrolling.
grid_body = settings.split("- (void)gridFootprintSelected:", 1)[1].split("- (void)showGridApplyInstructions", 1)[0]
assert "CCBGWriteModulePreferences" in grid_body
assert "reloadRowsAtIndexPaths" in grid_body
assert "indexPathForRow:0 inSection:1" in grid_body

# Automatic sequential/random playback also runs while a module is compact.
# Compact auto-advance must not install a media transition: the host owns the
# compact module frame and animating its player layer can make the module fly
# out and disappear at the end of a video.
advance_body = module.split("- (void)advanceBy:(NSInteger)offset", 1)[1].split("@end", 1)[0]
assert "[self showCurrentMediaWithTransition:self.expanded];" in advance_body
assert "[self showCurrentMediaWithTransition:YES];" not in advance_body
assert "self.visible = YES;" in advance_body
assert "self.view.layer.hidden = NO;" in advance_body

# Expanded sizing is owned by the expanded Control Center host. Compact
# slideshow changes must not rewrite preferredContentSize and trigger a host
# relayout while the player is advancing.
reload_body = module.split("- (void)reloadPreferencesAndMedia", 1)[1].split("- (void)applyFallbackColor", 1)[0]
assert 'NSArray<NSDictionary *> *queue = mode == 0 ? eligible : [self playbackQueueForItems:eligible];' in reload_body
assert 'NSInteger mode = MIN(2, MAX(0, [CCBGModulePreference(@"playbackMode", @0) integerValue]));' in reload_body
assert 'if (!overrideSelection.length && selection.length && !CCBGMediaItemNamed(self.mediaItems, selection))' in reload_body
assert '[expandedQueue insertObject:preferred atIndex:0];' in reload_body

# Control Center mounts five module instances in one pass. The shared media
# catalog must reuse a short-lived snapshot in SpringBoard so each instance
# does not rescan the filesystem synchronously during the opening animation.
assert "CCBGMediaCatalogCacheTimestamp" in shared
assert "CCBGMediaCatalogCacheTTL" in shared
assert "now - cachedAt < CCBGMediaCatalogCacheTTL" in shared
assert "CCBGMediaCatalogCache = snapshot;" in shared
assert "CCBGMediaDirectoryReadableCacheAt" in shared
assert "CCBGMediaDirectoryReadableCacheValue" in shared
assert "CCBGMediaDirectoryReadableCacheAt < CCBGMediaCatalogCacheTTL" in shared

# Layout settles through many callbacks. Mounted recovery is needed after a
# real geometry/player-surface change, but must not run on every unchanged pass.
layout_body = module.split("- (void)viewDidLayoutSubviews", 1)[1].split("- (void)reloadAfterFirstMountIfNeeded", 1)[0]
assert "if (playbackPassNeeded || !self.didScheduleFirstMountedReload) [self reloadAfterFirstMountIfNeeded];" in layout_body
assert "[self reloadAfterFirstMountIfNeeded];\n    // Layout callbacks" not in layout_body

# Generic overlay layout also repeats a window-coordinate conversion for the
# adaptive crop on every settle callback. Reapply that composition only when
# the geometry or expansion state actually changed.
assert "lastSceneLayoutBounds" in overlay
assert "lastSceneLayoutMediaBounds" in overlay
assert "sceneLayoutGeometryChanged" in overlay
assert "if (sceneLayoutGeometryChanged) {" in overlay
assert "[self applyCachedSceneComposition];" in overlay

# Startup prewarming only refreshes the catalog. Decoding every configured
# video at startup keeps backboardd/xpcproxy busy before Control Center opens.
# Coalesce the catalog pass and keep a meaningful completion cooldown.
assert "CCBGPrewarmInFlight" in overlay
assert "CCBGPrewarmLastCompletedAt" in overlay
assert "if (CCBGPrewarmInFlight) return;" in overlay
assert "now - CCBGPrewarmLastCompletedAt < 20.0" in overlay
prewarm_body = overlay.split("static void CCBGPrewarmOverlayMedia", 1)[1].split("static void CCBGScheduleStartupOverlayRefreshes", 1)[0]
assert "CCBGLoadVideoOnlyAsset" not in prewarm_body
assert "AVAssetImageGenerator" not in prewarm_body
assert "dispatch_group" not in prewarm_body
show_body = module.split("- (void)showCurrentMediaWithTransition:", 1)[1].split("- (void)preloadNextMedia", 1)[0]
assert "if (self.currentItem && self.expanded) [self updateAdaptiveExpandedSizeForItem:self.currentItem];" in reload_body
assert "if (self.expanded) [self updateAdaptiveExpandedSizeForItem:self.currentItem];" in show_body
transition_body = module.split("- (void)didTransitionToExpandedContentMode:", 1)[1].split("- (void)handleExpandedSwipe:", 1)[0]
assert "if (expanded && self.currentItem) [self updateAdaptiveExpandedSizeForItem:self.currentItem];" in transition_body
adaptive_body = module.split("- (void)updateAdaptiveExpandedSizeForItem:", 1)[1].split("- (void)manualAdvanceBy:", 1)[0]
assert "if (!self.expanded) return;" in adaptive_body
assert 'CCBGModulePreference(@"expandedWidth", @430)' in module
assert 'CCBGModulePreference(@"expandedHeight", @600)' in module
assert 'NSArray *defaults = @[@0, @0, @0, @0, @430, @600];' in advanced
assert 'self.moduleSlot, @430' in visual_features
assert 'self.moduleSlot, @600' in visual_features

# Expanded replacement must retain the decoded cover until AVPlayerItem is
# ready; otherwise the native controller can expose a black surface during a
# slow decode or a stalled sequential/random transition.
native_body = module.rsplit("- (void)updateNativePlayerPresentation", 1)[1].split("- (void)updateAdaptiveExpandedSizeForItem:", 1)[0]
assert "AVPlayerItemStatusReadyToPlay" in native_body
assert "nativeControlsReady" in native_body
assert "nativePresentationFallbackVisible" in module
assert "delayValue.doubleValue >= 0.45" in module
assert "playerItem.status == AVPlayerItemStatusReadyToPlay || self.nativePresentationFallbackVisible" in native_body
assert "if (self.nativePlayerController.player != self.player)" in native_body
assert "self.nativePlayerController.player = useNativePlayer ? self.player : nil;" not in native_body
assert "lastNativePresentationStateSignature" in module
assert "if ([stateSignature isEqualToString:self.lastNativePresentationStateSignature]) return;" in native_body
assert "Store the post-update state" in native_body
compact_native = native_body.split("if (useNativePlayer) {", 1)[1].split("} else {", 1)[1]
assert "self.nativePlayerController.player = nil;" not in compact_native

# Collapsing an expanded custom module must not tear down AVPlayerViewController
# or force a synchronous layout while CCSupport is animating the host.
compact_detach = module.rsplit("- (void)detachNativePlayerForCompactTransition", 1)[1].split("- (void)updateNativePlayerPresentation", 1)[0]
assert "native.player = nil" not in compact_detach
assert "removeFromSuperview" not in compact_detach
transition_body = module.split("- (void)didTransitionToExpandedContentMode:", 1)[1].split("- (void)handleExpandedSwipe:", 1)[0]
assert "if (!expanded) return;" in transition_body

# Focus discovery uses the exact iOS 16 runtime-header API. It must not invoke
# arbitrary getter-shaped private methods on SpringBoard's main thread.
focus_body = shared.split("static NSArray *CCBGFocusModeServices(void)", 1)[1].split("static void CCBGCollectConfiguredFocusModes", 1)[0]
for selector in ("modeConfigurationsReturningError:", "availableModesReturningError:", "allModesReturningError:"):
    assert selector in shared
assert "class_copyMethodList" not in focus_body

# Media changes must not push the module content in from a screen edge. Stored
# legacy styles remain valid, but every runtime transition is non-directional.
transition_body = module.split("- (void)showCurrentMediaWithTransition:(BOOL)transition", 1)[1].split("- (void)updateNativePlayerPresentation", 1)[0]
for directional in ("kCATransitionMoveIn", "kCATransitionPush", "kCATransitionFromRight", "kCATransitionFromLeft"):
    assert directional not in transition_body
assert "kCATransitionFade" in transition_body
assert "CASpringAnimation" in transition_body
assert "MIN(0.60, MAX(0.16" in transition_body
assert '@[@"淡化", @"柔和淡化", @"轻微缩放", @"快速淡化"]' in advanced
overlay_reload = overlay.rsplit("- (void)reloadIfNeeded:(BOOL)force", 1)[1].split("- (void)startPlaybackWhenReady", 1)[0]
assert "UIImage *retainedVisual = suppressRetainedVisual ? nil : self.imageView.image" in overlay_reload
assert "cover ?: retainedVisual ?: CCBGPlaceholderImageForItem(item)" in overlay_reload
assert 'title:@"过渡时长" key:@"crossfadeDuration" fallback:0.35 minimum:0.16 maximum:0.60' in settings

# Collapsing a generic system module should reuse the same AVPlayerItem when
# the selected video did not change. Replacing it synchronously causes a
# hitch, and falling back to the expanded presentation's image leaves one
# stale last frame visible during the compact transition.
assert "suppressRetainedVisualOnNextReload" in overlay
assert "reusePlayerItemOnNextReload" in overlay
assert "BOOL canReusePlayerItem" in overlay_reload
assert "if (!canReusePlayerItem)" in overlay_reload
assert "BOOL suppressRetainedVisual" in overlay_reload
assert "UIImage *retainedVisual = suppressRetainedVisual ? nil : self.imageView.image" in overlay_reload
assert "BOOL mediaChanged" in overlay_reload
assert "hadConfiguration && mediaChanged && !suppressRetainedVisual" in overlay_reload
assert "expandedFrameForHostView:hostView module:" in overlay
assert "self.adaptiveExpandedFrameEnabled && naturalSize.width > 1.0" in overlay
assert "aspect = MIN(2.0, MAX(0.5, aspect))" in overlay
assert 'CCBGGenericModuleExpandedDimension(genericModule, @"ExpandedWidth", 420.0, YES)' in overlay
assert 'CCBGGenericModuleExpandedDimension(genericModule, @"ExpandedHeight", 480.0, NO)' in overlay
assert 'MIN(screenSize.width, screenSize.height) - 24.0' in overlay
assert "CGRect availableBounds = UIEdgeInsetsInsetRect(bounds, safeInsets)" in overlay
assert "CGRectGetMinX(availableBounds) + floor" in overlay
# Generic overlays must stay behind the host's native content when no named
# backdrop exists. Inserting at logicalIndex makes the media view topmost and
# hides native icons, labels, and controls on third-party modules.
assert "if (!foundBackdrop && overlay && CCBGGenericModulesByKind[@(overlay.kind)]) return logicalIndex;" not in overlay
assert "return MIN(index, logicalIndex);" in overlay
assert 'CCBGOverlayKey(overlay.kind, @"MediaAboveNative")' in overlay
assert 'BOOL mediaAboveNative' in overlay
assert '@"素材覆盖原生内容"' in settings
assert 'MediaAboveNative' in settings
assert "self.frameAnimator" in overlay
assert "initWithDuration:0.18 curve:UIViewAnimationCurveEaseOut" in overlay
assert "(genericModule || cleanTakeover) && self.expandedPresentation && self.window && self.hasPresented" in overlay
# An outside-tap collapse must animate from the expanded root surface back to
# the compact host instead of immediately reparenting and snapping to bounds.
assert "collapseAnimationPending" in overlay
assert "UIViewAnimationCurveEaseInOut" in overlay
assert "takeoverBackdropAnimator" in overlay
assert "backdrop.alpha = 0.0" in overlay
assert "if (!self.collapseAnimationPending && !self.expandedPresentation && cleanTakeover" in overlay
assert "BOOL collapseAnimating = cleanTakeover && !expanded" in overlay
assert "self.mediaContainerView.bounds.size.width * 0.10" in overlay
assert "self.sceneContentMode != 0 ? 1.06 : 1.0" in overlay
assert "BOOL sliderOverlay = self.kind == CCBGSystemOverlayKindBrightness || self.kind == CCBGSystemOverlayKindVolume;" in overlay
assert "self.expandedPresentation && !sliderOverlay ? 0.45 : 0.0" in overlay
assert "CGFloat mediaInset = 0.0" in overlay
assert "CGRect mediaFrame = CGRectInset(self.bounds, mediaInset, mediaInset)" in overlay
assert "BOOL genericPresentationMedia" in overlay
assert "self.expandedPresentation && genericPresentationMedia ? @0 : @1" in overlay
assert "static CGFloat CCBGAdjustedOverlayCornerRadius" in overlay
assert "self.imageView.alpha = 0.0" in overlay
assert "self.imageView.alpha = mediaOpacityPresentation ? visualAlpha : 1.0" in overlay
assert "expectedMediaAlpha" in overlay
assert "self.blurView.alpha = expandedMaterial ? MIN(0.90, MAX(0.0, blur)) : 0.0;" in overlay
assert "CGFloat presentationDim = self.expandedPresentation ? MAX(dim, 0.03) : dim;" in overlay
assert "curve:UIViewAnimationCurveEaseOut" in overlay
assert "self.playerSurfaceView" in overlay
assert "if (self.playerLayer.readyForDisplay) {" in overlay
assert "self.imageView.hidden = YES;" in overlay
assert "BOOL needsReadinessCheck = !self.player.currentItem" in overlay
assert "lastCompositionSignature" in overlay
assert "NSStringFromCGAffineTransform(transform)" in overlay
assert "nativeSuppressionMatchesHostView" in overlay
assert "if ([self nativeSuppressionMatchesHostView:hostView]) return;" in overlay

# Dismissal must hide the Clean surface before restoring native controls. The
# reverse order briefly composites native icons over the outgoing video frame.
detach_body = overlay.split("static void CCBGDetachOverlayViewNow", 1)[1].split("static void CCBGScheduleOverlayDetachAfterDismissal", 1)[0]
assert detach_body.index("[overlay setPlaybackVisible:NO];") < detach_body.index("[overlay restoreSuppressedNativeContent];")
scheduled_detach_body = overlay.split("static void CCBGScheduleOverlayDetachAfterDismissal", 1)[1].split("static void CCBGRemoveStaleOverlaysForHost", 1)[0]
assert scheduled_detach_body.index("[overlay setPlaybackVisible:NO];") < scheduled_detach_body.index("[overlay restoreSuppressedNativeContent];")
reset_body = overlay.split("static void CCBGResetTakeoverPresentationState", 1)[1].split("static void CCBGHookControlCenterPresentationClass", 1)[0]
assert reset_body.index("[overlay setPlaybackVisible:NO];") < reset_body.index("[overlay restoreSuppressedNativeContent];")

# Native AVPlayer fallback recovery must invalidate the presentation signature;
# otherwise the 0.45s fallback pass can be skipped as an apparent no-op.
assert "nativePresentationFallbackVisible" in module
assert module.count("self.nativePresentationFallbackVisible,") >= 2
recovery_body = module.rsplit("- (void)scheduleNativePlayerPresentationRecovery", 1)[1].split("- (void)detachNativePlayerForCompactTransition", 1)[0]
assert "nativeSurfaceAttached" in recovery_body
assert "nativeControlsReady" in recovery_body
assert "BOOL nativeSurfaceAttached" in native_body
assert "BOOL nativeControlsReady" in native_body
assert "self.imageView.hidden = !nativeControlsReady" in native_body
# A reused Control Center root must schedule a tracked overlay rebind on open.
assert "CCBGSchedulePresentationRootRebind();" in overlay.split("static void CCBGHookControlCenterPresentationClass", 1)[1].split("static UIViewController *CCBGViewHostController", 1)[0]
# Root discovery must walk children without treating the presentation root as
# a generic module fallback. Its identity collection includes descendant
# module identifiers; claiming the root would cover the whole Control Center
# and make unrelated modules disappear.
rebind_body = overlay.split("static void CCBGRebindPresentationRootControllers", 1)[1].split("static void CCBGHookGenericContainerClass", 1)[0]
assert "if (controller != root) {" in rebind_body
assert "CCBGRebindGenericContainerController(controller);" in rebind_body
assert "static void CCBGRebindGenericContainerController" in overlay
refresh_body = overlay.split("static void CCBGRefreshTrackedOverlayControllers", 1)[1].split("static void CCBGScheduleTrackedOverlayRefreshes", 1)[0]
assert "CCBGRebindPresentationRootControllers(CCBGLastPresentationRoot)" not in refresh_body
window_block = overlay.split("- (void)didMoveToWindow", 1)[1].split("- (void)traitCollectionDidChange", 1)[0]
assert "CCBGScheduleTrackedOverlayRefreshOnce();" in window_block
assert "CCBGScheduleTrackedOverlayRefreshes();" not in window_block
root_schedule_body = overlay.rsplit("static void CCBGSchedulePresentationRootRebind", 1)[1].split("static void CCBGHideController", 1)[0]
assert "CCBGScheduleTrackedOverlayRefreshes();" not in root_schedule_body
assert "@[@0.12, @0.42]" in root_schedule_body
assert "CCBGRebindPresentationRootControllers(root)" in root_schedule_body
set_visible_block = overlay.rsplit("- (void)setPlaybackVisible:(BOOL)visible", 1)[1].split("- (void)restoreSuppressedArtwork", 1)[0]
assert "self.player.currentItem.status != AVPlayerItemStatusReadyToPlay" in set_visible_block
assert "|| self.imageView.image != nil" not in set_visible_block

# Appearance preferences are applied from preference/transition callbacks;
# layout passes only re-check them when geometry or expanded state changed.
assert "appearanceGeometryChanged" in module
assert "self.lastAppearanceBounds = self.view.bounds;" in module

# The expanded media picker is presented as a navigation controller. Both
# cancel and row selection must dismiss that controller, not the table child.
picker_body = module.rsplit("- (void)presentMediaSelectionList {", 1)[1].split("- (void)clearMediaSelectionState", 1)[0]
assert "UINavigationController *navigation = self.mediaPickerController.navigationController" in picker_body
assert "[navigation dismissViewControllerAnimated:YES" in picker_body
selection_body = module.split("- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:", 1)[1].split("- (void)selectMediaNamed:(NSString *)fileName {", 1)[0]
assert "[navigation dismissViewControllerAnimated:YES completion:finishSelection]" in selection_body

# Native AVPlayer transport touches must not be interpreted as module-level
# horizontal media navigation gestures.
assert "gestureRecognizer == self.swipeLeft || gestureRecognizer == self.swipeRight" in module
assert "CCBGTouchIsNativeTransportControl" in module
assert "touchTargetsNativePlayer && CCBGTouchIsNativeTransportControl(touch, nativePlayerView)" in module

# Selecting sequential/random mode enables the existing video-end advance
# path, while fixed mode remains non-advancing.
assert 'if (mode != 0) changes[@"slideshowEnabled"] = @YES;' in module
assert 'if (mode != 0) CCBGWriteModulePreference(@"slideshowEnabled"' in root_controller

# CCSwitch has a native single-tap and long-press expansion path. Its explicit
# identifier must be handled before generic geometry/state fallbacks.
expanded_body = overlay.split("static BOOL CCBGControllerIsExpandedPresentation", 1)[1].split("static CGFloat CCBGOverlayCornerRadius", 1)[0]
assert "CCBGCCSwitchExpandedState" in expanded_body
assert "netskao.ccswitchdatamodule" in overlay
assert "shouldBeginTransitionToExpandedContentModule" in overlay
claim_body = overlay.split("static CCBGSystemOverlayView *CCBGClaimTakeoverOverlay", 1)[1].split("static void CCBGTrackOverlayController", 1)[0]
assert "[candidate detachNativePlayerForCompactPresentation];" in claim_body
assert "self.expandedPresentation = NO;\n                // The overlay is about to be detached" in overlay
assert "self.expandedPresentation = NO;\n    [self detachNativePlayerForCompactPresentation];" in overlay
assert "overlay.expandedPresentation = NO;\n                    [overlay detachNativePlayerForCompactPresentation];" in overlay
assert 'MediaAboveNative' in overlay
assert 'genericUsesCustomExpansion' in overlay
assert 'CCBGGenericModuleUsesCustomExpansion' in overlay
assert 'expandedControlPanel' in overlay
assert 'expandedModeButtonTapped:' in overlay
assert 'expandedMediaButtonTapped:' in overlay

# A generic module with MediaAboveNative may use our custom long-press
# expansion.  The gesture delegate must only reject presentation-media
# touches when native expansion owns the interaction.
gesture_block = overlay.split("- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:", 1)[1].split("- (BOOL)gestureRecognizerShouldBegin:", 1)[0]
assert "self.genericUsesPresentationMedia && !self.genericUsesCustomExpansion" in gesture_block
assert "if (self.genericUsesPresentationMedia) return NO;" not in gesture_block

# Visibility convergence must compare the alpha that setPlaybackVisible:
# actually writes.  layer.opacity is never synchronized with targetOpacity
# and causes repeated fade animations whenever a non-1 opacity is configured.
visibility_block = overlay.rsplit("- (void)setPlaybackVisible:(BOOL)visible", 1)[1].split("- (void)restoreSuppressedArtwork", 1)[0]
assert "fabs(self.layer.opacity - targetOpacity)" not in visibility_block
assert "visualAlpha" in visibility_block
assert "(visible ? !self.hidden : self.hidden)" in visibility_block

# Custom expansion must use the overlay's last resolved presentation state.
# CCBGControllerIsExpandedPresentation can return an unknown sentinel (-1),
# which would be truthy if coerced directly to BOOL on the first long press.
long_press_block = overlay.split("- (void)handleOverlayLongPress:", 1)[1].split("- (void)handleGenericStateTap:", 1)[0]
assert "BOOL expanded = self.expandedPresentation;" in long_press_block
assert "BOOL expanded = CCBGControllerIsExpandedPresentation(self.hostController, self.kind);" not in long_press_block

# The media container intentionally has an inset/control-panel frame in the
# expanded state, so comparing it to the overlay bounds is permanently true.
# Layout callbacks must not force layoutIfNeeded on every pass.
adaptive_frame_block = overlay.split("- (void)applyAdaptiveFrameForHostView:", 1)[1].split("static BOOL CCBGHasOverlayPreferenceSnapshot", 1)[0]
layout_controller_block = overlay.split("static void CCBGLayoutControllerOverlay", 1)[1].split("static void CCBGUpdateOrLayoutController", 1)[0]
assert "BOOL mediaBoundsChanged" not in adaptive_frame_block
assert "BOOL mediaBoundsChanged" not in layout_controller_block
assert "if (frameChanged)" in layout_controller_block and "[overlay layoutIfNeeded];" in layout_controller_block

# Fixed-mode looping is asynchronous. Its seek completion must still belong
# to the item that ended, otherwise a quick manual switch can seek the new
# item using the old video's start time.
ended_block = overlay.split("- (void)videoEnded:", 1)[1].split("- (void)pausePlaybackPreservingPresentation", 1)[0]
assert "AVPlayerItem *endedItem = notification.object;" in ended_block
assert "self.player.currentItem == endedItem" in ended_block

# A pending readiness probe can outlive a Control Center dismissal.  Hiding
# the overlay must clear the active marker so the next presentation can start
# a fresh probe instead of remaining stuck on its placeholder frame.
readiness_block = overlay.rsplit("- (void)schedulePlaybackReadinessCheck:", 1)[1].split("- (void)playbackStalled:", 1)[0]
assert "if (self.hidden)" in readiness_block
assert "self.readinessCheckActive = NO;" in readiness_block.split("if (attempt == 0)", 1)[0]
assert "if (self.sceneLowPowerCoverActive)" in readiness_block
failure_guard = readiness_block.split("if (self.player.currentItem.status == AVPlayerItemStatusFailed)", 1)[1].split("BOOL itemReady", 1)[0]
assert "self.readinessCheckActive = NO;" in failure_guard
low_power_restore = overlay.split("if (!self.sceneLowPowerCoverActive) return;", 1)[1].split("- (NSArray<NSDictionary *> *)availableVideoItems", 1)[0]
assert "schedulePlaybackReadinessCheck" in low_power_restore

# Mounted convergence must be coalesced per instance; four delayed waves on
# every callback are the direct source of first-open Control Center hitching.
convergence = module.split("- (void)scheduleMountedPresentationConvergence:", 1)[1].split("- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot", 1)[0]
assert "convergenceGeneration" in convergence
assert "cancel" in convergence.lower() or "generation" in convergence.lower()
assert "lastConvergenceDiagnosticSignature" in module
assert 'isEqualToString:@"playback-start"' in shared

# Replay must expose a useful empty state and acknowledge a successful tap.
assert "CCBGSceneTimeline()" in director
assert 'CCBGRecordSceneTimelineEvent(@"manual-snapshot"' in director
assert "没有可回放" in director or "暂无回放" in director
assert "已恢复" in director or "replay" in director.lower()

# Control Center writes currentMedia from SpringBoard. The App keeps an
# in-process preference snapshot while it is backgrounded, so foregrounding
# must invalidate it and repaint visible previews.
app_active = app_delegate.split("- (void)applicationDidBecomeActive:", 1)[1].split("- (void)application:", 1)[0]
assert "CCBGInvalidatePreferenceReadCache();" in app_active
assert "reloadVisibleTableViewsInView" in app_active
assert "reloadRowsAtIndexPaths" in app_delegate
assert "indexPathsForVisibleRows" in app_delegate

# Returning to the main media library should not rebuild every cell when the
# catalog and filter state are unchanged; only visible rows need repainting.
root_body = (ROOT / "app" / "CCBGRootController.m").read_text(encoding="utf-8")
assert "catalogSignature" in root_body
assert "renderedFilterSignature" in root_body
assert "BOOL catalogChanged" in root_body
assert "if (catalogChanged || filterChanged" in root_body
assert "indexPathsForVisibleRows" in root_body

# Preview error/status cards should measure text only after a real bounds or
# message change, not on every layout callback during presentation.
preview_body = (ROOT / "app" / "CCBGPreviewController.m").read_text(encoding="utf-8")
assert "lastStatusBounds" in preview_body
assert "hasStatusLayout" in preview_body
assert "if (self.hasStatusLayout && CGRectEqualToRect(self.lastStatusBounds, self.view.bounds)) return;" in preview_body

# Grouped media navigation should not rebuild every section when returning to
# an unchanged catalog, and it should share the throttled thumbnail loader.
grouped_body = advanced.split("@implementation CCBGGroupedLibraryController", 1)[1].split("@interface CCBGLibraryInsightsController", 1)[0]
assert "catalogSignature" in grouped_body
assert "if (self.groups.count && [signature isEqualToString:self.catalogSignature]) return;" in grouped_body
assert 'CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"group-")' in grouped_body

print("current reported bug regression structure: PASS")
