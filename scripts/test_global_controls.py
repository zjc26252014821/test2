from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
QUICK = (ROOT / "app" / "CCBGQuickConfigController.m").read_text(encoding="utf-8")


# Global pause must suppress automatic scene selection while leaving an
# explicitly selected manual scene available for deliberate use.
assert "CCBGSceneDirectorAutomationPaused" in HEADER
pause_reader = SHARED.split("BOOL CCBGSceneDirectorAutomationPaused", 1)[1].split(
    "NSDictionary *CCBGSceneDirectorResolvedScene", 1
)[0]
assert 'CCBGReadPreference(@"sceneDirectorAutomationPaused"' in pause_reader
resolver = SHARED.split("NSDictionary *CCBGSceneDirectorResolvedScene", 1)[1].split(
    "NSString *CCBGSceneDirectorMediaForTarget", 1
)[0]
assert "CCBGSceneDirectorAutomationPaused()" in resolver
assert "if (!manualID.length && automationPaused)" in resolver


# The quick workspace exposes the global controls without making users enter a
# scene editor, including current snapshot, latest replay, and replay exit.
for identifier in ('@"automationPause"', '@"recordSnapshot"', '@"replayLatest"', '@"endReplay"'):
    assert identifier in QUICK, identifier
assert "globalAutomationChanged" in QUICK
assert "CCBGRecordSceneTimelineEvent(@\"manual-snapshot\"" in QUICK
assert "CCBGReplaySceneTimelineEntry" in QUICK
assert "CCBGExitSceneTimelineReplay" in QUICK


print("Global controls regression checks passed")
