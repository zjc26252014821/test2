from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
ADVANCED = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
SCENE_DIRECTOR = (ROOT / "app" / "CCBGSceneDirectorController.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")
CONTROLS = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")
CONTROLS_HEADER = (ROOT / "app" / "CCBGControls.h").read_text(encoding="utf-8")
SCENE_EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")


def function_body(source: str, signature: str, next_signature: str) -> str:
    return source.split(signature, 1)[1].split(next_signature, 1)[0]


# Continuous sliders must keep their labels live without synchronizing shared
# preferences and reloading Control Center on every drag frame. Persistence is
# committed once when tracking ends, including numeric-entry confirmation.
slider_configuration = function_body(
    CONTROLS,
    "- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(float)value",
    "- (void)refreshValueLabel",
)
assert "@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged" in slider_configuration
assert "target action:action forControlEvents:UIControlEventValueChanged" not in slider_configuration
assert "UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel" in slider_configuration
assert "UIControlEventEditingDidEnd" in slider_configuration
slider_value_changed = function_body(
    CONTROLS,
    "- (void)sliderValueChanged:",
    "- (void)refreshValueLabel",
)
assert "[self refreshValueLabel]" in slider_value_changed
assert "!sender.tracking" in slider_value_changed
assert "sendActionsForControlEvents:UIControlEventEditingDidEnd" in slider_value_changed
numeric_commit = function_body(
    CONTROLS,
    "- (void)valueLabelDoubleTapped:",
    "@end",
)
assert numeric_commit.count("sendActionsForControlEvents:") == 1
assert "sendActionsForControlEvents:UIControlEventTouchUpInside" in numeric_commit
assert "valueCommittedHandler" not in CONTROLS
assert "setValueCommittedHandler" not in CONTROLS_HEADER

# Memory pressure must release rebuildable preloads instead of only recording
# telemetry. The current AVPlayerItem remains retained by its player.
module_memory = MODULE.rsplit("- (void)mediaMemoryWarning:", 1)[1].split("- (BOOL)shouldUseSceneLowPowerCover", 1)[0]
for token in ("self.preloadedImage = nil", "self.preloadedAsset = nil", "removeAllObjects"):
    assert token in module_memory
overlay_memory = OVERLAY.rsplit("- (void)mediaMemoryWarning:", 1)[1].split("- (void)environmentDidChange:", 1)[0]
for token in ("[CCBGPreloadedOverlayAssets removeAllObjects]", "[CCBGPreloadedOverlayFrames removeAllObjects]", "CCBGPreloadedOverlayCatalog = nil"):
    assert token in overlay_memory
assert "self.pickerThumbnailCache.countLimit = 96" in MODULE

# Removed Scene Director features must not retain hidden mutation callbacks.
for event in ("scene-clip-timing", "scene-mood", "scene-mood-signal"):
    assert event not in SCENE_EDITOR


# Analytics are emitted by Control Center playback callbacks. The public
# recording APIs must leave the caller immediately, then serialize preference
# read-modify-write work across the separately linked module images. Analytics
# uses its own lock so catalog saves cannot recursively acquire preferences.lock.
for token in ("#import <sys/file.h>", "#import <fcntl.h>", "#import <unistd.h>"):
    assert token in SHARED, token
assert "CCBGAnalyticsMutationQueue" in SHARED
lock_body = function_body(
    SHARED,
    "static void CCBGWithFileLock",
    "static void CCBGWithAnalyticsMutationLock",
)
for token in ("open(", "flock(fileDescriptor, LOCK_EX)", "flock(fileDescriptor, LOCK_UN)", "close(fileDescriptor)"):
    assert token in lock_body, token
analytics_lock_body = function_body(
    SHARED,
    "static void CCBGWithAnalyticsMutationLock",
    "static void CCBGEnqueueAnalyticsMutation",
)
assert "CCBGWithFileLock(CCBGAnalyticsMutationLockPath" in analytics_lock_body
assert "CCBGPreferencesMutationLockPath" not in analytics_lock_body
enqueue_body = function_body(
    SHARED,
    "static void CCBGEnqueueAnalyticsMutation",
    "static void CCBGCreateDebouncedAutomaticBackup",
)
assert "dispatch_async(CCBGAnalyticsMutationQueue()" in enqueue_body
assert "CCBGWithAnalyticsMutationLock" in enqueue_body

