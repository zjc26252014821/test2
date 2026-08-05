#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"

@interface CCBGSceneDirectorController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *scenes;
@property(nonatomic, copy) NSArray<NSDictionary *> *timeline;
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;
@end

static NSString *CCBGTimelineEventTitle(NSString *event) {
    return @{
        @"scene-created": @"创建场景", @"scene-reordered": @"调整场景顺序", @"scene-deleted": @"删除场景",
        @"scene-activation": @"切换启用方式", @"scene-target": @"修改场景素材", @"scene-condition": @"修改自动条件",
        @"scene-focus": @"修改专注模式",
        @"scene-state-track": @"修改状态轨道", @"scene-relay": @"修改模块接力", @"scene-relay-media": @"修改接力素材",
        @"scene-setting": @"修改视觉策略", @"automatic-scene-hit": @"自动命中场景", @"playback-start": @"素材开始播放",
        @"playback-failure": @"素材播放失败", @"favorite-changed": @"修改素材收藏",
        @"relay": @"触发跨模块接力", @"replay": @"恢复历史视觉状态", @"replay-ended": @"结束历史回放", @"manual-snapshot": @"手动记录视觉状态",
    }[event] ?: @"场景事件";
}

static NSString *CCBGTimelineDisplayTime(NSDictionary *entry) {
    NSString *stored = [entry[@"displayTime"] isKindOfClass:NSString.class] ? entry[@"displayTime"] : @"";
    if (stored.length) return stored;
    NSTimeInterval timestamp = [entry[@"timestampMilliseconds"] longLongValue] > 0
        ? [entry[@"timestampMilliseconds"] longLongValue] / 1000.0 : [entry[@"time"] doubleValue];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.timeZone = NSTimeZone.localTimeZone;
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"未知时间";
}

@implementation CCBGSceneDirectorController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"场景导演";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addScene)];
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSceneData];
}

- (void)reloadSceneData {
    id stored = CCBGReadPreference(@"sceneDirectorScenes", @[]);
    NSMutableArray<NSDictionary *> *scenes = [NSMutableArray array];
    BOOL removedLegacyFeatures = NO;
    if ([stored isKindOfClass:NSArray.class]) for (id scene in (NSArray *)stored) {
        if (![scene isKindOfClass:NSDictionary.class] || ![scene[@"id"] isKindOfClass:NSString.class] || ![scene[@"id"] length]) continue;
        NSMutableDictionary *cleanScene = [scene mutableCopy];
        if (cleanScene[@"moods"] || cleanScene[@"clips"]) {
            [cleanScene removeObjectsForKeys:@[@"moods", @"clips"]];
            removedLegacyFeatures = YES;
        }
        NSMutableDictionary *conditions = [cleanScene[@"conditions"] isKindOfClass:NSDictionary.class] ? [cleanScene[@"conditions"] mutableCopy] : [NSMutableDictionary dictionary];
        if (conditions[@"startMinutes"] || conditions[@"endMinutes"]) {
            [conditions removeObjectsForKeys:@[@"startMinutes", @"endMinutes"]];
            removedLegacyFeatures = YES;
        }
        NSString *focus = [conditions[@"focus"] isKindOfClass:NSString.class] ? conditions[@"focus"] : @"";
        if (focus.length && ![conditions[@"focusEnabled"] respondsToSelector:@selector(boolValue)]) {
            conditions[@"focusEnabled"] = @YES;
            removedLegacyFeatures = YES;
        }
        cleanScene[@"conditions"] = conditions;
        [scenes addObject:cleanScene];
    }
    if (removedLegacyFeatures) CCBGWritePreference(@"sceneDirectorScenes", scenes);
    self.scenes = [scenes sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftPriority = [left[@"priority"] respondsToSelector:@selector(integerValue)] ? [left[@"priority"] integerValue] : 0;
        NSInteger rightPriority = [right[@"priority"] respondsToSelector:@selector(integerValue)] ? [right[@"priority"] integerValue] : 0;
        return leftPriority == rightPriority ? NSOrderedSame : leftPriority > rightPriority ? NSOrderedAscending : NSOrderedDescending;
    }];
    self.timeline = CCBGSceneTimeline();
    self.mediaCatalog = CCBGLoadMediaCatalog();
    [self.tableView reloadData];
}

