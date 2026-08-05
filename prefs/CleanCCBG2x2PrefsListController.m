#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

static CFStringRef const CCBGDomain = CFSTR("com.zjc.cleanccbg2x2");
static CFStringRef const CCBGReloadNotification = CFSTR("com.zjc.cleanccbg2x2/reload");
static NSString *const CCBGMediaDirectory = @"/var/mobile/Library/CleanCCBG2x2/Media";

@interface CleanCCBG2x2PrefsListController : PSListController <UIDocumentPickerDelegate>
@property(nonatomic, strong) NSArray *specifiers;
@end

@implementation CleanCCBG2x2PrefsListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Clean";
    self.view.tintColor = [UIColor colorWithRed:0.12 green:0.45 blue:0.92 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithDefaultBackground];
        appearance.backgroundColor = UIColor.systemBackgroundColor;
        appearance.shadowColor = UIColor.clearColor;
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        CCBGDomain
    );
    CFPreferencesAppSynchronize(CCBGDomain);
    [self postReload];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(CCBGDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        CCBGDomain
    );
    return value ? CFBridgingRelease(value) : [specifier propertyForKey:@"default"];
}

- (void)postReload {
    CFPreferencesAppSynchronize(CCBGDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CCBGReloadNotification,
        NULL,
        NULL,
        true
    );
}

- (void)ensureMediaDirectory {
    [[NSFileManager defaultManager] createDirectoryAtPath:CCBGMediaDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)chooseMedia {
    [self ensureMediaDirectory];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeImage, UTTypeMovie] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self ensureMediaDirectory];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger index = 0;
    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSString *extension = url.pathExtension.lowercaseString.length ? url.pathExtension.lowercaseString : @"dat";
        NSString *name = [NSString stringWithFormat:@"media-%0.f-%lu.%@", NSDate.date.timeIntervalSince1970 * 1000.0, (unsigned long)index++, extension];
        NSString *destination = [CCBGMediaDirectory stringByAppendingPathComponent:name];
        [manager removeItemAtPath:destination error:nil];
        [manager copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:nil];
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
    [self postReload];
}

- (void)clearMedia {
    [self ensureMediaDirectory];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *name in [manager contentsOfDirectoryAtPath:CCBGMediaDirectory error:nil]) {
        [manager removeItemAtPath:[CCBGMediaDirectory stringByAppendingPathComponent:name] error:nil];
    }
    [self postReload];
}

- (void)forceReload { [self postReload]; }

@end
