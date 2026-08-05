#import "CCBGAppControllers.h"
#import "CCBGMediaCatalog.h"

static NSString *CCBGGenericOverlayPrefix(NSString *identifier) {
    NSData *data = [[identifier lowercaseString] dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"customOverlay%016llx", hash];
}

static NSDictionary *CCBGNormalizedControlCenterModule(NSDictionary *module) {
    NSString *identifier = [module[@"identifier"] isKindOfClass:NSString.class] ? module[@"identifier"] : @"";
    if (!identifier.length) return nil;
    NSString *name = [module[@"name"] isKindOfClass:NSString.class] ? module[@"name"] : @"";
    NSString *principalClass = [module[@"principalClass"] isKindOfClass:NSString.class] ? module[@"principalClass"] : @"";
    NSString *prefix = [module[@"prefix"] isKindOfClass:NSString.class] ? module[@"prefix"] : @"";
    return @{
        @"identifier": identifier,
        @"name": name.length ? name : identifier,
        @"principalClass": principalClass,
        @"prefix": prefix.length ? prefix : CCBGGenericOverlayPrefix(identifier),
    };
}

static BOOL CCBGIsDedicatedSystemOverlay(NSDictionary *module) {
    NSString *search = [NSString stringWithFormat:@"%@ %@ %@", module[@"identifier"] ?: @"", module[@"name"] ?: @"", module[@"principalClass"] ?: @""].lowercaseString;
    for (NSString *token in @[@"connectivitymodule", @"brightnessmodule", @"displaymodule", @"audiomodule", @"volumemodule", @"nowplayingmodule", @"mediaremote.controlcenter"]) {
        if ([search containsString:token]) return YES;
    }
    return NO;
}

static NSArray<NSDictionary *> *CCBGAvailableGenericModules(void) {
    NSMutableDictionary<NSString *, NSDictionary *> *modules = [NSMutableDictionary dictionary];
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *root in @[@"/System/Library/ControlCenter/Bundles", @"/Library/ControlCenter/Bundles", @"/var/jb/Library/ControlCenter/Bundles"]) {
        for (NSString *entry in [manager contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
            if (![entry.pathExtension.lowercaseString isEqualToString:@"bundle"]) continue;
            NSString *path = [root stringByAppendingPathComponent:entry];
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            NSDictionary *info = bundle.infoDictionary ?: [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
            NSString *identifier = bundle.bundleIdentifier ?: info[@"CFBundleIdentifier"] ?: entry.stringByDeletingPathExtension;
            NSString *name = bundle.localizedInfoDictionary[@"CFBundleDisplayName"] ?: bundle.localizedInfoDictionary[@"CFBundleName"] ?: info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: entry.stringByDeletingPathExtension;
            NSString *principalClass = info[@"NSPrincipalClass"] ?: info[@"NSExtension"][@"NSExtensionPrincipalClass"] ?: @"";
            NSDictionary *module = CCBGNormalizedControlCenterModule(@{@"identifier": identifier, @"name": name, @"principalClass": principalClass});
            if (module && !CCBGIsDedicatedSystemOverlay(module)) modules[identifier] = module;
        }
    }
    for (NSString *preferenceKey in @[@"discoveredControlCenterModules", @"customSystemOverlayModules"]) {
        id stored = CCBGReadPreference(preferenceKey, @[]);
        if (![stored isKindOfClass:NSArray.class]) continue;
        for (id value in stored) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *module = CCBGNormalizedControlCenterModule(value);
            if (module && !CCBGIsDedicatedSystemOverlay(module)) modules[module[@"identifier"]] = module;
        }
    }
    return [modules.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

static void CCBGSaveConfiguredGenericModule(NSDictionary *selectedModule) {
    NSDictionary *selected = CCBGNormalizedControlCenterModule(selectedModule);
    if (!selected) return;
    NSMutableArray<NSDictionary *> *modules = [NSMutableArray array];
    BOOL replaced = NO;
    id stored = CCBGReadPreference(@"customSystemOverlayModules", @[]);
    if ([stored isKindOfClass:NSArray.class]) {
        for (id value in stored) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *module = CCBGNormalizedControlCenterModule(value);
            if (!module) continue;
            if ([module[@"identifier"] isEqualToString:selected[@"identifier"]]) {
                [modules addObject:selected];
                replaced = YES;
            } else {
                [modules addObject:module];
            }
        }
    }
    if (!replaced) [modules addObject:selected];
    CCBGWritePreference(@"customSystemOverlayModules", modules);
}

@interface CCBGGenericSystemModulesController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSArray<NSDictionary *> *modules;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredModules;
@property(nonatomic, strong) UISearchController *searchController;
@end

@implementation CCBGGenericSystemModulesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"其他控制中心模块";
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"搜索模块";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.modules = CCBGAvailableGenericModules();
    [self updateSearchResultsForSearchController:self.searchController];
}
- (NSArray<NSDictionary *> *)visibleModules { return self.filteredModules ?: self.modules ?: @[]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleModules.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"可用模块"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.modules.count ? @"选择模块后可分别设置紧凑和展开素材。控制中心运行时发现的第三方模块也会自动加入列表。" : @"请打开一次控制中心，让插件发现已安装模块。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *module = self.visibleModules[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"genericSystemModule"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"genericSystemModule"];
    BOOL enabled = [CCBGReadPreference([module[@"prefix"] stringByAppendingString:@"Enabled"], @NO) boolValue];
    cell.textLabel.text = module[@"name"];
    cell.detailTextLabel.text = module[@"identifier"];
    cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
    cell.imageView.tintColor = enabled ? self.view.tintColor : UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *module = self.visibleModules[(NSUInteger)indexPath.row];
    CCBGSaveConfiguredGenericModule(module);
    [self.navigationController pushViewController:[[CCBGSystemModulesController alloc] initWithGenericModule:module] animated:YES];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) self.filteredModules = nil;
    else {
        NSMutableArray *matches = [NSMutableArray array];
        for (NSDictionary *module in self.modules) {
            if ([module[@"name"] localizedCaseInsensitiveContainsString:query] || [module[@"identifier"] localizedCaseInsensitiveContainsString:query]) [matches addObject:module];
        }
        self.filteredModules = matches;
    }
    [self.tableView reloadData];
}
@end
