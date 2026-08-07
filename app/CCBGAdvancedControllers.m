#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static NSString *const CCBGBackupDirectory = @"/var/mobile/Library/CleanCCBG2x2/Backups";

static NSArray<NSDictionary *> *CCBGDictionaryArrayValue(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)value) if ([entry isKindOfClass:NSDictionary.class]) [result addObject:entry];
    return result;
}

static NSArray<NSString *> *CCBGStringArrayValue(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)value) if ([entry isKindOfClass:NSString.class] && [entry length]) [result addObject:entry];
    return result;
}

static NSInteger CCBGIntegerValue(id value, NSInteger fallback) {
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

static dispatch_queue_t CCBGBackupWorkQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.backup", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static BOOL CCBGWriteStreamData(NSOutputStream *stream, NSData *data, NSError **error) {
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        NSInteger written = [stream write:bytes + offset maxLength:data.length - offset];
        if (written <= 0) {
            if (error) *error = stream.streamError ?: [NSError errorWithDomain:@"CleanCCBGBackup" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法写入备份文件"}];
            return NO;
        }
        offset += (NSUInteger)written;
    }
    return YES;
}

static NSData *CCBGJSONFragment(id object, NSError **error) {
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingFragmentsAllowed error:error];
}

static BOOL CCBGWriteCompleteBackup(NSString *path, NSDictionary *preferences, NSError **error) {
    NSDictionary *metadata = @{
        @"format": @3,
        @"createdAt": @((long long)NSDate.date.timeIntervalSince1970),
        @"preferences": preferences ?: @{},
    };
    NSMutableData *prefix = [[NSJSONSerialization dataWithJSONObject:metadata options:0 error:error] mutableCopy];
    if (!prefix.length || ((const uint8_t *)prefix.bytes)[prefix.length - 1] != '}') return NO;
    [prefix setLength:prefix.length - 1];
    [prefix appendData:[@",\"media\":{" dataUsingEncoding:NSUTF8StringEncoding]];

    NSOutputStream *stream = [NSOutputStream outputStreamToFileAtPath:path append:NO];
    [stream open];
    BOOL success = CCBGWriteStreamData(stream, prefix, error);
    BOOL first = YES;
    for (NSString *name in CCBGScanMediaNames()) {
        if (!success) break;
        @autoreleasepool {
            NSData *mediaData = [NSData dataWithContentsOfFile:[CCBGMediaDirectoryPath stringByAppendingPathComponent:name]];
            if (!mediaData.length) continue;
            NSData *keyData = CCBGJSONFragment(name, error);
            NSData *valueData = CCBGJSONFragment([mediaData base64EncodedStringWithOptions:0], error);
            if (!keyData || !valueData) { success = NO; continue; }
            if (!first) success = CCBGWriteStreamData(stream, [@"," dataUsingEncoding:NSUTF8StringEncoding], error);
            if (success) success = CCBGWriteStreamData(stream, keyData, error);
            if (success) success = CCBGWriteStreamData(stream, [@":" dataUsingEncoding:NSUTF8StringEncoding], error);
            if (success) success = CCBGWriteStreamData(stream, valueData, error);
            first = NO;
        }
    }
    if (success) success = CCBGWriteStreamData(stream, [@"}}" dataUsingEncoding:NSUTF8StringEncoding], error);
    [stream close];
    if (!success) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return success;
}

static NSString *CCBGCreateAutomaticBackup(NSString *reason) {
    [[NSFileManager defaultManager] createDirectoryAtPath:CCBGBackupDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *object = @{
        @"format": @3,
        @"createdAt": @((long long)NSDate.date.timeIntervalSince1970),
        @"reason": reason ?: @"自动备份",
        @"preferences": CCBGConfigurationPreferencesSnapshot(),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = [CCBGBackupDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"backup-%.0f.json", NSDate.date.timeIntervalSince1970]];
    [data writeToFile:path atomically:YES];
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:CCBGBackupDirectory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    while (files.count > 10) {
        [[NSFileManager defaultManager] removeItemAtPath:[CCBGBackupDirectory stringByAppendingPathComponent:files.firstObject] error:nil];
        files = [files subarrayWithRange:NSMakeRange(1, files.count - 1)];
    }
    return path;
}

static BOOL CCBGApplyPreferencesDictionary(NSDictionary *preferences, NSError **error) {
    if (![preferences isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.backup" code:1 userInfo:@{NSLocalizedDescriptionKey: @"备份中没有有效配置。"}];
        return NO;
    }
    return CCBGRestorePreferencesSnapshot(preferences, error);
}

static NSDictionary *CCBGProfilePreferencesSnapshot(void) {
    NSMutableDictionary *preferences = [CCBGConfigurationPreferencesSnapshot() mutableCopy] ?: [NSMutableDictionary dictionary];
    [preferences removeObjectForKey:@"configurationProfiles"];
    [preferences removeObjectForKey:@"quickConfigurationUndoStack"];
    return preferences;
}

static BOOL CCBGApplyProfilePreferences(id value, NSError **error) {
    if (![value isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.backup" code:2 userInfo:@{NSLocalizedDescriptionKey: @"配置模板格式无效。"}];
        return NO;
    }
    NSMutableDictionary *preferences = [value mutableCopy];
    id profiles = CCBGReadPreference(@"configurationProfiles", @[]);
    if (profiles) preferences[@"configurationProfiles"] = profiles;
    return CCBGRestorePreferencesSnapshot(preferences, error);
}

static dispatch_queue_t CCBGInsightsAnalysisQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.insights", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static void CCBGCollectMediaReferences(id value, NSSet<NSString *> *knownNames, NSMutableSet<NSString *> *references) {
    if ([value isKindOfClass:NSString.class]) {
        if ([knownNames containsObject:value]) [references addObject:value];
    } else if ([value isKindOfClass:NSArray.class]) {
        for (id item in value) CCBGCollectMediaReferences(item, knownNames, references);
    } else if ([value isKindOfClass:NSDictionary.class]) {
        for (id item in [value allValues]) CCBGCollectMediaReferences(item, knownNames, references);
    }
}

@interface CCBGGroupedLibraryController ()
@property(nonatomic,copy)NSArray<NSString *> *groups;
@property(nonatomic,copy)NSDictionary<NSString *,NSArray<NSDictionary *> *> *itemsByGroup;
@property(nonatomic,strong)NSMutableSet<NSString *> *collapsed;
@property(nonatomic,copy)NSString *catalogSignature;
@end

@implementation CCBGGroupedLibraryController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"分组与标签";NSArray *stored=CCBGReadPreference(@"collapsedMediaGroups",@[]);self.collapsed=[NSMutableSet setWithArray:[stored isKindOfClass:NSArray.class]?stored:@[]];}
- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    NSArray<NSDictionary *> *catalog = CCBGLoadMediaCatalog();
    NSMutableString *signature = [NSMutableString stringWithCapacity:catalog.count * 48];
    for (NSDictionary *item in catalog) {
        [signature appendFormat:@"%@|%@|%@|%@;", item[@"fileName"] ?: @"", item[@"group"] ?: @"",
            [item[@"favorite"] boolValue] ? @"1" : @"0", [item[@"tags"] componentsJoinedByString:@","] ?: @""];
    }
    if (self.groups.count && [signature isEqualToString:self.catalogSignature]) return;
    self.catalogSignature = signature;
    NSMutableDictionary *map=[NSMutableDictionary dictionary];
    for(NSDictionary *item in catalog){NSString *group=[item[@"group"] length]?item[@"group"]:@"未分组";[map[group]?: (map[group]=[NSMutableArray array]) addObject:item];if([item[@"favorite"] boolValue])[map[@"收藏"]?: (map[@"收藏"]=[NSMutableArray array]) addObject:item];for(NSString *tag in item[@"tags"]?:@[]){NSString *key=[@"#" stringByAppendingString:tag];[map[key]?: (map[key]=[NSMutableArray array]) addObject:item];}}
    self.groups=[map.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.itemsByGroup=map;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return self.groups.count;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{NSString *group=self.groups[section];return [self.collapsed containsObject:group]?0:self.itemsByGroup[group].count;}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section{NSString *group=self.groups[section];UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.tag=section;button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];[button setTitle:[NSString stringWithFormat:@"  %@ · %lu",group,(unsigned long)self.itemsByGroup[group].count] forState:UIControlStateNormal];[button setImage:[UIImage systemImageNamed:[self.collapsed containsObject:group]?@"chevron.right":@"chevron.down"] forState:UIControlStateNormal];[button addTarget:self action:@selector(toggleGroup:) forControlEvents:UIControlEventTouchUpInside];return button;}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section{return 44;}
- (void)toggleGroup:(UIButton *)sender{NSString *group=self.groups[sender.tag];if([self.collapsed containsObject:group])[self.collapsed removeObject:group];else[self.collapsed addObject:group];CCBGWritePreference(@"collapsedMediaGroups",self.collapsed.allObjects);[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:sender.tag] withRowAnimation:UITableViewRowAnimationAutomatic];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{NSDictionary *item=self.itemsByGroup[self.groups[indexPath.section]][indexPath.row];UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"groupItem"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"groupItem"];cell.textLabel.text=CCBGDisplayNameForItem(item);cell.detailTextLabel.text=[item[@"tags"]componentsJoinedByString:@" · "];CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"group-");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{[tableView deselectRowAtIndexPath:indexPath animated:YES];NSDictionary *item=self.itemsByGroup[self.groups[indexPath.section]][indexPath.row];[self.navigationController pushViewController:[[CCBGMediaDetailController alloc]initWithMediaItem:item] animated:YES];}
@end

