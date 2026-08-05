from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
module = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
overlay = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
settings = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")
advanced = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
shared = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
controls = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")
master_switch = (ROOT / "utilitytoggle" / "CleanCCBGMasterSwitch.m").read_text(encoding="utf-8")
scene_editor = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")
main_tabs = (ROOT / "app" / "CCBGMainTabBarController.m").read_text(encoding="utf-8")
app_delegate = (ROOT / "app" / "CleanCCBG2x2App.m").read_text(encoding="utf-8")


# Expandable generic modules use compact/expanded media and leave native taps alone.
for token in (
    "CCBGGenericModuleUsesPresentationMedia",
    '@"SupportsExpanded"',
    '@"CompactMedia"',
    '@"ExpandedMedia"',
    "genericUsesPresentationMedia",
):
    assert token in overlay, token
assert "BOOL usesPresentationMedia = [self genericModuleSupportsExpandedPresentation]" in settings
assert 'usesPresentationMedia ? @"CompactMedia" : @"StateOffMedia"' in settings
assert 'usesPresentationMedia ? @"ExpandedMedia" : @"StateOnMedia"' in settings
interaction_block = overlay.rsplit("- (void)installInteractionsOnHostView:", 1)[1].split("- (BOOL)gestureRecognizer:", 1)[0]
assert "if (usesPresentationMedia && !customExpansion)" in interaction_block
assert "genericUsesCustomExpansion" in interaction_block
assert "[recognizers removeAllObjects]" in interaction_block

# Expanded sizing explicitly distinguishes adaptive fitting from manual dimensions.
assert '@"adaptiveExpandedSizeEnabled"' in shared
assert 'CCBGModulePreference(@"adaptiveExpandedSizeEnabled", @YES)' in module
assert '@[@"自适应", @"手动"]' in advanced
assert "if (!CCBGUsesAdaptiveExpandedSize()) return maximum;" in module

# Privacy media is allowed to load when its directory is readable, and orientation uses the scene.
assert "CCBGCurrentInterfaceIsLandscape(self.view)" in module
assert "windowScene.interfaceOrientation" in module
assert "CCBGLastKnownLayoutLandscape" in module
assert "CCBGModuleLayoutOrientationDidChangeNotification" in module
assert "CCBGRecordModuleLayoutOrientation(orientation)" in module
assert "module-layout-orientation" in module
display_block = module.split("- (void)showCurrentMediaWithTransition:", 1)[1].split("- (UIImage *)filteredImageAtPath:", 1)[0]
assert "if (!mediaDirectoryReadable)" in display_block
assert "|| privacyProtected" not in display_block
mounted_reload = module.rsplit("- (BOOL)requiresMountedMediaReload", 1)[1].split("- (void)resumeVideoPlaybackIfNeeded", 1)[0]
assert "privacyEnabled" not in mounted_reload
assert "self.player.currentItem" not in mounted_reload
assert "- (BOOL)requiresMountedPlayerLayerRecovery" in module
assert "self.playerLayer.superlayer != self.view.layer" in module
mounted_convergence = module.rsplit("- (void)scheduleMountedPresentationConvergence", 1)[1].split("- (NSArray<NSDictionary *> *)mountedPresentationHierarchySnapshot", 1)[0]
assert "[weakSelf reloadAfterFirstMountIfNeeded]" in mounted_convergence
assert "mounted-presentation-delayed" in mounted_convergence

# Haptics reuse a prepared generator, and native player touches bypass custom tap actions.
assert "hapticGenerator" in module
assert "[self.hapticGenerator impactOccurredWithIntensity:0.85]" in module
assert "touchTargetsNativePlayer" in module

# Automation overrides never overwrite the base current media and cleanly restore it.
assert "self.automationOverrideActive = overrideSelection.length > 0;" in module
assert "NSString *baseSelection" in module
assert "selection = overrideSelection.length ? overrideSelection : baseSelection;" in module

