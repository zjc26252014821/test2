from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE = (ROOT / "module" / "CleanCCBG2x2.m").read_text(encoding="utf-8")
OVERLAY = (ROOT / "systemoverlay" / "CleanCCBGSystemOverlays.m").read_text(encoding="utf-8")
SHARED = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")


# CCAster's edit-mode resize path is intentionally separate. Clean keeps its
# own compact-module drag handle, while the preview frame is reset before an
# expanded transition so compact resizing cannot alter expanded presentation.
assert "self.view.frame =" not in MODULE.rsplit("- (void)handleResizePan:", 1)[1].split("- (BOOL)gestureRecognizer:", 1)[0]
assert "resetLiveResizePreviewBeforeExpansion" not in MODULE
assert "[self.view bringSubviewToFront:self.resizeButton];" in MODULE
assert "CCBGIsCCAsterEditModeActive" in MODULE
assert "kCCBGCCAsterEditShieldTag" in MODULE
assert "CCBGIsCCAsterEditModeActive(self.view)" in MODULE
assert "gestureRecognizer == self.resizePan" in MODULE
ccaster_read = MODULE.rsplit("static BOOL CCBGReadCCAsterGridSize", 1)[1].split("static CCUILayoutSize CCBGRuntimeModuleSize", 1)[0]
assert "CFPreferencesAppSynchronize(domain);" in ccaster_read
assert "CCBGHasCachedCCAsterGridSizes" in ccaster_read
size_reload_callback = MODULE.rsplit("static void CCBGSizeReloadCallback(", 1)[1].split("static void CCBGPresentationRecoveryCallback(", 1)[0]
assert "CCBGHasCachedCCAsterGridSizes = NO;" in size_reload_callback
assert "CCBGSyncCCAsterGridSizeIfPresent" in SHARED
assert "com.futur3sn0w.ccaster/ReloadPrefs" in SHARED
restore_snapshot = SHARED.rsplit("BOOL CCBGRestorePreferencesSnapshot", 1)[1].split("BOOL CCBGClearAllConfigurationPreservingMedia", 1)[0]
assert "CCBGSyncCCAsterGridSizeIfPresent(values);" in restore_snapshot

# The Clean drag preview must map visual axes back to logical grid axes in
# landscape and clamp the temporary frame to its host bounds.
resize = MODULE.rsplit("- (void)handleResizePan:", 1)[1].split("- (BOOL)gestureRecognizer:", 1)[0]
assert "landscape ? translation.y : translation.x" in resize
assert "landscape ? translation.x : translation.y" in resize
ended = resize.split("if (recognizer.state == UIGestureRecognizerStateEnded)", 1)[1].split("} else if (recognizer.state", 1)[0]
assert "clearLiveResizePreviewRestoringOriginalFrame:YES" in ended
assert "scheduleResizeLayoutRecovery" in ended
layout_recovery = MODULE.rsplit("- (void)scheduleResizeLayoutRecovery", 1)[1].split("- (void)showResizeFeedbackForWidth:", 1)[0]
assert "CCBGRequestControlCenterSizeReload();" in layout_recovery
assert "requestControlCenterLayoutSizeUpdate" in layout_recovery
assert "CCBGHasCachedRuntimeGridSize = NO;" in layout_recovery
preview = MODULE.rsplit("- (void)applyLiveResizePreviewForTranslation:", 1)[1].split("- (void)clearLiveResizePreviewRestoringOriginalFrame:", 1)[0]
assert "self.view.superview" in preview
assert "CGRectGetMaxX(hostBounds)" in preview
external_size = MODULE.rsplit("- (void)handleExternalGridSizeReload", 1)[1].split("- (void)requestControlCenterLayoutSizeUpdate", 1)[0]
assert "CCBGReadModulePreference(@\"gridWidth\"" in external_size
assert "CCBGModulePreference(@\"gridWidth\"" not in external_size

print("Clean resize regression checks passed")
