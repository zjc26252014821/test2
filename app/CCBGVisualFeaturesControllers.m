#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <AVFoundation/AVFoundation.h>

static NSString *CCBGVisualThemeTitle(NSDictionary *item) {
    NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
    return name.length ? name : @"未命名主题";
}

static UIColor *CCBGVisualColorFromHex(NSString *hex) {
    NSString *value = [[(hex ?: @"") stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (value.length != 6) return CCBGAppAccentColor();
    unsigned number = 0;
    if (![[NSScanner scannerWithString:value] scanHexInt:&number]) return CCBGAppAccentColor();
    return [UIColor colorWithRed:((number >> 16) & 0xff) / 255.0 green:((number >> 8) & 0xff) / 255.0 blue:(number & 0xff) / 255.0 alpha:1.0];
}

static NSUInteger CCBGEligibleVisualThemeCount(void) {
    NSUInteger count = 0;
    for (NSDictionary *theme in CCBGVisualThemes()) if ([theme[@"enabled"] boolValue]) count++;
    return count;
}

static NSUInteger CCBGVisualThemeChangedValueCount(NSDictionary *theme) {
    NSDictionary *values = [theme[@"values"] isKindOfClass:NSDictionary.class] ? theme[@"values"] : @{};
    NSDictionary *current = CCBGReadAllPreferences();
    NSUInteger count = 0;
    for (NSString *key in values) {
        if ([key containsString:@"forcePreferenceMediaOnReload"]) continue;
        id expected = values[key];
        id actual = current[key];
        if ((expected || actual) && ![expected isEqual:actual]) count++;
    }
    return count;
}

static void CCBGShowVisualResult(UIViewController *controller, NSString *title, NSString *message) {
    __weak UIViewController *weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *strongController = weakController;
        if (!strongController || strongController.presentedViewController) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [strongController presentViewController:alert animated:YES completion:nil];
    });
}

static NSString *CCBGVisualThemeLastResultText(void) {
    NSDictionary *result = CCBGReadPreference(@"visualThemeLastResult", @{});
    NSString *status = [result[@"status"] isKindOfClass:NSString.class] ? result[@"status"] : @"";
    NSString *reason = [result[@"reason"] isKindOfClass:NSString.class] ? result[@"reason"] : @"";
    NSString *name = [result[@"themeName"] isKindOfClass:NSString.class] ? result[@"themeName"] : @"";
    NSString *resultText = @"尚未运行";
    if ([status isEqualToString:@"applied"]) resultText = name.length ? [NSString stringWithFormat:@"已切换到 %@", name] : @"主题已应用";
    else if ([status isEqualToString:@"unchanged"]) resultText = name.length ? [NSString stringWithFormat:@"%@ 已经生效", name] : @"当前主题无需切换";
    else if ([reason isEqualToString:@"no-enabled-theme"]) resultText = @"没有参与随机的主题";
    return resultText;
}

@interface CCBGVisualThemesController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *themes;
@end