# Automatic-dimension rows must remain visible in the appearance/privacy controller.
assert "cell.hidden = height >= 0 && height < 1.0;" in advanced

# Preference/environment reloads require a full host-hierarchy recovery after media changes.
assert 'convergeMountedPresentation:@"environment-change"' in module
assert '[reason hasPrefix:@"reload"]' in module
assert '[reason hasPrefix:@"environment-change"]' in module

# Generic module discovery must never recursively rescan the object graph on every layout pass.
generic_layout_hook = overlay.split("static void CCBGHookGenericContainerClass", 1)[1].split("static CGFloat CCBGGenericModuleExpandedDimension", 1)[0]
generic_layout = generic_layout_hook.split("SEL appearSelector", 1)[0]
generic_appearance = generic_layout_hook.split("SEL appearSelector", 1)[1]
assert "CCBGUpdateOrLayoutController(controller" in generic_layout
for forbidden in ("CCBGUpdateKnownGenericContainerController", "CCBGUpdateGenericContainerController", "CCBGRecordGenericModuleMatch"):
    assert forbidden not in generic_layout
assert "CCBGUpdateGenericContainerController(controller)" in generic_appearance
assert "CCBG_GENERIC_IDENTITY_LIMIT" in overlay
identity_scan = overlay.split("static void CCBGCollectGenericObjectIdentity", 1)[1].split("static BOOL CCBGGenericContainerShouldUseFallback", 1)[0]
assert '@"module",' not in identity_scan

# Fixed, compact, and generic playback failures preserve the configured selection.
failure_block = overlay.split("- (void)handlePlaybackFailure", 2)[2].split("- (void)videoEnded:", 1)[0]
assert "BOOL preserveConfiguredSelection = [self playbackMode] == 0 || !self.expandedPresentation" in failure_block
preserve_block = failure_block.split("if (preserveConfiguredSelection)", 1)[1].split("NSString *fileName", 1)[0]
assert "advanceAutomaticallyBy" not in preserve_block

# CCSwitch transitions are native-owned: generic disappear callbacks do not suppress,
# hide, or schedule repeated compact restores while Control Center is animating.
controller_hook = overlay.split("static void CCBGHookControllerClass", 1)[1].split("static id CCBGValueForKeyIfAvailable", 1)[0]
assert "CCBGScheduleGenericCompactRestore" not in controller_hook
generic_container_hook = overlay.split("static void CCBGHookGenericContainerClass", 1)[1].split("static CGFloat CCBGGenericModuleExpandedDimension", 1)[0]
assert "SEL willDisappearSelector" not in generic_container_hook
assert "SEL disappearSelector" not in generic_container_hook
assert "CCBGScheduleGenericCompactRestore" not in overlay
assert "CCBGGenericOverlaySuppressUntilKey" not in overlay
assert "CCBGRestoreVisibleCompactOverlays" not in overlay
assert "- (void)didMoveToWindow" in overlay
assert "if (!self.window && !self.expandedPresentation)" in overlay
assert "UIViewPropertyAnimator *visibilityAnimator" in overlay
assert "BOOL wasAnimating = self.visibilityAnimator != nil" in overlay
assert "windowAttachmentGeneration" in overlay
assert "generation != self.windowAttachmentGeneration" in overlay
assert "if (!overlay.superview || CGRectIsEmpty(overlay.bounds)) overlay.frame = hostView.bounds;" in overlay
assert "CCBGGenericContainerShouldUseFallback" in overlay
assert '@"netskao.ccswitchdatamodule"' in overlay