for token in ("CCBGModuleLifecycleTraceLockPath", "CCBGWithModuleLifecycleTraceLock"):
    assert token in SHARED, token
lifecycle_lock = function_body(SHARED, "static void CCBGWithModuleLifecycleTraceLock", "static dispatch_queue_t CCBGModuleLifecycleTraceQueue")
assert "createDirectoryAtPath" in lifecycle_lock
assert "CCBGWithFileLock(CCBGModuleLifecycleTraceLockPath" in lifecycle_lock
lifecycle_record = function_body(SHARED, "void CCBGRecordModuleLifecycleEvent", "NSArray<NSString *> *CCBGReadModuleLifecycleTrace")
lifecycle_read = function_body(SHARED, "NSArray<NSString *> *CCBGReadModuleLifecycleTrace", "void CCBGClearModuleLifecycleTrace")
lifecycle_clear = function_body(SHARED, "void CCBGClearModuleLifecycleTrace", "static void CCBGCreateDebouncedAutomaticBackup")
for body in (lifecycle_record, lifecycle_read):
    assert "CCBGWithModuleLifecycleTraceLock" in body
assert "dispatch_sync(CCBGModuleLifecycleTraceQueue()" in lifecycle_clear
assert "dispatch_async" not in lifecycle_clear
assert "CCBGWithModuleLifecycleTraceLock" in lifecycle_clear

analytics_functions = (
    ("void CCBGRecordSceneTimelineEvent", "NSArray<NSDictionary *> *CCBGSceneTimeline"),
    ("void CCBGRecordMediaPlaybackStart", "void CCBGRecordMediaPlaybackDuration"),
    ("void CCBGRecordMediaPlaybackDuration", "void CCBGRecordMediaMemoryPressure"),
    ("void CCBGRecordMediaMemoryPressure", "void CCBGRecordMediaPlaybackFailure"),
    ("void CCBGRecordMediaPlaybackFailure", "static void CCBGSetMediaFailure"),
)
for signature, next_signature in analytics_functions:
    body = function_body(SHARED, signature, next_signature)
    assert "CCBGEnqueueAnalyticsMutation" in body, signature

timeline_record = function_body(
    SHARED,
    "void CCBGRecordSceneTimelineEvent",
    "NSArray<NSDictionary *> *CCBGSceneTimeline",
)
for forbidden in ("CCBGReadPreference", "CCBGReadModulePreference"):
    assert forbidden not in timeline_record, forbidden
assert "CFPreferencesCopyAppValue" in timeline_record
assert "CFPreferencesAppSynchronize(domain)" in timeline_record

timeline_read = function_body(
    SHARED,
    "NSArray<NSDictionary *> *CCBGSceneTimeline",
    "void CCBGReplaySceneTimelineEntry",
)
assert "CCBGReadAnalyticsStateSynchronously" in timeline_read

# The Scene Director table must render one immutable timeline snapshot. Reading
# preferences again for every row both blocks the App and can mix generations.
assert "@property(nonatomic, copy) NSArray<NSDictionary *> *timeline;" in SCENE_DIRECTOR
assert SCENE_DIRECTOR.count("CCBGSceneTimeline()") == 1
director_appearance = function_body(SCENE_DIRECTOR, "- (void)viewWillAppear:", "- (void)addScene")
assert "self.timeline = CCBGSceneTimeline()" in director_appearance
for signature, next_signature in (
    ("- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:", "- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:"),
    ("- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:", "- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:"),
    ("- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:", "@end"),
):
    body = function_body(SCENE_DIRECTOR, signature, next_signature)
    assert "CCBGSceneTimeline()" not in body
    assert "self.timeline" in body