@implementation CCBGVisualThemesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视觉主题";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTheme)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"排序" style:UIBarButtonItemStylePlain target:self action:@selector(toggleThemeReordering)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.themes = CCBGVisualThemes(); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 5 : self.themes.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"快捷操作" : @"已保存主题"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 0 ? @"启用后，每次打开控制中心都会从参与随机的主题中切换一次。" : @"主题只保存当前素材和视觉外观，不修改播放模式、手势、尺寸或自动化。置顶主题会显示在控制中心主题模块中。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"visualTheme"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"visualTheme"];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.imageView.tintColor = CCBGAppAccentColor();
    if (indexPath.section == 0) {
        if (indexPath.row == 1) {
            NSString *key = @"visualThemeRandomOnOpen";
            CCBGSwitchCell *switchCell = [tableView dequeueReusableCellWithIdentifier:key] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:key];
            [switchCell configureWithTitle:@"打开控制中心时随机" key:key value:[CCBGReadPreference(key, @NO) boolValue] target:self action:@selector(automationSwitchChanged:)];
            return switchCell;
        }
        if (indexPath.row == 4) {
            cell.textLabel.text = @"随机切换状态";
            cell.detailTextLabel.text = CCBGVisualThemeLastResultText();
            cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle"];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        if (indexPath.row == 0) {
            cell.textLabel.text = @"随机应用一个主题";
            cell.detailTextLabel.text = @"按权重从启用的主题中选择";
            cell.imageView.image = [UIImage systemImageNamed:@"dice"];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"快捷指令与 URL";
            cell.detailTextLabel.text = @"复制到快捷指令、NFC 或自动化";
            cell.imageView.image = [UIImage systemImageNamed:@"link"];
        } else {
            NSUInteger enabledCount = [self.themes indexesOfObjectsPassingTest:^BOOL(NSDictionary *theme, NSUInteger index, BOOL *stop) { return [theme[@"enabled"] boolValue]; }].count;
            cell.textLabel.text = @"管理随机池";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu/%lu 个主题参与随机", (unsigned long)enabledCount, (unsigned long)self.themes.count];
            cell.imageView.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
        }
        return cell;
    }
    NSDictionary *theme = self.themes[(NSUInteger)indexPath.row];
    BOOL active = [theme[@"id"] isEqualToString:CCBGReadPreference(@"activeVisualThemeID", @"")];
    BOOL pinned = [theme[@"pinned"] boolValue];
    cell.textLabel.text = CCBGVisualThemeTitle(theme);
    NSUInteger changed = CCBGVisualThemeChangedValueCount(theme);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · 权重 %.1fx%@", changed ? [NSString stringWithFormat:@"将改变 %lu 项", (unsigned long)changed] : @"当前已是此主题", [theme[@"enabled"] boolValue] ? @"参与随机" : @"不参与随机", MAX(0.1, [theme[@"randomWeight"] doubleValue]), pinned ? @" · 已置顶" : @""];
    cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
    cell.imageView.tintColor = CCBGVisualColorFromHex(theme[@"paletteHex"]);
    cell.accessoryType = active ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)addTheme {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存当前视觉主题" message:@"记录五模块和系统模块当前素材，以及五模块外观。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"主题名称"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSDictionary *theme = CCBGCaptureVisualTheme(alert.textFields.firstObject.text);
        if (CCBGSaveVisualTheme(theme)) { weakSelf.themes = CCBGVisualThemes(); [weakSelf.tableView reloadData]; CCBGShowVisualResult(weakSelf, @"主题已保存", @"请修改素材或外观后再保存另一个主题，即可观察切换效果。"); }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            if (CCBGEligibleVisualThemeCount() < 2) CCBGShowVisualResult(self, @"无法随机切换", @"至少保存两个不同主题，并让它们参与随机。");
            else { BOOL applied = CCBGApplyRandomVisualTheme(); [self.tableView reloadData]; CCBGShowVisualResult(self, applied ? @"已随机切换" : @"没有发生切换", CCBGVisualThemeLastResultText()); }
        }
        else if (indexPath.row == 2) [self.navigationController pushViewController:[CCBGShortcutActionsController new] animated:YES];
        else if (indexPath.row == 3) [self presentRandomPoolActions];
        return;
    }
    NSDictionary *theme = self.themes[(NSUInteger)indexPath.row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:CCBGVisualThemeTitle(theme) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"立即应用" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { BOOL applied = CCBGApplyVisualTheme(theme[@"id"]); [weakSelf.tableView reloadData]; CCBGShowVisualResult(weakSelf, applied ? @"应用成功" : @"没有发生变化", CCBGVisualThemeLastResultText()); }]];
    [menu addAction:[UIAlertAction actionWithTitle:[theme[@"pinned"] boolValue] ? @"取消置顶" : @"置顶到控制中心" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSMutableDictionary *updated = [theme mutableCopy]; updated[@"pinned"] = @(![theme[@"pinned"] boolValue]); CCBGSaveVisualTheme(updated); weakSelf.themes = CCBGVisualThemes(); [weakSelf.tableView reloadData]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:[theme[@"enabled"] boolValue] ? @"不参与随机" : @"参与随机" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSMutableDictionary *updated = [theme mutableCopy]; updated[@"enabled"] = @(![theme[@"enabled"] boolValue]); CCBGSaveVisualTheme(updated); weakSelf.themes = CCBGVisualThemes(); [weakSelf.tableView reloadData]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"设置随机权重" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf editWeightForTheme:theme]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"重命名主题" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf renameTheme:theme]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"复制主题" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf duplicateTheme:theme]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"删除主题" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSMutableArray *items = [CCBGVisualThemes() mutableCopy];
        NSUInteger index = [items indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) { return [candidate[@"id"] isEqualToString:theme[@"id"]]; }];
        if (index != NSNotFound) [items removeObjectAtIndex:index];
        CCBGWriteMetadataPreference(@"visualThemes", items); weakSelf.themes = items; [weakSelf.tableView reloadData];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *sourceCell = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceView = sourceCell;
    menu.popoverPresentationController.sourceRect = sourceCell.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)automationSwitchChanged:(UISwitch *)sender {
    if (sender.on && CCBGEligibleVisualThemeCount() < 2) {
        sender.on = NO;
        CCBGWriteMetadataPreference(sender.accessibilityIdentifier, @NO);
        CCBGShowVisualResult(self, @"暂时无法启用", @"至少保存两个不同主题，并让它们参与随机。" );
        return;
    }
    CCBGWriteMetadataPreference(sender.accessibilityIdentifier, @(sender.on));
}
- (void)editWeightForTheme:(NSDictionary *)theme {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"随机权重" message:@"范围 0.1 到 10，数值越大越容易被选中。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeDecimalPad; field.text = [NSString stringWithFormat:@"%.1f", MAX(0.1, [theme[@"randomWeight"] doubleValue])]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSMutableDictionary *updated = [theme mutableCopy]; updated[@"randomWeight"] = @(MIN(10.0, MAX(0.1, alert.textFields.firstObject.text.doubleValue))); CCBGSaveVisualTheme(updated); weakSelf.themes = CCBGVisualThemes(); [weakSelf.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)toggleThemeReordering {
    BOOL editing = !self.tableView.editing;
    [self.tableView setEditing:editing animated:YES];
    self.navigationItem.leftBarButtonItem.title = editing ? @"完成" : @"排序";
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 1; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath { return NO; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 1; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == 1) return proposedDestinationIndexPath;
    NSInteger row = proposedDestinationIndexPath.section < 1 ? 0 : MAX(0, (NSInteger)self.themes.count - 1);
    return [NSIndexPath indexPathForRow:row inSection:1];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 1 || destinationIndexPath.section != 1 || sourceIndexPath.row == destinationIndexPath.row) return;
    NSMutableArray<NSDictionary *> *themes = [self.themes mutableCopy];
    NSDictionary *theme = themes[(NSUInteger)sourceIndexPath.row];
    [themes removeObjectAtIndex:(NSUInteger)sourceIndexPath.row];
    [themes insertObject:theme atIndex:(NSUInteger)MIN(destinationIndexPath.row, (NSInteger)themes.count)];
    self.themes = themes;
    CCBGWriteMetadataPreference(@"visualThemes", themes);
}
- (void)duplicateTheme:(NSDictionary *)theme {
    NSMutableDictionary *copy = [theme mutableCopy];
    copy[@"id"] = NSUUID.UUID.UUIDString;
    copy[@"name"] = [NSString stringWithFormat:@"%@ 副本", CCBGVisualThemeTitle(theme)];
    copy[@"createdAt"] = @(NSDate.date.timeIntervalSince1970);
    copy[@"pinned"] = @NO;
    if (!CCBGSaveVisualTheme(copy)) return;
    self.themes = CCBGVisualThemes();
    [self.tableView reloadData];
    CCBGShowVisualResult(self, @"主题已复制", @"副本保留原主题的素材、外观和随机权重，可以继续单独调整。" );
}
- (void)renameTheme:(NSDictionary *)theme {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名主题" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = CCBGVisualThemeTitle(theme); field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) return;
        NSMutableDictionary *updated = [theme mutableCopy];
        updated[@"name"] = name;
        if (!CCBGSaveVisualTheme(updated)) return;
        weakSelf.themes = CCBGVisualThemes();
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)setAllThemesRandomEnabled:(BOOL)enabled {
    NSMutableArray<NSDictionary *> *themes = [NSMutableArray arrayWithCapacity:self.themes.count];
    for (NSDictionary *theme in self.themes) {
        NSMutableDictionary *updated = [theme mutableCopy];
        updated[@"enabled"] = @(enabled);
        [themes addObject:updated];
    }
    self.themes = themes;
    CCBGWriteMetadataPreference(@"visualThemes", themes);
    [self.tableView reloadData];
}
- (void)resetAllThemeWeights {
    NSMutableArray<NSDictionary *> *themes = [NSMutableArray arrayWithCapacity:self.themes.count];
    for (NSDictionary *theme in self.themes) {
        NSMutableDictionary *updated = [theme mutableCopy];
        updated[@"randomWeight"] = @1.0;
        [themes addObject:updated];
    }
    self.themes = themes;
    CCBGWriteMetadataPreference(@"visualThemes", themes);
    [self.tableView reloadData];
}
- (void)presentRandomPoolActions {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"管理随机池" message:@"批量决定哪些主题会参与手动随机和打开控制中心时随机。" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"全部加入随机池" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf setAllThemesRandomEnabled:YES]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"全部权重恢复为 1.0" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf resetAllThemeWeights]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"全部暂停随机" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [weakSelf setAllThemesRandomEnabled:NO]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end