@interface CCBGLibraryInsightsController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) NSArray<NSArray<NSDictionary *> *> *duplicateGroups;
@property(nonatomic, copy) NSArray<NSDictionary *> *sizeRankedItemsCache;
@property(nonatomic, copy) NSDictionary<NSString *, NSNumber *> *fileSizesByName;
@property(nonatomic) NSUInteger playedCount;
@property(nonatomic) NSUInteger failedCount;
@property(nonatomic, strong) NSProgress *metadataProgress;
@property(nonatomic, strong) NSProgress *foregroundProgress;
@end

@implementation CCBGLibraryInsightsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"素材洞察"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadInsights]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.metadataProgress cancel]; }
- (void)dealloc { [self.metadataProgress cancel]; [self.foregroundProgress cancel]; }
- (void)reloadInsights {
    [self.metadataProgress cancel];
    self.items = CCBGLoadMediaCatalog();
    self.playedCount = 0;
    self.failedCount = 0;
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *item in self.items) {
        if ([item[@"playCount"] unsignedLongLongValue] > 0) self.playedCount++;
        if ([item[@"failureReason"] length] > 0) self.failedCount++;
        NSString *hash = item[@"fileHash"];
        if (hash.length) [groups[hash] ?: (groups[hash] = [NSMutableArray array]) addObject:item];
    }
    NSMutableArray *duplicates = [NSMutableArray array];
    for (NSArray *group in groups.allValues) if (group.count > 1) [duplicates addObject:group];
    self.duplicateGroups = duplicates;
    self.sizeRankedItemsCache = nil;
    self.fileSizesByName = @{};
    [self.tableView reloadData];
    [self refreshFileMetadata];
}
- (void)refreshFileMetadata {
    NSArray<NSDictionary *> *items = self.items ?: @[];
    if (!items.count) { self.sizeRankedItemsCache = @[]; return; }
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:(int64_t)items.count];
    self.metadataProgress = progress;
    dispatch_async(CCBGInsightsAnalysisQueue(), ^{
        NSFileManager *manager = [NSFileManager new];
        NSMutableDictionary<NSString *, NSNumber *> *sizes = [NSMutableDictionary dictionaryWithCapacity:items.count];
        NSMutableArray<NSDictionary *> *ranked = [NSMutableArray arrayWithCapacity:items.count];
        for (NSDictionary *item in items) {
            if (progress.cancelled) return;
            @autoreleasepool {
                NSString *name = item[@"fileName"] ?: @"";
                NSDictionary *attributes = [manager attributesOfItemAtPath:CCBGPathForItem(item) error:nil];
                NSNumber *size = attributes[NSFileSize] ?: @0;
                if (name.length) sizes[name] = size;
                [ranked addObject:@{@"item": item, @"size": size}];
            }
            progress.completedUnitCount++;
        }
        [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"size"] compare:left[@"size"]];
        }];
        NSArray *sortedItems = [ranked valueForKey:@"item"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progress.cancelled || self.metadataProgress != progress) return;
            self.metadataProgress = nil;
            self.fileSizesByName = sizes;
            self.sizeRankedItemsCache = sortedItems;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
        });
    });
}
- (UIAlertController *)showProgressWithTitle:(NSString *)title message:(NSString *)message progress:(NSProgress *)progress {
    [self.foregroundProgress cancel];
    self.foregroundProgress = progress;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [progress cancel];
        if (self.foregroundProgress == progress) self.foregroundProgress = nil;
    }]];
    [self presentViewController:alert animated:YES completion:nil];
    return alert;
}
- (void)updateProgressAlert:(UIAlertController *)alert progress:(NSProgress *)progress completed:(NSUInteger)completed total:(NSUInteger)total {
    if (progress.cancelled || self.foregroundProgress != progress) return;
    NSUInteger stride = MAX((NSUInteger)1, total / 20);
    if (completed % stride != 0 && completed != total) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!progress.cancelled && self.foregroundProgress == progress) alert.message = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)completed, (unsigned long)total];
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5;
    if (section == 1) return self.items.count ? (self.sizeRankedItemsCache ? MIN((NSUInteger)10, self.sizeRankedItemsCache.count) : 1) : 0;
    return 7;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"使用统计", @"空间占用排行", @"整理工具"][section]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"insight"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"insight"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.imageView.tintColor = CCBGAppAccentColor();
    if (indexPath.section == 0) {
        NSArray *titles = @[@"素材总数", @"已播放", @"从未使用", @"故障隔离", @"重复组"];
        NSArray *values = @[@(self.items.count), @(self.playedCount), @(self.items.count - self.playedCount), @(self.failedCount), @(self.duplicateGroups.count)];
        cell.textLabel.text = titles[indexPath.row]; cell.detailTextLabel.text = [values[indexPath.row] stringValue];
        cell.imageView.image = [UIImage systemImageNamed:@[@"photo.stack", @"play.circle", @"clock", @"exclamationmark.triangle", @"square.on.square"][indexPath.row]];
        return cell;
    }
    if (indexPath.section == 1) {
        if (!self.sizeRankedItemsCache) {
            cell.textLabel.text = @"正在分析空间占用…";
            cell.detailTextLabel.text = nil;
            cell.imageView.image = [UIImage systemImageNamed:@"clock"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        NSDictionary *item = self.sizeRankedItemsCache[indexPath.row];
        cell.textLabel.text = CCBGDisplayNameForItem(item);
        cell.detailTextLabel.text = CCBGReadableBytes([self.fileSizesByName[item[@"fileName"]] unsignedLongLongValue]);
        CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"insight-size-");
        return cell;
    }
    NSArray *titles = @[@"按分组与标签浏览", @"扫描文件哈希", @"合并重复素材", @"批量编辑", @"存储清理建议", @"清除故障隔离", @"提取素材主色"];
    NSArray *icons = @[@"folder", @"number", @"arrow.triangle.merge", @"checklist", @"trash.slash", @"wrench.and.screwdriver", @"paintpalette"];
    cell.textLabel.text = titles[indexPath.row]; cell.detailTextLabel.text = nil;
    cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;
    if (indexPath.row == 0) [self.navigationController pushViewController:[CCBGGroupedLibraryController new] animated:YES];
    else if (indexPath.row == 1) [self scanHashes];
    else if (indexPath.row == 2) [self mergeDuplicates];
    else if (indexPath.row == 3) [self.navigationController pushViewController:[CCBGBatchEditController new] animated:YES];
    else if (indexPath.row == 4) [self showCleanupSuggestions];
    else if (indexPath.row == 5) [self clearFailures];
    else [self extractColors];
}
- (void)scanHashes {
    NSArray<NSDictionary *> *items = self.items ?: @[];
    if (!items.count) return;
    NSProgress *task = [NSProgress progressWithTotalUnitCount:(int64_t)items.count];
    UIAlertController *alert = [self showProgressWithTitle:@"扫描文件哈希" message:@"准备扫描…" progress:task];
    dispatch_async(CCBGInsightsAnalysisQueue(), ^{
        NSMutableArray *updated = [NSMutableArray arrayWithCapacity:items.count];
        NSFileManager *manager = [NSFileManager new];
        for (NSUInteger index = 0; index < items.count; index++) {
            if (task.cancelled) return;
            @autoreleasepool {
                NSDictionary *item = items[index];
                NSMutableDictionary *copy = [item mutableCopy];
                NSDictionary *attributes = [manager attributesOfItemAtPath:CCBGPathForItem(item) error:nil];
                unsigned long long fileSize = [attributes[NSFileSize] unsignedLongLongValue];
                NSTimeInterval modifiedAt = [attributes[NSFileModificationDate] timeIntervalSince1970];
                BOOL cacheValid = [copy[@"fileHash"] length] && [copy[@"fileSize"] unsignedLongLongValue] == fileSize && fabs([copy[@"fileModifiedAt"] doubleValue] - modifiedAt) < 0.001;
                if (!cacheValid) copy[@"fileHash"] = CCBGSHA256ForFileAtPath(CCBGPathForItem(item));
                copy[@"fileSize"] = @(fileSize);
                copy[@"fileModifiedAt"] = @(modifiedAt);
                [updated addObject:copy];
            }
            task.completedUnitCount = (int64_t)index + 1;
            [self updateProgressAlert:alert progress:task completed:index + 1 total:items.count];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.cancelled || self.foregroundProgress != task) return;
            self.foregroundProgress = nil;
            CCBGSaveMediaCatalog(updated);
            [alert dismissViewControllerAnimated:YES completion:^{ [self reloadInsights]; }];
        });
    });
}
- (void)mergeDuplicates {
    if (!self.duplicateGroups.count) { [self scanHashes]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"合并重复素材？" message:@"每组保留第一项，并把所有模块、规则和播放列表引用迁移到保留项。" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"合并" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        CCBGCreateAutomaticBackup(@"合并重复素材前");
        NSMutableArray *catalog = [CCBGLoadMediaCatalog() mutableCopy];
        for (NSArray<NSDictionary *> *group in self.duplicateGroups) {
            NSDictionary *keeper = group.firstObject;
            NSMutableDictionary *merged = [keeper mutableCopy];
            NSMutableSet *tags = [NSMutableSet setWithArray:keeper[@"tags"] ?: @[]];
            for (NSDictionary *duplicate in [group subarrayWithRange:NSMakeRange(1, group.count - 1)]) {
                [tags addObjectsFromArray:duplicate[@"tags"] ?: @[]];
                merged[@"favorite"] = @([merged[@"favorite"] boolValue] || [duplicate[@"favorite"] boolValue]);
                merged[@"playCount"] = @([merged[@"playCount"] unsignedLongLongValue] + [duplicate[@"playCount"] unsignedLongLongValue]);
                CCBGReplaceMediaReferences(duplicate[@"fileName"], keeper[@"fileName"]);
                [[NSFileManager defaultManager] removeItemAtPath:CCBGPathForItem(duplicate) error:nil];
                [catalog removeObject:duplicate];
            }
            merged[@"tags"] = tags.allObjects;
            NSUInteger keeperIndex = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"fileName"] isEqualToString:keeper[@"fileName"]]; }];
            if (keeperIndex != NSNotFound) catalog[keeperIndex] = merged;
        }
        CCBGSaveMediaCatalog(catalog); [self reloadInsights];
    }]];
    alert.popoverPresentationController.sourceView = self.view; alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showCleanupSuggestions {
    NSArray<NSDictionary *> *items = self.items ?: @[];
    NSDictionary<NSString *, NSNumber *> *cachedSizes = self.fileSizesByName ?: @{};
    NSProgress *task = [NSProgress progressWithTotalUnitCount:(int64_t)items.count + 1];
    UIAlertController *progressAlert = [self showProgressWithTitle:@"分析清理建议" message:@"正在检查引用…" progress:task];
    dispatch_async(CCBGInsightsAnalysisQueue(), ^{
        NSDictionary *preferences = CCBGReadAllPreferences();
        NSSet<NSString *> *knownNames = [NSSet setWithArray:[items valueForKey:@"fileName"]];
        NSMutableSet<NSString *> *references = [NSMutableSet set];
        [preferences enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (![key isEqualToString:@"mediaCatalog"]) CCBGCollectMediaReferences(value, knownNames, references);
        }];
        task.completedUnitCount = 1;
        NSUInteger unused = 0, failed = 0, oversized = 0, unreferenced = 0;
        NSFileManager *manager = [NSFileManager new];
        for (NSUInteger index = 0; index < items.count; index++) {
            if (task.cancelled) return;
            NSDictionary *item = items[index];
            if ([item[@"playCount"] unsignedLongLongValue] == 0) unused++;
            if ([item[@"failureReason"] length]) failed++;
            NSNumber *size = cachedSizes[item[@"fileName"]];
            if (!size) size = [manager attributesOfItemAtPath:CCBGPathForItem(item) error:nil][NSFileSize] ?: @0;
            if (size.unsignedLongLongValue > 100ull * 1024ull * 1024ull) oversized++;
            if (![references containsObject:item[@"fileName"]]) unreferenced++;
            task.completedUnitCount = (int64_t)index + 2;
            [self updateProgressAlert:progressAlert progress:task completed:index + 1 total:items.count];
        }
        NSString *message = [NSString stringWithFormat:@"从未使用：%lu\n无模块引用：%lu\n故障隔离：%lu\n超过 100 MB：%lu\n重复组：%lu", (unsigned long)unused, (unsigned long)unreferenced, (unsigned long)failed, (unsigned long)oversized, (unsigned long)self.duplicateGroups.count];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.cancelled || self.foregroundProgress != task) return;
            self.foregroundProgress = nil;
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理建议" message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        });
    });
}
- (void)clearFailures { for(NSDictionary *item in self.items) CCBGClearMediaFailure(item[@"fileName"]); CCBGPostReload(); [self reloadInsights]; }
- (void)extractColors {
    NSArray<NSDictionary *> *items = self.items ?: @[];
    if (!items.count) return;
    NSProgress *task = [NSProgress progressWithTotalUnitCount:(int64_t)items.count];
    UIAlertController *alert = [self showProgressWithTitle:@"提取素材主色" message:@"准备提取…" progress:task];
    dispatch_async(CCBGInsightsAnalysisQueue(), ^{
        NSMutableArray *updated = [NSMutableArray arrayWithCapacity:items.count];
        for (NSUInteger index = 0; index < items.count; index++) {
            if (task.cancelled) return;
            @autoreleasepool {
                NSDictionary *item = items[index];
                NSMutableDictionary *copy = [item mutableCopy];
                if (![copy[@"dominantColor"] length]) copy[@"dominantColor"] = CCBGDominantColorHexForMediaAtPath(CCBGPathForItem(item));
                [updated addObject:copy];
            }
            task.completedUnitCount = (int64_t)index + 1;
            [self updateProgressAlert:alert progress:task completed:index + 1 total:items.count];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.cancelled || self.foregroundProgress != task) return;
            self.foregroundProgress = nil;
            CCBGSaveMediaCatalog(updated);
            [alert dismissViewControllerAnimated:YES completion:^{ [self reloadInsights]; }];
        });
    });
}
@end