# Visual features belong to a specific scene. The director's former five-item
# global menu silently edited whichever scene happened to resolve last, so the
# director now exposes only scenes and replay; users enter a scene to edit its
# state tracks, relay, and visual policy.
assert "- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }" in SCENE_DIRECTOR
assert 'return @[@"已编排场景", @"控制中心回放"]' in SCENE_DIRECTOR
assert "configureVisualFeatureAtIndex" not in SCENE_DIRECTOR
assert "视觉演出" not in SCENE_DIRECTOR

# Focus discovery runs inside SpringBoard and is consumed from the settings
# app through shared preferences. Modern iOS exposes DND state/configuration
# through error-parameter selectors, and the active state must be merged with
# the cached list so opening Focus in Control Center is enough to discover it.
for token in (
    '@"DNDModeConfigurationService"',
    '@"modeConfigurationsReturningError:"',
    '@"availableModesReturningError:"',
    '@"allModesReturningError:"',
    '@"queryCurrentStateWithError:"',
    '@"activeModeConfiguration"',
    '@"modeConfiguration"',
):
    assert token in SHARED, token
available_focus = function_body(
    SHARED,
    "NSArray<NSDictionary<NSString *, id> *> *CCBGAvailableFocusModes(void)",
    "NSArray<NSString *> *CCBGCurrentFocusAliases(void)",
)
assert "CCBGAppendStoredFocusModes" in available_focus
assert "CCBGFocusAliasesFromServices" in available_focus
assert "CCBGAppendFocusMode" in available_focus

# Restored scenes are consumed inside SpringBoard. Runtime resolution must
# filter malformed elements before sorting/subscripting and reuse the result
# across the several scene feature lookups made by one layout pass.
resolved_scene = function_body(
    SHARED,
    "NSDictionary *CCBGSceneDirectorResolvedScene(NSDictionary *context)",
    "NSString *CCBGSceneDirectorMediaForTarget",
)
sorted_scenes = function_body(
    SHARED,
    "static NSArray<NSDictionary *> *CCBGSceneDirectorSortedScenes(void)",
    "NSArray<NSDictionary *> *CCBGSceneDirectorMatchingScenes",
)
assert "isKindOfClass:NSDictionary.class" in sorted_scenes
assert "respondsToSelector:@selector(integerValue)" in sorted_scenes
assert " compare:" not in resolved_scene
assert "CCBGResolvedSceneCacheContext" in resolved_scene
assert "CCBGSceneDirectorSortedScenes()" in resolved_scene

# Layout can reapply an unchanged blur value.
# Cache it on each owned media layer so a new player layer still gets a filter,
# while stable layers avoid repeatedly allocating private CAFilter objects.
module_blur = function_body(MODULE, "static void CCBGApplyGaussianBlurToLayer", "static void CCBGRefreshModulePreferenceSnapshot")
overlay_blur = function_body(OVERLAY, "static void CCBGApplyGaussianBlurToLayer", "static BOOL CCBGArmSystemOverlayCrashLoopGuard")
for blur_body in (module_blur, overlay_blur):
    assert "objc_getAssociatedObject" in blur_body
    assert "objc_setAssociatedObject" in blur_body
    assert "fabs" in blur_body

# The SpringBoard tweak constructor must not invoke the crash-loop telemetry
# helper. Its dispatch_after block is unsafe while dyld is still initializing
# libdispatch and was the direct EXC_BAD_ACCESS path in the crash report.
overlay_constructor = OVERLAY.rsplit("__attribute__((constructor)) static void CCBGSystemOverlayInit", 1)[1]
for forbidden in (
    "CCBGArmSystemOverlayCrashLoopGuard()",
    "dispatch_async",
    "dispatch_after",
    "_dyld_register_func_for_add_image",
    "CCBGSystemOverlayStart();",
):
    assert forbidden not in overlay_constructor, forbidden
