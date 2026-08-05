#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <CoreFoundation/CoreFoundation.h>

static NSArray<NSString *> *CCBGSceneMediaTargets(void) {
    return @[@"module0", @"module1", @"module2", @"module3", @"module4",
             @"connectivityOverlayCompact", @"connectivityOverlayExpanded",
             @"musicOverlayCompact", @"musicOverlayExpanded",
             @"brightnessOverlayCompact", @"brightnessOverlayExpanded",
             @"volumeOverlayCompact", @"volumeOverlayExpanded"];
}

static NSDictionary *CCBGSceneDictionaryValue(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *CCBGSceneArrayValue(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSString *CCBGSceneStringValue(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSInteger CCBGSceneIntegerValue(id value, NSInteger fallback) {
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

static BOOL CCBGSceneBoolValue(id value, BOOL fallback) {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static NSArray<NSDictionary *> *CCBGSceneDictionaryArrayValue(id value) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id entry in CCBGSceneArrayValue(value)) {
        if ([entry isKindOfClass:NSDictionary.class]) [result addObject:entry];
    }
    return result;
}

static NSArray<NSDictionary *> *CCBGStoredScenes(void) {
    return CCBGSceneDictionaryArrayValue(CCBGReadPreference(@"sceneDirectorScenes", @[]));
}

static NSArray<NSDictionary *> *CCBGConfiguredGenericModules(void) {
    return CCBGSceneDictionaryArrayValue(CCBGReadPreference(@"customSystemOverlayModules", @[]));
}

static NSString *CCBGSceneTargetTitle(NSString *target) {
    NSDictionary *titles = @{
        @"module0": @"2x2", @"module1": @"1x2", @"module2": @"2x3", @"module3": @"3x2", @"module4": @"3x3",
        @"connectivityOverlayCompact": @"连接模块紧凑", @"connectivityOverlayExpanded": @"连接模块展开",
        @"musicOverlayCompact": @"音乐模块紧凑", @"musicOverlayExpanded": @"音乐模块展开",
        @"brightnessOverlayCompact": @"亮度模块紧凑", @"brightnessOverlayExpanded": @"亮度模块展开",
        @"volumeOverlayCompact": @"音量模块紧凑", @"volumeOverlayExpanded": @"音量模块展开",
    };
    return titles[target] ?: target;
}

static NSString *CCBGSceneStateTitle(NSString *state) {
    return @{ @"off": @"关闭", @"on": @"开启", @"loading": @"加载中", @"unavailable": @"不可用" }[state] ?: state;
}

@interface CCBGSceneSlotPickerController : UITableViewController
- (instancetype)initWithSource:(NSInteger)source selected:(NSArray<NSNumber *> *)selected completion:(void (^)(NSArray<NSNumber *> *))completion;
@end

@interface CCBGSceneSlotPickerController ()
@property(nonatomic) NSInteger source;
@property(nonatomic, strong) NSMutableOrderedSet<NSNumber *> *selectedSlots;
@property(nonatomic, copy) void (^completion)(NSArray<NSNumber *> *slots);
@end

@implementation CCBGSceneSlotPickerController
- (instancetype)initWithSource:(NSInteger)source selected:(NSArray<NSNumber *> *)selected completion:(void (^)(NSArray<NSNumber *> *))completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _source = source; _selectedSlots = [NSMutableOrderedSet orderedSetWithArray:selected ?: @[]]; _completion = [completion copy]; self.title = @"接力目标"; }
    return self;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return CCBGModuleDisplayNames().count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slot"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"slot"];
    NSNumber *slot = @(indexPath.row); cell.textLabel.text = CCBGModuleDisplayNames()[(NSUInteger)indexPath.row];
    cell.textLabel.textColor = indexPath.row == self.source ? UIColor.secondaryLabelColor : UIColor.labelColor;
    cell.selectionStyle = indexPath.row == self.source ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.accessoryType = [self.selectedSlots containsObject:slot] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if (indexPath.row == self.source) return;
    NSNumber *slot = @(indexPath.row); if ([self.selectedSlots containsObject:slot]) [self.selectedSlots removeObject:slot]; else [self.selectedSlots addObject:slot];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if (self.isMovingFromParentViewController && self.completion) self.completion(self.selectedSlots.array); }
@end

@interface CCBGSceneFocusPickerController : UITableViewController
- (instancetype)initWithSelectedName:(NSString *)selected completion:(void (^)(NSString *name))completion;
@end

@interface CCBGSceneFocusPickerController ()
@property(nonatomic, copy) NSString *selectedName;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *modes;
@property(nonatomic, copy) void (^completion)(NSString *name);
@end

@implementation CCBGSceneFocusPickerController
- (instancetype)initWithSelectedName:(NSString *)selected completion:(void (^)(NSString *))completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _selectedName = [selected copy] ?: @""; _completion = [completion copy]; self.title = @"专注模式"; }
    return self;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.modes = CCBGAvailableFocusModes();
    [self.tableView reloadData];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)CCBGFocusRefreshNotificationName,
                                         NULL, NULL, YES);
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delayValue in @[@0.6, @1.8]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayValue.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !self.view.window || self.modes.count) return;
            self.modes = CCBGRefreshFocusModeCache();
            [self.tableView reloadData];
        });
    }
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.modes.count + 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.modes.count) return @"列表由 SpringBoard 自动读取。";
    NSDictionary *springBoard = CCBGFocusDiscoveryStatus()[@"springboard"];
    if (![springBoard isKindOfClass:NSDictionary.class] || !springBoard.count) return @"正在请求 SpringBoard 读取专注模式…";
    NSArray *serviceClasses = [springBoard[@"serviceClasses"] isKindOfClass:NSArray.class] ? springBoard[@"serviceClasses"] : @[];
    NSArray *fileResults = [springBoard[@"fileResults"] isKindOfClass:NSArray.class] ? springBoard[@"fileResults"] : @[];
    NSUInteger readableFiles = 0;
    for (NSDictionary *file in fileResults) if ([file[@"bytes"] unsignedIntegerValue] > 0) readableFiles++;
    return [NSString stringWithFormat:@"SpringBoard 已响应：框架 %@，服务类 %lu 个，可读配置 %lu 个，提取结果 0。可在“诊断与备份”中导出详细状态。",
            [springBoard[@"frameworkLoaded"] boolValue] ? @"已加载" : @"未加载",
            (unsigned long)serviceClasses.count, (unsigned long)readableFiles];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"focus"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"focus"];
    NSString *name = @"";
    if (indexPath.row == 0) {
        cell.textLabel.text = @"清除已选模式";
        cell.detailTextLabel.text = @"启用专注条件时需要选择具体模式";
    } else {
        NSDictionary *mode = self.modes[(NSUInteger)indexPath.row - 1];
        name = mode[@"name"] ?: @"";
        cell.textLabel.text = name;
        NSArray *aliases = [mode[@"aliases"] isKindOfClass:NSArray.class] ? mode[@"aliases"] : @[];
        cell.detailTextLabel.text = aliases.count > 1 ? [aliases componentsJoinedByString:@" · "] : nil;
    }
    cell.accessoryType = [name isEqualToString:self.selectedName] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = indexPath.row == 0 ? @"" : (self.modes[(NSUInteger)indexPath.row - 1][@"name"] ?: @"");
    if (self.completion) self.completion(name);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface CCBGSceneStateTrackEditorController : UITableViewController
