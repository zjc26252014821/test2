from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
EDITOR = (ROOT / "app" / "CCBGSceneEditorController.m").read_text(encoding="utf-8")


condition_matcher = SHARED.split("static BOOL CCBGSceneConditionMatches", 1)[1].split(
    "static NSDictionary *CCBGResolvedSceneCacheContext", 1
)[0]
assert "BOOL hasEnabledCondition = NO" in condition_matcher
assert "hasEnabledCondition = YES" in condition_matcher
assert "return hasEnabledCondition" in condition_matcher


relay = SHARED.split("BOOL CCBGSceneDirectorRelayFromSlotInContext", 1)[1].split(
    "void CCBGRecordModuleRuntimeState", 1
)[0]
assert "sceneDirectorRelay" not in relay
assert "return YES" in relay
assert "FOUNDATION_EXPORT BOOL CCBGSceneDirectorRelayFromSlotInContext" in HEADER

gesture_action = MODULE.split("- (void)performConfiguredActionForGestureName:", 2)[2].split(
    "- (void)requestExpandedPresentation", 1
)[0]
assert "BOOL relayed = NO" in gesture_action
assert "relayed = CCBGSceneDirectorRelayFromSlotInContext" in gesture_action
assert "action != 0 || relayed" in gesture_action


low_power_policy = SHARED.split("BOOL CCBGSceneDirectorLowPowerStatic", 1)[1].split(
    "BOOL CCBGSceneDirectorBreathingGridEnabled", 1
)[0]
assert "sceneDirectorLowPowerStatic" not in low_power_policy
assert "return sceneEnabled" in low_power_policy


assert "双击来源模块触发" in EDITOR
assert "仅在当前场景命中时生效" in EDITOR
assert "低电量模式下暂停视频并显示封面帧" in EDITOR


print("Scene switch behavior regression checks passed")
