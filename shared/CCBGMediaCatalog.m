#import "CCBGMediaCatalog.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <math.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <dlfcn.h>

NSString *const CCBGPreferenceDomain = @"com.zjc.cleanccbg2x2";
NSString *const CCBGReloadNotificationName = @"com.zjc.cleanccbg2x2/reload";
NSString *const CCBGSizeReloadNotificationName = @"com.zjc.cleanccbg2x2/size-reload";
NSString *const CCBGPresentationRecoveryNotificationName = @"com.zjc.cleanccbg2x2/presentation-recovery";
NSString *const CCBGFocusRefreshNotificationName = @"com.zjc.cleanccbg2x2/refresh-focus";
NSString *const CCBGMediaDirectoryPath = @"/var/mobile/Library/CleanCCBG2x2/Media";
static NSString *const CCBGAutomaticBackupDirectory = @"/var/mobile/Library/CleanCCBG2x2/Backups";
static NSString *const CCBGQuickConfigurationUndoStackKey = @"quickConfigurationUndoStack";
static NSString *const CCBGModuleLifecycleTracePath = @"/var/mobile/Library/CleanCCBG2x2/module-lifecycle.log";
static NSString *const CCBGModuleLifecycleTraceLockPath = @"/var/mobile/Library/CleanCCBG2x2/module-lifecycle.lock";
static NSString *const CCBGAnalyticsMutationLockPath = @"/var/mobile/Library/Preferences/com.zjc.cleanccbg2x2.analytics.lock";
static NSString *const CCBGPreferencesMutationLockPath = @"/var/mobile/Library/Preferences/com.zjc.cleanccbg2x2.preferences.lock";
static CFStringRef const CCBGCCAsterPreferencesDomain = CFSTR("com.futur3sn0w.ccaster.preferences");
static CFStringRef const CCBGCCAsterReloadNotification = CFSTR("com.futur3sn0w.ccaster/ReloadPrefs");
static void *CCBGAnalyticsMutationQueueSpecificKey = &CCBGAnalyticsMutationQueueSpecificKey;

static dispatch_queue_t CCBGAnalyticsMutationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.analytics-mutation", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_queue_set_specific(queue, CCBGAnalyticsMutationQueueSpecificKey, CCBGAnalyticsMutationQueueSpecificKey, NULL);
    });
    return queue;
}

static void CCBGWithFileLock(NSString *lockPath, dispatch_block_t mutation) {
    if (!mutation) return;
    int fileDescriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    BOOL locked = NO;
    if (fileDescriptor >= 0) {
        int result;
        do {
            result = flock(fileDescriptor, LOCK_EX);
        } while (result != 0 && errno == EINTR);
        locked = result == 0;
    }
    mutation();
    if (locked) flock(fileDescriptor, LOCK_UN);
    if (fileDescriptor >= 0) close(fileDescriptor);
}

static void CCBGWithAnalyticsMutationLock(dispatch_block_t mutation) {
    CCBGWithFileLock(CCBGAnalyticsMutationLockPath, mutation);
}

static void CCBGEnqueueAnalyticsMutation(dispatch_block_t mutation) {
    if (!mutation) return;
    dispatch_async(CCBGAnalyticsMutationQueue(), ^{
        @autoreleasepool {
            CCBGWithAnalyticsMutationLock(mutation);
        }
    });
}

static void CCBGReadAnalyticsStateSynchronously(dispatch_block_t readBlock) {
    if (!readBlock) return;
    if (dispatch_get_specific(CCBGAnalyticsMutationQueueSpecificKey)) {
        readBlock();
        return;
    }
    dispatch_sync(CCBGAnalyticsMutationQueue(), ^{
        @autoreleasepool {
            CCBGWithAnalyticsMutationLock(readBlock);
        }
    });
}

static void CCBGWithModuleLifecycleTraceLock(dispatch_block_t operation) {
    NSString *directory = [CCBGModuleLifecycleTracePath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    CCBGWithFileLock(CCBGModuleLifecycleTraceLockPath, operation);
}

static dispatch_queue_t CCBGModuleLifecycleTraceQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.module-lifecycle", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

void CCBGRecordModuleLifecycleEvent(NSInteger slot, NSString *event, NSDictionary *details) {
    NSString *safeEvent = [(event ?: @"unknown") stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (safeEvent.length > 80) safeEvent = [safeEvent substringToIndex:80];
    NSDictionary *capturedDetails = [details copy] ?: @{};
    NSTimeInterval recordedAt = NSDate.date.timeIntervalSince1970;
    dispatch_async(CCBGModuleLifecycleTraceQueue(), ^{
        @autoreleasepool {
            NSString *detail = [capturedDetails.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (detail.length > 480) detail = [detail substringToIndex:480];
            NSString *line = [NSString stringWithFormat:@"%.3f slot=%ld event=%@ detail=%@\n", recordedAt, (long)slot, safeEvent, detail];
            CCBGWithModuleLifecycleTraceLock(^{
                NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
                unsigned long long existingBytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:CCBGModuleLifecycleTracePath error:nil][NSFileSize] unsignedLongLongValue];
                if (existingBytes > 65536) {
                    [data writeToFile:CCBGModuleLifecycleTracePath atomically:YES];
                    return;
                }
                if (![[NSFileManager defaultManager] fileExistsAtPath:CCBGModuleLifecycleTracePath]) [data writeToFile:CCBGModuleLifecycleTracePath atomically:YES];
                else {
                    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:CCBGModuleLifecycleTracePath];
                    [handle seekToEndOfFile];
                    [handle writeData:data];
                    [handle closeFile];
                }
            });
        }
    });
}

NSArray<NSString *> *CCBGReadModuleLifecycleTrace(void) {
    __block NSString *contents = @"";
    CCBGWithModuleLifecycleTraceLock(^{
        contents = [NSString stringWithContentsOfFile:CCBGModuleLifecycleTracePath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    });
    NSArray<NSString *> *lines = [contents componentsSeparatedByString:@"\n"];
    if (lines.count <= 160) return lines;
    return [lines subarrayWithRange:NSMakeRange(lines.count - 160, 160)];
}

void CCBGClearModuleLifecycleTrace(void) {
    dispatch_sync(CCBGModuleLifecycleTraceQueue(), ^{
        CCBGWithModuleLifecycleTraceLock(^{
            [[NSFileManager defaultManager] removeItemAtPath:CCBGModuleLifecycleTracePath error:nil];
        });
    });
}

static void CCBGCreateDebouncedAutomaticBackup(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.zjc.cleanccbg2x2.app"]) return;
    static NSTimeInterval lastBackup = 0;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - lastBackup < 300) return;
    lastBackup = now;
    NSDictionary *values = CCBGConfigurationPreferencesSnapshot();
    NSDictionary *backup = @{@"format": @3, @"createdAt": @((long long)now), @"reason": @"自动修改前快照", @"preferences": values};
    NSData *data = [NSJSONSerialization dataWithJSONObject:backup options:0 error:nil];
    if (!data) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:CCBGAutomaticBackupDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *backupPath = [CCBGAutomaticBackupDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"backup-%.0f.json", now]];
    // BUGFIX: previously the write's success/failure was ignored, so a failed
    // write (e.g. disk full or permission issue) would still fall through to
    // trimming older backups, potentially deleting good backups while the new
    // one never landed. Now we bail out before trimming if the write failed.
    if (![data writeToFile:backupPath atomically:YES]) return;
    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:CCBGAutomaticBackupDirectory error:nil];
    // BUGFIX: previously trimmed oldest-first using a plain string compare of
    // filenames, which only sorts chronologically as long as the numeric
    // timestamp component has a fixed digit width. Sort numerically on the
    // extracted timestamp instead so trimming is correct regardless of digit
    // width changes.
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        long long leftValue = [[left stringByReplacingOccurrencesOfString:@"backup-" withString:@""] longLongValue];
        long long rightValue = [[right stringByReplacingOccurrencesOfString:@"backup-" withString:@""] longLongValue];
        if (leftValue < rightValue) return NSOrderedAscending;
        if (leftValue > rightValue) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray<NSString *> *remaining = [files mutableCopy];
    while (remaining.count > 10) {
        [[NSFileManager defaultManager] removeItemAtPath:[CCBGAutomaticBackupDirectory stringByAppendingPathComponent:remaining.firstObject] error:nil];
        [remaining removeObjectAtIndex:0];
    }
}

static NSSet<NSString *> *CCBGSupportedExtensions(void) {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"gif", @"mp4", @"mov", @"m4v"]];
    });
    return extensions;
}

static NSDictionary *CCBGDefaultMediaConfiguration(void) {
    return @{
        @"randomWeight": @1.0,
        @"mute": @YES,
        @"loop": @YES,
        @"playbackRate": @1.0,
        @"startTime": @0.0,
        @"endTime": @0.0,
        @"contentMode": @1,
        @"blurIntensity": @0.25,
        @"dim": @0.0,
        @"saturation": @1.0,
        @"contrast": @1.0,
        @"opacity": @1.0,
        @"focalX": @0.5,
        @"focalY": @0.5,
        @"compactContentMode": @-1,
        @"expandedContentMode": @-1,
        @"compactFocalX": @-1.0,
        @"compactFocalY": @-1.0,
        @"expandedFocalX": @-1.0,
        @"expandedFocalY": @-1.0,
        @"compactCropZoom": @1.0,
        @"expandedCropZoom": @1.0,
        @"imageDuration": @0.0,
        @"videoAdvancePolicy": @0,
        @"videoPlayCount": @1,
        @"coverFrameTime": @0.0,
        @"portraitContentMode": @-1,
        @"landscapeContentMode": @-1,
        @"portraitFocalX": @-1.0,
        @"portraitFocalY": @-1.0,
        @"landscapeFocalX": @-1.0,
        @"landscapeFocalY": @-1.0,
        @"autoColor": @NO,
    };
}

static NSObject *CCBGPreferenceReadCacheLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSDictionary<NSString *, id> *CCBGPreferenceReadCache;
static NSArray<NSDictionary *> *CCBGMediaCatalogCache;
static NSTimeInterval CCBGMediaCatalogCacheTimestamp;
static NSTimeInterval CCBGMediaDirectoryReadableCacheAt;
static BOOL CCBGMediaDirectoryReadableCacheValue;
// SpringBoard mounts multiple Clean modules in one opening pass. A short
// shared snapshot prevents each instance from rescanning the media directory
// while still allowing external file changes to appear promptly.
static const NSTimeInterval CCBGMediaCatalogCacheTTL = 0.65;
static NSNumber *CCBGMediaStorageBytesCache;
static BOOL CCBGPreferenceReadCacheAllowed(void);

static NSObject *CCBGMediaCatalogCacheLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSArray<NSDictionary *> *CCBGMediaCatalogCachedValue(void) {
    @synchronized (CCBGMediaCatalogCacheLock()) {
        NSArray<NSDictionary *> *cached = CCBGMediaCatalogCache;
        if (!cached) return nil;
        if (CCBGPreferenceReadCacheAllowed()) return cached;
        NSTimeInterval cachedAt = CCBGMediaCatalogCacheTimestamp;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (cachedAt > 0.0 && now - cachedAt < CCBGMediaCatalogCacheTTL) return cached;
        CCBGMediaCatalogCache = nil;
        CCBGMediaCatalogCacheTimestamp = 0.0;
        return nil;
    }
}

static BOOL CCBGPreferenceReadCacheAllowed(void) {
    static BOOL allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // SpringBoard and system overlays must always see cross-process
        // preference changes immediately. Only the settings app can use the
        // in-process snapshot to avoid repeated reads while scrolling.
        allowed = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.zjc.cleanccbg2x2.app"];
    });
    return allowed;
}

static NSDictionary<NSString *, id> *CCBGReadPreferencesFromDisk(void) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesAppSynchronize(domain);
    CFArrayRef keysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSArray *keys = CFBridgingRelease(keysRef) ?: @[];
    CFDictionaryRef valuesRef = CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(valuesRef) ?: @{};
}

void CCBGInvalidatePreferenceReadCache(void) {
    @synchronized (CCBGPreferenceReadCacheLock()) {
        CCBGPreferenceReadCache = nil;
    }
    @synchronized (CCBGMediaCatalogCacheLock()) {
        CCBGMediaCatalogCache = nil;
        CCBGMediaCatalogCacheTimestamp = 0.0;
        CCBGMediaDirectoryReadableCacheAt = 0.0;
        CCBGMediaStorageBytesCache = nil;
    }
}

id CCBGReadPreference(NSString *key, id fallback) {
    if (!key.length) return fallback;
    if (!CCBGPreferenceReadCacheAllowed()) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesAppSynchronize(domain);
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
        return value ? CFBridgingRelease(value) : fallback;
    }
    return CCBGReadAllPreferences()[key] ?: fallback;
}

BOOL CCBGPluginEnabled(void) {
    return [CCBGReadPreference(@"pluginEnabled", @YES) boolValue];
}

void CCBGSetPluginEnabled(BOOL enabled) {
    CCBGWritePreference(@"pluginEnabled", @(enabled));
    // The master switch is a separate Control Center bundle. In addition to
    // the preference reload, send an explicit presentation boundary so
    // already-mounted modules can reattach their media without waiting for a
    // new viewWillAppear callback.
    CCBGPostPresentationRecovery();
}

NSDictionary<NSString *, id> *CCBGReadAllPreferences(void) {
    if (!CCBGPreferenceReadCacheAllowed()) return CCBGReadPreferencesFromDisk();
    @synchronized (CCBGPreferenceReadCacheLock()) {
        if (!CCBGPreferenceReadCache) CCBGPreferenceReadCache = CCBGReadPreferencesFromDisk();
        return CCBGPreferenceReadCache;
    }
}

static BOOL CCBGConfigurationKeyIsVolatile(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return YES;
    for (NSString *prefix in @[
        @"sceneDirectorLast", @"genericOverlayLast", @"lastConfigurationWrite",
        @"runtimeDiagnostic.", @"moduleLifecycle", @"configurationRevision"
    ]) {
        if ([key hasPrefix:prefix]) return YES;
    }
    for (NSString *fragment in @[
        @"runtimeMedia", @"mediaSelectionRevision", @"moduleRuntimePosition",
        @"moduleRuntimeDuration", @"runtimePosition", @"runtimeDuration",
        @"playbackHistory", @"recentMedia"
    ]) {
        if ([key containsString:fragment]) return YES;
    }
    return [@[
        @"sceneDirectorManualSceneID", @"sceneDirectorReplayActive",
        @"sceneDirectorExpandedSlot", @"quickConfigurationUndoStack", @"visualThemeAutomationLastClaimAt"
    ] containsObject:key];
}

NSDictionary<NSString *, id> *CCBGConfigurationPreferencesSnapshot(void) {
    NSMutableDictionary<NSString *, id> *snapshot = [CCBGReadAllPreferences() mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in [snapshot.allKeys copy]) {
        if (CCBGConfigurationKeyIsVolatile(key)) [snapshot removeObjectForKey:key];
    }
    return snapshot;
}

static BOOL CCBGPreferenceChangesIncludeGridSize(NSDictionary<NSString *, id> *values) {
    for (id rawKey in values) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        NSString *key = rawKey;
        if ([key isEqualToString:@"gridWidth"] || [key isEqualToString:@"gridHeight"] ||
            [key hasPrefix:@"gridWidth.module"] || [key hasPrefix:@"gridHeight.module"]) return YES;
    }
    return NO;
}

static BOOL CCBGPreferenceChangesOnlyGridSize(NSDictionary<NSString *, id> *values) {
    if (!values.count) return NO;
    for (id rawKey in values) {
        if (![rawKey isKindOfClass:NSString.class]) return NO;
        NSString *key = rawKey;
        BOOL gridKey = [key isEqualToString:@"gridWidth"] || [key isEqualToString:@"gridHeight"] ||
            [key hasPrefix:@"gridWidth.module"] || [key hasPrefix:@"gridHeight.module"];
        if (!gridKey) return NO;
    }
    return YES;
}

static void CCBGSyncCCAsterGridSizeIfPresent(NSDictionary<NSString *, id> *values) {
    if (!values.count) return;
    CFPropertyListRef existingRef = CFPreferencesCopyAppValue(CFSTR("ModuleGridSizes"), CCBGCCAsterPreferencesDomain);
    NSDictionary *existing = CFBridgingRelease(existingRef);
    if (![existing isKindOfClass:NSDictionary.class]) return;
    NSArray<NSString *> *identifiers = @[
        @"com.zjc.cleanccbg2x2.module", @"com.zjc.cleanccbg2x2.module1x2",
        @"com.zjc.cleanccbg2x2.module2x3", @"com.zjc.cleanccbg2x2.module3x2",
        @"com.zjc.cleanccbg2x2.module3x3",
    ];
    NSMutableDictionary *sizes = [existing mutableCopy];
    BOOL changed = NO;
    for (NSInteger slot = 0; slot < (NSInteger)identifiers.count; slot++) {
        NSString *widthKey = slot == 0 ? @"gridWidth" : [NSString stringWithFormat:@"gridWidth.module%ld", (long)slot];
        NSString *heightKey = slot == 0 ? @"gridHeight" : [NSString stringWithFormat:@"gridHeight.module%ld", (long)slot];
        NSNumber *width = values[widthKey];
        NSNumber *height = values[heightKey];
        if (![width respondsToSelector:@selector(integerValue)] || ![height respondsToSelector:@selector(integerValue)]) continue;
        NSArray *normalized = @[
            @(MIN(4, MAX(1, width.integerValue))),
            @(MIN(4, MAX(1, height.integerValue))),
        ];
        if (![sizes[identifiers[(NSUInteger)slot]] isEqual:normalized]) {
            sizes[identifiers[(NSUInteger)slot]] = normalized;
            changed = YES;
        }
    }
    if (!changed) return;
    CFPreferencesSetAppValue(CFSTR("ModuleGridSizes"), (__bridge CFPropertyListRef)sizes, CCBGCCAsterPreferencesDomain);
    CFPreferencesAppSynchronize(CCBGCCAsterPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CCBGCCAsterReloadNotification,
        NULL, NULL, true);
}

static void CCBGApplyPreferenceChangesLocked(NSDictionary<NSString *, id> *values, CFStringRef domain) {
    NSMutableDictionary<NSString *, id> *toSet = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
    [values enumerateKeysAndObjectsUsingBlock:^(id rawKey, id value, BOOL *stop) {
        if (![rawKey isKindOfClass:NSString.class] || ![rawKey length]) return;
        if (value == NSNull.null) [toRemove addObject:rawKey];
        else toSet[rawKey] = value;
    }];
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)toSet, (__bridge CFArrayRef)toRemove,
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(domain);
}

static BOOL CCBGReplacePreferencesAtomically(NSDictionary<NSString *, id> *values, NSDictionary<NSString *, id> *rollback) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    __block BOOL restored = NO;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        CFArrayRef existingKeysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSArray<NSString *> *existingKeys = CFBridgingRelease(existingKeysRef) ?: @[];
        NSMutableArray<NSString *> *toRemove = [existingKeys mutableCopy];
        [toRemove removeObjectsInArray:values.allKeys];
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, (__bridge CFArrayRef)toRemove,
            domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(domain);

        CFArrayRef writtenKeysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSArray *writtenKeys = CFBridgingRelease(writtenKeysRef) ?: @[];
        CFDictionaryRef writtenValuesRef = CFPreferencesCopyMultiple((__bridge CFArrayRef)writtenKeys, domain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSMutableDictionary *writtenValues = [CFBridgingRelease(writtenValuesRef) mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *expectedValues = [values mutableCopy];
        for (NSString *key in [writtenValues.allKeys copy]) if (CCBGConfigurationKeyIsVolatile(key)) [writtenValues removeObjectForKey:key];
        for (NSString *key in [expectedValues.allKeys copy]) if (CCBGConfigurationKeyIsVolatile(key)) [expectedValues removeObjectForKey:key];
        restored = [writtenValues isEqualToDictionary:expectedValues];
        if (restored || !rollback) return;

        NSMutableArray<NSString *> *rollbackRemovals = [writtenKeys mutableCopy];
        [rollbackRemovals removeObjectsInArray:rollback.allKeys];
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)rollback, (__bridge CFArrayRef)rollbackRemovals,
            domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(domain);
    });
    return restored;
}

void CCBGWritePreference(NSString *key, id value) {
    CCBGWritePreferences(key.length ? @{key: value ?: NSNull.null} : @{});
}

void CCBGWritePreferences(NSDictionary<NSString *, id> *values) {
    if (![values isKindOfClass:NSDictionary.class] || !values.count) return;
    __block BOOL valid = YES;
    [values enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || ![key length] ||
            (value != NSNull.null && ![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0])) {
            valid = NO;
            *stop = YES;
        }
    }];
    if (!valid) return;
    CCBGCreateDebouncedAutomaticBackup();
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        CCBGApplyPreferenceChangesLocked(values, domain);
    });
    CCBGInvalidatePreferenceReadCache();
    CCBGSyncCCAsterGridSizeIfPresent(values);
    BOOL sizeOnly = CCBGPreferenceChangesOnlyGridSize(values);
    if (CCBGPreferenceChangesIncludeGridSize(values)) CCBGRequestControlCenterSizeReload();
    // A size-only edit is handled by CCSupport. Rebuilding every video player here
    // causes a visible playback interruption for an otherwise layout-only change.
    if (!sizeOnly) CCBGPostReload();
}

void CCBGWriteMetadataPreference(NSString *key, id value) {
    if (!key.length || (value && ![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0])) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        CCBGApplyPreferenceChangesLocked(@{key: value ?: NSNull.null}, domain);
    });
    CCBGInvalidatePreferenceReadCache();
}

