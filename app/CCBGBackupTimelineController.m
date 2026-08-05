#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"

static NSString *const CCBGBackupTimelineDirectory = @"/var/mobile/Library/CleanCCBG2x2/Backups";
static const NSUInteger CCBGBackupTimelineLimit = 20;

static NSDictionary *CCBGBackupTimelineObjectAtPath(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *backup = value;
    NSDictionary *preferences = [backup[@"preferences"] isKindOfClass:NSDictionary.class] ? backup[@"preferences"] : nil;
    if (!preferences || ![NSPropertyListSerialization propertyList:preferences isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return nil;
    return backup;
}

static NSString *CCBGBackupTimelineDateString(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"未知时间";
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale currentLocale];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"未知时间";
}

@interface CCBGBackupTimelineController ()
@property(nonatomic, copy) NSArray<NSDictionary *> *backups;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) BOOL operationInFlight;
@end

@implementation CCBGBackupTimelineController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"备份时间机";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createManualSnapshot)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadBackups];
}

- (void)reloadBackups {
    NSUInteger generation = ++self.loadGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:CCBGBackupTimelineDirectory error:nil] ?: @[];
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
        for (NSString *name in names) {
            if (![name.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
            NSString *path = [CCBGBackupTimelineDirectory stringByAppendingPathComponent:name];
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
            if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
            NSDictionary *backup = CCBGBackupTimelineObjectAtPath(path);
            if (!backup) continue;
            NSTimeInterval createdAt = [backup[@"createdAt"] respondsToSelector:@selector(doubleValue)] ? [backup[@"createdAt"] doubleValue] : [attributes[NSFileModificationDate] timeIntervalSince1970];
            NSString *reason = [backup[@"reason"] isKindOfClass:NSString.class] ? backup[@"reason"] : @"手动导出的备份";
            NSDictionary *preferences = backup[@"preferences"];
            [entries addObject:@{
                @"path": path,
                @"createdAt": @(createdAt),
                @"reason": reason,
                @"preferences": preferences,
                @"keyCount": @(preferences.count),
            }];
        }
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"createdAt"] compare:left[@"createdAt"]];
        }];
        if (entries.count > CCBGBackupTimelineLimit) [entries removeObjectsInRange:NSMakeRange(CCBGBackupTimelineLimit, entries.count - CCBGBackupTimelineLimit)];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.loadGeneration) return;
            self.backups = entries;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.backups.count ? @"恢复前会自动保存一个新的回退点；仅恢复设置，不删除或覆盖素材文件。" : @"自动备份会在设置修改前生成。点右上角加号可立即创建一个完整设置快照。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = self.backups[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backup"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"backup"];
    cell.textLabel.text = CCBGBackupTimelineDateString([entry[@"createdAt"] doubleValue]);
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ 项设置", entry[@"reason"] ?: @"备份", entry[@"keyCount"] ?: @0];
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"clock.badge.checkmark" : @"clock.arrow.circlepath"];
    cell.imageView.tintColor = CCBGAppAccentColor();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSUInteger)changedPreferenceCountForBackup:(NSDictionary *)backup {
    NSDictionary *preferences = [backup[@"preferences"] isKindOfClass:NSDictionary.class] ? backup[@"preferences"] : @{};
    NSDictionary *current = CCBGReadAllPreferences();
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:current.allKeys];
    [keys addObjectsFromArray:preferences.allKeys];
    NSUInteger changed = 0;
    for (NSString *key in keys) if (![current[key] isEqual:preferences[key]]) changed++;
    return changed;
}

- (BOOL)writeSnapshotWithReason:(NSString *)reason error:(NSError **)error {
    NSDictionary *preferences = CCBGConfigurationPreferencesSnapshot();
    NSDictionary *backup = @{
        @"format": @3,
        @"createdAt": @((long long)NSDate.date.timeIntervalSince1970),
        @"appVersion": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"reason": reason.length ? reason : @"手动快照",
        @"preferences": preferences,
    };
    if (![NSJSONSerialization isValidJSONObject:backup]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:backup options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:CCBGBackupTimelineDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSString *name = [NSString stringWithFormat:@"snapshot-%.0f.json", NSDate.date.timeIntervalSince1970 * 1000.0];
    NSString *path = [CCBGBackupTimelineDirectory stringByAppendingPathComponent:name];
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (void)createManualSnapshot {
    if (self.operationInFlight) return;
    self.operationInFlight = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在创建设置快照" message:@"正在整理配置并写入备份时间机。" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        BOOL written = [self writeSnapshotWithReason:@"手动创建的完整设置快照" error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.operationInFlight = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [progress dismissViewControllerAnimated:YES completion:^{
                if (written) {
                    [self reloadBackups];
                    return;
                }
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法创建快照" message:error.localizedDescription ?: @"写入失败。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        });
    });
}

- (void)restoreBackup:(NSDictionary *)backup {
    if (self.operationInFlight) return;
    self.operationInFlight = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    NSDictionary *preferences = backup[@"preferences"];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在恢复完整设置" message:@"正在创建回退点并校验写入。" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        BOOL snapshotSaved = [self writeSnapshotWithReason:@"恢复前快照" error:&error];
        BOOL restored = snapshotSaved && CCBGRestorePreferencesSnapshot(preferences, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.operationInFlight = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [progress dismissViewControllerAnimated:YES completion:^{
                [self reloadBackups];
                UIAlertController *result = [UIAlertController alertControllerWithTitle:restored ? @"设置已恢复" : @"未恢复" message:restored ? @"已保留恢复前快照，完整配置已校验并重新载入。" : (error.localizedDescription ?: @"无法恢复配置。") preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:result animated:YES completion:nil];
            }];
        });
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= self.backups.count) return;
    NSDictionary *backup = self.backups[(NSUInteger)indexPath.row];
    NSUInteger changed = [self changedPreferenceCountForBackup:backup];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:CCBGBackupTimelineDateString([backup[@"createdAt"] doubleValue]) message:[NSString stringWithFormat:@"%@\n与当前设置相比：%lu 项将变化。", backup[@"reason"] ?: @"备份", (unsigned long)changed] preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"查看影响" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *details = [UIAlertController alertControllerWithTitle:@"恢复影响" message:[NSString stringWithFormat:@"将替换 %lu 项设置。共享素材文件不会被删除或覆盖。", (unsigned long)changed] preferredStyle:UIAlertControllerStyleAlert];
        [details addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:details animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"恢复此备份" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self restoreBackup:backup];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"删除此快照" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[NSFileManager defaultManager] removeItemAtPath:backup[@"path"] error:nil];
        [self reloadBackups];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

@end
