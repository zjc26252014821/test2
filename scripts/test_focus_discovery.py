from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")


# DND classes are private-framework symbols and are not guaranteed to be
# present in SpringBoard until the framework image has been loaded explicitly.
for token in (
    "#import <dlfcn.h>",
    "CCBGEnsureFocusFrameworkLoaded",
    'DoNotDisturb.framework/DoNotDisturb',
    "dlopen(",
):
    assert token in SHARED, token

services = SHARED.split("static NSArray *CCBGFocusModeServices(void)", 1)[1].split("static void CCBGAppendFocusMode", 1)[0]
assert "CCBGEnsureFocusFrameworkLoaded" in services
assert "@try" in services and "@catch" in services
alias_collector = SHARED.split("static void CCBGCollectFocusAliases", 1)[1].split("static BOOL CCBGEnsureFocusFrameworkLoaded", 1)[0]
assert "@try" in alias_collector and "@catch" in alias_collector
for activity_selector in ('@"activityDisplayName"', '@"activityIdentifier"', '@"activityUniqueIdentifier"'):
    assert activity_selector in alias_collector, activity_selector
active_query = SHARED.split("static NSArray<NSString *> *CCBGFocusAliasesFromServices", 1)[1].split("static void CCBGCollectConfiguredFocusModes", 1)[0]
assert "@try" in active_query and "@catch" in active_query

# FocusUI itself obtains the user-visible list through FCActivityManager. This
# path must run before the lower-level DND XPC getters, which can reject tweak
# clients even when the selectors are present.
activity_manager = SHARED.split("static id CCBGFocusActivityManager(void)", 1)[1].split("static NSArray *CCBGFocusModeServices", 1)[0]
for token in (
    'NSClassFromString(@"FCActivityManager")',
    '@"sharedActivityManager"',
    '@"availableActivities"',
    '@"activeActivity"',
):
    assert token in activity_manager, token

# iOS 16's generated DoNotDisturb runtime headers expose these exact sync
# getters. The older guessed *WithError: names silently return no modes.
for selector in (
    '@"modeConfigurationsReturningError:"',
    '@"availableModesReturningError:"',
    '@"allModesReturningError:"',
):
    assert selector in SHARED, selector
for wrong_selector in ('@"allModeConfigurationsWithError:"', '@"modeConfigurationsWithError:"'):
    assert wrong_selector not in SHARED, wrong_selector
focus_discovery = SHARED.split("static NSArray *CCBGFocusModeServices(void)", 1)[1].split("NSDictionary *CCBGSceneRuntimeContext", 1)[0]
assert "class_copyMethodList" not in focus_discovery
assert '@"source": @"ios16-runtime-header"' in focus_discovery
assert "NSError **" in focus_discovery
available_modes = SHARED.split("NSArray<NSDictionary<NSString *, id> *> *CCBGAvailableFocusModes(void)", 1)[1].split("NSArray<NSDictionary<NSString *, id> *> *CCBGRefreshFocusModeCache", 1)[0]
assert available_modes.index("CCBGFocusActivityManager()") < available_modes.index("CCBGFocusModeServices()")
assert 'activityManagerResult' in available_modes
fallback_guard = available_modes.split("if (!modes.count)", 1)
assert len(fallback_guard) == 2
assert "CCBGFocusConfigurationPaths()" not in fallback_guard[0]
assert "CFPreferencesCopyKeyList" not in fallback_guard[0]
assert "CCBGFocusConfigurationPaths()" in fallback_guard[1]
assert "CFPreferencesCopyKeyList" in fallback_guard[1]

current_aliases = SHARED.split("NSArray<NSString *> *CCBGCurrentFocusAliases(void)", 1)[1].split("static NSDictionary *CCBGSceneBaseRuntimeContext", 1)[0]
assert current_aliases.index("CCBGFocusAliasesFromActivityManager") < current_aliases.index("CCBGFocusAliasesFromServices")
for token in (
    "CCBGFocusActivityManagerHasAuthoritativeState",
    "managerAuthoritative",
    "CCBGPersistCurrentFocusAliases(@[])",
):
    assert token in current_aliases, token
assert current_aliases.index("if (managerAuthoritative)") < current_aliases.index("return [stored isKindOfClass:NSArray.class]")
assert "CCBGCurrentFocusAliasesCache = [activeAliases copy]" not in available_modes

# Focus discovery and current-state ownership are separate. The shared
# observer drives enter/exit/switch changes, while every linked module image
# invalidates its own scene caches before resolving the resulting reload.
for token in ("CCBGObserveFocusActivityChanges", "CCBGInvalidateSceneRuntimeCaches"):
    assert token in HEADER, token
observer_source = SHARED.split("@interface CCBGFocusActivityObserver", 1)[1].split("static NSString *CCBGFocusDiscoveryProcessKey", 1)[0]
for token in (
    "activeActivityDidChangeForManager:",
    "activeModeDidChangeForManager:",
    "availableActivitiesDidChangeForManager:",
    "addObserver:",
):
    assert token in observer_source, token
assert "if (!CCBGFocusActivityChangeHandler)" in observer_source
cache_invalidation = SHARED.split("void CCBGInvalidateSceneRuntimeCaches(void)", 1)[1].split("NSDictionary *CCBGSceneDirectorResolvedScene", 1)[0]
for token in (
    "CCBGCurrentFocusAliasesCache = nil",
    "CCBGSceneRuntimeContextCache = nil",
    "CCBGResolvedSceneCacheValid = NO",
):
    assert token in cache_invalidation, token
