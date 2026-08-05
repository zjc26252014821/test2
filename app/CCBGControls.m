#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import <objc/runtime.h>

NSArray<NSDictionary *> *CCBGAppThemeOptions(void) {
    static NSArray<NSDictionary *> *options;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        options = @[
            @{@"key": @"teal", @"name": @"青绿", @"color": UIColor.systemTealColor},
            @{@"key": @"blue", @"name": @"蓝色", @"color": UIColor.systemBlueColor},
            @{@"key": @"indigo", @"name": @"靛蓝", @"color": UIColor.systemIndigoColor},
            @{@"key": @"purple", @"name": @"紫色", @"color": UIColor.systemPurpleColor},
            @{@"key": @"pink", @"name": @"粉色", @"color": UIColor.systemPinkColor},
            @{@"key": @"red", @"name": @"红色", @"color": UIColor.systemRedColor},
            @{@"key": @"orange", @"name": @"橙色", @"color": UIColor.systemOrangeColor},
            @{@"key": @"green", @"name": @"绿色", @"color": UIColor.systemGreenColor},
        ];
    });
    return options;
}

UIColor *CCBGAppAccentColor(void) {
    static NSString *cachedKey;
    static UIColor *cachedColor;
    NSString *selectedKey = CCBGReadPreference(@"appAccentColor", @"teal");
    if (cachedColor && [cachedKey isEqualToString:selectedKey]) return cachedColor;
    for (NSDictionary *option in CCBGAppThemeOptions()) {
        if ([option[@"key"] isEqualToString:selectedKey]) {
            cachedKey = [selectedKey copy];
            cachedColor = option[@"color"];
            return cachedColor;
        }
    }
    cachedKey = @"teal";
    cachedColor = UIColor.systemTealColor;
    return cachedColor;
}

static UIColor *CCBGStyledAccentColor;
static char CCBGStyledAccentAssociationKey;
static void CCBGAnimateControlCellPress(UITableViewCell *cell, BOOL pressed, BOOL animated);

static void CCBGStyleControlCell(UITableViewCell *cell) {
    if (!cell) return;
    UIColor *accent = CCBGStyledAccentColor ?: CCBGAppAccentColor();
    BOOL alreadyStyled = cell.selectedBackgroundView != nil &&
        fabs(cell.contentView.layer.cornerRadius - 16.0) <= 0.01;
    UIColor *appliedAccent = objc_getAssociatedObject(cell, &CCBGStyledAccentAssociationKey);
    BOOL backgroundWasReinstalled = cell.backgroundView != nil;
    if (alreadyStyled && !backgroundWasReinstalled && appliedAccent == accent) {
        // Reused cells only need their palette refreshed. Avoid allocating a
        // new selectedBackgroundView and reapplying layer geometry on every
        // scroll pass.
        return;
    }
    // Inset-grouped tables install a private backgroundView that is square for
    // middle rows. Remove it so the rounded content surface below is the only
    // visible background for every row.
    cell.backgroundView = nil;
    cell.backgroundColor = UIColor.clearColor;
    if (fabs(cell.layer.cornerRadius - 16.0) > 0.01) cell.layer.cornerRadius = 16.0;
    cell.layer.masksToBounds = YES;
    cell.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.contentView.layer.cornerRadius = 16.0;
    cell.contentView.layer.masksToBounds = YES;
    cell.contentView.layer.borderWidth = 0.5;
    cell.contentView.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.18].CGColor;
    if (@available(iOS 13.0, *)) cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layoutMargins = UIEdgeInsetsMake(4.0, 0.0, 4.0, 0.0);
    UIView *selected = [[UIView alloc] initWithFrame:CGRectZero];
    selected.backgroundColor = [accent colorWithAlphaComponent:0.10];
    selected.layer.cornerRadius = 16.0;
    selected.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) selected.layer.cornerCurve = kCACornerCurveContinuous;
    cell.selectedBackgroundView = selected;
    objc_setAssociatedObject(cell, &CCBGStyledAccentAssociationKey, accent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// UIKit's inset-grouped table only rounds the first and last native rows.
// Most of this app uses ordinary UITableViewCell instances, so those rows
// otherwise remain square while custom control cells are rounded. Apply the
// same material after UIKit has laid out every app cell; the style helper is
// idempotent and reused cells only pay the cheap palette update.
@implementation UITableViewCell (CCBGRoundedAppCells)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(layoutSubviews));
        Method replacement = class_getInstanceMethod(self, @selector(ccbg_rounded_layoutSubviews));
        if (original && replacement) method_exchangeImplementations(original, replacement);
        Method originalHighlight = class_getInstanceMethod(self, @selector(setHighlighted:animated:));
        Method replacementHighlight = class_getInstanceMethod(self, @selector(ccbg_rounded_setHighlighted:animated:));
        if (originalHighlight && replacementHighlight) method_exchangeImplementations(originalHighlight, replacementHighlight);
    });
}

- (void)ccbg_rounded_layoutSubviews {
    [self ccbg_rounded_layoutSubviews];
    CCBGStyleControlCell(self);
}

