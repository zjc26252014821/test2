from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED_H = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
PREVIEW = (ROOT / "app" / "CCBGPreviewController.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")
CONTROLS = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")
ROOT_CONTROLLER = (ROOT / "app" / "CCBGRootController.m").read_text(encoding="utf-8")
ADVANCED = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
TIMELINE = (ROOT / "app" / "CCBGBackupTimelineController.m").read_text(encoding="utf-8")


def body(source: str, start: str, end: str) -> str:
    assert start in source, start
    part = source.split(start, 1)[1]
    assert end in part, end
    return part.split(end, 1)[0]


def implementation_body(source: str, start: str, end: str) -> str:
    assert start in source, start
    part = source.rsplit(start, 1)[1]
    assert end in part, end
    return part.split(end, 1)[0]


# Grid size writes must invalidate the module-side cache before asking
# CCSupport to query moduleSizeForOrientation again.
for token in (
    "CCBGSizeReloadNotificationName",
    "CCBGRequestControlCenterSizeReload",
    "com.opa334.ccsupport/ReloadSizes",
):
    assert token in SHARED_H + SHARED
assert "CCBGSizeReloadCallback" in MODULE
assert "CCBGHasCachedRuntimeGridSize = NO" in MODULE
assert "CCBGSizeReloadNotificationName" in MODULE
runtime_size = body(MODULE, "static CCUILayoutSize CCBGRuntimeModuleSize", "static BOOL CCBGCurrentInterfaceIsLandscape")
assert "CFPreferencesCopyMultiple" in runtime_size
assert "persistentDomainForName" not in runtime_size


# Cross-process configuration writes and full restore are one locked,
# validated transaction rather than a merge followed by several reloads.
for token in (
    "CCBGPreferencesMutationLockPath",
    "CFPreferencesSetMultiple",
    "CCBGRestorePreferencesSnapshot",
    "CCBGConfigurationPreferencesSnapshot",
):
    assert token in SHARED_H + SHARED
restore = body(
    SHARED,
    "BOOL CCBGRestorePreferencesSnapshot",
    "void CCBGPostReload",
)
for token in ("rollback", "CCBGReadAllPreferences", "CCBGReplacePreferencesAtomically"):
    assert token in restore
transaction = body(
    SHARED,
    "static BOOL CCBGReplacePreferencesAtomically",
    "void CCBGWritePreference",
)
for token in ("rollback", "CFPreferencesSetMultiple", "isEqualToDictionary"):
    assert token in transaction
assert "CCBGRestorePreferencesSnapshot" in ADVANCED
assert "CCBGRestorePreferencesSnapshot" in TIMELINE
assert "CCBGRestorePreferencesSnapshot" in SETTINGS
copy_config = body(SHARED, "void CCBGCopyModuleConfiguration", "void CCBGResetModuleConfiguration")
reset_config = body(SHARED, "void CCBGResetModuleConfiguration", "void CCBGMigrateLegacyAutomationPreferences")
for transaction_path in (copy_config, reset_config):
    assert "CCBGWritePreferences" in transaction_path
    assert "CFPreferencesSetAppValue" not in transaction_path


# Settings export must serialize and write away from the main thread.
export = body(SETTINGS, "- (void)exportBackup", "- (void)importBackup")
assert "CCBGSettingsBackupQueue" in export
assert "dispatch_async" in export
assert export.index("dispatch_async") < export.index("dataWithJSONObject")


# A video that repeatedly fails to advance must be quarantined and all
# modules must reload onto healthy media instead of seeking forever.
for token in (
    "handleVideoPlaybackFailureForItem",
    "videoStallRecoveryCount",
    "rebuildVideoAfterExtendedSuspensionIfNeeded",
    "CCBGInvalidateVideoOnlyAssetMemoryCache",
    "CCBGMarkMediaFailure",
    "AVPlayerItemStatusFailed",
):
    assert token in MODULE + SHARED + SHARED_H