module_reload = MODULE.split("static void CCBGReloadCallback", 1)[1].split("static void CCBGPresentationRecoveryCallback", 1)[0]
assert module_reload.index("CCBGInvalidateSceneRuntimeCaches()") < module_reload.index("reloadPreferencesAndMedia")

# The App cannot rely on scene evaluation happening incidentally. Opening the
# picker requests a refresh from the always-loaded SpringBoard overlay tweak,
# then reads the cross-process cache again after the notification is handled.
for token in (
    "CCBGFocusRefreshNotificationName",
    "CCBGRefreshFocusModeCache",
    "CCBGFocusDiscoveryStatus",
):
    assert token in HEADER, token
for token in (
    "CCBGFocusRefreshCallback",
    "CCBGFocusRefreshNotificationName",
    "CCBGRefreshFocusModeCache()",
    "CFNotificationCenterAddObserver",
):
    assert token in OVERLAY, token
springboard_refresh = OVERLAY.split("static NSUInteger CCBGFocusRefreshGeneration", 1)[1].split("static void CCBGStartNetworkMonitoring", 1)[0]
assert '@[@0.0, @0.8, @2.0]' in springboard_refresh
assert "CCBGFocusRefreshGeneration" in springboard_refresh
focus_refresh_schedule = springboard_refresh.split("static void CCBGScheduleFocusRefreshes", 1)[1].split("static void CCBGFocusRefreshCallback", 1)[0]
assert "CCBGObserveFocusActivityChanges" in focus_refresh_schedule
for token in (
    "CCBGHandleFocusActivityChange",
    "CCBGObserveFocusActivityChanges",
    "CCBGInvalidateSceneRuntimeCaches",
    "CCBGPostReload",
    "CCBGLastFocusStateSignature",
):
    assert token in OVERLAY, token
overlay_reload = OVERLAY.split("static void CCBGSystemOverlayReload", 1)[1].split("static NSUInteger CCBGFocusRefreshGeneration", 1)[0]
assert overlay_reload.index("CCBGInvalidateSceneRuntimeCaches()") < overlay_reload.index("CCBGUpdateController")


# FCActivityManager can deliver its observer callback before activeActivity
# settles. Every change therefore needs bounded re-sampling, not one 80 ms
# read that can permanently preserve the previous Focus signature.
focus_change_handler = OVERLAY.split("static void CCBGHandleFocusActivityChange", 1)[1].split("static void CCBGScheduleFocusRefreshes", 1)[0]
assert "@[@0.08, @0.35, @0.90]" in focus_change_handler
assert "CCBGFocusStateChangeGeneration" in focus_change_handler
assert focus_change_handler.count("CCBGInvalidateSceneRuntimeCaches()") >= 1
assert "CCBGPostReload()" in focus_change_handler

# Appearance callbacks must invalidate the shared scene context before they
# ask the module/overlay to resolve dark-mode conditions again.
module_trait = MODULE.split("- (void)traitCollectionDidChange:", 1)[1].split("- (void)viewWillTransitionToSize:", 1)[0]
assert module_trait.index("CCBGInvalidateSceneRuntimeCaches()") < module_trait.index("environmentDidChange")
overlay_trait = OVERLAY.split("- (void)traitCollectionDidChange:", 1)[1].split("- (void)applyAdaptiveFrameForHostView:", 1)[0]
assert overlay_trait.index("CCBGInvalidateSceneRuntimeCaches()") < overlay_trait.index("reloadIfNeeded")

# Mounted scene and legacy module appearance automation share the canonical
# global system appearance. Control Center host traits can be fixed to light.
runtime_context = SHARED.split("NSDictionary *CCBGSceneRuntimeContext", 1)[1].split("static BOOL CCBGSceneConditionMatches", 1)[0]
assert "BOOL dark = CCBGSystemUsesDarkAppearance();" in runtime_context
assert "traitCollection.userInterfaceStyle" not in runtime_context
automation_body = MODULE.split("- (NSString *)automationSelectionForItems:", 1)[1].split("- (void)reloadPreferencesAndMedia", 1)[0]
assert "NSDictionary *sceneContext = CCBGSceneContextForModule(self.view)" in automation_body
assert '(BOOL)dark != [sceneContext[@"dark"] boolValue]' in automation_body
for token in ('@"darkModeAutomationEnabled"', '@"darkModeMedia"', '@"lightModeMedia"'):
    assert token in automation_body, token
picker_appearance = EDITOR.split("- (void)viewWillAppear:(BOOL)animated", 1)[1].split("- (NSInteger)tableView", 1)[0]
for token in (
    "CFNotificationCenterPostNotification",
    "CCBGFocusRefreshNotificationName",
    "dispatch_after",
    "CCBGAvailableFocusModes()",
):
    assert token in picker_appearance, token
assert '@[@0.6, @1.8]' in picker_appearance

# Empty results must be observable on device instead of collapsing framework,
# service, file, and cache failures into the same generic footer.
assert "CCBGFocusDiscoveryStatus()" in EDITOR
assert 'sceneDirectorFocusDiscovery' in SHARED
for token in ('@"focusDiscovery": CCBGFocusDiscoveryStatus()', '@"knownFocusModes"', '@"lastFocusAliases"'):
    assert token in SETTINGS, token

print("Focus discovery cross-process regression checks passed")