# Re-enabling the master switch must rediscover controllers that remained
# mounted after their media overlay was detached. A reload notification alone
# is insufficient because those controllers may not receive viewWillAppear:
# again while Control Center stays open.
assert "CCBGTrackedOverlayControllers" in overlay
assert "CCBGRefreshTrackedOverlayControllers" in overlay
assert "CCBGUpdateOrLayoutController(controller, kind)" in overlay
assert "CCBGRefreshTrackedOverlayControllers();" in overlay
# Master-switch recovery should not rebuild offscreen controller trees. An
# on-screen controller is the only one that can need a visible media/player
# recovery; refreshing hidden ones starts unnecessary AVFoundation work.
assert "if (!controller.isViewLoaded || !controller.view.window) continue;" in overlay
assert "hostController.view.window || hostController.view.superview" in overlay
assert "CCBGSystemOverlayPresentationRecovery" in overlay
assert "CCBGPresentationRecoveryNotificationName" in overlay
presentation_hook = overlay.split("static void CCBGHookControlCenterPresentationClass", 1)[1].split("static UIViewController *CCBGViewHostController", 1)[0]
assert "CCBGApplyVisualThemeAutomationIfNeeded(controller.view);" in presentation_hook
assert "CCBGSchedulePresentationRootRebind();" in presentation_hook
assert "CCBGScheduleTrackedOverlayRefreshes();" not in presentation_hook
controller_layout_hook = overlay.split("static void CCBGHookControllerClass", 1)[1].split("static id CCBGValueForKeyIfAvailable", 1)[0]
assert "CCBGUpdateOrLayoutController(controller, resolvedKind)" in controller_layout_hook
generic_layout_hook = overlay.split("static void CCBGHookGenericContainerClass", 1)[1].split("static CGFloat CCBGGenericModuleExpandedDimension", 1)[0]
assert "CCBGUpdateOrLayoutController(controller, (CCBGSystemOverlayKind)kindValue.integerValue)" in generic_layout_hook
assert "CCBGOverlayRebindAttemptKey" in overlay
assert "now - lastAttempt.doubleValue < 0.30" in overlay
reload_block = overlay.split("static void CCBGSystemOverlayReload", 1)[1].split("static NSUInteger CCBGFocusRefreshGeneration", 1)[0]
assert "CCBGInvalidatePreferenceReadCache();" in reload_block
hide_controller = overlay.rsplit("static void CCBGHideController", 1)[1].split("static BOOL CCBGClassIsSubclassOf", 1)[0]
assert "if (controller.view.window) return;" in hide_controller
visible_body = overlay.rsplit("- (void)setPlaybackVisible:(BOOL)visible", 1)[1].split("- (void)restoreSuppressedArtwork", 1)[0]
assert "self.playerLayer.hidden = NO;" in visible_body

# A generic container remains a valid fallback until its concrete content
# controller was actually bound. Some built-in modules (including flashlight)
# instantiate that controller before our hook is installed.
assert "static BOOL CCBGGenericContainerShouldUseFallback(UIViewController *controller, NSDictionary *module)" in overlay
assert "CCBGGenericContainerHasDirectOwner" in overlay
configured_hook = overlay.split("static void CCBGHookConfiguredModuleClass", 1)[1].split("static void CCBGInstallGenericModuleHooks", 1)[0]
assert "CCBGDetachGenericFallbackOverlaysForDirectController(controller" in configured_hook

# Both media pickers open at the active selection, including a system-overlay
# playlist whose selected item is outside the playlist scope.
for source in (controls, overlay):
    assert "scrollToSelectedItemIfNeeded" in source
    assert "scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO" in source
assert "(NSInteger)itemIndex + 1" in controls
assert "self.scopeControl.selectedSegmentIndex = 0;" in overlay
assert "[self.playlistItems indexOfObjectPassingTest:" in overlay

# Environment automations must use SpringBoard lock state, observe rotation,
# and recheck style changes after the global preference write settles.
assert "CCBGSystemIsLocked" in module
assert "UIDeviceOrientationDidChangeNotification" in module
assert "scheduleEnvironmentRefresh" in module
automation_block = module.split("- (NSString *)automationSelectionForItems:", 1)[1].split("- (void)reloadPreferencesAndMedia", 1)[0]
assert "UIApplication.sharedApplication.protectedDataAvailable" not in automation_block

