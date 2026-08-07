#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static dispatch_queue_t CCBGSettingsBackupQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.settings-backup", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static CCBGSwitchCell *CCBGConfiguredSwitch(UITableView *tableView, NSString *title, NSString *key, BOOL fallback, id target, SEL action) {
    CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
    if (!cell) cell = [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
    [cell configureWithTitle:title key:key value:[CCBGReadPreference(key, @(fallback)) boolValue] target:target action:action];
    return cell;
}

static CCBGSwitchCell *CCBGConfiguredModuleSwitch(UITableView *tableView, NSString *title, NSString *key, BOOL fallback, id target, SEL action) {
    CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"moduleSwitch"];
    if (!cell) cell = [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"moduleSwitch"];
    [cell configureWithTitle:title key:key value:[CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @(fallback)) boolValue] target:target action:action];
    return cell;
}


@implementation CCBGModuleManagerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"模块";
    self.tableView.sectionHeaderTopPadding = 12;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? CCBGModuleDisplayNames().count : section == 1 ? 3 : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"五个独立模块", @"控制中心占格", @"配置工具"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"点选模块后，主界面的素材、播放、显示与自动化页面都会切换到该模块。";
    if (section == 1) return @"点选任意格位即可一次性调整宽高，并立即通知控制中心重排。开启模块内调尺寸后，可在控制中心紧凑状态点右下角按钮选择占格；iPhone 控制中心为四列网格，横屏会自动交换宽高。";
    return @"复制和重置只处理模块配置，不会复制、删除或修改共享素材。";
}

- (NSArray<NSNumber *> *)defaultGridForSlot:(NSInteger)slot {
    return @[@[@2,@2], @[@1,@2], @[@2,@3], @[@3,@2], @[@3,@3]][(NSUInteger)MIN(4, MAX(0, slot))];
}

- (NSString *)summaryForSlot:(NSInteger)slot {
    NSArray<NSDictionary *> *items = CCBGLoadMediaCatalog();
    NSArray<NSString *> *modes = @[@"常显", @"顺序", @"随机"];
    NSInteger mode = MIN(2, MAX(0, [CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue]));
    NSDictionary *selected = CCBGMediaItemNamed(items, CCBGActiveModuleMediaName(slot));
    NSString *mediaName = selected ? CCBGDisplayNameForItem(selected) : @"未选择素材";
    return [NSString stringWithFormat:@"%@ · %@", modes[(NSUInteger)mode], mediaName];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"module"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"module"];
        NSInteger slot = indexPath.row;
        cell.textLabel.text = [NSString stringWithFormat:@"%@ 模块", CCBGModuleDisplayNames()[(NSUInteger)slot]];
        cell.detailTextLabel.text = [self summaryForSlot:slot];
        cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
        cell.imageView.tintColor = slot == CCBGActiveModuleSlot() ? CCBGAppAccentColor() : UIColor.secondaryLabelColor;
        cell.accessoryType = slot == CCBGActiveModuleSlot() ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        NSInteger slot = CCBGActiveModuleSlot();
        NSArray<NSNumber *> *defaults = [self defaultGridForSlot:slot];
        NSInteger width = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", slot, defaults[0]) integerValue]));
        NSInteger height = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", slot, defaults[1]) integerValue]));
        CCBGGridSizePickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"gridFootprint"] ?: [[CCBGGridSizePickerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"gridFootprint"];
        [cell configureWithTitle:@"自定义控制中心占格" width:width height:height maximum:4 target:self action:@selector(gridFootprintSelected:)];
        return cell;
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return CCBGConfiguredModuleSwitch(tableView, @"在控制中心内调尺寸", @"controlCenterResizeEnabled", NO, self, @selector(controlCenterResizeChanged:));
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"applyGrid"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"applyGrid"];
        NSInteger slot = CCBGActiveModuleSlot();
        NSArray<NSNumber *> *defaults = [self defaultGridForSlot:slot];
        NSInteger width = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", slot, defaults[0]) integerValue]));
        NSInteger height = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", slot, defaults[1]) integerValue]));
        cell.textLabel.text = @"重新应用当前尺寸";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld × %ld · 已实时保存", (long)width, (long)height];
        cell.imageView.image = [UIImage systemImageNamed:@"rectangle.arrowtriangle.2.outward"];
        cell.imageView.tintColor = CCBGAppAccentColor();
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tool"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tool"];
    cell.textLabel.text = indexPath.row == 0 ? @"复制当前模块配置到…" : @"重置当前模块配置";
    cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"square.on.square" : @"arrow.counterclockwise"];
    cell.imageView.tintColor = indexPath.row == 0 ? CCBGAppAccentColor() : UIColor.systemRedColor;
    cell.textLabel.textColor = indexPath.row == 0 ? UIColor.labelColor : UIColor.systemRedColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        CCBGWritePreference(@"activeModuleSlot", @(indexPath.row));
        [self.tableView reloadData];
        return;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 2) [self showGridApplyInstructions];
        return;
    }
    if (indexPath.row == 0) [self showCopyTargets];
    else [self confirmReset];
}

- (void)gridFootprintSelected:(UIButton *)sender {
    NSArray<NSString *> *parts = [sender.accessibilityIdentifier componentsSeparatedByString:@"x"];
    if (parts.count != 2) return;
    NSInteger width = MIN(4, MAX(1, parts[0].integerValue));
    NSInteger height = MIN(4, MAX(1, parts[1].integerValue));
    CCBGWriteModulePreferences(@{ @"gridWidth": @(width), @"gridHeight": @(height) }, CCBGActiveModuleSlot());
    // Reconfigure the picker immediately so its highlighted footprint and
    // summary match the value already accepted by Control Center.  Reload
    // only this row to keep the surrounding settings scroll position stable.
    NSIndexPath *gridIndexPath = [NSIndexPath indexPathForRow:0 inSection:1];
    if (self.isViewLoaded && self.tableView.window && [self.tableView numberOfSections] > 1 && [self.tableView numberOfRowsInSection:1] > 0) {
        [self.tableView reloadRowsAtIndexPaths:@[gridIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)showGridApplyInstructions {
    NSInteger slot = CCBGActiveModuleSlot();
    NSArray<NSNumber *> *defaults = [self defaultGridForSlot:slot];
    NSInteger width = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridWidth", slot, defaults[0]) integerValue]));
    NSInteger height = MIN(4, MAX(1, [CCBGReadModulePreference(@"gridHeight", slot, defaults[1]) integerValue]));
    CCBGRequestControlCenterSizeReload();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"已通知重排 %ld × %ld", (long)width, (long)height] message:@"尺寸已保存并发送给控制中心。若控制中心正在显示，收起后重新打开即可看到新尺寸。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)controlCenterResizeChanged:(UISwitch *)sender {
    CCBGWriteModulePreference(@"controlCenterResizeEnabled", CCBGActiveModuleSlot(), @(sender.on));
}

- (void)showCopyTargets {
    NSInteger sourceSlot = CCBGActiveModuleSlot();
    NSString *sourceName = CCBGModuleDisplayNames()[(NSUInteger)sourceSlot];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"复制模块配置" message:[NSString stringWithFormat:@"把 %@ 的独立配置复制到：", sourceName] preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [CCBGModuleDisplayNames() enumerateObjectsUsingBlock:^(NSString *name, NSUInteger index, BOOL *stop) {
        if ((NSInteger)index == sourceSlot) return;
        [menu addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            CCBGCopyModuleConfiguration(sourceSlot, (NSInteger)index);
            [weakSelf.tableView reloadData];
        }]];
    }];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)confirmReset {
    NSInteger slot = CCBGActiveModuleSlot();
    NSString *name = CCBGModuleDisplayNames()[(NSUInteger)slot];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"重置 %@ 模块？", name] message:@"播放、显示和自动化将恢复默认值，共享素材不会被删除。" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"重置配置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        CCBGResetModuleConfiguration(slot);
        [weakSelf.tableView reloadData];
    }]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}
@end


@implementation CCBGAppearanceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"外观";
    self.tableView.sectionHeaderTopPadding = 12;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : CCBGAppThemeOptions().count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"界面风格" : @"主题色"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 1 ? @"主题色会应用到导航、开关、选中状态和主要操作。" : nil; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"appearanceMode"];
        if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"appearanceMode"];
        [cell configureWithTitle:@"界面风格" key:@"appAppearanceMode" items:@[@"跟随系统", @"浅色", @"深色"] selected:[CCBGReadPreference(@"appAppearanceMode", @0) integerValue] target:self action:@selector(appearanceModeChanged:)];
        return cell;
    }
    NSDictionary *option = CCBGAppThemeOptions()[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"accent"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"accent"];
    cell.textLabel.text = option[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:@"circle.fill"];
    cell.imageView.tintColor = option[@"color"];
    cell.accessoryType = [option[@"key"] isEqualToString:CCBGReadPreference(@"appAccentColor", @"teal")] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)appearanceModeChanged:(UISegmentedControl *)sender {
    CCBGWritePreference(@"appAppearanceMode", @(sender.selectedSegmentIndex));
    CCBGApplyAppTheme(self.view.window);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    NSDictionary *option = CCBGAppThemeOptions()[(NSUInteger)indexPath.row];
    CCBGWritePreference(@"appAccentColor", option[@"key"]);
    CCBGApplyAppTheme(self.view.window);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}
@end


