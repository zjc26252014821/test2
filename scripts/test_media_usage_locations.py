from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> None:
    detail = source("app/CCBGMediaDetailController.m")
    for token in (
        "CCBGPreferenceValueContainsMediaName",
        '@"查看使用位置"',
        "showMediaUsageLocations",
        "mediaUsageLocations",
        "usageLabelForPreferenceKey",
        "CCBGReadAllPreferences()",
        '@"mediaCatalog"',
        '@".mediaOverrides"',
        '@"五模块 · %@ · %@"',
        '@"系统模块 · %@ · %@"',
        '@"场景导演"',
        '@"播放列表"',
        '@"配置方案"',
        '@"此素材仍被 %lu 处配置引用。删除后这些位置将无法继续使用它。',
    ):
        assert token in detail, token

    usage = detail.split("- (NSArray<NSString *> *)mediaUsageLocations", 1)[1].split("- (void)showMediaUsageLocations", 1)[0]
    assert "CCBGWrite" not in usage
    assert "CCBGPostReload" not in usage
    assert "CCBGSave" not in usage

    print("Media usage location regression checks passed")


if __name__ == "__main__":
    main()