- (void)ccbg_rounded_setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [self ccbg_rounded_setHighlighted:highlighted animated:animated];
    CCBGAnimateControlCellPress(self, highlighted, animated);
}
@end

static void CCBGAnimateControlCellPress(UITableViewCell *cell, BOOL pressed, BOOL animated) {
    if (!cell) return;
    CGAffineTransform target = pressed ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
    if (CGAffineTransformEqualToTransform(cell.contentView.transform, target)) return;
    NSTimeInterval duration = pressed ? 0.06 : 0.14;
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        cell.contentView.transform = target;
        return;
    }
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{ cell.contentView.transform = target; }
                     completion:nil];
}

void CCBGApplyAppTheme(UIWindow *window) {
    if (!window) return;
    UIColor *accent = CCBGAppAccentColor();
    CCBGStyledAccentColor = accent;
    NSInteger mode = [CCBGReadPreference(@"appAppearanceMode", @0) integerValue];
    window.overrideUserInterfaceStyle = mode == 1 ? UIUserInterfaceStyleLight : mode == 2 ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    window.tintColor = accent;
    window.backgroundColor = UIColor.systemGroupedBackgroundColor;

    // Keep the app visually coherent with Control Center's material hierarchy:
    // translucent chrome, quiet separators, and one accent color. Appearance
    // proxies cover controllers that are pushed after launch without forcing a
    // reload/layout pass while the user is scrolling.
    UITableView *tableAppearance = [UITableView appearance];
    tableAppearance.backgroundColor = UIColor.systemGroupedBackgroundColor;
    tableAppearance.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (@available(iOS 15.0, *)) tableAppearance.sectionHeaderTopPadding = 8.0;
    UITableViewCell *cellAppearance = [UITableViewCell appearance];
    cellAppearance.tintColor = accent;
    UISwitch *switchAppearance = [UISwitch appearance];
    switchAppearance.onTintColor = accent;
    UISlider *sliderAppearance = [UISlider appearance];
    sliderAppearance.minimumTrackTintColor = accent;
    UISegmentedControl *segmentAppearance = [UISegmentedControl appearance];
    segmentAppearance.selectedSegmentTintColor = [accent colorWithAlphaComponent:0.88];

    UINavigationBarAppearance *navigationAppearance = [UINavigationBarAppearance new];
    [navigationAppearance configureWithTransparentBackground];
    navigationAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    navigationAppearance.backgroundColor = [UIColor systemBackgroundColor];
    navigationAppearance.shadowColor = UIColor.clearColor;
    navigationAppearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};
    navigationAppearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.labelColor};

    UITabBarAppearance *tabAppearance = [UITabBarAppearance new];
    [tabAppearance configureWithDefaultBackground];
    tabAppearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    tabAppearance.shadowColor = UIColor.clearColor;
    tabAppearance.selectionIndicatorTintColor = [accent colorWithAlphaComponent:0.16];

    void (^applyToController)(UIViewController *) = ^(UIViewController *controller) {
        if (!controller) return;
        controller.view.tintColor = accent;
        if ([controller isKindOfClass:UINavigationController.class]) {
            UINavigationController *navigation = (UINavigationController *)controller;
            navigation.navigationBar.standardAppearance = navigationAppearance;
            navigation.navigationBar.scrollEdgeAppearance = navigationAppearance;
            navigation.navigationBar.compactAppearance = navigationAppearance;
            navigation.navigationBar.tintColor = accent;
        }
        if ([controller isKindOfClass:UITabBarController.class]) {
            UITabBarController *tabs = (UITabBarController *)controller;
            tabs.tabBar.standardAppearance = tabAppearance;
            tabs.tabBar.scrollEdgeAppearance = tabAppearance;
            tabs.tabBar.tintColor = accent;
            tabs.tabBar.unselectedItemTintColor = UIColor.secondaryLabelColor;
        }
        if ([controller isKindOfClass:UITableViewController.class] && controller.isViewLoaded) {
            UITableView *table = ((UITableViewController *)controller).tableView;
            table.backgroundColor = UIColor.systemGroupedBackgroundColor;
            table.separatorStyle = UITableViewCellSeparatorStyleNone;
            table.tintColor = accent;
            // Appearance proxies update the existing cells in place. A full
            // reload here blocks scrolling and can restart thumbnail work;
            // callers that changed a setting refresh only their own section.
            [table setNeedsLayout];
        }
    };
    applyToController(window.rootViewController);
    if ([window.rootViewController isKindOfClass:UITabBarController.class]) {
        for (UIViewController *child in ((UITabBarController *)window.rootViewController).viewControllers) {
            applyToController(child);
            if ([child isKindOfClass:UINavigationController.class]) {
                for (UIViewController *root in ((UINavigationController *)child).viewControllers) applyToController(root);
            }
        }
    } else if ([window.rootViewController isKindOfClass:UINavigationController.class]) {
        for (UIViewController *root in ((UINavigationController *)window.rootViewController).viewControllers) applyToController(root);
    }
}