@implementation CCBGPlaybackSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"%@ 播放", CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)activePlaybackMode { return [CCBGReadModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @0) integerValue]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? (self.activePlaybackMode == 0 ? 0 : 5) : section == 1 ? 4 : (self.activePlaybackMode == 0 ? 4 : 5); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? (self.activePlaybackMode == 0 ? nil : @"切换") : section == 1 ? @"统一显示" : @"性能"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.activePlaybackMode != 0) return @"图片按切换间隔播放；视频播放结束后切换。";
    if (section == 1) return @"透明度和模糊度属于当前模块。构图只影响展开态，自动会按素材比例完整显示。";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0) return UITableViewAutomaticDimension;
    if (indexPath.row == 1 && ![CCBGReadModulePreference(@"slideshowEnabled", CCBGActiveModuleSlot(), @NO) boolValue]) return 0.01;
    if (indexPath.row == 3 && self.activePlaybackMode != 2) return 0.01;
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = [self tableView:tableView heightForRowAtIndexPath:indexPath];
    cell.hidden = height >= 0 && height < 1.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"启用轮播", @"slideshowEnabled", NO, self, @selector(switchChanged:));
        if (indexPath.row == 1) return [self sliderCell:tableView title:@"切换间隔" key:@"slideshowInterval" fallback:8 minimum:2 maximum:120 format:@"%.0f 秒"];
        if (indexPath.row == 2) return CCBGConfiguredModuleSwitch(tableView, @"记住上次素材", @"rememberLast", YES, self, @selector(switchChanged:));
        if (indexPath.row == 3) return CCBGConfiguredModuleSwitch(tableView, @"每次展开时随机", @"randomOnOpen", NO, self, @selector(switchChanged:));
        return [self sliderCell:tableView title:@"过渡时长" key:@"crossfadeDuration" fallback:0.35 minimum:0.16 maximum:0.60 format:@"%.2f 秒"];
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"启用模糊效果", @"blurEnabled", YES, self, @selector(switchChanged:));
        if (indexPath.row == 1) return [self sliderCell:tableView title:@"模块模糊度" key:@"moduleBlurIntensity" fallback:0 minimum:0 maximum:1 format:@"%.0f%%"];
        if (indexPath.row == 2) return [self sliderCell:tableView title:@"模块透明度" key:@"moduleOpacity" fallback:1 minimum:0.05 maximum:1 format:@"%.0f%%"];
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"expandedDisplayMode"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"expandedDisplayMode"];
        NSInteger mode = [CCBGReadModulePreference(@"expandedDisplayMode", CCBGActiveModuleSlot(), @0) integerValue];
        [cell configureWithTitle:@"展开构图" key:@"expandedDisplayMode" items:@[@"自动", @"完整", @"填充"] selected:MIN(2, MAX(0, mode)) target:self action:@selector(displayModeChanged:)];
        return cell;
    }
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if (self.activePlaybackMode != 0) [rows addObject:@{@"title": @"仅播放收藏素材", @"key": @"favoritesOnly", @"fallback": @NO}];
    [rows addObjectsFromArray:@[
        @{@"title": @"仅充电时播放视频", @"key": @"chargingOnlyVideo", @"fallback": @NO},
        @{@"title": @"低电量模式改用图片", @"key": @"lowPowerStatic", @"fallback": @NO},
        @{@"title": @"展开时显示素材信息", @"key": @"showExpandedCaption", @"fallback": @YES},
        @{@"title": @"手势触感反馈", @"key": @"hapticFeedbackEnabled", @"fallback": @YES},
    ]];
    NSDictionary *row = rows[(NSUInteger)indexPath.row];
    return CCBGConfiguredModuleSwitch(tableView, row[@"title"], row[@"key"], [row[@"fallback"] boolValue], self, @selector(switchChanged:));
}

- (CCBGSliderCell *)sliderCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key fallback:(float)fallback minimum:(float)minimum maximum:(float)maximum format:(NSString *)format {
    CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider"];
    if (!cell) cell = [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"slider"];
    [cell configureWithTitle:title key:key value:[CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @(fallback)) floatValue] minimum:minimum maximum:maximum format:format target:self action:@selector(sliderChanged:)];
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(sender.on));
    UITableViewCell *cell = (UITableViewCell *)sender.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (UITableViewCell *)cell.superview;
    NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (indexPath && indexPath.section == 0 && indexPath.row == 0) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath && indexPath.section == 1 && indexPath.row == 0) {
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath && indexPath.section == 2) {
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}
- (void)sliderChanged:(UISlider *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:CCBGSliderCell.class]) view = view.superview;
    [(CCBGSliderCell *)view refreshValueLabel];
    CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(sender.value));
}
@end


@implementation CCBGGestureSettingsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"手势与触感"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section < 2 ? 4 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"紧凑状态", @"展开状态", @"反馈"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"默认单击选择素材、长按展开。多击手势会优先识别，避免单击抢先触发。";
    if (section == 1) return @"展开后仍可为四种手势分配素材选择或切换动作。";
    return @"触感在手势动作、左右切换以及显示参数调整开始时触发。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) return CCBGConfiguredModuleSwitch(tableView, @"手势触感反馈", @"hapticFeedbackEnabled", YES, self, @selector(hapticChanged:));
    NSArray *names = @[@"SingleTap", @"DoubleTap", @"TripleTap", @"LongPress"];
    NSArray *titles = @[@"单击", @"双击", @"三击", @"长按"];
    NSString *prefix = indexPath.section == 0 ? @"compact" : @"expanded";
    NSString *key = [NSString stringWithFormat:@"%@%@Action", prefix, names[indexPath.row]];
    NSInteger fallback = indexPath.section == 0 && indexPath.row == 0 ? 1 : indexPath.section == 0 && indexPath.row == 3 ? 2 : 0;
    CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"gestureAction"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"gestureAction"];
    [cell configureWithTitle:titles[indexPath.row] key:key items:@[@"无", @"选素材", @"展开", @"上一项", @"下一项"] selected:[CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @(fallback)) integerValue] target:self action:@selector(actionChanged:)];
    return cell;
}
- (void)actionChanged:(UISegmentedControl *)sender { CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(sender.selectedSegmentIndex)); }
- (void)hapticChanged:(UISwitch *)sender { CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(sender.on)); }
@end


@interface CCBGAutomationController ()
@property(nonatomic, strong) NSTimer *statusTimer;
@property(nonatomic, copy) NSString *lastStatusSignature;
@property(nonatomic, copy) NSArray<NSDictionary *> *eligibleItemsSnapshot;
@property(nonatomic) BOOL statusReloadPending;
@end

@implementation CCBGAutomationController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"%@ 自动化", CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.lastStatusSignature = nil;
    self.statusReloadPending = NO;
    [self.statusTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshStatus];
    }];
    [self refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    NSInteger automationSection = section - 1;
    return automationSection == 0 ? 5 : automationSection == 3 ? 4 : 3;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"实时状态", @"昼夜时段", @"浅色 / 深色模式", @"工作日 / 周末", @"电源状态"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"命中优先级：低电量、充电、系统外观、星期、昼夜时段。";
    return section == 4 ? [NSString stringWithFormat:@"以上自动化仅应用于 %@ 模块。", CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self statusCell:tableView row:indexPath.row];
    NSInteger automationSection = indexPath.section - 1;
    if (automationSection == 0) {
        if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"启用昼夜切换", @"scheduleEnabled", NO, self, @selector(switchChanged:));
        if (indexPath.row == 1) return [self timeCell:tableView title:@"白天开始" key:@"dayStartMinutes" fallback:420];
        if (indexPath.row == 2) return [self mediaCell:tableView title:@"白天背景" key:@"dayMedia"];
        if (indexPath.row == 3) return [self timeCell:tableView title:@"夜间开始" key:@"nightStartMinutes" fallback:1140];
        return [self mediaCell:tableView title:@"夜间背景" key:@"nightMedia"];
    }
    if (automationSection == 1) {
        if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"启用外观切换", @"darkModeAutomationEnabled", NO, self, @selector(switchChanged:));
        return [self mediaCell:tableView title:indexPath.row == 1 ? @"浅色模式背景" : @"深色模式背景" key:indexPath.row == 1 ? @"lightModeMedia" : @"darkModeMedia"];
    }
    if (automationSection == 2) {
        if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"启用星期切换", @"weekdayAutomationEnabled", NO, self, @selector(switchChanged:));
        return [self mediaCell:tableView title:indexPath.row == 1 ? @"工作日背景" : @"周末背景" key:indexPath.row == 1 ? @"weekdayMedia" : @"weekendMedia"];
    }
    if (indexPath.row == 0) return CCBGConfiguredModuleSwitch(tableView, @"低电量模式切换", @"lowPowerAutomationEnabled", NO, self, @selector(switchChanged:));
    if (indexPath.row == 1) return [self mediaCell:tableView title:@"低电量背景" key:@"lowPowerMedia"];
    if (indexPath.row == 2) return CCBGConfiguredModuleSwitch(tableView, @"充电时切换", @"chargingAutomationEnabled", NO, self, @selector(switchChanged:));
    return [self mediaCell:tableView title:@"充电背景" key:@"chargingMedia"];
}

- (BOOL)isCharging {
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

- (NSArray<NSDictionary *> *)eligibleAutomationItems {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *item in CCBGMediaItemsForModule(CCBGLoadMediaCatalog(), CCBGActiveModuleSlot())) {
        if (![item[@"enabled"] boolValue]) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) continue;
        [items addObject:item];
    }
    return items;
}

