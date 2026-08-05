from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    shared = source("shared/CCBGMediaCatalog.m")
    app = source("app/CCBGVisualFeaturesControllers.m")
    overlay = source("systemoverlay/CleanCCBGSystemOverlays.m")
    module = source("module/CleanCCBG2x2.m")
    theme_module = source("utilitytheme/CleanCCBGThemeSwitcher.m")

    automation = block(shared, "BOOL CCBGApplyVisualThemeAutomationIfNeeded", "BOOL CCBGRestorePreferencesSnapshot")
    assert "visualThemeRandomOnOpen" in automation
    assert "CCBGApplyRandomVisualTheme" in automation
    assert "visualThemeWallpaperSyncEnabled" not in automation
    assert "visualThemeAutomationSuppressedUntil" not in automation

    themes = block(app, "@implementation CCBGVisualThemesController", "@end")
    assert "打开控制中心时随机" in themes
    assert "按壁纸颜色匹配主题" not in themes
    assert "visualThemeWallpaperSyncEnabled" not in themes

    assert "CCUIModularControlCenterOverlayViewController" in overlay
    assert "CCBGHookControlCenterPresentationClass" in overlay
    assert "CCBGApplyVisualThemeAutomationIfNeeded(controller.view)" in overlay
    module_appear = block(module, "- (void)viewWillAppear:(BOOL)animated", "- (void)viewDidAppear:(BOOL)animated")
    assert "CCBGApplyVisualThemeAutomationIfNeeded" not in module_appear
    assert "CCBGApplyVisualThemeAutomationIfNeeded" not in theme_module

    snapshot_capture = block(shared, "CCBGCaptureVisualTheme(NSString *name)", "BOOL CCBGSaveVisualTheme")
    snapshot_save = block(shared, "BOOL CCBGSaveVisualTheme", "static void CCBGRecordVisualThemeResult")
    assert "visualThemeAutomationSuppressedUntil" not in snapshot_capture
    assert "visualThemeAutomationSuppressedUntil" not in snapshot_save

    print("Random theme Control Center open trigger checks passed")


if __name__ == "__main__":
    main()