stall = body(
    MODULE,
    "- (void)recoverVideoPlaybackStallForItem:",
    "- (void)showCurrentMediaWithTransition:",
)
assert "videoStallRecoveryCount" in stall
assert "CCBGInvalidateVideoOnlyAssetMemoryCache" in stall
assert "视频连续无播放进度，已自动隔离" not in stall
assert "CCBGPostReload" in SHARED.split("void CCBGMarkMediaFailure", 1)[1]
assert "systemUptime - suspendedAt < 300.0" in MODULE
assert "now - self.lastVideoStallRecoveryAt >= 1.0" in MODULE
assert 'CCBGAnalyticsMutationLockPath = @"/var/mobile/Library/Preferences/com.zjc.cleanccbg2x2.analytics.lock"' in SHARED
analytics_lock = body(
    SHARED,
    "static void CCBGWithAnalyticsMutationLock",
    "static void CCBGEnqueueAnalyticsMutation",
)
assert "CCBGAnalyticsMutationLockPath" in analytics_lock
assert "CCBGPreferencesMutationLockPath" not in analytics_lock
clear_configuration = SHARED.split("BOOL CCBGClearAllConfigurationPreservingMedia", 1)[1].split(
    "void CCBGPostReload", 1
)[0]
assert "preferences.lock" not in clear_configuration
assert "analytics.lock" not in clear_configuration
assert "module-lifecycle.lock" not in clear_configuration
failure_handler = MODULE.split("- (void)handleVideoPlaybackFailureForItem:", 2)[-1].split(
    "- (void)showCurrentMediaWithTransition:", 1
)[0]
assert failure_handler.index("videoFailureRebuildCount == 0") < failure_handler.index("CCBGMarkMediaFailure")
video_install = MODULE.split("CCBGLoadVideoOnlyAsset(path", 1)[1].split("[self.player replaceCurrentItemWithPlayerItem", 1)[0]
assert "recordSuccessfulMediaStartIfNeeded" not in video_install



# Lifecycle diagnostics can carry a hierarchy snapshot. Serialize that detail
# on the existing utility queue so a Control Center layout pass never pays for
# an NSDictionary description on the main thread.
lifecycle_trace = body(
    SHARED,
    "void CCBGRecordModuleLifecycleEvent",
    "NSArray<NSString *> *CCBGReadModuleLifecycleTrace",
)
assert "NSDictionary *capturedDetails = [details copy] ?: @{};" in lifecycle_trace
assert lifecycle_trace.index("dispatch_async") < lifecycle_trace.index("NSString *detail")


# actionAtItemEnd belongs to AVPlayer, not AVPlayerItem. Keeping this contract
# catches a compiler-breaking preview loop regression before cloud builds.
assert "self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;" in PREVIEW
assert "playerItem.actionAtItemEnd" not in PREVIEW


# Mounted recovery must rebuild only a detached player surface without
# repeatedly reloading the full preferences/catalog transaction.
mounted_reload = implementation_body(
    MODULE,
    "- (void)reloadAfterFirstMountIfNeeded",
    "- (void)protectedDataDidBecomeAvailable:",
)
assert "BOOL needsMediaReload" in mounted_reload
assert "mounted-layer-recovery" in mounted_reload
assert mounted_reload.index("if (needsMediaReload)") < mounted_reload.index("[self reloadPreferencesAndMedia]")
layer_recovery = implementation_body(
    MODULE,
    "- (void)recoverPlayerLayerSurfaceIfNeededForItem:",
    "- (void)startVideoWatchdogForItem:",
)
assert "layerAttached" in layer_recovery
assert "self.playerLayer.superlayer == self.view.layer" in layer_recovery


# Delayed presentation probes are recovery-only. Once a mounted module is
# already visible, attached, and loaded, they must not repeat layout and
# playback work on the main thread.
scheduled_convergence = implementation_body(
    MODULE,
    "- (void)scheduleMountedPresentationConvergence:",
    "- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot",
)
assert "BOOL needsRecovery" in scheduled_convergence
assert "if (!needsRecovery) return;" in scheduled_convergence



# Layout passes repeatedly apply the current appearance. Resetting an already
# empty visual-effect view is unnecessary compositor work, while layer blur
# validation must remain in place for external layer changes.
layout = implementation_body(
    MODULE,
    "- (void)viewDidLayoutSubviews",
    "- (void)reloadAfterFirstMountIfNeeded",
)
assert "BOOL contentFrameChanged" in layout
assert "if (contentFrameChanged)" in layout
assert layout.index("if (contentFrameChanged)") < layout.index("[self installGestureHostIfNeeded]")
assert "[self updateNativePlayerPresentation]" in layout
assert "[self reloadAfterFirstMountIfNeeded]" in layout
assert "[self resumeVideoPlaybackIfNeeded]" in layout


# Layout should only rewrite video geometry when the effective frame changes.
# Repeated Control Center layout passes otherwise force needless compositor
# work and can make active video appear to hitch.
assert "hasLaidOutContentFrame" in MODULE
assert "lastLaidOutContentFrame" in MODULE


blur_application = implementation_body(
    MODULE,
    "- (void)applyBlurIntensity:",
    "- (void)updateNativePlayerPresentation",
)
assert "if (self.blurView.effect || self.blurView.alpha > 0.001)" in blur_application
assert blur_application.count("CCBGApplyGaussianBlurToLayer") == 3