- (UITableViewCell *)statusCell:(UITableView *)tableView row:(NSInteger)row {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"automationStatus"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"automationStatus"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.tintColor = CCBGAppAccentColor();
    if (row == 0) {
        BOOL dark = CCBGSystemUsesDarkAppearance();
        NSInteger weekday = [NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date];
        BOOL weekend = weekday == 1 || weekday == 7;
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", dark ? @"深色模式" : @"浅色模式", weekend ? @"周末" : @"工作日"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", NSProcessInfo.processInfo.lowPowerModeEnabled ? @"低电量模式" : @"正常电量", [self isCharging] ? @"正在充电" : @"未充电"];
        cell.imageView.image = [UIImage systemImageNamed:dark ? @"moon.fill" : @"sun.max.fill"];
    } else {
        NSArray<NSDictionary *> *items = self.eligibleItemsSnapshot ?: @[];
        NSString *name = CCBGAutomationMediaName(items, [self isCharging], CCBGActiveModuleSlot());
        NSDictionary *item = CCBGMediaItemNamed(items, name);
        cell.textLabel.text = @"当前命中素材";
        cell.detailTextLabel.text = item ? CCBGDisplayNameForItem(item) : @"未命中，使用当前播放设置";
        cell.imageView.image = [UIImage systemImageNamed:item ? @"checkmark.circle.fill" : @"minus.circle"];
    }
    return cell;
}

- (void)refreshStatus {
    if (!self.isViewLoaded || !self.view.window) return;
    BOOL dark = CCBGSystemUsesDarkAppearance();
    NSInteger weekday = [NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date];
    BOOL weekend = weekday == 1 || weekday == 7;
    BOOL charging = [self isCharging];
    BOOL lowPower = NSProcessInfo.processInfo.lowPowerModeEnabled;
    NSArray<NSDictionary *> *items = [self eligibleAutomationItems];
    self.eligibleItemsSnapshot = items;
    NSString *hitName = CCBGAutomationMediaName(items, charging, CCBGActiveModuleSlot()) ?: @"";
    NSString *signature = [NSString stringWithFormat:@"%d|%d|%d|%d|%@", dark, weekend, charging, lowPower, hitName];
    if ([signature isEqualToString:self.lastStatusSignature]) return;
    self.lastStatusSignature = signature;
    if (self.tableView.dragging || self.tableView.decelerating) {
        self.statusReloadPending = YES;
        return;
    }
    self.statusReloadPending = NO;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)flushPendingStatusReload {
    if (!self.statusReloadPending || self.tableView.dragging || self.tableView.decelerating) return;
    self.statusReloadPending = NO;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self flushPendingStatusReload];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self flushPendingStatusReload];
}

- (UITableViewCell *)timeCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key fallback:(NSInteger)fallback {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:key];
    UIDatePicker *picker = nil;
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:key];
        picker = [UIDatePicker new];
        picker.datePickerMode = UIDatePickerModeTime;
        picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
        picker.accessibilityIdentifier = key;
        [picker addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = picker;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        picker = (UIDatePicker *)cell.accessoryView;
    }
    cell.textLabel.text = title;
    NSInteger minutes = [CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @(fallback)) integerValue];
    NSDateComponents *components = [NSDateComponents new];
    components.hour = minutes / 60;
    components.minute = minutes % 60;
    picker.date = [NSCalendar.currentCalendar dateFromComponents:components] ?: NSDate.date;
    return cell;
}

- (UITableViewCell *)mediaCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"media"];
    NSString *name = CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @"");
    NSDictionary *item = CCBGMediaItemNamed(CCBGLoadMediaCatalog(), name);
    cell.textLabel.text = title;
    cell.detailTextLabel.text = item ? CCBGDisplayNameForItem(item) : @"默认";
    CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"automation-cell-");
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = key;
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(sender.on));
    [self refreshStatus];
}
- (void)timeChanged:(UIDatePicker *)sender {
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:sender.date];
    CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(components.hour * 60 + components.minute));
    [self refreshStatus];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *key = cell.accessibilityIdentifier;
    if (!key.length || [cell.accessoryView isKindOfClass:UIDatePicker.class]) return;
    __weak typeof(self) weakSelf = self;
    NSInteger slot = CCBGActiveModuleSlot();
    CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:cell.textLabel.text selected:CCBGReadModulePreference(key, slot, @"") completion:^(NSString *fileName) {
        CCBGWriteModulePreference(key, slot, fileName ?: @"");
        [weakSelf.tableView reloadData];
        [weakSelf refreshStatus];
    }];
    [self.navigationController pushViewController:picker animated:YES];
}
@end


@interface CCBGSystemOverlayPlaylistController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *preferenceKey;
@property(nonatomic, copy) NSString *displayTitle;
@property(nonatomic, copy) NSArray<NSDictionary *> *videoItems;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredItems;
@property(nonatomic, strong) NSMutableArray<NSString *> *playlist;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic) NSUInteger searchReloadGeneration;
- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey title:(NSString *)title;
@end

@implementation CCBGSystemOverlayPlaylistController
- (instancetype)initWithPreferenceKey:(NSString *)preferenceKey title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _preferenceKey = [preferenceKey copy];
    _displayTitle = [title copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.displayTitle;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"搜索视频";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray<NSDictionary *> *videos = [NSMutableArray array];
    for (NSDictionary *item in CCBGLoadMediaCatalog()) {
        if ([item[@"enabled"] boolValue] && CCBGIsVideoName(item[@"fileName"]) &&
            [[NSFileManager defaultManager] fileExistsAtPath:CCBGPathForItem(item)]) [videos addObject:item];
    }
    self.videoItems = videos;
    id stored = CCBGReadPreference(self.preferenceKey, @[]);
    self.playlist = [stored isKindOfClass:NSArray.class] ? [stored mutableCopy] : [NSMutableArray array];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.searchReloadGeneration++;
}

- (NSArray<NSDictionary *> *)availableItems { return self.filteredItems ?: self.videoItems; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.playlist.count : self.availableItems.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"当前播放列表" : @"视频素材库"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 0 && !self.playlist.count ? @"未配置时使用全部可用视频。" : nil; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemOverlayPlaylist"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"systemOverlayPlaylist"];
    NSString *name = indexPath.section == 0 ? self.playlist[(NSUInteger)indexPath.row] : self.availableItems[(NSUInteger)indexPath.row][@"fileName"];
    NSDictionary *item = CCBGMediaItemNamed(self.videoItems, name);
    cell.textLabel.text = item ? CCBGDisplayNameForItem(item) : name;
    cell.detailTextLabel.text = item[@"fileName"] ?: @"素材已缺失";
    CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"system-playlist-");
    cell.accessoryType = indexPath.section == 1 && [self.playlist containsObject:name] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    if (source.section != 0 || destination.section != 0) { [tableView reloadData]; return; }
    NSString *name = self.playlist[(NSUInteger)source.row];
    [self.playlist removeObjectAtIndex:(NSUInteger)source.row];
    [self.playlist insertObject:name atIndex:(NSUInteger)destination.row];
    [self savePlaylist];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete || indexPath.section != 0) return;
    [self.playlist removeObjectAtIndex:(NSUInteger)indexPath.row];
    [self savePlaylist];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    NSString *name = self.availableItems[(NSUInteger)indexPath.row][@"fileName"];
    if ([self.playlist containsObject:name]) [self.playlist removeObject:name];
    else [self.playlist addObject:name];
    [self savePlaylist];
    [tableView reloadData];
}

- (void)savePlaylist {
    CCBGWritePreference(self.preferenceKey, self.playlist);
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) self.filteredItems = nil;
    else {
        NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
        for (NSDictionary *item in self.videoItems) {
            if ([CCBGDisplayNameForItem(item) localizedCaseInsensitiveContainsString:query] || [item[@"fileName"] localizedCaseInsensitiveContainsString:query]) [matches addObject:item];
        }
        self.filteredItems = matches;
    }
    NSUInteger generation = ++self.searchReloadGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.searchReloadGeneration || !self.viewIfLoaded.window) return;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    });
}
@end

@interface CCBGSystemModulesController ()
@property(nonatomic) NSInteger selectedOverlayIndex;
@property(nonatomic, strong) UISegmentedControl *overlayControl;
@property(nonatomic, strong) UIScrollView *overlayScrollView;
@property(nonatomic, copy) NSDictionary *genericModule;
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;
@end

@implementation CCBGSystemModulesController
- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) _selectedOverlayIndex = MIN(3, MAX(0, [CCBGReadPreference(@"selectedSystemOverlayIndex", @0) integerValue]));
    return self;
}
- (instancetype)initWithOverlayIndex:(NSInteger)overlayIndex {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _selectedOverlayIndex = MIN(3, MAX(0, overlayIndex));
    return self;
}
- (instancetype)initWithGenericModule:(NSDictionary *)module {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _genericModule = [module copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.genericModule) {
        self.title = self.genericModule[@"name"] ?: @"Control Center Module";
        return;
    }
    self.title = @"系统模块背景";
    self.overlayControl = [[UISegmentedControl alloc] initWithItems:@[@"连接", @"音乐", @"亮度", @"音量"]];
    self.overlayControl.selectedSegmentIndex = self.selectedOverlayIndex;
    [self.overlayControl addTarget:self action:@selector(overlayChanged:) forControlEvents:UIControlEventValueChanged];
    self.overlayControl.frame = CGRectMake(0, 0, 380, 34);
    self.overlayScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(16, 16, MAX(288, CGRectGetWidth(self.tableView.bounds) - 32), 38)];
    self.overlayScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.overlayScrollView.showsHorizontalScrollIndicator = YES;
    self.overlayScrollView.contentSize = CGSizeMake(380, 34);
    [self.overlayScrollView addSubview:self.overlayControl];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 64)];
    [header addSubview:self.overlayScrollView];
    self.tableView.tableHeaderView = header;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.mediaCatalog = CCBGLoadMediaCatalog();
    [self.tableView reloadData];
}

