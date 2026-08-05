#import <UIKit/UIKit.h>
#import "CCBGMediaCatalog.h"

typedef struct { NSUInteger width; NSUInteger height; } CCUILayoutSize;

@protocol CCUIContentModule <NSObject>
@property(nonatomic, readonly) UIViewController *contentViewController;
@property(nonatomic, readonly) UIViewController *backgroundViewController;
@optional
- (BOOL)_canShowWhileLocked;
- (void)controlCenterModuleDidReceiveTap;
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation;
- (BOOL)shouldBeginTransitionToExpandedContentModule;
@end

static NSString *CCBGThemeSwitcherDisplayName(NSDictionary *theme) {
    NSString *name = [theme[@"name"] isKindOfClass:NSString.class] ? theme[@"name"] : @"";
    if (!name.length) return @"主题";
    return name.length > 4 ? [name substringToIndex:4] : name;
}

@interface CleanCCBGThemeSwitcherViewController : UIViewController
@property(nonatomic, strong) UIImageView *compactIcon;
@property(nonatomic, strong) UILabel *compactLabel;
@property(nonatomic, strong) UIStackView *themeStack;
@property(nonatomic, strong) UIVisualEffectView *materialView;
@property(nonatomic) NSUInteger transitionGeneration;
- (void)cycleTheme;
- (void)setExpanded:(BOOL)expanded;
@end

