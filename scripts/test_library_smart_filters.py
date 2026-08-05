from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "app" / "CCBGRootController.m").read_text(encoding="utf-8")


# The library uses only catalog metadata already maintained by the runtime.
# Recent playback is ordered by the real playback timestamp and failures map to
# the explicit failure quarantine marker, without scanning media files.
assert '@"全部", @"图片", @"视频", @"收藏", @"最近", @"故障"' in SOURCE
filters = SOURCE.split("- (void)applyMediaFilters", 1)[1].split(
    "- (void)updateSearchResultsForSearchController", 1
)[0]
assert 'scope == 4 && [item[@"lastPlayedAt"] doubleValue] <= 0' in filters
assert 'scope == 5 && ![item[@"failureReason"] length]' in filters
assert "if (scope == 4)" in filters
assert '[right[@"lastPlayedAt"] compare:left[@"lastPlayedAt"]]' in filters
assert "CCBGPathForItem" not in filters
assert "NSFileManager" not in filters

print("Library smart filter regression checks passed")
