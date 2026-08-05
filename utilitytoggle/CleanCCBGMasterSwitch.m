#import <UIKit/UIKit.h>
#import "CCBGMediaCatalog.h"

typedef struct {
    NSUInteger width;
    NSUInteger height;
} CCUILayoutSize;

@protocol CCUIContentModule <NSObject>
@property(nonatomic, readonly) UIViewController *contentViewController;
@property(nonatomic, readonly) UIViewController *backgroundViewController;
@optional
- (BOOL)_canShowWhileLocked;
- (void)controlCenterModuleDidReceiveTap;
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation;
@end

@interface CleanCCBGMasterSwitchViewController : UIViewController
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *stateLabel;
@property(nonatomic, strong) UIVisualEffectView *materialView;
@property(nonatomic) NSTimeInterval lastToggleAt;
- (void)togglePlugin;
@end

@implementation CleanCCBGMasterSwitchViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.view.layer.cornerRadius = 18.0;
    self.view.layer.borderWidth = 0.6;
    self.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.view.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) self.view.layer.cornerCurve = kCACornerCurveContinuous;

    self.materialView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.materialView.frame = self.view.bounds;
    self.materialView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.materialView.userInteractionEnabled = NO;
    self.materialView.alpha = 0.88;
    [self.view addSubview:self.materialView];

    self.iconView = [UIImageView new];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.iconView];

    self.stateLabel = [UILabel new];
    self.stateLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.stateLabel.textAlignment = NSTextAlignmentCenter;
    self.stateLabel.textColor = UIColor.whiteColor;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stateLabel];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.accessibilityLabel = @"CleanCCBG master switch";
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:@selector(togglePlugin) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-7.0],
        [self.iconView.widthAnchor constraintEqualToConstant:30.0],
        [self.iconView.heightAnchor constraintEqualToConstant:30.0],
        [self.stateLabel.topAnchor constraintEqualToAnchor:self.iconView.bottomAnchor constant:1.0],
        [self.stateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [button.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [button.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self updateAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateAppearance];
}

- (void)updateAppearance {
    BOOL enabled = CCBGPluginEnabled();
    UIColor *accent = enabled ? [UIColor colorWithRed:0.18 green:0.72 blue:0.42 alpha:1.0] : [UIColor colorWithWhite:0.56 alpha:1.0];
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.12 : 0.20
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.view.backgroundColor = [accent colorWithAlphaComponent:0.18];
        self.iconView.tintColor = accent;
        self.stateLabel.textColor = accent;
    } completion:nil];
    [UIView transitionWithView:self.iconView
                      duration:UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.16
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState
                    animations:^{ self.iconView.image = [UIImage systemImageNamed:enabled ? @"power.circle.fill" : @"power.circle"]; }
                    completion:nil];
    self.stateLabel.text = enabled ? @"ON" : @"OFF";
}

- (void)togglePlugin {
    // Depending on the iOS 16 Control Center host, one physical tap can be
    // delivered both to the embedded UIButton and to
    // controlCenterModuleDidReceiveTap. Coalesce that event so the switch
    // cannot toggle twice and end in its previous state.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - self.lastToggleAt < 0.24) return;
    self.lastToggleAt = now;
    BOOL enabled = !CCBGPluginEnabled();
    CCBGSetPluginEnabled(enabled);
    [self updateAppearance];
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

- (BOOL)_canShowWhileLocked { return YES; }
- (BOOL)providesOwnPlatter { return YES; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }
- (CGFloat)preferredExpandedContentWidth { return 160.0; }
- (CGFloat)preferredExpandedContentHeight { return 160.0; }
@end

@interface CleanCCBGMasterSwitchModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) CleanCCBGMasterSwitchViewController *controller;
@end

@implementation CleanCCBGMasterSwitchModule
- (instancetype)init {
    self = [super init];
    if (self) _controller = [CleanCCBGMasterSwitchViewController new];
    return self;
}
- (UIViewController *)contentViewController { return self.controller; }
- (UIViewController *)backgroundViewController { return nil; }
- (BOOL)_canShowWhileLocked { return YES; }
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation { return (CCUILayoutSize){1, 1}; }
- (void)controlCenterModuleDidReceiveTap { [self.controller togglePlugin]; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }
- (CGFloat)preferredExpandedContentWidth { return self.controller.preferredExpandedContentWidth; }
- (CGFloat)preferredExpandedContentHeight { return self.controller.preferredExpandedContentHeight; }
@end