NSURL *CCBGFilzaURLForPath(NSString *path) {
    if (!path.length) return nil;
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"filza";
    components.host = @"view";
    components.percentEncodedPath = [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    return components.URL;
}

@interface CCBGSwitchCell ()
@property(nonatomic, strong, readwrite) UISwitch *toggle;
@end


@implementation CCBGSwitchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _toggle = [UISwitch new];
        _toggle.onTintColor = CCBGAppAccentColor();
        self.accessoryView = _toggle;
        CCBGStyleControlCell(self);
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.numberOfLines = 0;
        self.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(BOOL)value target:(id)target action:(SEL)action {
    self.textLabel.text = title;
    self.toggle.onTintColor = CCBGAppAccentColor();
    self.toggle.accessibilityIdentifier = key;
    self.toggle.on = value;
    [self.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CCBGAnimateControlCellPress(self, highlighted, animated);
}
@end


@interface CCBGSliderCell ()
@property(nonatomic, strong, readwrite) UISlider *slider;
@property(nonatomic, strong, readwrite) UILabel *valueLabel;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, copy) NSString *valueFormat;
@end

@implementation CCBGSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    CCBGStyleControlCell(self);
    _titleLabel = [UILabel new];
    _valueLabel = [UILabel new];
    _slider = [UISlider new];
    _slider.minimumTrackTintColor = CCBGAppAccentColor();
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _titleLabel.numberOfLines = 0;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(valueLabelDoubleTapped:)];
    tap.numberOfTapsRequired = 2;
    [_valueLabel addGestureRecognizer:tap];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _valueLabel]];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, _slider]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(float)value minimum:(float)minimum maximum:(float)maximum format:(NSString *)format target:(id)target action:(SEL)action {
    self.titleLabel.text = title;
    self.slider.accessibilityIdentifier = key;
    self.slider.minimumValue = minimum;
    self.slider.maximumValue = maximum;
    self.slider.value = MIN(maximum, MAX(minimum, value));
    self.slider.continuous = YES;
    self.valueFormat = format;
    [self refreshValueLabel];
    [self.slider removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:target action:action forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventEditingDidEnd];
}

- (void)sliderValueChanged:(UISlider *)sender {
    [self refreshValueLabel];
    if (!sender.tracking) [sender sendActionsForControlEvents:UIControlEventEditingDidEnd];
}

- (void)refreshValueLabel {
    NSString *format = self.valueFormat ?: @"%.2f";
    float displayValue = [format containsString:@"%%"] ? self.slider.value * 100.0f : self.slider.value;
    self.valueLabel.text = [NSString stringWithFormat:format, displayValue];
}

- (UIViewController *)owningViewController {
    UIResponder *responder = self;
    while (responder) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    }
    return nil;
}

- (void)valueLabelDoubleTapped:(UITapGestureRecognizer *)recognizer {
    NSString *key = self.slider.accessibilityIdentifier;
    if (!key.length) return;
    UIViewController *controller = [self owningViewController];
    if (!controller) return;
    BOOL percent = [self.valueFormat containsString:@"%%"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.titleLabel.text ?: @"输入数值"
                                                                   message:percent ? @"输入 0-100 之间的百分比" : nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeDecimalPad;
        field.text = [NSString stringWithFormat:percent ? @"%.0f" : @"%.2f", percent ? self.slider.value * 100.0f : self.slider.value];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        NSString *text = alert.textFields.firstObject.text ?: @"";
        float value = text.floatValue;
        if (percent) value /= 100.0f;
        value = MIN(self.slider.maximumValue, MAX(self.slider.minimumValue, value));
        [self.slider setValue:value animated:YES];
        [self refreshValueLabel];
        [self.slider sendActionsForControlEvents:UIControlEventTouchUpInside];
    }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CCBGAnimateControlCellPress(self, highlighted, animated);
}
@end


@interface CCBGSegmentCell ()
@property(nonatomic, strong, readwrite) UISegmentedControl *segments;
@property(nonatomic, strong) UILabel *titleLabel;
@end

@implementation CCBGSegmentCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    CCBGStyleControlCell(self);
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _titleLabel.numberOfLines = 0;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _segments = [UISegmentedControl new];
    _segments.selectedSegmentTintColor = [CCBGAppAccentColor() colorWithAlphaComponent:0.88];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _segments]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)configureWithTitle:(NSString *)title key:(NSString *)key items:(NSArray<NSString *> *)items selected:(NSInteger)selected target:(id)target action:(SEL)action {
    self.titleLabel.text = title;
    [self.segments removeAllSegments];
    [items enumerateObjectsUsingBlock:^(NSString *item, NSUInteger index, BOOL *stop) {
        [self.segments insertSegmentWithTitle:item atIndex:index animated:NO];
    }];
    self.segments.accessibilityIdentifier = key;
    self.segments.selectedSegmentIndex = MIN((NSInteger)items.count - 1, MAX(0, selected));
    [self.segments removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.segments addTarget:target action:action forControlEvents:UIControlEventValueChanged];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CCBGAnimateControlCellPress(self, highlighted, animated);
}
@end


@interface CCBGGridSizePickerCell ()
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, strong) UIStackView *gridStack;
@end