NSArray<NSDictionary<NSString *, id> *> *CCBGQuickConfigurationHistory(void) {
    id stored = CCBGReadPreference(CCBGQuickConfigurationUndoStackKey, @[]);
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *history = [NSMutableArray array];
    for (id value in (NSArray *)stored) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *entry = value;
        if (![entry[@"before"] isKindOfClass:NSDictionary.class] || ![entry[@"missingKeys"] isKindOfClass:NSArray.class]) continue;
        [history addObject:entry];
        if (history.count >= 20) break;
    }
    return history;
}

BOOL CCBGApplyQuickConfigurationChanges(NSDictionary<NSString *, id> *values, NSString *title) {
    if (![values isKindOfClass:NSDictionary.class] || !values.count) return NO;
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    [values enumerateKeysAndObjectsUsingBlock:^(id rawKey, id value, BOOL *stop) {
        if (![rawKey isKindOfClass:NSString.class] || ![rawKey length] || [rawKey isEqualToString:CCBGQuickConfigurationUndoStackKey]) return;
        BOOL valid = value == NSNull.null || [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0];
        if (valid) changes[rawKey] = value;
    }];
    if (!changes.count) return NO;

    NSDictionary *current = CCBGReadAllPreferences();
    NSMutableDictionary *before = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *missingKeys = [NSMutableArray array];
    for (NSString *key in changes) {
        id oldValue = current[key];
        if (oldValue) before[key] = oldValue;
        else [missingKeys addObject:key];
    }
    NSMutableArray *history = [CCBGQuickConfigurationHistory() mutableCopy];
    NSDictionary *entry = @{
        @"id": NSUUID.UUID.UUIDString,
        @"title": title.length ? title : @"快捷修改",
        @"createdAt": @(NSDate.date.timeIntervalSince1970),
        @"before": before,
        @"missingKeys": missingKeys,
        @"changedKeys": changes.allKeys,
    };
    [history insertObject:entry atIndex:0];
    if (history.count > 20) [history removeObjectsInRange:NSMakeRange(20, history.count - 20)];
    changes[CCBGQuickConfigurationUndoStackKey] = history;
    CCBGWritePreferences(changes);
    return YES;
}

BOOL CCBGUndoLastQuickConfiguration(NSString **title) {
    NSMutableArray<NSDictionary<NSString *, id> *> *history = [CCBGQuickConfigurationHistory() mutableCopy];
    NSDictionary *entry = history.firstObject;
    if (!entry) return NO;
    NSDictionary *before = [entry[@"before"] isKindOfClass:NSDictionary.class] ? entry[@"before"] : @{};
    NSArray *missingKeys = [entry[@"missingKeys"] isKindOfClass:NSArray.class] ? entry[@"missingKeys"] : @[];
    NSMutableDictionary<NSString *, id> *changes = [before mutableCopy];
    for (id key in missingKeys) if ([key isKindOfClass:NSString.class] && [key length]) changes[key] = NSNull.null;
    [history removeObjectAtIndex:0];
    changes[CCBGQuickConfigurationUndoStackKey] = history;
    CCBGWritePreferences(changes);
    if (title) *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"快捷修改";
    return YES;
}

void CCBGClearQuickConfigurationHistory(void) {
    CCBGWriteMetadataPreference(CCBGQuickConfigurationUndoStackKey, nil);
}

void CCBGReplaceAllPreferences(NSDictionary<NSString *, id> *values) {
    CCBGRestorePreferencesSnapshot(values, nil);
}

static NSArray<NSString *> *CCBGModuleVisualThemeKeys(void) {
    return @[
        @"moduleCornerRadius", @"moduleInset", @"moduleBorderWidth", @"moduleBorderColor",
        @"moduleMaskDim", @"moduleOpacity", @"moduleBlurIntensity", @"fallbackColor",
        @"expandedAppearanceEnabled", @"expandedCornerRadius", @"expandedOpacity",
        @"expandedBlurIntensity", @"expandedBorderWidth",
        @"foregroundAppTintEnabled", @"wallpaperTintEnabled", @"dynamicTintTarget", @"dynamicTintStrength",
    ];
}

static id CCBGDefaultModuleVisualThemeValue(NSString *key) {
    static NSDictionary<NSString *, id> *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = @{
            @"moduleCornerRadius": @0,
            @"moduleInset": @0,
            @"moduleBorderWidth": @0,
            @"moduleBorderColor": @"#FFFFFF",
            @"moduleMaskDim": @0,
            @"moduleOpacity": @1,
            @"moduleBlurIntensity": @0,
            @"fallbackColor": @"#193D61",
            @"expandedAppearanceEnabled": @NO,
            @"expandedCornerRadius": @0,
            @"expandedOpacity": @1,
            @"expandedBlurIntensity": @0,
            @"expandedBorderWidth": @0,
            @"foregroundAppTintEnabled": @NO,
            @"wallpaperTintEnabled": @NO,
            @"dynamicTintTarget": @0,
            @"dynamicTintStrength": @0.65,
        };
    });
    return defaults[key];
}

static NSArray<NSDictionary<NSString *, id> *> *CCBGSanitizedNamedConfigurations(NSString *preferenceKey) {
    id stored = CCBGReadPreference(preferenceKey, @[]);
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];
    for (id value in (NSArray *)stored) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = value;
        if (![item[@"id"] isKindOfClass:NSString.class] || ![item[@"id"] length] ||
            ![item[@"values"] isKindOfClass:NSDictionary.class]) continue;
        NSString *storedPalette = [item[@"paletteHex"] isKindOfClass:NSString.class] ? item[@"paletteHex"] : @"";
        if ([preferenceKey isEqualToString:@"visualThemes"] && !storedPalette.length) {
            NSMutableDictionary *updated = [item mutableCopy];
            NSDictionary *values = item[@"values"];
            NSArray *catalog = CCBGLoadMediaCatalog();
            NSString *paletteHex = @"";
            for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count && !paletteHex.length; slot++) {
                NSString *mediaName = values[CCBGPreferenceKeyForModule(@"selectedMedia", slot)] ?: values[CCBGPreferenceKeyForModule(@"currentMedia", slot)];
                NSDictionary *mediaItem = CCBGMediaItemNamed(catalog, mediaName);
                paletteHex = [mediaItem[@"dominantColor"] isKindOfClass:NSString.class] ? mediaItem[@"dominantColor"] : @"";
            }
            if (!paletteHex.length) paletteHex = values[CCBGPreferenceKeyForModule(@"fallbackColor", 0)] ?: @"#193D61";
            updated[@"paletteHex"] = paletteHex;
            item = updated;
        }
        [items addObject:item];
    }
    return items;
}

NSArray<NSDictionary<NSString *, id> *> *CCBGVisualThemes(void) {
    return CCBGSanitizedNamedConfigurations(@"visualThemes");
}

NSDictionary<NSString *, id> *CCBGCaptureVisualTheme(NSString *name) {
    NSDictionary<NSString *, id> *preferences = CCBGReadAllPreferences();
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        for (NSString *key in CCBGModuleVisualThemeKeys()) {
            NSString *scopedKey = CCBGPreferenceKeyForModule(key, slot);
            id value = preferences[scopedKey] ?: CCBGDefaultModuleVisualThemeValue(key);
            if (value) values[scopedKey] = value;
        }
        NSString *playbackModeKey = CCBGPreferenceKeyForModule(@"playbackMode", slot);
        NSInteger playbackMode = [preferences[playbackModeKey] respondsToSelector:@selector(integerValue)] ? [preferences[playbackModeKey] integerValue] : 0;
        NSString *mediaPreferenceKey = CCBGPreferenceKeyForModule(CCBGActiveMediaPreferenceKey(playbackMode), slot);
        NSString *mediaName = [preferences[mediaPreferenceKey] isKindOfClass:NSString.class] ? preferences[mediaPreferenceKey] : @"";
        if (mediaName.length) {
            values[CCBGPreferenceKeyForModule(@"selectedMedia", slot)] = mediaName;
            values[CCBGPreferenceKeyForModule(@"currentMedia", slot)] = mediaName;
            values[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
        }
    }
    for (NSString *key in CCBGSystemMediaReferenceKeys()) {
        if (![key containsString:@"Media"]) continue;
        id value = preferences[key];
        if (value) values[key] = value;
    }
    NSArray *catalog = CCBGLoadMediaCatalog();
    NSString *paletteHex = @"";
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count && !paletteHex.length; slot++) {
        NSString *mediaName = values[CCBGPreferenceKeyForModule(@"currentMedia", slot)];
        NSDictionary *paletteItem = CCBGMediaItemNamed(catalog, mediaName);
        paletteHex = [paletteItem[@"dominantColor"] isKindOfClass:NSString.class] ? paletteItem[@"dominantColor"] : @"";
        if (!paletteHex.length && paletteItem) paletteHex = CCBGDominantColorHexForMediaAtPath(CCBGPathForItem(paletteItem));
    }
    if (!paletteHex.length) paletteHex = CCBGReadModulePreference(@"fallbackColor", 0, @"#193D61");
    return @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": name.length ? name : @"未命名主题",
        @"createdAt": @(NSDate.date.timeIntervalSince1970),
        @"enabled": @YES,
        @"pinned": @NO,
        @"randomWeight": @1.0,
        @"paletteHex": paletteHex ?: @"#193D61",
        @"values": values,
    };
}

BOOL CCBGSaveVisualTheme(NSDictionary<NSString *, id> *theme) {
    if (![theme isKindOfClass:NSDictionary.class] || ![theme[@"id"] isKindOfClass:NSString.class] ||
        ![theme[@"id"] length] || ![theme[@"values"] isKindOfClass:NSDictionary.class]) return NO;
    NSMutableArray<NSDictionary<NSString *, id> *> *themes = [CCBGVisualThemes() mutableCopy];
    NSUInteger index = [themes indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
        return [candidate[@"id"] isEqualToString:theme[@"id"]];
    }];
    if (index == NSNotFound) [themes addObject:theme];
    else themes[index] = theme;
    while (themes.count > 30) [themes removeObjectAtIndex:0];
    CCBGWriteMetadataPreference(@"visualThemes", themes);
    return YES;
}

static void CCBGRecordVisualThemeResult(NSString *status, NSString *reason, NSDictionary *theme) {
    CCBGWriteMetadataPreference(@"visualThemeLastResult", @{
        @"status": status ?: @"unknown",
        @"reason": reason ?: @"",
        @"themeID": [theme[@"id"] isKindOfClass:NSString.class] ? theme[@"id"] : @"",
        @"themeName": [theme[@"name"] isKindOfClass:NSString.class] ? theme[@"name"] : @"",
        @"at": @(NSDate.date.timeIntervalSince1970),
    });
}

BOOL CCBGApplyVisualTheme(NSString *themeID) {
    if (!themeID.length) { CCBGRecordVisualThemeResult(@"failed", @"missing-theme-id", nil); return NO; }
    NSDictionary *theme = nil;
    for (NSDictionary *candidate in CCBGVisualThemes()) {
        if ([candidate[@"id"] isEqualToString:themeID]) { theme = candidate; break; }
    }
    NSDictionary *values = [theme[@"values"] isKindOfClass:NSDictionary.class] ? theme[@"values"] : nil;
    if (!values.count) { CCBGRecordVisualThemeResult(@"failed", @"missing-theme", theme); return NO; }
    NSMutableDictionary *changes = [values mutableCopy];
    changes[@"activeVisualThemeID"] = themeID;
    changes[@"visualThemeAppliedAt"] = @(NSDate.date.timeIntervalSince1970);
    changes[@"fiveModulePresentationRecoveryGeneration"] = @(NSDate.date.timeIntervalSince1970);
    BOOL applied = CCBGApplyQuickConfigurationChanges(changes, [NSString stringWithFormat:@"应用主题：%@", theme[@"name"] ?: @"未命名"]);
    if (applied) CCBGPostPresentationRecovery();
    CCBGRecordVisualThemeResult(applied ? @"applied" : @"failed", applied ? @"theme-applied" : @"preference-write-failed", theme);
    return applied;
}

BOOL CCBGApplyRandomVisualTheme(void) {
    NSMutableArray<NSDictionary *> *choices = [NSMutableArray array];
    double totalWeight = 0;
    NSString *activeID = CCBGReadPreference(@"activeVisualThemeID", @"");
    for (NSDictionary *theme in CCBGVisualThemes()) {
        if (![theme[@"enabled"] boolValue] || [theme[@"id"] isEqualToString:activeID]) continue;
        double weight = MIN(10.0, MAX(0.1, [theme[@"randomWeight"] doubleValue]));
        [choices addObject:theme];
        totalWeight += weight;
    }
    if (!choices.count) {
        totalWeight = 0;
        for (NSDictionary *theme in CCBGVisualThemes()) {
            if (![theme[@"enabled"] boolValue]) continue;
            [choices addObject:theme];
            totalWeight += MIN(10.0, MAX(0.1, [theme[@"randomWeight"] doubleValue]));
        }
    }
    if (!choices.count || totalWeight <= 0) { CCBGRecordVisualThemeResult(@"failed", @"no-enabled-theme", nil); return NO; }
    double target = ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * totalWeight;
    NSDictionary *selected = choices.lastObject;
    for (NSDictionary *theme in choices) {
        target -= MIN(10.0, MAX(0.1, [theme[@"randomWeight"] doubleValue]));
        if (target <= 0) { selected = theme; break; }
    }
    return CCBGApplyVisualTheme(selected[@"id"]);
}

NSArray<NSDictionary<NSString *, id> *> *CCBGVisualStylePresets(void) {
    return CCBGSanitizedNamedConfigurations(@"visualStylePresets");
}

NSDictionary<NSString *, id> *CCBGCaptureVisualStylePreset(NSString *name, NSInteger slot) {
    NSDictionary<NSString *, id> *preferences = CCBGReadAllPreferences();
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSString *key in CCBGModuleVisualThemeKeys()) {
        if ([key containsString:@"Media"]) continue;
        NSString *scopedKey = CCBGPreferenceKeyForModule(key, slot);
        id value = preferences[scopedKey] ?: CCBGDefaultModuleVisualThemeValue(key);
        if (value) values[key] = value;
    }
    return @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": name.length ? name : @"未命名外观",
        @"createdAt": @(NSDate.date.timeIntervalSince1970),
        @"values": values,
    };
}

BOOL CCBGSaveVisualStylePreset(NSDictionary<NSString *, id> *preset) {
    if (![preset isKindOfClass:NSDictionary.class] || ![preset[@"id"] isKindOfClass:NSString.class] ||
        ![preset[@"id"] length] || ![preset[@"values"] isKindOfClass:NSDictionary.class]) return NO;
    NSMutableArray<NSDictionary<NSString *, id> *> *presets = [CCBGVisualStylePresets() mutableCopy];
    NSUInteger index = [presets indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
        return [candidate[@"id"] isEqualToString:preset[@"id"]];
    }];
    if (index == NSNotFound) [presets addObject:preset];
    else presets[index] = preset;
    CCBGWriteMetadataPreference(@"visualStylePresets", presets);
    return YES;
}

BOOL CCBGApplyVisualStylePreset(NSString *presetID, NSInteger slot) {
    NSDictionary *preset = nil;
    for (NSDictionary *candidate in CCBGVisualStylePresets()) {
        if ([candidate[@"id"] isEqualToString:presetID]) { preset = candidate; break; }
    }
    NSDictionary *values = [preset[@"values"] isKindOfClass:NSDictionary.class] ? preset[@"values"] : nil;
    if (!values.count) return NO;
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSString *key in values) {
        if ([key isEqualToString:@"selectedMedia"] || [key isEqualToString:@"currentMedia"] || [key isEqualToString:@"playbackMode"]) continue;
        changes[CCBGPreferenceKeyForModule(key, slot)] = values[key];
    }
    return CCBGApplyQuickConfigurationChanges(changes, [NSString stringWithFormat:@"应用外观：%@", preset[@"name"] ?: @"未命名"]);
}

static UIColor *CCBGAverageColorForImage(UIImage *image) {
    if (!image.CGImage) return nil;
    unsigned char pixel[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    return [UIColor colorWithRed:pixel[0] / 255.0 green:pixel[1] / 255.0 blue:pixel[2] / 255.0 alpha:1.0];
}

static UIColor *CCBGAverageColorForView(UIView *view) {
    if (!view || CGRectGetWidth(view.bounds) < 1 || CGRectGetHeight(view.bounds) < 1) return nil;
    unsigned char pixel[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;
    CGContextScaleCTM(context, 1.0 / CGRectGetWidth(view.bounds), 1.0 / CGRectGetHeight(view.bounds));
    [view.layer renderInContext:context];
    CGContextRelease(context);
    return [UIColor colorWithRed:pixel[0] / 255.0 green:pixel[1] / 255.0 blue:pixel[2] / 255.0 alpha:1.0];
}

static id CCBGSharedObjectForClassName(NSString *className) {
    Class cls = objc_getClass(className.UTF8String);
    if (!cls) return nil;
    for (NSString *selectorName in @[@"sharedInstance", @"sharedInstanceIfExists", @"sharedApplication"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([cls respondsToSelector:selector]) return ((id (*)(id, SEL))objc_msgSend)(cls, selector);
    }
    return nil;
}

static NSString *CCBGFrontmostApplicationIdentifier(void) {
    for (NSString *className in @[@"SBMainWorkspace", @"SpringBoard", @"SBApplicationController"]) {
        id workspace = CCBGSharedObjectForClassName(className);
        if (!workspace) continue;
        id application = nil;
        for (NSString *selectorName in @[@"frontmostApplication", @"_accessibilityFrontMostApplication"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([workspace respondsToSelector:selector]) { application = ((id (*)(id, SEL))objc_msgSend)(workspace, selector); break; }
        }
        if (!application) continue;
        for (NSString *selectorName in @[@"bundleIdentifier", @"displayIdentifier"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![application respondsToSelector:selector]) continue;
            NSString *identifier = ((id (*)(id, SEL))objc_msgSend)(application, selector);
            if ([identifier isKindOfClass:NSString.class] && identifier.length) return identifier;
        }
    }
    return @"";
}

static UIColor *CCBGForegroundApplicationPaletteColor(void) {
    static NSString *cachedIdentifier;
    static UIColor *cachedColor;
    static NSTimeInterval cachedAt = 0;
    NSString *identifier = CCBGFrontmostApplicationIdentifier();
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if ([identifier isEqualToString:cachedIdentifier] && now - cachedAt < 5.0) return cachedColor;
    cachedIdentifier = [identifier copy];
    cachedAt = now;
    cachedColor = nil;
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (identifier.length && [UIImage respondsToSelector:selector]) {
        id icon = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(UIImage.class, selector, identifier, 2, UIScreen.mainScreen.scale);
        cachedColor = [icon isKindOfClass:UIImage.class] ? CCBGAverageColorForImage(icon) : nil;
    }
    if (!cachedColor && identifier.length) {
        id applicationController = CCBGSharedObjectForClassName(@"SBApplicationController");
        SEL applicationSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        id application = [applicationController respondsToSelector:applicationSelector]
            ? ((id (*)(id, SEL, id))objc_msgSend)(applicationController, applicationSelector, identifier) : nil;
        for (NSString *selectorName in @[@"iconImage", @"applicationIconImage"]) {
            SEL imageSelector = NSSelectorFromString(selectorName);
            if (![application respondsToSelector:imageSelector]) continue;
            id icon = ((id (*)(id, SEL))objc_msgSend)(application, imageSelector);
            cachedColor = [icon isKindOfClass:UIImage.class] ? CCBGAverageColorForImage(icon) : nil;
            if (cachedColor) break;
        }
        for (NSString *selectorName in @[@"iconImageForVariant:", @"iconImageForFormat:"]) {
            if (cachedColor) break;
            SEL imageSelector = NSSelectorFromString(selectorName);
            if (![application respondsToSelector:imageSelector]) continue;
            for (NSInteger variant = 0; variant < 3 && !cachedColor; variant++) {
                id icon = ((id (*)(id, SEL, NSInteger))objc_msgSend)(application, imageSelector, variant);
                cachedColor = [icon isKindOfClass:UIImage.class] ? CCBGAverageColorForImage(icon) : nil;
            }
        }
    }
    return cachedColor;
}

static UIView *CCBGWallpaperViewInHierarchy(UIView *view, NSUInteger depth) {
    if (!view || depth > 5) return nil;
    if ([NSStringFromClass(view.class) localizedCaseInsensitiveContainsString:@"wallpaper"]) return view;
    for (UIView *subview in view.subviews) {
        UIView *match = CCBGWallpaperViewInHierarchy(subview, depth + 1);
        if (match) return match;
    }
    return nil;
}

static UIColor *CCBGWallpaperPaletteColor(UIView *view) {
    static UIColor *cachedColor;
    static NSTimeInterval cachedAt = 0;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (cachedColor && cachedAt > 0 && now - cachedAt < 8.0) return cachedColor;
    for (NSString *className in @[@"SBWallpaperController", @"SBFWallpaperController"]) {
        id controller = CCBGSharedObjectForClassName(className);
        for (NSString *selectorName in @[@"wallpaperImage", @"_wallpaperImage", @"wallpaperView", @"_wallpaperView"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![controller respondsToSelector:selector]) continue;
            id object = ((id (*)(id, SEL))objc_msgSend)(controller, selector);
            cachedColor = [object isKindOfClass:UIImage.class] ? CCBGAverageColorForImage(object) : [object isKindOfClass:UIView.class] ? CCBGAverageColorForView(object) : nil;
            if (cachedColor) { cachedAt = now; return cachedColor; }
        }
        for (NSString *selectorName in @[@"wallpaperViewForVariant:", @"_wallpaperViewForVariant:", @"wallpaperImageForVariant:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![controller respondsToSelector:selector]) continue;
            for (NSInteger variant = 0; variant < 3; variant++) {
                id object = ((id (*)(id, SEL, NSInteger))objc_msgSend)(controller, selector, variant);
                cachedColor = [object isKindOfClass:UIImage.class] ? CCBGAverageColorForImage(object) : [object isKindOfClass:UIView.class] ? CCBGAverageColorForView(object) : nil;
                if (cachedColor) { cachedAt = now; return cachedColor; }
            }
        }
    }
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha < 0.01) continue;
        UIView *wallpaperView = CCBGWallpaperViewInHierarchy(window, 0);
        if (!wallpaperView) continue;
        cachedColor = CCBGAverageColorForView(wallpaperView);
        if (cachedColor) { cachedAt = now; return cachedColor; }
    }
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        UIView *wallpaperView = CCBGWallpaperViewInHierarchy(candidate, 0);
        if (!wallpaperView) continue;
        cachedColor = CCBGAverageColorForView(wallpaperView);
        if (cachedColor) { cachedAt = now; return cachedColor; }
    }
    return cachedColor;
}

static UIColor *CCBGBlendPaletteColors(UIColor *left, UIColor *right) {
    if (!left) return right;
    if (!right) return left;
    CGFloat lr = 0, lg = 0, lb = 0, la = 0, rr = 0, rg = 0, rb = 0, ra = 0;
    if (![left getRed:&lr green:&lg blue:&lb alpha:&la] || ![right getRed:&rr green:&rg blue:&rb alpha:&ra]) return left;
    return [UIColor colorWithRed:(lr + rr) * 0.5 green:(lg + rg) * 0.5 blue:(lb + rb) * 0.5 alpha:1.0];
}

UIColor *CCBGResolvedDynamicPaletteColor(UIView *view, BOOL useForegroundApp, BOOL useWallpaper) {
    UIColor *applicationColor = useForegroundApp ? CCBGForegroundApplicationPaletteColor() : nil;
    UIColor *wallpaperColor = useWallpaper ? CCBGWallpaperPaletteColor(view) : nil;
    return CCBGBlendPaletteColors(applicationColor, wallpaperColor);
}

BOOL CCBGApplyVisualThemeAutomationIfNeeded(UIView *view) {
    (void)view;
    if (![CCBGReadPreference(@"visualThemeRandomOnOpen", @NO) boolValue]) return NO;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval lastClaim = [CCBGReadPreference(@"visualThemeAutomationLastClaimAt", @0) doubleValue];
    if (now - lastClaim < 0.75) return NO;
    CCBGWriteMetadataPreference(@"visualThemeAutomationLastClaimAt", @(now));
    return CCBGApplyRandomVisualTheme();
}

BOOL CCBGRestorePreferencesSnapshot(NSDictionary<NSString *, id> *values, NSError **error) {
    if (![values isKindOfClass:NSDictionary.class] ||
        ![NSPropertyListSerialization propertyList:values isValidForFormat:NSPropertyListBinaryFormat_v1_0]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.configuration" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"配置快照格式无效。"}];
        return NO;
    }
    NSDictionary<NSString *, id> *rollback = CCBGReadAllPreferences();
    CCBGCreateDebouncedAutomaticBackup();
    if (!CCBGReplacePreferencesAtomically(values, rollback)) {
        if (error) *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.configuration" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"配置写入校验失败，已经恢复写入前状态。"}];
        return NO;
    }
    CCBGInvalidatePreferenceReadCache();
    CCBGSyncCCAsterGridSizeIfPresent(values);
    CCBGInvalidateSceneRuntimeCaches();
    CCBGRequestControlCenterSizeReload();
    CCBGPostReload();
    CCBGPostPresentationRecovery();
    return YES;
}

BOOL CCBGClearAllConfigurationPreservingMedia(NSError **error) {
    NSDictionary<NSString *, id> *rollback = CCBGReadAllPreferences();
    if (!CCBGReplacePreferencesAtomically(@{}, rollback)) {
        if (error) *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.configuration" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"无法清除偏好域，原配置已保留。"}];
        return NO;
    }
    CCBGInvalidatePreferenceReadCache();

    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *path in @[
        @"/var/mobile/Library/CleanCCBG2x2/Backups",
        @"/var/mobile/Library/CleanCCBG2x2/Thumbnails",
        @"/var/mobile/Library/CleanCCBG2x2/OverlayFrames",
        @"/var/mobile/Library/CleanCCBG2x2/VideoOnlyCache",
        CCBGModuleLifecycleTracePath,
    ]) {
        [manager removeItemAtPath:path error:nil];
    }
    CCBGInvalidateSceneRuntimeCaches();
    CCBGRequestControlCenterSizeReload();
    CCBGPostReload();
    CCBGPostPresentationRecovery();
    return YES;
}

void CCBGPostReload(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CCBGReloadNotificationName,
        NULL,
        NULL,
        true
    );
}