- (void)displayModeChanged:(UISegmentedControl *)sender {
    CCBGWriteModulePreference(sender.accessibilityIdentifier, CCBGActiveModuleSlot(), @(MIN(2, MAX(0, sender.selectedSegmentIndex))));
}

- (void)overlayChanged:(UISegmentedControl *)sender { if (self.genericModule) return; self.selectedOverlayIndex = sender.selectedSegmentIndex; CCBGWritePreference(@"selectedSystemOverlayIndex", @(self.selectedOverlayIndex)); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)overlayIndexForSection:(NSInteger)section { return self.genericModule ? 2 : self.selectedOverlayIndex; }
- (NSInteger)baseRowCountForSection:(NSInteger)section { NSInteger overlay = [self overlayIndexForSection:section]; return overlay == 0 ? 12 : overlay == 1 ? 9 : 8; }
- (BOOL)genericModuleSupportsExpandedPresentation {
    if (!self.genericModule) return NO;
    NSString *prefix = self.genericModule[@"prefix"] ?: @"";
    if ([CCBGReadPreference([prefix stringByAppendingString:@"MediaAboveNative"], @NO) boolValue]) return YES;
    if ([CCBGReadPreference([prefix stringByAppendingString:@"SupportsExpanded"], @NO) boolValue]) return YES;
    NSDictionary *runtime = CCBGReadPreference([prefix stringByAppendingString:@"LastRuntimeMatch"], @{});
    return [runtime isKindOfClass:NSDictionary.class] && [runtime[@"expanded"] boolValue];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.genericModule) return [self genericModuleSupportsExpandedPresentation] ? 11 : 9;
    return [self baseRowCountForSection:section] + 12;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.genericModule ? [NSString stringWithFormat:@"%@ 背景", self.genericModule[@"name"] ?: @"控制中心模块"] : @[@"连接模块背景", @"音乐模块背景", @"亮度模块背景", @"音量模块背景"][[self overlayIndexForSection:section]]; }
- (NSString *)prefixForSection:(NSInteger)section { return self.genericModule ? self.genericModule[@"prefix"] : @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"][[self overlayIndexForSection:section]]; }
- (BOOL)shouldHideRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.genericModule) return NO;
    NSInteger overlay = [self overlayIndexForSection:indexPath.section];
    NSString *prefix = [self prefixForSection:indexPath.section];
    NSInteger compactMode = [CCBGReadPreference([prefix stringByAppendingString:@"CompactPlaybackMode"], @0) integerValue];
    NSInteger expandedMode = [CCBGReadPreference([prefix stringByAppendingString:@"ExpandedPlaybackMode"], @0) integerValue];
    NSInteger base = [self baseRowCountForSection:indexPath.section];
    if (self.genericModule && indexPath.row >= base) return NO;
    if (overlay == 0 && indexPath.row == 3) return expandedMode != 0;
    if (overlay == 0 && indexPath.row >= 4 && indexPath.row <= 6) {
        return expandedMode != 0 || ![CCBGReadPreference([prefix stringByAppendingString:@"FollowNetwork"], @NO) boolValue];
    }
    if (overlay == 1 && indexPath.row == 3) return compactMode != 0 && expandedMode != 0;
    if (indexPath.row == base) return compactMode == 0;
    if (indexPath.row == base + 1) return expandedMode == 0;
    if (indexPath.row == base + 4) return compactMode == 0 && expandedMode == 0;
    if (indexPath.row == base + 6) {
        return (compactMode == 0 && expandedMode == 0) || ![CCBGReadPreference([prefix stringByAppendingString:@"SwipeEnabled"], @YES) boolValue];
    }
    return NO;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self shouldHideRowAtIndexPath:indexPath] ? 0.01 : UITableViewAutomaticDimension;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSInteger overlay = [self overlayIndexForSection:section];
    if (self.genericModule) return [self genericModuleSupportsExpandedPresentation]
        ? @"此模块支持展开，紧凑和展开分别使用自己的素材；可选择素材是否覆盖原生图标和控件。"
        : @"此模块不支持展开，点一下只切换关闭/开启状态素材；可选择素材是否覆盖原生图标和控件。";
    if (overlay == 0) return @"网络跟随只接管展开状态的当前背景；固定、顺序、随机分别记住紧凑与展开状态。";
    if (overlay == 1) return @"未选择固定背景时可使用实时专辑封面；固定、顺序、随机分别记住紧凑与展开状态。";
    return @"紧凑与展开使用独立背景和播放进度；顺序与随机也分别保存最后播放的视频。";
}

- (UITableViewCell *)systemMediaCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemMedia"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"systemMedia"];
    NSDictionary *item = CCBGMediaItemNamed(self.mediaCatalog, CCBGReadPreference(key, @""));
    cell.textLabel.text = title;
    cell.detailTextLabel.text = item ? CCBGDisplayNameForItem(item) : @"默认";
    CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"system-media-cell-");
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = key;
    return cell;
}

- (UITableViewCell *)systemSliderCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key fallback:(CGFloat)fallback maximum:(CGFloat)maximum {
    CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemEffectSlider"];
    if (!cell) cell = [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"systemEffectSlider"];
    CGFloat value = [CCBGReadPreference(key, @(fallback)) floatValue];
    CGFloat minimum = [key hasSuffix:@"Opacity"] ? 0.1 : 0.0;
    [cell configureWithTitle:title key:key value:value minimum:minimum maximum:maximum format:@"%.0f%%" target:self action:@selector(opacityChanged:)];
    cell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    return cell;
}

- (UITableViewCell *)expandedSystemCell:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    NSInteger overlay = [self overlayIndexForSection:indexPath.section];
    NSString *prefix = [self prefixForSection:indexPath.section];
    NSInteger baseRowCount = [self baseRowCountForSection:indexPath.section];
    if (indexPath.row >= baseRowCount) {
        NSInteger featureRow = indexPath.row - baseRowCount;
        if (featureRow == 0 || featureRow == 1) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemOverlayPlaylistRow"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"systemOverlayPlaylistRow"];
            NSString *key = [prefix stringByAppendingString:featureRow == 0 ? @"CompactPlaylist" : @"ExpandedPlaylist"];
            id stored = CCBGReadPreference(key, @[]);
            NSUInteger count = [stored isKindOfClass:NSArray.class] ? [stored count] : 0;
            cell.textLabel.text = featureRow == 0 ? @"紧凑播放列表" : @"展开播放列表";
            cell.detailTextLabel.text = count ? [NSString stringWithFormat:@"%lu 个视频", (unsigned long)count] : @"全部视频";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.accessibilityIdentifier = key;
            return cell;
        }
        if (featureRow == 2 || featureRow == 3) {
            NSString *key = [prefix stringByAppendingString:featureRow == 2 ? @"CompactPlaybackMode" : @"ExpandedPlaybackMode"];
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemOverlayPlaybackMode"];
            if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"systemOverlayPlaybackMode"];
            [cell configureWithTitle:featureRow == 2 ? @"紧凑播放" : @"展开播放" key:key items:@[@"固定", @"顺序", @"随机"] selected:[CCBGReadPreference(key, @0) integerValue] target:self action:@selector(systemSegmentChanged:)];
            return cell;
        }
        NSMutableArray<NSString *> *titles = [@[@"轮播模式允许左右滑动", @"允许长按选择", @"切换触感反馈", @"故障自动跳过", @"展开框适应视频比例", @"素材覆盖原生内容"] mutableCopy];
        NSMutableArray<NSString *> *suffixes = [@[@"SwipeEnabled", @"LongPressEnabled", @"HapticsEnabled", @"AutoSkipFailures", @"AdaptiveExpandedFrame", @"MediaAboveNative"] mutableCopy];
        NSUInteger switchIndex = (NSUInteger)featureRow - 4 - (self.genericModule ? 2 : 0);
        NSString *suffix = suffixes[switchIndex];
        BOOL fallback = [suffix isEqualToString:@"MediaAboveNative"] ? NO : YES;
        return CCBGConfiguredSwitch(tableView, titles[switchIndex], [prefix stringByAppendingString:suffix], fallback, self, @selector(switchChanged:));
    }
    if (indexPath.row == 0) return CCBGConfiguredSwitch(tableView, @"启用", [prefix stringByAppendingString:@"Enabled"], NO, self, @selector(switchChanged:));
    if (indexPath.row == 1) {
        return [self systemMediaCell:tableView title:@"紧凑固定背景" key:[prefix stringByAppendingString:@"CompactMedia"]];
    }
    if (indexPath.row == 2) {
        NSString *fixedTitle = overlay == 0 ? @"展开默认背景" : @"展开固定背景";
        return [self systemMediaCell:tableView title:fixedTitle key:[prefix stringByAppendingString:@"ExpandedMedia"]];
    }
    if (overlay == 0) {
        if (indexPath.row == 3) return CCBGConfiguredSwitch(tableView, @"展开时跟随网络", [prefix stringByAppendingString:@"FollowNetwork"], NO, self, @selector(switchChanged:));
        if (indexPath.row == 4) return [self systemMediaCell:tableView title:@"Wi-Fi 背景" key:[prefix stringByAppendingString:@"WiFiMedia"]];
        if (indexPath.row == 5) return [self systemMediaCell:tableView title:@"蜂窝背景" key:[prefix stringByAppendingString:@"CellularMedia"]];
        if (indexPath.row == 6) return [self systemMediaCell:tableView title:@"离线背景" key:[prefix stringByAppendingString:@"OfflineMedia"]];
    } else if (overlay == 1) {
        if (indexPath.row == 3) return CCBGConfiguredSwitch(tableView, @"未选背景时使用实时封面", [prefix stringByAppendingString:@"UseArtwork"], YES, self, @selector(switchChanged:));
    }
    NSInteger compactModeRow = overlay == 0 ? 7 : overlay == 1 ? 4 : 3;
    NSInteger expandedModeRow = overlay == 0 ? 8 : overlay == 1 ? 5 : 4;
    if (indexPath.row == compactModeRow || indexPath.row == expandedModeRow) {
        NSString *modeSuffix = indexPath.row == compactModeRow ? @"CompactContentMode" : @"ExpandedContentMode";
        NSString *title = indexPath.row == compactModeRow ? @"紧凑适配" : @"展开适配";
        NSString *key = [prefix stringByAppendingString:modeSuffix];
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemAdaptiveContentMode"];
        if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"systemAdaptiveContentMode"];
        [cell configureWithTitle:title key:key items:@[@"完整", @"填充"] selected:[CCBGReadPreference(key, @1) integerValue] target:self action:@selector(systemSegmentChanged:)];
        return cell;
    }
    NSInteger effectIndex = indexPath.row - expandedModeRow;
    if (effectIndex == 1) return [self systemSliderCell:tableView title:@"背景透明度" key:[prefix stringByAppendingString:@"Opacity"] fallback:0.65 maximum:1.0];
    if (effectIndex == 2) return [self systemSliderCell:tableView title:@"背景模糊" key:[prefix stringByAppendingString:@"Blur"] fallback:0 maximum:1.0];
    if (effectIndex == 3) return [self systemSliderCell:tableView title:@"压暗强度" key:[prefix stringByAppendingString:@"Dim"] fallback:0 maximum:0.85];
    return [self systemSliderCell:tableView title:@"背景透明度" key:[prefix stringByAppendingString:@"Opacity"] fallback:0.65 maximum:1.0];
}