@implementation CCBGGridSizePickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    CCBGStyleControlCell(self);
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _titleLabel.numberOfLines = 0;
    _valueLabel = [UILabel new];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _valueLabel]];
    _gridStack = [UIStackView new];
    _gridStack.axis = UILayoutConstraintAxisVertical;
    _gridStack.spacing = 6;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, _gridStack]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
    ]];
    return self;
}

- (void)configureWithTitle:(NSString *)title width:(NSInteger)width height:(NSInteger)height maximum:(NSInteger)maximum target:(id)target action:(SEL)action {
    width = MIN(maximum, MAX(1, width));
    height = MIN(maximum, MAX(1, height));
    self.titleLabel.text = title;
    self.valueLabel.text = [NSString stringWithFormat:@"%ld × %ld", (long)width, (long)height];
    for (UIView *view in self.gridStack.arrangedSubviews.copy) {
        [self.gridStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSInteger row = maximum; row >= 1; row--) {
        UIStackView *line = [UIStackView new];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 6;
        line.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger column = 1; column <= maximum; column++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.accessibilityIdentifier = [NSString stringWithFormat:@"%ldx%ld", (long)column, (long)row];
            button.accessibilityLabel = [NSString stringWithFormat:@"%ld 乘 %ld", (long)column, (long)row];
            BOOL selected = column <= width && row <= height;
            button.backgroundColor = selected ? CCBGAppAccentColor() : UIColor.tertiarySystemFillColor;
            button.tintColor = selected ? UIColor.whiteColor : UIColor.secondaryLabelColor;
            button.layer.cornerRadius = 8.0;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            [button setImage:[UIImage systemImageNamed:selected ? @"checkmark" : @"circle"] forState:UIControlStateNormal];
            [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
            [line addArrangedSubview:button];
            [button.heightAnchor constraintEqualToConstant:30].active = YES;
        }
        [self.gridStack addArrangedSubview:line];
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CCBGAnimateControlCellPress(self, highlighted, animated);
}
@end


@interface CCBGMediaPickerController () <UISearchResultsUpdating, UISearchBarDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) NSArray<NSDictionary *> *scopeItems;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredItems;
@property(nonatomic, copy) NSString *selectedName;
@property(nonatomic, copy) void (^completion)(NSString *fileName);
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic) NSUInteger searchReloadGeneration;
@property(nonatomic, copy) NSString *renderedItemsSignature;
@end

@implementation CCBGMediaPickerController
- (instancetype)initWithTitle:(NSString *)title selected:(NSString *)selected completion:(void (^)(NSString *))completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _selectedName = [selected copy] ?: @"";
        _completion = [completion copy];
        _items = CCBGLoadMediaCatalog();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.placeholder = @"搜索共享素材";
    self.searchController.searchBar.scopeButtonTitles = @[@"全部", @"收藏", @"最近"];
    self.searchController.searchBar.showsScopeBar = YES;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self applyMediaFilters];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The picker can stay alive while another screen imports or removes media.
    // Refresh its immutable source snapshot when it becomes visible again.
    self.items = CCBGLoadMediaCatalog();
    self.renderedItemsSignature = nil;
    [self applyMediaFilters];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.viewIfLoaded.window || self.searchController.isActive) return;
        [self scrollToSelectedItemIfNeeded];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.searchController.isActive) [self scrollToSelectedItemIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.searchReloadGeneration++;
}

- (NSArray<NSDictionary *> *)visibleItems { return self.filteredItems ?: self.scopeItems ?: self.items; }

- (void)scrollToSelectedItemIfNeeded {
    if (!self.selectedName.length) return;
    NSUInteger itemIndex = [self.visibleItems indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
        return [item[@"fileName"] isEqualToString:self.selectedName];
    }];
    if (itemIndex == NSNotFound) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)itemIndex + 1 inSection:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath.row < [self.tableView numberOfRowsInSection:0]) {
            [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        }
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyMediaFilters];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self applyMediaFilters];
}