assert "CFRunLoopObserverCreate" in overlay_constructor
assert "CCBGSystemOverlayRunLoopObserverCallback" in overlay_constructor
assert "__attribute__((noinline)) void CCBGSystemOverlayStart" in OVERLAY
module_init = MODULE.rsplit("- (instancetype)init", 1)[1].split("- (UIViewController *)contentViewController", 1)[0]
# Control Center instantiates module objects while CCSupport is updating its
# module table. Keep that constructor path free of diagnostic queue creation;
# lifecycle tracing starts once the content controller is requested.
assert "CCBGRecordModuleLifecycleEvent" not in module_init
assert "CCBG_VIEW_CONTROLLER_CLASS new" in module_init
module_display = MODULE.rsplit("- (void)applyDisplayForItem:(NSDictionary *)item", 1)[1].split("- (UIImage *)filteredImageAtPath:", 1)[0]
assert module_display.count("CCBGSceneContextForModule(self.view)") == 1
assert "performWithoutAnimation" in module_display
assert "setDisableActions:YES" in module_display
overlay_composition = OVERLAY.rsplit("- (void)applyCachedSceneComposition", 1)[1].split("- (void)applyCachedScenePresentation", 1)[0]
assert "performWithoutAnimation" in overlay_composition
assert "setDisableActions:YES" in overlay_composition

# Diagnostics must tolerate stale or malformed preferences instead of sending
# dictionary subscripting to arbitrary objects while the first screen loads.
diagnostics = SETTINGS.split("@implementation CCBGDiagnosticsController", 1)[1].split("@end", 1)[0]
for token in (
    "diagnosticStatusRows",
    "diagnosticMaintenanceTitles",
    "[rawItem isKindOfClass:NSDictionary.class]",
    "[rawRule isKindOfClass:NSDictionary.class]",
    "[name isKindOfClass:NSString.class]",
    "text(CCBGDisplayNameForItem(current), @\"无\")",
):
    assert token in diagnostics, token
diagnostic_rows = function_body(
    diagnostics,
    "- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:",
    "- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:",
)
assert "statusRows.count" in diagnostic_rows
assert "diagnosticStatusRows.count" not in diagnostic_rows
assert "diagnosticMaintenanceTitles.count" in diagnostic_rows

# Playback health may schedule a timeline event only after its own locked
# mutation has completed. Calling it from inside the mutation block would
# deadlock if the implementation ever becomes synchronous.
start_body = function_body(
    SHARED,
    "void CCBGRecordMediaPlaybackStart",
    "void CCBGRecordMediaPlaybackDuration",
)
start_mutation = start_body.split("CCBGEnqueueAnalyticsMutation", 1)[1].split("});", 1)[0]
assert "CCBGRecordSceneTimelineEvent" not in start_mutation
assert "CCBGRecordSceneTimelineEvent" in start_body
failure_body = function_body(
    SHARED,
    "void CCBGRecordMediaPlaybackFailure",
    "static void CCBGSetMediaFailure",
)
failure_mutation = failure_body.split("CCBGEnqueueAnalyticsMutation", 1)[1].split("});", 1)[0]
assert "CCBGRecordSceneTimelineEvent" not in failure_mutation
assert "CCBGRecordSceneTimelineEvent" in failure_body
set_failure_body = function_body(
    SHARED,
    "static void CCBGSetMediaFailure",
    "void CCBGMarkMediaFailure",
)
assert "CCBGWithAnalyticsMutationLock" in set_failure_body

# App-side catalog edits must participate in the same lock and merge every
# runtime-owned statistic, otherwise a stale settings screen can erase health
# updates that completed just before Save was tapped.
save_catalog_body = function_body(
    SHARED,
    "void CCBGSaveMediaCatalog",
    "NSDictionary *CCBGMediaItemNamed",
)
assert "CCBGWithAnalyticsMutationLock" in save_catalog_body
for runtime_key in (
    "playCount",
    "lastPlayedAt",
    "healthSuccessfulStarts",
    "healthFirstFrameSamples",
    "healthTotalFirstFrameLatency",
    "healthAverageFirstFrameLatency",
    "healthMaxFirstFrameLatency",
    "healthPlaybackSessions",
    "healthPlaybackSeconds",
    "healthAveragePlaybackDuration",
    "healthMemoryPressureCount",
    "healthLastMemoryPressureAt",
    "healthFailureCount",
    "healthLastFailureAt",
    "healthLastFailureReason",
    "healthStatus",
):
    assert f'@"{runtime_key}"' in save_catalog_body, runtime_key