- (instancetype)initWithSceneID:(NSString *)sceneID target:(NSString *)target;
@end

@interface CCBGMediaHealthController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@end

@implementation CCBGMediaHealthController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"素材健康度"; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSDictionary *rank = @{@"不推荐": @0, @"需关注": @1, @"未检测": @2, @"良好": @3};
    self.items = [CCBGLoadMediaCatalog() sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftRank = [rank[left[@"healthStatus"] ?: @"未检测"] integerValue];
        NSInteger rightRank = [rank[right[@"healthStatus"] ?: @"未检测"] integerValue];
        if (leftRank != rightRank) return leftRank < rightRank ? NSOrderedAscending : NSOrderedDescending;
        return [CCBGDisplayNameForItem(left) localizedCaseInsensitiveCompare:CCBGDisplayNameForItem(right)];
    }];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"health"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"health"];
    NSString *status = item[@"healthStatus"] ?: @"未检测";
    cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", CCBGDisplayNameForItem(item), status];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"首帧 %.2f 秒 · 平均播放 %.1f 秒\n启动 %@ · 失败 %@ · 内存压力 %@",
        [item[@"healthAverageFirstFrameLatency"] doubleValue], [item[@"healthAveragePlaybackDuration"] doubleValue],
        item[@"healthSuccessfulStarts"] ?: @0, item[@"healthFailureCount"] ?: @0, item[@"healthMemoryPressureCount"] ?: @0];
    cell.textLabel.textColor = [status isEqualToString:@"不推荐"] ? UIColor.systemRedColor : [status isEqualToString:@"需关注"] ? UIColor.systemOrangeColor : UIColor.labelColor;
    CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"scene-health-");
    return cell;
}
@end