# Static module appearance should not rewrite layer properties on every layout.
# Dynamic palette modes intentionally bypass the cache so their live colors stay
# responsive to foreground and wallpaper changes.
appearance_application = implementation_body(
    MODULE,
    "- (void)applyModuleAppearance",
    "- (void)presentMediaSelectionList",
)
assert "lastStaticAppearanceSignature" in MODULE
assert "if (!foregroundTint && !wallpaperTint)" in appearance_application
assert "self.lastStaticAppearanceSignature = nil;" in appearance_application


# The five-module size editor writes width and height together, then lets the
# shared preferences path issue exactly one CCSupport size reload. Separate
# writes create a visible intermediate module size and double the relayout cost.
grid_selection = body(
    SETTINGS,
    "- (void)gridFootprintSelected:",
    "- (void)showGridApplyInstructions",
)
assert "CCBGWriteModulePreferences(@{ @\"gridWidth\": @(width), @\"gridHeight\": @(height) }" in grid_selection
assert "CCBGWriteModulePreference(@" not in grid_selection
assert "CCBGGridSizePickerCell" in SETTINGS
assert "gridSizeChanged:" not in SETTINGS


# The Control Center-side size handle is opt-in and compact-only. Its preview
# stays local while the finger moves; the durable grid update happens once at
# the end of the gesture so a CCSupport reflow cannot cancel the active pan.
assert 'controlCenterResizeEnabled' in SHARED + SETTINGS + MODULE
assert 'UIPanGestureRecognizer *resizePan' in MODULE
assert 'handleResizePan:' in MODULE
assert 'showResizeEditor' not in MODULE
resize_pan = implementation_body(
    MODULE,
    '- (void)handleResizePan:',
    '- (BOOL)gestureRecognizer:',
)
assert 'if (self.expanded || CCBGIsCCAsterEditModeActive(self.view) || ![CCBGModulePreference(@"controlCenterResizeEnabled", @NO) boolValue]) return;' in resize_pan
assert 'CCBGWriteModulePreferences(@{ @"gridWidth": @(width), @"gridHeight": @(height) }, CCBG_MODULE_SLOT);' in resize_pan
assert resize_pan.index('if (recognizer.state == UIGestureRecognizerStateEnded)') < resize_pan.index('CCBGWriteModulePreferences(@{ @"gridWidth": @(width), @"gridHeight": @(height) }')
assert 'translationInView:self.view.window ?: self.view' in resize_pan
assert 'CGRectGetWidth(self.resizeOriginalFrame)' in resize_pan
assert 'CGRectGetHeight(self.resizeOriginalFrame)' in resize_pan
assert 'self.view.frame =' not in resize_pan
assert '- (void)applyLiveResizePreviewForWidth:(NSInteger)width height:(NSInteger)height' in MODULE
assert '[self applyLiveResizePreviewForTranslation:translation];' in resize_pan
assert '[self applyLiveResizePreviewForWidth:width height:height];' not in resize_pan
assert '- (void)clearLiveResizePreviewRestoringOriginalFrame:(BOOL)restoreOriginalFrame' in MODULE
assert 'resizeCommitPending' not in MODULE
assert '[self clearLiveResizePreviewRestoringOriginalFrame:YES];' in MODULE
assert 'self.view.frame = preview;' in MODULE
assert '- (void)requestControlCenterLayoutSizeUpdate' in MODULE
assert 'requestLayoutSizeUpdate' in MODULE
assert '[source valueForKey:@"module"]' in MODULE
assert '[host setNeedsLayout];' in MODULE
assert 'resizeSuppressedGestures' not in MODULE
assert 'beginResizeGestureExclusivity' not in MODULE
assert 'endResizeGestureExclusivity' not in MODULE
assert 'if (gestureRecognizer == self.resizePan || otherGestureRecognizer == self.resizePan) return YES;' in MODULE
assert 'self.controller.moduleOwner = self;' in MODULE
assert 'reloadPreferencesAndMedia' not in resize_pan
assert 'stopPlayback' not in resize_pan
assert 'actionLongPress' not in resize_pan
assert resize_pan.count('[self requestControlCenterLayoutSizeUpdate];') == 2
size_reload_callback = implementation_body(MODULE, 'static void CCBGSizeReloadCallback(', 'static void CCBGPresentationRecoveryCallback(')
assert 'CCBGInvalidatePreferenceReadCache();' in size_reload_callback
assert '[controller handleExternalGridSizeReload];' in size_reload_callback
assert 'dispatch_after(dispatch_time' in size_reload_callback
assert '- (void)handleExternalGridSizeReload' in MODULE
external_grid_reload = implementation_body(MODULE, '- (void)handleExternalGridSizeReload', '- (void)requestControlCenterLayoutSizeUpdate')
assert 'observedGridWidth' in external_grid_reload
assert 'observedGridHeight' in external_grid_reload
assert 'resizeLayoutUpdateDeferred' in external_grid_reload
assert '[self requestControlCenterLayoutSizeUpdate];' in external_grid_reload
assert 'reloadPreferencesAndMedia' not in external_grid_reload
assert 'if (self.expanded)' in external_grid_reload
assert 'self.resizeLayoutUpdateDeferred = YES;' in external_grid_reload
transition = implementation_body(MODULE, '- (void)didTransitionToExpandedContentMode:', '- (void)handleExpandedSwipe:')
assert 'resizeLayoutUpdateDeferred' in transition
assert '[self requestControlCenterLayoutSizeUpdate];' in transition
will_transition = implementation_body(MODULE, '- (void)willTransitionToExpandedContentMode:', '- (void)didTransitionToExpandedContentMode:')
assert '[self scheduleNativePlayerPresentationRecovery];' in will_transition
assert 'self.view.bounds.size.width) * 0.18' in resize_pan
assert 'self.view.bounds.size.height) * 0.18' in resize_pan
assert 'self.view.layoutIfNeeded' not in resize_pan
assert '- (void)scheduleNativePlayerPresentationRecovery' in MODULE
native_recovery = implementation_body(MODULE, '- (void)scheduleNativePlayerPresentationRecovery', '- (void)updateNativePlayerPresentation')
assert 'updateNativePlayerPresentation' in native_recovery
assert 'self.expanded' in native_recovery
assert 'self.player.currentItem' in native_recovery
assert 'dispatch_after(dispatch_time' in native_recovery
native_presentation = implementation_body(MODULE, '- (void)updateNativePlayerPresentation', '- (void)updateAdaptiveExpandedSizeForItem:')
assert 'superview != self.view' in native_presentation
assert 'insertSubview:self.nativePlayerController.view belowSubview:anchor' in native_presentation
assert 'insertSubview:controller.view belowSubview:anchor' in native_presentation
view_did_load = implementation_body(MODULE, '- (void)viewDidLoad', '- (BOOL)applyPluginEnabledState')
assert 'self.nativePlayerController = [AVPlayerViewController new];' in view_did_load
assert '[self addChildViewController:self.nativePlayerController];' in view_did_load
native_reveal = implementation_body(MODULE, '- (void)revealVideoWhenReadyForItem:', '- (void)recoverPlayerLayerSurfaceIfNeededForItem:')
assert 'self.expanded && playerItem.status == AVPlayerItemStatusReadyToPlay' in native_reveal
assert 'self.nativePlayerController.player == self.player' in native_reveal
assert 'nativePresentation && playerItem.status == AVPlayerItemStatusReadyToPlay' not in native_reveal
assert '[self updateNativePlayerPresentation];' in native_reveal
assert 'self.imageView.hidden = YES;' in native_reveal
request_layout = implementation_body(MODULE, '- (void)requestControlCenterLayoutSizeUpdate', '- (void)applyLiveResizePreviewForWidth:')
assert 'for (NSUInteger depth = 0; host && depth < 8;' in request_layout
assert '[host layoutIfNeeded];' in request_layout
assert 'CCBGSyncCCAsterGridSizeIfPresent' in SHARED
assert 'com.futur3sn0w.ccaster.preferences' in SHARED
assert 'ModuleGridSizes' in SHARED
assert 'CCBGReadCCAsterGridSize' in MODULE
assert 'ModuleGridSizes' in MODULE
assert '- (void)scheduleResizeControlVisibilityRecovery' in MODULE
resize_visibility = implementation_body(MODULE, '- (void)scheduleResizeControlVisibilityRecovery', '- (void)handleResizePan:')
assert 'updateResizeControlVisibility' in resize_visibility
assert 'dispatch_after(dispatch_time' in resize_visibility
layout = implementation_body(MODULE, '- (void)viewDidLayoutSubviews', '- (void)reloadAfterFirstMountIfNeeded')
assert 'dragStillActive' in layout
assert 'self.view.frame = self.resizePreviewFrame;' in layout
assert 'CCBGPreferenceChangesOnlyGridSize' in SHARED
write_preferences = body(SHARED, 'void CCBGWritePreferences', 'void CCBGWriteMetadataPreference')
assert 'if (!sizeOnly) CCBGPostReload();' in write_preferences


