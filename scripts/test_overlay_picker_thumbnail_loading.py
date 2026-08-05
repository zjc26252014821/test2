from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")


def implementation_body(start: str, end: str) -> str:
    return SOURCE.rsplit(start, 1)[1].split(end, 1)[0]


def test_picker_cells_never_read_media_synchronously() -> None:
    cell_body = implementation_body("- (UITableViewCell *)tableView:", "- (void)tableView:")
    assert "CCBGOverlayPickerThumbnailForItem(item)" not in cell_body
    assert "[self cachedOverlayPickerThumbnailForItem:item]" in cell_body
    assert "[self loadOverlayPickerThumbnailForItem:item]" in cell_body


def test_picker_thumbnail_loading_is_cached_and_backgrounded() -> None:
    assert "@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;" in SOURCE
    assert "@property(nonatomic, strong) NSMutableSet<NSString *> *thumbnailRequests;" in SOURCE
    loader = implementation_body("- (void)loadOverlayPickerThumbnailForItem:", "- (void)tableView:")
    assert "dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)" in loader
    assert "CCBGOverlayPickerThumbnailForItem(snapshot)" in loader
    assert "dispatch_async(dispatch_get_main_queue(), ^{" in loader
    thumbnail_helper = SOURCE.split("static UIImage *CCBGOverlayPickerThumbnailForItem", 1)[1].split("@implementation CCBGOverlayMediaPickerController", 1)[0]
    assert "CGImageSourceCreateThumbnailAtIndex" in thumbnail_helper
    assert "_thumbnailCache.totalCostLimit = 12 * 1024 * 1024;" in SOURCE


if __name__ == "__main__":
    test_picker_cells_never_read_media_synchronously()
    test_picker_thumbnail_loading_is_cached_and_backgrounded()
    print("Overlay picker thumbnail loading checks passed")