@interface CCBGVisualStylePresetsController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *presets;
@end

static NSString *CCBGVisualStylePresetSummary(NSDictionary *preset) {
    NSDictionary *values = [preset[@"values"] isKindOfClass:NSDictionary.class] ? preset[@"values"] : @{};
    CGFloat radius = [values[@"moduleCornerRadius"] doubleValue];
    CGFloat border = [values[@"moduleBorderWidth"] doubleValue];
    CGFloat opacity = [values[@"moduleOpacity"] doubleValue] * 100.0;
    CGFloat blur = [values[@"moduleBlurIntensity"] doubleValue] * 100.0;
    return [NSString stringWithFormat:@"圆角 %.0f · 边框 %.1f · 透明度 %.0f%% · 模糊 %.0f%%", radius, border, opacity, blur];
}

@implementation CCBGVisualStylePresetsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"模块外观方案"; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 72.0; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPreset)]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.presets = CCBGVisualStylePresets(); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.presets.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"视觉参数快照"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"保存一个模块的视觉参数，再应用到任意模块；素材、播放、尺寸和手势保持不变。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *preset = self.presets[(NSUInteger)indexPath.row]; UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stylePreset"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"stylePreset"]; cell.textLabel.text = preset[@"name"] ?: @"未命名外观"; cell.detailTextLabel.text = CCBGVisualStylePresetSummary(preset); cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0; cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping; cell.imageView.image = [UIImage systemImageNamed:@"paintbrush.pointed"]; cell.imageView.tintColor = CCBGAppAccentColor(); cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)addPreset { NSString *moduleName = CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]; UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存当前模块外观" message:[NSString stringWithFormat:@"来源：%@", moduleName] preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"外观名称"; }]; [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; __weak typeof(self) weakSelf = self; [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { BOOL saved = CCBGSaveVisualStylePreset(CCBGCaptureVisualStylePreset(alert.textFields.firstObject.text, CCBGActiveModuleSlot())); weakSelf.presets = CCBGVisualStylePresets(); [weakSelf.tableView reloadData]; CCBGShowVisualResult(weakSelf, saved ? @"外观方案已保存" : @"保存失败", saved ? [NSString stringWithFormat:@"已记录 %@ 的视觉参数。", moduleName] : @"外观参数无效。"); }]]; [self presentViewController:alert animated:YES completion:nil]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *preset = self.presets[(NSUInteger)indexPath.row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:preset[@"name"] ?: @"应用外观" message:@"选择目标模块" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [CCBGModuleDisplayNames() enumerateObjectsUsingBlock:^(NSString *moduleName, NSUInteger slot, BOOL *stop) {
        [menu addAction:[UIAlertAction actionWithTitle:moduleName style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            BOOL applied = CCBGApplyVisualStylePreset(preset[@"id"], (NSInteger)slot);
            CCBGShowVisualResult(weakSelf, applied ? @"应用成功" : @"应用失败", applied ? [NSString stringWithFormat:@"外观方案已应用到 %@。", moduleName] : @"外观方案数据无效。");
        }]];
    }];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *sourceCell = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceView = sourceCell;
    menu.popoverPresentationController.sourceRect = sourceCell.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath { if (style != UITableViewCellEditingStyleDelete) return; NSMutableArray *items = [self.presets mutableCopy]; [items removeObjectAtIndex:(NSUInteger)indexPath.row]; CCBGWriteMetadataPreference(@"visualStylePresets", items); self.presets = items; [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic]; }