- (void)applyMediaFilters {
    NSInteger scope = self.searchController.searchBar.selectedScopeButtonIndex;
    NSArray<NSDictionary *> *source = self.items ?: @[];
    if (scope == 1) {
        source = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
            return [item[@"favorite"] respondsToSelector:@selector(boolValue)] && [item[@"favorite"] boolValue];
        }]];
    } else if (scope == 2) {
        source = [[source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
            return [item[@"lastPlayedAt"] respondsToSelector:@selector(doubleValue)] && [item[@"lastPlayedAt"] doubleValue] > 0;
        }]] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSTimeInterval leftTime = [left[@"lastPlayedAt"] respondsToSelector:@selector(doubleValue)] ? [left[@"lastPlayedAt"] doubleValue] : 0;
            NSTimeInterval rightTime = [right[@"lastPlayedAt"] respondsToSelector:@selector(doubleValue)] ? [right[@"lastPlayedAt"] doubleValue] : 0;
            return rightTime > leftTime ? NSOrderedAscending : rightTime < leftTime ? NSOrderedDescending : NSOrderedSame;
        }];
        if (source.count > 50) source = [source subarrayWithRange:NSMakeRange(0, 50)];
    }
    self.scopeItems = source;
    NSString *query = self.searchController.searchBar.text ?: @"";
    if (!query.length) {
        self.filteredItems = nil;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
            return [CCBGDisplayNameForItem(item) localizedCaseInsensitiveContainsString:query] ||
                [item[@"fileName"] localizedCaseInsensitiveContainsString:query];
        }];
        self.filteredItems = [source filteredArrayUsingPredicate:predicate];
    }
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%lu|%@|", (unsigned long)self.visibleItems.count, query];
    for (NSDictionary *item in self.visibleItems) [signature appendFormat:@"%@|", item[@"fileName"] ?: @""];
    if ([self.renderedItemsSignature isEqualToString:signature]) return;
    self.renderedItemsSignature = signature.copy;
    NSUInteger generation = ++self.searchReloadGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.searchReloadGeneration) return;
        [self.tableView reloadData];
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleItems.count + 1; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"media"];
    CCBGStyleControlCell(cell);
    cell.contentConfiguration = nil;
    cell.textLabel.textColor = UIColor.labelColor;
    NSString *name = @"";
    if (indexPath.row == 0) {
        cell.textLabel.text = @"跟随默认选择";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"circle.dashed"];
        cell.accessibilityIdentifier = @"";
    } else {
        NSDictionary *item = self.visibleItems[indexPath.row - 1];
        name = item[@"fileName"];
        cell.textLabel.text = CCBGDisplayNameForItem(item);
        NSString *kind = CCBGIsVideoName(name) ? @"视频" : @"图片";
        cell.detailTextLabel.text = [item[@"enabled"] boolValue] ? kind : [kind stringByAppendingString:@" · 已停用，选择后启用"];
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = cell.textLabel.text;
        content.secondaryText = cell.detailTextLabel.text;
        CGSize thumbnailSize = CGSizeMake(52, 52);
        NSString *cacheKey = CCBGThumbnailCacheKeyForItem(item, thumbnailSize, @"picker-");
        content.image = CCBGPlaceholderImageForItem(item);
        content.imageProperties.maximumSize = CGSizeMake(52, 52);
        content.imageProperties.reservedLayoutSize = CGSizeMake(52, 52);
        content.imageProperties.cornerRadius = 7;
        content.textProperties.color = [item[@"enabled"] boolValue] ? UIColor.labelColor : UIColor.secondaryLabelColor;
        cell.contentConfiguration = content;
        cell.accessibilityIdentifier = cacheKey;
        __weak UITableViewCell *weakCell = cell;
        CCBGLoadThumbnailForItem(item, thumbnailSize, ^(UIImage *thumbnail) {
            UITableViewCell *strongCell = weakCell;
            if (!thumbnail || ![strongCell.accessibilityIdentifier isEqualToString:cacheKey]) return;
            UIListContentConfiguration *updated = (UIListContentConfiguration *)strongCell.contentConfiguration;
            updated.image = thumbnail;
            strongCell.contentConfiguration = updated;
        });
    }
    cell.accessoryType = [name isEqualToString:self.selectedName] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = @"";
    if (indexPath.row > 0) {
        NSDictionary *selectedItem = self.visibleItems[indexPath.row - 1];
        name = selectedItem[@"fileName"];
        if (![selectedItem[@"enabled"] boolValue]) {
            NSMutableArray *catalog = [self.items mutableCopy];
            NSUInteger itemIndex = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) {
                return [item[@"fileName"] isEqualToString:name];
            }];
            if (itemIndex != NSNotFound) {
                NSMutableDictionary *enabledItem = [catalog[itemIndex] mutableCopy];
                enabledItem[@"enabled"] = @YES;
                catalog[itemIndex] = enabledItem;
                self.items = catalog;
                CCBGSaveMediaCatalog(catalog);
            }
        }
    }
    if (self.completion) self.completion(name);
    [self.navigationController popViewControllerAnimated:YES];
}
@end


NSString *CCBGReadableBytes(unsigned long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
}

UIImage *CCBGPlaceholderImageForItem(NSDictionary *item) {
    NSString *fileName = item[@"fileName"] ?: @"";
    return [UIImage systemImageNamed:CCBGIsVideoName(fileName) ? @"video.fill" : @"photo.fill"];
}

NSString *CCBGThumbnailCacheKeyForItem(NSDictionary *item, CGSize size, NSString *prefix) {
    NSString *fileName = item[@"fileName"] ?: @"";
    NSString *safeName = [[fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    unsigned long long fileSize = [item[@"fileSize"] unsignedLongLongValue];
    NSTimeInterval modified = [item[@"fileModifiedAt"] doubleValue];
    return [NSString stringWithFormat:@"%@%@-%.0fx%.0f-%llu-%.0f-%.1f", prefix ?: @"", safeName, size.width, size.height,
        fileSize, modified, [item[@"coverFrameTime"] doubleValue]];
}

static NSCache<NSString *, UIImage *> *CCBGThumbnailMemoryCache(void) {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 240;
    });
    return cache;
}

static dispatch_queue_t CCBGThumbnailQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjc.cleanccbg2x2.thumbnails", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