# Scene automatic conditions must use the mounted Control Center appearance,
# accept a Focus display name such as `个人`, and pass real runtime state to
# system/third-party overlays instead of hard-coded false/empty values.
scene_runtime = shared.split("NSDictionary *CCBGSceneRuntimeContext(UIView *view)", 1)[1].split("static BOOL CCBGSceneConditionMatches", 1)[0]
assert "BOOL dark = CCBGSystemUsesDarkAppearance();" in scene_runtime
assert "traitCollection.userInterfaceStyle" not in scene_runtime
assert "CCBGCurrentFocusAliases" in scene_runtime
focus_lookup = shared.split("static void CCBGCollectFocusAliases", 1)[1].split("NSDictionary *CCBGSceneRuntimeContext", 1)[0]
for selector_name in ('@"displayName"', '@"localizedName"', '@"name"', '@"title"', '@"identifier"'):
    assert selector_name in focus_lookup, selector_name
condition_match = shared.split("static BOOL CCBGSceneConditionMatches", 1)[1].split("NSDictionary *CCBGSceneDirectorResolvedScene", 1)[0]
assert "CCBGNormalizedSceneText" in condition_match
assert '@"focusAliases"' in condition_match
module_scene_context = module.split("static NSDictionary *CCBGSceneContextForModule", 1)[1].split("static float CCBGEffectivePlaybackRate", 1)[0]
assert "CCBGSceneRuntimeContext(view)" in module_scene_context
environment_signature = module.split("- (NSString *)currentEnvironmentSignature", 2)[2].split("- (void)environmentDidChange:", 1)[0]
assert 'context[@"dark"]' in environment_signature
assert 'context[@"focus"]' in environment_signature
assert '@"charging": @NO, @"locked": @NO, @"landscape": @NO, @"focus": @""' not in overlay
assert "CCBGSceneRuntimeContext(view)" in overlay
assert "traitCollectionDidChange:" in overlay
assert "CCBGSceneFocusPickerController" in scene_editor
assert "CCBGAvailableFocusModes" in scene_editor
assert 'presentTextAlert:@"专注模式标识"' not in scene_editor
assert "ModeConfigurations.json" in shared

# Scene Director is global across all slots and system overlays. It must be a
# dedicated bottom tab, never a row that follows the active module selector.
tab_setup = main_tabs.split("self.viewControllers = @[", 1)[1].split("];", 1)[0]
assert "CCBGSceneDirectorController" in tab_setup
assert '@"场景"' in tab_setup
workspace_rows = main_tabs.split("@implementation CCBGModuleWorkspaceController", 1)[1].split("@implementation CCBGMoreController", 1)[0]
assert "CCBGSceneDirectorController" not in workspace_rows
assert "CCBGDashboardController.class" in main_tabs.split("@implementation CCBGMoreController", 1)[1]
assert "tabs.viewControllers[1]" in app_delegate

# The master switch intentionally refuses expansion, but iOS 16 still asks
# the content controller for its expanded dimensions during a long press.
assert "- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }" in master_switch
assert "- (CGFloat)preferredExpandedContentHeight" in master_switch
assert "- (CGFloat)preferredExpandedContentWidth" in master_switch

# Remaining Scene functions stay runtime-backed: relays keep every custom slot
# independent, and replay restores only an explicit snapshot.
scene_controller = (ROOT / "app" / "CCBGSceneDirectorController.m").read_text(encoding="utf-8")
for token in (
    "CCBGTimelineEventTitle", '@"playback-start": @"素材开始播放"', '@"playback-failure": @"素材播放失败"',
):
    assert token in scene_controller, token
for ambiguous_global_entry in (
    "交互式素材编排", "模块情绪联动", "状态轨道与智能封面", "configureVisualFeatureAtIndex",
):
    assert ambiguous_global_entry not in scene_controller, ambiguous_global_entry
for dead_token in ("CCBGSceneRelayTargetsController", "selectClipMediaForScene", "selectStateTrackMediaForScene", 'Generic / %@'):
    assert dead_token not in scene_controller, dead_token
