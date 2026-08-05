#import <UIKit/UIKit.h>

@interface CCBGRootController : UITableViewController
@end
@interface CCBGMainTabBarController : UITabBarController
@end
@interface CCBGDashboardController : UITableViewController
@end
@interface CCBGModuleWorkspaceController : UITableViewController
@end
@interface CCBGMoreController : UITableViewController
@end
@interface CCBGQuickConfigController : UITableViewController
@end
@interface CCBGShortcutActionsController : UITableViewController
@end
@interface CCBGVisualThemesController : UITableViewController
@end
@interface CCBGVisualStylePresetsController : UITableViewController
@end
@interface CCBGCompositionEditorController : UIViewController
- (instancetype)initWithMediaItem:(NSDictionary *)item moduleSlot:(NSInteger)slot;
- (instancetype)initWithSystemMediaItem:(NSDictionary *)item
                        preferencePrefix:(NSString *)prefix
                      compactAspectRatio:(CGFloat)compactAspectRatio
                     expandedAspectRatio:(CGFloat)expandedAspectRatio;
- (void)setInitialExpandedMode:(BOOL)expanded;
@end

@interface CCBGMediaDetailController : UITableViewController
- (instancetype)initWithMediaItem:(NSDictionary *)item;
@end

@interface CCBGPreviewController : UIViewController
- (instancetype)initWithMediaItem:(NSDictionary *)item;
@end

@interface CCBGPlaybackSettingsController : UITableViewController
@end
@interface CCBGGestureSettingsController : UITableViewController
@end

@interface CCBGModuleManagerController : UITableViewController
@end

@interface CCBGAppearanceController : UITableViewController
@end

@interface CCBGAutomationController : UITableViewController
@end

@interface CCBGSystemModulesController : UITableViewController
- (instancetype)initWithOverlayIndex:(NSInteger)overlayIndex;
- (instancetype)initWithGenericModule:(NSDictionary *)module;
@end
@interface CCBGGenericSystemModulesController : UITableViewController
@end
@interface CCBGFiveModuleDefaultController : UITableViewController
@end

@interface CCBGDiagnosticsController : UITableViewController
@end
@interface CCBGBackupTimelineController : UITableViewController
@end

@interface CCBGLibraryInsightsController : UITableViewController
@end
@interface CCBGGroupedLibraryController : UITableViewController
@end
@interface CCBGBatchEditController : UITableViewController
@end
@interface CCBGPlaylistController : UITableViewController
@end
@interface CCBGStatusDashboardController : UITableViewController
@end
@interface CCBGAdaptationPreviewController : UIViewController
- (instancetype)initWithMediaItem:(NSDictionary *)item;
@end
@interface CCBGProfilesController : UITableViewController
@end
@interface CCBGModuleAppearanceController : UITableViewController
@end
@interface CCBGAdvancedAutomationController : UITableViewController
@end
@interface CCBGAutomationPriorityController : UITableViewController
@end
@interface CCBGSceneDirectorController : UITableViewController
@end
@interface CCBGSceneEditorController : UITableViewController
- (instancetype)initWithScene:(NSDictionary *)scene;
@end
