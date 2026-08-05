#import <UIKit/UIKit.h>
#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"

@interface CCBGRootController (Shortcuts)
- (void)showImportOptions;
@end

@interface CCBGAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation CCBGAppDelegate

- (void)reloadVisibleTableViewsInView:(UIView *)view {
    if ([view isKindOfClass:UITableView.class]) {
        // Hidden tab and navigation stacks can remain in the window tree.
        // Repainting every row on activation needlessly rebuilds cells and
        // thumbnails, so refresh only mounted, visible rows. Fall back to a
        // full reload only when UIKit has not created any visible rows yet.
        UITableView *table = (UITableView *)view;
        if (view.window && !view.hidden && view.alpha > 0.01) {
            NSMutableArray<NSIndexPath *> *validRows = [NSMutableArray array];
            for (NSIndexPath *indexPath in table.indexPathsForVisibleRows ?: @[]) {
                if (indexPath.section < [table numberOfSections] && indexPath.row < [table numberOfRowsInSection:indexPath.section]) {
                    [validRows addObject:indexPath];
                }
            }
            if (validRows.count) [table reloadRowsAtIndexPaths:validRows withRowAnimation:UITableViewRowAnimationNone];
            else [table reloadData];
        }
        return;
    }
    if (view.hidden || view.alpha <= 0.01) return;
    for (UIView *subview in view.subviews) [self reloadVisibleTableViewsInView:subview];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    CCBGMigrateLegacyAutomationPreferences();
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [CCBGMainTabBarController new];
    CCBGApplyAppTheme(self.window);
    [self.window makeKeyAndVisible];
    application.shortcutItems = @[
        [[UIApplicationShortcutItem alloc] initWithType:@"com.zjc.cleanccbg.import" localizedTitle:@"导入素材" localizedSubtitle:nil icon:[UIApplicationShortcutIcon iconWithSystemImageName:@"plus"] userInfo:nil],
        [[UIApplicationShortcutItem alloc] initWithType:@"com.zjc.cleanccbg.profile" localizedTitle:@"切换配置方案" localizedSubtitle:nil icon:[UIApplicationShortcutIcon iconWithSystemImageName:@"arrow.triangle.2.circlepath"] userInfo:nil],
        [[UIApplicationShortcutItem alloc] initWithType:@"com.zjc.cleanccbg.theme" localizedTitle:@"随机视觉主题" localizedSubtitle:nil icon:[UIApplicationShortcutIcon iconWithSystemImageName:@"dice"] userInfo:nil],
        [[UIApplicationShortcutItem alloc] initWithType:@"com.zjc.cleanccbg.rebuild" localizedTitle:@"重建素材索引" localizedSubtitle:nil icon:[UIApplicationShortcutIcon iconWithSystemImageName:@"arrow.clockwise"] userInfo:nil],
    ];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // SpringBoard can change currentMedia while this App is inactive. Clear
    // the App-only snapshot before visible preview cells query preferences.
    CCBGInvalidatePreferenceReadCache();
    [self reloadVisibleTableViewsInView:self.window];
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    CCBGMainTabBarController *tabs = (CCBGMainTabBarController *)self.window.rootViewController;
    UINavigationController *libraryNavigation = tabs.viewControllers.count > 1 ? tabs.viewControllers[1] : nil;
    CCBGRootController *root = (CCBGRootController *)libraryNavigation.viewControllers.firstObject;
    if ([shortcutItem.type hasSuffix:@"import"]) {
        tabs.selectedIndex = 1;
        [root showImportOptions];
    } else if ([shortcutItem.type hasSuffix:@"rebuild"]) {
        CCBGPruneMissingMediaConfigurations();
        CCBGSaveMediaCatalog(CCBGLoadMediaCatalog());
    } else if ([shortcutItem.type hasSuffix:@"theme"]) {
        CCBGApplyRandomVisualTheme();
    } else if ([shortcutItem.type hasSuffix:@"profile"]) {
        NSArray *profiles = CCBGReadPreference(@"configurationProfiles", @[]);
        if (profiles.count) {
            NSInteger index = ([CCBGReadPreference(@"lastShortcutProfile", @-1) integerValue] + 1) % profiles.count;
            NSDictionary *preferences = profiles[(NSUInteger)index][@"preferences"];
            NSMutableDictionary *updated = [preferences mutableCopy] ?: [NSMutableDictionary dictionary];
            updated[@"lastShortcutProfile"] = @(index);
            CCBGWritePreferences(updated);
        }
    }
    completionHandler(YES);
}

- (BOOL)handleShortcutURL:(NSURL *)url {
    if (![[url.scheme lowercaseString] isEqualToString:@"cleanccbg"]) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) if (item.name.length) query[item.name] = item.value ?: @"";
    NSString *host = components.host.lowercaseString ?: @"";
    NSString *action = [components.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]].lowercaseString;

    if ([host isEqualToString:@"theme"] && [action isEqualToString:@"apply"]) {
        return CCBGApplyVisualTheme(query[@"id"]);
    }
    if ([host isEqualToString:@"theme"] && [action isEqualToString:@"random"]) {
        return CCBGApplyRandomVisualTheme();
    }
    if ([host isEqualToString:@"module"] && [action isEqualToString:@"media"]) {
        NSInteger slot = [query[@"slot"] integerValue];
        NSString *name = query[@"name"] ?: @"";
        if (slot < 0 || slot >= (NSInteger)CCBGModuleDisplayNames().count || !CCBGMediaItemNamed(CCBGLoadMediaCatalog(), name)) return NO;
        CCBGSelectModuleMedia(name, slot, YES);
        return YES;
    }
    if ([host isEqualToString:@"plugin"]) {
        NSString *state = action.length ? action : query[@"state"].lowercaseString;
        if ([state isEqualToString:@"toggle"]) CCBGSetPluginEnabled(!CCBGPluginEnabled());
        else if ([state isEqualToString:@"on"]) CCBGSetPluginEnabled(YES);
        else if ([state isEqualToString:@"off"]) CCBGSetPluginEnabled(NO);
        else return NO;
        return YES;
    }
    return NO;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    return [self handleShortcutURL:url];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CCBGAppDelegate.class));
    }
}
