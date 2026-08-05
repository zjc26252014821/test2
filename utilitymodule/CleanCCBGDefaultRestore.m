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
- (BOOL)shouldBeginTransitionToExpandedContentModule;
@end

@interface CleanCCBGDefaultRestoreViewController : UIViewController
@property(nonatomic, strong) UIImageView *compactIcon;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIStackView *actionStack;
@property(nonatomic, strong) UIVisualEffectView *materialView;
@property(nonatomic) BOOL batchActionPending;
@property(nonatomic) BOOL recoveryPending;
@property(nonatomic) NSUInteger transitionGeneration;
- (void)setExpanded:(BOOL)expanded;
@end

@implementation CleanCCBGDefaultRestoreViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.13 green:0.16 blue:0.19 alpha:1.0];
    self.view.layer.cornerRadius = 18;
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

    self.compactIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]];
    self.compactIcon.tintColor = UIColor.whiteColor;
    self.compactIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.compactIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.compactIcon];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"五模块素材";
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    UIButton *apply = [self actionButtonWithTitle:@"应用默认" image:@"checkmark.circle.fill" selector:@selector(applyDefault)];
    UIButton *restore = [self actionButtonWithTitle:@"恢复" image:@"arrow.uturn.backward.circle.fill" selector:@selector(restorePrevious)];
    self.actionStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, apply, restore]];
    self.actionStack.axis = UILayoutConstraintAxisVertical;
    self.actionStack.spacing = 12.0;
    self.actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionStack.hidden = YES;
    [self.view addSubview:self.actionStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.compactIcon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.compactIcon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.compactIcon.widthAnchor constraintEqualToConstant:32],
        [self.compactIcon.heightAnchor constraintEqualToConstant:32],
        [self.actionStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.actionStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.actionStack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title image:(NSString *)imageName selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:imageName];
    configuration.imagePadding = 8.0;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.baseBackgroundColor = [UIColor colorWithRed:0.16 green:0.46 blue:0.92 alpha:0.92];
    configuration.baseForegroundColor = UIColor.whiteColor;
    button.configuration = configuration;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:48.0].active = YES;
    return button;
}

- (void)setExpanded:(BOOL)expanded {
    NSUInteger generation = ++self.transitionGeneration;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    if (expanded) {
        self.actionStack.hidden = NO;
        self.actionStack.alpha = 0.0;
        self.actionStack.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
    } else {
        self.compactIcon.hidden = NO;
        self.compactIcon.alpha = 0.0;
        self.compactIcon.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.94, 0.94);
    }
    [UIView animateWithDuration:reduceMotion ? 0.14 : 0.22
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.compactIcon.alpha = expanded ? 0.0 : 1.0;
        self.compactIcon.transform = CGAffineTransformIdentity;
        self.actionStack.alpha = expanded ? 1.0 : 0.0;
        self.actionStack.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        if (generation != self.transitionGeneration) return;
        self.compactIcon.hidden = expanded;
        self.actionStack.hidden = !expanded;
    }];
}

- (void)applyDefault {
    [self performBatchAction:NO];
}

- (void)restorePrevious {
    [self performBatchAction:YES];
}

- (void)performBatchAction:(BOOL)restore {
    if (self.batchActionPending) return;
    self.batchActionPending = YES;
    BOOL success = restore ? CCBGRestoreFiveModuleMedia() : CCBGApplyFiveModuleDefaultMedia();
    self.batchActionPending = NO;
    if (success) self.recoveryPending = YES;
    UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
    [feedback notificationOccurred:success ? UINotificationFeedbackTypeSuccess : (restore ? UINotificationFeedbackTypeWarning : UINotificationFeedbackTypeError)];
}

- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return 320.0; }
- (CGFloat)preferredExpandedContentHeight { return 230.0; }
- (void)willTransitionToExpandedContentMode:(BOOL)expanded { [self setExpanded:expanded]; }
- (void)didTransitionToExpandedContentMode:(BOOL)expanded {
    [self setExpanded:expanded];
    if (!expanded && self.recoveryPending) {
        self.recoveryPending = NO;
        CCBGRecordModuleLifecycleEvent(-1, @"control-center-batch-collapse-recovery", nil);
        CCBGPostPresentationRecovery();
    }
}
- (BOOL)_canShowWhileLocked { return YES; }
- (BOOL)providesOwnPlatter { return YES; }

@end

@interface CleanCCBGDefaultRestoreModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) CleanCCBGDefaultRestoreViewController *controller;
@end

@implementation CleanCCBGDefaultRestoreModule
- (instancetype)init {
    self = [super init];
    if (self) _controller = [CleanCCBGDefaultRestoreViewController new];
    return self;
}
- (UIViewController *)contentViewController { return self.controller; }
- (UIViewController *)backgroundViewController { return nil; }
- (BOOL)_canShowWhileLocked { return YES; }
- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation { return (CCUILayoutSize){1, 1}; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return YES; }
- (CGFloat)preferredExpandedContentWidth { return self.controller.preferredExpandedContentWidth; }
- (CGFloat)preferredExpandedContentHeight { return self.controller.preferredExpandedContentHeight; }
@end