void CCBGRequestControlCenterSizeReload(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CCBGSizeReloadNotificationName, NULL, NULL, true);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.opa334.ccsupport/ReloadSizes"), NULL, NULL, true);
}

NSArray<NSString *> *CCBGModuleDisplayNames(void) {
    return @[@"2x2", @"1x2", @"2x3", @"3x2", @"3x3"];
}

NSString *CCBGPreferenceKeyForModule(NSString *key, NSInteger slot) {
    return slot <= 0 ? key : [NSString stringWithFormat:@"%@.module%ld", key, (long)slot];
}

id CCBGReadModulePreference(NSString *key, NSInteger slot, id fallback) {
    return CCBGReadPreference(CCBGPreferenceKeyForModule(key, slot), fallback);
}

void CCBGWriteModulePreference(NSString *key, NSInteger slot, id value) {
    CCBGWritePreference(CCBGPreferenceKeyForModule(key, slot), value);
}

void CCBGWriteModulePreferences(NSDictionary<NSString *, id> *values, NSInteger slot) {
    if (![values isKindOfClass:NSDictionary.class] || !values.count) return;
    NSMutableDictionary<NSString *, id> *scopedValues = [NSMutableDictionary dictionaryWithCapacity:values.count];
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (key.length) scopedValues[CCBGPreferenceKeyForModule(key, slot)] = value;
    }];
    CCBGWritePreferences(scopedValues);
}

NSString *CCBGActiveMediaPreferenceKey(NSInteger playbackMode) {
    return playbackMode == 0 ? @"selectedMedia" : @"currentMedia";
}

NSString *CCBGActiveModuleMediaName(NSInteger slot) {
    NSInteger playbackMode = [CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue];
    return CCBGReadModulePreference(CCBGActiveMediaPreferenceKey(playbackMode), slot, @"");
}

void CCBGSelectModuleMedia(NSString *fileName, NSInteger slot, BOOL makeConstant) {
    if (!fileName.length) return;
    NSMutableDictionary<NSString *, id> *values = [@{@"currentMedia": fileName} mutableCopy];
    if (makeConstant) {
        values[@"playbackMode"] = @0;
        values[@"selectedMedia"] = fileName;
    }
    CCBGWriteModulePreferences(values, slot);
}

BOOL CCBGFiveModuleDefaultsReady(void) {
    NSArray<NSDictionary *> *catalog = CCBGLoadMediaCatalog();
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        NSString *fileName = CCBGReadModulePreference(@"defaultOverrideMedia", slot, @"");
        if (!fileName.length || !CCBGMediaItemNamed(catalog, fileName)) return NO;
    }
    return YES;
}

BOOL CCBGApplyFiveModuleDefaultMedia(void) {
    BOOL ready = CCBGFiveModuleDefaultsReady();
    if (!ready) {
        CCBGRecordModuleLifecycleEvent(-1, @"defaults-apply-rejected", @{@"ready": @NO});
        return NO;
    }
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    id existingSnapshot = CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil);
    if (![existingSnapshot isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            snapshot[[NSString stringWithFormat:@"%ld", (long)slot]] = @{
                @"playbackMode": CCBGReadModulePreference(@"playbackMode", slot, @0),
                @"selectedMedia": CCBGReadModulePreference(@"selectedMedia", slot, @""),
                @"currentMedia": CCBGReadModulePreference(@"currentMedia", slot, @""),
            };
        }
        changes[@"fiveModuleDefaultRestoreSnapshot"] = snapshot;
    }
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        NSString *fileName = CCBGReadModulePreference(@"defaultOverrideMedia", slot, @"");
        changes[CCBGPreferenceKeyForModule(@"playbackMode", slot)] = @0;
        changes[CCBGPreferenceKeyForModule(@"selectedMedia", slot)] = fileName;
        changes[CCBGPreferenceKeyForModule(@"currentMedia", slot)] = fileName;
        changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
    }
    changes[@"fiveModuleDefaultActive"] = @YES;
    changes[@"fiveModulePresentationRecoveryGeneration"] = @(NSDate.date.timeIntervalSince1970);
    CCBGWritePreferences(changes);
    BOOL snapshotStored = [CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil) isKindOfClass:NSDictionary.class];
    CCBGRecordModuleLifecycleEvent(-1, @"defaults-apply-finished", @{@"snapshotStored": @(snapshotStored)});
    return snapshotStored;
}

void CCBGPostPresentationRecovery(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)CCBGPresentationRecoveryNotificationName,
        NULL,
        NULL,
        true
    );
}

BOOL CCBGRestoreFiveModuleMedia(void) {
    id stored = CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil);
    if (![stored isKindOfClass:NSDictionary.class]) {
        CCBGRecordModuleLifecycleEvent(-1, @"defaults-restore-rejected", @{@"hasSnapshot": @NO});
        return NO;
    }
    NSDictionary *snapshot = stored;
    NSMutableDictionary<NSString *, id> *changes = [@{
        @"fiveModuleDefaultRestoreSnapshot": NSNull.null,
        @"fiveModuleDefaultActive": NSNull.null,
        @"fiveModulePresentationRecoveryGeneration": @(NSDate.date.timeIntervalSince1970),
    } mutableCopy];
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        NSDictionary *state = snapshot[[NSString stringWithFormat:@"%ld", (long)slot]];
        if (![state isKindOfClass:NSDictionary.class]) continue;
        for (NSString *key in @[@"playbackMode", @"selectedMedia", @"currentMedia"]) {
            changes[CCBGPreferenceKeyForModule(key, slot)] = state[key] ?: NSNull.null;
        }
        changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
    }
    CCBGWritePreferences(changes);
    BOOL snapshotCleared = ![CCBGReadPreference(@"fiveModuleDefaultRestoreSnapshot", nil) isKindOfClass:NSDictionary.class];
    CCBGRecordModuleLifecycleEvent(-1, @"defaults-restore-finished", @{@"snapshotCleared": @(snapshotCleared)});
    return snapshotCleared;
}

NSInteger CCBGActiveModuleSlot(void) {
    NSInteger slot = [CCBGReadPreference(@"activeModuleSlot", @0) integerValue];
    return MIN((NSInteger)CCBGModuleDisplayNames().count - 1, MAX(0, slot));
}

NSArray<NSString *> *CCBGModuleConfigurationKeys(void) {
    return @[
        @"selectedMedia", @"gridWidth", @"gridHeight", @"controlCenterResizeEnabled", @"playbackMode", @"slideshowEnabled", @"slideshowInterval",
        @"rememberLast", @"randomOnOpen", @"crossfadeDuration", @"blurEnabled", @"moduleOpacity", @"moduleBlurIntensity",
        @"favoritesOnly", @"chargingOnlyVideo", @"lowPowerStatic", @"fallbackColor",
        @"showExpandedCaption", @"hapticFeedbackEnabled",
        @"compactSingleTapAction", @"compactDoubleTapAction", @"compactTripleTapAction", @"compactLongPressAction",
        @"expandedSingleTapAction", @"expandedDoubleTapAction", @"expandedTripleTapAction", @"expandedLongPressAction",
        @"scheduleEnabled", @"dayStartMinutes", @"dayMedia", @"nightStartMinutes", @"nightMedia",
        @"darkModeAutomationEnabled", @"lightModeMedia", @"darkModeMedia",
        @"weekdayAutomationEnabled", @"weekdayMedia", @"weekendMedia",
        @"lowPowerAutomationEnabled", @"lowPowerMedia", @"chargingAutomationEnabled", @"chargingMedia",
        @"mediaOverrides", @"playlist", @"playlistLoop", @"noRepeatCount", @"recentMedia",
        @"playbackHistory", @"transitionStyle", @"preloadEnabled", @"performanceMode",
        @"moduleCornerRadius", @"moduleInset", @"moduleBorderWidth", @"moduleBorderColor", @"moduleMaskDim",
        @"expandedAppearanceEnabled", @"expandedCornerRadius", @"expandedOpacity", @"expandedBlurIntensity", @"expandedBorderWidth",
        @"expandedDisplayMode", @"fallbackMediaChains",
        @"foregroundAppTintEnabled", @"wallpaperTintEnabled", @"dynamicTintTarget", @"dynamicTintStrength",
        @"adaptiveExpandedSizeEnabled", @"expandedWidth", @"expandedHeight",
        @"privacyEnabled", @"privacyMedia", @"privacyBlur", @"privacyPauseVideo",
        @"portraitMedia", @"landscapeMedia", @"defaultOverrideMedia", @"scheduledPlaylists", @"compoundRules", @"activeProfile",
    ];
}

void CCBGCopyModuleConfiguration(NSInteger sourceSlot, NSInteger destinationSlot) {
    if (sourceSlot == destinationSlot) return;
    NSDictionary<NSString *, id> *preferences = CCBGReadAllPreferences();
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    for (NSString *key in CCBGModuleConfigurationKeys()) {
        NSString *sourceKey = CCBGPreferenceKeyForModule(key, sourceSlot);
        NSString *destinationKey = CCBGPreferenceKeyForModule(key, destinationSlot);
        changes[destinationKey] = preferences[sourceKey] ?: NSNull.null;
    }
    changes[CCBGPreferenceKeyForModule(@"currentMedia", destinationSlot)] = NSNull.null;
    CCBGWritePreferences(changes);
}

void CCBGResetModuleConfiguration(NSInteger slot) {
    NSMutableDictionary<NSString *, id> *changes = [NSMutableDictionary dictionary];
    for (NSString *key in CCBGModuleConfigurationKeys()) {
        changes[CCBGPreferenceKeyForModule(key, slot)] = NSNull.null;
    }
    changes[CCBGPreferenceKeyForModule(@"currentMedia", slot)] = NSNull.null;
    CCBGWritePreferences(changes);
}