static dispatch_semaphore_t CCBGThumbnailSemaphore(void) {
    static dispatch_semaphore_t semaphore;
    static dispatch_once_t onceToken;
    // Keep background decoding below the level that competes with table
    // scrolling and video playback. Two workers still fill a cold library
    // quickly while avoiding bursts of decoder and JPEG work.
    dispatch_once(&onceToken, ^{ semaphore = dispatch_semaphore_create(2); });
    return semaphore;
}

static NSMutableDictionary<NSString *, NSMutableArray *> *CCBGThumbnailPendingCallbacks(void) {
    static NSMutableDictionary<NSString *, NSMutableArray *> *callbacks;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        callbacks = [NSMutableDictionary dictionary];
    });
    return callbacks;
}

static NSMutableDictionary<NSString *, AVAssetImageGenerator *> *CCBGActiveThumbnailGenerators(void) {
    static NSMutableDictionary<NSString *, AVAssetImageGenerator *> *generators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ generators = [NSMutableDictionary dictionary]; });
    return generators;
}

static NSString *CCBGThumbnailCachePathForItem(NSDictionary *item, CGSize size) {
    NSString *cacheDirectory = @"/var/mobile/Library/CleanCCBG2x2/Thumbnails";
    NSString *cacheName = [CCBGThumbnailCacheKeyForItem(item, size, @"") stringByAppendingPathExtension:@"jpg"];
    return [cacheDirectory stringByAppendingPathComponent:cacheName];
}

static UIImage *CCBGScaleAndCacheThumbnail(UIImage *source, CGSize size, NSString *cachePath) {
    if (!source) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = YES;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor secondarySystemGroupedBackgroundColor] setFill];
        UIRectFill((CGRect){CGPointZero, size});
        CGFloat sourceRatio = source.size.width / MAX(1.0, source.size.height);
        CGFloat targetRatio = size.width / MAX(1.0, size.height);
        CGRect drawRect = CGRectZero;
        if (sourceRatio > targetRatio) {
            CGFloat width = size.height * sourceRatio;
            drawRect = CGRectMake((size.width - width) / 2.0, 0, width, size.height);
        } else {
            CGFloat height = size.width / MAX(0.01, sourceRatio);
            drawRect = CGRectMake(0, (size.height - height) / 2.0, size.width, height);
        }
        [source drawInRect:drawRect];
    }];
    NSData *jpeg = UIImageJPEGRepresentation(scaled, 0.78);
    if (jpeg && cachePath.length) [jpeg writeToFile:cachePath atomically:YES];
    return scaled;
}

static UIImage *CCBGGeneratedThumbnailForItem(NSDictionary *item, CGSize size) {
    NSString *path = CCBGPathForItem(item);
    NSString *fileName = item[@"fileName"] ?: @"";
    NSString *cacheDirectory = @"/var/mobile/Library/CleanCCBG2x2/Thumbnails";
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cachePath = CCBGThumbnailCachePathForItem(item, size);
    UIImage *cached = [UIImage imageWithContentsOfFile:cachePath];
    if (cached) return cached;

    UIImage *source = nil;
    if (CCBGIsVideoName(fileName)) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        NSTimeInterval durationSeconds = CMTimeGetSeconds(asset.duration);
        BOOL hasValidDuration = isfinite(durationSeconds) && durationSeconds > 0.0;
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(size.width * 2, size.height * 2);
        generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
        generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
        NSTimeInterval coverFrameTime = [item[@"coverFrameTime"] doubleValue];
        NSArray<NSNumber *> *times = coverFrameTime > 0
            ? @[@(coverFrameTime), @(MAX(0.05, [item[@"startTime"] doubleValue])), @1.0, @2.0, @0.1]
            : @[@(MAX(0.05, [item[@"startTime"] doubleValue])), @1.0, @2.0, @0.1];
        for (NSNumber *secondsValue in times) {
            NSTimeInterval seconds = MAX(0.0, secondsValue.doubleValue);
            if (hasValidDuration) seconds = MIN(seconds, MAX(0.0, durationSeconds - 0.03));
            CGImageRef frame = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(seconds, 600) actualTime:nil error:nil];
            if (frame) {
                source = [UIImage imageWithCGImage:frame];
                CGImageRelease(frame);
                break;
            }
        }
    } else {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
        if (imageSource) {
            NSDictionary *options = @{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(size.width, size.height) * 2),
            };
            CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
            if (thumbnail) {
                source = [UIImage imageWithCGImage:thumbnail];
                CGImageRelease(thumbnail);
            }
            CFRelease(imageSource);
        }
    }
    return CCBGScaleAndCacheThumbnail(source, size, cachePath);
}

