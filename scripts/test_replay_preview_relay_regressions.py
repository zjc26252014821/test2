from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
PREVIEW = (ROOT / "app" / "CCBGPreviewController.m").read_text(encoding="utf-8")
EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")


# Current-material video preview must use the native iOS controller, which
# supplies the expected transport controls, PiP path, and audio route behavior.
assert "AVPlayerViewController" in PREVIEW
assert "showsPlaybackControls = YES" in PREVIEW
assert "playerController" in PREVIEW


# A replay entry must retain a wall-clock timestamp with millisecond precision,
# a display-ready label, and a complete preference snapshot. Replaying it must
# write the snapshot atomically and issue a real Control Center reload.
assert "CCBGRecordSceneTimelineEvent" in HEADER
timeline_recording = SHARED.split("void CCBGRecordSceneTimelineEvent", 1)[1].split(
    "NSArray<NSDictionary *> *CCBGSceneTimeline", 1
)[0]
assert "timeIntervalSince1970" in timeline_recording
assert "timestampMilliseconds" in timeline_recording
assert "displayTime" in timeline_recording
assert 'entry[@"snapshot"]' in SHARED
replay = SHARED.split("void CCBGReplaySceneTimelineEntry", 1)[1]
assert "CCBGWritePreferences" in replay
assert "CCBGInvalidateSceneRuntimeCaches" in replay


# Scene-editor status must read the last context confirmed in SpringBoard
# before falling back to the app's own context; these processes can differ.
context_method = EDITOR.split("- (NSDictionary *)currentSceneContext", 1)[1].split(
    "- (BOOL)currentSceneIsResolved", 1
)[0]
assert 'CCBGReadPreference(@"sceneDirectorLastRuntimeContext"' in context_method
assert "CCBGSceneRuntimeContext(self.view)" in context_method


print("Replay, native preview, and relay-context regression checks passed")