void CCBGMigrateLegacyAutomationPreferences(void) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
    if ([CCBGReadPreference(@"moduleAutomationMigrationVersion", @0) integerValue] < 2) {
        NSArray<NSString *> *keys = @[
            @"scheduleEnabled", @"dayStartMinutes", @"dayMedia", @"nightStartMinutes", @"nightMedia",
            @"darkModeAutomationEnabled", @"lightModeMedia", @"darkModeMedia",
            @"weekdayAutomationEnabled", @"weekdayMedia", @"weekendMedia",
            @"lowPowerAutomationEnabled", @"lowPowerMedia", @"chargingAutomationEnabled", @"chargingMedia",
            @"fallbackColor",
        ];
        for (NSString *key in keys) {
            CFPropertyListRef legacyRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
            id legacyValue = CFBridgingRelease(legacyRef);
            if (!legacyValue) continue;
            for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
                NSString *moduleKey = CCBGPreferenceKeyForModule(key, slot);
                CFPropertyListRef currentRef = CFPreferencesCopyAppValue((__bridge CFStringRef)moduleKey, domain);
                id currentValue = CFBridgingRelease(currentRef);
                if (!currentValue) CFPreferencesSetAppValue((__bridge CFStringRef)moduleKey, (__bridge CFPropertyListRef)legacyValue, domain);
            }
        }
        CFPreferencesSetAppValue(CFSTR("moduleAutomationMigrationVersion"), (__bridge CFPropertyListRef)@2, domain);
    }

    if ([CCBGReadPreference(@"moduleMediaConfigurationMigrationVersion", @0) integerValue] < 1) {
        id storedValue = CCBGReadPreference(@"mediaCatalog", @[]);
        NSArray *stored = [storedValue isKindOfClass:NSArray.class] ? storedValue : @[];
        NSMutableArray *sanitizedCatalog = [NSMutableArray array];
        NSMutableArray<NSMutableDictionary *> *overridesBySlot = [NSMutableArray array];
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            NSDictionary *existing = CCBGReadModulePreference(@"mediaOverrides", slot, @{});
            [overridesBySlot addObject:[existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary]];
        }
        for (id candidate in stored) {
            if (![candidate isKindOfClass:NSDictionary.class]) continue;
            NSString *fileName = candidate[@"fileName"];
            if (![fileName isKindOfClass:NSString.class] || !fileName.length) continue;
            NSMutableDictionary *configuration = [CCBGDefaultMediaConfiguration() mutableCopy];
            for (NSString *key in CCBGModuleMediaConfigurationKeys()) {
                if (candidate[key]) configuration[key] = candidate[key];
            }
            for (NSMutableDictionary *overrides in overridesBySlot) {
                if (!overrides[fileName]) overrides[fileName] = configuration;
            }
            NSMutableDictionary *sharedItem = [candidate mutableCopy];
            [sharedItem removeObjectsForKeys:CCBGModuleMediaConfigurationKeys()];
            [sanitizedCatalog addObject:sharedItem];
        }
        for (NSInteger slot = 0; slot < (NSInteger)overridesBySlot.count; slot++) {
            NSString *key = CCBGPreferenceKeyForModule(@"mediaOverrides", slot);
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFDictionaryRef)overridesBySlot[(NSUInteger)slot], domain);
        }
        CFPreferencesSetAppValue(CFSTR("mediaCatalog"), (__bridge CFArrayRef)sanitizedCatalog, domain);
        CFPreferencesSetAppValue(CFSTR("moduleMediaConfigurationMigrationVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    if ([CCBGReadPreference(@"systemOverlayMediaMigrationVersion", @0) integerValue] < 1) {
        NSDictionary<NSString *, NSArray<NSString *> *> *migrations = @{
            @"connectivityOverlayMedia": @[@"connectivityOverlayCompactMedia", @"connectivityOverlayExpandedMedia"],
            @"musicOverlayMedia": @[@"musicOverlayCompactMedia", @"musicOverlayExpandedMedia"],
        };
        [migrations enumerateKeysAndObjectsUsingBlock:^(NSString *legacyKey, NSArray<NSString *> *stateKeys, BOOL *stop) {
            CFPropertyListRef legacyRef = CFPreferencesCopyAppValue((__bridge CFStringRef)legacyKey, domain);
            id legacyValue = CFBridgingRelease(legacyRef);
            if (![legacyValue isKindOfClass:NSString.class] || ![legacyValue length]) return;
            for (NSString *stateKey in stateKeys) {
                CFPropertyListRef currentRef = CFPreferencesCopyAppValue((__bridge CFStringRef)stateKey, domain);
                id currentValue = CFBridgingRelease(currentRef);
                if (!currentValue) CFPreferencesSetAppValue((__bridge CFStringRef)stateKey, (__bridge CFStringRef)legacyValue, domain);
            }
        }];
        CFPreferencesSetAppValue(CFSTR("systemOverlayMediaMigrationVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    if ([CCBGReadPreference(@"systemOverlayPlaybackMigrationVersion", @0) integerValue] < 1) {
        NSString *compactMusic = CCBGReadPreference(@"musicOverlayCompactMedia", @"");
        NSString *expandedMusic = CCBGReadPreference(@"musicOverlayExpandedMedia", @"");
        if (CCBGIsVideoName(compactMusic) || CCBGIsVideoName(expandedMusic)) {
            CFPreferencesSetAppValue(CFSTR("musicOverlayEnabled"), (__bridge CFPropertyListRef)@YES, domain);
            CFPreferencesSetAppValue(CFSTR("musicOverlayVideo"), (__bridge CFPropertyListRef)@YES, domain);
        }
        CFPreferencesSetAppValue(CFSTR("systemOverlayPlaybackMigrationVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    if ([CCBGReadPreference(@"systemOverlayIndependentModeMigrationVersion", @0) integerValue] < 1) {
        for (NSString *prefix in @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"]) {
            for (NSString *presentation in @[@"Compact", @"Expanded"]) {
                NSString *legacyKey = [NSString stringWithFormat:@"%@%@CurrentMedia", prefix, presentation];
                NSString *legacyValue = CCBGReadPreference(legacyKey, @"");
                if (![legacyValue isKindOfClass:NSString.class] || !legacyValue.length) continue;
                for (NSString *mode in @[@"Sequential", @"Random"]) {
                    NSString *stateKey = [NSString stringWithFormat:@"%@%@%@CurrentMedia", prefix, presentation, mode];
                    if (![CCBGReadPreference(stateKey, @"") length]) {
                        CFPreferencesSetAppValue((__bridge CFStringRef)stateKey, (__bridge CFStringRef)legacyValue, domain);
                    }
                }
            }
        }
        CFPreferencesSetAppValue(CFSTR("systemOverlayIndependentModeMigrationVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    if ([CCBGReadPreference(@"sliderCompactFailureRepairVersion", @0) integerValue] < 1) {
        for (NSString *prefix in @[@"brightnessOverlay", @"volumeOverlay"]) {
            NSString *fixedName = CCBGReadPreference([prefix stringByAppendingString:@"CompactMedia"], @"");
            NSInteger mode = [CCBGReadPreference([prefix stringByAppendingString:@"CompactPlaybackMode"], @0) integerValue];
            if ([fixedName isKindOfClass:NSString.class] && fixedName.length && mode != 0) {
                NSString *modeName = mode == 2 ? @"Random" : @"Sequential";
                NSString *currentKey = [prefix stringByAppendingFormat:@"Compact%@CurrentMedia", modeName];
                CFPreferencesSetAppValue((__bridge CFStringRef)currentKey, (__bridge CFStringRef)fixedName, domain);
            }
            CFPreferencesSetAppValue((__bridge CFStringRef)[prefix stringByAppendingString:@"FailureCounts"], (__bridge CFDictionaryRef)@{}, domain);
        }
        CFPreferencesSetAppValue(CFSTR("sliderCompactFailureRepairVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    if ([CCBGReadPreference(@"visualThemeAutomationCleanupVersion", @0) integerValue] < 1) {
        CFPreferencesSetAppValue(CFSTR("visualThemeWallpaperSyncEnabled"), NULL, domain);
        CFPreferencesSetAppValue(CFSTR("visualThemeLastWallpaperHex"), NULL, domain);
        CFPreferencesSetAppValue(CFSTR("visualThemeAutomationSuppressedUntil"), NULL, domain);
        CFPreferencesSetAppValue(CFSTR("visualThemeAutomationCleanupVersion"), (__bridge CFPropertyListRef)@1, domain);
    }
    CFPreferencesAppSynchronize(domain);
    });
    // Migration reads can populate the App-only snapshot before direct CFPreferences
    // writes complete. Drop it so the first visible settings page sees migrated values.
    CCBGInvalidatePreferenceReadCache();
}

static NSDictionary<NSString *, id> *CCBGDarkAppearanceLastDiagnostics;
static BOOL CCBGDarkAppearanceCachedValue;
static BOOL CCBGDarkAppearanceHasCachedValue;

static NSObject *CCBGDarkAppearanceLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL CCBGParseDarkAppearanceValue(id value, BOOL *dark) {
    if ([value isKindOfClass:NSString.class]) {
        NSString *style = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([style caseInsensitiveCompare:@"Dark"] == NSOrderedSame) { if (dark) *dark = YES; return YES; }
        if ([style caseInsensitiveCompare:@"Light"] == NSOrderedSame) { if (dark) *dark = NO; return YES; }
    }
    if ([value isKindOfClass:NSNumber.class]) {
        NSInteger style = [value integerValue];
        if (style == UIUserInterfaceStyleDark || style == UIUserInterfaceStyleLight) {
            if (dark) *dark = style == UIUserInterfaceStyleDark;
            return YES;
        }
    }
    return NO;
}

static BOOL CCBGResolveDarkAppearance(NSString **resolvedSource, NSDictionary **resolvedCandidates) {
    NSMutableDictionary<NSString *, id> *candidates = [NSMutableDictionary dictionary];
    BOOL dark = NO;
    NSString *source = @"fallback-light";
    BOOL resolved = NO;

    // The Control Center module view can carry a locally forced light trait.
    // UIScreen and the current system trait remain process-wide on iOS 16.
    if ([NSThread isMainThread]) {
        UIUserInterfaceStyle screenStyle = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        candidates[@"mainScreenTrait"] = @(screenStyle);
        if (screenStyle == UIUserInterfaceStyleDark || screenStyle == UIUserInterfaceStyleLight) {
            dark = screenStyle == UIUserInterfaceStyleDark;
            source = @"main-screen-trait";
            resolved = YES;
        }
        UIUserInterfaceStyle currentStyle = UITraitCollection.currentTraitCollection.userInterfaceStyle;
        candidates[@"currentTrait"] = @(currentStyle);
        if (!resolved && (currentStyle == UIUserInterfaceStyleDark || currentStyle == UIUserInterfaceStyleLight)) {
            dark = currentStyle == UIUserInterfaceStyleDark;
            source = @"current-trait";
            resolved = YES;
        }
    }

    if (!resolved) {
        CFStringRef globalDomain = CFSTR(".GlobalPreferences");
        CFPreferencesSynchronize(globalDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
        CFPreferencesSynchronize(globalDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef rawGlobalValue = CFPreferencesCopyValue(CFSTR("AppleInterfaceStyle"), globalDomain,
                                                                  kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
        if (!rawGlobalValue) rawGlobalValue = CFPreferencesCopyValue(CFSTR("AppleInterfaceStyle"), globalDomain,
                                                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (!rawGlobalValue) rawGlobalValue = CFPreferencesCopyValue(CFSTR("AppleInterfaceStyle"), kCFPreferencesAnyApplication,
                                                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id globalValue = CFBridgingRelease(rawGlobalValue);
        candidates[@"globalPreference"] = globalValue ?: @"missing";
        BOOL globalDark = NO;
        if (CCBGParseDarkAppearanceValue(globalValue, &globalDark)) {
            dark = globalDark;
            source = @"global-preference";
            resolved = YES;
        }
    } else {
        candidates[@"globalPreference"] = @"skipped";
    }

    if (!resolved) {
        NSDictionary *globalPlist = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/.GlobalPreferences.plist"];
        id plistValue = globalPlist[@"AppleInterfaceStyle"];
        candidates[@"globalPlist"] = plistValue ?: @"missing";
        BOOL plistDark = NO;
        if (CCBGParseDarkAppearanceValue(plistValue, &plistDark)) {
            dark = plistDark;
            source = @"global-plist";
            resolved = YES;
        }
    } else {
        candidates[@"globalPlist"] = @"skipped";
    }

    @synchronized (CCBGDarkAppearanceLock()) {
        if (!resolved && CCBGDarkAppearanceHasCachedValue) {
            dark = CCBGDarkAppearanceCachedValue;
            source = @"process-cache";
            resolved = YES;
        }
    }
    NSDictionary *lastContext = CCBGReadPreference(@"sceneDirectorLastRuntimeContext", @{});
    id persistedDark = [lastContext isKindOfClass:NSDictionary.class] ? lastContext[@"dark"] : nil;
    candidates[@"persistedRuntime"] = persistedDark ?: @"missing";
    if (!resolved && [persistedDark respondsToSelector:@selector(boolValue)]) {
        dark = [persistedDark boolValue];
        source = @"persisted-runtime";
        resolved = YES;
    }

    NSDictionary *diagnostics = @{
        @"dark": @(dark),
        @"source": source,
        @"resolved": @(resolved),
        @"mainThread": @([NSThread isMainThread]),
        @"process": NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName ?: @"unknown",
        @"candidates": candidates,
    };
    @synchronized (CCBGDarkAppearanceLock()) {
        if (resolved) {
            CCBGDarkAppearanceCachedValue = dark;
            CCBGDarkAppearanceHasCachedValue = YES;
        }
        CCBGDarkAppearanceLastDiagnostics = diagnostics;
    }
    if (resolvedSource) *resolvedSource = source;
    if (resolvedCandidates) *resolvedCandidates = candidates;
    return dark;
}

BOOL CCBGSystemUsesDarkAppearance(void) {
    return CCBGResolveDarkAppearance(NULL, NULL);
}

NSDictionary<NSString *, id> *CCBGDarkAppearanceDiagnostics(void) {
    CCBGSystemUsesDarkAppearance();
    @synchronized (CCBGDarkAppearanceLock()) {
        return [CCBGDarkAppearanceLastDiagnostics copy] ?: @{};
    }
}

static NSString *CCBGNormalizedSceneText(id value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.precomposedStringWithCanonicalMapping.lowercaseString;
}

static void CCBGCollectFocusAliases(id object, NSMutableOrderedSet<NSString *> *aliases, NSUInteger depth) {
    if (!object || depth > 8) return;
    if ([object isKindOfClass:NSString.class]) {
        NSString *value = [(NSString *)object stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length) [aliases addObject:value];
        return;
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class] || [object isKindOfClass:NSOrderedSet.class]) {
        for (id value in object) CCBGCollectFocusAliases(value, aliases, depth + 1);
        return;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = object;
        for (NSString *key in @[@"activityDisplayName", @"displayName", @"localizedName", @"name", @"title", @"userVisibleString", @"activityIdentifier", @"activityUniqueIdentifier", @"identifier", @"modeIdentifier", @"configurationIdentifier", @"activeModeConfigurationIdentifier", @"dndMode", @"configuration", @"modeConfiguration", @"activeModeConfiguration", @"mode", @"focusMode"]) {
            CCBGCollectFocusAliases(dictionary[key], aliases, depth + 1);
        }
        return;
    }
    for (NSString *selectorName in @[@"activityDisplayName", @"displayName", @"localizedName", @"name", @"title", @"userVisibleString", @"activityIdentifier", @"activityUniqueIdentifier", @"identifier", @"modeIdentifier", @"configurationIdentifier", @"activeModeConfigurationIdentifier", @"dndMode", @"configuration", @"modeConfiguration", @"activeModeConfiguration", @"mode", @"focusMode"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:selector]) {
            id value = nil;
            @try {
                value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            } @catch (__unused NSException *exception) {
                continue;
            }
            CCBGCollectFocusAliases(value, aliases, depth + 1);
        }
    }
}

static BOOL CCBGEnsureFocusFrameworkLoaded(void) {
    static BOOL loaded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = @[
            @"/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb",
            @"/System/Library/PrivateFrameworks/Focus.framework/Focus",
        ];
        for (NSString *path in paths) {
            if (dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL)) loaded = YES;
        }
    });
    return loaded || NSClassFromString(@"DNDStateService") || NSClassFromString(@"DNDModeConfigurationService");
}

static NSArray<NSString *> *CCBGAvailableFocusServiceClassNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *className in @[@"DNDStateService", @"DNDModeConfigurationService"]) {
        if (NSClassFromString(className)) [names addObject:className];
    }
    return names;
}

static id CCBGFocusActivityManager(void) {
    CCBGEnsureFocusFrameworkLoaded();
    Class managerClass = NSClassFromString(@"FCActivityManager");
    if (!managerClass) return nil;
    SEL selector = NSSelectorFromString(@"sharedActivityManager");
    if (![managerClass respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(managerClass, selector);
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static id CCBGFocusActivityManagerValue(id manager, NSString *selectorName, NSString **exceptionText) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!manager || ![manager respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    } @catch (NSException *exception) {
        if (exceptionText) *exceptionText = exception.reason ?: exception.name ?: @"exception";
        return nil;
    }
}

static id CCBGFocusActivitiesFromManager(id manager, NSString **exceptionText) {
    return CCBGFocusActivityManagerValue(manager, @"availableActivities", exceptionText);
}

static NSArray<NSString *> *CCBGFocusAliasesFromActivityManager(id manager) {
    NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
    CCBGCollectFocusAliases(CCBGFocusActivityManagerValue(manager, @"activeActivity", NULL), aliases, 0);
    return aliases.array;
}

static BOOL CCBGFocusActivityManagerHasAuthoritativeState(id manager) {
    if (!manager) return NO;
    if (CCBGFocusActivityManagerValue(manager, @"activeActivity", NULL)) return YES;
    id availableActivities = CCBGFocusActivitiesFromManager(manager, NULL);
    return [availableActivities respondsToSelector:@selector(count)] && [availableActivities count] > 0;
}

static void (^CCBGFocusActivityChangeHandler)(void);
static id CCBGFocusActivityObserverInstance;

static void CCBGDeliverFocusActivityChange(void) {
    void (^handler)(void) = CCBGFocusActivityChangeHandler;
    if (!handler) return;
    if ([NSThread isMainThread]) handler();
    else dispatch_async(dispatch_get_main_queue(), handler);
}

@interface CCBGFocusActivityObserver : NSObject
@end

@implementation CCBGFocusActivityObserver
- (void)activeActivityDidChangeForManager:(id)manager { CCBGDeliverFocusActivityChange(); }
- (void)activeModeDidChangeForManager:(id)manager { CCBGDeliverFocusActivityChange(); }
- (void)availableActivitiesDidChangeForManager:(id)manager { CCBGDeliverFocusActivityChange(); }
@end

void CCBGObserveFocusActivityChanges(void (^handler)(void)) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ CCBGObserveFocusActivityChanges(handler); });
        return;
    }
    if (!CCBGFocusActivityChangeHandler) CCBGFocusActivityChangeHandler = [handler copy];
    if (CCBGFocusActivityObserverInstance) return;
    id manager = CCBGFocusActivityManager();
    SEL selector = NSSelectorFromString(@"addObserver:");
    if (!manager || ![manager respondsToSelector:selector]) return;
    id observer = [CCBGFocusActivityObserver new];
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(manager, selector, observer);
        CCBGFocusActivityObserverInstance = observer;
    } @catch (__unused NSException *exception) {
    }
}

static NSString *CCBGFocusDiscoveryProcessKey(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return [bundleIdentifier isEqualToString:@"com.apple.springboard"]
        ? @"sceneDirectorFocusDiscoverySpringBoard"
        : @"sceneDirectorFocusDiscoveryApp";
}

static NSArray<NSDictionary<NSString *, id> *> *CCBGFocusModeDiscoveryCache;
static NSTimeInterval CCBGFocusModeDiscoveryCacheTime = 0;
static NSArray<NSString *> *CCBGCurrentFocusAliasesCache;
static NSTimeInterval CCBGCurrentFocusAliasesCacheTime = 0;

static void CCBGStoreFocusDiscoveryStatus(NSDictionary<NSString *, id> *status) {
    if (!status.count) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)CCBGFocusDiscoveryProcessKey(), (__bridge CFDictionaryRef)status, domain);
    CFPreferencesAppSynchronize(domain);
}

NSDictionary<NSString *, id> *CCBGFocusDiscoveryStatus(void) {
    id springBoard = CCBGReadPreference(@"sceneDirectorFocusDiscoverySpringBoard", @{});
    id app = CCBGReadPreference(@"sceneDirectorFocusDiscoveryApp", @{});
    return @{
        @"springboard": [springBoard isKindOfClass:NSDictionary.class] ? springBoard : @{},
        @"app": [app isKindOfClass:NSDictionary.class] ? app : @{},
    };
}

static NSArray *CCBGFocusModeServices(void) {
    CCBGEnsureFocusFrameworkLoaded();
    NSMutableArray *services = [NSMutableArray array];
    NSString *clientIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.apple.springboard";
    for (NSString *className in @[@"DNDStateService", @"DNDModeConfigurationService"]) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id service = nil;
        SEL selector = NSSelectorFromString(@"serviceForClientIdentifier:");
        if ([cls respondsToSelector:selector]) {
            @try {
                service = ((id (*)(id, SEL, id))objc_msgSend)(cls, selector, clientIdentifier);
            } @catch (__unused NSException *exception) {
                service = nil;
            }
        }
        if (service && ![services containsObject:service]) [services addObject:service];
    }
    return services;
}

static void CCBGAppendFocusMode(NSArray<NSString *> *aliases, NSMutableArray<NSDictionary<NSString *, id> *> *modes, NSMutableSet<NSString *> *seen) {
    NSMutableOrderedSet<NSString *> *cleanAliases = [NSMutableOrderedSet orderedSet];
    for (id rawAlias in aliases) {
        if (![rawAlias isKindOfClass:NSString.class]) continue;
        NSString *alias = [rawAlias stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (alias.length) [cleanAliases addObject:alias];
    }
    NSString *name = cleanAliases.firstObject;
    NSString *key = CCBGNormalizedSceneText(name);
    if (!key.length || [seen containsObject:key]) return;
    [seen addObject:key];
    [modes addObject:@{ @"name": name, @"aliases": cleanAliases.array }];
}

static void CCBGAppendStoredFocusModes(id stored, NSMutableArray<NSDictionary<NSString *, id> *> *modes, NSMutableSet<NSString *> *seen) {
    if (![stored isKindOfClass:NSArray.class]) return;
    for (id rawMode in (NSArray *)stored) {
        if (![rawMode isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *mode = rawMode;
        NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
        CCBGCollectFocusAliases(mode[@"name"], aliases, 0);
        CCBGCollectFocusAliases(mode[@"aliases"], aliases, 0);
        CCBGAppendFocusMode(aliases.array, modes, seen);
    }
}

static NSArray<NSString *> *CCBGFocusAliasesFromServices(NSArray *services) {
    NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
    for (id service in services) {
        SEL selector = NSSelectorFromString(@"queryCurrentStateWithError:");
        if (![service respondsToSelector:selector]) continue;
        NSError *error = nil;
        @try {
            CCBGCollectFocusAliases(((id (*)(id, SEL, NSError **))objc_msgSend)(service, selector, &error), aliases, 0);
        } @catch (__unused NSException *exception) {
            continue;
        }
    }
    return aliases.array;
}

static void CCBGCollectConfiguredFocusModes(id object, NSMutableArray<NSDictionary<NSString *, id> *> *modes, NSMutableSet<NSString *> *seen, NSUInteger depth) {
    if (!object || depth > 8) return;
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class] || [object isKindOfClass:NSOrderedSet.class]) {
        for (id value in object) CCBGCollectConfiguredFocusModes(value, modes, seen, depth + 1);
        return;
    }
    if (![object isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dictionary = object;
    id label = dictionary[@"displayName"] ?: dictionary[@"localizedName"] ?: dictionary[@"name"] ?: dictionary[@"title"];
    if ([label isKindOfClass:NSString.class] && [label length]) {
        NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
        CCBGCollectFocusAliases(dictionary, aliases, 0);
        CCBGAppendFocusMode(aliases.array, modes, seen);
    }
    for (id value in dictionary.allValues) CCBGCollectConfiguredFocusModes(value, modes, seen, depth + 1);
}

static NSArray<NSString *> *CCBGFocusModeListSelectorNames(void) {
    return @[@"modeConfigurationsReturningError:", @"availableModesReturningError:", @"allModesReturningError:"];
}

static void CCBGAppendFocusCollection(id collection, NSMutableArray<NSDictionary<NSString *, id> *> *modes, NSMutableSet<NSString *> *seen) {
    if ([collection isKindOfClass:NSDictionary.class]) collection = [collection allValues];
    if ([collection isKindOfClass:NSArray.class] || [collection isKindOfClass:NSSet.class] || [collection isKindOfClass:NSOrderedSet.class]) {
        for (id mode in collection) {
            NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
            CCBGCollectFocusAliases(mode, aliases, 0);
            CCBGAppendFocusMode(aliases.array, modes, seen);
        }
        return;
    }
    NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSet];
    CCBGCollectFocusAliases(collection, aliases, 0);
    CCBGAppendFocusMode(aliases.array, modes, seen);
}

static NSArray<NSString *> *CCBGFocusConfigurationPaths(void) {
    return @[
        @"/var/mobile/Library/DoNotDisturb/DB/ModeConfigurations.json",
        @"/var/mobile/Library/DoNotDisturb/DB/ModeConfigurations.plist",
        @"/var/mobile/Library/DoNotDisturb/ModeConfigurations.json",
        @"/var/mobile/Library/DoNotDisturb/ModeConfigurations.plist",
        @"/var/mobile/Library/Preferences/com.apple.donotdisturb.plist",
        @"/var/mobile/Library/Preferences/com.apple.Focus.plist",
    ];
}

static id CCBGReadFocusConfiguration(NSString *path, NSMutableArray<NSDictionary<NSString *, id> *> *fileResults) {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSData *data = exists ? [NSData dataWithContentsOfFile:path] : nil;
    NSError *jsonError = nil;
    NSError *plistError = nil;
    id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
    if (!root && data.length) root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&plistError];
    NSMutableDictionary *result = [@{
        @"path": path,
        @"exists": @(exists),
        @"bytes": @(data.length),
        @"parsed": @(root != nil),
    } mutableCopy];
    NSString *error = jsonError.localizedDescription ?: plistError.localizedDescription;
    if (data.length && !root && error.length) result[@"error"] = error;
    [fileResults addObject:result];
    return root;
}

NSArray<NSDictionary<NSString *, id> *> *CCBGAvailableFocusModes(void) {
    id stored = CCBGReadPreference(@"sceneDirectorKnownFocusModes", @[]);
    if (![NSThread isMainThread]) return [stored isKindOfClass:NSArray.class] ? stored : @[];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (CCBGFocusModeDiscoveryCache && now - CCBGFocusModeDiscoveryCacheTime < 60.0) return CCBGFocusModeDiscoveryCache;
    BOOL frameworkLoaded = CCBGEnsureFocusFrameworkLoaded();
    NSArray<NSString *> *serviceClassNames = CCBGAvailableFocusServiceClassNames();
    NSMutableArray<NSDictionary<NSString *, id> *> *modes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSDictionary<NSString *, id> *> *fileResults = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *domainResults = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *selectorResults = [NSMutableArray array];
    id activityManager = CCBGFocusActivityManager();
    NSString *activityException = nil;
    id availableActivities = CCBGFocusActivitiesFromManager(activityManager, &activityException);
    id activeActivity = CCBGFocusActivityManagerValue(activityManager, @"activeActivity", NULL);
    CCBGAppendFocusCollection(availableActivities, modes, seen);
    CCBGAppendFocusCollection(activeActivity, modes, seen);
    CCBGAppendStoredFocusModes(stored, modes, seen);
    NSUInteger activityCount = [availableActivities respondsToSelector:@selector(count)] ? [availableActivities count] : availableActivities ? 1 : 0;
    NSMutableDictionary *activityManagerResult = [@{
        @"managerClass": activityManager ? NSStringFromClass([activityManager class]) ?: @"" : @"",
        @"availableClass": availableActivities ? NSStringFromClass([availableActivities class]) ?: @"" : @"",
        @"availableCount": @(activityCount),
        @"activeClass": activeActivity ? NSStringFromClass([activeActivity class]) ?: @"" : @"",
    } mutableCopy];
    if (activityException.length) activityManagerResult[@"error"] = activityException;
    NSArray *services = modes.count ? @[] : CCBGFocusModeServices();
    NSArray<NSString *> *exactListSelectors = CCBGFocusModeListSelectorNames();
    for (id service in services) {
        for (NSString *selectorName in exactListSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            BOOL responds = [service respondsToSelector:selector];
            NSError *error = nil;
            id collection = nil;
            NSString *exceptionText = @"";
            if (responds) {
                @try {
                    collection = ((id (*)(id, SEL, NSError **))objc_msgSend)(service, selector, &error);
                } @catch (NSException *exception) {
                    exceptionText = exception.reason ?: exception.name ?: @"exception";
                }
            }
            NSUInteger resultCount = [collection respondsToSelector:@selector(count)] ? [collection count] : collection ? 1 : 0;
            NSMutableDictionary *result = [@{
                @"serviceClass": NSStringFromClass([service class]) ?: @"",
                @"selector": selectorName,
                @"source": @"ios16-runtime-header",
                @"responds": @(responds),
                @"valueClass": collection ? NSStringFromClass([collection class]) ?: @"" : @"",
                @"resultCount": @(resultCount),
            } mutableCopy];
            NSString *errorText = error.localizedDescription ?: exceptionText;
            if (errorText.length) result[@"error"] = errorText;
            [selectorResults addObject:result];
            CCBGAppendFocusCollection(collection, modes, seen);
        }
    }
    if (!modes.count) {
        for (NSString *path in CCBGFocusConfigurationPaths()) {
            id root = CCBGReadFocusConfiguration(path, fileResults);
            if (root) CCBGCollectConfiguredFocusModes(root, modes, seen, 0);
        }
        for (NSString *domainName in @[@"com.apple.donotdisturb", @"com.apple.Focus", @"com.apple.focus"] ) {
            CFStringRef domain = (__bridge CFStringRef)domainName;
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFArrayRef keysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            NSArray *keys = CFBridgingRelease(keysRef) ?: @[];
            CFDictionaryRef valuesRef = keys.count
                ? CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                : NULL;
            NSDictionary *values = CFBridgingRelease(valuesRef) ?: @{};
            [domainResults addObject:@{ @"domain": domainName, @"keyCount": @(keys.count) }];
            if (values.count) CCBGCollectConfiguredFocusModes(values, modes, seen, 0);
        }
    }
    NSMutableOrderedSet<NSString *> *activeAliasSet = [NSMutableOrderedSet orderedSetWithArray:CCBGFocusAliasesFromActivityManager(activityManager)];
    if (!activeAliasSet.count) [activeAliasSet addObjectsFromArray:CCBGFocusAliasesFromServices(services)];
    NSArray<NSString *> *activeAliases = activeAliasSet.array;
    CCBGAppendFocusMode(activeAliases, modes, seen);
    if (modes.count && ![modes isEqual:stored]) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue(CFSTR("sceneDirectorKnownFocusModes"), (__bridge CFArrayRef)modes, domain);
        CFPreferencesAppSynchronize(domain);
    }
    CCBGStoreFocusDiscoveryStatus(@{
        @"time": @(NSDate.date.timeIntervalSince1970),
        @"process": NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName ?: @"unknown",
        @"frameworkLoaded": @(frameworkLoaded),
        @"serviceClasses": serviceClassNames,
        @"serviceCount": @(services.count),
        @"activityManager": activityManagerResult,
        @"selectorResults": selectorResults,
        @"fallbackSkipped": @(!fileResults.count && !domainResults.count && modes.count > 0),
        @"domainResults": domainResults,
        @"fileResults": fileResults,
        @"activeAliases": activeAliases,
        @"modeCount": @(modes.count),
    });
    CCBGFocusModeDiscoveryCache = [modes copy];
    CCBGFocusModeDiscoveryCacheTime = now;
    return CCBGFocusModeDiscoveryCache;
}

