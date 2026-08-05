#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"

static UINavigationController *CCBGNavigationController(UIViewController *root, NSString *title, NSString *imageName) {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.navigationBar.tintColor = CCBGAppAccentColor();
    navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:imageName] selectedImage:nil];
    return navigation;
}

@implementation CCBGMainTabBarController
- (void)viewDidLoad {
    [super viewDidLoad];
    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithDefaultBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    appearance.shadowColor = UIColor.clearColor;
    appearance.selectionIndicatorTintColor = [CCBGAppAccentColor() colorWithAlphaComponent:0.16];
    self.tabBar.standardAppearance = appearance;
    self.tabBar.scrollEdgeAppearance = appearance;
    self.tabBar.tintColor = CCBGAppAccentColor();
    self.tabBar.unselectedItemTintColor = UIColor.secondaryLabelColor;
    self.viewControllers = @[
        CCBGNavigationController([[CCBGModuleWorkspaceController alloc] initWithStyle:UITableViewStyleInsetGrouped], @"模块", @"square.3.layers.3d"),
        CCBGNavigationController([[CCBGRootController alloc] initWithStyle:UITableViewStyleInsetGrouped], @"素材", @"photo.on.rectangle.angled"),
        CCBGNavigationController([[CCBGSystemModulesController alloc] initWithStyle:UITableViewStyleInsetGrouped], @"系统", @"switch.2"),
        CCBGNavigationController([[CCBGSceneDirectorController alloc] initWithStyle:UITableViewStyleInsetGrouped], @"场景", @"sparkles.rectangle.stack"),
        CCBGNavigationController([[CCBGQuickConfigController alloc] initWithStyle:UITableViewStyleInsetGrouped], @"快捷", @"slider.horizontal.3"),
    ];
}
@end

@interface CCBGModuleWorkspaceController ()
@property(nonatomic, strong) UISegmentedControl *slotControl;
@property(nonatomic, strong) UIScrollView *slotScrollView;
@property(nonatomic, copy) NSArray<NSDictionary *> *catalogSnapshot;
@property(nonatomic, copy) NSString *renderedWorkspaceSignature;
@end

@implementation CCBGModuleWorkspaceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"模块";
    self.slotControl = [[UISegmentedControl alloc] initWithItems:CCBGModuleDisplayNames()];
    self.slotControl.selectedSegmentIndex = CCBGActiveModuleSlot();
    [self.slotControl addTarget:self action:@selector(slotChanged:) forControlEvents:UIControlEventValueChanged];
    self.slotControl.frame = CGRectMake(0, 0, 440, 34);
    self.slotScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(16, 16, MAX(288, CGRectGetWidth(self.tableView.bounds) - 32), 38)];
    self.slotScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.slotScrollView.showsHorizontalScrollIndicator = YES;
    self.slotScrollView.contentSize = CGSizeMake(440, 34);
    [self.slotScrollView addSubview:self.slotControl];
    UILabel *scope = [[UILabel alloc] initWithFrame:CGRectMake(16, 56, MAX(288, CGRectGetWidth(self.tableView.bounds) - 32), 22)];
    scope.text = @"当前页面的修改只作用于选中的模块";
    scope.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    scope.textColor = UIColor.secondaryLabelColor;
    scope.textAlignment = NSTextAlignmentCenter;
    scope.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 88)];
    [header addSubview:self.slotScrollView];
    [header addSubview:scope];
    self.tableView.tableHeaderView = header;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.slotControl.selectedSegmentIndex = CCBGActiveModuleSlot();
    [self reloadWorkspaceIfNeeded];
}
- (void)slotChanged:(UISegmentedControl *)sender {
    CCBGWritePreference(@"activeModuleSlot", @(sender.selectedSegmentIndex));
    [self reloadWorkspaceIfNeeded];
}
- (void)reloadWorkspaceIfNeeded {
    NSInteger slot = CCBGActiveModuleSlot();
    NSArray<NSDictionary *> *catalog = CCBGLoadMediaCatalog();
    self.catalogSnapshot = catalog;
    NSString *signature = [NSString stringWithFormat:@"%ld|%ld|%@",
        (long)slot,
        (long)[CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue],
        CCBGActiveModuleMediaName(slot) ?: @""];
    if ([signature isEqualToString:self.renderedWorkspaceSignature]) return;
    self.renderedWorkspaceSignature = signature;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return [CCBGReadModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @0) integerValue] == 0 ? 1 : 2;
    return section == 2 ? 5 : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"当前状态", @"播放", @"行为与外观", @"配置工具"][section];
}
- (NSArray *)rowsForSection:(NSInteger)section {
    if (section == 1) return @[
        @[@"播放与显示", @"slider.horizontal.3", CCBGPlaybackSettingsController.class],
        @[@"独立播放列表", @"list.number", CCBGPlaylistController.class],
    ];
    if (section == 2) return @[
        @[@"模块外观与隐私", @"square.dashed", CCBGModuleAppearanceController.class],
        @[@"手势与触感", @"hand.tap", CCBGGestureSettingsController.class],
        @[@"基础自动化", @"clock.arrow.circlepath", CCBGAutomationController.class],
        @[@"组合规则与定时", @"point.3.connected.trianglepath.dotted", CCBGAdvancedAutomationController.class],
        @[@"自动化优先级", @"list.bullet.rectangle", CCBGAutomationPriorityController.class],
    ];
    return @[
        @[@"尺寸、复制与重置", @"square.on.square", CCBGModuleManagerController.class],
        @[@"默认素材与恢复", @"arrow.triangle.2.circlepath", CCBGFiveModuleDefaultController.class],
    ];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"workspace"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"workspace"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = UIColor.labelColor;
    if (indexPath.section == 0) {
        NSInteger slot = CCBGActiveModuleSlot();
        NSArray *catalog = self.catalogSnapshot ?: CCBGLoadMediaCatalog();
        NSDictionary *item = CCBGMediaItemNamed(CCBGMediaItemsForModule(catalog, slot), CCBGActiveModuleMediaName(slot));
        cell.textLabel.text = [NSString stringWithFormat:@"%@ 模块", CCBGModuleDisplayNames()[slot]];
        cell.detailTextLabel.text = item ? CCBGDisplayNameForItem(item) : @"未选择素材";
        cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
    } else {
        NSArray *row = [self rowsForSection:indexPath.section][indexPath.row];
        cell.textLabel.text = row[0];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:row[1]];
    }
    cell.imageView.tintColor = CCBGAppAccentColor();
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self.navigationController pushViewController:[[CCBGRootController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        return;
    }
    Class controllerClass = [self rowsForSection:indexPath.section][indexPath.row][2];
    UITableViewController *controller = [(UITableViewController *)[controllerClass alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}
@end

@implementation CCBGMoreController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"更多"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self rowsForSection:section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"界面", @"数据与方案", @"维护"][section]; }
- (NSArray *)rowsForSection:(NSInteger)section {
    if (section == 0) return @[
        @[@"总览", @"rectangle.grid.2x2", CCBGDashboardController.class],
        @[@"App 外观与主题", @"paintpalette", CCBGAppearanceController.class],
        @[@"五模块状态与历史", @"waveform.path.ecg", CCBGStatusDashboardController.class],
    ];
    if (section == 1) return @[
        @[@"方案与自动回滚", @"archivebox", CCBGProfilesController.class],
        @[@"备份时间机", @"clock.badge.checkmark", CCBGBackupTimelineController.class],
        @[@"素材洞察与批量编辑", @"chart.bar.xaxis", CCBGLibraryInsightsController.class],
    ];
    return @[@[@"诊断与备份", @"stethoscope", CCBGDiagnosticsController.class]];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *row = [self rowsForSection:indexPath.section][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"more"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
    cell.textLabel.text = row[0];
    cell.imageView.image = [UIImage systemImageNamed:row[1]];
    cell.imageView.tintColor = CCBGAppAccentColor();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    Class controllerClass = [self rowsForSection:indexPath.section][indexPath.row][2];
    UITableViewController *controller = [(UITableViewController *)[controllerClass alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}
@end

@interface CCBGDashboardController ()
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property(nonatomic, copy) NSArray<NSDictionary *> *catalogSnapshot;
@property(nonatomic, copy) NSString *renderedDashboardSignature;
@end

@implementation CCBGDashboardController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.thumbnailCache = [NSCache new];
    self.thumbnailCache.countLimit = 24;
    self.title = @"总览";
    self.tableView.sectionHeaderTopPadding = 10;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 112)];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 18, 330, 34)];
    title.text = @"Control Center Media";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    UILabel *summary = [[UILabel alloc] initWithFrame:CGRectMake(20, 58, 350, 38)];
    summary.text = @"五个模块独立配置，系统背景独立运行";
    summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    summary.textColor = UIColor.secondaryLabelColor;
    [header addSubview:title];
    [header addSubview:summary];
    self.tableView.tableHeaderView = header;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadDashboardIfNeeded]; }