for token in (
    "CCBGSceneDirectorStateMediaForTarget",
    "CCBGSceneDirectorRelayFromSlotInContext", "@\"snapshot\"", "healthSuccessfulStarts", "healthFailureCount",
):
    assert token in shared, token
assert "CCBGSceneDirectorRelayFromSlotInContext(CCBG_MODULE_SLOT" in module
assert "CCBGSceneDirectorLowPowerStatic(CCBGSceneContextForModule(self.view))" in module
assert "StateStatus" in overlay
for token in (
    "自动条件", "素材目标",
    "第三方状态轨道", "跨模块接力", "低电量使用封面帧",
    "CCBGSceneStateTrackEditorController",
    "CCBGSceneSlotPickerController", "sceneDirectorManualSceneID",
):
    assert token in scene_editor, token
for removed in ("CCBGSceneClipEditorController", "CCBGSceneMoodEditorController", "CCBGSceneDirectorClipForTarget", "CCBGSceneDirectorMoodForTarget"):
    assert removed not in scene_editor + shared + module + overlay, removed
for label in (
    "Connectivity compact", "Relay targets", "Automatic conditions", "Media targets",
    "Storyboard clips", "Mood transform", "Third-party state tracks", "Cross-module relay",
    "Low power cover frames", "Event media", "State tracks", "Not set", "Start seconds",
    "End seconds (0 means end)", "Media health", "Relay media override",
):
    assert label not in scene_editor, label
assert "relayEnabled" in scene_editor
assert "canMoveRowAtIndexPath" in scene_controller
for token in ("CCBGSceneDirectorLowPowerStatic", "CCBGCurrentFocusIdentifier", "CCBGSceneDirectorRelayFromSlotInContext"):
    assert token in shared, token
for token in ("CCBGSceneDirectorBreathingGridEnabled", "CCBGSceneDirectorSetExpandedSlot", "CCBGPostPresentationRecovery"):
    assert token in shared, token
assert "CCBGSceneDirectorSetExpandedSlot(enabled ? CCBG_MODULE_SLOT : -1)" in module
assert "CCBGModuleLayoutOrientationDidChangeNotification" in module
presentation_recovery = module.split("static void CCBGPresentationRecoveryCallback", 1)[1].split("@implementation CCBG_VIEW_CONTROLLER_CLASS", 1)[0]
assert "applyDisplayForItem:controller.currentItem" in presentation_recovery
assert "- (void)applyDisplayForItem:(NSDictionary *)item;" in module

# Removed mood linkage leaves no live-signal scene context or hot callbacks.
scene_runtime = shared.split("NSDictionary *CCBGSceneRuntimeContext(UIView *view)", 1)[1].split("static BOOL CCBGSceneConditionMatches", 1)[0]
for signal in ('@"volume"', '@"brightness"', '@"network"', '@"musicActive"'):
    assert signal not in scene_runtime, signal
environment_signature = module.split("- (NSString *)currentEnvironmentSignature", 2)[2].split("- (void)environmentDidChange:", 1)[0]
for signal in ('context[@"volume"]', 'context[@"brightness"]', 'context[@"network"]', 'context[@"musicActive"]'):
    assert signal not in environment_signature, signal

# Scene low-power mode must preserve the selected video and player position.
# It may pause behind a smart cover, but it must never filter that video from
# the queue and silently select a different item.
eligibility = module.split("- (NSArray<NSDictionary *> *)eligibleItems:", 1)[1].split("- (NSArray<NSDictionary *> *)playbackQueueForItems:", 1)[0]
assert "CCBGSceneDirectorLowPowerStatic" not in eligibility
for token in ("sceneLowPowerCoverActive", "activateSceneLowPowerCoverIfNeeded", "restoreSceneLowPowerPlaybackIfNeeded"):
    assert token in module, token