clear_failures = function_body(ADVANCED, "- (void)clearFailures", "- (void)clearCache")
assert "CCBGClearMediaFailure" in clear_failures
assert "CCBGPostReload()" in clear_failures
assert 'CCBGWritePreference(@"mediaCatalog"' not in clear_failures

# Control Center can lay out an expanded module dozens of times during a
# transition. Layout may apply cached geometry/mood only; it must not touch
# CFPreferences, discover Focus state, or resolve a scene.
layout_body = function_body(OVERLAY, "- (void)layoutSubviews", "- (void)traitCollectionDidChange:")
assert "applyCachedSceneComposition" in layout_body
assert "applyCachedScenePresentation" not in layout_body
for forbidden in (
    "CCBGReadPreference",
    "CCBGSceneRuntimeContext",
    "CCBGSceneDirectorResolvedScene",
    "CCBGSceneDirectorMoodForTarget",
    "applySceneMoodOnly",
):
    assert forbidden not in layout_body, forbidden

composition_body = OVERLAY.rsplit("- (void)applyCachedSceneComposition", 1)[1].split("- (void)generateSceneSmartCoverAtTime", 1)[0]
for token in ("cachedAdaptiveCompositionEnabled", "convertRect:self.bounds toView:self.window"):
    assert token in composition_body, token
for forbidden in (
    "CCBGReadPreference",
    "CCBGSceneRuntimeContext",
    "CCBGSceneDirectorResolvedScene",
    "CCBGApplyGaussianBlurToLayer",
    "self.dimView.alpha",
    "self.alpha =",
    "self.player.rate =",
):
    assert forbidden not in composition_body, forbidden
for removed in ("cachedSceneMood", "applyCachedScenePresentation", "applySceneMoodOnly"):
    assert removed not in OVERLAY

# The low-power cover pauses the existing AVPlayerItem, so its current time is
# already preserved. Seeking again during restore races the immediate play and
# can flash or stick on the cover frame.
module_low_power_restore = MODULE.rsplit("- (void)restoreSceneLowPowerPlaybackIfNeeded", 1)[1].split("- (void)startVideoPlaybackWhenReadyForItem:", 1)[0]
overlay_low_power_policy = OVERLAY.rsplit("- (void)applySceneLowPowerPolicy", 1)[1].split("- (NSArray<NSDictionary *> *)availableVideoItems", 1)[0]
for body in (module_low_power_restore, overlay_low_power_policy):
    assert "seekToTime" not in body

# Storyboard presentation state was removed with the feature.
for removed in ("applySceneEvent:", "sceneBaseItem", "restoreBasePresentationAfterSceneClip"):
    assert removed not in MODULE

# Automatic-scene hit deduplication represents an active interval, not a scene
# that matched once forever. Leaving automation or entering manual mode must
# clear the remembered ID so the same scene can be recorded on re-entry.
expanded_slot_writer = function_body(
    SHARED,
    "void CCBGSceneDirectorSetExpandedSlot",
    "NSString *CCBGSceneDirectorStateMediaForTarget",
)
assert "CCBGInvalidatePreferenceReadCache();" in expanded_slot_writer

clear_quick_history = function_body(
    SHARED,
    "void CCBGClearQuickConfigurationHistory",
    "void CCBGReplaceAllPreferences",
)
assert "CCBGWriteMetadataPreference(CCBGQuickConfigurationUndoStackKey, nil);" in clear_quick_history
assert "CFPreferencesSetAppValue" not in clear_quick_history

environment_change = MODULE.rsplit("- (void)environmentDidChange:", 1)[1].split("- (void)scheduleEnvironmentRefresh", 1)[0]
assert "automaticSceneActive" in environment_change
assert 'CFPreferencesSetAppValue(CFSTR("sceneDirectorLastAutomaticTimelineSceneID"), NULL, domain)' in environment_change

# Volume/brightness callbacks can arrive much faster than scene resolution.
# Coalesce them while retaining the orientation-specific settled-layout retry.
for token in ("environmentChangeScheduled", "pendingOrientationRefresh"):
    assert token in MODULE, token