# Thumbnail cache reads run on the thumbnail queue. imageWithContentsOfFile
# must never execute in CCBGLoadThumbnailForItem before that dispatch.
thumbnail_loader = body(CONTROLS, 'void CCBGLoadThumbnailForItem', 'void CCBGApplyThumbnailToCell')
disk_read = 'UIImage *diskCached = [UIImage imageWithContentsOfFile:CCBGThumbnailCachePathForItem(snapshot, size)];'
assert disk_read in thumbnail_loader
assert thumbnail_loader.index('dispatch_async(CCBGThumbnailQueue()') < thumbnail_loader.index(disk_read)
quick_look = thumbnail_loader.split('void (^startQuickLook)(void) = ^{', 1)[1].split('// UITableView asks for cells while scrolling.', 1)[0]
assert quick_look.index('dispatch_async(CCBGThumbnailQueue()') < quick_look.index('finish(CCBGScaleAndCacheThumbnail')
thumbnail_cell = CONTROLS.split('void CCBGApplyThumbnailToCell', 1)[1]
assert '[strongCell setNeedsLayout]' not in thumbnail_cell

# The resize control's own pan must be allowed through the common button
# exclusion used to protect compact-tap actions.
resize_delegate = body(MODULE, '- (BOOL)gestureRecognizer:', '- (void)installGestureHostIfNeeded')
assert 'gestureRecognizer != self.resizePan' in resize_delegate
assert '[self.view bringSubviewToFront:self.resizeButton];' in MODULE

