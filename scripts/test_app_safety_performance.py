from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")
DIRECTOR = (ROOT / "app" / "CCBGSceneDirectorController.m").read_text(encoding="utf-8")
SCENE_EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
APP_DELEGATE = (ROOT / "app" / "CleanCCBG2x2App.m").read_text(encoding="utf-8")
SETTINGS_AUTOMATION = SETTINGS.split("@implementation CCBGAutomationController", 1)[1].split("@interface CCBGSystemOverlayPlaylistController", 1)[0]
PREVIEW = (ROOT / "app" / "CCBGPreviewController.m").read_text(encoding="utf-8")
DETAIL = (ROOT / "app" / "CCBGMediaDetailController.m").read_text(encoding="utf-8")


def body(start: str, end: str) -> str:
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


# Preference-backed collections must filter their container and element types
# before table row counts and dictionary subscripting use them.
for token in (
    "CCBGDictionaryArrayValue",
    "CCBGStringArrayValue",
    "[entry isKindOfClass:NSDictionary.class]",
    "[entry isKindOfClass:NSString.class]",
):
    assert token in SOURCE, token

profiles_appearance = body("@implementation CCBGProfilesController", "- (NSInteger)numberOfSectionsInTableView")
assert "CCBGDictionaryArrayValue(CCBGReadPreference" in profiles_appearance
for token in ("CCBGProfilePreferencesSnapshot", "CCBGApplyProfilePreferences"):
    assert token in SOURCE, token
profile_snapshot = body("static NSDictionary *CCBGProfilePreferencesSnapshot", "static BOOL CCBGApplyProfilePreferences")
profile_apply = body("static BOOL CCBGApplyProfilePreferences", "static dispatch_queue_t CCBGInsightsAnalysisQueue")
assert 'removeObjectForKey:@"configurationProfiles"' in profile_snapshot
assert 'preferences[@"configurationProfiles"]' in profile_apply
assert "CCBGRestorePreferencesSnapshot" in profile_apply
profiles_controller = body("@implementation CCBGProfilesController", "@implementation CCBGModuleAppearanceController")
assert "CCBGProfilePreferencesSnapshot()" in profiles_controller
assert "CCBGApplyProfilePreferences" in profiles_controller

rules_appearance = body("@implementation CCBGAdvancedAutomationController", "- (void)updateConflictHeader")
assert rules_appearance.count("CCBGDictionaryArrayValue") == 2
conflict_header = body("- (void)updateConflictHeader", "- (NSInteger)tableView")
assert "CCBGIntegerValue" in conflict_header
assert '[@"priority"]compare:' not in conflict_header


# The two-second status refresh must scan the catalog and read history once,
# then render all cells and summaries from that immutable snapshot.
status_controller = body("@interface CCBGStatusDashboardController", "@interface CCBGAdaptationPreviewController")
for token in ("catalogSnapshot", "historySnapshot", "reloadStatusSnapshot"):
    assert token in status_controller, token
refresh = status_controller.split("- (void)reloadStatusSnapshot", 1)[1].split("- (void)viewWillAppear", 1)[0]
assert refresh.count("CCBGLoadMediaCatalog()") == 1
assert "CCBGDictionaryArrayValue" in refresh
cell = status_controller.split("cellForRowAtIndexPath:", 1)[1].split("willDisplayCell:", 1)[0]
display = status_controller.split("willDisplayCell:", 1)[1].split("didSelectRowAtIndexPath:", 1)[0]
for rendering_path in (cell, display):
    assert "CCBGLoadMediaCatalog()" not in rendering_path
    assert 'CCBGReadModulePreference(@"playbackHistory"' not in rendering_path


# Complete backups should stream on a utility queue. Building one giant media
# dictionary on the main thread freezes the App and multiplies memory usage.
for token in ("CCBGBackupWorkQueue", "CCBGWriteCompleteBackup", "NSOutputStream"):
    assert token in SOURCE, token
export = body("- (void)exportIncludingMedia:", "- (void)documentPicker:")
assert "dispatch_async(CCBGBackupWorkQueue()" in export
before_dispatch = export.split("dispatch_async(CCBGBackupWorkQueue()", 1)[0]
assert "dataWithContentsOfFile" not in before_dispatch
assert "base64EncodedStringWithOptions" not in before_dispatch

# The settings app repeatedly asks for the catalog while rendering adjacent
# screens. Reuse the in-process snapshot and invalidate it with preferences;
# SpringBoard keeps uncached reads for cross-process freshness.
for token in (
    "CCBGMediaCatalogCacheLock",
    "CCBGMediaCatalogCachedValue",
    "CCBGPreferenceReadCacheAllowed()",
    "CCBGMediaCatalogCache = nil",
    "CCBGMediaStorageBytesCache",
):
    assert token in SHARED, token

# Becoming active should not reload hidden navigation/tab tables. Only tables
# still attached to a visible window participate in the refresh.
reload_helper = APP_DELEGATE.split("- (void)reloadVisibleTableViewsInView:", 1)[1].split("- (BOOL)application:", 1)[0]
assert "view.window" in reload_helper
assert "view.hidden" in reload_helper
assert "view.alpha" in reload_helper

# Automation status rows share one eligible-media snapshot per refresh instead
# of rescanning the catalog once for every visible row.
assert "eligibleItemsSnapshot" in SETTINGS_AUTOMATION
status_cell = SETTINGS_AUTOMATION.split("- (UITableViewCell *)statusCell:", 1)[1].split("- (void)refreshStatus", 1)[0]
assert "self.eligibleItemsSnapshot" in status_cell