- (void)addScene {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新场景" message:@"场景可按锁屏、外观、充电、方向和专注模式自动命中。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"例如：夜间充电"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableArray *scenes = [self.scenes mutableCopy] ?: [NSMutableArray array];
        NSString *identifier = NSUUID.UUID.UUIDString;
        [scenes addObject:@{
            @"id": identifier, @"name": alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : @"新场景",
            @"enabled": @YES, @"priority": @(scenes.count + 1),
            @"conditions": @{ @"locked": @-1, @"dark": @-1, @"charging": @-1, @"landscape": @-1, @"focusEnabled": @NO, @"focus": @"" },
            @"targets": @{},
        }];
        CCBGWritePreference(@"sceneDirectorScenes", scenes);
        CCBGRecordSceneTimelineEvent(@"scene-created", @{ @"sceneID": identifier });
        [self reloadSceneData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.scenes.count : MIN((NSUInteger)30, self.timeline.count) + 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"已编排场景", @"控制中心回放"][(NSUInteger)section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    return self.timeline.count ? @"回放会恢复五模块和系统模块，并固定记录时命中的场景；可随时结束回放回到自动条件。" : @"暂无回放记录。先记录当前视觉状态，后续即可一键恢复。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"scene"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"scene"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 0) {
        NSDictionary *scene = self.scenes[(NSUInteger)indexPath.row];
        cell.textLabel.text = [scene[@"name"] isKindOfClass:NSString.class] ? scene[@"name"] : @"场景";
        cell.detailTextLabel.text = [scene[@"enabled"] boolValue] ? [NSString stringWithFormat:@"优先级 %@", scene[@"priority"]] : @"已停用";
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"记录当前视觉状态";
            cell.detailTextLabel.text = self.timeline.count ? @"保存一个新的回放节点" : @"没有可回放记录，点此创建第一个节点";
            cell.imageView.image = [UIImage systemImageNamed:@"record.circle"];
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        if (indexPath.row == 1) {
            BOOL replayActive = [CCBGReadPreference(@"sceneDirectorReplayActive", @NO) boolValue];
            cell.textLabel.text = @"结束当前回放";
            cell.detailTextLabel.text = replayActive ? @"解除固定场景，重新按照自动条件运行" : @"当前没有固定的回放状态";
            cell.imageView.image = [UIImage systemImageNamed:@"stop.circle"];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = replayActive ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            return cell;
        }
        NSDictionary *entry = self.timeline[(NSUInteger)indexPath.row - 2];
        cell.textLabel.text = CCBGTimelineEventTitle(entry[@"event"]);
        NSDictionary *details = [entry[@"details"] isKindOfClass:NSDictionary.class] ? entry[@"details"] : @{};
        NSString *mediaName = [details[@"media"] isKindOfClass:NSString.class] ? details[@"media"] : @"";
        NSDictionary *media = CCBGMediaItemNamed(self.mediaCatalog, mediaName);
        NSString *mediaDetail = media ? [NSString stringWithFormat:@" · %@", CCBGDisplayNameForItem(media)] : @"";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", CCBGTimelineDisplayTime(entry), mediaDetail];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 0 || destinationIndexPath.section != 0) return;
    NSMutableArray *stored = [self.scenes mutableCopy];
    NSDictionary *scene = stored[(NSUInteger)sourceIndexPath.row];
    [stored removeObjectAtIndex:(NSUInteger)sourceIndexPath.row];
    [stored insertObject:scene atIndex:(NSUInteger)destinationIndexPath.row];
    for (NSUInteger index = 0; index < stored.count; index++) {
        NSMutableDictionary *updated = [stored[index] mutableCopy];
        updated[@"priority"] = @(stored.count - index);
        stored[index] = updated;
    }
    CCBGWritePreference(@"sceneDirectorScenes", stored);
    CCBGRecordSceneTimelineEvent(@"scene-reordered", @{});
    self.scenes = stored;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath { return UITableViewCellEditingStyleDelete; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0) return;
    NSDictionary *scene = self.scenes[(NSUInteger)indexPath.row];
    NSMutableArray *stored = [self.scenes mutableCopy];
    [stored removeObjectAtIndex:(NSUInteger)indexPath.row];
    id manualSceneID = CCBGReadPreference(@"sceneDirectorManualSceneID", @"");
    if ([manualSceneID isKindOfClass:NSString.class] && [manualSceneID isEqualToString:scene[@"id"]]) CCBGWritePreference(@"sceneDirectorManualSceneID", @"");
    CCBGWritePreference(@"sceneDirectorScenes", stored);
    CCBGRecordSceneTimelineEvent(@"scene-deleted", @{ @"sceneID": scene[@"id"] ?: @"" });
    [self reloadSceneData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 0) {
        CCBGRecordSceneTimelineEvent(@"manual-snapshot", @{ @"source": @"scene-director" });
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadSceneData];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已记录" message:@"当前视觉状态已加入控制中心回放。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        if (![CCBGReadPreference(@"sceneDirectorReplayActive", @NO) boolValue]) return;
        CCBGExitSceneTimelineReplay();
        [self reloadSceneData];
        return;
    }
    if (indexPath.section == 1) {
        CCBGReplaySceneTimelineEntry(self.timeline[(NSUInteger)indexPath.row - 2]);
        [self reloadSceneData];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已恢复" message:@"五模块和系统模块已切换到记录状态；可在“结束当前回放”恢复自动条件。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section != 0) return;
    NSDictionary *scene = self.scenes[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[[CCBGSceneEditorController alloc] initWithScene:scene] animated:YES];
}

@end