NSArray<NSDictionary<NSString *, id> *> *CCBGRefreshFocusModeCache(void) {
    if ([NSThread isMainThread]) {
        CCBGFocusModeDiscoveryCache = nil;
        CCBGFocusModeDiscoveryCacheTime = 0;
        CCBGInvalidateSceneRuntimeCaches();
        return CCBGAvailableFocusModes();
    }
    __block NSArray<NSDictionary<NSString *, id> *> *modes = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ modes = CCBGRefreshFocusModeCache(); });
    return modes ?: @[];
}

static void CCBGPersistCurrentFocusAliases(NSArray<NSString *> *aliases) {
    NSArray<NSString *> *safeAliases = [aliases isKindOfClass:NSArray.class] ? aliases : @[];
    id stored = CCBGReadPreference(@"sceneDirectorLastFocusAliases", @[]);
    if ([stored isKindOfClass:NSArray.class] && [stored isEqual:safeAliases]) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetAppValue(CFSTR("sceneDirectorLastFocusAliases"),
                             safeAliases.count ? (__bridge CFArrayRef)safeAliases : NULL,
                             domain);
    CFPreferencesAppSynchronize(domain);
}

NSArray<NSString *> *CCBGCurrentFocusAliases(void) {
    id stored = CCBGReadPreference(@"sceneDirectorLastFocusAliases", @[]);
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if ([NSThread isMainThread] && CCBGCurrentFocusAliasesCache && now - CCBGCurrentFocusAliasesCacheTime < 5.0) {
        return CCBGCurrentFocusAliasesCache;
    }
    id activityManager = [NSThread isMainThread] ? CCBGFocusActivityManager() : nil;
    BOOL managerAuthoritative = CCBGFocusActivityManagerHasAuthoritativeState(activityManager);
    NSMutableOrderedSet<NSString *> *aliases = [NSMutableOrderedSet orderedSetWithArray:CCBGFocusAliasesFromActivityManager(activityManager)];
    NSArray *services = managerAuthoritative || aliases.count || ![NSThread isMainThread] ? @[] : CCBGFocusModeServices();
    if (!aliases.count) [aliases addObjectsFromArray:CCBGFocusAliasesFromServices(services)];
    if (!aliases.count) {
        if (managerAuthoritative) {
            CCBGPersistCurrentFocusAliases(@[]);
            CCBGCurrentFocusAliasesCache = @[];
            CCBGCurrentFocusAliasesCacheTime = now;
            return @[];
        }
        return [stored isKindOfClass:NSArray.class] ? stored : @[];
    }
    NSArray<NSDictionary<NSString *, id> *> *availableModes = CCBGAvailableFocusModes();
    NSMutableSet<NSString *> *activeKeys = [NSMutableSet set];
    for (NSString *alias in aliases) {
        NSString *key = CCBGNormalizedSceneText(alias);
        if (key.length) [activeKeys addObject:key];
    }
    BOOL matchedAvailableMode = NO;
    for (NSDictionary *mode in availableModes) {
        NSArray *modeAliases = [mode[@"aliases"] isKindOfClass:NSArray.class] ? mode[@"aliases"] : @[];
        BOOL activeMode = NO;
        for (NSString *alias in modeAliases) {
            if ([activeKeys containsObject:CCBGNormalizedSceneText(alias)]) { activeMode = YES; break; }
        }
        if (activeMode) {
            matchedAvailableMode = YES;
            for (NSString *alias in modeAliases) if (alias.length) [aliases addObject:alias];
        }
    }
    if (aliases.count && !matchedAvailableMode) {
        NSMutableArray *updatedModes = [availableModes mutableCopy] ?: [NSMutableArray array];
        [updatedModes addObject:@{ @"name": aliases.firstObject, @"aliases": aliases.array }];
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue(CFSTR("sceneDirectorKnownFocusModes"), (__bridge CFArrayRef)updatedModes, domain);
        CFPreferencesAppSynchronize(domain);
    }
    CCBGPersistCurrentFocusAliases(aliases.array);
    CCBGCurrentFocusAliasesCache = [aliases.array copy];
    CCBGCurrentFocusAliasesCacheTime = now;
    return aliases.array;
}

NSString *CCBGCurrentFocusIdentifier(void) {
    return CCBGCurrentFocusAliases().firstObject ?: @"";
}

static NSDictionary *CCBGSceneRuntimeContextCache;
static NSTimeInterval CCBGSceneRuntimeContextCacheTime = 0;

static BOOL CCBGSceneSystemIsLocked(void) {
    if (![NSThread isMainThread]) return NO;
    for (NSString *className in @[@"SBLockScreenManager", @"SBLockStateAggregator", @"SBCoverSheetPresentationManager"]) {
        Class cls = NSClassFromString(className);
        SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
        if (!cls || ![cls respondsToSelector:sharedSelector]) continue;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSelector);
        for (NSString *selectorName in @[@"isUILocked", @"isLocked", @"isLockScreenVisible", @"isCoverSheetPresented"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([manager respondsToSelector:selector] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector)) return YES;
        }
    }
    return !UIApplication.sharedApplication.protectedDataAvailable;
}

NSDictionary *CCBGSceneRuntimeContext(UIView *view) {
    BOOL dark = CCBGSystemUsesDarkAppearance();
    BOOL mainThreadView = view && [NSThread isMainThread];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (mainThreadView && CCBGSceneRuntimeContextCache && now - CCBGSceneRuntimeContextCacheTime < 0.10) {
        return CCBGSceneRuntimeContextCache;
    }
    NSDictionary *lastContext = CCBGReadPreference(@"sceneDirectorLastRuntimeContext", @{});
    if (mainThreadView) {
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    }
    UIDeviceBatteryState batteryState = mainThreadView ? UIDevice.currentDevice.batteryState : UIDeviceBatteryStateUnknown;
    BOOL charging = mainThreadView ? (batteryState == UIDeviceBatteryStateCharging || batteryState == UIDeviceBatteryStateFull) : [lastContext[@"charging"] boolValue];
    BOOL landscape = mainThreadView ? NO : [lastContext[@"landscape"] boolValue];
    if (mainThreadView) {
        UIInterfaceOrientation orientation = view.window.windowScene.interfaceOrientation;
        if (UIInterfaceOrientationIsLandscape(orientation)) landscape = YES;
        else if (!UIInterfaceOrientationIsPortrait(orientation)) landscape = CGRectGetWidth(view.bounds) > CGRectGetHeight(view.bounds);
    }
    NSArray<NSString *> *focusAliases = CCBGCurrentFocusAliases();
    NSDictionary *context = @{
        @"locked": @(mainThreadView ? CCBGSceneSystemIsLocked() : [lastContext[@"locked"] boolValue]), @"dark": @(dark), @"charging": @(charging),
        @"landscape": @(landscape), @"focus": focusAliases.firstObject ?: @"", @"focusAliases": focusAliases,
    };
    BOOL springBoardRuntime = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
    if (mainThreadView && springBoardRuntime) {
        NSDictionary *darkDiagnostics = CCBGDarkAppearanceDiagnostics();
        NSDictionary *lastDarkDiagnostics = CCBGReadPreference(@"sceneDirectorLastDarkAppearanceDiagnostics", @{});
        BOOL contextChanged = ![context isEqual:lastContext];
        BOOL diagnosticsChanged = ![darkDiagnostics isEqual:lastDarkDiagnostics];
        if (contextChanged || diagnosticsChanged) {
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        if (contextChanged) CFPreferencesSetAppValue(CFSTR("sceneDirectorLastRuntimeContext"), (__bridge CFDictionaryRef)context, domain);
        if (diagnosticsChanged) CFPreferencesSetAppValue(CFSTR("sceneDirectorLastDarkAppearanceDiagnostics"), (__bridge CFDictionaryRef)darkDiagnostics, domain);
        CFPreferencesAppSynchronize(domain);
        }
    }
    if (mainThreadView) {
        CCBGSceneRuntimeContextCache = context;
        CCBGSceneRuntimeContextCacheTime = now;
    }
    return context;
}

static BOOL CCBGSceneConditionMatches(NSDictionary *conditions, NSDictionary *context) {
    if (![conditions isKindOfClass:NSDictionary.class]) return NO;
    BOOL hasEnabledCondition = NO;
    for (NSString *key in @[@"locked", @"dark", @"charging", @"landscape"]) {
        id rawExpected = conditions[key];
        NSInteger expected = [rawExpected respondsToSelector:@selector(integerValue)] ? [rawExpected integerValue] : -1;
        if (expected >= 0) {
            hasEnabledCondition = YES;
            if ([context[key] boolValue] != (BOOL)expected) return NO;
        }
    }
    NSString *focus = CCBGNormalizedSceneText(conditions[@"focus"]);
    id storedFocusEnabled = conditions[@"focusEnabled"];
    BOOL focusEnabled = [storedFocusEnabled respondsToSelector:@selector(boolValue)] ? [storedFocusEnabled boolValue] : focus.length > 0;
    if (focusEnabled) {
        hasEnabledCondition = YES;
        if (!focus.length) return NO;
        NSMutableArray *aliases = [NSMutableArray array];
        if ([context[@"focusAliases"] isKindOfClass:NSArray.class]) [aliases addObjectsFromArray:context[@"focusAliases"]];
        if ([context[@"focus"] isKindOfClass:NSString.class]) [aliases addObject:context[@"focus"]];
        BOOL matched = NO;
        for (id alias in aliases) {
            if ([focus isEqualToString:CCBGNormalizedSceneText(alias)]) { matched = YES; break; }
        }
        if (!matched) return NO;
    }
    return hasEnabledCondition;
}

NSDictionary *CCBGSceneDirectorEvaluationForScene(NSDictionary *scene, NSDictionary *context) {
    if (![scene isKindOfClass:NSDictionary.class]) return @{ @"matches": @NO, @"reasons": @[@"场景数据无效"], @"enabledConditionCount": @0 };
    NSMutableArray<NSString *> *reasons = [NSMutableArray array];
    if (![scene[@"enabled"] respondsToSelector:@selector(boolValue)] || ![scene[@"enabled"] boolValue]) [reasons addObject:@"场景已停用"];
    NSDictionary *conditions = [scene[@"conditions"] isKindOfClass:NSDictionary.class] ? scene[@"conditions"] : @{};
    NSDictionary *safeContext = [context isKindOfClass:NSDictionary.class] ? context : @{};
    NSDictionary *labels = @{ @"locked": @"锁屏", @"dark": @"深色模式", @"charging": @"充电中", @"landscape": @"横屏" };
    NSInteger enabledCount = 0;
    for (NSString *key in @[@"locked", @"dark", @"charging", @"landscape"]) {
        id rawExpected = conditions[key];
        NSInteger expected = [rawExpected respondsToSelector:@selector(integerValue)] ? [rawExpected integerValue] : -1;
        if (expected < 0) continue;
        enabledCount += 1;
        if ([safeContext[key] boolValue] != (BOOL)expected) [reasons addObject:[NSString stringWithFormat:@"%@需要%@", labels[key], expected ? @"开启" : @"关闭"]];
    }
    NSString *focus = CCBGNormalizedSceneText(conditions[@"focus"]);
    id storedFocusEnabled = conditions[@"focusEnabled"];
    BOOL focusEnabled = [storedFocusEnabled respondsToSelector:@selector(boolValue)] ? [storedFocusEnabled boolValue] : focus.length > 0;
    if (focusEnabled) {
        enabledCount += 1;
        if (!focus.length) [reasons addObject:@"未选择专注模式"];
        else {
            NSMutableArray *aliases = [NSMutableArray array];
            if ([safeContext[@"focusAliases"] isKindOfClass:NSArray.class]) [aliases addObjectsFromArray:safeContext[@"focusAliases"]];
            if ([safeContext[@"focus"] isKindOfClass:NSString.class]) [aliases addObject:safeContext[@"focus"]];
            BOOL matched = NO;
            for (id alias in aliases) if ([focus isEqualToString:CCBGNormalizedSceneText(alias)]) { matched = YES; break; }
            if (!matched) [reasons addObject:[NSString stringWithFormat:@"当前专注模式不是 %@", conditions[@"focus"] ?: focus]];
        }
    }
    if (enabledCount == 0) [reasons addObject:@"未启用任何自动条件"];
    return @{ @"matches": @(reasons.count == 0), @"reasons": reasons, @"enabledConditionCount": @(enabledCount) };
}

static NSArray<NSDictionary *> *CCBGSceneDirectorSortedScenes(void) {
    id stored = CCBGReadPreference(@"sceneDirectorScenes", @[]);
    NSMutableArray<NSDictionary *> *validScenes = [NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) for (id candidate in (NSArray *)stored) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = [candidate[@"id"] isKindOfClass:NSString.class] ? candidate[@"id"] : @"";
        if (identifier.length) [validScenes addObject:candidate];
    }
    return [validScenes sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSInteger leftPriority = [left[@"priority"] respondsToSelector:@selector(integerValue)] ? [left[@"priority"] integerValue] : 0;
        NSInteger rightPriority = [right[@"priority"] respondsToSelector:@selector(integerValue)] ? [right[@"priority"] integerValue] : 0;
        return leftPriority == rightPriority ? NSOrderedSame : leftPriority > rightPriority ? NSOrderedAscending : NSOrderedDescending;
    }];
}

NSArray<NSDictionary *> *CCBGSceneDirectorMatchingScenes(NSDictionary *context) {
    NSDictionary *safeContext = [context isKindOfClass:NSDictionary.class] ? context : @{};
    if (CCBGSceneDirectorAutomationPaused() && ![CCBGReadPreference(@"sceneDirectorManualSceneID", @"") length]) return @[];
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSDictionary *scene in CCBGSceneDirectorSortedScenes()) {
        if (![scene[@"enabled"] respondsToSelector:@selector(boolValue)] || ![scene[@"enabled"] boolValue]) continue;
        if (CCBGSceneConditionMatches(scene[@"conditions"], safeContext)) [matches addObject:scene];
    }
    return matches;
}

static NSDictionary *CCBGResolvedSceneCacheContext;
static NSDictionary *CCBGResolvedSceneCacheValue;
static NSTimeInterval CCBGResolvedSceneCacheTime;
static BOOL CCBGResolvedSceneCacheValid;

void CCBGInvalidateSceneRuntimeCaches(void) {
    CCBGCurrentFocusAliasesCache = nil;
    CCBGCurrentFocusAliasesCacheTime = 0;
    CCBGSceneRuntimeContextCache = nil;
    CCBGSceneRuntimeContextCacheTime = 0;
    CCBGResolvedSceneCacheContext = nil;
    CCBGResolvedSceneCacheValue = nil;
    CCBGResolvedSceneCacheTime = 0;
    CCBGResolvedSceneCacheValid = NO;
}

BOOL CCBGSceneDirectorAutomationPaused(void) {
    return [CCBGReadPreference(@"sceneDirectorAutomationPaused", @NO) boolValue];
}

static void CCBGClearStaleManualSceneState(void) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)@{@"sceneDirectorReplayActive": @NO},
            (__bridge CFArrayRef)@[@"sceneDirectorManualSceneID"], domain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize(domain);
    });
}

NSDictionary *CCBGSceneDirectorResolvedScene(NSDictionary *context) {
    NSDictionary *safeContext = [context isKindOfClass:NSDictionary.class] ? context : @{};
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (CCBGResolvedSceneCacheValid && CCBGResolvedSceneCacheContext == safeContext && now - CCBGResolvedSceneCacheTime < 0.10) {
        return CCBGResolvedSceneCacheValue;
    }
    NSArray<NSDictionary *> *scenes = CCBGSceneDirectorSortedScenes();
    id storedManualID = CCBGReadPreference(@"sceneDirectorManualSceneID", @"");
    NSString *manualID = [storedManualID isKindOfClass:NSString.class] ? storedManualID : @"";
    BOOL automationPaused = CCBGSceneDirectorAutomationPaused();
    NSDictionary *resolved = nil;
    NSDictionary *manualScene = nil;
    if (manualID.length) {
        for (NSDictionary *scene in scenes) {
            if ([scene[@"id"] isEqualToString:manualID] && [scene[@"enabled"] boolValue]) {
                manualScene = scene;
                break;
            }
        }
        if (manualScene) resolved = manualScene;
        else {
            CCBGClearStaleManualSceneState();
            manualID = @"";
        }
    }
    if (!manualID.length && automationPaused) {
        CCBGResolvedSceneCacheContext = safeContext;
        CCBGResolvedSceneCacheValue = nil;
        CCBGResolvedSceneCacheTime = now;
        CCBGResolvedSceneCacheValid = YES;
        return nil;
    }
    for (NSDictionary *scene in scenes) {
        if (resolved) break;
        if (![scene[@"enabled"] respondsToSelector:@selector(boolValue)] || ![scene[@"enabled"] boolValue]) continue;
        if (CCBGSceneConditionMatches(scene[@"conditions"], safeContext)) { resolved = scene; break; }
    }
    CCBGResolvedSceneCacheContext = safeContext;
    CCBGResolvedSceneCacheValue = resolved;
    CCBGResolvedSceneCacheTime = now;
    CCBGResolvedSceneCacheValid = YES;
    return resolved;
}

NSString *CCBGSceneDirectorMediaForTarget(NSString *target, NSDictionary *context) {
    NSDictionary *scene = CCBGSceneDirectorResolvedScene(context);
    NSDictionary *targets = [scene[@"targets"] isKindOfClass:NSDictionary.class] ? scene[@"targets"] : @{};
    id media = targets[target];
    return [media isKindOfClass:NSString.class] ? media : @"";
}

BOOL CCBGSceneDirectorLowPowerStatic(NSDictionary *context) {
    NSDictionary *scene = CCBGSceneDirectorResolvedScene(context);
    BOOL sceneEnabled = [scene[@"lowPowerStatic"] respondsToSelector:@selector(boolValue)] && [scene[@"lowPowerStatic"] boolValue];
    return sceneEnabled;
}