@end

@interface CCBGShortcutActionsController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *actions;
@end


@implementation CCBGShortcutActionsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"快捷指令 URL"; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 82.0; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray *actions = [@[
        @{@"title": @"随机视觉主题", @"url": @"cleanccbg://theme/random"},
        @{@"title": @"切换插件总开关", @"url": @"cleanccbg://plugin/toggle"},
        @{@"title": @"开启插件", @"url": @"cleanccbg://plugin/on"},
        @{@"title": @"关闭插件", @"url": @"cleanccbg://plugin/off"},
    ] mutableCopy];
    for (NSDictionary *theme in CCBGVisualThemes()) {
        NSString *escaped = [theme[@"id"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
        [actions addObject:@{@"title": [NSString stringWithFormat:@"应用主题：%@", CCBGVisualThemeTitle(theme)], @"url": [NSString stringWithFormat:@"cleanccbg://theme/apply?id=%@", escaped]}];
    }
    NSArray *catalog = CCBGLoadMediaCatalog();
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        NSString *name = CCBGActiveModuleMediaName(slot);
        if (!CCBGMediaItemNamed(catalog, name)) continue;
        NSString *escaped = [name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
        [actions addObject:@{@"title": [NSString stringWithFormat:@"%@ 使用当前素材", CCBGModuleDisplayNames()[slot]], @"url": [NSString stringWithFormat:@"cleanccbg://module/media?slot=%ld&name=%@", (long)slot, escaped]}];
    }
    self.actions = actions;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.actions.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"点按可立即执行以验证效果，也可以复制 URL 到快捷指令、NFC 或其他自动化。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *action = self.actions[(NSUInteger)indexPath.row]; UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shortcutURL"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"shortcutURL"]; cell.textLabel.text = action[@"title"]; cell.detailTextLabel.text = action[@"url"]; cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0; cell.detailTextLabel.lineBreakMode = NSLineBreakByCharWrapping; cell.imageView.image = [UIImage systemImageNamed:@"link"]; cell.imageView.tintColor = CCBGAppAccentColor(); return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *urlString = self.actions[(NSUInteger)indexPath.row][@"url"];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:self.actions[(NSUInteger)indexPath.row][@"title"] message:urlString preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"立即执行" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSURL *url = [NSURL URLWithString:urlString];
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) CCBGShowVisualResult(weakSelf, @"执行失败", @"系统没有接受这个快捷指令 URL。");
        }];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"复制 URL" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = urlString;
        CCBGShowVisualResult(weakSelf, @"已复制", urlString);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *sourceCell = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceView = sourceCell;
    menu.popoverPresentationController.sourceRect = sourceCell.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end

