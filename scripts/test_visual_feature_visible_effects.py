from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    module = source("module/CleanCCBG2x2.m")
    visual_ui = source("app/CCBGVisualFeaturesControllers.m")
    shared = source("shared/CCBGMediaCatalog.m")
    theme_module = source("utilitytheme/CleanCCBGThemeSwitcher.m")

    appearance = module.rsplit("- (void)applyModuleAppearance", 1)[1].split("- (void)presentMediaSelectionList", 1)[0]
    assert "dynamicTintView" in module
    assert "dynamicTintView.backgroundColor" in appearance
    assert "dynamicTintView.alpha" in appearance
    assert "MAX(2.0" in appearance

    presets = block(visual_ui, "@implementation CCBGVisualStylePresetsController", "@end")
    assert "CCBGModuleDisplayNames()" in presets
    assert "UIAlertControllerStyleActionSheet" in presets
    assert "CCBGApplyVisualStylePreset" in presets
    assert "应用成功" in presets

    themes = block(visual_ui, "@implementation CCBGVisualThemesController", "@end")
    assert "CCBGEligibleVisualThemeCount" in themes
    assert "至少保存两个不同主题" in themes
    assert "visualThemeLastResult" in visual_ui
    assert "随机切换状态" in themes
    assert "将改变" in themes

    shortcuts = block(visual_ui, "@implementation CCBGShortcutActionsController", "@end")
    assert "立即执行" in shortcuts
    assert "复制 URL" in shortcuts
    assert "openURL" in shortcuts

    automation = block(shared, "BOOL CCBGApplyVisualThemeAutomationIfNeeded", "BOOL CCBGRestorePreferencesSnapshot")
    assert "visualThemeLastResult" in shared
    assert "CCBGApplyRandomVisualTheme" in automation
    assert "wallpaper-color-unavailable" not in automation
    assert "no-matching-theme" not in automation

    assert "[self reloadThemes]" in block(theme_module, "- (void)viewWillAppear", "- (void)viewDidLoad")
    cycle = theme_module.rsplit("- (void)cycleTheme", 1)[1].split("- (void)setExpanded", 1)[0]
    assert "UINotificationFeedbackGenerator" in cycle

    print("Visual feature visible-effect contracts passed")


if __name__ == "__main__":
    main()
