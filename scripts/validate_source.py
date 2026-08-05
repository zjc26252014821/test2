from __future__ import annotations

import plistlib
import py_compile
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_SPECS = {
    "module1x2": (1, 2, "CleanCCBG1x2Module", 1),
    "module": (2, 2, "CleanCCBG2x2Module", 0),
    "module2x3": (2, 3, "CleanCCBG2x3Module", 2),
    "module3x2": (3, 2, "CleanCCBG3x2Module", 3),
    "module3x3": (3, 3, "CleanCCBG3x3Module", 4),
}


def main() -> None:
    control_bytes = (ROOT / "control").read_bytes()
    assert not control_bytes.startswith(b"\xef\xbb\xbf"), "control must not contain a UTF-8 BOM"
    for path in (
        ROOT / "module/Info.plist",
        ROOT / "prefs/Info.plist",
        ROOT / "prefs/entry.plist",
        ROOT / "prefs/Root.plist",
        ROOT / "app/Info.plist",
        ROOT / "app/AppEntitlements.plist",
        ROOT / "layout/Library/PreferenceLoader/Preferences/CleanCCBG2x2Prefs.plist",
        *(ROOT / directory / "Info.plist" for directory in MODULE_SPECS),
        ROOT / "utilitymodule/Info.plist",
        ROOT / "utilitytoggle/Info.plist",
        ROOT / "utilitytheme/Info.plist",
    ):
        plistlib.loads(path.read_bytes())
    module_info = plistlib.loads((ROOT / "module/Info.plist").read_bytes())
    app_info = plistlib.loads((ROOT / "app/Info.plist").read_bytes())
    for directory, (width, height, principal_class, slot) in MODULE_SPECS.items():
        info = plistlib.loads((ROOT / directory / "Info.plist").read_bytes())
        portrait = info["CCSModuleSize"]["Portrait"]
        assert (portrait["Width"], portrait["Height"]) == (width, height)
        assert info["NSPrincipalClass"] == principal_class
        assert info["CCSGetModuleSizeAtRuntime"] is True
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        assert info["MinimumOSVersion"] == "15.0"
        assert info["UIDeviceFamily"] == [1, 2]
        assert "CCSPreferencesRootListController" not in info
        assert info["CFBundleShortVersionString"] == "2.3.0"
        assert info["CFBundleVersion"] == "20300"
        makefile = (ROOT / directory / "Makefile").read_text(encoding="utf-8")
        if directory != "module":
            assert f"-DCCBG_MODULE_SLOT={slot}" in makefile
            assert f"-DCCBG_MODULE_CLASS={principal_class}" in makefile
        assert f"-DCCBG_DEFAULT_GRID_WIDTH={width}" in makefile
        assert f"-DCCBG_DEFAULT_GRID_HEIGHT={height}" in makefile
    assert app_info["CFBundleShortVersionString"] == "2.3.0"
    assert app_info["CFBundleVersion"] == "20300"
    utility_info = plistlib.loads((ROOT / "utilitymodule/Info.plist").read_bytes())
    assert utility_info["CFBundleShortVersionString"] == "2.3.0"
    assert utility_info["CFBundleVersion"] == "20300"
    assert utility_info["NSPrincipalClass"] == "CleanCCBGDefaultRestoreModule"
    assert utility_info["CCSModuleSize"]["Portrait"] == {"Width": 1, "Height": 1}
    assert utility_info["CCSGetModuleSizeAtRuntime"] is False
    master_switch_info = plistlib.loads((ROOT / "utilitytoggle/Info.plist").read_bytes())
    assert master_switch_info["CFBundleShortVersionString"] == "2.3.0"
    assert master_switch_info["CFBundleVersion"] == "20300"
    assert master_switch_info["NSPrincipalClass"] == "CleanCCBGMasterSwitchModule"
    assert master_switch_info["CCSModuleSize"]["Portrait"] == {"Width": 1, "Height": 1}
    assert master_switch_info["CCSGetModuleSizeAtRuntime"] is False
    theme_switcher_info = plistlib.loads((ROOT / "utilitytheme/Info.plist").read_bytes())
    assert theme_switcher_info["CFBundleShortVersionString"] == "2.3.0"
    assert theme_switcher_info["CFBundleVersion"] == "20300"
    assert theme_switcher_info["NSPrincipalClass"] == "CleanCCBGThemeSwitcherModule"
    assert theme_switcher_info["CCSModuleSize"]["Portrait"] == {"Width": 1, "Height": 1}
    assert theme_switcher_info["CCSGetModuleSizeAtRuntime"] is False
    assert app_info["LSApplicationQueriesSchemes"] == ["filza"]
    prefs = plistlib.loads((ROOT / "prefs/Root.plist").read_bytes())
    prefs_info = plistlib.loads((ROOT / "prefs/Info.plist").read_bytes())
    assert prefs_info["CFBundleShortVersionString"] == "2.3.0"
    assert prefs_info["CFBundleVersion"] == "20300"
    controls = [item for item in prefs["items"] if item.get("key")]
    assert len(controls) == 6
    assert all(item["defaults"] == "com.zjc.cleanccbg2x2" for item in controls)
    assert all(item["PostNotification"] == "com.zjc.cleanccbg2x2/reload" for item in controls)
    prefs_makefile = (ROOT / "prefs/Makefile").read_text(encoding="utf-8")
    assert "CleanCCBG2x2Prefs_RESOURCE_FILES = Info.plist Root.plist" in prefs_makefile
    module_makefile = (ROOT / "module/Makefile").read_text(encoding="utf-8")
    assert "CleanCCBG2x2_RESOURCE_FILES = Info.plist" in module_makefile
    assert "CoreImage QuartzCore ImageIO" in module_makefile
    utility_makefile = (ROOT / "utilitymodule/Makefile").read_text(encoding="utf-8")
    assert "CleanCCBGDefaultRestore_FILES" in utility_makefile
    master_switch_makefile = (ROOT / "utilitytoggle/Makefile").read_text(encoding="utf-8")
    assert "CleanCCBGMasterSwitch_FILES" in master_switch_makefile
    theme_switcher_makefile = (ROOT / "utilitytheme/Makefile").read_text(encoding="utf-8")
    assert "CleanCCBGThemeSwitcher_FILES" in theme_switcher_makefile
    layout_entry = plistlib.loads(
        (ROOT / "layout/Library/PreferenceLoader/Preferences/CleanCCBG2x2Prefs.plist").read_bytes()
    )
    assert layout_entry["entry"]["bundle"] == "CleanCCBG2x2Prefs"
    assert layout_entry["entry"]["detail"] == "CleanCCBG2x2PrefsListController"
    assert layout_entry["entry"]["isController"] is True
    module_source = (ROOT / "module/CleanCCBG2x2.m").read_text(encoding="utf-8")
    prefs_source = (ROOT / "prefs/CleanCCBG2x2PrefsListController.m").read_text(encoding="utf-8")
    for token in (
        "CFNotificationCenterAddObserver", "reloadPreferencesAndMedia",
        "AVPlayerLayer", "self.view.userInteractionEnabled = YES", "advanceBy:",
        "environmentDidChange:", "CCBGAutomationMediaName(items, [self isCharging], CCBG_MODULE_SLOT)",
        "handlingVideoBoundary", "videoCompositionWithAsset",
        "shouldBeginTransitionToExpandedContentModule", "preferredExpandedContentWidth",
        "preferredExpandedContentHeight", "setExpandedInteractionEnabled:", "manualAdvanceBy:",
        "favoritesOnly", "randomMediaIndexExcludingCurrent", "handleOpacityPan:",
        "updateCurrentOpacity:", "CCBG_MODULE_SLOT", "CCBGModulePreference",
        "cornerRadius = 18.0", "kCACornerCurveContinuous", "autoAdvance",
        "CCBGIsVideoName(self.currentItem[@\"fileName\"])", "repeats:NO",
        "CCBGMediaItemIsCurrentlyEligible", "scheduledPlaylists", "compoundRules",
        "noRepeatCount", "imageDuration", "videoPlayCount", "transitionStyle",
        "preloadNextMedia", "CCBGRecordMediaPlayback", "CCBGMarkMediaFailure",
        "privacyPauseVideo", "portraitContentMode", "moduleCornerRadius",
        "presentMediaSelectionList", "expandedWidth",
        "AVPlayerViewController", "updateNativePlayerPresentation", "showsPlaybackControls",
        "BOOL hasVideoPlayer", "BOOL useNativePlayer = hasVideoPlayer && self.expanded",
        "insertSubview:controller.view belowSubview:anchor",
        "CCBGExpandedSizeForNaturalSize", "updateAdaptiveExpandedSizeForItem",
        "loadValuesAsynchronouslyForKeys", "self.preferredContentSize = size",
        "applyModuleAppearance", "kCAMediaTimingFunctionEaseInEaseOut",
        "UITableViewDataSource", "playerLayer.masksToBounds = YES",
        "lastRuntimePersistAt", "now - self.lastRuntimePersistAt >= 10.0",
        "compactTap", "handleCompactTap:", "presentationHostController",
        "playbackQueueForItems:", "automationOverrideActive",
        "UISearchResultsUpdating", "visiblePickerItems", "pendingPickerThumbnailCallbacks",
        "CCBGThumbnailQueue", "CleanCCBG2x2/Thumbnails", "requestedTimeToleranceBefore",
        "scopeButtonTitles", "coverFrameTime",
        "static UIImage *CCBGThumbnailForItem", "CGImageSourceCreateThumbnailAtIndex",
        "hasLoadedPreferences", "suppressCurrentPersistence",
        "self.automationOverrideActive = overrideSelection.length > 0", "self.suppressCurrentPersistence = NO",
        "pendingManualAdvanceOffset", "commitPendingManualAdvance",
        "replaceCurrentItemWithPlayerItem:playerItem", "BOOL useNativePlayer",
        "self.playerLayer.hidden = !hasVideoPlayer || nativeControlsReady",
        "if (self.nativePlayerController.player != self.player)",
        "requiresMountedMediaReload", "resumeVideoPlaybackIfNeeded", "viewDidAppear:",
        "didScheduleFirstMountedReload", "reloadAfterFirstMountIfNeeded",
        "UIApplicationProtectedDataDidBecomeAvailable", "protectedDataDidBecomeAvailable:",
        "self.didScheduleFirstMountedReload = NO", "MountProbeView", "handleModuleWindowChange:",
    ):
        assert token in module_source, token
    assert "mediaLongPress" not in module_source
    assert "handleMediaLongPress:" not in module_source
    assert "- (void)controlCenterModuleDidReceiveTap { [self.controller handleControlCenterTap]; }" in module_source
    assert 'if (self.automationOverrideActive) return;' in module_source
    assert 'if (self.suppressCurrentPersistence) return;' in module_source
    assert 'self.playerLayer.hidden = NO;' in module_source
    assert 'self.visible = YES;' in module_source
    assert 'BOOL compactModuleIsMounted = self.view.window != nil;' in module_source
    assert 'NSString *baseSelection = mode == 0 && selectedMedia.length ? selectedMedia : rememberedCurrentMedia;' in module_source
    assert 'selection = overrideSelection.length ? overrideSelection : baseSelection;' in module_source
    assert "lastOverrideSelection" not in module_source
    reload_block = module_source.split("- (void)reloadPreferencesAndMedia", 1)[1].split("- (void)applyFallbackColor", 1)[0]
    assert 'CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", CCBG_MODULE_SLOT)' in module_source
    assert 'BOOL forcePreferenceMedia = [CCBGModulePreference(@"forcePreferenceMediaOnReload", @NO) boolValue];' in reload_block
    assert 'CCBGSetCachedModulePreference(@"forcePreferenceMediaOnReload", nil);' in reload_block
    assert 'if (!selection.length && mode != 0 && forcePreferenceMedia)' in reload_block
    assert 'NSString *preferredCurrentMedia = CCBGModulePreference(@"currentMedia", @"");' in reload_block
    assert reload_block.index("forcePreferenceMedia") < reload_block.index("CCBGMediaItemNamed(self.mediaItems, currentName)")
    assert '@"forced": @(forcePreferenceMedia)' in reload_block
    assert '@"preferenceCurrent": CCBGModulePreference(@"currentMedia", @"")' in reload_block
    assert 'CCBGPreferenceKeyForModule(@"selectedMedia", CCBG_MODULE_SLOT)' in module_source
    picker_selection = module_source.split("- (void)selectMediaNamed:(NSString *)fileName makeConstant:", 2)[2].split("- (void)reloadAfterFirstMountIfNeeded", 1)[0]
    assert 'CCBGPreferenceKeyForModule(@"currentMedia", CCBG_MODULE_SLOT)' in picker_selection
    assert 'CCBGPreferenceKeyForModule(@"selectedMedia", CCBG_MODULE_SLOT)' in picker_selection
    assert 'if (makeConstant)' in picker_selection
    assert 'self.visible = self.view.window != nil;' not in picker_selection
    assert 'self.visible = YES;' in picker_selection
    assert 'self.view.hidden = NO;' in picker_selection
    assert 'self.view.alpha = 1.0;' in picker_selection
    assert "playImmediatelyAtRate:" in module_source
    assert "prerollAtRate:" not in module_source
    assert "revealVideoWhenReadyForItem:" in module_source
    module_readiness = module_source.split("- (void)startVideoPlaybackWhenReadyForItem:", 1)[1].split("- (void)revealVideoWhenReadyForItem:", 1)[0]
    assert "playerItem.status == AVPlayerItemStatusFailed" in module_readiness
    assert "attempt >= 100" in module_readiness
    assert module_readiness.count("handleVideoPlaybackFailureForItem") >= 2
    assert "attempt < 10 ? 0.03 : 0.1" in module_readiness
    reveal_readiness = module_source.split("- (void)revealVideoWhenReadyForItem:", 1)[1].split("- (void)recoverPlayerLayerSurfaceIfNeededForItem:", 1)[0]
    assert "self.playerLayer.readyForDisplay" in reveal_readiness
    assert "self.imageView.hidden = YES;" in reveal_readiness
    assert "self.imageView.hidden = NO;" in reveal_readiness
    assert "current > start + 0.02" not in reveal_readiness
    assert "recoverPlayerLayerSurfaceIfNeededForItem:playerItem" in reveal_readiness
    video_transition = module_source.split("- (void)showCurrentMediaWithTransition:", 1)[1].split("- (void)preloadNextMedia", 1)[0]
    assert "UIImage *retainedCover = initialFrame ?: self.imageView.image ?: CCBGPlaceholderImageForItem(self.currentItem);" in video_transition
    assert "self.imageView.hidden = NO;" in video_transition
    assert "weakSelf.imageView.hidden = YES" not in video_transition
    assert "BOOL mediaDirectoryReadable = CCBGMediaDirectoryIsReadable();" in video_transition
    assert "if (!mediaDirectoryReadable)" in video_transition
    assert "privacyProtected" not in video_transition
    assert "if (!UIApplication.sharedApplication.protectedDataAvailable) {" not in video_transition
    native_presentation = module_source.split("- (void)updateNativePlayerPresentation", 2)[2].split("- (void)updateAdaptiveExpandedSizeForItem", 1)[0]
    assert "[self.view insertSubview:controller.view belowSubview:anchor];" in native_presentation
    assert "bringSubviewToFront:self.nativePlayerController.view" not in native_presentation
    assert "manualAdvanceTimer" not in module_source
    assert "timerWithTimeInterval:0.28" not in module_source
    assert "self.player = nil" not in module_source
    assert "self.playerLayer = nil" not in module_source
    assert "[AVPlayer playerWithPlayerItem:playerItem]" not in module_source
    assert "CCBGCurrentMediaNaturalSize" not in module_source
    manual_advance = module_source.split("- (void)manualAdvanceBy:", 2)[2].split("- (void)commitPendingManualAdvance", 1)[0]
    assert 'CCBGModulePreference(@"playbackMode", @0) integerValue] == 0' in manual_advance
    manual_commit = module_source.split("- (void)commitPendingManualAdvance", 2)[2].split("- (void)videoReachedBoundary", 1)[0]
    assert 'CCBGPreferenceKeyForModule(@"selectedMedia"' not in manual_commit
    remount_reload = module_source.split("- (void)reloadAfterFirstMountIfNeeded", 2)[2].split("- (void)resumeVideoPlaybackIfNeeded", 1)[0]
    assert "self.didScheduleFirstMountedReload = NO" in remount_reload
    assert "[self requiresMountedMediaReload]" in remount_reload
    assert "[self reloadPreferencesAndMedia];" in remount_reload
    assert "if (UIApplication.sharedApplication.protectedDataAvailable)" not in remount_reload
    mounted_state = module_source.split("- (BOOL)requiresMountedMediaReload", 2)[2].split("- (void)resumeVideoPlaybackIfNeeded", 1)[0]
    assert "!self.currentItem || !self.hasLoadedPreferences" in mounted_state
    assert "return NO;" in mounted_state
    view_did_appear = module_source.split("- (void)viewDidAppear:", 1)[1].split("- (void)viewDidDisappear:", 1)[0]
    assert "[self reloadAfterFirstMountIfNeeded]" in view_did_appear
    view_will_appear = module_source.split("- (void)viewWillAppear:", 1)[1].split("- (void)viewDidAppear:", 1)[0]
    assert "[self requiresMountedMediaReload] ||" in view_will_appear
    protected_data = module_source.split("- (void)protectedDataDidBecomeAvailable:", 2)[2].split("- (BOOL)requiresMountedMediaReload", 1)[0]
    assert "[self reloadAfterFirstMountIfNeeded]" in protected_data
    mount_probe = module_source.split("- (void)handleModuleWindowChange:", 2)[2].split("- (void)viewDidDisappear:", 1)[0]
    assert "if (!attached) return;" in mount_probe
    assert "NSUInteger generation = self.convergenceGeneration;" in mount_probe
    assert "generation != self.convergenceGeneration || !self.view.window" in mount_probe
    assert "generation != delayedWeakSelf.convergenceGeneration" in mount_probe
    assert "[self reloadAfterFirstMountIfNeeded]" in mount_probe
    assert "reload-no-media-directory" in module_source
    assert "if (!CCBGMediaDirectoryIsReadable())" in module_source
    for token in ("CCBGRuntimeModuleSize", "moduleSizeForOrientation:", "CFPreferencesCopyMultiple"):
        assert token in module_source, token
    assert "CCBGScheduleMountedControlCenterSizeRefresh" not in module_source
    assert module_source.count("[[UISwipeGestureRecognizer alloc]") == 2
    assert module_source.count("[[UIPanGestureRecognizer alloc]") == 2
    assert "self.opacityPan = [[UIPanGestureRecognizer alloc]" in module_source
    assert "self.resizePan = [[UIPanGestureRecognizer alloc]" in module_source
    assert "[self.resizeButton addGestureRecognizer:self.resizePan]" in module_source
    resize_pan = module_source.rsplit("- (void)handleResizePan:", 1)[1].split("- (BOOL)gestureRecognizer:", 1)[0]
    assert "CCBGWriteModulePreferences(@{ @\"gridWidth\": @(width), @\"gridHeight\": @(height) }, CCBG_MODULE_SLOT);" in resize_pan
    assert resize_pan.index("if (recognizer.state == UIGestureRecognizerStateEnded)") < resize_pan.index("CCBGWriteModulePreferences(@{ @\"gridWidth\": @(width), @\"gridHeight\": @(height) }")
    assert "translationInView:self.view.window ?: self.view" in resize_pan
    assert "CGRectGetWidth(self.resizeOriginalFrame)" in resize_pan
    assert "CGRectGetHeight(self.resizeOriginalFrame)" in resize_pan
    resize_layout_recovery = module_source.rsplit("- (void)scheduleResizeLayoutRecovery", 1)[1].split("- (void)showResizeFeedbackForWidth:", 1)[0]
    assert "CCBGRequestControlCenterSizeReload();" in resize_layout_recovery
    assert "self.view.frame =" not in resize_pan
    assert "- (void)applyLiveResizePreviewForWidth:(NSInteger)width height:(NSInteger)height" in module_source
    assert "[self applyLiveResizePreviewForTranslation:translation];" in resize_pan
    assert "[self applyLiveResizePreviewForWidth:width height:height];" not in resize_pan
    assert "- (void)clearLiveResizePreviewRestoringOriginalFrame:(BOOL)restoreOriginalFrame" in module_source
    assert "resizeCommitPending" not in module_source
    assert "[self clearLiveResizePreviewRestoringOriginalFrame:YES];" in module_source
    assert "self.view.frame = preview;" in module_source
    assert "- (void)requestControlCenterLayoutSizeUpdate" in module_source
    assert "requestLayoutSizeUpdate" in module_source
    assert "[source valueForKey:@\"module\"]" in module_source
    assert "[host setNeedsLayout];" in module_source
    assert "resizeSuppressedGestures" not in module_source
    assert "beginResizeGestureExclusivity" not in module_source
    assert "endResizeGestureExclusivity" not in module_source
    assert "if (gestureRecognizer == self.resizePan || otherGestureRecognizer == self.resizePan) return YES;" in module_source
    assert "self.controller.moduleOwner = self;" in module_source
    assert "reloadPreferencesAndMedia" not in resize_pan
    assert resize_pan.count("[self requestControlCenterLayoutSizeUpdate];") == 2
    size_reload_callback = module_source.rsplit("static void CCBGSizeReloadCallback(", 1)[1].split("static void CCBGPresentationRecoveryCallback(", 1)[0]
    assert "CCBGInvalidatePreferenceReadCache();" in size_reload_callback
    assert "[controller handleExternalGridSizeReload];" in size_reload_callback
    assert "dispatch_after(dispatch_time" in size_reload_callback
    assert "- (void)handleExternalGridSizeReload" in module_source
    external_grid_reload = module_source.rsplit("- (void)handleExternalGridSizeReload", 1)[1].split("- (void)requestControlCenterLayoutSizeUpdate", 1)[0]
    assert "observedGridWidth" in external_grid_reload
    assert "observedGridHeight" in external_grid_reload
    assert "resizeLayoutUpdateDeferred" in external_grid_reload
    assert "[self requestControlCenterLayoutSizeUpdate];" in external_grid_reload
    assert "reloadPreferencesAndMedia" not in external_grid_reload
    assert "if (self.expanded)" in external_grid_reload
    assert "self.resizeLayoutUpdateDeferred = YES;" in external_grid_reload
    transition = module_source.rsplit("- (void)didTransitionToExpandedContentMode:", 1)[1].split("- (void)handleExpandedSwipe:", 1)[0]
    assert "resizeLayoutUpdateDeferred" in transition
    assert "[self requestControlCenterLayoutSizeUpdate];" in transition
    will_transition = module_source.rsplit("- (void)willTransitionToExpandedContentMode:", 1)[1].split("- (void)didTransitionToExpandedContentMode:", 1)[0]
    assert "[self scheduleNativePlayerPresentationRecovery];" in will_transition
    assert "self.view.bounds.size.width) * 0.18" in resize_pan
    assert "self.view.bounds.size.height) * 0.18" in resize_pan
    assert "- (void)scheduleNativePlayerPresentationRecovery" in module_source
    native_recovery = module_source.rsplit("- (void)scheduleNativePlayerPresentationRecovery", 1)[1].split("- (void)updateNativePlayerPresentation", 1)[0]
    assert "updateNativePlayerPresentation" in native_recovery
    assert "self.expanded" in native_recovery
    assert "self.player.currentItem" in native_recovery
    assert "dispatch_after(dispatch_time" in native_recovery
    native_presentation = module_source.rsplit("- (void)updateNativePlayerPresentation", 1)[1].split("- (void)updateAdaptiveExpandedSizeForItem:", 1)[0]
    assert "superview != self.view" in native_presentation
    assert "insertSubview:self.nativePlayerController.view belowSubview:anchor" in native_presentation
    assert "insertSubview:controller.view belowSubview:anchor" in native_presentation
    view_did_load = module_source.rsplit("- (void)viewDidLoad", 1)[1].split("- (BOOL)applyPluginEnabledState", 1)[0]
    assert "self.nativePlayerController = [AVPlayerViewController new];" in view_did_load
    assert "[self addChildViewController:self.nativePlayerController];" in view_did_load
    native_reveal = module_source.rsplit("- (void)revealVideoWhenReadyForItem:", 1)[1].split("- (void)recoverPlayerLayerSurfaceIfNeededForItem:", 1)[0]
    assert "self.expanded && playerItem.status == AVPlayerItemStatusReadyToPlay" in native_reveal
    assert "self.nativePlayerController.player == self.player" in native_reveal
    assert "nativePresentation && playerItem.status == AVPlayerItemStatusReadyToPlay" not in native_reveal
    assert "[self updateNativePlayerPresentation];" in native_reveal
    assert "self.imageView.hidden = YES;" in native_reveal
    request_layout = module_source.rsplit("- (void)requestControlCenterLayoutSizeUpdate", 1)[1].split("- (void)applyLiveResizePreviewForWidth:", 1)[0]
    assert "for (NSUInteger depth = 0; host && depth < 8;" in request_layout
    assert "[host layoutIfNeeded];" in request_layout
    shared_source = (ROOT / "shared/CCBGMediaCatalog.m").read_text(encoding="utf-8")
    assert "CCBGSyncCCAsterGridSizeIfPresent" in shared_source
    assert "com.futur3sn0w.ccaster.preferences" in shared_source
    assert "ModuleGridSizes" in shared_source
    assert "com.futur3sn0w.ccaster/ReloadPrefs" in shared_source
    restore_snapshot = shared_source.rsplit("BOOL CCBGRestorePreferencesSnapshot", 1)[1].split("BOOL CCBGClearAllConfigurationPreservingMedia", 1)[0]
    assert "CCBGSyncCCAsterGridSizeIfPresent(values);" in restore_snapshot
    assert "CCBGReadCCAsterGridSize" in module_source
    assert "ModuleGridSizes" in module_source
    ccaster_read = module_source.rsplit("static BOOL CCBGReadCCAsterGridSize", 1)[1].split("static CCUILayoutSize CCBGRuntimeModuleSize", 1)[0]
    assert "CFPreferencesAppSynchronize(domain);" in ccaster_read
    assert "CCBGHasCachedCCAsterGridSizes" in ccaster_read
    size_reload_callback = module_source.rsplit("static void CCBGSizeReloadCallback(", 1)[1].split("static void CCBGPresentationRecoveryCallback(", 1)[0]
    assert "CCBGHasCachedCCAsterGridSizes = NO;" in size_reload_callback
    assert "- (void)scheduleResizeControlVisibilityRecovery" in module_source
    resize_visibility = module_source.rsplit("- (void)scheduleResizeControlVisibilityRecovery", 1)[1].split("- (void)handleResizePan:", 1)[0]
    assert "updateResizeControlVisibility" in resize_visibility
    assert "dispatch_after(dispatch_time" in resize_visibility
    layout = module_source.rsplit("- (void)viewDidLayoutSubviews", 1)[1].split("- (void)reloadAfterFirstMountIfNeeded", 1)[0]
    assert "dragStillActive" in layout
    assert "self.view.frame = self.resizePreviewFrame;" in layout
    assert 'CCBGReadPreference(@"fallbackColor"' not in module_source
    assert "scheduledTimerWithTimeInterval:10.0 repeats:YES" in module_source
    environment_signature = module_source.split("- (NSString *)currentEnvironmentSignature", 1)[1].split("- (void)environmentDidChange", 1)[0]
    assert "CCBGLoadMediaCatalog" not in environment_signature
    assert "UIViewPropertyAnimator" in module_source
    app_source = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "app").glob("*.m"))
    for token in (
        "UIDocumentPickerViewController", "UTTypeMovie", "CCBGWritePreference",
        "slideshowInterval", "UIApplicationMain", "CCBGMediaPickerController",
        "selectedMedia", "CCBGPreviewController", "scheduleEnabled",
        "darkModeAutomationEnabled", "weekdayAutomationEnabled",
        "lowPowerAutomationEnabled", "chargingAutomationEnabled",
        "NSJSONSerialization", "CCBGMediaStorageBytes", "favoritesOnly",
        "randomWeight", "exportDiagnosticReport", "resetCurrentItem",
        "PHPickerViewController", "importMediaFromPhotos", "CCBGFilzaURLForPath",
        "canEditRowAtIndexPath:", "editingStyleForRowAtIndexPath:",
        "CCBGActiveModuleSlot", "CCBGSystemModulesController", "CCBGAppearanceController",
        "CCBGApplyAppTheme", "mediaLibraryExpanded", "toggleMediaLibrary",
        "showMediaTools", "statusTimer", "当前命中素材",
        "CCBGLibraryInsightsController", "CCBGPlaylistController", "CCBGStatusDashboardController",
        "CCBGProfilesController", "CCBGAdaptationPreviewController", "CCBGModuleAppearanceController",
        "CCBGAdvancedAutomationController", "livePhotosFilter", "application.shortcutItems",
        "CGRectMake(0, 0, 1, 214)", "cover.image = thumbnail ?:",
        "CCBGDashboardModeSummary", "invalidMediaReferenceCount",
        "connectivityOverlayLastPresentation", "CCBGLoadThumbnailForItem",
        "CCBGAutomationPriorityController", "CCBGPlaceholderImageForItem",
        "CCBGThumbnailPendingCallbacks", "thumbnailCacheKeyForItem",
        "CCBGThumbnailCacheKeyForItem", "clearThumbnailCache",
        "rebuildThumbnailCache", "cleanInvalidReferences",
    ):
        assert token in app_source, token
    automation_source = (ROOT / "app/CCBGSettingsControllers.m").read_text(encoding="utf-8")
    generic_modules_source = (ROOT / "app/CCBGGenericSystemModulesController.m").read_text(encoding="utf-8")
    for token in (
        "CCBGGenericSystemModulesController", "customSystemOverlayModules",
        "CCBGAvailableGenericModules", "CCBGGenericOverlayPrefix",
        "initWithGenericModule:", "紧凑和展开素材",
    ):
        assert token in generic_modules_source, token
    for token in ("genericModule", "initWithGenericModule:", "self.genericModule ? self.genericModule[@\"prefix\"]", "StateOffMedia", "StateOnMedia"):
        assert token in automation_source, token
    automation_block = automation_source.split("@implementation CCBGAutomationController", 1)[1].split("@end", 1)[0]
    assert "CCBGReadModulePreference" in automation_block
    assert "CCBGWriteModulePreference" in automation_block
    assert not re.search(r"CCBG(?:Read|Write)Preference\(", automation_block)
    app_makefile = (ROOT / "app/Makefile").read_text(encoding="utf-8")
    for source in (
        "CCBGMainTabBarController.m", "CCBGQuickConfigController.m", "CCBGControls.m", "CCBGRootController.m", "CCBGMediaDetailController.m",
        "CCBGPreviewController.m", "CCBGSettingsControllers.m", "CCBGGenericSystemModulesController.m", "CCBGAdvancedControllers.m",
    ):
        assert source in app_makefile, source
    assert "AVFoundation QuartzCore PhotosUI Photos ImageIO" in app_makefile
    controls_source = (ROOT / "app/CCBGControls.m").read_text(encoding="utf-8")
    for token in (
        "UISearchResultsUpdating", 'placeholder = @"搜索共享素材"', "已停用，选择后启用",
        "continuous = YES", "valueLabelDoubleTapped:", "CleanCCBG2x2/Thumbnails",
        "CGImageSourceCreateThumbnailAtIndex", "UIImageJPEGRepresentation",
        "CCBGLoadThumbnailForItem", "CCBGThumbnailPendingCallbacks",
        "requestedTimeToleranceBefore", "CCBGGenerateVideoThumbnailAsync",
        "generateCGImagesAsynchronouslyForTimes", "CCBGActiveThumbnailGenerators",
        "finishOnce", "6.0 * NSEC_PER_SEC", "requestFinished",
        "__weak AVAssetImageGenerator *weakGenerator", "completionLock",
        "2.0 * NSEC_PER_SEC", "fallbackStarted", "startFallback",
        "QLThumbnailGenerationRequestRepresentationTypeLowQualityThumbnail",
        "CCBGThumbnailCachePathForItem", "needsSyncFallback",
    ):
        assert token in controls_source, token
    assert "NSString *CCBGActiveMediaPreferenceKey" in shared_source
    assert "NSString *CCBGActiveModuleMediaName" in shared_source
    assert "void CCBGSelectModuleMedia" in shared_source
    assert "void CCBGWriteModulePreferences" in shared_source
    assert "void CCBGReplaceAllPreferences" in shared_source
    assert "NSDictionary<NSString *, id> *CCBGReadAllPreferences" in shared_source
    assert "NSArray<NSString *> *CCBGModuleMediaReferenceKeys" in shared_source
    assert "NSArray<NSString *> *CCBGSystemMediaReferenceKeys" in shared_source
    module_selection = shared_source.split("void CCBGSelectModuleMedia", 1)[1].split("NSInteger CCBGActiveModuleSlot", 1)[0]
    assert '@"currentMedia": fileName' in module_selection
    assert 'values[@"selectedMedia"] = fileName;' in module_selection
    assert "CCBGWriteModulePreferences(values, slot);" in module_selection
    module_batch = shared_source.split("void CCBGWriteModulePreferences", 1)[1].split("NSString *CCBGActiveMediaPreferenceKey", 1)[0]
    assert "[values isKindOfClass:NSDictionary.class]" in module_batch
    assert "CCBGPreferenceKeyForModule(key, slot)" in module_batch
    assert "CCBGWritePreferences(scopedValues);" in module_batch
    preference_batch = shared_source.split("void CCBGWritePreferences", 1)[1].split("void CCBGReplaceAllPreferences", 1)[0]
    assert "[values isKindOfClass:NSDictionary.class]" in preference_batch
    automatic_backup = shared_source.split("static void CCBGCreateDebouncedAutomaticBackup", 1)[1].split("static NSSet<NSString *> *CCBGSupportedExtensions", 1)[0]
    assert "CCBGConfigurationPreferencesSnapshot()" in automatic_backup
    assert "CFPreferencesCopyMultiple" not in automatic_backup
    replace_preferences = shared_source.split("void CCBGReplaceAllPreferences", 1)[1].split("void CCBGPostReload", 1)[0]
    assert "CCBGRestorePreferencesSnapshot" in replace_preferences
    preference_transaction = shared_source.split("static BOOL CCBGReplacePreferencesAtomically", 1)[1].split("void CCBGWritePreference", 1)[0]
    for token in ("CFPreferencesCopyKeyList", "CFPreferencesSetMultiple", "isEqualToDictionary", "rollback"):
        assert token in preference_transaction
    assert "CCBGActiveModuleMediaName(slot)" in app_source
    assert 'CCBGReadModulePreference(@"currentMedia", slot, CCBGReadModulePreference(@"selectedMedia"' not in app_source
    assert 'updated[@"lastShortcutProfile"] = @(index);' in app_source
    assert "CFPreferencesSetAppValue(CFSTR(\"lastShortcutProfile\")" not in app_source
    assert "for (NSString *key in CCBGModuleMediaReferenceKeys())" in app_source
    assert "for (NSString *key in CCBGSystemMediaReferenceKeys())" in app_source
    for token in (
        "CCBGDefaultMediaItem", "mediaCatalog", "NSFileSize", "favorite", "randomWeight",
        "CCBGPreferenceKeyForModule", "CCBGMigrateLegacyAutomationPreferences",
        "CCBGCopyModuleConfiguration", "CCBGResetModuleConfiguration",
        "CCBGRemoveAllMediaConfigurations", "CCBGPruneMissingMediaConfigurations",
        "CCBGClearModuleLifecycleTrace",
        "lowPowerAutomationEnabled", "chargingAutomationEnabled",
        "CFPreferencesAppSynchronize",
        "validFrom", "playCount", "failureReason", "CCBGSHA256ForFileAtPath",
        "CCBGDominantColorHexForImageAtPath", "CCBGReplaceMediaReferences",
        "fileModifiedAt", "nameSet", "CGImageSourceCreateThumbnailAtIndex",
        "coverFrameTime", "connectivityOverlayCompactMedia", "musicOverlayExpandedMedia",
        "systemOverlayMediaMigrationVersion", "connectivityOverlayCompactMedia",
        "systemOverlayPlaybackMigrationVersion", "musicOverlayEnabled", "musicOverlayVideo",
    ):
        assert token in shared_source, token
    appearance_lookup = shared_source.split("BOOL CCBGSystemUsesDarkAppearance(void)", 1)[1].split("static NSString *CCBGNormalizedSceneText", 1)[0]
    assert "UIScreen" not in appearance_lookup
    assert 'CCBGReadModulePreference(@"scheduleEnabled", slot' in shared_source
    playback_block = shared_source.split("void CCBGRecordMediaPlayback", 1)[1].split("static void CCBGSetMediaFailure", 1)[0]
    assert playback_block.count("CFPreferencesAppSynchronize") == 1
    assert "CCBGModuleManagerController" in app_source
    for token in ("mediaOverrides", "CCBGMediaItemForModule", "CCBGSaveModuleMediaConfiguration", "moduleMediaConfigurationMigrationVersion"):
        assert token in shared_source, token
    default_item_block = shared_source.split("NSDictionary *CCBGDefaultMediaItem", 1)[1].split("NSArray<NSString *> *CCBGModuleMediaConfigurationKeys", 1)[0]
    for module_only_key in ("randomWeight", "playbackRate", "contentMode", "opacity", "focalX"):
        assert module_only_key not in default_item_block, module_only_key
    assert "CCBGMediaItemsForModule(catalog, CCBG_MODULE_SLOT)" in module_source
    assert 'CCBGPreferenceKeyForModule(@"moduleOpacity", CCBG_MODULE_SLOT)' in module_source
    assert 'CCBGPreferenceKeyForModule(@"moduleBlurIntensity", CCBG_MODULE_SLOT)' in module_source
    opacity_update = module_source.split("- (void)updateCurrentOpacity:", 2)[2].split("- (void)updateCurrentBlur:", 1)[0]
    assert "CCBGSaveModuleMediaConfiguration" not in opacity_update
    assert 'CFSTR("mediaCatalog")' not in module_source
    detail_source = (ROOT / "app/CCBGMediaDetailController.m").read_text(encoding="utf-8")
    assert "CCBGSaveModuleMediaConfiguration(self.item, self.moduleSlot)" in detail_source
    assert "catalog[index] = [self.item copy]" not in detail_source
    assert "无法删除素材" in detail_source
    assert "coverFrameTime" in detail_source
    root_source = (ROOT / "app/CCBGRootController.m").read_text(encoding="utf-8")
    root_preview = root_source.split("- (void)showPreview", 1)[1].split("- (void)rebuildCatalog", 1)[0]
    assert "CCBGActiveModuleMediaName(slot)" in root_preview
    assert 'CCBGReadModulePreference(@"selectedMedia"' not in root_preview
    settings_source = (ROOT / "app/CCBGSettingsControllers.m").read_text(encoding="utf-8")
    assert 'CCBGReadModulePreference(@"adaptiveExpandedSizeEnabled"' in app_source
    assert 'indexPath.section == 1 && indexPath.row >= 5' in app_source
    system_selection = settings_source.split("- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:", 1)[1].split("@implementation CCBGDiagnosticsController", 1)[0]
    assert "CCBGWritePreferences(changes)" in system_selection
    assert '[prefix stringByAppendingString:@"Enabled"]: @YES' in system_selection
    system_modules = settings_source.split("@implementation CCBGSystemModulesController", 1)[1].split("@implementation CCBGFiveModuleDefaultController", 1)[0]
    assert 'changes[[prefix stringByAppendingString:currentSuffix]] = fileName ?: @"";' not in system_modules
    assert 'currentKey: CCBGReadPreference(fixedKey, @"") ?: @""' not in system_modules
    assert "BOOL mediaRow" not in system_modules
    assert 'if (indexPath.row == 1) return compactMode != 0;' not in system_modules
    assert 'if (indexPath.row == 2) return expandedMode != 0;' not in system_modules
    for token in ("defaultGridForSlot:", "CCBGGridSizePickerCell", "gridFootprintSelected:", "showGridApplyInstructions", "自定义控制中心占格", "重新应用当前尺寸"):
        assert token in settings_source, token
    assert "CCBGRequestControlCenterSizeReload" in settings_source
    assert "注销 SpringBoard" not in settings_source
    for token in (
        '@"format": @4', "propertyList:preferences isValidForFormat:",
        "backupObject isKindOfClass:NSDictionary.class", "applyBackupPreferences:",
        "CCBGConfigurationPreferencesSnapshot()", "CCBGRestorePreferencesSnapshot",
        "CCBGRemoveAllMediaConfigurations", "部分素材删除失败",
        "CCBGClearAllConfigurationPreservingMedia", "素材文件会保留",
    ):
        assert token in settings_source, token
    assert "removeObjectsForKeys:CCBGModuleMediaConfigurationKeys()" in shared_source
    advanced_source = (ROOT / "app/CCBGAdvancedControllers.m").read_text(encoding="utf-8")
    assert "CCBGRestorePreferencesSnapshot(preferences, error)" in advanced_source
    assert "CCBGAllPreferences" not in advanced_source
    adaptation_preview = advanced_source.split("@implementation CCBGAdaptationPreviewController", 1)[1].split("@implementation CCBGProfilesController", 1)[0]
    assert "CCBGActiveModuleMediaName(CCBGActiveModuleSlot())" in adaptation_preview
    assert 'CCBGReadModulePreference(@"currentMedia"' not in adaptation_preview
    assert "CFPreferencesCopyMultiple" not in app_source
    assert '@"preferences": CCBGConfigurationPreferencesSnapshot()' in app_source
    for token in (
        "CCBGGroupedLibraryController", "collapsedMediaGroups", "duplicateGroups", "mergeDuplicates",
        "CCBGBatchEditController", "configurationProfiles", "CCBGCreateAutomaticBackup",
        "commitEditingStyle:(UITableViewCellEditingStyle)editingStyle", "无法删除备份",
        "exportIncludingMedia", "playbackHistory", "runtimePosition", "updateConflictHeader",
        "无模块引用", "五尺寸适配预览", "随机防重复", "完整配置模板",
        "CCBGInsightsAnalysisQueue", "sizeRankedItemsCache", "CCBGCollectMediaReferences",
        'CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"batch-")',
        'CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"playlist-")',
        'CCBGApplyThumbnailToCell(cell, media, CGSizeMake(44, 44), @"advanced-rule-")',
        "showProgressWithTitle", "fileSizesByName",
    ):
        assert token in advanced_source, token
    for token in (
        '@"FollowNetwork"', '@"WiFiMedia"', '@"CellularMedia"', '@"OfflineMedia"',
        '@"UseArtwork"', '@"CompactMedia"', '@"ExpandedMedia"',
        '@"CompactContentMode"', '@"ExpandedContentMode"',
        "systemAdaptiveContentMode", "背景模糊", "压暗强度",
        '@"musicOverlayCompactMedia"',
    ):
        assert token in settings_source, token
    for token in (
        "connectivityOverlayWiFiMedia", "connectivityOverlayCellularMedia",
        "connectivityOverlayOfflineMedia",
    ):
        assert token in shared_source, token
    preview_source = (ROOT / "app/CCBGPreviewController.m").read_text(encoding="utf-8")
    assert "AVPlayerViewController" in preview_source
    assert "showsPlaybackControls = YES" in preview_source
    assert "videoCompositionWithAsset" not in preview_source
    assert "CoreImage" not in preview_source
    for icon in ("AppIcon60x60@2x.png", "AppIcon60x60@3x.png"):
        data = (ROOT / "app" / icon).read_bytes()
        assert data.startswith(b"\x89PNG\r\n\x1a\n"), icon
    root_makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    assert "SUBPROJECTS += module module1x2 module2x3 module3x2 module3x3 utilitymodule utilitytoggle utilitytheme systemoverlay prefs app" in root_makefile
    workflow_source = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
    assert "python3 scripts/test_2_3_regressions.py" in workflow_source
    assert "make package FINALPACKAGE=1 2>&1 | tee packages/build-error.txt" in workflow_source
    assert "if: failure()" in workflow_source
    assert 'cp "$RUNNER_TEMP/build-error.txt" build-error.txt' in workflow_source
    overlay_source = (ROOT / "systemoverlay/CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
    overlay_placeholder = "static UIImage *CCBGPlaceholderImageForItem(NSDictionary *item)"
    assert overlay_placeholder in overlay_source
    assert overlay_source.index(overlay_placeholder) < overlay_source.index("- (void)reloadIfNeeded:")
    assert "NSNumber *legacyContentMode" in overlay_source
    assert "genericContentMode" in overlay_source
    assert 'CCBGOverlayKey(self.kind, @"ContentMode")' in overlay_source
    controls_source = (ROOT / "app/CCBGControls.m").read_text(encoding="utf-8")
    controls_header = (ROOT / "app/CCBGControls.h").read_text(encoding="utf-8")
    slider_configuration = controls_source.split(
        "- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(float)value",
        1,
    )[1].split("- (void)refreshValueLabel", 1)[0]
    assert "@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged" in slider_configuration
    assert "target action:action forControlEvents:UIControlEventValueChanged" not in slider_configuration
    assert "UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel" in slider_configuration
    assert "UIControlEventEditingDidEnd" in slider_configuration
    slider_value_changed = controls_source.split("- (void)sliderValueChanged:", 1)[1].split("- (void)refreshValueLabel", 1)[0]
    assert "[self refreshValueLabel]" in slider_value_changed
    assert "!sender.tracking" in slider_value_changed
    assert "sendActionsForControlEvents:UIControlEventEditingDidEnd" in slider_value_changed
    numeric_commit = controls_source.split("- (void)valueLabelDoubleTapped:", 1)[1].split("@end", 1)[0]
    assert numeric_commit.count("sendActionsForControlEvents:") == 1
    assert "sendActionsForControlEvents:UIControlEventTouchUpInside" in numeric_commit
    assert "valueCommittedHandler" not in controls_source
    assert "setValueCommittedHandler" not in controls_header
    for token in (
        "CCUIConnectivityModuleViewController", "MRUControlCenterViewController",
        "CCUIDisplayModuleViewController", "MRUVolumeViewController", "CCUIContinuousSliderView",
        "CCBGExpandedStateFromObject", '@"isExpanded"', '@"gaussianBlur"', '@"inputRadius"',
        "CCBGPrimarySliderView", "CCBGFindLargestSliderView", "BOOL sliderOverlay",
        "CCBGSystemOverlayView", "CCBGOverlayInsertionIndex", "player.muted = YES",
        "layoutHostView",
        "StateOffMedia", "StateOnMedia", "CCBGGenericStateMediaName",
        "handleGenericStateTap", "stateTap",
        "CCBGDetachOverlayViewNow",
        "genericLongPress", "recognizer.cancelsTouchesInView = recognizer == self.longPress && !genericModule",
        "CCBGGenericModuleExpandedDimension(genericModule",
        "interactionHostView = (genericModule || cleanTakeover) ? controller.view : hostView",
        "viewWillDisappear:", "[overlay removeFromSuperview]",
        "playImmediatelyAtRate:self.playbackRate",
        "_dyld_register_func_for_add_image", "CCBGAvailableOverlayItems",
        "systemUptime", "lastConfigurationCheck", "nw_path_monitor_create",
        "nw_path_uses_interface_type", "CCBGConnectivityStateWiFi", "CCBGArtworkInView",
        "UseArtwork", "FollowNetwork", "UIVisualEffectView", "ContentMode", "Blur", "Dim",
        "expandedPresentation", "CompactMedia", "ExpandedMedia",
        "CCBGOverlayPlaybackMode", "CCBGCurrentMediaKey", "CCBGFixedMediaKey",
        '@"Sequential"', '@"Random"',
        "CompactContentMode", "ExpandedContentMode",
        "CCBGControllerIsExpandedPresentation", "parentViewController",
        "CCUIConnectivityExpandedViewController", "MediaControlsPanelViewController",
        "CCBGRecordOverlayDiagnostic", "LastPresentation",
        "self.currentItem = item", "BOOL hasVisual", "return NO;",
        "CCBGControllerShouldOwnOverlay", "&& !item",
        "CCBGSelectedOverlayMediaName", "CCBGPlaceOverlay",
        "expandedThreshold", "presentationChanged",
        "useArtwork ? (void *)self.dynamicArtwork.CGImage : NULL",
        "toleranceBefore:kCMTimeZero", "playerLayer.masksToBounds = YES",
        "restoreSuppressedArtwork", "CCBGArtworkViewInView",
        "CCBGPrewarmOverlayMedia", "CCBGPreloadedOverlayAssets",
        "CCBGPreloadedOverlayFrames", "suppressedArtworkHidden",
        "CCBGFastOverlayItems", "CCBGPreloadedOverlayCatalog",
        "viewWillAppear:", "playbackGeneration", "readyForDisplay",
        "startPlaybackWhenReady", "schedulePlaybackReadinessCheck:",
        "AVPlayerItemPlaybackStalledNotification",
        "CCBGArmSystemOverlayCrashLoopGuard", "systemOverlayRapidLoadCount",
        "rapidLoadCount >= 3",
        "NSData *coverFrameData", "UIImage imageWithData:coverFrameData",
        "BOOL playbackAdvanced", "layerReady || playbackAdvanced",
        "CCBGOverlayHostView", "CCBGGenericModuleUsesCleanTakeover(kind)", "controller.view.subviews.count > 2",
        "return controller.view.subviews[2]",
        "musicOverlayPlaybackState", "timeControl=%ld",
        "resolved=%d", "reason=itemMissing",
        "reason=usingSystemArtwork",
        "CCBGShowOverlayWithPresentationArbitration", "candidate.expandedPresentation",
        "CCBGMigrateLegacyAutomationPreferences();",
        "CCBGOverlayMediaPickerController", "UISearchResultsUpdating",
        "CCBGInteractiveMediaKey", "installInteractionsOnHostView:",
        "handleOverlaySwipe:", "handleOverlayLongPress:", "advanceVideoBy:",
        "UISwipeGestureRecognizerDirectionLeft", "UISwipeGestureRecognizerDirectionRight",
        "UILongPressGestureRecognizer", "minimumPressDuration = 0.42",
        "CFPreferencesSetAppValue", "CFPreferencesAppSynchronize", "shouldReceiveTouch:",
        "[candidate isKindOfClass:UIControl.class]", "cancelsTouchesInView",
        "[overlay reloadIfNeeded:YES]",
        "CCBGPresentationKey", "expanded ? @\"Expanded\" : @\"Compact\"",
        "self.expandedPresentation, @\"Playlist\"",
        "CCBGOverlayPlaybackMode(self.kind, self.expandedPresentation)",
        "systemOverlayFavoriteMedia", "systemOverlayRecentMedia",
        "SwipeEnabled", "LongPressEnabled", "HapticsEnabled",
        "AutoSkipFailures", "AdaptiveExpandedFrame", "FailureCounts",
        "AVPlayerItemFailedToPlayToEndTimeNotification",
        "handledFailureGeneration", "recordRecentVideoName:",
        "applyAdaptiveFrameForHostView:", "naturalVideoSize",
        "CCBGLoadVideoOnlyAsset",
        "arc4random_uniform", "advanceAutomaticallyBy:1 random:NO",
        "gestureRecognizer == self.longPress", "gestureRecognizer == self.swipeLeft",
        "mediaContainerView", "self.mediaContainerView.frame = mediaFrame",
        "self.frame = hostView.bounds", "consecutiveFailureSkips >= 3",
        "automaticVideoItems", "clearFailure:(BOOL)clearFailure",
    ):
        assert token in overlay_source, token
    assert "CCBG_GENERIC_IDENTITY_LIMIT" in overlay_source
    generic_hook = overlay_source.split("static void CCBGHookGenericContainerClass", 1)[1].split("static CGFloat CCBGGenericModuleExpandedDimension", 1)[0]
    generic_layout = generic_hook.split("SEL appearSelector", 1)[0]
    generic_appearance = generic_hook.split("SEL appearSelector", 1)[1]
    assert "CCBGUpdateOrLayoutController(controller" in generic_layout
    for forbidden in ("CCBGUpdateKnownGenericContainerController", "CCBGUpdateGenericContainerController", "CCBGRecordGenericModuleMatch"):
        assert forbidden not in generic_layout
    assert "CCBGUpdateGenericContainerController(controller)" in generic_appearance
    assert "CCBGGenericModulesByKind[@(self.kind)]" in overlay_source
    assert "StateActive" in overlay_source
    assert "StateOnMedia" in overlay_source
    assert "StateOffMedia" in overlay_source
    assert "CCBGGenericActiveStateInObject" not in overlay_source
    assert "CCBGInstallGenericExpansionMethods" not in overlay_source
    assert "CCBGPrepareGenericExpansionObject" not in overlay_source
    overlay_layout_source = overlay_source.split("- (void)layoutSubviews", 1)[1].split("- (void)applyAdaptiveFrameForHostView:", 1)[0]
    assert "CCBGGenericModulesByKind[@(self.kind)] != nil" not in overlay_layout_source
    # Startup and media reloads must not ask CCSupport to recompute persisted
    # module sizes. Only an explicit grid-size edit may request that reload.
    assert "CCBGScheduleStartupControlCenterSizeReloads" not in overlay_source
    assert "CCBGRequestControlCenterSizeReload();" not in overlay_source
    music_classifier = overlay_source.split("static BOOL CCBGControllerIsExpandedPresentation", 1)[1].split("static CGFloat CCBGOverlayCornerRadius", 1)[0]
    for token in ("BOOL sawRuntimeState", "if (runtimeState == 1) return YES;", "if (sawRuntimeState) return NO;"):
        assert token in music_classifier, token
    assert 'if ([NSStringFromClass(candidate.class) isEqualToString:@"MRUControlCenterViewController"]) return NO;' not in music_classifier
    slider_classifier = music_classifier.split("if (kind == CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume)", 1)[1]
    for token in ("UIView *primarySlider", "CCBGExpandedStateFromObject(primarySlider)", "CCBGExpandedStateFromObject(controller)"):
        assert token in slider_classifier, token
    assert "if (sliderState >= 0) return sliderState == 1;" not in slider_classifier
    assert "if (sliderState == 1 || controllerState == 1) return YES;" in slider_classifier
    assert slider_classifier.index("if (size.width >= expandedThreshold") < slider_classifier.index("(sliderState == 0 || controllerState == 0)")
    assert "parentDepth < 3" in slider_classifier
    assert "CCBGExpandedStateFromObject(candidate) == 1" in slider_classifier
    assert "for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {\n            NSInteger runtimeState" not in slider_classifier
    selected_overlay = overlay_source.split("static NSString *CCBGSelectedOverlayMediaName", 1)[1].split("static NSArray<NSDictionary *> *CCBGAvailableOverlayItems", 1)[0]
    assert "CCBGSystemOverlayKindBrightness || kind == CCBGSystemOverlayKindVolume" in selected_overlay
    assert "return fixedName;" in selected_overlay
    overlay_reload = overlay_source.split("- (void)reloadIfNeeded:", 2)[2].split("- (void)videoEnded:", 1)[0]
    assert "legacyCurrentKey" in overlay_reload
    assert "CCBGFixedMediaKey(self.kind, self.expandedPresentation)" not in overlay_reload
    system_reload = overlay_source.split("static void CCBGSystemOverlayReload", 1)[1].split("static void CCBGStartNetworkMonitoring", 1)[0]
    assert "reloadAfterPreferenceChange" in system_reload
    assert "reloadIfNeeded:YES" not in system_reload
    prewarm_reload = overlay_source.split("static void CCBGPrewarmOverlayMedia", 1)[1].split("static void CCBGScheduleStartupOverlayRefreshes", 1)[0]
    assert "BOOL needsRecovery = overlay.window && !overlay.hidden && !overlay.player.currentItem;" in prewarm_reload
    assert "if (!needsRecovery) continue;" in prewarm_reload
    assert "[overlay reloadAfterPreferenceChange];" in prewarm_reload
    assert "reloadIfNeeded:YES" not in prewarm_reload
    assert "CFPreferencesSetValue" in overlay_source
    assert "kCFPreferencesCurrentUser, kCFPreferencesAnyHost" in overlay_source
    for token in ("sliderCompactFailureRepairVersion", "Compact%@CurrentMedia", "brightnessOverlay", "volumeOverlay"):
        assert token in shared_source, token
    failure_handler = overlay_source.split("- (void)handlePlaybackFailure", 2)[2].split("- (void)videoEnded:", 1)[0]
    preserved_selection_retry = failure_handler.split("if (preserveConfiguredSelection)", 1)[1].split('NSString *fileName = self.currentItem[@"fileName"]', 1)[0]
    for token in ("configuredSelectionFailureRetries", "reloadIfNeeded:YES", "setPlaybackVisible:YES", "return;"):
        assert token in preserved_selection_retry, token
    assert "advanceAutomaticallyBy" not in preserved_selection_retry
    assert "FailureCounts" not in preserved_selection_retry
    assert "catalog.firstObject" not in overlay_source
    assert "addObserver:self forKeyPath" not in overlay_source
    assert "removeObserver:self forKeyPath" not in overlay_source
    # Generic takeover overlays expose the same native AVPlayerViewController
    # transport surface as the five custom modules while expanded.
    assert "AVPlayerViewController" in overlay_source
    # Generic takeover overlays move to the Control Center canvas. AVKit must
    # receive a real, stable child-controller relationship with that canvas;
    # an unmanaged view or an intermediate wrapper leaves the transport
    # controls absent after the transition.
    assert "[host addChildViewController:controller]" not in overlay_source
    assert "[host addChildViewController:native]" in overlay_source
    assert "[native didMoveToParentViewController:host]" in overlay_source
    assert "CCBGViewHostController(self.superview) ?: self.hostController" in overlay_source
    assert "nativePlayerHostController" not in overlay_source
    assert "attachNativePlayerControllerToHost" in overlay_source
    assert "removeFromParentViewController" in overlay_source
    assert "[self.player replaceCurrentItemWithPlayerItem:playerItem]" in overlay_source
    assert "if (!self.playerLayer)" in overlay_source
    assert "self.playerLayer.frame = self.bounds;" not in overlay_source
    readiness_source = overlay_source.split("- (void)schedulePlaybackReadinessCheck:", 2)[2].split("- (void)playbackStalled:", 1)[0]
    assert "if (playbackAdvanced)" in readiness_source
    assert readiness_source.index("if (playbackAdvanced)") < readiness_source.index("[self recordRecentVideoName:")
    assert "attempt >= 120" in readiness_source
    startup_refresh = overlay_source.split("static void CCBGScheduleStartupOverlayRefreshes", 1)[1].split("static void CCBGFindArtwork", 1)[0]
    assert "@[@2.0]" in startup_refresh
    assert "@0.75" not in startup_refresh
    assert "@4.0" not in startup_refresh
    assert "@7.0" not in startup_refresh
    assert "CCBGPrewarmOverlayMedia();" in startup_refresh
    assert "CCBGScheduleStartupOverlayRefreshes();" in overlay_source
    assert "return rapidLoadCount >= 3" not in overlay_source
    assert "recognizer.cancelsTouchesInView = recognizer == self.longPress" in overlay_source
    assert "if (self.hidden) return NO;" in overlay_source
    assert 'return CCBGMediaKey(kind, expanded);' in overlay_source
    interactive_selection = overlay_source.split("- (void)applyInteractiveVideoName:", 1)[1].split("- (void)advanceVideoBy:", 1)[0]
    assert "CCBGWritePreferences" not in interactive_selection
    assert interactive_selection.count("CFPreferencesSetValue") >= 3
    assert "CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)" in interactive_selection
    assert "[self reloadIfNeeded:YES]" in interactive_selection
    automatic_advance = overlay_source.split("- (void)advanceAutomaticallyBy:", 2)[2].split("- (void)handleOverlaySwipe:", 1)[0]
    assert "applyInteractiveVideoName" not in automatic_advance
    assert "clearFailure:NO" in automatic_advance
    overlay_swipe = overlay_source.split("- (void)handleOverlaySwipe:", 1)[1].split("- (void)handleOverlayLongPress:", 1)[0]
    assert "[self playbackMode] == 0" in overlay_swipe
    prewarm_source = overlay_source.split("static void CCBGPrewarmOverlayMedia", 1)[1].split("static void CCBGFindArtwork", 1)[0]
    assert "CCBGAvailableOverlayItems" in prewarm_source
    assert "CCBGLoadVideoOnlyAsset" not in prewarm_source
    assert "AVAssetImageGenerator" not in prewarm_source
    assert "dispatch_group" not in prewarm_source
    assert "CCBGPrewarmLastCompletedAt > 0.0 && now - CCBGPrewarmLastCompletedAt < 20.0" in prewarm_source
    playback_visibility = overlay_source.split("- (void)setPlaybackVisible:(BOOL)visible", 2)[2].split("- (void)restoreSuppressedArtwork", 1)[0]
    assert "playImmediatelyAtRate:self.playbackRate" in playback_visibility
    assert "[self.player play]" not in overlay_source
    crash_guard = overlay_source.split("CCBGArmSystemOverlayCrashLoopGuard", 1)[1].split("static NSString *CCBGOverlayKey", 1)[0]
    assert "return NO;" in crash_guard
    presentation_detection = overlay_source.split("static BOOL CCBGControllerIsExpandedPresentation", 1)[1].split("static CGFloat CCBGOverlayCornerRadius", 1)[0]
    assert presentation_detection.index("MRUControlCenterViewController") < presentation_detection.index("expandedThreshold")
    assert presentation_detection.index("if ([compactClasses containsObject:") > presentation_detection.index("expandedThreshold")
    async_thumbnail = controls_source.split("static void CCBGGenerateVideoThumbnailAsync", 1)[1].split("UIImage *CCBGThumbnailForItem", 1)[0]
    assert "generateCGImagesAsynchronouslyForTimes" in async_thumbnail
    assert "copyCGImageAtTime" not in async_thumbnail
    thumbnail_loader = controls_source.split("void CCBGLoadThumbnailForItem", 1)[1]
    assert "if (needsSyncFallback) generateFallback();" in thumbnail_loader
    assert "CCBGScaleAndCacheThumbnail(image" in thumbnail_loader
    prewarm_source = overlay_source.split("static void CCBGPrewarmOverlayMedia", 1)[1].split("static void CCBGFindArtwork", 1)[0]
    assert "UIImage imageWithContentsOfFile" not in prewarm_source
    assert "UIImage imageWithCGImage" not in prewarm_source
    assert "UIImageJPEGRepresentation" not in prewarm_source
    tracked_refresh = overlay_source.rsplit("static void CCBGRefreshTrackedOverlayControllers", 1)[1].split("static void CCBGScheduleTrackedOverlayRefreshes", 1)[0]
    assert "!controller.isViewLoaded || !controller.view.window" in tracked_refresh
    tracked_schedule = overlay_source.rsplit("static void CCBGScheduleTrackedOverlayRefreshes", 1)[1].split("static void CCBGScheduleTrackedOverlayRefreshOnce", 1)[0]
    assert "@[@0.0, @0.35]" in tracked_schedule
    assert "@0.90" not in tracked_schedule
    assert 'UIPasteboard.generalPasteboard.string = state;' in app_source
    diagnostic_export = app_source.split("- (void)exportDiagnosticReport", 1)[1].split("- (void)exportBackup", 1)[0]
    assert "isValidJSONObject" in diagnostic_export
    assert "initForExportingURLs" in diagnostic_export
    assert "UIActivityViewController" not in diagnostic_export
    overlay_makefile = (ROOT / "systemoverlay/Makefile").read_text(encoding="utf-8")
    assert "AVKit" not in overlay_makefile
    assert "CCBGWritePreference(key, value)" not in overlay_source
    assert "bounds.size.width > 220.0" not in overlay_source
    assert "MIN(size.width, size.height) > 220.0" not in overlay_source
    for token in (
        "CCBGSystemOverlayPlaylistController", "当前播放列表", "视频素材库",
        "canMoveRowAtIndexPath:", "commitEditingStyle:",
        "CompactPlaylist", "ExpandedPlaylist",
        "CompactPlaybackMode", "ExpandedPlaybackMode",
        "轮播模式允许左右滑动", "允许长按选择", "切换触感反馈",
        "故障自动跳过", "展开框适应视频比例",
        "展开默认背景", "未选背景时使用实时封面",
    ):
        assert token in settings_source, token
    assert "固定、顺序、随机分别记住紧凑与展开状态" in settings_source
    assert "常显模式锁定所选背景并停用左右滑动" in app_source
    assert "setValueCommittedHandler:" not in settings_source
    assert "removeTarget:self action:@selector(opacityChanged:)" not in settings_source
    system_settings = settings_source.split("@implementation CCBGSystemModulesController", 1)[1].split("@implementation CCBGFiveModuleDefaultController", 1)[0]
    assert "CCBGPostReload();" not in system_settings
    for token in ("shouldHideRowAtIndexPath:", "compactMode != 0", "expandedMode != 0", "cell.hidden ="):
        assert token in system_settings, token
    assert "settingsSections" not in root_source
    for token in ("CCBGMainTabBarController", '@"总览"', '@"模块"', '@"素材"', '@"系统"', '@"快捷"', "CCBGModuleWorkspaceController", "CCBGQuickConfigController"):
        assert token in app_source, token
    assert "self.window.rootViewController = [CCBGMainTabBarController new]" in app_source
    assert "- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }" in system_modules
    assert '@[@"连接", @"音乐", @"亮度", @"音量"]' in system_modules
    assert "selectedSystemOverlayIndex" in system_modules
    defaults_block = shared_source.split("BOOL CCBGFiveModuleDefaultsReady", 1)[1].split("BOOL CCBGRestoreFiveModuleMedia", 1)[0]
    assert 'CCBGReadModulePreference(@"defaultOverrideMedia", slot' in defaults_block
    assert 'CCBGReadPreference(@"fiveModuleDefaultMedia"' not in defaults_block
    assert "BOOL ready = CCBGFiveModuleDefaultsReady();" in defaults_block
    assert 'CCBGRecordModuleLifecycleEvent(-1, @"defaults-apply-rejected"' in defaults_block
    assert 'CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)' in shared_source
    assert '@"defaultOverrideMedia"' in shared_source
    assert "playbackMode == 0" in app_source
    assert '@"%@%@%@CurrentMedia"' in shared_source
    assert '@[@"Sequential", @"Random"]' in shared_source
    assert "systemOverlayIndependentModeMigrationVersion" in shared_source
    for prefix in ("connectivityOverlay", "musicOverlay", "brightnessOverlay", "volumeOverlay"):
        for presentation in ("Compact", "Expanded"):
            for mode in ("Sequential", "Random"):
                assert f'@"{prefix}{presentation}{mode}CurrentMedia"' in shared_source
    assert 'stringByAppendingString:@"Video"' not in system_settings
    assert "回退素材播放视频" not in system_settings
    assert "五尺寸适配预览" not in root_source
    assert "五尺寸适配预览" not in detail_source
    for token in (
        "CCBGSystemOverlayKindBrightness", "CCBGSystemOverlayKindVolume",
        "CCUIBrightnessModuleViewController", "CCUIVolumeModuleViewController",
        '@"brightnessOverlay"', '@"volumeOverlay"',
    ):
        assert token in overlay_source, token
    for token in ("亮度模块背景", "音量模块背景", "CCBGFiveModuleDefaultController"):
        assert token in settings_source + root_source, token
    for token in (
        "UIModalPresentationPageSheet", "modalInPresentation = NO",
        "prefersGrabberVisible = YES", "presentationControllerDidDismiss:",
        "CCBGApplyFiveModuleDefaultMedia", "CCBGRestoreFiveModuleMedia",
    ):
        assert token in module_source + shared_source, token
    utility_source = (ROOT / "utilitymodule/CleanCCBGDefaultRestore.m").read_text(encoding="utf-8")
    for token in (
        "CleanCCBGDefaultRestoreModule", "UIStackView", "actionButtonWithTitle:",
        "应用默认", "恢复", "CCBGApplyFiveModuleDefaultMedia", "CCBGRestoreFiveModuleMedia",
    ):
        assert token in utility_source, token
    assert utility_source.count("- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }") == 2
    assert "- (CGFloat)preferredExpandedContentWidth { return 320.0; }" in utility_source
    assert "- (CGFloat)preferredExpandedContentHeight { return 230.0; }" in utility_source
    assert "performBatchAction:" in utility_source
    batch_action = utility_source.split("- (void)performBatchAction:", 1)[1].split("- (BOOL)shouldBeginTransitionToExpandedContentModule", 1)[0]
    assert "dispatch_after" not in batch_action
    assert "CCBGPostReload();" not in batch_action
    assert "defaults-apply-finished" in shared_source
    assert "defaults-restore-finished" in shared_source
    assert "rootViewController" not in utility_source
    assert "presentActions" not in utility_source
    assert "UIAlertController" not in utility_source
    assert "willTransitionToExpandedContentMode" in utility_source
    master_switch_source = (ROOT / "utilitytoggle/CleanCCBGMasterSwitch.m").read_text(encoding="utf-8")
    for token in (
        "CleanCCBGMasterSwitchModule", "controlCenterModuleDidReceiveTap", "CCBGPluginEnabled",
        "CCBGSetPluginEnabled", "power.circle.fill", "power.circle", '@"ON"', '@"OFF"',
    ):
        assert token in master_switch_source, token
    for token in ("CCBGPluginEnabled", "CCBGSetPluginEnabled", '@"pluginEnabled"'):
        assert token in shared_source, token
    for token in (
        "applyPluginEnabledState",
        "CCBGModuleGlobalPreference",
        "if (![self applyPluginEnabledState]) return;",
        'if ([CCBGModuleGlobalPreference(@"pluginEnabled", @YES) boolValue]) return YES;',
        "if (!self.visible) return;",
    ):
        assert token in module_source, token
    for token in (
        "if (!CCBGPluginEnabled())", "overlay.hidden = YES;", "BOOL pluginEnabled = CCBGPluginEnabled();",
        "CCBGDetachOverlayViewNow(overlay)",
        "CCBGOverlayPickerThumbnailForItem", "hostController.isViewLoaded && (hostController.view.window || hostController.view.superview)",
        "CCBGLoadVideoOnlyAsset", "self.player.volume = 0.0", "BOOL needsRecovery",
    ):
        assert token in overlay_source, token
    for token in ("prepareForImmediateDetach", "restoreVisualLayersForPlayback", "playerItem.audioMix"):
        assert token not in overlay_source, token
    assert "CCBGScheduleGenericContainerReconcile" not in overlay_source
    for token in (
        "CCBGScheduleGenericCompactRestore",
        "CCBGGenericOverlaySuppressUntilKey",
        "CCBGSuppressGenericOverlayForController",
        "CCBGGenericOverlaySuppressedForController",
    ):
        assert token not in overlay_source, token
    assert "CCBGGenericContainerShouldUseFallback" in overlay_source
    reload_block = overlay_source.split("static void CCBGSystemOverlayReload", 1)[1].split("static void CCBGStartNetworkMonitoring", 1)[0]
    assert "CCBGPrewarmOverlayMedia();" not in reload_block
    assert "overlay.hidden = NO;" not in reload_block
    assert "defaultActionButton" not in module_source
    for token in (
        "doubleTap", "tripleTap", "actionLongPress", "performConfiguredActionForGestureName:",
        '@"compact"', '@"expanded"', '@"SingleTap"', '@"DoubleTap"', '@"TripleTap"', '@"LongPress"',
        "requestExpandedPresentation", "impactOccurredWithIntensity:0.85",
        "moduleOpacity", "moduleBlurIntensity", "updateCurrentBlur:", "self.adjustingBlur",
        "CCBGLoadVideoOnlyAsset", "self.player.volume = 0.0",
        "playbackInstallGeneration", "self.playbackInstallGeneration++",
        "locationInView:self.view",
        "self.view.hidden = NO", "self.view.alpha = 1.0",
    ):
        assert token in module_source, token
    assert "CCBGSilentAudioMixForLoadedAsset" not in module_source
    assert "playerItem.audioMix" not in module_source
    video_only_loader = shared_source.split(
        "static NSCache<NSString *, AVAsset *> *CCBGVideoOnlyAssetCache", 1
    )[1].split("NSString *CCBGPathForItem", 1)[0]
    for token in (
        "AVMutableComposition", "tracksWithMediaType:AVMediaTypeVideo", "dispatch_get_main_queue()",
        "AVAssetExportSession", "AVAssetExportPresetPassthrough", "VideoOnlyCache",
        "AVURLAsset URLAssetWithURL:outputURL", "CCBGVideoOnlyExportQueue",
        "CCBGValidateVideoOnlyAsset", "CCBGRemoveVideoOnlyDiskCache",
    ):
        assert token in video_only_loader, token
    assert "tracksWithMediaType:AVMediaTypeAudio" not in video_only_loader
    assert "CCBGFinishVideoOnlyAssetLoad(cacheKey, composition" not in video_only_loader
    preview_playback = preview_source.split("- (void)loadMedia", 1)[1].split("- (void)videoEnded:", 1)[0]
    assert "CCBGLoadVideoOnlyAsset" in preview_playback
    assert "playerItemWithURL:[NSURL fileURLWithPath:path]" not in preview_playback
    selection_block = module_source.split("- (void)selectMediaNamed:(NSString *)fileName makeConstant:", 2)[2].split("- (BOOL)isCharging", 1)[0]
    assert "setExpandedInteractionEnabled:NO" not in selection_block
    display_block = module_source.split("- (void)applyDisplayForItem:", 1)[1].split("- (UIImage *)filteredImageAtPath:", 1)[0]
    assert 'CCBGModulePreference(@"moduleOpacity"' in display_block
    assert 'CCBGModulePreference(@"moduleBlurIntensity"' in display_block
    assert 'item[@"opacity"]' not in display_block
    for token in ("CCBGGestureSettingsController", "紧凑状态", "展开状态", "选素材", "上一项", "下一项", "slotScrollView", "overlayScrollView"):
        assert token in app_source, token
    for key in (
        "moduleOpacity", "moduleBlurIntensity", "compactSingleTapAction", "compactDoubleTapAction",
        "compactTripleTapAction", "compactLongPressAction", "expandedSingleTapAction",
        "expandedDoubleTapAction", "expandedTripleTapAction", "expandedLongPressAction",
    ):
        assert f'@"{key}"' in shared_source, key
    assert "mountReloadAttempts < 45" in module_source
    assert "mountReloadAttempts < 15" not in module_source
    assert "MIN(2.0, 0.25 * self.mountReloadAttempts)" in module_source
    for token in (
        "convergeMountedPresentation:",
        'presentation-converged',
        'convergeMountedPresentation:@"window-change"',
        'convergeMountedPresentation:@"window-change-delayed"',
        'convergeMountedPresentation:@"view-did-appear"',
        'convergeMountedPresentation:@"reload-notification"',
        'convergeMountedPresentation:@"reload-finished"',
        'convergeMountedPresentation:@"select-media"',
        "[self.view layoutIfNeeded]",
        "self.view.layer.hidden = NO",
        "self.view.layer.opacity = 1.0",
        '@"playerLayerReady": @(self.playerLayer.readyForDisplay)',
        '@"playerStatus": @(self.player.currentItem.status)',
        '@"playerTime": @(CMTimeGetSeconds(self.player.currentTime))',
        "player-layer-recovered",
        "video-layer-not-ready",
        "repairMountedPresentationHierarchyForFullRecovery:",
        "scheduleMountedPresentationConvergence:",
        "fiveModulePresentationRecoveryGeneration",
        "hierarchyRepairRequested",
        "video-stall-recovered",
        "startVideoWatchdogForItem:",
        "recoverVideoPlaybackStallForItem:",
    ):
        assert token in module_source, token
    assert "BOOL deferFileValidation = !CCBGMediaDirectoryIsReadable();" in module_source
    assert "self.imageView.image = self.imageView.image ?: CCBGPlaceholderImageForItem(self.currentItem);" in module_source
    assert "CCBGMediaDirectoryIsReadable" in shared_source
    assert "BOOL directoryUnavailable = !directoryReadable && stored.count > 0;" in shared_source
    assert "BOOL deferFileValidation = !CCBGMediaDirectoryIsReadable();" in module_source
    assert "if (!CCBGMediaDirectoryIsReadable()) return YES;" in module_source
    assert "if (!queue.count && previousItem)" in module_source
    assert "[self.controller loadViewIfNeeded]" not in module_source
    for token in ("CCBGRecordModuleLifecycleEvent", "content-controller", "reload-finished"):
        assert token in module_source, token
    module_init = module_source.rsplit("- (instancetype)init", 1)[1].split("- (UIViewController *)contentViewController", 1)[0]
    assert "CCBGRecordModuleLifecycleEvent" not in module_init
    assert "CCBGReadModuleLifecycleTrace" in app_source
    mounted_reload = module_source.rsplit("- (BOOL)requiresMountedMediaReload", 1)[1].split("- (void)resumeVideoPlaybackIfNeeded", 1)[0]
    assert "self.player.currentItem" not in mounted_reload
    for token in (
        "CCBGRefreshModulePreferenceSnapshot", "CFPreferencesCopyMultiple", "lastPreferencesReloadAt",
        "scheduledTimerWithTimeInterval:10.0", "self.environmentTimer.tolerance = 2.0",
        "QOS_CLASS_UTILITY",
        "if (!self.expanded || ![CCBGModulePreference(@\"preloadEnabled\"",
    ):
        assert token in module_source, token
    assert "@synchronized (NSProcessInfo.processInfo)" not in module_source
    assert "@synchronized (NSProcessInfo.processInfo)" not in overlay_source
    assert "scheduledTimerWithTimeInterval:2.0" not in module_source
    for token in ("CCBGPresentationItemsEqual", "NSDictionary *previousItem = self.currentItem", "if (CCBGPresentationItemsEqual(previousItem, self.currentItem)", "BOOL needsMediaReload = [self requiresMountedMediaReload];", "if (!needsMediaReload)", "reloadScheduled", "@synchronized (controller)"):
        assert token in module_source, token
    for token in ("gestureHostView", "installGestureHostIfNeeded", "self.swipeLeft.delegate = self", "self.opacityPan.cancelsTouchesInView = NO", "if (ours || otherIsOurs) return YES;", "CCBGTouchIsNativeTransportControl", "CGRectContainsPoint(self.view.bounds, point)"):
        assert token in module_source, token
    for token in ("handleControlCenterTap", "controlCenterTapGeneration", "lastProtocolTapAt", "applyBlurIntensity", "CCBGApplyGaussianBlurToLayer"):
        assert token in module_source, token
    gesture_touch_block = module_source.split("shouldReceiveTouch:(UITouch *)touch", 1)[1].split("- (void)installGestureHostIfNeeded", 1)[0]
    assert "isKindOfClass:UIControl.class" not in gesture_touch_block
    for token in ("CCBGSharedSliderOverlayKind", "CCUIContinuousSliderViewController", "CCUIAudioModuleViewController", "AudioModule", "Brightness"):
        assert token in overlay_source, token
    for token in (
        "customSystemOverlayModules", "CCBGHookGenericContainerClass",
        "CCBGGenericModuleForContainerController", "CCUIContentModuleContainerViewController",
        "CCBGGenericModulesByKind", "CCBGHookConfiguredModuleClass",
        "CCBGCollectGenericObjectIdentity", "contentModule",
        "LastRuntimeMatch", "sliderOverlay = self.kind",
        "StateOffMedia", "StateOnMedia",
    ):
        assert token in overlay_source, token
    for token in ("CCBGClassIsSubclassOf", "class_getSuperclass", "CCBGOverlayDiscoveryPasses >= 4", "CCBGScheduleBrightnessVolumeDiscovery", "dladdr", "objc_getClassList", "free(classes)"):
        assert token in overlay_source, token
    for token in ("CCBGSliderKindFromText", "CCBGSliderKindInView", "accessibilityIdentifier", "accessibilityLabel", "CCBGApplyGaussianBlurToLayer", "CCBGHookControllerClass(cls, 0)"):
        assert token in overlay_source, token
    assert "[cls isSubclassOfClass:UIViewController.class]" not in overlay_source
    assert "videoScrubber" not in module_source
    assert "handleVideoScrub:" not in module_source
    for old_text in (
        "Play temporarily", "Set as constant",
        "Automation or privacy is currently overriding playback",
        "Media previews are generated and cached locally",
        "Automation Priority", "Organized as Playback",
        "Rebuild preview cache", "Clean invalid references", "Invalid references",
        "Connectivity view", "Music view", "Cover frame time",
    ):
        assert old_text not in app_source + module_source, old_text
    overlay_makefile = (ROOT / "systemoverlay/Makefile").read_text(encoding="utf-8")
    assert "UIKit AVFoundation QuartzCore Network ImageIO" in overlay_makefile
    overlay_filter = plistlib.loads((ROOT / "systemoverlay/CleanCCBGSystemOverlays.plist").read_bytes())
    assert overlay_filter["Filter"]["Bundles"] == ["com.apple.springboard"]
    for token in (
        "CFPreferencesSetAppValue", "CFPreferencesAppSynchronize",
        "CFPreferencesCopyAppValue", "CFNotificationCenterPostNotification",
        "UIDocumentPickerViewController",
    ):
        assert token in prefs_source, token
    for script in (ROOT / "scripts").glob("*.py"):
        py_compile.compile(str(script), doraise=True)
    print("Source validation passed: plists, preferences, live reload, media, scripts")


if __name__ == "__main__":
    main()