@interface CCBGBatchEditController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, strong) NSMutableSet<NSString *> *selectedNames;
@end

@implementation CCBGBatchEditController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"批量编辑"; self.selectedNames = [NSMutableSet set]; self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"应用" style:UIBarButtonItemStyleDone target:self action:@selector(showActions)]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.items = CCBGLoadMediaCatalog(); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { NSDictionary *item=self.items[indexPath.row]; UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"batch"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"batch"]; cell.textLabel.text=CCBGDisplayNameForItem(item); cell.detailTextLabel.text=item[@"group"] ?: @""; CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"batch-"); cell.accessoryType=[self.selectedNames containsObject:item[@"fileName"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSString *name=self.items[indexPath.row][@"fileName"]; if([self.selectedNames containsObject:name])[self.selectedNames removeObject:name];else[self.selectedNames addObject:name]; [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)showActions {
    if (!self.selectedNames.count) return;
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"已选 %lu 项",(unsigned long)self.selectedNames.count] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles=@[@"设为收藏",@"取消收藏",@"启用",@"停用",@"设置分组",@"透明度 50%",@"清除模糊",@"填充显示"];
    for(NSUInteger i=0;i<titles.count;i++){[menu addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self applyAction:i];}]];}
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; menu.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem; [self presentViewController:menu animated:YES completion:nil];
}
- (void)applyAction:(NSUInteger)action {
    if (action==4) { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"素材分组" message:nil preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"例如：节日、工作、夜间";}]; [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self applyGroup:alert.textFields.firstObject.text];}]]; [self presentViewController:alert animated:YES completion:nil]; return; }
    CCBGCreateAutomaticBackup(@"批量编辑前");
    NSMutableArray *catalog=[CCBGLoadMediaCatalog() mutableCopy]; NSInteger slot=CCBGActiveModuleSlot();
    for(NSUInteger i=0;i<catalog.count;i++){NSMutableDictionary *item=[catalog[i] mutableCopy];if(![self.selectedNames containsObject:item[@"fileName"]])continue;if(action<=3)item[action<2?@"favorite":@"enabled"]=@(action==0||action==2);else{NSMutableDictionary *effective=[CCBGMediaItemForModule(item,slot) mutableCopy];if(action==5)effective[@"opacity"]=@0.5;else if(action==6)effective[@"blurIntensity"]=@0;else effective[@"contentMode"]=@1;CCBGSaveModuleMediaConfiguration(effective,slot);}catalog[i]=item;}
    CCBGSaveMediaCatalog(catalog); self.items=catalog; [self.tableView reloadData];
}
- (void)applyGroup:(NSString *)group { CCBGCreateAutomaticBackup(@"批量分组前"); NSMutableArray *catalog=[CCBGLoadMediaCatalog() mutableCopy];for(NSUInteger i=0;i<catalog.count;i++){NSMutableDictionary *item=[catalog[i] mutableCopy];if([self.selectedNames containsObject:item[@"fileName"]])item[@"group"]=group?:@"";catalog[i]=item;}CCBGSaveMediaCatalog(catalog);self.items=catalog;[self.tableView reloadData]; }
@end

