from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")


def blur_body(source: str) -> str:
    start = source.index("static void CCBGApplyGaussianBlurToLayer")
    end = source.index("\n}\n", start) + 2
    return source[start:end]


for source in (MODULE, OVERLAY):
    body = blur_body(source)
    assert "CCBGAppliedGaussianBlurFilterKey" in source
    assert "layer.filters.count == 1" in body
    assert "appliedFilter && layer.filters.firstObject == appliedFilter" in body
    assert body.count("[CATransaction setDisableActions:YES]") >= 2
    clear_index = body.index("layer.filters = nil;")
    assign_index = body.index("layer.filters = @[filter];")
    assert clear_index < assign_index
    assert "objc_setAssociatedObject(layer, &CCBGAppliedGaussianBlurFilterKey" in body

cleanup = OVERLAY.split("static void CCBGRemoveStaleOverlaysForHost", 1)[1].split("static void CCBGTrackOverlayController", 1)[0]
assert "candidate.superview != hostView" in cleanup
assert "candidate.hostController == controller" in cleanup
assert "CCBGDetachOverlayViewNow(candidate)" in cleanup
assert "CCBGRemoveStaleOverlaysForHost(hostView, kind, overlay, controller);" in OVERLAY

print("Blur filters are replaced atomically and stale same-host overlays are removed.")
