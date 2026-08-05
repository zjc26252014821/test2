from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")
DIRECTOR = (ROOT / "app" / "CCBGSceneDirectorController.m").read_text(encoding="utf-8")


# Scene Director automatic conditions no longer expose or evaluate time ranges.
condition_matcher = SHARED.split("static BOOL CCBGSceneConditionMatches", 1)[1].split(
    "NSDictionary *CCBGSceneDirectorResolvedScene", 1
)[0]
assert "startMinutes" not in condition_matcher
assert "endMinutes" not in condition_matcher
assert "scene-time" not in DIRECTOR
assert 'title:@"时间段"' not in EDITOR


# Storyboard clips and mood linkage are removed end to end, not merely hidden.
for token in ("CCBGSceneDirectorClipForTarget", "CCBGSceneDirectorMoodForTarget"):
    assert token not in HEADER
    assert token not in SHARED
for token in (
    "CCBGSceneClipEditorController",
    "CCBGSceneMoodEditorController",
    'title:@"分镜片段"',
    'title:@"情绪联动"',
):
    assert token not in EDITOR
for token in ("sceneClipActive", "sceneBaseItem", "restoreBasePresentationAfterSceneClip"):
    assert token not in MODULE
for token in ("cachedSceneMood", "applySceneMoodOnly"):
    assert token not in OVERLAY


# Focus retains the selected mode while an explicit switch decides whether it
# participates in matching.
assert 'conditions[@"focusEnabled"]' in condition_matcher
assert 'conditions[@"focus"]' in condition_matcher
assert 'key:@"focusEnabled"' in EDITOR
assert 'updatedConditions[@"focusEnabled"]' in EDITOR
assert "清除已选模式" in EDITOR


# Every remaining automatic condition uses the same mounted runtime context.
for key in ('@"locked"', '@"dark"', '@"charging"', '@"landscape"'):
    assert key in condition_matcher
runtime_context = SHARED.split("NSDictionary *CCBGSceneRuntimeContext", 1)[1].split(
    "static BOOL CCBGSceneConditionMatches", 1
)[0]
for token in ("CCBGSceneSystemIsLocked", "CCBGSystemUsesDarkAppearance", "batteryState", "interfaceOrientation"):
    assert token in runtime_context


# Local environment callbacks must invalidate the 100 ms scene cache before
# resolving media. Overlays must perform a real media reload, not only effects.
module_environment = MODULE.rsplit("- (void)environmentDidChange:", 1)[1].split(
    "- (void)scheduleEnvironmentRefresh", 1
)[0]
assert module_environment.index("CCBGInvalidateSceneRuntimeCaches()") < module_environment.index(
    "CCBGSceneDirectorResolvedScene"
)
overlay_environment = OVERLAY.rsplit("- (void)environmentDidChange:", 1)[1].split(
    "- (void)applyCachedSceneComposition", 1
)[0]
assert "CCBGInvalidateSceneRuntimeCaches()" in overlay_environment
assert "self.lastConfigurationCheck = 0" in overlay_environment
assert "reloadIfNeeded:NO" in overlay_environment
assert "pendingSceneOrientationRefresh" in overlay_environment
assert "needsOrientationRefresh" in overlay_environment
assert "0.65 * NSEC_PER_SEC" in overlay_environment
for notification in (
    "UIDeviceBatteryStateDidChangeNotification",
    "UIDeviceOrientationDidChangeNotification",
    "UIApplicationDidBecomeActiveNotification",
    'com.apple.springboard.lockstate',
    'com.apple.springboard.hasBlankedScreen',
):
    assert notification in MODULE or notification in OVERLAY, notification


# Remaining state-track and relay features must tolerate malformed restored
# nested preferences instead of subscripting or messaging arbitrary objects.
state_track = SHARED.split("NSString *CCBGSceneDirectorStateMediaForTarget", 1)[1].split(
    "BOOL CCBGSceneDirectorRelayFromSlotInContext", 1
)[0]
assert 'scene[@"stateTracks"] isKindOfClass:NSDictionary.class' in state_track
relay = SHARED.split("BOOL CCBGSceneDirectorRelayFromSlotInContext", 1)[1].split(
    "void CCBGRecordModuleRuntimeState", 1
)[0]
assert 'relay[@"mediaBySlot"] isKindOfClass:NSDictionary.class' in relay
assert "isKindOfClass:NSNumber.class" in relay
assert "[value integerValue]" in relay


# Priority remains explicit and documented: the highest numeric priority wins
# when multiple enabled automatic scenes match simultaneously.
resolver = SHARED.split("NSDictionary *CCBGSceneDirectorResolvedScene", 1)[1].split(
    "NSString *CCBGSceneDirectorMediaForTarget", 1
)[0]
scene_sorter = SHARED.split("static NSArray<NSDictionary *> *CCBGSceneDirectorSortedScenes", 1)[1].split(
    "NSArray<NSDictionary *> *CCBGSceneDirectorMatchingScenes", 1
)[0]
assert "leftPriority > rightPriority ? NSOrderedAscending" in scene_sorter
assert "CCBGSceneDirectorSortedScenes()" in resolver
assert "优先级数值更高的场景生效" in EDITOR


print("Scene Director simplification and condition regression checks passed")