assert "if (self.environmentChangeScheduled) return" in environment_change
assert "dispatch_after" in environment_change
assert "needsOrientationRefresh" in environment_change
assert "        }\n        if (needsOrientationRefresh)" in environment_change
runtime_persistence = environment_change.split("if (self.player.currentItem", 1)[1].split("NSDictionary *scene", 1)[0]
assert "CCBGRecordModuleRuntimeState" in runtime_persistence
assert "CFPreferencesSetAppValue" not in runtime_persistence
assert "CFPreferencesAppSynchronize" not in runtime_persistence
runtime_writer = function_body(
    SHARED,
    "void CCBGRecordModuleRuntimeState",
    "void CCBGRecordRuntimeDiagnostic",
)
assert "CCBGEnqueueAnalyticsMutation" in runtime_writer
diagnostic_writer = function_body(
    SHARED,
    "void CCBGRecordRuntimeDiagnostic",
    "void CCBGRecordSystemOverlayPlaybackSuccess",
)
assert "if (!key.length) return" in diagnostic_writer
assert "CCBGEnqueueAnalyticsMutation" in diagnostic_writer
overlay_success_writer = function_body(
    SHARED,
    "void CCBGRecordSystemOverlayPlaybackSuccess",
    "void CCBGRecordSceneTimelineEvent",
)
for token in ("CCBGEnqueueAnalyticsMutation", "systemOverlayRecentMedia", "failureKeyCopy"):
    assert token in overlay_success_writer, token

# Shared health APIs already copy arguments and enqueue under their own serial
# lock. Control Center callers must not lock a public process singleton or add
# a second utility-queue hop around those APIs.
assert "@synchronized (NSProcessInfo.processInfo)" not in MODULE
assert "@synchronized (NSProcessInfo.processInfo)" not in OVERLAY
module_health_start = MODULE.rsplit("- (void)recordSuccessfulMediaStartIfNeeded", 1)[1].split("- (void)recordActivePlaybackDurationIfNeeded", 1)[0]
module_health_duration = MODULE.rsplit("- (void)recordActivePlaybackDurationIfNeeded", 1)[1].split("- (void)mediaMemoryWarning:", 1)[0]
module_health_memory = MODULE.rsplit("- (void)mediaMemoryWarning:", 1)[1].split("- (BOOL)shouldUseSceneLowPowerCover", 1)[0]
for body in (module_health_start, module_health_duration, module_health_memory):
    assert "dispatch_get_global_queue" not in body

# Controller attachment can call this diagnostic repeatedly while Control
# Center settles. It must deduplicate in memory and enqueue diagnostics rather
# than synchronously reading/writing CFPreferences on the main thread.
overlay_diagnostic = function_body(
    OVERLAY,
    "static void CCBGRecordOverlayDiagnostic",
    "static void CCBGHideController",
)
assert "CCBGLastOverlayDiagnosticValues" in overlay_diagnostic
assert "CCBGRecordRuntimeDiagnostic" in overlay_diagnostic
for forbidden in ("CCBGReadPreference", "CFPreferencesSetAppValue", "CFPreferencesAppSynchronize"):
    assert forbidden not in overlay_diagnostic, forbidden

# Host viewDidLayoutSubviews fires for every transition frame. Those hooks may
# resize an attached overlay, but a full preference/media refresh is allowed
# only once when compact/expanded runtime state actually changes.
layout_helper = OVERLAY.split("static void CCBGLayoutControllerOverlay", 1)[1].split("static void CCBGUpdateOrLayoutController", 1)[0]
assert layout_helper.count("CCBGUpdateController") == 1
assert "overlay.expandedPresentation != expanded" in layout_helper
assert "overlay.kind != kind" in layout_helper
assert "expandedFrameForHostView:hostView module:" in layout_helper
assert "CCBGPlaceOverlay(overlay, hostView)" in layout_helper
for forbidden in ("CCBGReadPreference", "CCBGSelectedOverlayMediaName", "reloadIfNeeded", "applyAdaptiveFrameForHostView"):
    assert forbidden not in layout_helper, forbidden
