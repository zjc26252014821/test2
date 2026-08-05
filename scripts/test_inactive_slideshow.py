from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")

def method_body(name: str, next_name: str) -> str:
    return SOURCE.split(name, 1)[1].split(next_name, 1)[0]

def test_disappearing_module_cancels_slideshow_timer() -> None:
    body = method_body("- (void)viewDidDisappear:", "- (void)traitCollectionDidChange:")
    assert "[self.slideTimer invalidate];" in body
    assert "self.slideTimer = nil;" in body

def test_slideshow_timer_does_not_advance_an_unmounted_module() -> None:
    body = method_body("- (void)configureSlideshow", "- (void)advanceBy:")
    assert "if (!weakSelf || !weakSelf.visible || !weakSelf.view.window) return;" in body

def test_automatic_advance_requires_a_visible_mounted_module() -> None:
    body = method_body("- (void)advanceBy:", "@end")
    assert "if (!self.visible || !self.view.window) return;" in body

if __name__ == "__main__":
    test_disappearing_module_cancels_slideshow_timer()
    test_slideshow_timer_does_not_advance_an_unmounted_module()
    test_automatic_advance_requires_a_visible_mounted_module()
    print("Inactive slideshow lifecycle checks passed")