BOOL CCBGSceneDirectorBreathingGridEnabled(NSDictionary *context) {
    id enabled = CCBGSceneDirectorResolvedScene(context)[@"breathingGridEnabled"];
    return [enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
}

NSInteger CCBGSceneDirectorExpandedSlot(void) { return [CCBGReadPreference(@"sceneDirectorExpandedSlot", @-1) integerValue]; }

void CCBGSceneDirectorSetExpandedSlot(NSInteger slot) {
    NSInteger value = MIN((NSInteger)CCBGModuleDisplayNames().count - 1, MAX(-1, slot));
    if (CCBGSceneDirectorExpandedSlot() == value) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetAppValue(CFSTR("sceneDirectorExpandedSlot"), (__bridge CFPropertyListRef)@(value), domain);
    CFPreferencesAppSynchronize(domain);
    CCBGInvalidatePreferenceReadCache();
    CCBGPostPresentationRecovery();
}

NSString *CCBGSceneDirectorStateMediaForTarget(NSString *target, NSString *state, NSDictionary *context) {
    NSDictionary *scene = CCBGSceneDirectorResolvedScene(context);
    NSDictionary *allTracks = [scene[@"stateTracks"] isKindOfClass:NSDictionary.class] ? scene[@"stateTracks"] : @{};
    id tracks = allTracks[target];
    if (![tracks isKindOfClass:NSDictionary.class]) return @"";
    id media = tracks[state.length ? state : @"off"];
    return [media isKindOfClass:NSString.class] ? media : @"";
}

BOOL CCBGSceneDirectorRelayFromSlotInContext(NSInteger sourceSlot, NSString *mediaName, NSDictionary *context) {
    if (sourceSlot < 0 || sourceSlot >= (NSInteger)CCBGModuleDisplayNames().count || !mediaName.length) return NO;
    NSDictionary *sceneRelay = CCBGSceneDirectorResolvedScene(context)[@"relay"];
    NSDictionary *relay = [sceneRelay isKindOfClass:NSDictionary.class] ? sceneRelay : @{};
    if (![relay[@"enabled"] respondsToSelector:@selector(boolValue)] || ![relay[@"enabled"] boolValue]) return NO;
    NSInteger configuredSource = [relay[@"sourceSlot"] integerValue];
    if (configuredSource != sourceSlot) return NO;
    NSArray *targets = relay[@"targetSlots"];
    if (![targets isKindOfClass:NSArray.class]) return NO;
    NSDictionary *mediaBySlot = [relay[@"mediaBySlot"] isKindOfClass:NSDictionary.class] ? relay[@"mediaBySlot"] : @{};
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (id value in targets) {
        if (![value isKindOfClass:NSNumber.class]) continue;
        NSInteger slot = [value integerValue];
        if (slot < 0 || slot >= (NSInteger)CCBGModuleDisplayNames().count || slot == sourceSlot) continue;
        NSString *configuredMedia = mediaBySlot[@(slot).stringValue];
        NSString *targetMedia = [configuredMedia isKindOfClass:NSString.class] ? configuredMedia : mediaName;
        if (!targetMedia.length) continue;
        changes[CCBGPreferenceKeyForModule(@"selectedMedia", slot)] = targetMedia;
        changes[CCBGPreferenceKeyForModule(@"currentMedia", slot)] = targetMedia;
        changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
    }
    if (!changes.count) return NO;
    CCBGWritePreferences(changes);
    CCBGRecordSceneTimelineEvent(@"relay", @{ @"sourceSlot": @(sourceSlot), @"media": mediaName, @"targets": targets });
    return YES;
}

void CCBGRecordModuleRuntimeState(NSInteger slot, NSTimeInterval position, NSTimeInterval duration) {
    if (slot < 0 || slot >= (NSInteger)CCBGModuleDisplayNames().count) return;
    if (!isfinite(position)) position = 0;
    if (!isfinite(duration)) duration = 0;
    position = MAX(0.0, position);
    duration = MAX(0.0, duration);
    CCBGEnqueueAnalyticsMutation(^{
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"runtimePosition", slot), (__bridge CFPropertyListRef)@(position), domain);
        CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"runtimeDuration", slot), (__bridge CFPropertyListRef)@(duration), domain);
        CFPreferencesAppSynchronize(domain);
    });
}

void CCBGRecordRuntimeDiagnostic(NSString *key, id value) {
    if (!key.length) return;
    NSString *keyCopy = [key copy];
    id valueCopy = [value respondsToSelector:@selector(copy)] ? [value copy] : value;
    CCBGEnqueueAnalyticsMutation(^{
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)keyCopy, valueCopy ? (__bridge CFPropertyListRef)valueCopy : NULL, domain);
        CFPreferencesAppSynchronize(domain);
    });
}

void CCBGRecordSystemOverlayPlaybackSuccess(NSString *fileName, NSString *failureKey) {
    if (!fileName.length || !failureKey.length) return;
    NSString *fileNameCopy = [fileName copy];
    NSString *failureKeyCopy = [failureKey copy];
    CCBGEnqueueAnalyticsMutation(^{
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesAppSynchronize(domain);
        CFPropertyListRef failuresRef = CFPreferencesCopyAppValue((__bridge CFStringRef)failureKeyCopy, domain);
        id storedFailures = CFBridgingRelease(failuresRef);
        if ([storedFailures isKindOfClass:NSDictionary.class] && storedFailures[fileNameCopy]) {
            NSMutableDictionary *failures = [storedFailures mutableCopy];
            [failures removeObjectForKey:fileNameCopy];
            CFPreferencesSetAppValue((__bridge CFStringRef)failureKeyCopy, (__bridge CFDictionaryRef)failures, domain);
        }
        CFPropertyListRef recentRef = CFPreferencesCopyAppValue(CFSTR("systemOverlayRecentMedia"), domain);
        id storedRecent = CFBridgingRelease(recentRef);
        NSMutableArray<NSString *> *recent = [storedRecent isKindOfClass:NSArray.class] ? [storedRecent mutableCopy] : [NSMutableArray array];
        [recent removeObject:fileNameCopy];
        [recent insertObject:fileNameCopy atIndex:0];
        if (recent.count > 30) [recent removeObjectsInRange:NSMakeRange(30, recent.count - 30)];
        CFPreferencesSetAppValue(CFSTR("systemOverlayRecentMedia"), (__bridge CFArrayRef)recent, domain);
        CFPreferencesAppSynchronize(domain);
    });
}

void CCBGRecordSceneTimelineEvent(NSString *event, NSDictionary *details) {
    NSString *eventCopy = [event copy] ?: @"";
    NSDictionary *detailsCopy = [details copy] ?: @{};
    CCBGEnqueueAnalyticsMutation(^{
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        CFPreferencesAppSynchronize(domain);
        id (^readValue)(NSString *, id) = ^id(NSString *key, id fallback) {
            CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
            return valueRef ? CFBridgingRelease(valueRef) : fallback;
        };
        id storedTimeline = readValue(@"sceneDirectorTimeline", @[]);
        NSMutableArray *timeline = [storedTimeline isKindOfClass:NSArray.class] ? [storedTimeline mutableCopy] : [NSMutableArray array];
        NSDictionary *latestEntry = [timeline.firstObject isKindOfClass:NSDictionary.class] ? timeline.firstObject : nil;
        NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970;
        if ([eventCopy isEqualToString:@"playback-start"] && [latestEntry[@"event"] isEqualToString:@"playback-start"] &&
            timestamp - [latestEntry[@"time"] doubleValue] < 1.0) {
            return;
        }
        NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            snapshot[[NSString stringWithFormat:@"module%ld", (long)slot]] = @{
                @"selectedMedia": readValue(CCBGPreferenceKeyForModule(@"selectedMedia", slot), @"") ?: @"",
                @"currentMedia": readValue(CCBGPreferenceKeyForModule(@"currentMedia", slot), @"") ?: @"",
                @"playbackMode": readValue(CCBGPreferenceKeyForModule(@"playbackMode", slot), @0) ?: @0,
            };
        }
        NSMutableDictionary *systemOverlays = [NSMutableDictionary dictionary];
        for (NSString *key in CCBGSystemMediaReferenceKeys()) {
            id value = readValue(key, nil);
            if (value) systemOverlays[key] = value;
        }
        for (NSString *prefix in @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"]) {
            for (NSString *suffix in @[@"Enabled", @"CompactPlaybackMode", @"ExpandedPlaybackMode"]) {
                NSString *key = [prefix stringByAppendingString:suffix];
                id value = readValue(key, nil);
                if (value) systemOverlays[key] = value;
            }
        }
        id customModules = readValue(@"customSystemOverlayModules", @[]);
        if ([customModules isKindOfClass:NSArray.class]) {
            NSArray *suffixes = @[@"Enabled", @"CompactMedia", @"ExpandedMedia", @"CompactCurrentMedia", @"ExpandedCurrentMedia",
                @"CompactSequentialCurrentMedia", @"ExpandedSequentialCurrentMedia", @"CompactRandomCurrentMedia", @"ExpandedRandomCurrentMedia",
                @"CompactPlaybackMode", @"ExpandedPlaybackMode", @"StateOffMedia", @"StateOnMedia", @"StateLoadingMedia", @"StateUnavailableMedia"];
            for (NSDictionary *module in (NSArray *)customModules) {
                NSString *prefix = [module[@"prefix"] isKindOfClass:NSString.class] ? module[@"prefix"] : @"";
                if (!prefix.length) continue;
                for (NSString *suffix in suffixes) {
                    NSString *key = [prefix stringByAppendingString:suffix];
                    id value = readValue(key, nil);
                    if (value) systemOverlays[key] = value;
                }
            }
        }
        snapshot[@"systemOverlays"] = systemOverlays;
        NSString *manualSceneID = readValue(@"sceneDirectorManualSceneID", @"") ?: @"";
        NSDictionary *runtimeContext = readValue(@"sceneDirectorLastRuntimeContext", @{});
        if (![runtimeContext isKindOfClass:NSDictionary.class]) runtimeContext = @{};
        NSDictionary *resolvedScene = CCBGSceneDirectorResolvedScene(runtimeContext);
        NSString *automaticSceneID = [resolvedScene[@"id"] isKindOfClass:NSString.class] ? resolvedScene[@"id"] : @"";
        NSString *capturedSceneID = manualSceneID.length ? manualSceneID : automaticSceneID;
        snapshot[@"scene"] = @{
            @"id": capturedSceneID,
            @"mode": manualSceneID.length ? @"manual" : automaticSceneID.length ? @"automatic" : @"none",
            @"name": [resolvedScene[@"name"] isKindOfClass:NSString.class] ? resolvedScene[@"name"] : @"",
        };
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = NSLocale.currentLocale;
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterMediumStyle;
        NSDictionary *entry = @{
            @"time": @(timestamp), @"timestampMilliseconds": @((long long)llround(timestamp * 1000.0)),
            @"displayTime": [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"",
            @"event": eventCopy, @"details": detailsCopy, @"sceneID": capturedSceneID, @"snapshot": snapshot,
        };
        [timeline insertObject:entry atIndex:0];
        if (timeline.count > 60) [timeline removeObjectsInRange:NSMakeRange(60, timeline.count - 60)];
        CFPreferencesSetAppValue(CFSTR("sceneDirectorTimeline"), (__bridge CFArrayRef)timeline, domain);
        CFPreferencesAppSynchronize(domain);
    });
}

NSArray<NSDictionary *> *CCBGSceneTimeline(void) {
    __block NSArray<NSDictionary *> *result = @[];
    CCBGReadAnalyticsStateSynchronously(^{
        id timeline = CCBGReadPreference(@"sceneDirectorTimeline", @[]);
        if (![timeline isKindOfClass:NSArray.class]) return;
        NSMutableArray<NSDictionary *> *safeEntries = [NSMutableArray array];
        for (id entry in (NSArray *)timeline) {
            if ([entry isKindOfClass:NSDictionary.class]) [safeEntries addObject:entry];
        }
        result = safeEntries;
    });
    return result;
}

void CCBGReplaySceneTimelineEntry(NSDictionary *entry) {
    NSString *sceneID = [entry[@"sceneID"] isKindOfClass:NSString.class] ? entry[@"sceneID"] : @"";
    NSDictionary *snapshot = entry[@"snapshot"];
    NSDictionary *sceneSnapshot = [snapshot[@"scene"] isKindOfClass:NSDictionary.class] ? snapshot[@"scene"] : @{};
    NSString *snapshotSceneID = [sceneSnapshot[@"id"] isKindOfClass:NSString.class] ? sceneSnapshot[@"id"] : @"";
    if (snapshotSceneID.length) sceneID = snapshotSceneID;
    BOOL sceneExists = NO;
    for (NSDictionary *scene in CCBGSceneDirectorSortedScenes()) {
        if ([scene[@"id"] isEqualToString:sceneID]) { sceneExists = YES; break; }
    }
    NSMutableDictionary *changes = [@{
        @"sceneDirectorManualSceneID": sceneExists ? sceneID : @"",
        @"sceneDirectorReplayActive": @(sceneExists),
        @"sceneDirectorReplayEntryTime": entry[@"timestampMilliseconds"] ?: entry[@"time"] ?: @0,
    } mutableCopy];
    if ([snapshot isKindOfClass:NSDictionary.class]) {
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            NSDictionary *state = snapshot[[NSString stringWithFormat:@"module%ld", (long)slot]];
            if (![state isKindOfClass:NSDictionary.class]) continue;
            for (NSString *key in @[@"selectedMedia", @"currentMedia", @"playbackMode"]) {
                if (state[key]) changes[CCBGPreferenceKeyForModule(key, slot)] = state[key];
            }
            changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
        }
        NSDictionary *systemOverlays = snapshot[@"systemOverlays"];
        if ([systemOverlays isKindOfClass:NSDictionary.class]) [changes addEntriesFromDictionary:systemOverlays];
    }
    CCBGWritePreferences(changes);
    CCBGInvalidateSceneRuntimeCaches();
    CCBGPostPresentationRecovery();
    CCBGRecordSceneTimelineEvent(@"replay", @{ @"sceneID": sceneExists ? sceneID : @"", @"pinned": @(sceneExists) });
}

void CCBGExitSceneTimelineReplay(void) {
    CCBGWritePreferences(@{
        @"sceneDirectorManualSceneID": @"",
        @"sceneDirectorReplayActive": @NO,
        @"sceneDirectorReplayEntryTime": NSNull.null,
    });
    CCBGInvalidateSceneRuntimeCaches();
    CCBGPostPresentationRecovery();
    CCBGRecordSceneTimelineEvent(@"replay-ended", @{});
}

NSString *CCBGAutomationMediaName(NSArray<NSDictionary *> *catalog, BOOL charging, NSInteger slot) {
    NSString *(^validSelection)(NSString *) = ^NSString *(NSString *name) {
        return CCBGMediaItemNamed(catalog, name) ? name : nil;
    };
    if (NSProcessInfo.processInfo.lowPowerModeEnabled && [CCBGReadModulePreference(@"lowPowerAutomationEnabled", slot, @NO) boolValue]) {
        NSString *name = validSelection(CCBGReadModulePreference(@"lowPowerMedia", slot, @""));
        if (name.length) return name;
    }
    if (charging && [CCBGReadModulePreference(@"chargingAutomationEnabled", slot, @NO) boolValue]) {
        NSString *name = validSelection(CCBGReadModulePreference(@"chargingMedia", slot, @""));
        if (name.length) return name;
    }
    if ([CCBGReadModulePreference(@"darkModeAutomationEnabled", slot, @NO) boolValue]) {
        NSString *key = CCBGSystemUsesDarkAppearance() ? @"darkModeMedia" : @"lightModeMedia";
        NSString *name = validSelection(CCBGReadModulePreference(key, slot, @""));
        if (name.length) return name;
    }
    if ([CCBGReadModulePreference(@"weekdayAutomationEnabled", slot, @NO) boolValue]) {
        NSInteger weekday = [NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date];
        NSString *key = (weekday == 1 || weekday == 7) ? @"weekendMedia" : @"weekdayMedia";
        NSString *name = validSelection(CCBGReadModulePreference(key, slot, @""));
        if (name.length) return name;
    }
    if ([CCBGReadModulePreference(@"scheduleEnabled", slot, @NO) boolValue]) {
        NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:NSDate.date];
        NSInteger minutes = components.hour * 60 + components.minute;
        NSInteger dayStart = [CCBGReadModulePreference(@"dayStartMinutes", slot, @420) integerValue];
        NSInteger nightStart = [CCBGReadModulePreference(@"nightStartMinutes", slot, @1140) integerValue];
        BOOL day = dayStart <= nightStart
            ? (minutes >= dayStart && minutes < nightStart)
            : (minutes >= dayStart || minutes < nightStart);
        NSString *name = validSelection(CCBGReadModulePreference(day ? @"dayMedia" : @"nightMedia", slot, @""));
        if (name.length) return name;
    }
    return nil;
}

BOOL CCBGIsVideoName(NSString *name) {
    return [@[@"mp4", @"mov", @"m4v"] containsObject:name.pathExtension.lowercaseString];
}

static NSArray<NSString *> *CCBGScanMediaNamesWithReadability(BOOL *readable) {
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:CCBGMediaDirectoryPath
       withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:CCBGMediaDirectoryPath error:nil];
    if (readable) *readable = names != nil;
    if (!names) names = @[];
    NSMutableArray<NSString *> *supported = [NSMutableArray array];
    for (NSString *name in names) {
        if ([CCBGSupportedExtensions() containsObject:name.pathExtension.lowercaseString]) {
            [supported addObject:name];
        }
    }
    [supported sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return supported;
}

NSArray<NSString *> *CCBGScanMediaNames(void) {
    return CCBGScanMediaNamesWithReadability(NULL);
}

BOOL CCBGMediaDirectoryIsReadable(void) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (CCBGMediaCatalogCacheLock()) {
        if (CCBGMediaDirectoryReadableCacheAt > 0.0 &&
            now - CCBGMediaDirectoryReadableCacheAt < CCBGMediaCatalogCacheTTL) {
            return CCBGMediaDirectoryReadableCacheValue;
        }
    }
    BOOL readable = NO;
    CCBGScanMediaNamesWithReadability(&readable);
    @synchronized (CCBGMediaCatalogCacheLock()) {
        CCBGMediaDirectoryReadableCacheAt = NSProcessInfo.processInfo.systemUptime;
        CCBGMediaDirectoryReadableCacheValue = readable;
    }
    return readable;
}

NSDictionary *CCBGDefaultMediaItem(NSString *fileName) {
    return @{
        @"fileName": fileName,
        @"displayName": fileName.stringByDeletingPathExtension,
        @"enabled": @YES,
        @"favorite": @NO,
        @"group": @"",
        @"tags": @[],
        @"validFrom": @0,
        @"validUntil": @0,
        @"playCount": @0,
        @"lastPlayedAt": @0,
        @"failureReason": @"",
        @"fileHash": @"",
        @"fileSize": @0,
        @"fileModifiedAt": @0,
        @"dominantColor": @"",
        @"coverFrameTime": @0.0,
        @"addedAt": @0,
        @"healthSuccessfulStarts": @0,
        @"healthFailureCount": @0,
        @"healthAverageFirstFrameLatency": @0,
        @"healthAveragePlaybackDuration": @0,
        @"healthMemoryPressureCount": @0,
        @"healthStatus": @"未检测",
    };
}

NSArray<NSString *> *CCBGModuleMediaConfigurationKeys(void) {
    return @[
        @"randomWeight", @"mute", @"loop", @"playbackRate", @"startTime", @"endTime",
        @"contentMode", @"blurIntensity", @"dim", @"saturation", @"contrast", @"opacity",
        @"focalX", @"focalY", @"imageDuration", @"videoAdvancePolicy", @"videoPlayCount",
        @"compactContentMode", @"expandedContentMode", @"compactFocalX", @"compactFocalY",
        @"expandedFocalX", @"expandedFocalY", @"compactCropZoom", @"expandedCropZoom",
        @"portraitContentMode", @"landscapeContentMode", @"portraitFocalX", @"portraitFocalY",
        @"landscapeFocalX", @"landscapeFocalY", @"autoColor",
    ];
}

NSArray<NSString *> *CCBGModuleMediaReferenceKeys(void) {
    return @[
        @"selectedMedia", @"currentMedia", @"dayMedia", @"nightMedia", @"lightModeMedia", @"darkModeMedia",
        @"weekdayMedia", @"weekendMedia", @"lowPowerMedia", @"chargingMedia",
        @"privacyMedia", @"portraitMedia", @"landscapeMedia", @"defaultOverrideMedia", @"fallbackMediaChains",
    ];
}

