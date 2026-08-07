from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")


custom_body = SOURCE.split("static BOOL CCBGGenericModuleUsesCustomExpansion", 1)[1].split("static BOOL CCBGGenericModuleUsesCleanTakeover", 1)[0]
assert "MediaAboveNative" in custom_body
assert "netskao.ccswitchdatamodule" not in custom_body
assert "return YES;" in custom_body

takeover_body = SOURCE.split("static BOOL CCBGGenericModuleUsesCleanTakeover", 1)[1].split("static CGSize CCBGCleanExpandedMaximumSize", 1)[0]
assert "MediaAboveNative" in takeover_body
selected_media_body = SOURCE.split("static NSString *CCBGSelectedOverlayMediaName", 1)[1].split("static NSArray<NSDictionary *> *CCBGAvailableOverlayItems", 1)[0]
assert "expanded && CCBGGenericModuleUsesCleanTakeover(kind)" in selected_media_body
assert "CCBGSelectedOverlayMediaName(kind, NO, view)" in selected_media_body
assert "kind >= CCBGSystemOverlayKindConnectivity && kind <= CCBGSystemOverlayKindVolume" in takeover_body
assert "CCBGGenericExpandedStates" in SOURCE
assert "CCBGGenericExpandedStateForKind" in SOURCE
assert "CCBGClearGenericExpandedStateForKind" in SOURCE
assert "CCBGOverlayUsesCleanTakeover" in SOURCE
assert "CCBGClaimTakeoverOverlay" in SOURCE

frame_body = SOURCE.split("- (CGRect)expandedFrameForHostView", 1)[1].split("- (void)applyAdaptiveFrameForHostView", 1)[0]
assert "CCBGCleanExpandedMaximumSize()" in frame_body
assert "CCBGCleanExpandedSizeForNaturalSize" in frame_body
assert "CCBGGenericModuleExpandedDimension" in frame_body

layout_body = SOURCE.split("- (void)layoutSubviews", 1)[1].split("- (void)didMoveToWindow", 1)[0]
assert "suppressNativeContentInHostView" in layout_body
assert "restoreSuppressedNativeContent" in layout_body
assert "self.opaque = NO;" in layout_body
assert "self.mediaContainerView.backgroundColor" in layout_body
assert "suppressedNativeGestureStates" in SOURCE
assert "gesture.enabled = NO" in SOURCE
suppression_body = SOURCE.split("- (BOOL)nativeSuppressionMatchesHostView", 1)[1].split("@end", 1)[0]
# Clean owns the expansion gesture. ReplayKit's native long press otherwise
# presents its background controller full-screen and bypasses the player.
assert "[gesture isKindOfClass:UILongPressGestureRecognizer.class]" not in suppression_body
# Diagnostic builds must retain the handoff state outside the bounded trace.
for event in [
    "takeover-clean-long-press",
    "takeover-presentation-change",
    "takeover-player-probe",
    "TakeoverCleanLongPress",
    "TakeoverNativeExpansionBlocked",
]:
    assert event in SOURCE

hit_test_body = SOURCE.split("- (UIView *)hitTest:(CGPoint)point withEvent", 1)[1].split("- (void)expandedModeButtonTapped", 1)[0]
assert "CCBGOverlayUsesCleanTakeover" in hit_test_body
assert "return self;" in hit_test_body
assert "return nil;" in hit_test_body
assert "mediaContainerView pointInside" in hit_test_body
assert "applyExpandedMediaOpacity:(CGFloat)opacity" in SOURCE
assert "self.mediaContainerView.alpha = 1.0;" in SOURCE
assert "BOOL mediaOpacityPresentation = visible && self.expandedPresentation && CCBGOverlayUsesCleanTakeover(self);" in SOURCE
assert "self.playerLayer.opacity = mediaOpacityPresentation ? visualAlpha : 1.0;" in SOURCE
assert "self.alpha = 1.0;" in SOURCE