adaptive_frame = OVERLAY.rsplit("- (void)applyAdaptiveFrameForHostView:", 1)[1].split("- (void)dealloc", 1)[0]
expanded_frame = OVERLAY.rsplit("- (CGRect)expandedFrameForHostView:", 1)[1].split("- (void)applyAdaptiveFrameForHostView:", 1)[0]
assert "self.preferredExpandedFrameSize = CGSizeMake(width, height)" in expanded_frame
assert "self.adaptiveExpandedFrameEnabled" in expanded_frame

controller_hook = function_body(
    OVERLAY,
    "static void CCBGHookControllerClass",
    "static id CCBGValueForKeyIfAvailable",
)
controller_layout_hook = controller_hook.split("SEL layoutSelector", 1)[1].split("SEL willAppearSelector", 1)[0]
assert "CCBGUpdateOrLayoutController" in controller_layout_hook
assert "CCBGUpdateController" not in controller_layout_hook

slider_layout_host = function_body(
    OVERLAY,
    "static void CCBGUpdateSliderViewHost",
    "static void CCBGHookSliderViewClass",
)
assert "CCBGUpdateOrLayoutController" in slider_layout_host
assert "CCBGUpdateController" not in slider_layout_host

update_or_layout = function_body(
    OVERLAY,
    "static void CCBGUpdateOrLayoutController",
    "static void CCBGHideController",
)
assert "objc_getAssociatedObject(controller, CCBGOverlayAssociationKey)" in update_or_layout
assert "CCBGLayoutControllerOverlay" in update_or_layout
assert "CCBGUpdateController" in update_or_layout

generic_container_hook = function_body(
    OVERLAY,
    "static void CCBGHookGenericContainerClass",
    "static CGFloat CCBGGenericModuleExpandedDimension",
)
generic_layout_hook = generic_container_hook.split("SEL layoutSelector", 1)[1].split("SEL appearSelector", 1)[0]
assert "CCBGUpdateOrLayoutController" in generic_layout_hook
for forbidden in ("CCBGUpdateKnownGenericContainerController", "CCBGRecordGenericModuleMatch", "CCBGUpdateController"):
    assert forbidden not in generic_layout_hook, forbidden

# A stable generic-module match updates two related runtime keys. Read them in
# one snapshot and commit them together without two independent synchronize
# cycles or a global reload notification.
generic_match = function_body(
    OVERLAY,
    "static void CCBGRecordGenericModuleMatch",
    "static void CCBGUpdateGenericContainerController",
)
for token in ("CFPreferencesCopyMultiple", "stateChanged", "supportsExpandedChanged"):
    assert token in generic_match, token
for forbidden in ("CCBGReadPreference", "CCBGSetPreferenceValue", "CCBGWritePreferences", "CCBGPostReload"):
    assert forbidden not in generic_match, forbidden
assert generic_match.count("CFPreferencesSynchronize(domain") == 1
assert generic_match.count("CFPreferencesAppSynchronize(domain)") == 2

configured_module_hook = function_body(
    OVERLAY,
    "static void CCBGHookConfiguredModuleClass",
    "static void CCBGInstallGenericModuleHooks",
)
assert "CCBGUpdateOrLayoutController(controller" in configured_module_hook
assert "if (controller.isViewLoaded) CCBGUpdateController" not in configured_module_hook

# Disabled overlays must leave before expansion discovery, scene/media
# resolution, and diagnostics. Control Center creates many hooked controllers
# even when their individual background feature is off.
controller_update = OVERLAY.split(
    "static void CCBGUpdateController(UIViewController *controller, CCBGSystemOverlayKind kind) {",
    1,
)[1].split("static void CCBGLayoutControllerOverlay", 1)[0]
disabled_prefix = controller_update.split("if (!enabled)", 1)[0]
for forbidden in ("CCBGControllerIsExpandedPresentation", "CCBGRecordOverlayDiagnostic", "CCBGSelectedOverlayMediaName"):
    assert forbidden not in disabled_prefix, forbidden
enabled_suffix = controller_update.split("if (!enabled)", 1)[1]
assert "CCBGControllerIsExpandedPresentation" in enabled_suffix
assert "CCBGRecordOverlayDiagnostic" in enabled_suffix

