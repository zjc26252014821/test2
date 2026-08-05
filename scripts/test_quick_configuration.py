from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
TABS = (ROOT / "app" / "CCBGMainTabBarController.m").read_text(encoding="utf-8")
CONTROLLERS = (ROOT / "app" / "CCBGAppControllers.h").read_text(encoding="utf-8")
CONTROLS = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")
QUICK = (ROOT / "app" / "CCBGQuickConfigController.m").read_text(encoding="utf-8")
ADVANCED = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
APP_MAKEFILE = (ROOT / "app" / "Makefile").read_text(encoding="utf-8")


# The dedicated tab keeps the high-frequency System tab and moves lower-use
# More tools into the searchable quick workspace.
assert "CCBGQuickConfigController" in CONTROLLERS
assert 'CCBGNavigationController([[CCBGQuickConfigController alloc]' in TABS
assert '@"快捷"' in TABS
assert 'CCBGNavigationController([[CCBGSystemModulesController alloc]' in TABS
assert 'CCBGNavigationController([[CCBGMoreController alloc]' not in TABS
assert "CCBGQuickConfigController.m" in APP_MAKEFILE
for label in ("系统模块", "第三方模块", "更多设置", "配置搜索"):
    assert label in QUICK

# Search typing must coalesce table work and invalidate queued refreshes when
# the controller leaves the screen.
assert "searchReloadGeneration" in QUICK
assert "dispatch_after" in QUICK
assert "generation != self.searchReloadGeneration" in QUICK


# Every quick mutation is one atomic preference transaction with a bounded,
# type-filtered undo history. Missing keys must restore as removals.
for symbol in (
    "CCBGApplyQuickConfigurationChanges",
    "CCBGUndoLastQuickConfiguration",
    "CCBGQuickConfigurationHistory",
    "CCBGClearQuickConfigurationHistory",
):
    assert symbol in HEADER and symbol in SHARED, symbol
apply_body = SHARED.split("BOOL CCBGApplyQuickConfigurationChanges", 1)[1].split(
    "BOOL CCBGUndoLastQuickConfiguration", 1
)[0]
assert "CCBGQuickConfigurationUndoStackKey" in apply_body
assert "NSPropertyListSerialization" in apply_body
assert "NSNull.null" in apply_body
assert "20" in apply_body
assert apply_body.count("CCBGWritePreferences(") == 1
undo_body = SHARED.split("BOOL CCBGUndoLastQuickConfiguration", 1)[1].split(
    "void CCBGClearQuickConfigurationHistory", 1
)[0]
assert undo_body.count("CCBGWritePreferences(") == 1
assert "missingKeys" in undo_body


# Quick apply, multi-module media assignment, and copy are complete actions,
# not navigation-only placeholders.
for token in (
    "applyMediaToSlots",
    "copyConfigurationFromSlot",
    "CCBGModuleConfigurationKeys",
    "forcePreferenceMediaOnReload",
    "批量设置素材",
    "复制模块设置",
):
    assert token in QUICK, token
assert "CCBGApplyQuickConfigurationChanges" in QUICK


# Templates restore an exact validated configuration snapshot, while profile
# snapshots do not recursively capture the undo stack or template list.
profile_apply = ADVANCED.split("static BOOL CCBGApplyProfilePreferences", 1)[1].split(
    "static dispatch_queue_t CCBGInsightsAnalysisQueue", 1
)[0]
assert "CCBGRestorePreferencesSnapshot" in profile_apply
assert 'preferences[@"configurationProfiles"]' in profile_apply
profile_snapshot = ADVANCED.split("static NSDictionary *CCBGProfilePreferencesSnapshot", 1)[1].split(
    "static BOOL CCBGApplyProfilePreferences", 1
)[0]
assert 'removeObjectForKey:@"quickConfigurationUndoStack"' in profile_snapshot
assert "配置模板与回滚" in QUICK


# Favorites/recent are first-class picker scopes, and the quick workspace has
# direct entries for preview, adaptation, and media batch editing.
assert 'scopeButtonTitles = @[@"全部", @"收藏", @"最近"]' in CONTROLS
assert 'item[@"favorite"]' in CONTROLS
assert 'item[@"lastPlayedAt"]' in CONTROLS
for label in ("预览当前素材", "素材适配助手", "素材批量编辑"):
    assert label in QUICK


# Effective state and conflict explanations use the real scene matcher.
for symbol in ("CCBGSceneDirectorMatchingScenes", "CCBGSceneDirectorEvaluationForScene"):
    assert symbol in HEADER and symbol in SHARED, symbol
for label in ("当前生效状态", "自动化冲突", "未命中原因", "禁用其他命中场景"):
    assert label in QUICK


# Three performance presets update every independent five-module slot in one
# transaction, and the selected preset is shown in the workspace.
for label in ("流畅", "均衡", "画质"):
    assert label in QUICK
for key in ("preloadEnabled", "performanceMode", "transitionStyle", "crossfadeDuration"):
    assert key in QUICK
assert "for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++)" in QUICK


# The quick adaptation assistant is an editor with live composition controls
# and an undoable module-scoped apply operation.
adaptation = QUICK.split("@implementation CCBGQuickCompositionController", 1)[1].split(
    "@interface CCBGQuickConfigController", 1
)[0]
for token in ("UISegmentedControl", "焦点 X", "焦点 Y", "应用到当前模块", "mediaOverrides", "CCBGApplyQuickConfigurationChanges"):
    assert token in adaptation, token


print("Quick configuration workspace regression checks passed")