insertion_body = SOURCE.split("static NSUInteger CCBGOverlayInsertionIndex", 1)[1].split("static void CCBGPlaceOverlay", 1)[0]
assert "CCBGGenericModuleUsesCleanTakeover(overlay.kind)" in insertion_body
assert "return logicalIndex;" in insertion_body
assert "CCBGKeepTakeoverOverlayOnTop" in SOURCE
assert "backdrop.backgroundColor = UIColor.clearColor;" in SOURCE
assert "UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark" in SOURCE

long_press_body = SOURCE.split("- (void)handleOverlayLongPress:", 1)[1].split("- (void)handleGenericStateTap:", 1)[0]
assert "BOOL customExpansion = CCBGGenericModuleUsesCustomExpansion(self.kind);" in long_press_body
assert "!customExpansion && ![CCBGReadPreference(CCBGOverlayKey(self.kind, @\"LongPressEnabled\"), @YES) boolValue]" in long_press_body
assert "CCBGSetGenericExpandedState(self.hostController, !expanded)" in long_press_body
receive_touch_body = SOURCE.split("- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:", 1)[1].split("- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneously", 1)[0]
assert "!self.genericUsesCustomExpansion && !CCBGOverlayUsesCleanTakeover(self)" in receive_touch_body
assert "gestureRecognizer == self.appearancePan" in receive_touch_body
assert "self.expandedControlPanel" in receive_touch_body
assert "gestureRecognizerShouldBegin" in SOURCE
assert "Horizontal movement belongs to the dedicated swipe recognizers" in SOURCE
assert "gestureRecognizer == self.appearancePan || otherGestureRecognizer == self.appearancePan" in SOURCE
assert "handleTakeoverOutsideTap" in SOURCE
assert "takeoverOutsideTap" in SOURCE
assert "takeoverRootTap" in SOURCE
outside_tap_body = SOURCE.split("- (void)handleTakeoverOutsideTap:", 1)[1].split("- (void)handleOverlayLongPress:", 1)[0]
assert "CCBGSetGenericExpandedStateForKind(self.kind, NO);" in outside_tap_body
assert "BOOL controllerIsMounted = controller && controller.isViewLoaded && controller.view.window;" in outside_tap_body
assert "CCBGScheduleTrackedOverlayRefreshes();" in outside_tap_body
assert "The root recognizer is the lifecycle fallback" in SOURCE
assert "CCBGSetGenericExpandedState(controller, NO)" in outside_tap_body
assert "UIView *cleanInteractionView = cleanTakeover" in SOURCE
assert "? overlay" in SOURCE.split("UIView *cleanInteractionView = cleanTakeover", 1)[1].split("[overlay installInteractionsOnHostView", 1)[0]
assert "self.swipeLeft.cancelsTouchesInView = NO" in SOURCE
assert "self.swipeRight.cancelsTouchesInView = NO" in SOURCE
assert "self.appearancePan.cancelsTouchesInView = NO" in SOURCE
assert "self.blurView.alpha = self.expandedPresentation ? MIN(0.90, MAX(0.0, blur)) : 0.0;" in SOURCE
assert "@[self.swipeLeft, self.swipeRight, self.longPress, self.appearancePan]" in SOURCE
assert "fabs(velocity.y) > fabs(velocity.x) * 1.15 && fabs(velocity.y) > 2.0" in SOURCE
assert "[self playbackMode] == 0 && !CCBGGenericModuleUsesCleanTakeover(self.kind)" in SOURCE
assert "self.swipeLeft.view == hostView && self.swipeRight.view == hostView && self.appearancePan.view == hostView" in SOURCE
assert "CGPoint startPoint = [recognizer locationInView:self.mediaContainerView];" in SOURCE
assert "self.adjustingBlur = startPoint.x < CGRectGetMidX(self.mediaContainerView.bounds);" in SOURCE
assert "expectedMediaAlpha" in SOURCE