- (UITableViewCell *)genericSystemCell:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    NSString *prefix = [self prefixForSection:indexPath.section];
    BOOL usesPresentationMedia = [self genericModuleSupportsExpandedPresentation];
    if (indexPath.row == 0) {
        return CCBGConfiguredSwitch(tableView, @"启用", [prefix stringByAppendingString:@"Enabled"], NO, self, @selector(switchChanged:));
    }
    if (indexPath.row == 1) {
        return [self systemMediaCell:tableView title:usesPresentationMedia ? @"紧凑素材" : @"关闭状态素材" key:[prefix stringByAppendingString:usesPresentationMedia ? @"CompactMedia" : @"StateOffMedia"]];
    }
    if (indexPath.row == 2) {
        return [self systemMediaCell:tableView title:usesPresentationMedia ? @"展开素材" : @"开启状态素材" key:[prefix stringByAppendingString:usesPresentationMedia ? @"ExpandedMedia" : @"StateOnMedia"]];
    }
    if (indexPath.row == 3) {
        if (usesPresentationMedia) {
            NSString *key = [prefix stringByAppendingString:@"CompactContentMode"];
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"genericCompactContentMode"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"genericCompactContentMode"];
            [cell configureWithTitle:@"紧凑显示" key:key items:@[@"完整", @"填充"] selected:[CCBGReadPreference(key, @1) integerValue] target:self action:@selector(systemSegmentChanged:)];
            return cell;
        }
        return CCBGConfiguredSwitch(tableView, @"允许长按选择当前状态素材", [prefix stringByAppendingString:@"LongPressEnabled"], YES, self, @selector(switchChanged:));
    }
    if (indexPath.row == 4) {
        NSString *key = [prefix stringByAppendingString:usesPresentationMedia ? @"ExpandedContentMode" : @"ContentMode"];
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"genericStateContentMode"];
        if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"genericStateContentMode"];
        [cell configureWithTitle:usesPresentationMedia ? @"展开显示" : @"显示方式" key:key items:@[@"完整", @"填充"] selected:[CCBGReadPreference(key, @1) integerValue] target:self action:@selector(systemSegmentChanged:)];
        return cell;
    }
    if (indexPath.row == 5) return [self systemSliderCell:tableView title:@"背景透明度" key:[prefix stringByAppendingString:@"Opacity"] fallback:0.65 maximum:1.0];
    if (indexPath.row == 6) return [self systemSliderCell:tableView title:@"背景模糊" key:[prefix stringByAppendingString:@"Blur"] fallback:0 maximum:1.0];
    if (indexPath.row == 7) return CCBGConfiguredSwitch(tableView, @"素材覆盖原生内容", [prefix stringByAppendingString:@"MediaAboveNative"], NO, self, @selector(switchChanged:));
    return [self systemSliderCell:tableView title:@"压暗强度" key:[prefix stringByAppendingString:@"Dim"] fallback:0 maximum:0.85];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger base = [self baseRowCountForSection:indexPath.section];
    BOOL compositionRow = self.genericModule ? ([self genericModuleSupportsExpandedPresentation] && indexPath.row >= 9) : indexPath.row >= base + 10;
    if (compositionRow) {
        BOOL expanded = self.genericModule ? indexPath.row == 10 : indexPath.row == base + 11;
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"systemComposition"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"systemComposition"];
        cell.textLabel.text = expanded ? @"展开可视化构图" : @"紧凑可视化构图";
        cell.detailTextLabel.text = @"拖动焦点，双指缩放";
        cell.imageView.image = [UIImage systemImageNamed:@"crop"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = self.genericModule ? [self genericSystemCell:tableView indexPath:indexPath] : [self expandedSystemCell:tableView indexPath:indexPath];
    cell.hidden = [self shouldHideRowAtIndexPath:indexPath];
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    CCBGWritePreference(sender.accessibilityIdentifier, @(sender.on));
    UITableViewCell *cell = (UITableViewCell *)sender.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (UITableViewCell *)cell.superview;
    NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (!indexPath) return;
    // System switches can reveal or hide neighbouring rows (network state,
    // playlist controls, swipe options). Refresh only this section so the
    // structure stays correct without rebuilding the whole settings table.
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)systemSegmentChanged:(UISegmentedControl *)sender {
    NSString *key = sender.accessibilityIdentifier;
    CCBGWritePreference(key, @(sender.selectedSegmentIndex));
    UITableViewCell *cell = (UITableViewCell *)sender.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class]) cell = (UITableViewCell *)cell.superview;
    NSIndexPath *indexPath = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (indexPath) [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)opacityChanged:(UISlider *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:CCBGSliderCell.class]) view = view.superview;
    CCBGSliderCell *cell = (CCBGSliderCell *)view;
    cell.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    CCBGWritePreference(sender.accessibilityIdentifier, @(sender.value));
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger compositionBase = [self baseRowCountForSection:indexPath.section];
    BOOL compositionRow = self.genericModule ? ([self genericModuleSupportsExpandedPresentation] && indexPath.row >= 9) : indexPath.row >= compositionBase + 10;
    if (compositionRow) {
        BOOL expanded = self.genericModule ? indexPath.row == 10 : indexPath.row == compositionBase + 11;
        NSString *prefix = [self prefixForSection:indexPath.section];
        NSString *currentKey = [prefix stringByAppendingString:expanded ? @"ExpandedCurrentMedia" : @"CompactCurrentMedia"];
        NSString *fixedKey = [prefix stringByAppendingString:expanded ? @"ExpandedMedia" : @"CompactMedia"];
        NSString *mediaName = CCBGReadPreference(currentKey, @"");
        if (!mediaName.length) mediaName = CCBGReadPreference(fixedKey, @"");
        NSDictionary *item = CCBGMediaItemNamed(CCBGLoadMediaCatalog(), mediaName);
        if (!item) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"请先选择素材" message:expanded ? @"先设置展开素材，再编辑展开构图。" : @"先设置紧凑素材，再编辑紧凑构图。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSInteger overlay = [self overlayIndexForSection:indexPath.section];
        CGFloat compactRatio = (overlay == 2 || overlay == 3) ? 0.5 : 1.0;
        CCBGCompositionEditorController *editor = [[CCBGCompositionEditorController alloc] initWithSystemMediaItem:item preferencePrefix:prefix compactAspectRatio:compactRatio expandedAspectRatio:1.0];
        [editor setInitialExpandedMode:expanded];
        [self.navigationController pushViewController:editor animated:YES];
        return;
    }
    if (self.genericModule) {
        if (indexPath.row != 1 && indexPath.row != 2) return;
        NSString *prefix = [self prefixForSection:indexPath.section];
        BOOL usesPresentationMedia = [self genericModuleSupportsExpandedPresentation];
        NSString *suffix = indexPath.row == 1
            ? (usesPresentationMedia ? @"CompactMedia" : @"StateOffMedia")
            : (usesPresentationMedia ? @"ExpandedMedia" : @"StateOnMedia");
        NSString *key = [prefix stringByAppendingString:suffix];
        __weak typeof(self) weakSelf = self;
        NSString *title = usesPresentationMedia ? (indexPath.row == 1 ? @"紧凑素材" : @"展开素材") : (indexPath.row == 1 ? @"关闭状态素材" : @"开启状态素材");
        CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:title selected:CCBGReadPreference(key, @"") completion:^(NSString *fileName) {
            NSMutableDictionary<NSString *, id> *changes = [@{
                key: fileName ?: @"",
                [prefix stringByAppendingString:@"Enabled"]: @YES,
            } mutableCopy];
            CCBGWritePreferences(changes);
            [weakSelf.tableView reloadData];
        }];
        [self.navigationController pushViewController:picker animated:YES];
        return;
    }
    NSInteger overlay = [self overlayIndexForSection:indexPath.section];
    NSInteger baseRowCount = [self baseRowCountForSection:indexPath.section];
    if (indexPath.row == baseRowCount || indexPath.row == baseRowCount + 1) {
        NSString *prefix = [self prefixForSection:indexPath.section];
        BOOL compact = indexPath.row == baseRowCount;
        NSString *key = [prefix stringByAppendingString:compact ? @"CompactPlaylist" : @"ExpandedPlaylist"];
        NSString *moduleName = self.genericModule ? (self.genericModule[@"name"] ?: @"模块") : @[@"连接", @"音乐", @"亮度", @"音量"][overlay];
        NSString *title = [NSString stringWithFormat:@"%@%@播放列表", moduleName, compact ? @"紧凑" : @"展开"];
        [self.navigationController pushViewController:[[CCBGSystemOverlayPlaylistController alloc] initWithPreferenceKey:key title:title] animated:YES];
        return;
    }
    if (indexPath.row == 1 || indexPath.row == 2 || (overlay == 0 && indexPath.row >= 4 && indexPath.row <= 6)) {
        NSString *suffix = indexPath.row == 1 ? @"CompactMedia" : indexPath.row == 2 ? @"ExpandedMedia" : indexPath.row == 4 ? @"WiFiMedia" : indexPath.row == 5 ? @"CellularMedia" : @"OfflineMedia";
        NSString *prefix = [self prefixForSection:indexPath.section];
        NSString *key = [prefix stringByAppendingString:suffix];
        __weak typeof(self) weakSelf = self;
        CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:@"选择系统模块背景" selected:CCBGReadPreference(key, @"") completion:^(NSString *fileName) {
            NSMutableDictionary<NSString *, id> *changes = [@{
                key: fileName ?: @"",
                [prefix stringByAppendingString:@"Enabled"]: @YES,
            } mutableCopy];
            CCBGWritePreferences(changes);
            [weakSelf.tableView reloadData];
        }];
        [self.navigationController pushViewController:picker animated:YES];
        return;
    }
}
@end