NSArray<NSString *> *CCBGSystemMediaReferenceKeys(void) {
    NSMutableArray<NSString *> *keys = [@[
        @"connectivityOverlayMedia", @"connectivityOverlayCompactMedia",
        @"connectivityOverlayExpandedMedia", @"connectivityOverlayCompactCurrentMedia",
        @"connectivityOverlayExpandedCurrentMedia", @"connectivityOverlayWiFiMedia",
        @"connectivityOverlayCellularMedia", @"connectivityOverlayOfflineMedia",
        @"connectivityOverlayCompactSequentialCurrentMedia", @"connectivityOverlayExpandedSequentialCurrentMedia",
        @"connectivityOverlayCompactRandomCurrentMedia", @"connectivityOverlayExpandedRandomCurrentMedia",
        @"musicOverlayMedia", @"musicOverlayCompactMedia", @"musicOverlayExpandedMedia",
        @"musicOverlayCompactCurrentMedia", @"musicOverlayExpandedCurrentMedia",
        @"musicOverlayCompactSequentialCurrentMedia", @"musicOverlayExpandedSequentialCurrentMedia",
        @"musicOverlayCompactRandomCurrentMedia", @"musicOverlayExpandedRandomCurrentMedia",
        @"brightnessOverlayCompactMedia", @"brightnessOverlayExpandedMedia",
        @"brightnessOverlayCompactSequentialCurrentMedia", @"brightnessOverlayExpandedSequentialCurrentMedia",
        @"brightnessOverlayCompactRandomCurrentMedia", @"brightnessOverlayExpandedRandomCurrentMedia",
        @"volumeOverlayCompactMedia", @"volumeOverlayExpandedMedia",
        @"volumeOverlayCompactSequentialCurrentMedia", @"volumeOverlayExpandedSequentialCurrentMedia",
        @"volumeOverlayCompactRandomCurrentMedia", @"volumeOverlayExpandedRandomCurrentMedia",
    ] mutableCopy];
    for (NSString *prefix in @[@"connectivityOverlay", @"musicOverlay", @"brightnessOverlay", @"volumeOverlay"]) {
        for (NSString *suffix in @[@"CompactContentMode", @"ExpandedContentMode", @"CompactFocalX", @"CompactFocalY",
            @"ExpandedFocalX", @"ExpandedFocalY", @"CompactCropZoom", @"ExpandedCropZoom"]) {
            [keys addObject:[prefix stringByAppendingString:suffix]];
        }
    }
    id genericModules = CCBGReadPreference(@"customSystemOverlayModules", @[]);
    if ([genericModules isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)genericModules) {
            if (![value isKindOfClass:NSDictionary.class]) continue;
            NSString *prefix = [value[@"prefix"] isKindOfClass:NSString.class] ? value[@"prefix"] : @"";
            if (!prefix.length) continue;
            for (NSString *suffix in @[@"Enabled", @"SupportsExpanded", @"StateActive", @"StateOffMedia", @"StateOnMedia",
                @"CompactMedia", @"ExpandedMedia", @"CompactContentMode", @"ExpandedContentMode", @"ContentMode",
                @"CompactFocalX", @"CompactFocalY", @"ExpandedFocalX", @"ExpandedFocalY", @"CompactCropZoom", @"ExpandedCropZoom",
                @"CompactSequentialCurrentMedia", @"ExpandedSequentialCurrentMedia", @"CompactRandomCurrentMedia", @"ExpandedRandomCurrentMedia",
                @"CompactPlaylist", @"ExpandedPlaylist", @"LongPressEnabled", @"Opacity", @"Blur", @"Dim"]) {
                [keys addObject:[prefix stringByAppendingString:suffix]];
            }
        }
    }
    return keys;
}

NSDictionary *CCBGMediaItemForModule(NSDictionary *item, NSInteger slot) {
    return CCBGMediaItemsForModule(item ? @[item] : @[], slot).firstObject;
}

NSArray<NSDictionary *> *CCBGMediaItemsForModule(NSArray<NSDictionary *> *items, NSInteger slot) {
    NSDictionary *stored = slot >= 0 ? CCBGReadModulePreference(@"mediaOverrides", slot, @{}) : @{};
    NSDictionary *overrides = [stored isKindOfClass:NSDictionary.class] ? stored : @{};
    NSMutableArray<NSDictionary *> *effectiveItems = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *effective = [CCBGDefaultMediaConfiguration() mutableCopy];
        [effective addEntriesFromDictionary:item];
        NSDictionary *configuration = overrides[item[@"fileName"]];
        if ([configuration isKindOfClass:NSDictionary.class]) [effective addEntriesFromDictionary:configuration];
        [effectiveItems addObject:effective];
    }
    return effectiveItems;
}

void CCBGSaveModuleMediaConfiguration(NSDictionary *item, NSInteger slot) {
    NSString *fileName = item[@"fileName"];
    if (!fileName.length || slot < 0) return;
    NSDictionary *stored = CCBGReadModulePreference(@"mediaOverrides", slot, @{});
    NSMutableDictionary *overrides = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];
    NSDictionary *defaults = CCBGDefaultMediaConfiguration();
    for (NSString *key in CCBGModuleMediaConfigurationKeys()) configuration[key] = item[key] ?: defaults[key];
    overrides[fileName] = configuration;
    CCBGWriteModulePreference(@"mediaOverrides", slot, overrides);
}

void CCBGResetModuleMediaConfiguration(NSString *fileName, NSInteger slot) {
    if (!fileName.length || slot < 0) return;
    NSDictionary *stored = CCBGReadModulePreference(@"mediaOverrides", slot, @{});
    if (![stored isKindOfClass:NSDictionary.class] || !stored[fileName]) return;
    NSMutableDictionary *overrides = [stored mutableCopy];
    [overrides removeObjectForKey:fileName];
    CCBGWriteModulePreference(@"mediaOverrides", slot, overrides);
}

static id CCBGRemovingReference(id value, NSString *fileName) {
    if ([value isKindOfClass:NSString.class]) return [value isEqualToString:fileName] ? nil : value;
    if ([value isKindOfClass:NSArray.class]) { NSMutableArray *result = [NSMutableArray array]; for (id item in value) { id kept = CCBGRemovingReference(item, fileName); if (kept) [result addObject:kept]; } return result; }
    if ([value isKindOfClass:NSDictionary.class]) { NSMutableDictionary *result = [NSMutableDictionary dictionary]; [value enumerateKeysAndObjectsUsingBlock:^(id key, id item, BOOL *stop) { if ([key isKindOfClass:NSString.class] && [key isEqualToString:fileName]) return; id kept = CCBGRemovingReference(item, fileName); if (kept) result[key] = kept; }]; return result; }
    return value;
}

void CCBGRemoveMediaConfigurationFromAllModules(NSString *fileName) {
    if (!fileName.length) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    __block BOOL changed = NO;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        CFArrayRef allKeysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSArray *allKeys = CFBridgingRelease(allKeysRef) ?: @[];
        for (NSString *key in allKeys) {
            if ([key isEqualToString:@"mediaCatalog"]) continue;
            CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
            id value = CFBridgingRelease(valueRef);
            id cleaned = CCBGRemovingReference(value, fileName);
            if ((value && !cleaned) || (cleaned && ![cleaned isEqual:value])) { CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)cleaned, domain); changed = YES; }
        }
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            NSString *overridesKey = CCBGPreferenceKeyForModule(@"mediaOverrides", slot);
            CFPropertyListRef storedRef = CFPreferencesCopyAppValue((__bridge CFStringRef)overridesKey, domain);
            NSDictionary *stored = CFBridgingRelease(storedRef);
            if ([stored isKindOfClass:NSDictionary.class] && stored[fileName]) {
                NSMutableDictionary *overrides = [stored mutableCopy];
                [overrides removeObjectForKey:fileName];
                CFPreferencesSetAppValue((__bridge CFStringRef)overridesKey, (__bridge CFDictionaryRef)overrides, domain);
                changed = YES;
            }
            for (NSString *referenceKey in CCBGModuleMediaReferenceKeys()) {
                NSString *key = CCBGPreferenceKeyForModule(referenceKey, slot);
                CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
                id value = CFBridgingRelease(valueRef);
                if ([value isKindOfClass:NSString.class] && [value isEqualToString:fileName]) {
                    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
                    changed = YES;
                }
            }
        }
        for (NSString *key in CCBGSystemMediaReferenceKeys()) {
            CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
            id value = CFBridgingRelease(valueRef);
            if ([value isKindOfClass:NSString.class] && [value isEqualToString:fileName]) {
                CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
                changed = YES;
            }
        }
        CFPreferencesAppSynchronize(domain);
    });
    if (changed) {
        CCBGInvalidatePreferenceReadCache();
        CCBGPostReload();
    }
}

void CCBGRemoveAllMediaConfigurations(void) {
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(@"mediaOverrides", slot), NULL, domain);
            for (NSString *referenceKey in CCBGModuleMediaReferenceKeys()) {
                CFPreferencesSetAppValue((__bridge CFStringRef)CCBGPreferenceKeyForModule(referenceKey, slot), NULL, domain);
            }
        }
        for (NSString *key in CCBGSystemMediaReferenceKeys()) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
        }
        CFPreferencesAppSynchronize(domain);
    });
    CCBGInvalidatePreferenceReadCache();
    CCBGPostReload();
}

void CCBGPruneMissingMediaConfigurations(void) {
    // A manual index rebuild is the explicit escape hatch for files changed
    // outside the App (for example through Filza), so bypass the App snapshot
    // before scanning the directory.
    @synchronized (CCBGMediaCatalogCacheLock()) {
        CCBGMediaCatalogCache = nil;
        CCBGMediaCatalogCacheTimestamp = 0.0;
        CCBGMediaDirectoryReadableCacheAt = 0.0;
        CCBGMediaStorageBytesCache = nil;
    }
    if (!CCBGMediaDirectoryIsReadable()) return;
    NSSet<NSString *> *validNames = [NSSet setWithArray:CCBGScanMediaNames()];
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    __block BOOL changed = NO;
    CCBGWithFileLock(CCBGPreferencesMutationLockPath, ^{
        CFPreferencesAppSynchronize(domain);
        for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
            NSString *overridesKey = CCBGPreferenceKeyForModule(@"mediaOverrides", slot);
            CFPropertyListRef storedRef = CFPreferencesCopyAppValue((__bridge CFStringRef)overridesKey, domain);
            NSDictionary *stored = CFBridgingRelease(storedRef);
            if ([stored isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
                [stored enumerateKeysAndObjectsUsingBlock:^(NSString *fileName, id value, BOOL *stop) {
                    if ([validNames containsObject:fileName]) filtered[fileName] = value;
                }];
                if (filtered.count != stored.count) {
                    CFPreferencesSetAppValue((__bridge CFStringRef)overridesKey, (__bridge CFDictionaryRef)filtered, domain);
                    changed = YES;
                }
            }
            for (NSString *referenceKey in CCBGModuleMediaReferenceKeys()) {
                NSString *key = CCBGPreferenceKeyForModule(referenceKey, slot);
                CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
                id value = CFBridgingRelease(valueRef);
                if ([value isKindOfClass:NSString.class] && [value length] && ![validNames containsObject:value]) {
                    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
                    changed = YES;
                }
            }
        }
        for (NSString *key in CCBGSystemMediaReferenceKeys()) {
            CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
            id value = CFBridgingRelease(valueRef);
            if ([value isKindOfClass:NSString.class] && [value length] && ![validNames containsObject:value]) {
                CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
                changed = YES;
            }
        }
        CFPreferencesAppSynchronize(domain);
    });
    if (changed) {
        CCBGInvalidatePreferenceReadCache();
        CCBGPostReload();
    }
}

NSArray<NSDictionary *> *CCBGLoadMediaCatalog(void) {
    NSArray<NSDictionary *> *cached = CCBGMediaCatalogCachedValue();
    if (cached) return cached;
    NSArray *stored = CCBGReadPreference(@"mediaCatalog", @[]);
    if (![stored isKindOfClass:NSArray.class]) stored = @[];
    BOOL directoryReadable = NO;
    NSArray<NSString *> *names = CCBGScanMediaNamesWithReadability(&directoryReadable);
    @synchronized (CCBGMediaCatalogCacheLock()) {
        CCBGMediaDirectoryReadableCacheAt = NSProcessInfo.processInfo.systemUptime;
        CCBGMediaDirectoryReadableCacheValue = directoryReadable;
    }
    NSSet<NSString *> *nameSet = [NSSet setWithArray:names];
    BOOL directoryUnavailable = !directoryReadable && stored.count > 0;
    NSMutableDictionary<NSString *, NSDictionary *> *byName = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *orderedNames = [NSMutableArray array];
    for (id candidate in stored) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        NSString *name = candidate[@"fileName"];
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        if (!byName[name]) [orderedNames addObject:name];
        byName[name] = candidate;
    }
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSString *name in orderedNames) {
        if (![nameSet containsObject:name] && !directoryUnavailable) continue;
        NSMutableDictionary *merged = [CCBGDefaultMediaItem(name) mutableCopy];
        [merged addEntriesFromDictionary:byName[name]];
        [merged removeObjectsForKeys:CCBGModuleMediaConfigurationKeys()];
        merged[@"fileName"] = name;
        [result addObject:merged];
    }
    for (NSString *name in names) {
        if (!byName[name]) [result addObject:CCBGDefaultMediaItem(name)];
    }
    NSArray<NSDictionary *> *snapshot = [result copy];
    @synchronized (CCBGMediaCatalogCacheLock()) {
        CCBGMediaCatalogCache = snapshot;
        CCBGMediaCatalogCacheTimestamp = NSProcessInfo.processInfo.systemUptime;
    }
    return snapshot;
}

void CCBGSaveMediaCatalog(NSArray<NSDictionary *> *catalog) {
    NSArray<NSDictionary *> *catalogCopy = [catalog copy] ?: @[];
    CCBGWithAnalyticsMutationLock(^{
        NSArray *stored = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableDictionary *runtimeByName = [NSMutableDictionary dictionary];
        for (NSDictionary *item in stored) if ([item[@"fileName"] isKindOfClass:NSString.class]) runtimeByName[item[@"fileName"]] = item;
        NSArray<NSString *> *runtimeKeys = @[
            @"playCount", @"lastPlayedAt", @"healthSuccessfulStarts", @"healthFirstFrameSamples",
            @"healthTotalFirstFrameLatency", @"healthAverageFirstFrameLatency", @"healthMaxFirstFrameLatency",
            @"healthPlaybackSessions", @"healthPlaybackSeconds", @"healthAveragePlaybackDuration",
            @"healthMemoryPressureCount", @"healthLastMemoryPressureAt", @"healthFailureCount",
            @"healthLastFailureAt", @"healthLastFailureReason", @"healthStatus",
        ];
        NSMutableArray *mergedCatalog = [NSMutableArray array];
        for (NSDictionary *item in catalogCopy) {
            NSMutableDictionary *merged = [item mutableCopy];
            NSDictionary *runtime = runtimeByName[item[@"fileName"]];
            for (NSString *key in runtimeKeys) if (runtime[key]) merged[key] = runtime[key];
            if ([runtime[@"failureReason"] length] && ![merged[@"failureReason"] length]) merged[@"failureReason"] = runtime[@"failureReason"];
            [mergedCatalog addObject:merged];
        }
        CCBGWritePreference(@"mediaCatalog", mergedCatalog);
    });
}

NSDictionary *CCBGMediaItemNamed(NSArray<NSDictionary *> *catalog, NSString *fileName) {
    if (!fileName.length) return nil;
    for (NSDictionary *item in catalog) {
        if ([item[@"fileName"] isEqualToString:fileName]) return item;
    }
    return nil;
}

NSString *CCBGDisplayNameForItem(NSDictionary *item) {
    NSString *displayName = item[@"displayName"];
    return displayName.length ? displayName : item[@"fileName"] ?: @"";
}

static NSCache<NSString *, AVAsset *> *CCBGVideoOnlyAssetCache(void) {
    static NSCache<NSString *, AVAsset *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 24;
    });
    return cache;
}

static NSMutableDictionary<NSString *, NSMutableArray *> *CCBGPendingVideoOnlyAssetLoads(void) {
    static NSMutableDictionary<NSString *, NSMutableArray *> *pendingLoads;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ pendingLoads = [NSMutableDictionary dictionary]; });
    return pendingLoads;
}

static dispatch_queue_t CCBGVideoOnlyExportQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.video-only-export", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static void CCBGFinishVideoOnlyAssetLoad(NSString *cacheKey, AVAsset *asset, NSError *error) {
    NSArray *callbacks = nil;
    @synchronized (CCBGPendingVideoOnlyAssetLoads()) {
        if (asset) [CCBGVideoOnlyAssetCache() setObject:asset forKey:cacheKey];
        callbacks = [CCBGPendingVideoOnlyAssetLoads()[cacheKey] copy];
        [CCBGPendingVideoOnlyAssetLoads() removeObjectForKey:cacheKey];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (id callbackValue in callbacks) {
            void (^callback)(AVAsset *, NSError *) = (void (^)(AVAsset *, NSError *))callbackValue;
            callback(asset, error);
        }
    });
}

static NSString *CCBGVideoOnlyAssetCacheKey(NSString *path) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [NSString stringWithFormat:@"%@|%@|%.3f", path ?: @"", attributes[NSFileSize] ?: @0,
            [attributes[NSFileModificationDate] timeIntervalSince1970]];
}

static NSString *CCBGVideoOnlyCacheBasePath(NSString *cacheKey) {
    NSData *data = [cacheKey dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [hash appendFormat:@"%02x", digest[index]];
    NSString *directory = @"/var/mobile/Library/CleanCCBG2x2/VideoOnlyCache";
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:hash];
}

static void CCBGRemoveVideoOnlyDiskCache(NSString *cacheBasePath) {
    if (!cacheBasePath.length) return;
    NSFileManager *fileManager = NSFileManager.defaultManager;
    @synchronized (fileManager) {
        for (NSString *extension in @[@"mp4", @"mov"]) {
            [fileManager removeItemAtPath:[cacheBasePath stringByAppendingPathExtension:extension] error:nil];
        }
        NSString *directory = cacheBasePath.stringByDeletingLastPathComponent;
        NSString *temporaryPrefix = [cacheBasePath.lastPathComponent stringByAppendingString:@"-"];
        for (NSString *name in [fileManager contentsOfDirectoryAtPath:directory error:nil] ?: @[]) {
            if ([name hasPrefix:temporaryPrefix]) {
                [fileManager removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
            }
        }
    }
}

static void CCBGValidateVideoOnlyAsset(AVAsset *asset, void (^completion)(BOOL valid, NSError *error)) {
    if (!completion) return;
    if (!asset) {
        NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:8
                                         userInfo:@{NSLocalizedDescriptionKey: @"Video-only asset is missing"}];
        completion(NO, error);
        return;
    }
    NSArray<NSString *> *keys = @[@"playable", @"tracks", @"duration"];
    NSObject *completionGate = [NSObject new];
    __block BOOL completed = NO;
    void (^finish)(BOOL, NSError *) = ^(BOOL valid, NSError *error) {
        @synchronized (completionGate) {
            if (completed) return;
            completed = YES;
        }
        completion(valid, error);
    };
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
        NSError *loadError = nil;
        BOOL keysLoaded = YES;
        for (NSString *key in keys) {
            if ([asset statusOfValueForKey:key error:&loadError] != AVKeyValueStatusLoaded) {
                keysLoaded = NO;
                break;
            }
        }
        AVAssetTrack *videoTrack = keysLoaded ? [asset tracksWithMediaType:AVMediaTypeVideo].firstObject : nil;
        CMTime duration = asset.duration;
        BOOL durationValid = CMTIME_IS_NUMERIC(duration) && CMTimeCompare(duration, kCMTimeZero) > 0;
        BOOL valid = keysLoaded && asset.playable && videoTrack != nil && durationValid;
        NSError *error = valid ? nil : (loadError ?: [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:9
            userInfo:@{NSLocalizedDescriptionKey: @"Video-only cache is not playable"}]);
        finish(valid, error);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:10
                                         userInfo:@{NSLocalizedDescriptionKey: @"Video-only validation timed out"}];
        finish(NO, error);
    });
}

void CCBGInvalidateVideoOnlyAssetMemoryCache(NSString *path) {
    if (!path.length) return;
    NSString *cacheKey = CCBGVideoOnlyAssetCacheKey(path);
    @synchronized (CCBGPendingVideoOnlyAssetLoads()) {
        [CCBGVideoOnlyAssetCache() removeObjectForKey:cacheKey];
    }
}

void CCBGInvalidateVideoOnlyAssetCache(NSString *path) {
    if (!path.length) return;
    NSString *cacheKey = CCBGVideoOnlyAssetCacheKey(path);
    BOOL loadInProgress = NO;
    @synchronized (CCBGPendingVideoOnlyAssetLoads()) {
        [CCBGVideoOnlyAssetCache() removeObjectForKey:cacheKey];
        loadInProgress = CCBGPendingVideoOnlyAssetLoads()[cacheKey] != nil;
    }
    if (!loadInProgress) CCBGRemoveVideoOnlyDiskCache(CCBGVideoOnlyCacheBasePath(cacheKey));
}