@interface CCBGSceneEditorController ()
@property(nonatomic, copy) NSString *sceneID;
@property(nonatomic, copy) NSDictionary *scene;
@property(nonatomic, copy) NSArray<NSDictionary *> *genericModules;
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;
@end

@implementation CCBGSceneEditorController
- (instancetype)initWithScene:(NSDictionary *)scene { self = [super initWithStyle:UITableViewStyleInsetGrouped]; if (self) _sceneID = [CCBGSceneStringValue(scene[@"id"]) copy]; return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"场景"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self loadScene]; }
- (void)loadScene {
    self.scene = nil;
    self.genericModules = CCBGConfiguredGenericModules();
    self.mediaCatalog = CCBGLoadMediaCatalog();
    for (NSDictionary *candidate in CCBGStoredScenes()) if ([CCBGSceneStringValue(candidate[@"id"]) isEqualToString:self.sceneID]) { self.scene = candidate; break; }
    if (!self.scene) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSString *name = CCBGSceneStringValue(self.scene[@"name"]); self.title = name.length ? name : @"场景"; [self.tableView reloadData];
}
- (void)updateScene:(void (^)(NSMutableDictionary *scene))mutation event:(NSString *)event {
    NSMutableArray *scenes = [CCBGStoredScenes() mutableCopy];
    NSUInteger index = [scenes indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) { return [CCBGSceneStringValue(candidate[@"id"]) isEqualToString:self.sceneID]; }];
    if (index == NSNotFound) return; NSMutableDictionary *updated = [scenes[index] mutableCopy]; mutation(updated); scenes[index] = updated;
    CCBGWritePreference(@"sceneDirectorScenes", scenes); CCBGRecordSceneTimelineEvent(event, @{ @"sceneID": self.sceneID ?: @"" }); self.scene = updated; [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 4 : section == 1 ? 6 : section == 2 ? CCBGSceneMediaTargets().count : section == 3 ? 1 + self.genericModules.count : section == 4 ? 5 : 6;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"场景", @"自动条件", @"素材目标", @"第三方状态轨道", @"跨模块接力", @"视觉策略"][(NSUInteger)section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"多个自动场景同时满足时，优先级数值更高的场景生效。";
    if (section == 1) return @"已启用的条件必须同时满足。自动场景至少启用一个条件；专注条件关闭后会保留已选择的模式。";
    if (section == 4) return @"仅在当前场景命中时生效。双击来源模块触发，并把素材同步到已选目标模块。";
    if (section == 5) return @"仅在当前场景命中时生效。低电量模式下暂停视频并显示封面帧；呼吸网格在展开五模块时压暗其余模块；感应式构图只调整填充素材的裁切焦点。";
    return nil;
}
- (UITableViewCell *)valueCell:(UITableView *)tableView title:(NSString *)title detail:(NSString *)detail key:(NSString *)key {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:key] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:key];
    cell.textLabel.text = title; cell.detailTextLabel.text = detail; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *conditions = CCBGSceneDictionaryValue(self.scene[@"conditions"]);
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"enabled"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"enabled"]; [cell configureWithTitle:@"已启用" key:@"enabled" value:CCBGSceneBoolValue(self.scene[@"enabled"], NO) target:self action:@selector(switchChanged:)]; return cell; }
        if (indexPath.row == 1) { CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"activation"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"activation"]; BOOL manual = [CCBGSceneStringValue(CCBGReadPreference(@"sceneDirectorManualSceneID", @"")) isEqualToString:self.sceneID]; [cell configureWithTitle:@"启用方式" key:@"activation" items:@[@"自动", @"手动"] selected:manual ? 1 : 0 target:self action:@selector(segmentChanged:)]; return cell; }
        if (indexPath.row == 2) { CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"priority"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"priority"]; [cell configureWithTitle:@"优先级" key:@"priority" items:@[@"1", @"2", @"3", @"4", @"5"] selected:MAX(0, MIN(4, CCBGSceneIntegerValue(self.scene[@"priority"], 1) - 1)) target:self action:@selector(segmentChanged:)]; return cell; }
        return [self valueCell:tableView title:@"重命名" detail:CCBGSceneStringValue(self.scene[@"name"]) key:@"rename"];
    }
    if (indexPath.section == 1) {
        if (indexPath.row < 4) {
            NSArray *keys = @[@"locked", @"dark", @"charging", @"landscape"]; NSArray *titles = @[@"锁屏", @"深色模式", @"充电中", @"横屏"];
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:keys[(NSUInteger)indexPath.row]] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:keys[(NSUInteger)indexPath.row]];
            NSInteger value = CCBGSceneIntegerValue(conditions[keys[(NSUInteger)indexPath.row]], -1); [cell configureWithTitle:titles[(NSUInteger)indexPath.row] key:[@"condition." stringByAppendingString:keys[(NSUInteger)indexPath.row]] items:@[@"任意", @"是", @"否"] selected:value < 0 ? 0 : value ? 1 : 2 target:self action:@selector(segmentChanged:)]; return cell;
        }
        NSString *focus = CCBGSceneStringValue(conditions[@"focus"]);
        if (indexPath.row == 4) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"focusEnabled"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"focusEnabled"]; BOOL enabled = [conditions[@"focusEnabled"] respondsToSelector:@selector(boolValue)] ? [conditions[@"focusEnabled"] boolValue] : focus.length > 0; [cell configureWithTitle:@"启用专注条件" key:@"focusEnabled" value:enabled target:self action:@selector(switchChanged:)]; return cell; }
        return [self valueCell:tableView title:@"专注模式" detail:focus.length ? focus : @"未选择" key:@"focus"];
    }
    if (indexPath.section == 2) { NSString *target = CCBGSceneMediaTargets()[(NSUInteger)indexPath.row]; NSDictionary *targets = CCBGSceneDictionaryValue(self.scene[@"targets"]); NSDictionary *item = CCBGMediaItemNamed(self.mediaCatalog, CCBGSceneStringValue(targets[target])); return [self valueCell:tableView title:CCBGSceneTargetTitle(target) detail:CCBGDisplayNameForItem(item) ?: @"未设置" key:target]; }
    if (indexPath.section == 3) {
        if (indexPath.row == 0) return [self valueCell:tableView title:@"全部第三方模块" detail:@"关闭、开启、加载中、不可用" key:@"stateTracks"];
        NSDictionary *module = self.genericModules[(NSUInteger)indexPath.row - 1]; NSString *name = CCBGSceneStringValue(module[@"name"]); if (!name.length) name = CCBGSceneStringValue(module[@"identifier"]); return [self valueCell:tableView title:name.length ? name : @"第三方模块" detail:@"独立设置关闭、开启、加载中、不可用" key:CCBGSceneStringValue(module[@"prefix"]).length ? CCBGSceneStringValue(module[@"prefix"]) : @"generic"];
    }
    if (indexPath.section == 4) {
        NSDictionary *relay = CCBGSceneDictionaryValue(self.scene[@"relay"]);
        if (indexPath.row == 0) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"relayEnabled"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"relayEnabled"]; [cell configureWithTitle:@"启用接力" key:@"relayEnabled" value:CCBGSceneBoolValue(relay[@"enabled"], NO) target:self action:@selector(switchChanged:)]; return cell; }
        if (indexPath.row == 1) { CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"relaySource"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"relaySource"]; [cell configureWithTitle:@"来源模块" key:@"relaySource" items:CCBGModuleDisplayNames() selected:MIN(4, MAX(0, CCBGSceneIntegerValue(relay[@"sourceSlot"], 0))) target:self action:@selector(segmentChanged:)]; return cell; }
        if (indexPath.row == 2) return [self valueCell:tableView title:@"目标模块" detail:[NSString stringWithFormat:@"已选择 %lu 个", (unsigned long)CCBGSceneArrayValue(relay[@"targetSlots"]).count] key:@"relayTargets"];
        if (indexPath.row == 3) return [self valueCell:tableView title:@"按目标覆盖素材" detail:@"可选" key:@"relayMedia"];
        return [self valueCell:tableView title:@"接力状态与测试" detail:[self currentSceneIsResolved] ? @"当前场景已命中" : @"当前场景未命中" key:@"relayStatus"];
    }
    if (indexPath.section == 5) {
        if (indexPath.row == 0) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"lowPower"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"lowPower"]; [cell configureWithTitle:@"低电量使用封面帧" key:@"lowPower" value:CCBGSceneBoolValue(self.scene[@"lowPowerStatic"], NO) target:self action:@selector(switchChanged:)]; return cell; }
        if (indexPath.row == 1) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"breathing"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"breathing"]; [cell configureWithTitle:@"呼吸网格" key:@"breathing" value:CCBGSceneBoolValue(self.scene[@"breathingGridEnabled"], NO) target:self action:@selector(switchChanged:)]; return cell; }
        if (indexPath.row == 2) { CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"adaptiveCompositionEnabled"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"adaptiveCompositionEnabled"]; [cell configureWithTitle:@"感应式构图" key:@"adaptiveCompositionEnabled" value:CCBGSceneBoolValue(self.scene[@"adaptiveCompositionEnabled"], NO) target:self action:@selector(switchChanged:)]; return cell; }
        if (indexPath.row == 3) return [self valueCell:tableView title:@"当前命中" detail:CCBGSceneDirectorResolvedScene(self.currentSceneContext)[@"name"] ?: @"没有自动命中" key:@"match"];
        if (indexPath.row == 4) return [self valueCell:tableView title:@"素材健康度" detail:[NSString stringWithFormat:@"%lu 个素材", (unsigned long)self.mediaCatalog.count] key:@"health"];
        return [self valueCell:tableView title:@"视觉策略状态" detail:[self currentSceneIsResolved] ? @"当前场景已命中" : @"当前场景未命中" key:@"visualStatus"];
    }
    return [UITableViewCell new];
}
- (void)switchChanged:(UISwitch *)sender { NSString *key = sender.accessibilityIdentifier; if ([key isEqualToString:@"focusEnabled"]) [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *updatedConditions = [CCBGSceneDictionaryValue(scene[@"conditions"]) mutableCopy]; updatedConditions[@"focusEnabled"] = @(sender.on); scene[@"conditions"] = updatedConditions; } event:@"scene-condition"]; else if ([key isEqualToString:@"relayEnabled"]) [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *relay = [CCBGSceneDictionaryValue(scene[@"relay"]) mutableCopy]; relay[@"enabled"] = @(sender.on); scene[@"relay"] = relay; } event:@"scene-relay"]; else [self updateScene:^(NSMutableDictionary *scene) { scene[[key isEqualToString:@"lowPower"] ? @"lowPowerStatic" : [key isEqualToString:@"breathing"] ? @"breathingGridEnabled" : key] = @(sender.on); } event:@"scene-setting"]; }
- (void)segmentChanged:(UISegmentedControl *)sender {
    NSString *key = sender.accessibilityIdentifier;
    if ([key isEqualToString:@"activation"]) { CCBGWritePreference(@"sceneDirectorManualSceneID", sender.selectedSegmentIndex ? self.sceneID : @""); CCBGRecordSceneTimelineEvent(@"scene-activation", @{ @"sceneID": self.sceneID ?: @"", @"manual": @(sender.selectedSegmentIndex) }); [self.tableView reloadData]; return; }
    if ([key isEqualToString:@"priority"]) { [self updateScene:^(NSMutableDictionary *scene) { scene[@"priority"] = @(sender.selectedSegmentIndex + 1); } event:@"scene-priority"]; return; }
    if ([key isEqualToString:@"relaySource"]) { [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *relay = [CCBGSceneDictionaryValue(scene[@"relay"]) mutableCopy]; relay[@"sourceSlot"] = @(sender.selectedSegmentIndex); relay[@"targetSlots"] = CCBGSceneArrayValue(relay[@"targetSlots"]); scene[@"relay"] = relay; } event:@"scene-relay"]; return; }
    if ([key hasPrefix:@"condition."]) { NSString *condition = [key substringFromIndex:10]; NSInteger value = sender.selectedSegmentIndex == 0 ? -1 : sender.selectedSegmentIndex == 1 ? 1 : 0; [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *conditions = [CCBGSceneDictionaryValue(scene[@"conditions"]) mutableCopy]; conditions[condition] = @(value); scene[@"conditions"] = conditions; } event:@"scene-condition"]; }
}
- (void)presentTextAlert:(NSString *)title value:(NSString *)value completion:(void (^)(NSString *text))completion { UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = value ?: @""; }]; [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(alert.textFields.firstObject.text ?: @""); }]]; [self presentViewController:alert animated:YES completion:nil]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3) { [self presentTextAlert:@"场景名称" value:self.scene[@"name"] completion:^(NSString *text) { [self updateScene:^(NSMutableDictionary *scene) { scene[@"name"] = text.length ? text : @"场景"; } event:@"scene-renamed"]; }]; return; }
    if (indexPath.section == 1 && indexPath.row == 5) { NSDictionary *conditions = CCBGSceneDictionaryValue(self.scene[@"conditions"]); CCBGSceneFocusPickerController *picker = [[CCBGSceneFocusPickerController alloc] initWithSelectedName:CCBGSceneStringValue(conditions[@"focus"]) completion:^(NSString *name) { [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *updatedConditions = [CCBGSceneDictionaryValue(scene[@"conditions"]) mutableCopy]; updatedConditions[@"focus"] = name ?: @""; scene[@"conditions"] = updatedConditions; } event:@"scene-focus"]; }]; [self.navigationController pushViewController:picker animated:YES]; return; }
    if (indexPath.section == 2) { NSString *target = CCBGSceneMediaTargets()[(NSUInteger)indexPath.row]; NSDictionary *targets = CCBGSceneDictionaryValue(self.scene[@"targets"]); NSString *selected = CCBGSceneStringValue(targets[target]); CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:CCBGSceneTargetTitle(target) selected:selected completion:^(NSString *name) { [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *updatedTargets = [CCBGSceneDictionaryValue(scene[@"targets"]) mutableCopy]; updatedTargets[target] = name ?: @""; scene[@"targets"] = updatedTargets; } event:@"scene-target"]; }]; [self.navigationController pushViewController:picker animated:YES]; return; }
    if (indexPath.section == 3) {
        NSString *target = @"generic";
        if (indexPath.row > 0) {
            NSDictionary *module = self.genericModules[(NSUInteger)indexPath.row - 1];
            if ([module[@"prefix"] isKindOfClass:NSString.class] && [module[@"prefix"] length]) target = module[@"prefix"];
        }
        [self.navigationController pushViewController:[[CCBGSceneStateTrackEditorController alloc] initWithSceneID:self.sceneID target:target] animated:YES]; return;
    }
    if (indexPath.section == 4 && indexPath.row == 2) { NSDictionary *relay = CCBGSceneDictionaryValue(self.scene[@"relay"]); NSInteger source = MIN(4, MAX(0, CCBGSceneIntegerValue(relay[@"sourceSlot"], 0))); CCBGSceneSlotPickerController *picker = [[CCBGSceneSlotPickerController alloc] initWithSource:source selected:CCBGSceneArrayValue(relay[@"targetSlots"]) completion:^(NSArray<NSNumber *> *slots) { [self updateScene:^(NSMutableDictionary *scene) { NSMutableDictionary *copy = [CCBGSceneDictionaryValue(scene[@"relay"]) mutableCopy]; copy[@"targetSlots"] = slots; scene[@"relay"] = copy; } event:@"scene-relay"]; }]; [self.navigationController pushViewController:picker animated:YES]; return; }
    if (indexPath.section == 4 && indexPath.row == 3) { [self configureRelayMedia]; return; }
    if (indexPath.section == 4 && indexPath.row == 4) { [self showRelayStatus]; return; }
    if (indexPath.section == 5 && indexPath.row == 3) { [self showVisualStrategyStatus]; return; }
    if (indexPath.section == 5 && indexPath.row == 4) { [self.navigationController pushViewController:[CCBGMediaHealthController new] animated:YES]; }
    if (indexPath.section == 5 && indexPath.row == 5) { [self showVisualStrategyStatus]; }
}
- (NSDictionary *)currentSceneContext {
    NSDictionary *springBoardContext = CCBGReadPreference(@"sceneDirectorLastRuntimeContext", @{});
    if ([springBoardContext isKindOfClass:NSDictionary.class] && springBoardContext.count) return springBoardContext;
    return CCBGSceneRuntimeContext(self.view);
}
- (BOOL)currentSceneIsResolved {
    NSString *resolvedID = CCBGSceneStringValue(CCBGSceneDirectorResolvedScene(self.currentSceneContext)[@"id"]);
    return resolvedID.length && [resolvedID isEqualToString:self.sceneID];
}
- (NSString *)currentSceneEligibilityText {
    NSDictionary *evaluation = CCBGSceneDirectorEvaluationForScene(self.scene, self.currentSceneContext);
    NSArray *reasons = CCBGSceneArrayValue(evaluation[@"reasons"]);
    if ([evaluation[@"matches"] boolValue]) return [self currentSceneIsResolved] ? @"当前场景已命中" : @"条件已满足，但被更高优先级场景覆盖";
    return reasons.count ? [reasons componentsJoinedByString:@"；"] : @"当前场景未命中";
}
- (void)showRelayStatus {
    NSDictionary *relay = CCBGSceneDictionaryValue(self.scene[@"relay"]);
    NSInteger source = MIN(4, MAX(0, CCBGSceneIntegerValue(relay[@"sourceSlot"], 0)));
    NSArray *targets = CCBGSceneArrayValue(relay[@"targetSlots"]);
    NSArray *names = CCBGModuleDisplayNames();
    NSMutableArray *targetNames = [NSMutableArray array];
    for (id rawSlot in targets) {
        NSInteger slot = [rawSlot respondsToSelector:@selector(integerValue)] ? [rawSlot integerValue] : -1;
        if (slot >= 0 && (NSUInteger)slot < names.count && slot != source) [targetNames addObject:names[(NSUInteger)slot]];
    }
    BOOL enabled = CCBGSceneBoolValue(relay[@"enabled"], NO);
    NSString *sourceMedia = CCBGActiveModuleMediaName(source);
    BOOL ready = enabled && self.currentSceneIsResolved && targetNames.count && sourceMedia.length;
    NSString *message = [NSString stringWithFormat:@"使用方法：当此场景生效时，在控制中心双击来源模块，目标模块会切换到接力素材。\n\n场景：%@\n接力开关：%@\n来源：%@\n目标：%@\n来源当前素材：%@",
                         self.currentSceneEligibilityText, enabled ? @"开启" : @"关闭", names[(NSUInteger)source],
                         targetNames.count ? [targetNames componentsJoinedByString:@"、"] : @"未选择",
                         sourceMedia.length ? sourceMedia : @"未设置"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ready ? @"接力可以使用" : @"接力尚不可用" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *test = [UIAlertAction actionWithTitle:@"立即测试接力" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        BOOL applied = CCBGSceneDirectorRelayFromSlotInContext(source, sourceMedia, self.currentSceneContext);
        UIAlertController *result = [UIAlertController alertControllerWithTitle:applied ? @"接力已执行" : @"接力未执行" message:applied ? @"重新打开控制中心即可查看目标模块。" : @"请确认当前场景已命中、接力已开启并且已选择目标模块。" preferredStyle:UIAlertControllerStyleAlert];
        [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:result animated:YES completion:nil];
    }];
    test.enabled = ready;
    [alert addAction:test];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showVisualStrategyStatus {
    BOOL resolved = self.currentSceneIsResolved;
    BOOL lowPowerEnabled = CCBGSceneBoolValue(self.scene[@"lowPowerStatic"], NO);
    BOOL systemLowPower = NSProcessInfo.processInfo.lowPowerModeEnabled;
    BOOL breathing = CCBGSceneBoolValue(self.scene[@"breathingGridEnabled"], NO);
    BOOL adaptive = CCBGSceneBoolValue(self.scene[@"adaptiveCompositionEnabled"], NO);
    NSString *message = [NSString stringWithFormat:@"场景：%@\n\n低电量模式封面帧：%@\n系统低电量模式：%@\n仅在两项都开启且当前素材为视频时生效。\n\n呼吸网格：%@\n展开任意五模块后，其余五模块会变暗。\n\n感应式构图：%@\n仅对填充显示的素材生效，会按模块在控制中心的位置调整裁切焦点。",
                         self.currentSceneEligibilityText,
                         lowPowerEnabled ? (resolved && systemLowPower ? @"正在生效" : @"已开启，等待条件") : @"关闭",
                         systemLowPower ? @"开启" : @"关闭",
                         breathing ? (resolved ? @"已开启，展开模块时生效" : @"已开启，等待场景命中") : @"关闭",
                         adaptive ? (resolved ? @"正在生效" : @"已开启，等待场景命中") : @"关闭"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:resolved ? @"视觉策略状态" : @"当前场景未命中" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)configureRelayMedia {
    NSDictionary *relay = CCBGSceneDictionaryValue(self.scene[@"relay"]);
    NSDictionary *mediaBySlot = CCBGSceneDictionaryValue(relay[@"mediaBySlot"]);
    NSArray<NSString *> *displayNames = CCBGModuleDisplayNames();
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"接力素材覆盖" message:@"未设置时沿用来源模块素材。" preferredStyle:UIAlertControllerStyleActionSheet];
    for (id rawSlot in CCBGSceneArrayValue(relay[@"targetSlots"])) {
        if (![rawSlot isKindOfClass:NSNumber.class]) continue;
        NSInteger slotIndex = [rawSlot integerValue];
        if (slotIndex < 0 || (NSUInteger)slotIndex >= displayNames.count) continue;
        NSNumber *slot = @(slotIndex);
        NSString *title = displayNames[(NSUInteger)slotIndex];
        NSString *selected = CCBGSceneStringValue(mediaBySlot[slot.stringValue]);
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:title selected:selected completion:^(NSString *name) {
                [self updateScene:^(NSMutableDictionary *scene) {
                    NSMutableDictionary *copy = [CCBGSceneDictionaryValue(scene[@"relay"]) mutableCopy];
                    NSMutableDictionary *media = [CCBGSceneDictionaryValue(copy[@"mediaBySlot"]) mutableCopy];
                    media[slot.stringValue] = name ?: @"";
                    copy[@"mediaBySlot"] = media;
                    scene[@"relay"] = copy;
                } event:@"scene-relay-media"];
            }];
            [self.navigationController pushViewController:picker animated:YES];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end

static NSDictionary *CCBGSceneWithID(NSString *sceneID) {
    for (NSDictionary *scene in CCBGStoredScenes()) if ([CCBGSceneStringValue(scene[@"id"]) isEqualToString:sceneID]) return scene;
    return @{};
}

static void CCBGMutateScene(NSString *sceneID, void (^mutation)(NSMutableDictionary *scene), NSString *event) {
    NSMutableArray *scenes = [CCBGStoredScenes() mutableCopy];
    NSUInteger index = [scenes indexOfObjectPassingTest:^BOOL(NSDictionary *scene, NSUInteger idx, BOOL *stop) { return [CCBGSceneStringValue(scene[@"id"]) isEqualToString:sceneID]; }];
    if (index == NSNotFound) return; NSMutableDictionary *updated = [scenes[index] mutableCopy]; mutation(updated); scenes[index] = updated;
    CCBGWritePreference(@"sceneDirectorScenes", scenes); CCBGRecordSceneTimelineEvent(event, @{ @"sceneID": sceneID ?: @"" });
}

@interface CCBGSceneStateTrackEditorController ()
@property(nonatomic, copy) NSString *sceneID;
@property(nonatomic, copy) NSString *target;
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;
@end

@implementation CCBGSceneStateTrackEditorController
- (instancetype)initWithSceneID:(NSString *)sceneID target:(NSString *)target { self = [super initWithStyle:UITableViewStyleInsetGrouped]; if (self) { _sceneID = [sceneID copy]; _target = [target copy]; self.title = @"状态轨道"; } return self; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.mediaCatalog = CCBGLoadMediaCatalog(); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 4; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { NSArray *states = @[@"off", @"on", @"loading", @"unavailable"]; NSString *state = states[(NSUInteger)indexPath.row]; NSDictionary *tracks = CCBGSceneDictionaryValue(CCBGSceneWithID(self.sceneID)[@"stateTracks"]); NSDictionary *target = CCBGSceneDictionaryValue(tracks[self.target]); NSString *selected = CCBGSceneStringValue(target[state]); NSDictionary *item = CCBGMediaItemNamed(self.mediaCatalog, selected); UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"state"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"state"]; cell.textLabel.text = CCBGSceneStateTitle(state); cell.detailTextLabel.text = CCBGDisplayNameForItem(item) ?: @"未设置"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSArray *states = @[@"off", @"on", @"loading", @"unavailable"]; NSString *state = states[(NSUInteger)indexPath.row]; NSDictionary *tracks = CCBGSceneDictionaryValue(CCBGSceneWithID(self.sceneID)[@"stateTracks"]); NSDictionary *target = CCBGSceneDictionaryValue(tracks[self.target]); NSString *selected = CCBGSceneStringValue(target[state]); CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:CCBGSceneStateTitle(state) selected:selected completion:^(NSString *name) { CCBGMutateScene(self.sceneID, ^(NSMutableDictionary *scene) { NSMutableDictionary *updatedTracks = [CCBGSceneDictionaryValue(scene[@"stateTracks"]) mutableCopy]; NSMutableDictionary *updatedTarget = [CCBGSceneDictionaryValue(updatedTracks[self.target]) mutableCopy]; updatedTarget[state] = name ?: @""; updatedTracks[self.target] = updatedTarget; scene[@"stateTracks"] = updatedTracks; }, @"scene-state-track"); [self.tableView reloadData]; }]; [self.navigationController pushViewController:picker animated:YES]; }
@end