@implementation CCBGFiveModuleDefaultController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"五模块默认与恢复";
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 5 : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"五个模块分别设置" : @"控制中心操作"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"每个尺寸保存自己的默认素材，不会读取其他模块配置。" : @"应用前保存五个模块的播放模式与素材，恢复时只还原本次操作修改的状态。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fiveModuleDefault"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"fiveModuleDefault"];
    BOOL mediaRow = indexPath.section == 0;
    cell.imageView.image = [UIImage systemImageNamed:mediaRow ? @"film" : indexPath.row == 0 ? @"checkmark.circle" : @"arrow.uturn.backward.circle"];
    cell.imageView.tintColor = CCBGAppAccentColor();
    cell.textLabel.text = mediaRow ? [NSString stringWithFormat:@"%@ 默认素材", CCBGModuleDisplayNames()[indexPath.row]] : indexPath.row == 0 ? @"应用五个默认素材" : @"恢复五个模块之前状态";
    cell.textLabel.textColor = UIColor.labelColor;
    cell.userInteractionEnabled = YES;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (mediaRow) {
        NSDictionary *item = CCBGMediaItemNamed(CCBGLoadMediaCatalog(), CCBGReadModulePreference(@"defaultOverrideMedia", indexPath.row, @""));
        cell.detailTextLabel.text = item ? CCBGDisplayNameForItem(item) : @"未设置";
        CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"five-default-");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 1 && ![CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil) isKindOfClass:NSDictionary.class]) {
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.userInteractionEnabled = NO;
    } else if (indexPath.section == 1 && indexPath.row == 0 && !CCBGFiveModuleDefaultsReady()) {
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = @"请先设置五个默认素材";
        cell.userInteractionEnabled = NO;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSInteger slot = indexPath.row;
        __weak typeof(self) weakSelf = self;
        NSString *title = [NSString stringWithFormat:@"选择 %@ 默认素材", CCBGModuleDisplayNames()[slot]];
        CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:title selected:CCBGReadModulePreference(@"defaultOverrideMedia", slot, @"") completion:^(NSString *fileName) {
            CCBGWriteModulePreference(@"defaultOverrideMedia", slot, fileName ?: @"");
            [weakSelf.tableView reloadData];
        }];
        [self.navigationController pushViewController:picker animated:YES];
    } else if (indexPath.row == 0) {
        CCBGApplyFiveModuleDefaultMedia();
        [self.tableView reloadData];
    } else {
        CCBGRestoreFiveModuleMedia();
        [self.tableView reloadData];
    }
}
@end


@interface CCBGDiagnosticsController () <UIDocumentPickerDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *statusRows;
@property(nonatomic) BOOL awaitingBackupImport;
- (NSUInteger)invalidMediaReferenceCount;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)diagnosticStatusRows;
- (NSArray<NSString *> *)diagnosticMaintenanceTitles;
- (void)rebuildThumbnailCache;
- (void)cleanInvalidReferences;
- (void)confirmClearAllConfiguration;
@end

