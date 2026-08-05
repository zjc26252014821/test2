from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "app" / "CCBGAdvancedControllers.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "app" / "CCBGSettingsControllers.m").read_text(encoding="utf-8")


def block(text: str, start: str, end: str) -> str:
    return text.rsplit(start, 1)[1].split(end, 1)[0]


appearance = block(SOURCE, "@implementation CCBGModuleAppearanceController", "@interface CCBGAdvancedAutomationController")
media_cell = appearance.rsplit("- (UITableViewCell *)mediaCell:", 1)[1].split("- (void)tableView:", 1)[0]

assert "@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;" in SOURCE
assert "self.mediaCatalog = CCBGLoadMediaCatalog();" in appearance
assert "CCBGMediaItemNamed(self.mediaCatalog" in media_cell
assert "CCBGLoadMediaCatalog()" not in media_cell

system_modules = block(SETTINGS, "@implementation CCBGSystemModulesController", "@implementation CCBGGenericSystemModulesController")
system_media_cell = system_modules.rsplit("- (UITableViewCell *)systemMediaCell:", 1)[1].split("- (UITableViewCell *)systemSliderCell:", 1)[0]

assert "@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;" in SETTINGS
assert "self.mediaCatalog = CCBGLoadMediaCatalog();" in system_modules
assert "CCBGMediaItemNamed(self.mediaCatalog" in system_media_cell
assert "CCBGLoadMediaCatalog()" not in system_media_cell

# System overlay playlist search uses the same coalesced refresh pattern as
# the shared media picker so typing does not rebuild the section per key.
playlist = SETTINGS.split("@implementation CCBGSystemOverlayPlaylistController", 1)[1].split("@interface CCBGSystemModulesController", 1)[0]
assert "searchReloadGeneration" in playlist
assert "dispatch_after" in playlist
assert "generation != self.searchReloadGeneration" in playlist

# Picker pages refresh their catalog when revisited so imports/deletions made
# elsewhere are visible without restarting the settings app.
picker = (ROOT / "app" / "CCBGControls.m").read_text(encoding="utf-8")
picker_block = picker.split("@implementation CCBGMediaPickerController", 1)[1].split("NSString *CCBGReadableBytes", 1)[0]
assert "- (void)viewWillAppear" in picker_block
assert "self.items = CCBGLoadMediaCatalog();" in picker_block
assert "scrollToSelectedItemIfNeeded" in picker_block

print("App list scrolling performance checks passed")