@interface CCBGPlaylistController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, strong) NSMutableArray<NSString *> *playlist;
@end

@implementation CCBGPlaylistController
- (void)viewDidLoad { [super viewDidLoad]; self.title=[NSString stringWithFormat:@"%@ 播放列表",CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]]; self.navigationItem.rightBarButtonItem=self.editButtonItem; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.items=CCBGLoadMediaCatalog(); NSArray *stored=CCBGReadModulePreference(@"playlist",CCBGActiveModuleSlot(),@[]); self.playlist=[stored isKindOfClass:NSArray.class]?[stored mutableCopy]:[NSMutableArray array]; [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?5:section==1?self.playlist.count:self.items.count;}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{if(indexPath.section!=0)return UITableViewAutomaticDimension;NSInteger mode=[CCBGReadModulePreference(@"playbackMode",CCBGActiveModuleSlot(),@0)integerValue];if((indexPath.row==0&&mode==2)||(indexPath.row==1&&mode!=2))return 0.01;return UITableViewAutomaticDimension;}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{CGFloat height=[self tableView:tableView heightForRowAtIndexPath:indexPath];cell.hidden=height>=0&&height<1.0;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"智能播放",@"当前队列",@"共享素材库"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    if(indexPath.section==0){if(indexPath.row==0||indexPath.row==2||indexPath.row==3){NSString *key=indexPath.row==0?@"playlistLoop":indexPath.row==2?@"preloadEnabled":@"performanceMode";NSString *title=indexPath.row==0?@"循环整个列表":indexPath.row==2?@"预加载下一项":@"性能模式";CCBGSwitchCell *cell=[tableView dequeueReusableCellWithIdentifier:@"pSwitch"]?:[[CCBGSwitchCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"pSwitch"];[cell configureWithTitle:title key:key value:[CCBGReadModulePreference(key,CCBGActiveModuleSlot(),indexPath.row==0||indexPath.row==2?@YES:@NO)boolValue] target:self action:@selector(switchChanged:)];return cell;}if(indexPath.row==1){CCBGSliderCell *cell=[tableView dequeueReusableCellWithIdentifier:@"pSlider"]?:[[CCBGSliderCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"pSlider"];[cell configureWithTitle:@"随机防重复" key:@"noRepeatCount" value:[CCBGReadModulePreference(@"noRepeatCount",CCBGActiveModuleSlot(),@3)floatValue] minimum:0 maximum:20 format:@"%.0f 项" target:self action:@selector(sliderChanged:)];return cell;}CCBGSegmentCell *cell=[tableView dequeueReusableCellWithIdentifier:@"transition"]?:[[CCBGSegmentCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"transition"];[cell configureWithTitle:@"切换动画" key:@"transitionStyle" items:@[@"淡化", @"柔和淡化", @"轻微缩放", @"快速淡化"] selected:[CCBGReadModulePreference(@"transitionStyle",CCBGActiveModuleSlot(),@0)integerValue] target:self action:@selector(segmentChanged:)];return cell;}
    NSString *name=indexPath.section==1?self.playlist[indexPath.row]:self.items[indexPath.row][@"fileName"];NSDictionary *item=CCBGMediaItemNamed(self.items,name);UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"playlist"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"playlist"];cell.textLabel.text=item?CCBGDisplayNameForItem(item):name;cell.detailTextLabel.text=item[@"group"]?:@"";CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"playlist-");cell.accessoryType=indexPath.section==2&&[self.playlist containsObject:name]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return cell;
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==1;}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination{NSString *name=self.playlist[source.row];[self.playlist removeObjectAtIndex:source.row];[self.playlist insertObject:name atIndex:destination.row];[self savePlaylist];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{[tableView deselectRowAtIndexPath:indexPath animated:YES];if(indexPath.section==1){[self.playlist removeObjectAtIndex:indexPath.row];[self savePlaylist];[tableView reloadData];}else if(indexPath.section==2){NSString *name=self.items[indexPath.row][@"fileName"];if([self.playlist containsObject:name])[self.playlist removeObject:name];else[self.playlist addObject:name];[self savePlaylist];[tableView reloadData];}}
- (void)savePlaylist{CCBGWriteModulePreference(@"playlist",CCBGActiveModuleSlot(),self.playlist);}
- (void)switchChanged:(UISwitch *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.on));}
- (void)sliderChanged:(UISlider *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(lround(sender.value)));UIView *v=sender;while(v&&![v isKindOfClass:CCBGSliderCell.class])v=v.superview;[(CCBGSliderCell *)v refreshValueLabel];}
- (void)segmentChanged:(UISegmentedControl *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.selectedSegmentIndex));}
@end

@implementation CCBGAutomationPriorityController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"自动化优先级";}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?6:4;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"判定顺序":@"含义说明";}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"priority"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"priority"];cell.selectionStyle=UITableViewCellSelectionStyleNone;if(indexPath.section==0){NSArray *titles=@[@"1. 隐私模式",@"2. 组合规则",@"3. 横竖屏素材",@"4. 基础自动化",@"5. 常显素材",@"6. 顺序或随机队列"];NSArray *details=@[@"锁屏时可切换指定素材、模糊当前内容或暂停视频。",@"命中的组合规则按优先级排序，最高的一条生效。",@"横屏和竖屏素材只在对应方向临时覆盖播放。",@"时间、深浅色、星期、低电量和充电状态在这里判定。",@"没有自动化覆盖时，常显模式使用固定素材。",@"播放列表和定时素材组只影响轮播队列，不会强行覆盖自动化。"];cell.textLabel.text=titles[(NSUInteger)indexPath.row];cell.detailTextLabel.text=details[(NSUInteger)indexPath.row];}else{NSArray *titles=@[@"临时选择",@"设为常显",@"定时播放列表",@"缺失素材"];NSArray *details=@[@"控制中心里的临时选择可能会被当前命中的自动化替换。",@"会切换到常显模式，并保存为当前模块的固定素材。",@"定时播放列表只筛选轮播队列，不改变自动化优先级。",@"诊断页可以统计并清理失效引用。"];cell.textLabel.text=titles[(NSUInteger)indexPath.row];cell.detailTextLabel.text=details[(NSUInteger)indexPath.row];}cell.detailTextLabel.numberOfLines=0;return cell;}
@end