# Outside dismissal must be handled before the takeover surface bounds check;
# otherwise a tap on the full-screen backdrop is rejected as "outside" the
# overlay and the expanded module can never collapse from an external tap.
receive_touch_prefix = receive_touch_body.split("BOOL takeover =", 1)[0]
assert receive_touch_prefix.index("gestureRecognizer == self.takeoverOutsideTap") < receive_touch_body.index("BOOL takeover =")

controller_body = SOURCE.split("static BOOL CCBGControllerIsExpandedPresentation", 1)[1].split("static CGFloat CCBGOverlayCornerRadius", 1)[0]
assert "CCBGGenericModuleUsesCleanTakeover(kind)" in controller_body
assert "CCBGGenericExpandedStateAssociationKey" in controller_body
assert "CCBGClearGenericExpandedState" in SOURCE
assert "static void CCBGSetGenericExpandedState" in SOURCE

update_body = SOURCE.split("static void CCBGUpdateController(UIViewController *controller, CCBGSystemOverlayKind kind) {", 1)[1].split("static void CCBGLayoutControllerOverlay", 1)[0]
assert "nativePreferredContentSize" in update_body
assert "preferredExpandedFrameSize" in update_body
assert "restoreSuppressedNativeContent" in update_body
assert "overlay.userInteractionEnabled = YES" in update_body
assert update_body.index("CCBGPlaceOverlay(overlay, hostView)") < update_body.index("CCBGKeepTakeoverOverlayOnTop(overlay)")
assert update_body.index("CCBGClearGenericExpandedState(controller)") < update_body.index("BOOL expanded = CCBGControllerIsExpandedPresentation")
install_index = update_body.index("[overlay installInteractionsOnHostView")
assert "[overlay suppressNativeContentInHostView:hostView]" in update_body
layout_controller_body = SOURCE.split("static void CCBGLayoutControllerOverlay", 1)[1].split("static void CCBGUpdateOrLayoutController", 1)[0]
assert "controller.preferredContentSize" in layout_controller_body
assert layout_controller_body.index("CCBGPlaceOverlay(overlay, hostView)") < layout_controller_body.index("CCBGKeepTakeoverOverlayOnTop(overlay)")

