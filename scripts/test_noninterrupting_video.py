from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def method_block(text: str, start: str, end: str) -> str:
    return text.rsplit(start, 1)[1].split(end, 1)[0]


def main() -> None:
    header = source("shared/CCBGMediaCatalog.h")
    shared = source("shared/CCBGMediaCatalog.m")
    module = source("module/CleanCCBG2x2.m")
    overlay = source("systemoverlay/CleanCCBGSystemOverlays.m")
    preview = source("app/CCBGPreviewController.m")

    assert "CCBGLoadVideoOnlyAsset" in header
    loader = method_block(
        shared,
        "static NSCache<NSString *, AVAsset *> *CCBGVideoOnlyAssetCache",
        "NSString *CCBGPathForItem",
    )
    assert "AVMutableComposition" in loader
    assert "AVAssetExportSession" in loader
    assert "AVAssetExportPresetPassthrough" in loader
    assert "VideoOnlyCache" in loader
    assert "AVURLAsset URLAssetWithURL:outputURL" in loader
    assert "tracksWithMediaType:AVMediaTypeVideo" in loader
    assert "tracksWithMediaType:AVMediaTypeAudio" not in loader
    assert "dispatch_get_main_queue()" in loader
    assert "CCBGFinishVideoOnlyAssetLoad(cacheKey, composition" not in loader

    module_playback = method_block(module, "- (void)showCurrentMediaWithTransition:", "- (void)preloadNextMedia")
    overlay_playback = method_block(overlay, "- (void)reloadIfNeeded:(BOOL)force", "- (void)reloadAfterPreferenceChange")
    preview_playback = method_block(preview, "- (void)loadMedia", "- (void)videoEnded:")

    for name, block in (("module", module_playback), ("overlay", overlay_playback), ("preview", preview_playback)):
        assert "CCBGLoadVideoOnlyAsset" in block, name
        assert "CCBGSilentAudioMixForLoadedAsset" not in block, name
        assert ".audioMix" not in block, name
        assert "preventsDisplaySleepDuringVideoPlayback = NO" in block, name

    assert "AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]" not in preview_playback
    overlay_install = method_block(overlay_playback, "void (^installVideoOnlyAsset)", "if (preloadedAsset)")
    assert "[self.player playImmediatelyAtRate:self.playbackRate]" not in overlay_install
    assert "[self schedulePlaybackReadinessCheck:self.playbackGeneration attempt:0]" in overlay_install
    print("Non-interrupting video regression checks passed")


if __name__ == "__main__":
    main()