# Preference reads are snapshot-cached. This prevents synchronous
# CFPreferences round-trips for every setting cell during a scroll, while
# local writes and Darwin reloads explicitly invalidate the cache.
assert 'void CCBGInvalidatePreferenceReadCache(void)' in SHARED
assert 'return CCBGReadAllPreferences()[key] ?: fallback;' in SHARED
assert SHARED.count('CCBGInvalidatePreferenceReadCache();') >= 3
assert 'CCBGPreferenceReadCacheAllowed' in SHARED
assert 'if (!CCBGPreferenceReadCacheAllowed()) return CCBGReadPreferencesFromDisk();' in SHARED

# Returning to the library must not rewrite the entire catalog and trigger a
# global SpringBoard reload when no media has changed.
root_appear = implementation_body(ROOT_CONTROLLER, '- (void)viewWillAppear:', '- (void)buildLibraryHeader')
assert 'CCBGSaveMediaCatalog(self.items);' not in root_appear


# Overlay reloads always execute under one preference snapshot; direct
# environment callbacks must not re-synchronize one preference per setting.
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
assert "CCBGHasOverlayPreferenceSnapshot" in OVERLAY
overlay_reload = implementation_body(
    OVERLAY,
    "- (void)reloadIfNeeded:(BOOL)force resolvedMediaName:",
    "- (void)reloadAfterPreferenceChange",
)
assert "CCBGWithOverlayPreferenceSnapshot" in overlay_reload
assert "NSDictionary *allPreferences = CCBGReadAllPreferences();" not in overlay_reload
assert overlay_reload.count("CCBGReadAllPreferences()") == 0


# Stale manual/replay scene state must not suppress normal automatic scenes.
resolver = body(
    SHARED,
    "NSDictionary *CCBGSceneDirectorResolvedScene",
    "NSString *CCBGSceneDirectorMediaForTarget",
)
assert "manualScene" in resolver
assert "CCBGClearStaleManualSceneState" in resolver
assert resolver.index("CCBGClearStaleManualSceneState") < resolver.rindex("CCBGSceneConditionMatches")
stale_scene_clear = body(
    SHARED,
    "static void CCBGClearStaleManualSceneState",
    "NSDictionary *CCBGSceneDirectorResolvedScene",
)
assert "sceneDirectorReplayActive" in stale_scene_clear


# Destructive reset removes all preference/configuration state and caches,
# but explicitly leaves the Media directory untouched.
for token in (
    "CCBGClearAllConfigurationPreservingMedia",
    "清除所有配置",
    "素材文件会保留",
):
    assert token in SHARED_H + SHARED + SETTINGS
clearer = body(
    SHARED,
    "BOOL CCBGClearAllConfigurationPreservingMedia",
    "NSDictionary *CCBGMediaItemNamed",
)
for path in ("Backups", "Thumbnails", "OverlayFrames", "VideoOnlyCache"):
    assert path in clearer
assert "removeItemAtPath:CCBGMediaDirectoryPath" not in clearer

print("2.3 regression checks passed")