@implementation CCBGDiagnosticsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"诊断与备份";
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStatus];
}
- (void)reloadStatus {
    self.items = CCBGLoadMediaCatalog();
    self.statusRows = [self diagnosticStatusRows];
    [self.tableView reloadData];
}
- (NSUInteger)invalidMediaReferenceCount {
    NSMutableSet<NSString *> *validNames = [NSMutableSet set];
    for (id rawItem in self.items ?: @[]) {
        if (![rawItem isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = rawItem;
        NSString *name = item[@"fileName"];
        if ([name isKindOfClass:NSString.class] && name.length) [validNames addObject:name];
    }
    NSUInteger count = 0;
    for (NSUInteger slot = 0; slot < CCBGModuleDisplayNames().count; slot++) {
        for (NSString *key in CCBGModuleMediaReferenceKeys()) {
            NSString *name = CCBGReadModulePreference(key, slot, @"");
            if ([name isKindOfClass:NSString.class] && name.length && ![validNames containsObject:name]) count++;
        }
        NSArray *rules = CCBGReadModulePreference(@"compoundRules", slot, @[]);
        if ([rules isKindOfClass:NSArray.class]) for (id rawRule in rules) {
            if (![rawRule isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *rule = rawRule;
            NSString *name = rule[@"media"];
            if ([name isKindOfClass:NSString.class] && name.length && ![validNames containsObject:name]) count++;
        }
    }
    for (NSString *key in CCBGSystemMediaReferenceKeys()) {
        NSString *name = CCBGReadPreference(key, @"");
        if ([name isKindOfClass:NSString.class] && name.length && ![validNames containsObject:name]) count++;
    }
    return count;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)diagnosticStatusRows {
    NSString *(^text)(id, NSString *) = ^NSString *(id value, NSString *fallback) {
        return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
    };
    NSInteger slot = CCBGActiveModuleSlot();
    NSDictionary *current = CCBGMediaItemNamed(self.items, CCBGActiveModuleMediaName(slot));
    NSString *version = text([NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"], @"未知");
    return @[
        @{@"title": @"版本", @"value": version},
        @{@"title": @"媒体数量", @"value": [NSString stringWithFormat:@"%lu", (unsigned long)self.items.count]},
        @{@"title": @"媒体占用", @"value": text(CCBGReadableBytes(CCBGMediaStorageBytes()), @"未知")},
        @{@"title": @"当前素材", @"value": current ? text(CCBGDisplayNameForItem(current), @"无") : @"无"},
        @{@"title": @"失效引用", @"value": [NSString stringWithFormat:@"%lu", (unsigned long)[self invalidMediaReferenceCount]]},
        @{@"title": @"连接模块视图", @"value": text(CCBGReadPreference(@"connectivityOverlayLastPresentation", @"未检测"), @"未检测")},
        @{@"title": @"音乐模块视图", @"value": text(CCBGReadPreference(@"musicOverlayLastPresentation", @"未检测"), @"未检测")},
        @{@"title": @"音乐播放状态", @"value": text(CCBGReadPreference(@"musicOverlayPlaybackState", @"未检测"), @"未检测")},
    ];
}

- (NSArray<NSString *> *)diagnosticMaintenanceTitles {
    return @[@"立即刷新模块", @"重建媒体索引", @"清理缩略图缓存", @"导出诊断报告", @"在 Filza 打开素材目录", @"重建预览缓存", @"清理失效引用", @"清除日志"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.statusRows.count : section == 1 ? self.diagnosticMaintenanceTitles.count : section == 2 ? 2 : (section == 3 || section == 4) ? 1 : 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"状态", @"维护", @"设置备份", @"配置重置", @"媒体存储"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) return @"备份包含五个模块、自动化、场景和系统模块设置，不包含素材文件。";
    if (section == 3) return @"清除所有配置、场景、自动化、备份、缩略图和运行缓存；素材文件会保留。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"value"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"value"];
        NSArray *rows = self.statusRows ?: @[];
        NSDictionary *row = (NSUInteger)indexPath.row < rows.count ? rows[(NSUInteger)indexPath.row] : @{};
        cell.textLabel.text = row[@"title"] ?: @"";
        cell.detailTextLabel.text = row[@"value"] ?: @"";
        BOOL showsDetails = indexPath.row == (NSInteger)rows.count - 1;
        cell.selectionStyle = showsDetails ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessoryType = showsDetails ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = self.view.tintColor;
    if (indexPath.section == 1) {
        NSArray *titles = self.diagnosticMaintenanceTitles;
        cell.textLabel.text = (NSUInteger)indexPath.row < titles.count ? titles[(NSUInteger)indexPath.row] : @"";
    }
    if (indexPath.section == 2) cell.textLabel.text = indexPath.row == 0 ? @"导出设置备份" : @"恢复设置备份";
    if (indexPath.section == 3) {
        cell.textLabel.text = @"清除所有配置";
        cell.textLabel.textColor = UIColor.systemRedColor;
    }
    if (indexPath.section == 4) {
        cell.textLabel.text = @"删除全部媒体";
        cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 7) {
        NSString *state = CCBGReadPreference(@"musicOverlayPlaybackState", @"未检测到音乐模块播放状态");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"音乐播放状态" message:state preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = state;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    else if (indexPath.section == 1 && indexPath.row == 0) CCBGPostReload();
    else if (indexPath.section == 1 && indexPath.row == 1) {
        CCBGPruneMissingMediaConfigurations();
        CCBGSaveMediaCatalog(CCBGLoadMediaCatalog());
        [self reloadStatus];
    }
    else if (indexPath.section == 1 && indexPath.row == 2) [self clearThumbnailCache];
    else if (indexPath.section == 1 && indexPath.row == 3) [self exportDiagnosticReport];
    else if (indexPath.section == 1 && indexPath.row == 4) [self openMediaDirectoryInFilza];
    else if (indexPath.section == 1 && indexPath.row == 5) [self rebuildThumbnailCache];
    else if (indexPath.section == 1 && indexPath.row == 6) [self cleanInvalidReferences];
    else if (indexPath.section == 1 && indexPath.row == 7) [self clearLogs];
    else if (indexPath.section == 2 && indexPath.row == 0) [self exportBackup];
    else if (indexPath.section == 2 && indexPath.row == 1) [self importBackup];
    else if (indexPath.section == 3) [self confirmClearAllConfiguration];
    else if (indexPath.section == 4) [self confirmClearMedia];
}

- (void)clearThumbnailCache {
    NSString *path = @"/var/mobile/Library/CleanCCBG2x2/Thumbnails";
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (void)rebuildThumbnailCache {
    NSArray<NSDictionary *> *items = [self.items copy] ?: @[];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"预览缓存" message:@"正在后台重建缩略图。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (NSDictionary *item in items) {
            @autoreleasepool {
                CCBGThumbnailForItem(item, CGSizeMake(54, 54));
                CCBGThumbnailForItem(item, CGSizeMake(180, 100));
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadStatus]; });
    });
}

- (void)cleanInvalidReferences {
    CCBGPruneMissingMediaConfigurations();
    CCBGSaveMediaCatalog(CCBGLoadMediaCatalog());
    [self reloadStatus];
}

- (void)clearLogs {
    CCBGClearModuleLifecycleTrace();
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    for (NSUInteger slot = 0; slot < CCBGModuleDisplayNames().count; slot++) {
        changes[CCBGPreferenceKeyForModule(@"playbackHistory", slot)] = @[];
        changes[CCBGPreferenceKeyForModule(@"recentMedia", slot)] = @[];
    }
    CCBGWritePreferences(changes);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志已清除" message:@"模块生命周期日志、播放历史和最近播放记录已清空。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openMediaDirectoryInFilza {
    NSURL *url = CCBGFilzaURLForPath(CCBGMediaDirectoryPath);
    if (url && [UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开 Filza" message:CCBGMediaDirectoryPath preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportDiagnosticReport {
    self.awaitingBackupImport = NO;
    NSMutableArray *media = [NSMutableArray array];
    for (NSDictionary *item in self.items) {
        NSString *path = CCBGPathForItem(item);
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        [media addObject:@{
            @"fileName": item[@"fileName"] ?: @"",
            @"displayName": CCBGDisplayNameForItem(item),
            @"video": @(CCBGIsVideoName(item[@"fileName"])),
            @"enabled": @([item[@"enabled"] boolValue]),
            @"favorite": @([item[@"favorite"] boolValue]),
            @"exists": @([[NSFileManager defaultManager] fileExistsAtPath:path]),
            @"bytes": @([attributes[NSFileSize] unsignedLongLongValue]),
        }];
    }
    NSMutableArray *modules = [NSMutableArray array];
    [CCBGModuleDisplayNames() enumerateObjectsUsingBlock:^(NSString *name, NSUInteger slot, BOOL *stop) {
        [modules addObject:@{
            @"name": name,
            @"slot": @(slot),
            @"selectedMedia": CCBGReadModulePreference(@"selectedMedia", slot, @""),
            @"currentMedia": CCBGReadModulePreference(@"currentMedia", slot, @""),
            @"playbackMode": CCBGReadModulePreference(@"playbackMode", slot, @0),
            @"scheduleEnabled": CCBGReadModulePreference(@"scheduleEnabled", slot, @NO),
            @"appearanceAutomationEnabled": CCBGReadModulePreference(@"darkModeAutomationEnabled", slot, @NO),
            @"weekdayAutomationEnabled": CCBGReadModulePreference(@"weekdayAutomationEnabled", slot, @NO),
            @"lowPowerAutomationEnabled": CCBGReadModulePreference(@"lowPowerAutomationEnabled", slot, @NO),
            @"chargingAutomationEnabled": CCBGReadModulePreference(@"chargingAutomationEnabled", slot, @NO),
        }];
    }];
    NSMutableArray *genericOverlays = [NSMutableArray array];
    id genericConfigured = CCBGReadPreference(@"customSystemOverlayModules", @[]);
    if ([genericConfigured isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)genericConfigured) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSString *prefix = [value[@"prefix"] isKindOfClass:NSString.class] ? value[@"prefix"] : @"";
            if (!prefix.length) continue;
            [genericOverlays addObject:@{
                @"identifier": value[@"identifier"] ?: @"",
                @"name": value[@"name"] ?: value[@"identifier"] ?: @"",
                @"principalClass": value[@"principalClass"] ?: @"",
                @"prefix": prefix,
                @"enabled": CCBGReadPreference([prefix stringByAppendingString:@"Enabled"], @NO),
                @"compactMedia": CCBGReadPreference([prefix stringByAppendingString:@"CompactMedia"], @""),
                @"expandedMedia": CCBGReadPreference([prefix stringByAppendingString:@"ExpandedMedia"], @""),
                @"lastRuntimeMatch": CCBGReadPreference([prefix stringByAppendingString:@"LastRuntimeMatch"], @{}),
                @"takeoverCleanLongPress": CCBGReadPreference([prefix stringByAppendingString:@"TakeoverCleanLongPress"], @{}),
                @"takeoverNativeExpansionBlocked": CCBGReadPreference([prefix stringByAppendingString:@"TakeoverNativeExpansionBlocked"], @{}),
            }];
        }
    }
    NSArray<NSDictionary *> *sceneTimeline = CCBGSceneTimeline();
    NSUInteger sceneTimelineCount = sceneTimeline.count;
    if (sceneTimeline.count > 20) sceneTimeline = [sceneTimeline subarrayWithRange:NSMakeRange(0, 20)];
    id storedSceneRuntimeContext = CCBGReadPreference(@"sceneDirectorLastRuntimeContext", @{});
    NSDictionary *sceneRuntimeContext = [storedSceneRuntimeContext isKindOfClass:NSDictionary.class] ? storedSceneRuntimeContext : @{};
    NSDictionary *resolvedSceneValue = CCBGSceneDirectorResolvedScene(sceneRuntimeContext);
    NSDictionary *(^sceneConditionSummary)(id) = ^NSDictionary *(id value) {
        NSDictionary *conditions = [value isKindOfClass:NSDictionary.class] ? value : @{};
        NSString *focus = [conditions[@"focus"] isKindOfClass:NSString.class] ? conditions[@"focus"] : @"";
        BOOL focusEnabled = [conditions[@"focusEnabled"] respondsToSelector:@selector(boolValue)] ? [conditions[@"focusEnabled"] boolValue] : focus.length > 0;
        return @{
            @"locked": [conditions[@"locked"] respondsToSelector:@selector(integerValue)] ? @([conditions[@"locked"] integerValue]) : @-1,
            @"dark": [conditions[@"dark"] respondsToSelector:@selector(integerValue)] ? @([conditions[@"dark"] integerValue]) : @-1,
            @"charging": [conditions[@"charging"] respondsToSelector:@selector(integerValue)] ? @([conditions[@"charging"] integerValue]) : @-1,
            @"landscape": [conditions[@"landscape"] respondsToSelector:@selector(integerValue)] ? @([conditions[@"landscape"] integerValue]) : @-1,
            @"focusEnabled": @(focusEnabled),
            @"focus": focus,
        };
    };
    NSDictionary *resolvedScene = [resolvedSceneValue isKindOfClass:NSDictionary.class] ? @{
        @"id": [resolvedSceneValue[@"id"] isKindOfClass:NSString.class] ? resolvedSceneValue[@"id"] : @"",
        @"name": [resolvedSceneValue[@"name"] isKindOfClass:NSString.class] ? resolvedSceneValue[@"name"] : @"",
        @"priority": [resolvedSceneValue[@"priority"] respondsToSelector:@selector(integerValue)] ? @([resolvedSceneValue[@"priority"] integerValue]) : @0,
        @"conditions": sceneConditionSummary(resolvedSceneValue[@"conditions"]),
    } : @{};
    NSString *resolvedSceneID = resolvedScene[@"id"] ?: @"";
    NSMutableArray<NSDictionary *> *sceneConditions = [NSMutableArray array];
    id storedScenes = CCBGReadPreference(@"sceneDirectorScenes", @[]);
    if ([storedScenes isKindOfClass:NSArray.class]) for (id candidate in (NSArray *)storedScenes) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        NSString *sceneID = [candidate[@"id"] isKindOfClass:NSString.class] ? candidate[@"id"] : @"";
        if (!sceneID.length) continue;
        [sceneConditions addObject:@{
            @"id": sceneID,
            @"name": [candidate[@"name"] isKindOfClass:NSString.class] ? candidate[@"name"] : @"",
            @"enabled": @([candidate[@"enabled"] respondsToSelector:@selector(boolValue)] && [candidate[@"enabled"] boolValue]),
            @"priority": [candidate[@"priority"] respondsToSelector:@selector(integerValue)] ? @([candidate[@"priority"] integerValue]) : @0,
            @"conditions": sceneConditionSummary(candidate[@"conditions"]),
            @"resolved": @([sceneID isEqualToString:resolvedSceneID]),
        }];
    }
    NSDictionary *report = @{
        @"generatedAt": @((long long)NSDate.date.timeIntervalSince1970),
        @"appVersion": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"unknown",
        @"deviceModel": UIDevice.currentDevice.model ?: @"unknown",
        @"mediaStorageBytes": @(CCBGMediaStorageBytes()),
        @"activeModule": CCBGModuleDisplayNames()[CCBGActiveModuleSlot()],
        @"selectedMedia": CCBGReadModulePreference(@"selectedMedia", CCBGActiveModuleSlot(), @""),
        @"currentMedia": CCBGReadModulePreference(@"currentMedia", CCBGActiveModuleSlot(), @""),
        @"playbackMode": CCBGReadModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @0),
        @"invalidMediaReferences": @([self invalidMediaReferenceCount]),
        @"connectivityOverlayLastPresentation": CCBGReadPreference(@"connectivityOverlayLastPresentation", @""),
        @"musicOverlayLastPresentation": CCBGReadPreference(@"musicOverlayLastPresentation", @""),
        @"musicOverlayPlaybackState": CCBGReadPreference(@"musicOverlayPlaybackState", @""),
        @"musicOverlayEnabled": CCBGReadPreference(@"musicOverlayEnabled", @NO),
        @"musicOverlayVideo": CCBGReadPreference(@"musicOverlayVideo", @YES),
        @"musicOverlayUseArtwork": CCBGReadPreference(@"musicOverlayUseArtwork", @YES),
        @"musicOverlayCompactMedia": CCBGReadPreference(@"musicOverlayCompactMedia", @""),
        @"musicOverlayExpandedMedia": CCBGReadPreference(@"musicOverlayExpandedMedia", @""),
        @"musicOverlayCompactCurrentMedia": CCBGReadPreference(@"musicOverlayCompactCurrentMedia", @""),
        @"musicOverlayExpandedCurrentMedia": CCBGReadPreference(@"musicOverlayExpandedCurrentMedia", @""),
        @"connectivityOverlayCompactMedia": CCBGReadPreference(@"connectivityOverlayCompactMedia", @""),
        @"connectivityOverlayExpandedMedia": CCBGReadPreference(@"connectivityOverlayExpandedMedia", @""),
        @"connectivityOverlayCompactCurrentMedia": CCBGReadPreference(@"connectivityOverlayCompactCurrentMedia", @""),
        @"connectivityOverlayExpandedCurrentMedia": CCBGReadPreference(@"connectivityOverlayExpandedCurrentMedia", @""),
        @"connectivityOverlayVideo": CCBGReadPreference(@"connectivityOverlayVideo", @YES),
        @"focusDiscovery": CCBGFocusDiscoveryStatus(),
        @"knownFocusModes": CCBGReadPreference(@"sceneDirectorKnownFocusModes", @[]),
        @"lastFocusAliases": CCBGReadPreference(@"sceneDirectorLastFocusAliases", @[]),
        @"sceneRuntimeContext": sceneRuntimeContext,
        @"darkAppearance": @{
            @"springBoard": CCBGReadPreference(@"sceneDirectorLastDarkAppearanceDiagnostics", @{}),
            @"app": CCBGDarkAppearanceDiagnostics(),
        },
        @"resolvedScene": resolvedScene,
        @"sceneDirectorManualSceneID": CCBGReadPreference(@"sceneDirectorManualSceneID", @""),
        @"sceneConditions": sceneConditions,
        @"sceneTimelineCount": @(sceneTimelineCount),
        @"sceneTimeline": sceneTimeline,
        @"moduleLifecycleTrace": CCBGReadModuleLifecycleTrace(),
        @"genericSystemOverlays": genericOverlays,
        @"modules": modules,
        @"media": media,
    };
    NSError *error = nil;
    if (![NSJSONSerialization isValidJSONObject:report]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法导出" message:@"诊断数据包含不支持的值。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CleanCCBG2x2-diagnostics.json"];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法导出" message:error.localizedDescription ?: @"无法写入诊断文件。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:path]] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)exportBackup {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CleanCCBG2x2-settings.json"];
    self.awaitingBackupImport = NO;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在导出设置" message:@"正在后台整理配置，请稍候。" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(CCBGSettingsBackupQueue(), ^{
        NSDictionary *backup = @{
            @"format": @4,
            @"createdAt": @((long long)NSDate.date.timeIntervalSince1970),
            @"appVersion": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
            @"preferences": CCBGConfigurationPreferencesSnapshot(),
        };
        NSError *error = nil;
        NSData *data = [NSJSONSerialization isValidJSONObject:backup]
            ? [NSJSONSerialization dataWithJSONObject:backup options:NSJSONWritingPrettyPrinted error:&error] : nil;
        BOOL success = data && [data writeToFile:path options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (!success) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法导出" message:error.localizedDescription ?: @"备份包含不支持的值。" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:path]] asCopy:YES];
                picker.delegate = self;
                [self presentViewController:picker animated:YES completion:nil];
            }];
        });
    });
}

