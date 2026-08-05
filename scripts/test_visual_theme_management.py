from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    visual_ui = source("app/CCBGVisualFeaturesControllers.m")
    themes = block(visual_ui, "@implementation CCBGVisualThemesController", "@end")

    for token in (
        'initWithTitle:@"排序"',
        "toggleThemeReordering",
        "canMoveRowAtIndexPath",
        "moveRowAtIndexPath",
        'CCBGWriteMetadataPreference(@"visualThemes", themes)',
        'actionWithTitle:@"复制主题"',
        "duplicateTheme:",
        "NSUUID.UUID.UUIDString",
        'copy[@"pinned"] = @NO',
        'actionWithTitle:@"重命名主题"',
        "renameTheme:",
        '@"管理随机池"',
        '@"全部加入随机池"',
        '@"全部暂停随机"',
        '@"全部权重恢复为 1.0"',
        "resetAllThemeWeights",
        "setAllThemesRandomEnabled:",
    ):
        assert token in themes, token

    duplicate = block(themes, "- (void)duplicateTheme:", "- (void)setAllThemesRandomEnabled:")
    assert "CCBGSaveVisualTheme(copy)" in duplicate
    assert "CCBGApplyVisualTheme" not in duplicate

    reorder = block(themes, "moveRowAtIndexPath:", "- (void)duplicateTheme:")
    assert "CCBGWriteMetadataPreference" in reorder
    assert "CCBGPostReload" not in reorder

    print("Visual theme management regression checks passed")


if __name__ == "__main__":
    main()