static NSString *CCBGDashboardModeSummary(NSUInteger slot, NSArray<NSDictionary *> *catalog) {
    BOOL locked = !UIApplication.sharedApplication.protectedDataAvailable;
    if (locked && [CCBGReadModulePreference(@"privacyEnabled", slot, @NO) boolValue] && [CCBGReadModulePreference(@"privacyMedia", slot, @"") length]) return @"隐私覆盖";
    NSArray *rules = CCBGDictionaryArrayValue(CCBGReadModulePreference(@"compoundRules", slot, @[]));
    if (rules.count) {
        NSDateComponents *c = [NSCalendar.currentCalendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:NSDate.date];
        NSInteger minute = c.hour * 60 + c.minute;
        BOOL dark = CCBGSystemUsesDarkAppearance();
        BOOL charging = UIDevice.currentDevice.batteryState == UIDeviceBatteryStateCharging || UIDevice.currentDevice.batteryState == UIDeviceBatteryStateFull;
        BOOL low = NSProcessInfo.processInfo.lowPowerModeEnabled;
        NSArray *sorted = [rules sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSInteger left=CCBGIntegerValue(a[@"priority"],0),right=CCBGIntegerValue(b[@"priority"],0);return left==right?NSOrderedSame:left>right?NSOrderedAscending:NSOrderedDescending; }];
        for (NSDictionary *rule in sorted) {
            if (!CCBGIntegerValue(rule[@"enabled"],0)) continue;
            NSInteger d = CCBGIntegerValue(rule[@"dark"],-1), ch = CCBGIntegerValue(rule[@"charging"],-1), lp = CCBGIntegerValue(rule[@"lowPower"],-1);
            if (d >= 0 && (BOOL)d != dark) continue;
            if (ch >= 0 && (BOOL)ch != charging) continue;
            if (lp >= 0 && (BOOL)lp != low) continue;
            NSArray *days = rule[@"weekdays"];
            if ([days isKindOfClass:NSArray.class] && days.count && ![days containsObject:@(c.weekday)]) continue;
            NSInteger start = CCBGIntegerValue(rule[@"startMinutes"],0), end = CCBGIntegerValue(rule[@"endMinutes"],0);
            if (end > 0) {
                BOOL active = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end);
                if (!active) continue;
            }
            NSString *media = [rule[@"media"] isKindOfClass:NSString.class] ? rule[@"media"] : @"";
            if (media.length && CCBGMediaItemNamed(catalog, media)) return [NSString stringWithFormat:@"组合规则：%@", [rule[@"name"] isKindOfClass:NSString.class] ? rule[@"name"] : @"命中"];
        }
    }
    NSInteger mode = [CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue];
    NSArray *modes = @[@"常显", @"顺序", @"随机"];
    NSArray *schedules = CCBGDictionaryArrayValue(CCBGReadModulePreference(@"scheduledPlaylists", slot, @[]));
    NSString *schedule = schedules.count ? @" · 定时列表可用" : @"";
    return [NSString stringWithFormat:@"%@%@", modes[(NSUInteger)MIN(2, MAX(0, mode))], schedule];
}

@interface CCBGStatusDashboardController ()
@property(nonatomic,strong)NSTimer *refreshTimer;
@property(nonatomic,copy)NSArray<NSDictionary *> *catalogSnapshot;
@property(nonatomic,copy)NSArray<NSDictionary *> *historySnapshot;
@property(nonatomic,copy)NSString *renderedStatusSignature;
@end
@implementation CCBGStatusDashboardController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"模块状态";}
- (void)reloadStatusSnapshot{self.catalogSnapshot=CCBGLoadMediaCatalog();self.historySnapshot=CCBGDictionaryArrayValue(CCBGReadModulePreference(@"playbackHistory",CCBGActiveModuleSlot(),@[]));}
- (NSString *)statusSignature {
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%ld|%lu|", (long)CCBGActiveModuleSlot(), (unsigned long)self.historySnapshot.count];
    for (NSUInteger slot = 0; slot < CCBGModuleDisplayNames().count; slot++) {
        [signature appendFormat:@"%ld:%@:%@|", (long)slot, CCBGActiveModuleMediaName(slot) ?: @"", CCBGReadModulePreference(@"runtimePosition", slot, @0)];
    }
    return signature;
}
- (void)reloadStatusIfChanged {
    [self reloadStatusSnapshot];
    NSString *signature = [self statusSignature];
    if ([signature isEqualToString:self.renderedStatusSignature]) return;
    self.renderedStatusSignature = signature;
    [self.tableView reloadData];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.refreshTimer invalidate];self.renderedStatusSignature=nil;[self reloadStatusIfChanged];__weak typeof(self) weakSelf=self;self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weakSelf reloadStatusIfChanged];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.refreshTimer invalidate];self.refreshTimer=nil;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?CCBGModuleDisplayNames().count:MIN((NSUInteger)30,self.historySnapshot.count);}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"五个模块":@"当前模块播放历史";}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"status"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"status"];NSArray *catalog=self.catalogSnapshot?:@[];if(indexPath.section==0){NSInteger slot=indexPath.row;NSString *current=CCBGActiveModuleMediaName(slot);NSDictionary *item=CCBGMediaItemNamed(catalog,current);NSArray *playlist=CCBGStringArrayValue(CCBGReadModulePreference(@"playlist",slot,@[]));NSUInteger currentIndex=[playlist indexOfObject:current];NSString *next=currentIndex!=NSNotFound&&playlist.count?playlist[(currentIndex+1)%playlist.count]:@"";NSTimeInterval position=[CCBGReadModulePreference(@"runtimePosition",slot,@0)doubleValue],duration=[CCBGReadModulePreference(@"runtimeDuration",slot,@0)doubleValue];NSString *progress=duration>0?[NSString stringWithFormat:@" · %.0f/%.0f 秒",position,duration]:@"";cell.textLabel.text=[NSString stringWithFormat:@"%@ 模块",CCBGModuleDisplayNames()[slot]];cell.detailTextLabel.text=[NSString stringWithFormat:@"当前：%@%@ · 下一项：%@",item?CCBGDisplayNameForItem(item):@"无",progress,CCBGDisplayNameForItem(CCBGMediaItemNamed(catalog,next))?:@"自动"];CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"status-current-");cell.accessoryType=UITableViewCellAccessoryDetailButton;}else{NSDictionary *entry=self.historySnapshot[(NSUInteger)indexPath.row];NSDictionary *historyItem=CCBGMediaItemNamed(catalog,entry[@"fileName"]);cell.textLabel.text=CCBGDisplayNameForItem(historyItem);cell.detailTextLabel.text=[NSDate dateWithTimeIntervalSince1970:[entry[@"playedAt"]doubleValue]].description;CCBGApplyThumbnailToCell(cell,historyItem,CGSizeMake(44,44),@"status-history-");cell.accessoryType=UITableViewCellAccessoryNone;}return cell;}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{if(indexPath.section!=0)return;NSString *summary=CCBGDashboardModeSummary((NSUInteger)indexPath.row,self.catalogSnapshot?:@[]);if(summary.length&&![cell.detailTextLabel.text containsString:summary])cell.detailTextLabel.text=[cell.detailTextLabel.text stringByAppendingFormat:@" · %@",summary];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{if(indexPath.section==0){CCBGWritePreference(@"activeModuleSlot",@(indexPath.row));[self reloadStatusSnapshot];[tableView reloadData];}}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath{if(indexPath.section!=0)return;NSInteger slot=indexPath.row;NSArray *playlist=CCBGStringArrayValue(CCBGReadModulePreference(@"playlist",slot,@[]));NSString *current=CCBGActiveModuleMediaName(slot);NSUInteger idx=[playlist indexOfObject:current];if(playlist.count)CCBGSelectModuleMedia(playlist[idx==NSNotFound?0:(idx+1)%playlist.count],slot,NO);}
@end

@interface CCBGAdaptationPreviewController ()
@property(nonatomic,strong)NSDictionary *previewItem;
@end
@implementation CCBGAdaptationPreviewController
- (instancetype)initWithMediaItem:(NSDictionary *)item{self=[super init];if(self)_previewItem=item;return self;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"五尺寸适配预览";self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;UIStackView *stack=[[UIStackView alloc]init];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];[self.view addSubview:scroll];[NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20]]];NSArray *catalog=CCBGLoadMediaCatalog();NSDictionary *item=self.previewItem?:CCBGMediaItemNamed(catalog,CCBGActiveModuleMediaName(CCBGActiveModuleSlot()))?:catalog.firstObject;UIImage *image=item?CCBGThumbnailForItem(item,CGSizeMake(800,800)):nil;NSArray *names=@[@"1×2",@"2×2",@"2×3",@"3×2",@"3×3"];NSArray *ratios=@[@0.5,@1.0,@(2.0/3.0),@(3.0/2.0),@1.0];for(NSUInteger i=0;i<names.count;i++){UILabel *label=[UILabel new];label.text=names[i];label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];[stack addArrangedSubview:label];UIImageView *preview=[[UIImageView alloc]initWithImage:image];preview.contentMode=[item[@"contentMode"]integerValue]==0?UIViewContentModeScaleAspectFit:UIViewContentModeScaleAspectFill;preview.clipsToBounds=YES;preview.layer.cornerRadius=12;preview.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;[stack addArrangedSubview:preview];[preview.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;[preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:1.0/[ratios[i]doubleValue]].active=YES;}}
@end

@interface CCBGProfilesController () <UIDocumentPickerDelegate>
@property(nonatomic,copy) NSArray<NSDictionary *> *profiles;
@property(nonatomic,copy) NSArray<NSString *> *backups;
@end