@interface CCBGCompositionEditorController ()
@property(nonatomic, strong) NSMutableDictionary *item;
@property(nonatomic) NSInteger moduleSlot;
@property(nonatomic, copy) NSString *systemPreferencePrefix;
@property(nonatomic) CGFloat compactAspectRatio;
@property(nonatomic) CGFloat expandedAspectRatio;
@property(nonatomic) CGSize naturalMediaSize;
@property(nonatomic) BOOL changesCommitted;
@property(nonatomic) BOOL expandedMode;
@property(nonatomic) NSInteger contentMode;
@property(nonatomic) CGFloat focalX;
@property(nonatomic) CGFloat focalY;
@property(nonatomic) CGFloat cropZoom;
@property(nonatomic) BOOL hasAppliedPreviewTransform;
@property(nonatomic) CGRect lastPreviewBounds;
@property(nonatomic) CGFloat lastPreviewFocalX;
@property(nonatomic) CGFloat lastPreviewFocalY;
@property(nonatomic) CGFloat lastPreviewCropZoom;
@property(nonatomic) NSInteger lastPreviewContentMode;
@property(nonatomic) BOOL lastPreviewExpandedMode;
@property(nonatomic, weak) CALayer *lastPreviewPlayerLayer;
@property(nonatomic, strong) UISegmentedControl *presentationControl;
@property(nonatomic, strong) UISegmentedControl *contentModeControl;
@property(nonatomic, strong) UIView *previewContainer;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic) BOOL restartingLoop;
@end