- (void)reloadDashboardIfNeeded {
    self.catalogSnapshot = CCBGLoadMediaCatalog();
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%ld|%lu|",
        (long)CCBGActiveModuleSlot(), (unsigned long)self.catalogSnapshot.count];
    for (NSUInteger slot = 0; slot < CCBGModuleDisplayNames().count; slot++) {
        [signature appendFormat:@"%ld:%ld:%@|",
            (long)slot,
            (long)[CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue],
            CCBGActiveModuleMediaName(slot) ?: @""];
    }
    for (NSString *prefix in @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"]) {
        [signature appendFormat:@"%@:%d|", prefix, [CCBGReadPreference([prefix stringByAppendingString:@"Enabled"], @NO) boolValue]];
    }
    if ([signature isEqualToString:self.renderedDashboardSignature]) return;
    self.renderedDashboardSignature = signature.copy;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 5 : section == 1 ? 5 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"五个独立模块", @"系统模块背景", @"恢复状态"][section]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dashboard"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"dashboard"];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = nil;
    if (indexPath.section == 0) {
        NSInteger slot = indexPath.row;
        NSArray *modes = @[@"固定", @"顺序", @"随机"];
        NSInteger mode = MIN(2, MAX(0, [CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue]));
        NSDictionary *item = CCBGMediaItemNamed(CCBGMediaItemsForModule(self.catalogSnapshot ?: @[], slot), CCBGActiveModuleMediaName(slot));
        cell.textLabel.text = [NSString stringWithFormat:@"%@ 模块", CCBGModuleDisplayNames()[slot]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", modes[mode], item ? CCBGDisplayNameForItem(item) : @"未选择素材"];
        CGSize size = CGSizeMake(44, 44);
        NSString *key = item ? CCBGThumbnailCacheKeyForItem(item, size, [NSString stringWithFormat:@"dashboard-%ld-", (long)slot]) : @"";
        UIImage *thumbnail = key.length ? [self.thumbnailCache objectForKey:key] : nil;
        cell.imageView.image = thumbnail ?: (item ? CCBGPlaceholderImageForItem(item) : [UIImage systemImageNamed:@"photo"]);
        cell.imageView.tintColor = slot == CCBGActiveModuleSlot() ? CCBGAppAccentColor() : UIColor.secondaryLabelColor;
        cell.accessibilityIdentifier = key;
        if (item && !thumbnail) {
            __weak UITableViewCell *weakCell = cell;
            CCBGLoadThumbnailForItem(item, size, ^(UIImage *loaded) {
                UITableViewCell *strongCell = weakCell;
                if (!loaded || ![strongCell.accessibilityIdentifier isEqualToString:key]) return;
                [self.thumbnailCache setObject:loaded forKey:key];
                strongCell.imageView.image = loaded;
                [strongCell setNeedsLayout];
            });
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 4) {
            cell.textLabel.text = @"其他控制中心模块";
            cell.detailTextLabel.text = @"选择任意模块设置独立素材";
            cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
            cell.imageView.tintColor = CCBGAppAccentColor();
            return cell;
        }
        NSArray *names = @[@"连接", @"音乐", @"亮度", @"音量"];
        NSArray *prefixes = @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"];
        NSString *prefix = prefixes[indexPath.row];
        cell.textLabel.text = names[indexPath.row];
        cell.detailTextLabel.text = [CCBGReadPreference([prefix stringByAppendingString:@"Enabled"], @NO) boolValue] ? @"已启用" : @"未启用";
        cell.imageView.image = [UIImage systemImageNamed:@[@"antenna.radiowaves.left.and.right", @"music.note", @"sun.max", @"speaker.wave.2"][indexPath.row]];
        cell.imageView.tintColor = CCBGAppAccentColor();
    } else {
        BOOL restorable = [CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil) isKindOfClass:NSDictionary.class];
        cell.textLabel.text = @"五模块默认与恢复";
        cell.detailTextLabel.text = restorable ? @"存在可恢复状态" : @"暂无恢复点";
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.imageView.tintColor = restorable ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        CCBGWritePreference(@"activeModuleSlot", @(indexPath.row));
        [self.navigationController pushViewController:[[CCBGModuleWorkspaceController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    } else if (indexPath.section == 1) {
        if (indexPath.row == 4) [self.navigationController pushViewController:[[CCBGGenericSystemModulesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        else [self.navigationController pushViewController:[[CCBGSystemModulesController alloc] initWithOverlayIndex:indexPath.row] animated:YES];
    } else {
        [self.navigationController pushViewController:[[CCBGFiveModuleDefaultController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    }
}
@end
