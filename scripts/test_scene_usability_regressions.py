from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
QUICK = (ROOT / "app" / "CCBGQuickConfigController.m").read_text(encoding="utf-8")
PREVIEW = (ROOT / "app" / "CCBGPreviewController.m").read_text(encoding="utf-8")
EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")


# Scene dark-mode matching must use the actual system appearance. Control Center
# host views may report a fixed local trait and must not override that value.
runtime_context = SHARED.split("NSDictionary *CCBGSceneRuntimeContext(UIView *view)", 1)[1].split(
    "static BOOL CCBGSceneConditionMatches", 1
)[0]
assert "BOOL dark = CCBGSystemUsesDarkAppearance();" in runtime_context
assert "traitCollection.userInterfaceStyle" not in runtime_context


# Quick preview must receive the selected slot's effective media configuration,
# and the preview controller must treat missing opacity/rate as normal defaults.
quick_preview = QUICK.split("- (void)previewCurrentMedia", 1)[1].split(
    "- (void)openCompositionAssistant", 1
)[0]
effective_item = QUICK.split("- (NSDictionary *)effectiveCurrentMediaItem", 1)[1].split(
    "- (void)previewCurrentMedia", 1
)[0]
assert "CCBGMediaItemForModule" in effective_item
assert "self.selectedSlot" in effective_item
assert "self.effectiveCurrentMediaItem" in quick_preview
assert "CCBGPreviewNumber" in PREVIEW
assert 'CCBGPreviewNumber(self.item, @"opacity", 1.0)' in PREVIEW
assert 'CCBGPreviewNumber(self.item, @"playbackRate", 1.0)' in PREVIEW


# Relay still uses a double tap at runtime, but the editor must expose whether
# this scene is currently eligible and explain the source/target trigger.
assert 'isEqualToString:@"DoubleTap"' in MODULE
assert "CCBGSceneDirectorRelayFromSlotInContext" in MODULE
assert "showRelayStatus" in EDITOR
assert "CCBGSceneDirectorEvaluationForScene" in EDITOR
assert "双击" in EDITOR
assert "当前场景未命中" in EDITOR


# Visual strategies are conditional effects, not media selectors. Their status
# screen must describe the live prerequisites so an enabled-but-inactive policy
# is distinguishable from a broken switch.
assert "showVisualStrategyStatus" in EDITOR
for text in ("低电量模式", "呼吸网格", "感应式构图", "当前场景未命中"):
    assert text in EDITOR, text


print("Scene condition, preview, relay, and visual strategy regression checks passed")