@implementation CCBGCompositionEditorController
- (instancetype)initWithMediaItem:(NSDictionary *)item moduleSlot:(NSInteger)slot {
    self = [super init];
    if (self) {
        _moduleSlot = slot;
        _item = [CCBGMediaItemForModule(item, slot) mutableCopy];
        _compactAspectRatio = 1.0;
        _expandedAspectRatio = 1.0;
        self.title = @"可视化构图";
    }
    return self;
}
- (instancetype)initWithSystemMediaItem:(NSDictionary *)item preferencePrefix:(NSString *)prefix compactAspectRatio:(CGFloat)compactAspectRatio expandedAspectRatio:(CGFloat)expandedAspectRatio {
    self = [super init];
    if (self) {
        _moduleSlot = NSNotFound;
        _item = [item mutableCopy];
        _systemPreferencePrefix = [prefix copy];
        _compactAspectRatio = MAX(0.25, compactAspectRatio);
        _expandedAspectRatio = MAX(0.25, expandedAspectRatio);
        for (NSString *presentation in @[@"compact", @"expanded"]) {
            for (NSString *suffix in @[@"ContentMode", @"FocalX", @"FocalY", @"CropZoom"]) {
                NSString *itemKey = [presentation stringByAppendingString:suffix];
                NSString *capitalizedKey = [itemKey stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[itemKey substringToIndex:1] uppercaseString]];
                id fallback = [suffix isEqualToString:@"ContentMode"] ? (_item[itemKey] ?: @1) : [suffix isEqualToString:@"CropZoom"] ? @1 : (_item[itemKey] ?: @0.5);
                _item[itemKey] = CCBGReadPreference([prefix stringByAppendingString:capitalizedKey], fallback);
            }
        }
        self.title = @"可视化构图";
    }
    return self;
}
- (void)setInitialExpandedMode:(BOOL)expanded { self.expandedMode = expanded; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveAndClose)];

    self.presentationControl = [[UISegmentedControl alloc] initWithItems:@[@"紧凑", @"展开"]];
    self.presentationControl.selectedSegmentIndex = self.expandedMode ? 1 : 0;
    [self.presentationControl addTarget:self action:@selector(presentationChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.presentationControl];

    self.previewContainer = [UIView new];
    self.previewContainer.backgroundColor = UIColor.blackColor;
    self.previewContainer.layer.cornerRadius = 14;
    self.previewContainer.clipsToBounds = YES;
    [self.view addSubview:self.previewContainer];
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.imageView.clipsToBounds = YES;
    [self.previewContainer addSubview:self.imageView];

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.previewContainer addGestureRecognizer:pinch];
    [self.previewContainer addGestureRecognizer:pan];

    self.contentModeControl = [[UISegmentedControl alloc] initWithItems:@[@"完整", @"填充"]];
    [self.contentModeControl addTarget:self action:@selector(contentModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.contentModeControl];

    self.valueLabel = [UILabel new];
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    self.valueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.valueLabel.textColor = UIColor.secondaryLabelColor;
    self.valueLabel.numberOfLines = 2;
    [self.view addSubview:self.valueLabel];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setImage:[UIImage systemImageNamed:@"arrow.counterclockwise"] forState:UIControlStateNormal];
    reset.accessibilityLabel = @"重置当前构图";
    [reset addTarget:self action:@selector(resetCurrentComposition) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reset];
    reset.tag = 7719;

    [self loadMedia];
    [self loadPresentationValues];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self commitChanges]; [self.player pause]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [self.player pause]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat top = CGRectGetMaxY(self.view.safeAreaLayoutGuide.layoutFrame) > 0 ? CGRectGetMinY(self.view.safeAreaLayoutGuide.layoutFrame) : 20;
    self.presentationControl.frame = CGRectMake(24, top + 14, width - 48, 34);
    CGFloat availableWidth = width - 32;
    CGFloat ratio = [self previewAspectRatio];
    CGFloat previewWidth = availableWidth;
    CGFloat previewHeight = previewWidth / MAX(0.2, ratio);
    CGFloat maximumHeight = MIN(430, CGRectGetHeight(self.view.bounds) - top - 190);
    if (previewHeight > maximumHeight) { previewHeight = maximumHeight; previewWidth = previewHeight * ratio; }
    self.previewContainer.frame = CGRectMake(floor((width - previewWidth) * 0.5), CGRectGetMaxY(self.presentationControl.frame) + 16, previewWidth, previewHeight);
    self.imageView.frame = self.previewContainer.bounds;
    self.playerLayer.frame = self.previewContainer.bounds;
    self.contentModeControl.frame = CGRectMake(24, CGRectGetMaxY(self.previewContainer.frame) + 16, width - 96, 34);
    UIView *reset = [self.view viewWithTag:7719];
    reset.frame = CGRectMake(width - 60, CGRectGetMinY(self.contentModeControl.frame), 36, 34);
    self.valueLabel.frame = CGRectMake(20, CGRectGetMaxY(self.contentModeControl.frame) + 10, width - 40, 48);
    [self applyPreviewTransform];
}
- (CGFloat)previewAspectRatio {
    if (self.expandedMode) {
        if (self.systemPreferencePrefix.length) {
            if (self.naturalMediaSize.width > 0 && self.naturalMediaSize.height > 0) return MAX(0.25, MIN(4.0, self.naturalMediaSize.width / self.naturalMediaSize.height));
            return self.expandedAspectRatio;
        }
        CGFloat width = [CCBGReadModulePreference(@"expandedWidth", self.moduleSlot, @430) doubleValue];
        CGFloat height = [CCBGReadModulePreference(@"expandedHeight", self.moduleSlot, @600) doubleValue];
        BOOL adaptive = [CCBGReadModulePreference(@"adaptiveExpandedSizeEnabled", self.moduleSlot, @YES) boolValue];
        if (adaptive && self.naturalMediaSize.width > 0 && self.naturalMediaSize.height > 0) {
            CGFloat maximumWidth = MIN(MAX(220.0, width), CGRectGetWidth(UIScreen.mainScreen.bounds) - 24.0);
            CGFloat maximumHeight = MIN(MAX(220.0, height), CGRectGetHeight(UIScreen.mainScreen.bounds) - 100.0);
            CGFloat naturalRatio = self.naturalMediaSize.width / self.naturalMediaSize.height;
            width = maximumWidth;
            height = width / MAX(0.01, naturalRatio);
            if (height > maximumHeight) { height = maximumHeight; width = height * naturalRatio; }
            width = round(MAX(220.0, MIN(maximumWidth, width)));
            height = round(MAX(220.0, MIN(maximumHeight, height)));
        }
        return MAX(0.4, MIN(2.5, width / MAX(1.0, height)));
    }
    if (self.systemPreferencePrefix.length) return self.compactAspectRatio;
    NSArray<NSArray<NSNumber *> *> *defaultSizes = @[@[@2, @2], @[@1, @2], @[@2, @3], @[@3, @2], @[@3, @3]];
    NSArray<NSNumber *> *defaultSize = self.moduleSlot >= 0 && self.moduleSlot < (NSInteger)defaultSizes.count ? defaultSizes[(NSUInteger)self.moduleSlot] : @[@2, @2];
    CGFloat width = [CCBGReadModulePreference(@"gridWidth", self.moduleSlot, defaultSize[0]) doubleValue];
    CGFloat height = [CCBGReadModulePreference(@"gridHeight", self.moduleSlot, defaultSize[1]) doubleValue];
    return MAX(0.25, MIN(4.0, width / MAX(1.0, height)));
}
- (NSString *)presentationPrefix { return self.expandedMode ? @"expanded" : @"compact"; }
- (NSString *)systemPreferenceKeyForSuffix:(NSString *)suffix {
    if (!self.systemPreferencePrefix.length || !suffix.length) return @"";
    NSString *capitalizedSuffix = [suffix stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[suffix substringToIndex:1] uppercaseString]];
    return [self.systemPreferencePrefix stringByAppendingString:capitalizedSuffix];
}
- (void)loadPresentationValues {
    NSString *prefix = [self presentationPrefix];
    NSInteger fallbackMode = MIN(1, MAX(0, [self.item[@"contentMode"] integerValue]));
    NSString *modeKey = [prefix stringByAppendingString:@"ContentMode"];
    id storedModeValue = self.item[modeKey];
    NSInteger storedMode = [storedModeValue integerValue];
    self.contentMode = storedMode >= 0 ? MIN(1, MAX(0, storedMode)) : fallbackMode;
    CGFloat fallbackX = MIN(1.0, MAX(0.0, [self.item[@"focalX"] doubleValue]));
    CGFloat fallbackY = MIN(1.0, MAX(0.0, [self.item[@"focalY"] doubleValue]));
    NSString *focalXKey = [prefix stringByAppendingString:@"FocalX"];
    NSString *focalYKey = [prefix stringByAppendingString:@"FocalY"];
    id storedXValue = self.item[focalXKey];
    id storedYValue = self.item[focalYKey];
    CGFloat storedX = [storedXValue doubleValue];
    CGFloat storedY = [storedYValue doubleValue];
    self.focalX = storedX >= 0 ? MIN(1.0, storedX) : fallbackX;
    self.focalY = storedY >= 0 ? MIN(1.0, storedY) : fallbackY;
    NSString *zoomKey = [prefix stringByAppendingString:@"CropZoom"];
    id storedZoomValue = self.item[zoomKey];
    self.cropZoom = MIN(2.5, MAX(1.0, [storedZoomValue doubleValue]));
    self.contentModeControl.selectedSegmentIndex = self.contentMode;
    [self.view setNeedsLayout];
    [self applyPreviewTransform];
}
- (void)savePresentationValues {
    NSString *prefix = [self presentationPrefix];
    self.item[[prefix stringByAppendingString:@"ContentMode"]] = @(self.contentMode);
    self.item[[prefix stringByAppendingString:@"FocalX"]] = @(self.focalX);
    self.item[[prefix stringByAppendingString:@"FocalY"]] = @(self.focalY);
    self.item[[prefix stringByAppendingString:@"CropZoom"]] = @(self.cropZoom);
}
- (void)commitChanges {
    if (self.changesCommitted) return;
    [self savePresentationValues];
    self.changesCommitted = YES;
    if (!self.systemPreferencePrefix.length) {
        CCBGSaveModuleMediaConfiguration(self.item, self.moduleSlot);
        return;
    }
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    for (NSString *presentation in @[@"compact", @"expanded"]) {
        for (NSString *suffix in @[@"ContentMode", @"FocalX", @"FocalY", @"CropZoom"]) {
            NSString *itemKey = [presentation stringByAppendingString:suffix];
            changes[[self systemPreferenceKeyForSuffix:itemKey]] = self.item[itemKey];
        }
    }
    CCBGWritePreferences(changes);
}
- (void)loadMedia {
    NSString *path = CCBGPathForItem(self.item);
    if (!CCBGIsVideoName(self.item[@"fileName"])) {
        self.imageView.image = [UIImage imageWithContentsOfFile:path];
        if (self.imageView.image.size.width > 0 && self.imageView.image.size.height > 0) self.naturalMediaSize = self.imageView.image.size;
        return;
    }
    __weak typeof(self) weakSelf = self;
    CCBGLoadVideoOnlyAsset(path, ^(AVAsset *asset, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !asset) return;
        self.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:asset]];
        self.player.preventsDisplaySleepDuringVideoPlayback = NO;
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        CGSize naturalSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
        self.naturalMediaSize = CGSizeMake(fabs(naturalSize.width), fabs(naturalSize.height));
        self.player.muted = YES;
        self.player.volume = 0;
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.masksToBounds = YES;
        [self.previewContainer.layer insertSublayer:self.playerLayer atIndex:0];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        [self.view setNeedsLayout];
        [self.player play];
    });
}
- (void)videoEnded:(NSNotification *)notification {
    if (notification.object != self.player.currentItem || self.restartingLoop) return;
    self.restartingLoop = YES;
    AVPlayer *player = self.player;
    [player pause];
    [player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.player != player) {
                self.restartingLoop = NO;
                return;
            }
            self.restartingLoop = NO;
            if (finished && self.view.window) [player playImmediatelyAtRate:1.0];
        });
    }];
}
- (void)presentationChanged:(UISegmentedControl *)sender { [self savePresentationValues]; self.expandedMode = sender.selectedSegmentIndex == 1; [self loadPresentationValues]; }
- (void)contentModeChanged:(UISegmentedControl *)sender { self.contentMode = sender.selectedSegmentIndex; [self applyPreviewTransform]; }
- (void)handlePinch:(UIPinchGestureRecognizer *)recognizer { self.cropZoom = MIN(2.5, MAX(1.0, self.cropZoom * recognizer.scale)); recognizer.scale = 1.0; [self applyPreviewTransform]; }
- (void)handlePan:(UIPanGestureRecognizer *)recognizer { CGPoint delta = [recognizer translationInView:self.previewContainer]; CGFloat width = MAX(1.0, CGRectGetWidth(self.previewContainer.bounds)); CGFloat height = MAX(1.0, CGRectGetHeight(self.previewContainer.bounds)); self.focalX = MIN(1.0, MAX(0.0, self.focalX - delta.x / width)); self.focalY = MIN(1.0, MAX(0.0, self.focalY - delta.y / height)); [recognizer setTranslation:CGPointZero inView:self.previewContainer]; [self applyPreviewTransform]; }
- (void)applyPreviewTransform {
    CGRect bounds = self.previewContainer.bounds;
    BOOL changed = !self.hasAppliedPreviewTransform ||
        !CGRectEqualToRect(self.lastPreviewBounds, bounds) ||
        fabs(self.lastPreviewFocalX - self.focalX) > 0.001 ||
        fabs(self.lastPreviewFocalY - self.focalY) > 0.001 ||
        fabs(self.lastPreviewCropZoom - self.cropZoom) > 0.001 ||
        self.lastPreviewContentMode != self.contentMode ||
        self.lastPreviewExpandedMode != self.expandedMode ||
        self.lastPreviewPlayerLayer != self.playerLayer;
    if (!changed) return;
    self.hasAppliedPreviewTransform = YES;
    self.lastPreviewBounds = bounds;
    self.lastPreviewFocalX = self.focalX;
    self.lastPreviewFocalY = self.focalY;
    self.lastPreviewCropZoom = self.cropZoom;
    self.lastPreviewContentMode = self.contentMode;
    self.lastPreviewExpandedMode = self.expandedMode;
    self.lastPreviewPlayerLayer = self.playerLayer;
    self.imageView.contentMode = self.contentMode == 0 ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    self.playerLayer.videoGravity = self.contentMode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    CGFloat baseScale = self.contentMode == 0 ? 1.0 : 1.12;
    CGFloat dx = (0.5 - self.focalX) * CGRectGetWidth(self.previewContainer.bounds) * 0.18;
    CGFloat dy = (0.5 - self.focalY) * CGRectGetHeight(self.previewContainer.bounds) * 0.18;
    CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformMakeScale(baseScale * self.cropZoom, baseScale * self.cropZoom), CGAffineTransformMakeTranslation(dx, dy));
    self.imageView.transform = transform;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; [self.playerLayer setAffineTransform:transform]; [CATransaction commit];
    self.valueLabel.text = [NSString stringWithFormat:@"%@ · 焦点 %.2f / %.2f · 缩放 %.2fx\n拖动画面调整焦点，双指缩放", self.expandedMode ? @"展开" : @"紧凑", self.focalX, self.focalY, self.cropZoom];
}
- (void)resetCurrentComposition { self.contentMode = MIN(1, MAX(0, [self.item[@"contentMode"] integerValue])); self.focalX = MIN(1.0, MAX(0.0, [self.item[@"focalX"] doubleValue])); self.focalY = MIN(1.0, MAX(0.0, [self.item[@"focalY"] doubleValue])); self.cropZoom = 1.0; self.contentModeControl.selectedSegmentIndex = self.contentMode; [self applyPreviewTransform]; }
- (void)saveAndClose { [self commitChanges]; [self.navigationController popViewControllerAnimated:YES]; }
@end