@implementation CleanCCBGThemeSwitcherViewController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadThemes];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.12 green:0.18 blue:0.22 alpha:1.0];
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

    self.compactIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"paintpalette.fill"]];
    self.compactIcon.tintColor = UIColor.whiteColor;
    self.compactIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.compactIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.compactIcon];
    self.compactLabel = [UILabel new];
    self.compactLabel.textColor = UIColor.whiteColor;
    self.compactLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.compactLabel.textAlignment = NSTextAlignmentCenter;
    self.compactLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.compactLabel];
    self.themeStack = [UIStackView new];
    self.themeStack.axis = UILayoutConstraintAxisVertical;
    self.themeStack.spacing = 8.0;
    self.themeStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.themeStack.hidden = YES;
    [self.view addSubview:self.themeStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.compactIcon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.compactIcon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-7],
        [self.compactIcon.widthAnchor constraintEqualToConstant:30],
        [self.compactIcon.heightAnchor constraintEqualToConstant:30],
        [self.compactLabel.topAnchor constraintEqualToAnchor:self.compactIcon.bottomAnchor constant:1],
        [self.compactLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.themeStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [self.themeStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [self.themeStack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    [self reloadThemes];
}
- (NSArray<NSDictionary *> *)visibleThemes {
    NSMutableArray *pinned = [NSMutableArray array];
    NSMutableArray *enabled = [NSMutableArray array];
    for (NSDictionary *theme in CCBGVisualThemes()) {
        if (![theme[@"enabled"] boolValue]) continue;
        [enabled addObject:theme];
        if ([theme[@"pinned"] boolValue]) [pinned addObject:theme];
    }
    NSArray *source = pinned.count ? pinned : enabled;
    return source.count > 4 ? [source subarrayWithRange:NSMakeRange(0, 4)] : source;
}
- (UIButton *)buttonWithTitle:(NSString *)title identifier:(NSString *)identifier random:(BOOL)random {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:random ? @"dice" : @"paintpalette"];
    configuration.imagePadding = 8;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.baseBackgroundColor = [UIColor colorWithRed:0.16 green:0.46 blue:0.92 alpha:0.92];
    configuration.baseForegroundColor = UIColor.whiteColor;
    button.configuration = configuration;
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:random ? @selector(applyRandom:) : @selector(applyTheme:) forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:42].active = YES;
    return button;
}
- (void)reloadThemes {
    for (UIView *view in self.themeStack.arrangedSubviews) { [self.themeStack removeArrangedSubview:view]; [view removeFromSuperview]; }
    UILabel *title = [UILabel new]; title.text = @"视觉主题"; title.textColor = UIColor.whiteColor; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; title.textAlignment = NSTextAlignmentCenter; [self.themeStack addArrangedSubview:title];
    for (NSDictionary *theme in [self visibleThemes]) [self.themeStack addArrangedSubview:[self buttonWithTitle:theme[@"name"] ?: @"未命名" identifier:theme[@"id"] random:NO]];
    [self.themeStack addArrangedSubview:[self buttonWithTitle:@"随机主题" identifier:@"" random:YES]];
    NSString *activeID = CCBGReadPreference(@"activeVisualThemeID", @"");
    NSDictionary *active = nil;
    for (NSDictionary *theme in CCBGVisualThemes()) if ([theme[@"id"] isEqualToString:activeID]) { active = theme; break; }
    self.compactLabel.text = active ? CCBGThemeSwitcherDisplayName(active) : @"主题";
}
- (void)applyTheme:(UIButton *)sender { if (CCBGApplyVisualTheme(sender.accessibilityIdentifier)) { [self reloadThemes]; [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess]; } }
- (void)applyRandom:(UIButton *)sender { if (CCBGApplyRandomVisualTheme()) { [self reloadThemes]; [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess]; } }
- (void)cycleTheme { NSArray *themes = [self visibleThemes]; if (!themes.count) { [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning]; return; } NSString *active = CCBGReadPreference(@"activeVisualThemeID", @""); NSUInteger index = [themes indexOfObjectPassingTest:^BOOL(NSDictionary *theme, NSUInteger idx, BOOL *stop) { return [theme[@"id"] isEqualToString:active]; }]; NSUInteger next = index == NSNotFound ? 0 : (index + 1) % themes.count; BOOL applied = CCBGApplyVisualTheme(themes[next][@"id"]); [self reloadThemes]; [[UINotificationFeedbackGenerator new] notificationOccurred:applied ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeWarning]; }
- (void)setExpanded:(BOOL)expanded {
    NSUInteger generation = ++self.transitionGeneration;
    if (expanded) [self reloadThemes];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    if (expanded) {
        self.themeStack.hidden = NO;
        self.themeStack.alpha = 0.0;
        self.themeStack.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
    } else {
        self.compactIcon.hidden = NO;
        self.compactLabel.hidden = NO;
        self.compactIcon.alpha = 0.0;
        self.compactLabel.alpha = 0.0;
    }
    [UIView animateWithDuration:reduceMotion ? 0.14 : 0.22
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.compactIcon.alpha = expanded ? 0.0 : 1.0;
        self.compactLabel.alpha = expanded ? 0.0 : 1.0;
        self.themeStack.alpha = expanded ? 1.0 : 0.0;
        self.themeStack.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        if (generation != self.transitionGeneration) return;
        self.compactIcon.hidden = expanded;
        self.compactLabel.hidden = expanded;
        self.themeStack.hidden = !expanded;
    }];
}
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return 320; }
- (CGFloat)preferredExpandedContentHeight { return 330; }
- (void)willTransitionToExpandedContentMode:(BOOL)expanded { [self setExpanded:expanded]; }
- (void)didTransitionToExpandedContentMode:(BOOL)expanded { [self setExpanded:expanded]; }
- (BOOL)_canShowWhileLocked { return YES; }
- (BOOL)providesOwnPlatter { return YES; }
@end

@interface CleanCCBGThemeSwitcherModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) CleanCCBGThemeSwitcherViewController *controller;
@end

@implementation CleanCCBGThemeSwitcherModule
- (instancetype)init { self = [super init]; if (self) _controller = [CleanCCBGThemeSwitcherViewController new]; return self; }
- (UIViewController *)contentViewController { return self.controller; }
- (UIViewController *)backgroundViewController { return nil; }
- (BOOL)_canShowWhileLocked { return YES; }
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation { return (CCUILayoutSize){1, 1}; }
- (void)controlCenterModuleDidReceiveTap { [self.controller cycleTheme]; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return self.controller.preferredExpandedContentWidth; }
- (CGFloat)preferredExpandedContentHeight { return self.controller.preferredExpandedContentHeight; }
@end