@implementation CCBGProfilesController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"配置模板与回滚";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(saveProfile)];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];self.profiles=CCBGDictionaryArrayValue(CCBGReadPreference(@"configurationProfiles",@[]));self.backups=CCBGStringArrayValue([[[NSFileManager defaultManager]contentsOfDirectoryAtPath:CCBGBackupDirectory error:nil]sortedArrayUsingSelector:@selector(compare:)].reverseObjectEnumerator.allObjects);[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?self.profiles.count:section==1?self.backups.count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"完整配置模板",@"自动备份",@"导入导出"][section];}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==1;}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==1?UITableViewCellEditingStyleDelete:UITableViewCellEditingStyleNone;}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath{if(editingStyle!=UITableViewCellEditingStyleDelete||indexPath.section!=1)return;NSString *name=self.backups[indexPath.row];NSString *path=[CCBGBackupDirectory stringByAppendingPathComponent:name];NSError *error=nil;if(![[NSFileManager defaultManager]removeItemAtPath:path error:&error]){UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"无法删除备份" message:error.localizedDescription?:name preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];return;}NSMutableArray *items=[self.backups mutableCopy];[items removeObjectAtIndex:indexPath.row];self.backups=items;[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"profile"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"profile"];if(indexPath.section==0){NSDictionary *profile=self.profiles[indexPath.row];cell.textLabel.text=[profile[@"name"]isKindOfClass:NSString.class]?profile[@"name"]:@"未命名方案";NSTimeInterval createdAt=[profile[@"createdAt"]respondsToSelector:@selector(doubleValue)]?[profile[@"createdAt"]doubleValue]:0;cell.detailTextLabel.text=createdAt>0?[NSDate dateWithTimeIntervalSince1970:createdAt].description:@"未知时间";cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}else if(indexPath.section==1){cell.textLabel.text=self.backups[indexPath.row];cell.detailTextLabel.text=@"点按回滚";cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}else{cell.textLabel.text=@[@"导出配置",@"导出配置和素材",@"导入完整备份"][indexPath.row];cell.detailTextLabel.text=nil;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return cell;}
- (void)saveProfile{UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存配置模板" message:nil preferredStyle:UIAlertControllerStyleAlert];[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"模板名称";}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSMutableArray *profiles=[self.profiles mutableCopy]?:[NSMutableArray array];[profiles addObject:@{@"name":alert.textFields.firstObject.text.length?alert.textFields.firstObject.text:@"未命名模板",@"createdAt":@(NSDate.date.timeIntervalSince1970),@"preferences":CCBGProfilePreferencesSnapshot()}];CCBGWritePreference(@"configurationProfiles",profiles);self.profiles=profiles;[self.tableView reloadData];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        if (indexPath.row < 2) [self exportIncludingMedia:indexPath.row == 1];
        else {
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        }
        return;
    }

    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在恢复配置" message:@"写入后会校验完整配置，请稍候。" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    NSDictionary *profile = indexPath.section == 0 ? self.profiles[(NSUInteger)indexPath.row][@"preferences"] : nil;
    NSString *backupName = indexPath.section == 1 ? self.backups[(NSUInteger)indexPath.row] : nil;
    __weak typeof(self) weakSelf = self;
    dispatch_async(CCBGBackupWorkQueue(), ^{
        __block NSError *error = nil;
        BOOL success = NO;
        if (profile) {
            CCBGCreateAutomaticBackup(@"切换方案前");
            success = CCBGApplyProfilePreferences(profile, &error);
        } else if (backupName.length) {
            NSString *path = [CCBGBackupDirectory stringByAppendingPathComponent:backupName];
            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
            id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
            NSDictionary *backup = [object isKindOfClass:NSDictionary.class] ? object : nil;
            success = CCBGApplyPreferencesDictionary(backup[@"preferences"], &error);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [progress dismissViewControllerAnimated:YES completion:^{
                self.profiles = CCBGDictionaryArrayValue(CCBGReadPreference(@"configurationProfiles", @[]));
                self.backups = CCBGStringArrayValue([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:CCBGBackupDirectory error:nil] sortedArrayUsingSelector:@selector(compare:)].reverseObjectEnumerator.allObjects);
                [self.tableView reloadData];
                UIAlertController *result = [UIAlertController alertControllerWithTitle:success ? @"配置已恢复" : @"恢复失败" message:success ? @"完整配置已校验并重新载入。" : (error.localizedDescription ?: @"配置无效。") preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:result animated:YES completion:nil];
            }];
        });
    });
}
- (void)exportIncludingMedia:(BOOL)includeMedia {
    NSDictionary *preferences = CCBGConfigurationPreferencesSnapshot();
    NSString *name = includeMedia ? @"CleanCCBG-complete.json" : @"CleanCCBG-settings.json";
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在导出" message:includeMedia ? @"正在流式写入素材，请稍候…" : @"正在写入设置…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(CCBGBackupWorkQueue(), ^{
        __block NSError *error = nil;
        BOOL success = NO;
        if (includeMedia) {
            success = CCBGWriteCompleteBackup(path, preferences, &error);
        } else {
            NSDictionary *backup = @{@"format": @3, @"createdAt": @((long long)NSDate.date.timeIntervalSince1970), @"preferences": preferences ?: @{}};
            NSData *data = [NSJSONSerialization dataWithJSONObject:backup options:0 error:&error];
            success = data && [data writeToFile:path options:NSDataWritingAtomic error:&error];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (!success) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败" message:error.localizedDescription ?: @"无法写入备份文件" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
                share.popoverPresentationController.sourceView = self.view;
                [self presentViewController:share animated:YES completion:nil];
            }];
        });
    });
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在恢复" message:@"正在校验并写入备份…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(CCBGBackupWorkQueue(), ^{
        __block NSError *error = nil;
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSData *sourceData = [NSData dataWithContentsOfURL:url options:0 error:&error];
        if (scoped) [url stopAccessingSecurityScopedResource];
        id object = sourceData ? [NSJSONSerialization JSONObjectWithData:sourceData options:0 error:&error] : nil;
        NSDictionary *backup = [object isKindOfClass:NSDictionary.class] ? object : nil;
        NSDictionary *preferences = [backup[@"preferences"] isKindOfClass:NSDictionary.class] ? backup[@"preferences"] : nil;
        NSDictionary *media = [backup[@"media"] isKindOfClass:NSDictionary.class] ? backup[@"media"] : @{};
        if (backup && preferences && media.count) {
            [[NSFileManager defaultManager] createDirectoryAtPath:CCBGMediaDirectoryPath withIntermediateDirectories:YES attributes:nil error:&error];
            [media enumerateKeysAndObjectsUsingBlock:^(id rawName, id rawEncoded, BOOL *stop) {
                if (error || ![rawName isKindOfClass:NSString.class] || ![rawEncoded isKindOfClass:NSString.class]) return;
                NSString *name = rawName;
                if (!name.length || ![name.lastPathComponent isEqualToString:name] ||
                    [name isEqualToString:@"."] || [name isEqualToString:@".."] ||
                    ![CCBGPathForItem(@{@"fileName": name}) length]) {
                    error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.backup" code:4
                                             userInfo:@{NSLocalizedDescriptionKey: @"备份包含非法素材文件名。"}];
                    *stop = YES;
                    return;
                }
                NSData *decoded = [[NSData alloc] initWithBase64EncodedString:rawEncoded options:0];
                if (!decoded || ![decoded writeToFile:CCBGPathForItem(@{@"fileName": name}) options:NSDataWritingAtomic error:&error]) *stop = YES;
            }];
        }
        BOOL restored = NO;
        if (backup && preferences && !error) {
            CCBGCreateAutomaticBackup(@"导入完整备份前");
            restored = CCBGApplyPreferencesDictionary(preferences, &error);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (!restored) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复失败" message:error.localizedDescription ?: @"备份格式无效" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    return;
                }
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复完成" message:@"配置与素材已校验并重新载入。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        });
    });
}
@end

@interface CCBGModuleAppearanceController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *mediaCatalog;
@end

