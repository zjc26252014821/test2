from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def block(text: str, start: str, end: str) -> str:
    return text.rsplit(start, 1)[1].split(end, 1)[0]


def main() -> None:
    module = (ROOT / "module/CleanCCBG2x2.m").read_text(encoding="utf-8")
    utility = (ROOT / "utilitymodule/CleanCCBGDefaultRestore.m").read_text(encoding="utf-8")
    overlay = (ROOT / "systemoverlay/CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
    header = (ROOT / "shared/CCBGMediaCatalog.h").read_text(encoding="utf-8")
    shared = (ROOT / "shared/CCBGMediaCatalog.m").read_text(encoding="utf-8")

    manual_advance = block(module, "- (void)commitPendingManualAdvance", "- (void)videoReachedBoundary")
    for token in (
        "self.visible = YES", "self.view.hidden = NO", "self.view.alpha = 1.0",
        "self.view.layer.hidden = NO", "self.view.layer.opacity = 1.0",
        'convergeMountedPresentation:@"manual-advance"',
        'scheduleMountedPresentationConvergence:@"manual-advance"',
    ):
        assert token in manual_advance, token
    assert "[self showCurrentMediaWithTransition:NO]" in manual_advance
    assert "[self showCurrentMediaWithTransition:YES]" not in manual_advance

    selection = block(module, "- (void)selectMediaNamed:(NSString *)fileName makeConstant:", "- (BOOL)isCharging")
    assert 'scheduleMountedPresentationConvergence:@"select-media"' in selection

    scheduled_recovery = block(module, "- (void)scheduleMountedPresentationConvergence:", "- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot")
    assert "if (!self.visible || !self.view.window) return;" not in scheduled_recovery
    assert "weakSelf.view.window && !weakSelf.view.window.hidden" in scheduled_recovery
    assert 'CCBGModuleGlobalPreference(@"pluginEnabled", @YES)' in scheduled_recovery
    assert "weakSelf.visible = YES;" in scheduled_recovery

    disappeared = block(module, "- (void)viewDidDisappear:(BOOL)animated", "- (void)viewWillTransitionToSize:")
    assert "self.convergenceGeneration += 1;" in disappeared

    window_change = block(module, "- (void)handleModuleWindowChange:(BOOL)attached", "- (void)viewDidDisappear:(BOOL)animated")
    assert "NSUInteger generation = self.convergenceGeneration;" in window_change
    assert "generation != delayedWeakSelf.convergenceGeneration" in window_change

    first_mount = block(module, "- (void)reloadAfterFirstMountIfNeeded", "- (void)protectedDataDidBecomeAvailable:")
    assert "NSUInteger generation = self.convergenceGeneration;" in first_mount
    assert "generation != self.convergenceGeneration" in first_mount

    presentation_callback = module.rsplit("static void CCBGPresentationRecoveryCallback", 1)[1].split("@implementation CCBG_VIEW_CONTROLLER_CLASS", 1)[0]
    assert "NSUInteger generation = controller.convergenceGeneration;" in presentation_callback
    assert "generation != controller.convergenceGeneration" in presentation_callback

    batch_action = block(utility, "- (void)performBatchAction:", "- (BOOL)shouldBeginTransitionToExpandedContentModule")
    assert "CCBGPostReload();" not in batch_action
    assert "dispatch_after" not in batch_action

    hierarchy_repair = block(module, "- (BOOL)repairMountedPresentationHierarchyForFullRecovery:", "- (void)scheduleMountedPresentationConvergence:")
    assert "CCBGHasVisibleOverlappingSiblingAbove" in module
    assert "CCBGHasVisibleOverlappingSiblingAbove(ancestor)" in hierarchy_repair
    assert "[ancestor.superview bringSubviewToFront:ancestor]" in hierarchy_repair
    convergence = block(module, "- (void)convergeMountedPresentation:", "- (BOOL)repairMountedPresentationHierarchyForFullRecovery:")
    assert "explicitHierarchyRecovery" in convergence
    assert 'hasPrefix:@"manual-advance"' in convergence
    assert 'hasPrefix:@"select-media"' in convergence
    assert "|| explicitHierarchyRecovery" in convergence

    # Native expanded playback must be selected from player ownership, not the
    # temporary hidden flag. During Control Center transitions UIKit can hide
    # the child view for a frame; readiness must still restore that view.
    readiness = block(module, "- (void)revealVideoWhenReadyForItem:", "- (void)recoverPlayerLayerSurfaceIfNeededForItem:")
    assert "BOOL nativePresentation" not in readiness
    assert "if (self.expanded && playerItem.status == AVPlayerItemStatusReadyToPlay)" in readiness
    assert "[self updateNativePlayerPresentation];" in readiness
    mounted_recovery = block(module, "- (BOOL)requiresMountedPresentationRecovery", "- (void)convergeMountedPresentation:")
    assert "nativePlayerMissing" in mounted_recovery
    assert "nativePlayerController.view.hidden" in mounted_recovery

    dismissal = block(overlay, "static void CCBGScheduleOverlayDetachAfterDismissal", "static CCBGSystemOverlayKind CCBGAssociatedGenericKindForController")
    assert "dismissalGeneration" in dismissal
    assert "dispatch_after" in dismissal
    assert dismissal.index("dispatch_after") < dismissal.index("removeFromSuperview")
    assert "[overlay.player pause]" not in dismissal.split("dispatch_after", 1)[0]
    hide_controller = block(overlay, "static void CCBGHideController", "static BOOL CCBGClassIsSubclassOf")
    assert "CCBGScheduleOverlayDetachAfterDismissal(overlay)" in hide_controller

    assert "CCBGPresentationRecoveryNotificationName" in header
    assert "CCBGPostPresentationRecovery" in header
    assert "CCBGPresentationRecoveryNotificationName" in shared
    assert "void CCBGPostPresentationRecovery" in shared
    assert "CCBGPresentationRecoveryCallback" in module
    assert "CCBGPresentationRecoveryNotificationName" in module
    assert "recoveryPending" in utility
    did_transition = block(utility, "- (void)didTransitionToExpandedContentMode:", "- (BOOL)_canShowWhileLocked")
    assert "!expanded && self.recoveryPending" in did_transition
    assert "CCBGPostPresentationRecovery();" in did_transition

    print("Mounted module recovery path checks passed")


if __name__ == "__main__":
    main()