static void CCBGExportVideoOnlyAsset(NSString *path, NSString *cacheKey, NSString *cacheBasePath) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path]
                                                  options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
    CCBGValidateVideoOnlyAsset(sourceAsset, ^(BOOL sourceValid, NSError *loadError) {
        AVAssetTrack *sourceVideoTrack = [sourceAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        if (!sourceValid || !sourceVideoTrack) {
            NSError *error = loadError ?: [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:2
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Video track is unavailable"}];
            CCBGFinishVideoOnlyAssetLoad(cacheKey, nil, error);
            return;
        }

        AVMutableComposition *composition = [AVMutableComposition composition];
        AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                         preferredTrackID:kCMPersistentTrackID_Invalid];
        CMTimeRange timeRange = sourceVideoTrack.timeRange;
        if (!CMTIMERANGE_IS_VALID(timeRange) || CMTIME_IS_INDEFINITE(timeRange.duration) || CMTimeCompare(timeRange.duration, kCMTimeZero) <= 0) {
            timeRange = CMTimeRangeMake(kCMTimeZero, sourceAsset.duration);
        }
        NSError *insertError = nil;
        BOOL inserted = [videoTrack insertTimeRange:timeRange ofTrack:sourceVideoTrack atTime:kCMTimeZero error:&insertError];
        if (!inserted) {
            NSError *error = insertError ?: [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:3
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Video track could not be isolated"}];
            CCBGFinishVideoOnlyAssetLoad(cacheKey, nil, error);
            return;
        }
        videoTrack.preferredTransform = sourceVideoTrack.preferredTransform;
        CGSize naturalSize = CGSizeApplyAffineTransform(sourceVideoTrack.naturalSize, sourceVideoTrack.preferredTransform);
        naturalSize = CGSizeMake(fabs(naturalSize.width), fabs(naturalSize.height));
        if (naturalSize.width > 0 && naturalSize.height > 0) composition.naturalSize = naturalSize;

        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
        if (!exportSession) {
            NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:4
                                             userInfo:@{NSLocalizedDescriptionKey: @"Video-only export is unavailable"}];
            CCBGFinishVideoOnlyAssetLoad(cacheKey, nil, error);
            return;
        }
        AVFileType outputType = [exportSession.supportedFileTypes containsObject:AVFileTypeMPEG4]
            ? AVFileTypeMPEG4
            : ([exportSession.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie] ? AVFileTypeQuickTimeMovie : nil);
        if (!outputType) {
            NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:5
                                             userInfo:@{NSLocalizedDescriptionKey: @"Video-only output format is unavailable"}];
            CCBGFinishVideoOnlyAssetLoad(cacheKey, nil, error);
            return;
        }
        NSString *extension = [outputType isEqualToString:AVFileTypeMPEG4] ? @"mp4" : @"mov";
        NSString *finalPath = [cacheBasePath stringByAppendingPathExtension:extension];
        NSString *temporaryName = [NSString stringWithFormat:@"%@-%@.%@", cacheBasePath.lastPathComponent,
                                   NSUUID.UUID.UUIDString, extension];
        NSString *temporaryPath = [cacheBasePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:temporaryName];
        NSURL *temporaryURL = [NSURL fileURLWithPath:temporaryPath];
        exportSession.outputURL = temporaryURL;
        exportSession.outputFileType = outputType;
        exportSession.shouldOptimizeForNetworkUse = YES;
        dispatch_async(CCBGVideoOnlyExportQueue(), ^{
            dispatch_semaphore_t finished = dispatch_semaphore_create(0);
            NSObject *completionLock = [NSObject new];
            __block BOOL completionFinished = NO;
            __block BOOL exportCallbackStarted = NO;
            void (^finishOnce)(AVAsset *, NSError *) = ^(AVAsset *asset, NSError *error) {
                BOOL shouldFinish = NO;
                @synchronized (completionLock) {
                    if (!completionFinished) {
                        completionFinished = YES;
                        shouldFinish = YES;
                    }
                }
                if (!shouldFinish) return;
                CCBGFinishVideoOnlyAssetLoad(cacheKey, asset, error);
                dispatch_semaphore_signal(finished);
            };
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                @synchronized (completionLock) {
                    if (exportCallbackStarted || completionFinished) return;
                    exportCallbackStarted = YES;
                }
                if (exportSession.status != AVAssetExportSessionStatusCompleted) {
                    [fileManager removeItemAtPath:temporaryPath error:nil];
                    NSError *error = exportSession.error ?: [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:6
                                                                             userInfo:@{NSLocalizedDescriptionKey: @"Video-only export failed"}];
                    finishOnce(nil, error);
                    return;
                }
                __block NSError *moveError = nil;
                @synchronized (fileManager) {
                    if ([fileManager fileExistsAtPath:finalPath]) {
                        [fileManager removeItemAtPath:temporaryPath error:nil];
                    } else if (![fileManager moveItemAtPath:temporaryPath toPath:finalPath error:&moveError]) {
                        [fileManager removeItemAtPath:temporaryPath error:nil];
                    }
                }
                if (moveError && ![fileManager fileExistsAtPath:finalPath]) {
                    finishOnce(nil, moveError);
                    return;
                }
                NSURL *outputURL = [NSURL fileURLWithPath:finalPath];
                AVURLAsset *fileAsset = [AVURLAsset URLAssetWithURL:outputURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
                CCBGValidateVideoOnlyAsset(fileAsset, ^(BOOL valid, NSError *validationError) {
                    if (!valid) [fileManager removeItemAtPath:finalPath error:nil];
                    finishOnce(valid ? fileAsset : nil, validationError);
                });
            }];
            // BUGFIX: bound the wait instead of DISPATCH_TIME_FOREVER. 45s is
            // generously above any normal passthrough export of a background
            // video clip; if the completion handler still hasn't fired by
            // then, cancel the session and finish with a timeout error so the
            // serial export queue is never stuck indefinitely.
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45.0 * NSEC_PER_SEC));
            if (dispatch_semaphore_wait(finished, timeout) != 0) {
                [exportSession cancelExport];
                [fileManager removeItemAtPath:temporaryPath error:nil];
                NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:7
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Video-only export timed out"}];
                finishOnce(nil, error);
            }
        });
    });
}

void CCBGLoadVideoOnlyAsset(NSString *path, void (^completion)(AVAsset *asset, NSError *error)) {
    if (!completion) return;
    if (!path.length) {
        NSError *error = [NSError errorWithDomain:@"com.zjc.cleanccbg2x2.video" code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Video path is empty"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
        return;
    }
    NSString *cacheKey = CCBGVideoOnlyAssetCacheKey(path);
    @synchronized (CCBGPendingVideoOnlyAssetLoads()) {
        AVAsset *cachedAsset = [CCBGVideoOnlyAssetCache() objectForKey:cacheKey];
        if (cachedAsset) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(cachedAsset, nil); });
            return;
        }
        NSMutableArray *callbacks = CCBGPendingVideoOnlyAssetLoads()[cacheKey];
        if (callbacks) {
            [callbacks addObject:[completion copy]];
            return;
        }
        CCBGPendingVideoOnlyAssetLoads()[cacheKey] = [NSMutableArray arrayWithObject:[completion copy]];
    }

    NSString *cacheBasePath = CCBGVideoOnlyCacheBasePath(cacheKey);
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *cachedPath = nil;
    for (NSString *extension in @[@"mp4", @"mov"]) {
        NSString *candidatePath = [cacheBasePath stringByAppendingPathExtension:extension];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:candidatePath error:nil];
        if ([attributes[NSFileSize] unsignedLongLongValue] > 0) {
            cachedPath = candidatePath;
            break;
        }
    }
    if (!cachedPath.length) {
        CCBGExportVideoOnlyAsset(path, cacheKey, cacheBasePath);
        return;
    }

    NSURL *outputURL = [NSURL fileURLWithPath:cachedPath];
    AVURLAsset *fileAsset = [AVURLAsset URLAssetWithURL:outputURL options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
    CCBGValidateVideoOnlyAsset(fileAsset, ^(BOOL valid, NSError *error) {
        if (valid) {
            CCBGFinishVideoOnlyAssetLoad(cacheKey, fileAsset, nil);
            return;
        }
        CCBGRemoveVideoOnlyDiskCache(cacheBasePath);
        CCBGExportVideoOnlyAsset(path, cacheKey, cacheBasePath);
    });
}

NSString *CCBGPathForItem(NSDictionary *item) {
    NSString *fileName = [item[@"fileName"] isKindOfClass:NSString.class] ? item[@"fileName"] : nil;
    if (!fileName.length || [fileName isEqualToString:@"."] || [fileName isEqualToString:@".."] ||
        ![fileName.lastPathComponent isEqualToString:fileName]) return nil;
    NSString *basePath = [CCBGMediaDirectoryPath stringByStandardizingPath];
    NSString *candidatePath = [[basePath stringByAppendingPathComponent:fileName] stringByStandardizingPath];
    NSString *allowedPrefix = [basePath stringByAppendingString:@"/"];
    return [candidatePath hasPrefix:allowedPrefix] ? candidatePath : nil;
}

unsigned long long CCBGMediaStorageBytes(void) {
    if (CCBGPreferenceReadCacheAllowed()) {
        @synchronized (CCBGMediaCatalogCacheLock()) {
            if (CCBGMediaStorageBytesCache) return CCBGMediaStorageBytesCache.unsignedLongLongValue;
        }
    }
    unsigned long long total = 0;
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *name in CCBGScanMediaNames()) {
        NSDictionary *attributes = [manager attributesOfItemAtPath:[CCBGMediaDirectoryPath stringByAppendingPathComponent:name] error:nil];
        total += [attributes[NSFileSize] unsignedLongLongValue];
    }
    if (CCBGPreferenceReadCacheAllowed()) {
        @synchronized (CCBGMediaCatalogCacheLock()) {
            CCBGMediaStorageBytesCache = @(total);
        }
    }
    return total;
}

BOOL CCBGMediaItemIsCurrentlyEligible(NSDictionary *item) {
    if (![item[@"enabled"] boolValue]) return NO;
    if ([item[@"failureReason"] isKindOfClass:NSString.class] && [item[@"failureReason"] length]) return NO;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval validFrom = [item[@"validFrom"] doubleValue];
    NSTimeInterval validUntil = [item[@"validUntil"] doubleValue];
    if (validFrom > 0 && now < validFrom) return NO;
    if (validUntil > 0 && now > validUntil) return NO;
    return YES;
}

static NSString *CCBGMediaHealthStatus(NSDictionary *item) {
    NSUInteger starts = [item[@"healthSuccessfulStarts"] unsignedIntegerValue];
    NSUInteger failures = [item[@"healthFailureCount"] unsignedIntegerValue];
    NSUInteger memoryWarnings = [item[@"healthMemoryPressureCount"] unsignedIntegerValue];
    NSTimeInterval averageLatency = [item[@"healthAverageFirstFrameLatency"] doubleValue];
    CGFloat failureRatio = failures / (CGFloat)MAX((NSUInteger)1, starts + failures);
    if ((failures >= 3 && failureRatio >= 0.25) || averageLatency >= 2.0 || memoryWarnings >= 4) return @"不推荐";
    if (failures || averageLatency >= 0.8 || memoryWarnings) return @"需关注";
    return starts ? @"良好" : @"未检测";
}

static void CCBGSaveHealthCatalog(NSMutableArray *catalog, NSUInteger index, NSMutableDictionary *item) {
    item[@"healthStatus"] = CCBGMediaHealthStatus(item);
    catalog[index] = item;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetAppValue(CFSTR("mediaCatalog"), (__bridge CFArrayRef)catalog, domain);
    CFPreferencesAppSynchronize(domain);
}

void CCBGRecordMediaPlaybackStart(NSString *fileName, NSInteger slot, NSTimeInterval firstFrameLatency) {
    if (!fileName.length) return;
    NSString *fileNameCopy = [fileName copy];
    CCBGEnqueueAnalyticsMutation(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        if (!catalog) catalog = [NSMutableArray array];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return [item[@"fileName"] isEqualToString:fileNameCopy];
        }];
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
        if (index != NSNotFound) {
            NSMutableDictionary *item = [catalog[index] mutableCopy];
            item[@"playCount"] = @([item[@"playCount"] unsignedLongLongValue] + 1);
            item[@"lastPlayedAt"] = @(now);
            item[@"healthSuccessfulStarts"] = @([item[@"healthSuccessfulStarts"] unsignedLongLongValue] + 1);
            if (isfinite(firstFrameLatency) && firstFrameLatency >= 0) {
                NSUInteger samples = [item[@"healthFirstFrameSamples"] unsignedIntegerValue] + 1;
                NSTimeInterval total = [item[@"healthTotalFirstFrameLatency"] doubleValue] + firstFrameLatency;
                item[@"healthFirstFrameSamples"] = @(samples);
                item[@"healthTotalFirstFrameLatency"] = @(total);
                item[@"healthAverageFirstFrameLatency"] = @(total / samples);
                item[@"healthMaxFirstFrameLatency"] = @(MAX(firstFrameLatency, [item[@"healthMaxFirstFrameLatency"] doubleValue]));
            }
            CCBGSaveHealthCatalog(catalog, index, item);
        }
        if (slot < 0) return;
        NSString *recentKey = CCBGPreferenceKeyForModule(@"recentMedia", slot);
        NSArray *storedRecent = CCBGReadPreference(recentKey, @[]);
        NSMutableArray *recent = [storedRecent isKindOfClass:NSArray.class] ? [storedRecent mutableCopy] : [NSMutableArray array];
        [recent removeObject:fileNameCopy];
        [recent insertObject:fileNameCopy atIndex:0];
        while (recent.count > 50) [recent removeLastObject];
        CFPreferencesSetAppValue((__bridge CFStringRef)recentKey, (__bridge CFArrayRef)recent, domain);
        NSString *historyKey = CCBGPreferenceKeyForModule(@"playbackHistory", slot);
        NSArray *storedHistory = CCBGReadPreference(historyKey, @[]);
        NSMutableArray *history = [storedHistory isKindOfClass:NSArray.class] ? [storedHistory mutableCopy] : [NSMutableArray array];
        [history insertObject:@{@"fileName": fileNameCopy, @"playedAt": @(now)} atIndex:0];
        while (history.count > 100) [history removeLastObject];
        CFPreferencesSetAppValue((__bridge CFStringRef)historyKey, (__bridge CFArrayRef)history, domain);
        CFPreferencesAppSynchronize(domain);
    });
    CCBGRecordSceneTimelineEvent(@"playback-start", @{ @"media": fileNameCopy, @"slot": @(slot), @"firstFrameLatency": @(MAX(0.0, firstFrameLatency)) });
}

void CCBGRecordMediaPlaybackDuration(NSString *fileName, NSTimeInterval duration) {
    if (!fileName.length || !isfinite(duration) || duration < 0.25) return;
    NSString *fileNameCopy = [fileName copy];
    CCBGEnqueueAnalyticsMutation(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"fileName"] isEqualToString:fileNameCopy]; }];
        if (index == NSNotFound) return;
        NSMutableDictionary *item = [catalog[index] mutableCopy];
        NSUInteger sessions = [item[@"healthPlaybackSessions"] unsignedIntegerValue] + 1;
        NSTimeInterval total = [item[@"healthPlaybackSeconds"] doubleValue] + duration;
        item[@"healthPlaybackSessions"] = @(sessions);
        item[@"healthPlaybackSeconds"] = @(total);
        item[@"healthAveragePlaybackDuration"] = @(total / sessions);
        CCBGSaveHealthCatalog(catalog, index, item);
    });
}

void CCBGRecordMediaMemoryPressure(NSString *fileName) {
    if (!fileName.length) return;
    NSString *fileNameCopy = [fileName copy];
    CCBGEnqueueAnalyticsMutation(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"fileName"] isEqualToString:fileNameCopy]; }];
        if (index == NSNotFound) return;
        NSMutableDictionary *item = [catalog[index] mutableCopy];
        item[@"healthMemoryPressureCount"] = @([item[@"healthMemoryPressureCount"] unsignedIntegerValue] + 1);
        item[@"healthLastMemoryPressureAt"] = @(NSDate.date.timeIntervalSince1970);
        CCBGSaveHealthCatalog(catalog, index, item);
    });
}

void CCBGRecordMediaPlaybackFailure(NSString *fileName, NSString *reason) {
    if (!fileName.length) return;
    NSString *fileNameCopy = [fileName copy];
    NSString *reasonCopy = [reason copy] ?: @"";
    CCBGEnqueueAnalyticsMutation(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"fileName"] isEqualToString:fileNameCopy]; }];
        if (index == NSNotFound) return;
        NSMutableDictionary *item = [catalog[index] mutableCopy];
        item[@"healthFailureCount"] = @([item[@"healthFailureCount"] unsignedLongLongValue] + 1);
        item[@"healthLastFailureAt"] = @(NSDate.date.timeIntervalSince1970);
        item[@"healthLastFailureReason"] = reasonCopy;
        CCBGSaveHealthCatalog(catalog, index, item);
    });
    CCBGRecordSceneTimelineEvent(@"playback-failure", @{ @"media": fileNameCopy, @"reason": reasonCopy });
}

// A decode failure is delivered on the AVFoundation/SpringBoard path. Never
// wait for the cross-process analytics lock there: the immediate caller has
// already detached the bad item, while this serial mutation persists its
// quarantine and posts the reload only after the catalog is durable.
static void CCBGSetMediaFailureAsync(NSString *fileName, NSString *reason) {
    if (!fileName.length) return;
    NSString *fileNameCopy = [fileName copy];
    NSString *reasonCopy = [reason copy] ?: @"";
    CCBGEnqueueAnalyticsMutation(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        if (!catalog) catalog = [NSMutableArray array];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return [item[@"fileName"] isEqualToString:fileNameCopy];
        }];
        BOOL updated = NO;
        if (index != NSNotFound) {
            NSMutableDictionary *item = [catalog[index] mutableCopy];
            item[@"failureReason"] = reasonCopy;
            if (reasonCopy.length) {
                item[@"healthFailureCount"] = @([item[@"healthFailureCount"] unsignedLongLongValue] + 1);
                item[@"healthLastFailureAt"] = @(NSDate.date.timeIntervalSince1970);
                item[@"healthLastFailureReason"] = reasonCopy;
            }
            CCBGSaveHealthCatalog(catalog, index, item);
            updated = YES;
        }
        if (updated && reasonCopy.length) {
            CCBGRecordSceneTimelineEvent(@"playback-failure", @{ @"media": fileNameCopy, @"reason": reasonCopy });
        }
        dispatch_async(dispatch_get_main_queue(), ^{ CCBGPostReload(); });
    });
}

static void CCBGSetMediaFailure(NSString *fileName, NSString *reason) {
    if (!fileName.length) return;
    NSString *fileNameCopy = [fileName copy];
    NSString *reasonCopy = [reason copy] ?: @"";
    __block BOOL updated = NO;
    CCBGWithAnalyticsMutationLock(^{
        id storedCatalog = CCBGReadPreference(@"mediaCatalog", @[]);
        NSMutableArray *catalog = [storedCatalog isKindOfClass:NSArray.class] ? [storedCatalog mutableCopy] : [CCBGLoadMediaCatalog() mutableCopy];
        NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
            return [item[@"fileName"] isEqualToString:fileNameCopy];
        }];
        if (index == NSNotFound) return;
        NSMutableDictionary *item = [catalog[index] mutableCopy];
        item[@"failureReason"] = reasonCopy;
        CCBGSaveHealthCatalog(catalog, index, item);
        updated = YES;
    });
    if (updated && reasonCopy.length) CCBGRecordMediaPlaybackFailure(fileNameCopy, reasonCopy);
}

void CCBGMarkMediaFailure(NSString *fileName, NSString *reason) {
    CCBGSetMediaFailureAsync(fileName, reason.length ? reason : @"无法解码");
}

void CCBGClearMediaFailure(NSString *fileName) {
    CCBGSetMediaFailure(fileName, @"");
}

NSString *CCBGSHA256ForFileAtPath(NSString *path) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!stream) return @"";
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024];
    NSInteger length = 0;
    while ((length = [stream read:buffer maxLength:sizeof(buffer)]) > 0) CC_SHA256_Update(&context, buffer, (CC_LONG)length);
    [stream close];
    if (length < 0) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}

static NSString *CCBGDominantColorHexForCGImage(CGImageRef image) {
    if (!image) return @"";
    uint8_t pixel[4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return @"";
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image);
    CGContextRelease(context);
    return [NSString stringWithFormat:@"#%02X%02X%02X", pixel[0], pixel[1], pixel[2]];
}

NSString *CCBGDominantColorHexForImageAtPath(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path ?: @""];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return @"";
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @32,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    NSString *hex = CCBGDominantColorHexForCGImage(image);
    if (image) CGImageRelease(image);
    return hex;
}

NSString *CCBGDominantColorHexForMediaAtPath(NSString *path) {
    if (!CCBGIsVideoName(path.lastPathComponent)) return CCBGDominantColorHexForImageAtPath(path);
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path ?: @""] options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(96, 96);
    NSTimeInterval duration = CMTimeGetSeconds(asset.duration);
    NSTimeInterval seconds = isfinite(duration) && duration > 0 ? MIN(1.0, duration * 0.33) : 0.0;
    NSError *error = nil;
    CGImageRef image = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(seconds, 600) actualTime:NULL error:&error];
    NSString *hex = CCBGDominantColorHexForCGImage(image);
    if (image) CGImageRelease(image);
    return hex;
}

static id CCBGReplacingReference(id value, NSString *oldName, NSString *newName) {
    if ([value isKindOfClass:NSString.class]) return [value isEqualToString:oldName] ? newName : value;
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:[value count]];
        for (id item in value) [result addObject:CCBGReplacingReference(item, oldName, newName) ?: NSNull.null];
        return result;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[value count]];
        [value enumerateKeysAndObjectsUsingBlock:^(id key, id item, BOOL *stop) {
            id replacedKey = [key isKindOfClass:NSString.class] && [key isEqualToString:oldName] ? newName : key;
            result[replacedKey] = CCBGReplacingReference(item, oldName, newName) ?: NSNull.null;
        }];
        return result;
    }
    return value;
}

void CCBGReplaceMediaReferences(NSString *oldName, NSString *newName) {
    if (!oldName.length || !newName.length || [oldName isEqualToString:newName]) return;
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFArrayRef keysRef = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSArray *keys = CFBridgingRelease(keysRef) ?: @[];
    for (NSString *key in keys) {
        if ([key isEqualToString:@"mediaCatalog"]) continue;
        CFPropertyListRef valueRef = CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
        id value = CFBridgingRelease(valueRef);
        id replaced = CCBGReplacingReference(value, oldName, newName);
        if (replaced && ![replaced isEqual:value]) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)replaced, domain);
        }
    }
    CFPreferencesAppSynchronize(domain);
    CCBGPostReload();
}