static void CCBGGenerateVideoThumbnailAsync(NSDictionary *item, CGSize size, NSString *requestKey, void (^completion)(UIImage *thumbnail)) {
    dispatch_async(CCBGThumbnailQueue(), ^{
        dispatch_semaphore_wait(CCBGThumbnailSemaphore(), DISPATCH_TIME_FOREVER);
        NSString *cacheDirectory = @"/var/mobile/Library/CleanCCBG2x2/Thumbnails";
        [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *cachePath = CCBGThumbnailCachePathForItem(item, size);
        UIImage *diskCached = [UIImage imageWithContentsOfFile:cachePath];
        if (diskCached) {
            dispatch_semaphore_signal(CCBGThumbnailSemaphore());
            completion(diskCached);
            return;
        }

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:CCBGPathForItem(item)]
                                                options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(size.width * 2, size.height * 2);
        generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
        generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
        NSTimeInterval coverFrameTime = MAX(0.0, [item[@"coverFrameTime"] doubleValue]);
        NSTimeInterval startTime = MAX(0.05, [item[@"startTime"] doubleValue]);
        NSArray<NSNumber *> *seconds = coverFrameTime > 0.0
            ? @[@(coverFrameTime), @(startTime), @1.0, @0.1, @0.0]
            : @[@(startTime), @1.0, @0.1, @0.0];
        NSMutableArray<NSValue *> *times = [NSMutableArray arrayWithCapacity:seconds.count];
        for (NSNumber *value in seconds) [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(value.doubleValue, 600)]];

        NSMutableDictionary<NSString *, AVAssetImageGenerator *> *active = CCBGActiveThumbnailGenerators();
        @synchronized (active) { active[requestKey] = generator; }
        __block NSInteger remaining = times.count;
        __block BOOL completed = NO;
        NSObject *completionLock = [NSObject new];
        __weak AVAssetImageGenerator *weakGenerator = generator;
        void (^finishOnce)(UIImage *) = ^(UIImage *source) {
            BOOL shouldFinish = NO;
            @synchronized (completionLock) {
                if (!completed) {
                    completed = YES;
                    shouldFinish = YES;
                }
            }
            if (!shouldFinish) return;
            AVAssetImageGenerator *strongGenerator = weakGenerator;
            [strongGenerator cancelAllCGImageGeneration];
            UIImage *thumbnail = CCBGScaleAndCacheThumbnail(source, size, cachePath);
            @synchronized (active) {
                if (strongGenerator && active[requestKey] == strongGenerator) [active removeObjectForKey:requestKey];
            }
            dispatch_semaphore_signal(CCBGThumbnailSemaphore());
            completion(thumbnail);
        };
        [generator generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
            (void)requestedTime; (void)actualTime; (void)error;
            BOOL shouldFinish = NO;
            UIImage *source = nil;
            @synchronized (completionLock) {
                if (completed) return;
                remaining--;
                if (result == AVAssetImageGeneratorSucceeded && image) {
                    source = [UIImage imageWithCGImage:image];
                    shouldFinish = YES;
                } else if (remaining <= 0) {
                    shouldFinish = YES;
                }
            }
            if (shouldFinish) finishOnce(source);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            finishOnce(nil);
        });
    });
}

UIImage *CCBGThumbnailForItem(NSDictionary *item, CGSize size) {
    NSString *cacheKey = CCBGThumbnailCacheKeyForItem(item, size, @"sync-");
    UIImage *cached = [CCBGThumbnailMemoryCache() objectForKey:cacheKey];
    if (cached) return cached;
    UIImage *thumbnail = CCBGGeneratedThumbnailForItem(item, size);
    if (thumbnail) {
        [CCBGThumbnailMemoryCache() setObject:thumbnail forKey:cacheKey];
        return thumbnail;
    }
    return CCBGPlaceholderImageForItem(item);
}