# Status updates must not interrupt an active table gesture; defer the small
# section reload until scrolling ends.
assert "statusReloadPending" in SETTINGS_AUTOMATION
assert "scrollViewDidEndDragging" in SETTINGS_AUTOMATION
assert "scrollViewDidEndDecelerating" in SETTINGS_AUTOMATION

# Large still-image previews must decode off the main thread and guard the
# result against a newer preview request.
image_preview = PREVIEW.split("UIImage *image = [UIImage imageWithContentsOfFile:path]", 1)[0]
assert "dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY" in PREVIEW
assert "UIImage *image = [UIImage imageWithContentsOfFile:path]" in PREVIEW
assert "playbackGeneration" in PREVIEW

# Media detail metadata must not synchronously open AVAsset or decode an image
# from the initializer; load it on a utility queue and refresh only metadata
# sections when it completes.
initializer = DETAIL.split("- (instancetype)initWithMediaItem", 1)[1].split("- (void)loadMediaMetadata", 1)[0]
assert "AVURLAsset" not in initializer
assert "imageWithContentsOfFile" not in initializer
assert "loadMediaMetadata" in DETAIL
assert "dispatch_get_global_queue(QOS_CLASS_UTILITY" in DETAIL


# Diagnostics and Scene Director should also render immutable page snapshots;
# otherwise each visible row repeats media-size/reference or catalog scans.
diagnostics = SETTINGS.split("@implementation CCBGDiagnosticsController", 1)[1].split("@end", 1)[0]
assert "@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *statusRows;" in SETTINGS
reload_status = diagnostics.split("- (void)reloadStatus", 1)[1].split("- (NSUInteger)invalidMediaReferenceCount", 1)[0]
assert "self.statusRows = [self diagnosticStatusRows]" in reload_status
diagnostic_table = diagnostics.split("- (NSInteger)numberOfSectionsInTableView", 1)[1].split("- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath", 1)[0]
assert "self.diagnosticStatusRows" not in diagnostic_table
assert diagnostic_table.count("self.statusRows") >= 2

# Device scene failures must be diagnosable without another guess-and-build
# cycle. Export the last SpringBoard context, the scene that resolves against
# it, the manual override, and a compact condition summary for every scene.
diagnostic_export = diagnostics.split("- (void)exportDiagnosticReport", 1)[1].split("- (void)exportBackup", 1)[0]
for token in (
    'CCBGReadPreference(@"sceneDirectorLastRuntimeContext", @{})',
    "CCBGSceneDirectorResolvedScene(sceneRuntimeContext)",
    'CCBGReadPreference(@"sceneDirectorManualSceneID", @"")',
    '@"sceneRuntimeContext"',
    '@"resolvedScene"',
    '@"sceneConditions"',
):
    assert token in diagnostic_export, token

assert "@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;" in DIRECTOR
director_appearance = DIRECTOR.split("- (void)viewWillAppear:", 1)[1].split("- (void)addScene", 1)[0]
assert "self.mediaCatalog = CCBGLoadMediaCatalog()" in director_appearance
director_cells = DIRECTOR.split("cellForRowAtIndexPath:", 1)[1].split("canMoveRowAtIndexPath:", 1)[0]
assert "CCBGLoadMediaCatalog()" not in director_cells
assert "self.mediaCatalog" in director_cells

# Timeline preferences are user-restorable data and may contain stale or
# malformed entries. The shared API must filter them before the UI subscripts.
timeline_reader = SHARED.split("NSArray<NSDictionary *> *CCBGSceneTimeline(void)", 1)[1].split("void CCBGReplaySceneTimelineEntry", 1)[0]
assert "isKindOfClass:NSDictionary.class" in timeline_reader
assert "reloadSceneData" in DIRECTOR
assert "[self viewWillAppear:NO]" not in DIRECTOR

# Scene and third-party module collections can come from restored legacy
# backups. One filtered snapshot must drive row counts, cells, selection, and
# mutation so malformed elements cannot be subscripted or change the row count
# between callbacks.
assert "static NSArray<NSDictionary *> *CCBGStoredScenes(void)" in SCENE_EDITOR
assert "static NSArray<NSDictionary *> *CCBGConfiguredGenericModules(void)" in SCENE_EDITOR
assert SCENE_EDITOR.count('CCBGReadPreference(@"sceneDirectorScenes"') == 1
assert SCENE_EDITOR.count('CCBGReadPreference(@"customSystemOverlayModules"') == 1
assert "for (NSDictionary *scene in CCBGReadPreference" not in SCENE_EDITOR
assert DIRECTOR.count('CCBGReadPreference(@"sceneDirectorScenes"') == 1
assert '[CCBGReadPreference(@"sceneDirectorScenes", @[]) mutableCopy]' not in DIRECTOR
assert 'NSMutableArray *stored = [self.scenes mutableCopy]' in DIRECTOR
assert "@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;" in SCENE_EDITOR
assert "self.mediaCatalog = CCBGLoadMediaCatalog();" in SCENE_EDITOR
for line in SCENE_EDITOR.splitlines():
    if "cellForRowAtIndexPath:" in line:
        assert "CCBGLoadMediaCatalog()" not in line

print("App safety and performance regression checks passed")