resume_block = module.split("- (void)resumeVideoPlaybackIfNeeded", 1)[1].split("- (BOOL)requiresMountedPlayerLayerRecovery", 1)[0]
assert "activateSceneLowPowerCoverIfNeeded" in resume_block
assert "restoreSceneLowPowerPlaybackIfNeeded" in resume_block

# Media health begins only after decode/first-frame success and records latency,
# useful playback duration, decode failures, and memory pressure.
for token in ("CCBGRecordMediaPlaybackStart", "CCBGRecordMediaPlaybackDuration", "CCBGRecordMediaMemoryPressure"):
    assert token in shared and token in (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8"), token
show_media = module.split("- (void)showCurrentMediaWithTransition:", 1)[1].split("- (void)preloadNextMedia", 1)[0]
record_before_decode = show_media.split("if (!CCBGIsVideoName", 1)[0]
assert "CCBGRecordMediaPlayback(" not in record_before_decode
reveal_video = module.split("- (void)revealVideoWhenReadyForItem:", 2)[2].split("- (void)recoverPlayerLayerSurfaceIfNeededForItem:", 1)[0]
assert "self.playerLayer.readyForDisplay" in reveal_video
assert "recordSuccessfulMediaStartIfNeeded" in reveal_video
assert "recordActivePlaybackDurationIfNeeded" in module
assert "UIApplicationDidReceiveMemoryWarningNotification" in module
for metric in ("healthAverageFirstFrameLatency", "healthAveragePlaybackDuration", "healthMemoryPressureCount", "healthStatus"):
    assert metric in shared and metric in scene_editor, metric

# Storyboard playback state is absent after removing the feature.
for token in ("sceneBaseItem", "sceneClipRestoreTimer", "restoreBasePresentationAfterSceneClip"):
    assert token not in module, token

# Timeline replay covers both custom and system visual state, and the timeline
# records automatic scene hits, favorite changes, and playback failures.
timeline_record = shared.split("void CCBGRecordSceneTimelineEvent", 1)[1].split("NSArray<NSDictionary *> *CCBGSceneTimeline", 1)[0]
assert '@"systemOverlays"' in timeline_record
timeline_replay = shared.split("void CCBGReplaySceneTimelineEntry", 1)[1].split("NSString *CCBGAutomationMediaName", 1)[0]
assert 'snapshot[@"systemOverlays"]' in timeline_replay
assert "CCBGWritePreference(" not in timeline_replay
assert timeline_replay.count("CCBGWritePreferences(changes)") == 1
assert '@"playback-failure"' in shared
assert '@"favorite-changed"' in (ROOT / "app" / "CCBGRootController.m").read_text(encoding="utf-8")
assert '@"automatic-scene-hit"' in module

# Smart-cover extraction samples the current video position, and adaptive
# composition uses the mounted module's normalized position in its window.
for token in ("generateSceneSmartCoverAtTime", "adaptiveCompositionEnabled"):
    assert token in module or token in shared or token in scene_editor, token
display_block = module.split("- (void)applyDisplayForItem:", 1)[1].split("- (UIImage *)filteredImageAtPath:", 1)[0]
assert "convertRect:self.view.bounds toView:self.view.window" in display_block
overlay_cached_composition = overlay.rsplit("- (void)applyCachedSceneComposition", 1)[1].split("- (void)generateSceneSmartCoverAtTime", 1)[0]
assert "convertRect:self.bounds toView:self.window" in overlay_cached_composition
assert "replaceCurrentItemWithPlayerItem" not in overlay_cached_composition
assert "reloadIfNeeded" not in overlay_cached_composition

# SpringBoard invokes overlay prewarming from a utility queue. UIKit's
# mainScreen asserts on iOS 16 when called there, so shared appearance lookup
# must be CoreFoundation-only. This is the exact crash signature in 2.0.107.
appearance_lookup = shared.split("BOOL CCBGSystemUsesDarkAppearance(void)", 1)[1].split("static NSString *CCBGNormalizedSceneText", 1)[0]
assert "UIScreen" not in appearance_lookup

print("reported module behavior regression checks passed")
