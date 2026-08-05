from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    shared = source("shared/CCBGMediaCatalog.m")
    header = source("shared/CCBGMediaCatalog.h")
    module = source("module/CleanCCBG2x2.m")
    overlay = source("systemoverlay/CleanCCBGSystemOverlays.m")

    loader_support = block(
        shared,
        "static NSCache<NSString *, AVAsset *> *CCBGVideoOnlyAssetCache",
        "NSString *CCBGPathForItem",
    )
    for token in (
        "CCBGValidateVideoOnlyAsset",
        '@[@"playable", @"tracks", @"duration"]',
        "tracksWithMediaType:AVMediaTypeVideo",
        "CCBGRemoveVideoOnlyDiskCache",
        "removeItemAtPath",
    ):
        assert token in loader_support, token

    loader = block(
        shared,
        "void CCBGLoadVideoOnlyAsset",
        "NSString *CCBGPathForItem",
    )
    cached_asset_path = block(
        loader,
        "NSURL *outputURL = [NSURL fileURLWithPath:cachedPath]",
        "CCBGRemoveVideoOnlyDiskCache(cacheBasePath);",
    )
    assert "CCBGValidateVideoOnlyAsset" in cached_asset_path
    assert cached_asset_path.index("CCBGValidateVideoOnlyAsset") < cached_asset_path.index(
        "CCBGFinishVideoOnlyAssetLoad"
    )

    export_helper = block(
        loader_support,
        "static void CCBGExportVideoOnlyAsset",
        "void CCBGLoadVideoOnlyAsset",
    )
    exported_asset_path = block(
        export_helper,
        "NSURL *outputURL = [NSURL fileURLWithPath:finalPath]",
        "dispatch_semaphore_signal(finished)",
    )
    assert "CCBGValidateVideoOnlyAsset" in exported_asset_path

    assert "CCBGInvalidateVideoOnlyAssetCache" in header
    invalidation = block(
        shared,
        "void CCBGInvalidateVideoOnlyAssetCache",
        "static void CCBGExportVideoOnlyAsset",
    )
    assert "loadInProgress" in invalidation
    assert "if (!loadInProgress) CCBGRemoveVideoOnlyDiskCache" in invalidation
    module_failure = block(
        module,
        "- (void)handleVideoPlaybackFailureForItem:",
        "- (void)showCurrentMediaWithTransition:",
    )
    assert "CCBGInvalidateVideoOnlyAssetCache" in module_failure

    overlay_failure = block(
        overlay,
        "- (void)handlePlaybackFailure",
        "- (void)videoEnded:",
    )
    assert "CCBGInvalidateVideoOnlyAssetCache" in overlay_failure
    assert "[self playbackMode] == 0" in overlay_failure
    assert overlay_failure.index("[self playbackMode] == 0") < overlay_failure.index(
        "advanceAutomaticallyBy"
    )

    print("Video-only cache recovery regression checks passed")


if __name__ == "__main__":
    main()