callback_body = SOURCE.split("static void CCBGHookGenericExpansionCallback", 1)[1].split("static void CCBGHookConfiguredModuleClass", 1)[0]
# A takeover must preserve the third-party module's real long-press callback.
# ReplayKit performs its expansion lifecycle in this method; short-circuiting
# it leaves the module compact and no expanded player can be presented.
assert "if (CCBGGenericModuleUsesCleanTakeover(kind)) return;" not in callback_body
native_callback = "((void (*)(id, SEL, BOOL))original)(object, selector, expanded);"
assert native_callback in callback_body
assert "CCBGRefreshGenericModuleExpansion(object, kind, expanded);" in callback_body
assert callback_body.index(native_callback) < callback_body.index("objc_setAssociatedObject(object, CCBGGenericExpandedStateAssociationKey")
reload_body = SOURCE.split("static void CCBGSystemOverlayReload", 1)[1].split("static void CCBGSystemOverlayPresentationRecovery", 1)[0]
assert "CCBGClearGenericExpandedState(hostController)" in reload_body
assert "CCBGGenericModuleUsesCleanTakeover(overlay.kind)" in reload_body
assert "CCBGRestoreNativeModuleVisibility(hostController)" in reload_body
assert "if (!pluginEnabled)" in reload_body
assert "CCBGRestoreNativeModuleVisibility(tracked)" in reload_body
assert "CCBGRestoreNativeModuleVisibility(controller)" in SOURCE
assert "BOOL overlayWasTakeover = overlay && overlay.genericUsesCustomExpansion;" in update_body
assert "if (overlayWasTakeover) CCBGRestoreNativeModuleVisibility(controller);" in update_body
assert "if (!overlay && cleanTakeover) overlay = CCBGClaimTakeoverOverlay(controller, kind);" in update_body
assert "overlay.genericUsesCustomExpansion = NO;" in update_body
claim_body = SOURCE.split("static CCBGSystemOverlayView *CCBGClaimTakeoverOverlay", 1)[1].split("static void CCBGTrackOverlayController", 1)[0]
assert "objc_setAssociatedObject(oldController, CCBGOverlayAssociationKey, nil" in claim_body
assert "objc_setAssociatedObject(controller, CCBGOverlayAssociationKey, candidate" in claim_body
assert "candidate.hostController = controller;" in claim_body
fallback_body = SOURCE.split("static void CCBGDetachGenericFallbackOverlaysForDirectController", 1)[1].split("static NSDictionary *CCBGGenericModuleForContainerController", 1)[0]
assert "CCBGClearGenericExpandedState(candidate)" in fallback_body
hide_body = SOURCE.rsplit("static void CCBGHideController", 1)[1].split("static BOOL CCBGClassIsSubclassOf", 1)[0]
assert "CCBGGenericModulesByKind[@(kind)] || cleanTakeover" in hide_body
assert "if (CCBGGenericModuleUsesCleanTakeover(kind)) return controller.view;" in SOURCE
assert "BOOL cleanTakeover = CCBGGenericModuleUsesCleanTakeover(kind);" in update_body
assert "(genericModule || cleanTakeover) ? controller.view : hostView" in update_body
assert "UIView *cleanInteractionView = cleanTakeover" in update_body
assert "? overlay" in update_body.split("UIView *cleanInteractionView = cleanTakeover", 1)[1].split("[overlay installInteractionsOnHostView", 1)[0]
assert "CCBGUpdateTakeoverBackdrop(overlay, hostView, cleanTakeover && expanded)" in update_body
hide_body = SOURCE.rsplit("static void CCBGHideController", 1)[1].split("static BOOL CCBGClassIsSubclassOf", 1)[0]
assert "if (cleanTakeover)" in hide_body
assert "if (controller.view.window || overlay.window) return;" in hide_body
assert hide_body.index("if (cleanTakeover)") < hide_body.index("if (CCBGGenericModulesByKind[@(kind)])")
layout_backdrop_body = SOURCE.split("static void CCBGLayoutControllerOverlay", 1)[1].split("static void CCBGUpdateOrLayoutController", 1)[0]
assert "CCBGUpdateTakeoverBackdrop(overlay, hostView" in layout_backdrop_body
assert "takeoverBackdrop" in SOURCE
assert "CCBGResetTakeoverPresentationState" in SOURCE
assert "CCBGClearGenericExpandedStateForKind(overlay.kind)" in SOURCE
reload_lock_body = SOURCE.split("static void CCBGSystemOverlayReload", 1)[1].split("static void CCBGSystemOverlayPresentationRecovery", 1)[0]
# The lock state is sampled once, then reused throughout the coalesced
# reload. Test that behavior rather than requiring a specific if expression.
assert "BOOL locked = CCBGSystemIsLocked();" in reload_lock_body
assert "if (locked)" in reload_lock_body
assert "overlay.expandedPresentation = NO;" in reload_lock_body
assert "viewDidDisappear:" in SOURCE.split("static void CCBGHookControlCenterPresentationClass", 1)[1].split("static UIViewController *CCBGViewHostController", 1)[0]
assert "[overlay installInteractionsOnHostView:interactionHost controller:controller];" in layout_backdrop_body
ownership_body = SOURCE.split("static BOOL CCBGControllerShouldOwnOverlay", 1)[1].split("static void CCBGRecordOverlayDiagnostic", 1)[0]
assert "candidate = controller; candidate; candidate = candidate.parentViewController" in ownership_body
assert "CCBGGenericModuleForContainerController(controller)" in ownership_body

print("Generic module takeover fully owns native visibility, interaction, expansion state, and sizing.")
