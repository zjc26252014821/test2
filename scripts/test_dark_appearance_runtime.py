from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")
HEADER = (ROOT / "shared" / "CCBGMediaCatalog.h").read_text(encoding="utf-8")
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
DIAGNOSTICS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")


# iOS 16 Control Center module traits can be locally forced to light. The
# resolver must use a system-level main-screen trait first, then fall back to
# persisted/global values for background prewarming.
resolver = SHARED.split("static BOOL CCBGResolveDarkAppearance", 1)[1].split(
    "BOOL CCBGSystemUsesDarkAppearance", 1
)[0]
screen_trait = "UIScreen.mainScreen.traitCollection.userInterfaceStyle"
current_trait = "UITraitCollection.currentTraitCollection.userInterfaceStyle"
assert screen_trait in resolver
assert current_trait in resolver
assert resolver.index(screen_trait) < resolver.index('CFSTR("AppleInterfaceStyle")')
assert 'CCBGReadPreference(@"sceneDirectorLastRuntimeContext"' in resolver


# The exact winning source must be exported so a device diagnostic can
# distinguish a bad UIKit trait from a missing global preference.
assert "CCBGDarkAppearanceDiagnostics" in HEADER
assert "CCBGDarkAppearanceDiagnostics" in SHARED
assert '@"darkAppearance": @{' in DIAGNOSTICS
assert 'CCBGReadPreference(@"sceneDirectorLastDarkAppearanceDiagnostics"' in DIAGNOSTICS
assert "CCBGDarkAppearanceDiagnostics()" in DIAGNOSTICS


# Observe both known UIKit Darwin spellings in custom modules and overlays.
notification = '@"com.apple.UIKit.userInterfaceStyleChanged"'
assert notification in MODULE
assert notification in OVERLAY


print("Dark appearance runtime source and diagnostics regression checks passed")