- (void)importBackup {
    self.awaitingBackupImport = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.awaitingBackupImport) return;
    self.awaitingBackupImport = NO;
    NSURL *url = urls.firstObject;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    id backupObject = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *backup = [backupObject isKindOfClass:NSDictionary.class] ? backupObject : nil;
    NSDictionary *preferences = [backup[@"preferences"] isKindOfClass:NSDictionary.class] ? backup[@"preferences"] : nil;
    NSInteger format = [backup[@"format"] integerValue];
    BOOL validPropertyList = preferences && [NSPropertyListSerialization propertyList:preferences isValidForFormat:NSPropertyListBinaryFormat_v1_0];
    if (!preferences || format < 1 || format > 4 || !validPropertyList) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法恢复备份" message:@"文件格式无效或包含不受支持的数据。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"恢复全部设置？" message:@"当前五个模块的独立配置和系统模块背景设置将被备份内容替换；素材文件不会被删除。" preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf applyBackupPreferences:preferences];
    }]];
    confirm.popoverPresentationController.sourceView = self.view;
    confirm.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.awaitingBackupImport = NO;
}

- (void)applyBackupPreferences:(NSDictionary *)preferences {
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在恢复全部设置" message:@"正在写入并校验配置，请稍候。" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(CCBGSettingsBackupQueue(), ^{
        NSError *error = nil;
        BOOL restored = CCBGRestorePreferencesSnapshot(preferences, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [progress dismissViewControllerAnimated:YES completion:^{
                [self reloadStatus];
                UIAlertController *result = [UIAlertController alertControllerWithTitle:restored ? @"设置已恢复" : @"恢复失败" message:restored ? @"五模块、自动化、场景和系统模块配置已校验并重新载入，素材文件保持不变。" : (error.localizedDescription ?: @"无法恢复配置。") preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:result animated:YES completion:nil];
            }];
        });
    });
}

- (void)confirmClearAllConfiguration {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"清除所有配置？" message:@"将清除五模块设置、自动化、场景、系统模块设置、备份、缩略图和运行缓存。素材文件会保留。" preferredStyle:UIAlertControllerStyleActionSheet];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"清除所有配置" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在清除配置" message:@"素材文件会保留，请稍候。" preferredStyle:UIAlertControllerStyleAlert];
        [weakSelf presentViewController:progress animated:YES completion:nil];
        dispatch_async(CCBGSettingsBackupQueue(), ^{
            NSError *error = nil;
            BOOL cleared = CCBGClearAllConfigurationPreservingMedia(&error);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                [progress dismissViewControllerAnimated:YES completion:^{
                    [self reloadStatus];
                    UIAlertController *result = [UIAlertController alertControllerWithTitle:cleared ? @"配置已清除" : @"清除失败" message:cleared ? @"所有配置和缓存已清除，素材文件会保留。" : (error.localizedDescription ?: @"无法清除配置。") preferredStyle:UIAlertControllerStyleAlert];
                    [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:result animated:YES completion:nil];
                }];
            });
        });
    }]];
    confirm.popoverPresentationController.sourceView = self.view;
    confirm.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)confirmClearMedia {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除全部媒体？" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSMutableArray<NSDictionary *> *removedItems = [NSMutableArray array];
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        for (NSDictionary *item in weakSelf.items) {
            NSString *path = CCBGPathForItem(item);
            NSError *error = nil;
            BOOL removed = ![[NSFileManager defaultManager] fileExistsAtPath:path] || [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
            if (removed) [removedItems addObject:item];
            else [failures addObject:[NSString stringWithFormat:@"%@：%@", CCBGDisplayNameForItem(item), error.localizedDescription ?: @"未知错误"]];
        }
        if (removedItems.count == weakSelf.items.count) {
            CCBGRemoveAllMediaConfigurations();
        } else {
            for (NSDictionary *item in removedItems) CCBGRemoveMediaConfigurationFromAllModules(item[@"fileName"]);
        }
        CCBGSaveMediaCatalog(CCBGLoadMediaCatalog());
        [weakSelf reloadStatus];
        if (failures.count) {
            UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"部分素材删除失败" message:[failures componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:failure animated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