@implementation CCBGModuleAppearanceController
- (void)viewDidLoad { [super viewDidLoad]; self.title = [NSString stringWithFormat:@"%@ 外观与尺寸", CCBGModuleDisplayNames()[CCBGActiveModuleSlot()]]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.mediaCatalog = CCBGLoadMediaCatalog(); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 3 : section == 1 ? 7 : section == 2 ? 4 : section == 3 ? 2 : section == 4 ? 4 : 5; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @[@"外观预设", @"外观与展开尺寸", @"隐私模式", @"方向素材", @"动态配色", @"展开独立外观"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { if (section == 1) return @"自适应会按素材比例计算展开尺寸；手动模式才直接使用下面的宽度和高度。"; if (section == 4) return @"默认关闭。开启后只改变边框或底色，不修改素材、模糊、透明度和播放状态。"; if (section == 5) return @"开启后展开态使用独立的圆角、透明度、模糊和边框；关闭则沿用紧凑态外观。"; return nil; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row >= 5 && [CCBGReadModulePreference(@"adaptiveExpandedSizeEnabled", CCBGActiveModuleSlot(), @YES) boolValue]) return 0.01;
    return UITableViewAutomaticDimension;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath { CGFloat height = [self tableView:tableView heightForRowAtIndexPath:indexPath]; cell.hidden = height >= 0 && height < 1.0; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"preset"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"preset"];
        cell.textLabel.text = @[@"简洁", @"柔和", @"描边"][indexPath.row];
        cell.imageView.image = [UIImage systemImageNamed:@[@"square", @"square.fill", @"square.dashed"][indexPath.row]];
        return cell;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 4) {
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"expandedSizeMode"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"expandedSizeMode"];
            BOOL adaptive = [CCBGReadModulePreference(@"adaptiveExpandedSizeEnabled", CCBGActiveModuleSlot(), @YES) boolValue];
            [cell configureWithTitle:@"展开尺寸" key:@"adaptiveExpandedSizeEnabled" items:@[@"自适应", @"手动"] selected:adaptive ? 0 : 1 target:self action:@selector(expandedSizeModeChanged:)];
            return cell;
        }
        NSArray *titles = @[@"圆角", @"内边距", @"边框", @"遮罩强度", @"展开宽度", @"展开高度"];
        NSArray *keys = @[@"moduleCornerRadius", @"moduleInset", @"moduleBorderWidth", @"moduleMaskDim", @"expandedWidth", @"expandedHeight"];
        NSArray *defaults = @[@0, @0, @0, @0, @430, @600];
        NSArray *minimums = @[@0, @0, @0, @0, @220, @220];
        NSArray *maximums = @[@40, @24, @6, @0.8, @430, @600];
        NSUInteger settingIndex = indexPath.row < 4 ? (NSUInteger)indexPath.row : (NSUInteger)indexPath.row - 1;
        CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"appearanceSlider"] ?: [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"appearanceSlider"];
        [cell configureWithTitle:titles[settingIndex] key:keys[settingIndex] value:[CCBGReadModulePreference(keys[settingIndex], CCBGActiveModuleSlot(), defaults[settingIndex]) floatValue] minimum:[minimums[settingIndex] floatValue] maximum:[maximums[settingIndex] floatValue] format:settingIndex >= 4 ? @"%.0f" : @"%.1f" target:self action:@selector(sliderChanged:)];
        return cell;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 3) return [self mediaCell:tableView title:@"锁屏素材" key:@"privacyMedia"];
        if (indexPath.row == 1) {
            CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"privacyBlur"] ?: [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"privacyBlur"];
            [cell configureWithTitle:@"锁屏模糊" key:@"privacyBlur" value:[CCBGReadModulePreference(@"privacyBlur", CCBGActiveModuleSlot(), @0.7) floatValue] minimum:0 maximum:1 format:@"%.0f%%" target:self action:@selector(sliderChanged:)];
            return cell;
        }
        NSString *key = indexPath.row == 0 ? @"privacyEnabled" : @"privacyPauseVideo";
        CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"privacySwitch"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"privacySwitch"];
        [cell configureWithTitle:indexPath.row == 0 ? @"启用隐私模式" : @"锁屏暂停视频" key:key value:[CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @YES) boolValue] target:self action:@selector(switchChanged:)];
        return cell;
    }
    if (indexPath.section == 3) return [self mediaCell:tableView title:indexPath.row == 0 ? @"竖屏素材" : @"横屏素材" key:indexPath.row == 0 ? @"portraitMedia" : @"landscapeMedia"];
    if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"expandedAppearanceSwitch"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"expandedAppearanceSwitch"];
            [cell configureWithTitle:@"启用独立展开外观" key:@"expandedAppearanceEnabled" value:[CCBGReadModulePreference(@"expandedAppearanceEnabled", CCBGActiveModuleSlot(), @NO) boolValue] target:self action:@selector(switchChanged:)];
            return cell;
        }
        NSArray *titles = @[@"展开圆角", @"展开透明度", @"展开模糊度", @"展开边框"];
        NSArray *keys = @[@"expandedCornerRadius", @"expandedOpacity", @"expandedBlurIntensity", @"expandedBorderWidth"];
        NSArray *defaults = @[@0, @1, @0, @0];
        NSArray *minimums = @[@0, @0.05, @0, @0];
        NSArray *maximums = @[@40, @1, @1, @6];
        NSUInteger i = (NSUInteger)indexPath.row - 1;
        CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"expandedAppearanceSlider"] ?: [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"expandedAppearanceSlider"];
        [cell configureWithTitle:titles[i] key:keys[i] value:[CCBGReadModulePreference(keys[i], CCBGActiveModuleSlot(), defaults[i]) floatValue] minimum:[minimums[i] floatValue] maximum:[maximums[i] floatValue] format:i == 0 || i == 3 ? @"%.1f" : @"%.0f%%" target:self action:@selector(sliderChanged:)];
        return cell;
    }
    if (indexPath.row == 0 || indexPath.row == 1) {
        NSString *key = indexPath.row == 0 ? @"foregroundAppTintEnabled" : @"wallpaperTintEnabled";
        CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dynamicTintSwitch"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dynamicTintSwitch"];
        [cell configureWithTitle:indexPath.row == 0 ? @"前台 App 图标取色" : @"壁纸配色" key:key value:[CCBGReadModulePreference(key, CCBGActiveModuleSlot(), @NO) boolValue] target:self action:@selector(switchChanged:)];
        return cell;
    }
    if (indexPath.row == 2) {
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dynamicTintTarget"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dynamicTintTarget"];
        [cell configureWithTitle:@"应用位置" key:@"dynamicTintTarget" items:@[@"边框", @"底色", @"两者"] selected:[CCBGReadModulePreference(@"dynamicTintTarget", CCBGActiveModuleSlot(), @0) integerValue] target:self action:@selector(dynamicTintTargetChanged:)];
        return cell;
    }
    CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"dynamicTintStrength"] ?: [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"dynamicTintStrength"];
    [cell configureWithTitle:@"配色强度" key:@"dynamicTintStrength" value:[CCBGReadModulePreference(@"dynamicTintStrength", CCBGActiveModuleSlot(), @0.65) floatValue] minimum:0 maximum:1 format:@"%.0f%%" target:self action:@selector(sliderChanged:)];
    return cell;
}
- (UITableViewCell *)mediaCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"appearanceMedia"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"appearanceMedia"];NSDictionary *item=CCBGMediaItemNamed(self.mediaCatalog,CCBGReadModulePreference(key,CCBGActiveModuleSlot(),@""));cell.textLabel.text=title;cell.detailTextLabel.text=CCBGDisplayNameForItem(item)?:@"??";CCBGApplyThumbnailToCell(cell,item,CGSizeMake(44,44),@"appearance-media-");cell.accessibilityIdentifier=key;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; if(indexPath.section==0){NSArray *values=indexPath.row==0?@[@0,@0,@0,@0]:indexPath.row==1?@[@22,@2,@0,@0.12]:@[@18,@1,@2,@0.08];NSArray *keys=@[@"moduleCornerRadius",@"moduleInset",@"moduleBorderWidth",@"moduleMaskDim"];CCBGWriteModulePreferences([NSDictionary dictionaryWithObjects:values forKeys:keys],CCBGActiveModuleSlot());[tableView reloadData];return;}UITableViewCell *cell=[tableView cellForRowAtIndexPath:indexPath];NSString *key=cell.accessibilityIdentifier;if(!key.length)return;NSInteger slot=CCBGActiveModuleSlot();CCBGMediaPickerController *picker=[[CCBGMediaPickerController alloc]initWithTitle:cell.textLabel.text selected:CCBGReadModulePreference(key,slot,@"") completion:^(NSString *name){CCBGWriteModulePreference(key,slot,name?:@"");[self.tableView reloadData];}];[self.navigationController pushViewController:picker animated:YES]; }
- (void)switchChanged:(UISwitch *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.on));}
- (void)expandedSizeModeChanged:(UISegmentedControl *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.selectedSegmentIndex==0));[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];}
- (void)dynamicTintTargetChanged:(UISegmentedControl *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.selectedSegmentIndex));}
- (void)sliderChanged:(UISlider *)sender{CCBGWriteModulePreference(sender.accessibilityIdentifier,CCBGActiveModuleSlot(),@(sender.value));UIView *v=sender;while(v&&![v isKindOfClass:CCBGSliderCell.class])v=v.superview;[(CCBGSliderCell *)v refreshValueLabel];}
@end

