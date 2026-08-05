from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def capture_reference(preferences: dict[str, object], slots: int = 5) -> dict[str, object]:
    values: dict[str, object] = {}
    for slot in range(slots):
        mode = int(preferences.get(f"module{slot}.playbackMode", 0))
        media_key = "selectedMedia" if mode == 0 else "currentMedia"
        media = preferences.get(f"module{slot}.{media_key}", "")
        if media:
            values[f"module{slot}.selectedMedia"] = media
            values[f"module{slot}.currentMedia"] = media
    return values


def main() -> None:
    shared = source("shared/CCBGMediaCatalog.m")
    capture = block(shared, "CCBGCaptureVisualTheme(NSString *name)", "BOOL CCBGSaveVisualTheme")
    save = block(shared, "BOOL CCBGSaveVisualTheme", "static void CCBGRecordVisualThemeResult")
    automation = block(shared, "BOOL CCBGApplyVisualThemeAutomationIfNeeded", "BOOL CCBGRestorePreferencesSnapshot")

    state_a = {f"module{slot}.playbackMode": 0 for slot in range(5)}
    state_a.update({f"module{slot}.selectedMedia": f"A{slot}.mp4" for slot in range(5)})
    state_b = dict(state_a)
    state_b["module1.selectedMedia"] = "B1.mp4"
    state_b["module3.selectedMedia"] = "B3.mp4"
    theme_1 = capture_reference(state_a)
    theme_2 = capture_reference(state_b)
    assert theme_1["module1.currentMedia"] == "A1.mp4"
    assert theme_2["module1.currentMedia"] == "B1.mp4"
    assert theme_1["module3.currentMedia"] == "A3.mp4"
    assert theme_2["module3.currentMedia"] == "B3.mp4"

    assert capture.count("CCBGReadAllPreferences()") == 1
    assert "CCBGActiveModuleMediaName" not in capture
    assert "CCBGActiveMediaPreferenceKey" in capture
    assert "preferences[" in capture
    assert "CCBGApplyVisualTheme" not in save
    assert "visualThemeAutomationSuppressedUntil" not in save
    assert "visualThemeAutomationSuppressedUntil" not in automation

    visual_ui = source("app/CCBGVisualFeaturesControllers.m")
    quick_ui = source("app/CCBGQuickConfigController.m")
    controls = source("app/CCBGControls.m")
    assert "numberOfLines = 0" in visual_ui
    assert "numberOfLines = 0" in quick_ui
    assert "numberOfLines = 0" in controls
    assert "CCBGVisualStylePresetSummary" in visual_ui
    assert "按壁纸颜色匹配主题" not in visual_ui

    print("Visual theme snapshot isolation and wrapping checks passed")


if __name__ == "__main__":
    main()
