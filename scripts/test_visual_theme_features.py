from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    header = source("shared/CCBGMediaCatalog.h")
    shared = source("shared/CCBGMediaCatalog.m")
    app_delegate = source("app/CleanCCBG2x2App.m")
    app_header = source("app/CCBGAppControllers.h")
    app_plist = source("app/Info.plist")
    app_makefile = source("app/Makefile")
    root_makefile = source("Makefile")

    for api in (
        "CCBGVisualThemes",
        "CCBGSaveVisualTheme",
        "CCBGCaptureVisualTheme",
        "CCBGApplyVisualTheme",
        "CCBGApplyRandomVisualTheme",
    ):
        assert api in header, api

    capture = block(shared, "CCBGCaptureVisualTheme(NSString *name)", "BOOL CCBGSaveVisualTheme")
    assert "CCBGModuleVisualThemeKeys" in capture
    assert "CCBGDefaultModuleVisualThemeValue" in capture
    assert "CCBGSystemMediaReferenceKeys" in capture
    assert 'CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload"' in capture
    assert "CCBGActiveModuleMediaName" not in capture
    assert "CCBGActiveMediaPreferenceKey(playbackMode)" in capture
    defaults = block(shared, "static id CCBGDefaultModuleVisualThemeValue", "static NSArray<NSDictionary<NSString *, id> *> *CCBGSanitizedNamedConfigurations")
    expected_defaults = {
        "moduleCornerRadius": "@0",
        "moduleInset": "@0",
        "moduleBorderWidth": "@0",
        "moduleBorderColor": '@"#FFFFFF"',
        "moduleMaskDim": "@0",
        "moduleOpacity": "@1",
        "moduleBlurIntensity": "@0",
        "fallbackColor": '@"#193D61"',
        "foregroundAppTintEnabled": "@NO",
        "wallpaperTintEnabled": "@NO",
        "dynamicTintTarget": "@0",
        "dynamicTintStrength": "@0.65",
    }
    for key, value in expected_defaults.items():
        assert f'@"{key}": {value}' in defaults, key
    assert "values[playbackModeKey]" not in capture
    for forbidden in ("compactDoubleTapAction", "gridWidth", "compoundRules"):
        assert forbidden not in capture, forbidden
    save_theme = block(shared, "BOOL CCBGSaveVisualTheme", "BOOL CCBGApplyVisualTheme")
    assert "CCBGWriteMetadataPreference" in save_theme
    assert "CCBGWritePreference" not in save_theme

    apply_theme = block(shared, "BOOL CCBGApplyVisualTheme", "BOOL CCBGApplyRandomVisualTheme")
    assert "CCBGApplyQuickConfigurationChanges" in apply_theme
    assert "CCBGRestorePreferencesSnapshot" not in apply_theme
    assert "CCBGReplaceAllPreferences" not in apply_theme

    random_theme = block(shared, "BOOL CCBGApplyRandomVisualTheme", "NSArray<NSDictionary *> *CCBGVisualStylePresets")
    assert 'theme[@"enabled"]' in random_theme
    assert 'theme[@"randomWeight"]' in random_theme
    assert "CCBGApplyVisualTheme" in random_theme

    assert "CFBundleURLTypes" in app_plist
    assert "cleanccbg" in app_plist
    assert "application:(UIApplication *)application openURL:" in app_delegate
    url_handler = block(app_delegate, "- (BOOL)handleShortcutURL:", "- (BOOL)application:(UIApplication *)application openURL:")
    for token in (
        "NSURLComponents",
        "CCBGApplyVisualTheme",
        "CCBGApplyRandomVisualTheme",
        "CCBGSelectModuleMedia",
        "CCBGSetPluginEnabled",
    ):
        assert token in url_handler, token
    assert "CFPreferencesSet" not in url_handler
    assert "CCBGShortcutActionsController" in app_header
    assert "CCBGVisualFeaturesControllers.m" in app_makefile
    assert "utilitytheme" in root_makefile

    visual_ui = source("app/CCBGVisualFeaturesControllers.m")
    for controller in (
        "CCBGVisualThemesController",
        "CCBGVisualStylePresetsController",
        "CCBGShortcutActionsController",
    ):
        assert f"@implementation {controller}" in visual_ui, controller
    for token in (
        "CCBGCaptureVisualTheme",
        "CCBGSaveVisualTheme",
        "CCBGApplyVisualTheme",
        "CCBGApplyRandomVisualTheme",
        'UIPasteboard.generalPasteboard.string',
    ):
        assert token in visual_ui, token

    theme_module = source("utilitytheme/CleanCCBGThemeSwitcher.m")
    assert "CleanCCBGThemeSwitcherModule" in theme_module
    assert "CCBGVisualThemes" in theme_module
    assert "CCBGApplyVisualTheme" in theme_module
    assert "CCBGApplyRandomVisualTheme" in theme_module
    assert "CCBGRestorePreferencesSnapshot" not in theme_module

    media_detail = source("app/CCBGMediaDetailController.m")
    module = source("module/CleanCCBG2x2.m")
    overlay = source("systemoverlay/CleanCCBGSystemOverlays.m")
    for key in (
        "compactContentMode",
        "expandedContentMode",
        "compactFocalX",
        "compactFocalY",
        "expandedFocalX",
        "expandedFocalY",
        "compactCropZoom",
        "expandedCropZoom",
    ):
        assert f'@"{key}"' in shared, key
    apply_display = block(module, "- (void)applyDisplayForItem:", "- (UIImage *)filteredImageAtPath:")
    assert 'self.expanded ? @"expandedContentMode" : @"compactContentMode"' in apply_display
    assert 'self.expanded ? @"expandedCropZoom" : @"compactCropZoom"' in apply_display
    overlay_reload = overlay.rsplit("- (void)reloadIfNeeded:(BOOL)force", 1)[1].split("- (void)reloadAfterPreferenceChange", 1)[0]
    assert 'self.expandedPresentation ? @"expandedContentMode" : @"compactContentMode"' in overlay_reload
    assert 'self.expandedPresentation ? @"expandedCropZoom" : @"compactCropZoom"' in overlay_reload

    assert "@implementation CCBGCompositionEditorController" in visual_ui
    composition_editor = block(visual_ui, "@implementation CCBGCompositionEditorController", "@end")
    for token in (
        "UIPinchGestureRecognizer",
        "UIPanGestureRecognizer",
        "CCBGLoadVideoOnlyAsset",
        "CCBGSaveModuleMediaConfiguration",
        "presentationPrefix",
        'stringByAppendingString:@"CropZoom"',
        "changesCommitted",
        "commitChanges",
        "initWithSystemMediaItem",
        "systemPreferenceKeyForSuffix",
    ):
        assert token in composition_editor, token
    assert '@[@2, @2], @[@1, @2], @[@2, @3], @[@3, @2], @[@3, @3]' in composition_editor
    assert 'CCBGReadModulePreference(@"adaptiveExpandedSizeEnabled"' in composition_editor
    assert "naturalMediaSize.width / self.naturalMediaSize.height" in composition_editor
    assert "saveAndClose { [self commitChanges]" in composition_editor
    assert "viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self commitChanges]" in composition_editor
    assert composition_editor.count("CCBGSaveModuleMediaConfiguration") == 1
    assert "CCBGCompositionEditorController" in media_detail
    detail_refresh = block(media_detail, "- (void)viewWillAppear:(BOOL)animated", "- (void)viewWillDisappear:(BOOL)animated")
    assert "CCBGMediaItemNamed(CCBGLoadMediaCatalog(), fileName)" in detail_refresh
    assert "CCBGMediaItemForModule(sharedItem, self.moduleSlot)" in detail_refresh

    for api in ("CCBGResolvedDynamicPaletteColor", "CCBGApplyVisualThemeAutomationIfNeeded"):
        assert api in header, api
    assert '@"paletteHex"' in capture
    automation = block(shared, "BOOL CCBGApplyVisualThemeAutomationIfNeeded", "BOOL CCBGRestorePreferencesSnapshot")
    for token in (
        "visualThemeRandomOnOpen",
        "CCBGApplyRandomVisualTheme",
        "visualThemeAutomationLastClaimAt",
        "CCBGWriteMetadataPreference",
    ):
        assert token in automation, token
    assert "visualThemeWallpaperSyncEnabled" not in automation
    assert "CCBGApplyVisualThemeAutomationIfNeeded(self.view)" not in module
    assert "CCBG_MODULE_SLOT == 0" not in module
    appearance = module.rsplit("- (void)applyModuleAppearance", 1)[1].split("- (void)presentMediaSelectionList", 1)[0]
    assert "CCBGResolvedDynamicPaletteColor" in appearance
    assert "foregroundAppTintEnabled" in appearance
    assert "wallpaperTintEnabled" in appearance

    advanced = source("app/CCBGAdvancedControllers.m")
    appearance_ui = block(advanced, "@implementation CCBGModuleAppearanceController", "@end")
    for key in ("foregroundAppTintEnabled", "wallpaperTintEnabled", "dynamicTintTarget", "dynamicTintStrength"):
        assert key in appearance_ui, key
        assert key in shared, key
    themes_ui = block(visual_ui, "@implementation CCBGVisualThemesController", "@end")
    assert "visualThemeRandomOnOpen" in themes_ui
    assert "按壁纸颜色匹配主题" not in themes_ui

    advanced = source("app/CCBGAdvancedControllers.m")
    assert "CCBGDominantColorHexForMediaAtPath" in advanced
    media_color = block(shared, "NSString *CCBGDominantColorHexForMediaAtPath", "static id CCBGReplacingReference")
    assert "AVAssetImageGenerator" in media_color
    assert "copyCGImageAtTime" in media_color

    settings = source("app/CCBGSettingsControllers.m")
    assert 'textLabel.text = expanded ? @"展开可视化构图" : @"紧凑可视化构图"' in settings
    assert "initWithSystemMediaItem:item preferencePrefix:prefix" in settings
    assert "[self genericModuleSupportsExpandedPresentation] ? 11 : 9" in settings
    assert "presentationModeValue respondsToSelector" in overlay_reload
    assert "configuredZoom respondsToSelector" in overlay_reload
    assert "CCBGHookControlCenterPresentationClass" in overlay
    assert "CCBGApplyVisualThemeAutomationIfNeeded(controller.view)" in overlay
    assert "CCBGApplyVisualThemeAutomationIfNeeded(self.view)" not in theme_module
    wallpaper_palette = block(shared, "static UIColor *CCBGWallpaperPaletteColor", "static UIColor *CCBGBlendPaletteColors")
    assert "if (cachedColor && cachedAt > 0" in wallpaper_palette
    assert "cachedAt = now; return cachedColor" in wallpaper_palette

    print("Visual theme service regression checks passed")


if __name__ == "__main__":
    main()