@interface CCBGAdvancedAutomationController ()
@property(nonatomic,strong)NSMutableArray<NSDictionary *> *rules;
@property(nonatomic,strong)NSMutableArray<NSDictionary *> *schedules;
@end

@implementation CCBGAdvancedAutomationController
- (void)viewDidLoad{[super viewDidLoad];self.title=@"组合规则与定时列表";UIDevice.currentDevice.batteryMonitoringEnabled=YES;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addMenu)];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];self.rules=[CCBGDictionaryArrayValue(CCBGReadModulePreference(@"compoundRules",CCBGActiveModuleSlot(),@[]))mutableCopy];self.schedules=[CCBGDictionaryArrayValue(CCBGReadModulePreference(@"scheduledPlaylists",CCBGActiveModuleSlot(),@[]))mutableCopy];[self updateConflictHeader];[self.tableView reloadData];}
- (void)updateConflictHeader {
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:NSDate.date];
    NSInteger minute = components.hour * 60 + components.minute;
    BOOL dark = CCBGSystemUsesDarkAppearance();
    BOOL charging = UIDevice.currentDevice.batteryState == UIDeviceBatteryStateCharging || UIDevice.currentDevice.batteryState == UIDeviceBatteryStateFull;
    BOOL lowPower = NSProcessInfo.processInfo.lowPowerModeEnabled;
    NSArray *sorted = [self.rules sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftPriority = CCBGIntegerValue(left[@"priority"], 0);
        NSInteger rightPriority = CCBGIntegerValue(right[@"priority"], 0);
        return leftPriority == rightPriority ? NSOrderedSame : leftPriority > rightPriority ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSDictionary *rule in sorted) {
        if (!CCBGIntegerValue(rule[@"enabled"], 0)) continue;
        NSInteger ruleDark = CCBGIntegerValue(rule[@"dark"], -1);
        NSInteger ruleCharging = CCBGIntegerValue(rule[@"charging"], -1);
        NSInteger ruleLowPower = CCBGIntegerValue(rule[@"lowPower"], -1);
        if (ruleDark >= 0 && (BOOL)ruleDark != dark) continue;
        if (ruleCharging >= 0 && (BOOL)ruleCharging != charging) continue;
        if (ruleLowPower >= 0 && (BOOL)ruleLowPower != lowPower) continue;
        NSArray *days = [rule[@"weekdays"] isKindOfClass:NSArray.class] ? rule[@"weekdays"] : @[];
        if (days.count && ![days containsObject:@(components.weekday)]) continue;
        NSInteger start = CCBGIntegerValue(rule[@"startMinutes"], 0);
        NSInteger end = CCBGIntegerValue(rule[@"endMinutes"], 0);
        if (end > 0) {
            BOOL active = start <= end ? minute >= start && minute < end : minute >= start || minute < end;
            if (!active) continue;
        }
        [matches addObject:rule];
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *rule in matches) if ([rule[@"name"] isKindOfClass:NSString.class]) [names addObject:rule[@"name"]];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, MAX(1, self.tableView.bounds.size.width - 40), matches.count ? 76 : 52)];
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = matches.count ? [NSString stringWithFormat:@"当前命中：%@\n最终采用：%@", [names componentsJoinedByString:@"、"], names.firstObject ?: @"未命名规则"] : @"当前没有组合规则命中，将继续检查基础自动化。";
    self.tableView.tableHeaderView = label;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?self.rules.count:self.schedules.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"组合自动化规则":@"定时素材分组";}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"advancedRule"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"advancedRule"];
    NSDictionary *item = indexPath.section == 0 ? self.rules[indexPath.row] : self.schedules[indexPath.row];
    cell.textLabel.text = item[@"name"] ?: (indexPath.section == 0 ? @"组合规则" : @"定时列表");
    if (indexPath.section == 0) {
        NSDictionary *media = CCBGMediaItemNamed(CCBGLoadMediaCatalog(), item[@"media"]);
        cell.detailTextLabel.text = [NSString stringWithFormat:@"优先级 %@ · %@", item[@"priority"] ?: @0, media ? CCBGDisplayNameForItem(media) : @"未选择素材"];
        CCBGApplyThumbnailToCell(cell, media, CGSizeMake(44, 44), @"advanced-rule-");
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %02ld:%02ld–%02ld:%02ld", item[@"group"] ?: @"未分组", (long)[item[@"startMinutes"] integerValue] / 60, (long)[item[@"startMinutes"] integerValue] % 60, (long)[item[@"endMinutes"] integerValue] / 60, (long)[item[@"endMinutes"] integerValue] % 60];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)addMenu{UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"新增" message:nil preferredStyle:UIAlertControllerStyleActionSheet];[menu addAction:[UIAlertAction actionWithTitle:@"组合规则" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self chooseMediaForNewRule];}] ];[menu addAction:[UIAlertAction actionWithTitle:@"定时素材分组" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self addSchedule];}] ];[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:menu animated:YES completion:nil];}
- (void)chooseMediaForNewRule{NSInteger slot=CCBGActiveModuleSlot();CCBGMediaPickerController *picker=[[CCBGMediaPickerController alloc]initWithTitle:@"规则命中素材" selected:@"" completion:^(NSString *name){[self.rules addObject:@{@"name":@"组合规则",@"enabled":@YES,@"priority":@(self.rules.count+1),@"media":name?:@"",@"dark":@-1,@"charging":@-1,@"lowPower":@-1,@"weekdays":@[]}];CCBGWriteModulePreference(@"compoundRules",slot,self.rules);[self.tableView reloadData];}];[self.navigationController pushViewController:picker animated:YES];}
- (void)addSchedule{UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"定时素材分组" message:@"默认 18:00–23:59，可在再次点按后调整。" preferredStyle:UIAlertControllerStyleAlert];[alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"分组名称";}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){[self.schedules addObject:@{@"name":alert.textFields.firstObject.text?:@"定时列表",@"group":alert.textFields.firstObject.text?:@"",@"enabled":@YES,@"startMinutes":@1080,@"endMinutes":@1439}];CCBGWriteModulePreference(@"scheduledPlaylists",CCBGActiveModuleSlot(),self.schedules);[self.tableView reloadData];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{[tableView deselectRowAtIndexPath:indexPath animated:YES];NSMutableArray *source=indexPath.section==0?self.rules:self.schedules;NSMutableDictionary *entry=[source[indexPath.row]mutableCopy];UIAlertController *menu=[UIAlertController alertControllerWithTitle:entry[@"name"] message:indexPath.section==0?@"可组合深色、充电、低电量条件":@"点调整可轮换常用时间段" preferredStyle:UIAlertControllerStyleActionSheet];if(indexPath.section==0){[menu addAction:[UIAlertAction actionWithTitle:@"切换深色条件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){entry[@"dark"]=@(([entry[@"dark"]integerValue]+2)%3-1);[self saveEntry:entry at:indexPath];}]];[menu addAction:[UIAlertAction actionWithTitle:@"切换充电条件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){entry[@"charging"]=@(([entry[@"charging"]integerValue]+2)%3-1);[self saveEntry:entry at:indexPath];}]];[menu addAction:[UIAlertAction actionWithTitle:@"切换低电量条件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){entry[@"lowPower"]=@(([entry[@"lowPower"]integerValue]+2)%3-1);[self saveEntry:entry at:indexPath];}]];[menu addAction:[UIAlertAction actionWithTitle:@"提高优先级" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){entry[@"priority"]=@([entry[@"priority"]integerValue]+1);[self saveEntry:entry at:indexPath];}]];}else{[menu addAction:[UIAlertAction actionWithTitle:@"切换为白天 07:00–18:00" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){entry[@"startMinutes"]=@420;entry[@"endMinutes"]=@1080;[self saveEntry:entry at:indexPath];}]];}[menu addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){[source removeObjectAtIndex:indexPath.row];CCBGWriteModulePreference(indexPath.section==0?@"compoundRules":@"scheduledPlaylists",CCBGActiveModuleSlot(),source);[self.tableView reloadData];}]];[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=self.view;menu.popoverPresentationController.sourceRect=self.view.bounds;[self presentViewController:menu animated:YES completion:nil];}
- (void)saveEntry:(NSDictionary *)entry at:(NSIndexPath *)indexPath{NSMutableArray *source=indexPath.section==0?self.rules:self.schedules;source[indexPath.row]=entry;CCBGWriteModulePreference(indexPath.section==0?@"compoundRules":@"scheduledPlaylists",CCBGActiveModuleSlot(),source);[self.tableView reloadData];}
@end