void CCBGLoadThumbnailForItem(NSDictionary *item, CGSize size, void (^completion)(UIImage *thumbnail)) {
    if (!completion) return;
    NSDictionary *snapshot = [item copy];
    NSString *cacheKey = CCBGThumbnailCacheKeyForItem(snapshot, size, @"async-");
    UIImage *cached = [CCBGThumbnailMemoryCache() objectForKey:cacheKey];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    NSMutableDictionary<NSString *, NSMutableArray *> *pending = CCBGThumbnailPendingCallbacks();
    @synchronized (pending) {
        NSMutableArray *callbacks = pending[cacheKey];
        if (callbacks) {
            [callbacks addObject:[completion copy]];
            return;
        }
        pending[cacheKey] = [NSMutableArray arrayWithObject:[completion copy]];
    }
    __block BOOL requestFinished = NO;
    __block BOOL fallbackStarted = NO;
    void (^finish)(UIImage *) = ^(UIImage *thumbnail) {
        NSArray *finishedCallbacks = nil;
        @synchronized (pending) {
            if (requestFinished) return;
            requestFinished = YES;
            finishedCallbacks = [pending[cacheKey] copy];
            [pending removeObjectForKey:cacheKey];
        }
        if (thumbnail) [CCBGThumbnailMemoryCache() setObject:thumbnail forKey:cacheKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (id callback in finishedCallbacks) {
                void (^block)(UIImage *) = callback;
                block(thumbnail);
            }
        });
    };
    void (^generateFallback)(void) = ^{
        dispatch_async(CCBGThumbnailQueue(), ^{
            UIImage *queuedCached = [CCBGThumbnailMemoryCache() objectForKey:cacheKey];
            UIImage *diskCached = queuedCached ? nil : [UIImage imageWithContentsOfFile:CCBGThumbnailCachePathForItem(snapshot, size)];
            if (diskCached) {
                [CCBGThumbnailMemoryCache() setObject:diskCached forKey:cacheKey];
                finish(diskCached);
                return;
            }
            dispatch_semaphore_wait(CCBGThumbnailSemaphore(), DISPATCH_TIME_FOREVER);
            UIImage *thumbnail = queuedCached ?: CCBGGeneratedThumbnailForItem(snapshot, size);
            dispatch_semaphore_signal(CCBGThumbnailSemaphore());
            finish(thumbnail);
        });
    };
    NSString *path = CCBGPathForItem(snapshot);
    BOOL video = CCBGIsVideoName(snapshot[@"fileName"]);
    void (^startFallback)(void) = ^{
        @synchronized (pending) {
            if (requestFinished || fallbackStarted) return;
            fallbackStarted = YES;
        }
        if (video) {
            CCBGGenerateVideoThumbnailAsync(snapshot, size, cacheKey, ^(UIImage *thumbnail) {
                if (thumbnail) finish(thumbnail);
                else {
                    BOOL needsSyncFallback = NO;
                    @synchronized (pending) { needsSyncFallback = !requestFinished; }
                    if (needsSyncFallback) generateFallback();
                }
            });
        } else {
            generateFallback();
        }
    };
    void (^startQuickLook)(void) = ^{
        if (@available(iOS 13.0, *)) {
            QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc]
                initWithFileAtURL:[NSURL fileURLWithPath:path]
                size:size
                scale:UIScreen.mainScreen.scale
                representationTypes:(QLThumbnailGenerationRequestRepresentationTypeThumbnail | QLThumbnailGenerationRequestRepresentationTypeLowQualityThumbnail)];
            request.iconMode = NO;
            [[QLThumbnailGenerator sharedGenerator] generateBestRepresentationForRequest:request completionHandler:^(QLThumbnailRepresentation *representation, NSError *error) {
                UIImage *image = representation.UIImage;
                if (!image) {
                    startFallback();
                    return;
                }
                // Quick Look may call back on the main thread. Scaling and JPEG
                // cache writes are deliberately returned to the worker queue.
                dispatch_async(CCBGThumbnailQueue(), ^{
                    finish(CCBGScaleAndCacheThumbnail(image, size, CCBGThumbnailCachePathForItem(snapshot, size)));
                });
            }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                startFallback();
            });
        } else {
            startFallback();
        }
    };
    // UITableView asks for cells while scrolling. Check and decode the cached
    // image off-main first; expensive thumbnail generation starts only on a miss.
    dispatch_async(CCBGThumbnailQueue(), ^{
        UIImage *diskCached = [UIImage imageWithContentsOfFile:CCBGThumbnailCachePathForItem(snapshot, size)];
        if (diskCached) {
            [CCBGThumbnailMemoryCache() setObject:diskCached forKey:cacheKey];
            finish(diskCached);
        } else {
            startQuickLook();
        }
    });
}

void CCBGApplyThumbnailToCell(UITableViewCell *cell, NSDictionary *item, CGSize size, NSString *prefix) {
    if (!cell) return;
    if (!item) {
        cell.imageView.image = [UIImage systemImageNamed:@"photo"];
        cell.imageView.accessibilityIdentifier = @"";
        return;
    }
    NSString *cacheKey = CCBGThumbnailCacheKeyForItem(item, size, prefix ?: @"cell-");
    cell.imageView.image = CCBGPlaceholderImageForItem(item);
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 7.0;
    cell.imageView.accessibilityIdentifier = cacheKey;
    __weak UITableViewCell *weakCell = cell;
    CCBGLoadThumbnailForItem(item, size, ^(UIImage *thumbnail) {
        UITableViewCell *strongCell = weakCell;
        if (!thumbnail || ![strongCell.imageView.accessibilityIdentifier isEqualToString:cacheKey]) return;
        if (strongCell.imageView.image == thumbnail) return;
        UIView *ancestor = strongCell.superview;
        BOOL tableIsScrolling = NO;
        while (ancestor) {
            if ([ancestor isKindOfClass:UITableView.class]) {
                UITableView *table = (UITableView *)ancestor;
                tableIsScrolling = table.dragging || table.decelerating;
                break;
            }
            ancestor = ancestor.superview;
        }
        // During a scroll, a cross-dissolve per visible cell competes with
        // scrolling and video decoding. Apply the ready thumbnail directly;
        // keep the short fade for stationary cells where it adds polish.
        if (UIAccessibilityIsReduceMotionEnabled() || tableIsScrolling) {
            strongCell.imageView.image = thumbnail;
        } else {
            [UIView transitionWithView:strongCell.imageView
                              duration:0.12
                               options:UIViewAnimationOptionTransitionCrossDissolve |
                                       UIViewAnimationOptionBeginFromCurrentState |
                                       UIViewAnimationOptionAllowUserInteraction
                            animations:^{ strongCell.imageView.image = thumbnail; }
                            completion:nil];
        }
    });
}
