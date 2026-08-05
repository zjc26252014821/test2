from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")


def body(start: str, end: str) -> str:
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


def test_presentation_host_must_own_the_overlay() -> None:
    host_body = body("- (UIViewController *)nativePlayerPresentationHost", "- (void)updateNativePlayerPresentation")
    assert "return self.hostController;" not in host_body
    assert "return nil;" in host_body


def test_update_keeps_avkit_unmounted_without_a_valid_host() -> None:
    update_body = SOURCE.rsplit("- (void)updateNativePlayerPresentation", 1)[1].split("- (void)scheduleNativePlayerPresentationRecovery", 1)[0]
    guard = "if (hasVideo && !host)"
    assert guard in update_body
    assert update_body.index(guard) < update_body.index("AVPlayerViewController *controller = [AVPlayerViewController new];")
    no_host_block = update_body.split(guard, 1)[1].split("AVPlayerViewController *controller", 1)[0]
    assert "[self scheduleNativePlayerPresentationRecovery];" in no_host_block
    assert "[self detachNativePlayerForCompactPresentation];" not in no_host_block


def test_recovery_never_reparents_avkit_view_without_a_controller_host() -> None:
    recovery = SOURCE.rsplit("- (void)scheduleNativePlayerPresentationRecovery", 1)[1].split("- (void)detachNativePlayerForCompactPresentation", 1)[0]
    assert "UIViewController *presentationHost = [self nativePlayerPresentationHost];" in recovery
    assert "if (!presentationHost)" in recovery
    assert "native.parentViewController != presentationHost" in recovery
    assert "@2.80" in recovery


if __name__ == "__main__":
    test_presentation_host_must_own_the_overlay()
    test_update_keeps_avkit_unmounted_without_a_valid_host()
    test_recovery_never_reparents_avkit_view_without_a_controller_host()
    print("Overlay native-player containment checks passed")