# One full overlay update reads many related keys. A transaction-scoped
# snapshot must collapse those reads to one domain synchronization, and the
# selected media resolved by the controller must flow into reloadIfNeeded
# instead of traversing scene/state preferences a second time.
for token in (
    "CCBGWithOverlayPreferenceSnapshot",
    "CCBGOverlayReadPreference",
    "#define CCBGReadPreference CCBGOverlayReadPreference",
):
    assert token in OVERLAY, token
snapshot_wrapper = function_body(
    OVERLAY,
    "static void CCBGWithOverlayPreferenceSnapshot",
    "#define CCBGReadPreference CCBGOverlayReadPreference",
)
assert "CCBGReadAllPreferences" in snapshot_wrapper
assert "threadDictionary" in snapshot_wrapper
assert "@finally" in snapshot_wrapper
assert "CCBGWithOverlayPreferenceSnapshot(^{" in controller_update
assert controller_update.count("CCBGSelectedOverlayMediaName") == 1
assert "[overlay reloadIfNeeded:presentationChanged resolvedMediaName:selectedName]" in controller_update
resolved_reload = OVERLAY.split(
    "- (void)reloadIfNeeded:(BOOL)force resolvedMediaName:(NSString *)resolvedMediaName {",
    1,
)[1].split("- (void)startPlaybackWhenReady", 1)[0]
assert "resolvedMediaName ?: CCBGSelectedOverlayMediaName" in resolved_reload

overlay_environment = OVERLAY.rsplit("- (void)environmentDidChange:", 1)[1].split("- (void)applyCachedSceneComposition", 1)[0]
assert "sceneEnvironmentRefreshScheduled" in OVERLAY
assert "if (self.sceneEnvironmentRefreshScheduled) return" in overlay_environment
assert "dispatch_after" in overlay_environment
assert "self.sceneEnvironmentRefreshScheduled = NO" in overlay_environment
assert "CCBGInvalidateSceneRuntimeCaches()" in overlay_environment
assert "self.lastConfigurationCheck = 0" in overlay_environment
assert "[self reloadIfNeeded:NO]" in overlay_environment
assert "[self applySceneLowPowerPolicy]" in overlay_environment

assert "CCBGRecordRuntimeDiagnostic(@\"musicOverlayPlaybackState\"" in OVERLAY
assert 'CFPreferencesSetAppValue(CFSTR("musicOverlayPlaybackState")' not in OVERLAY
recent_success = OVERLAY.rsplit("- (void)recordRecentVideoName:", 1)[1].split("- (void)applyInteractiveVideoName:", 1)[0]
assert "CCBGRecordSystemOverlayPlaybackSuccess" in recent_success
for forbidden in ("CCBGReadPreference", "CCBGSetPreferenceValue", "CCBGStringArrayPreference"):
    assert forbidden not in recent_success, forbidden
playback_failure = OVERLAY.rsplit("- (void)handlePlaybackFailure", 1)[1].split("- (void)videoEnded:", 1)[0]
assert "self.lastRecordedRecentName = nil" in playback_failure

runtime_size = function_body(MODULE, "static CCUILayoutSize CCBGRuntimeModuleSize", "static BOOL CCBGCurrentInterfaceIsLandscape")
assert "CCBGLastRuntimeSizeLogSignature" in runtime_size
assert "if (![signature isEqualToString:CCBGLastRuntimeSizeLogSignature])" in runtime_size
assert "CCBGHasCachedRuntimeGridSize" in runtime_size
assert "CCBGLastRuntimeGridReadAt" in runtime_size
assert "if (!CCBGHasCachedRuntimeGridSize || now - CCBGLastRuntimeGridReadAt >= 0.5)" in runtime_size
reload_callback = function_body(MODULE, "static void CCBGReloadCallback(", "static void CCBGPresentationRecoveryCallback(")
assert "CCBGHasCachedRuntimeGridSize = NO" in reload_callback

clear_logs = function_body(SETTINGS, "- (void)clearLogs", "- (void)openMediaDirectoryInFilza")
assert "CCBGWritePreferences(changes)" in clear_logs
assert "CCBGWriteModulePreference" not in clear_logs

print("scene runtime safety regression checks passed")
