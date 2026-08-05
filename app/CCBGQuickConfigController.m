#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <math.h>

static NSArray<NSDictionary *> *CCBGQuickDictionaryArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)value) if ([entry isKindOfClass:NSDictionary.class]) [result addObject:entry];
    return result;
}

static NSArray<NSNumber *> *CCBGQuickValidSlots(id value, NSInteger excludedSlot) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableOrderedSet<NSNumber *> *slots = [NSMutableOrderedSet orderedSet];
    for (id entry in (NSArray *)value) {
        if (![entry isKindOfClass:NSNumber.class]) continue;
        NSInteger slot = [entry integerValue];
        if (slot < 0 || slot >= (NSInteger)CCBGModuleDisplayNames().count || slot == excludedSlot) continue;
        [slots addObject:@(slot)];
    }
    return slots.array;
}

static void CCBGQuickShowResult(UIViewController *controller, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static void CCBGQuickSetActiveModuleSlotWithoutReload(NSInteger slot) {
    slot = MIN((NSInteger)CCBGModuleDisplayNames().count - 1, MAX(0, slot));
    CFStringRef domain = (__bridge CFStringRef)CCBGPreferenceDomain;
    CFPreferencesSetAppValue(CFSTR("activeModuleSlot"), (__bridge CFPropertyListRef)@(slot), domain);
    CFPreferencesAppSynchronize(domain);
}

@interface CCBGQuickSlotPickerController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title excludedSlot:(NSInteger)excludedSlot completion:(void (^)(NSArray<NSNumber *> *slots))completion;
@end

@interface CCBGQuickSlotPickerController ()
@property(nonatomic) NSInteger excludedSlot;
@property(nonatomic, strong) NSMutableOrderedSet<NSNumber *> *selectedSlots;
@property(nonatomic, copy) void (^completion)(NSArray<NSNumber *> *slots);
@end

@implementation CCBGQuickSlotPickerController
- (instancetype)initWithTitle:(NSString *)title excludedSlot:(NSInteger)excludedSlot completion:(void (^)(NSArray<NSNumber *> *))completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _excludedSlot = excludedSlot;
        _selectedSlots = [NSMutableOrderedSet orderedSet];
        _completion = [completion copy];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(finishSelection)];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return CCBGModuleDisplayNames().count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return [NSString stringWithFormat:@"已选择 %lu 个模块", (unsigned long)self.selectedSlots.count]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slot"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"slot"];
    NSNumber *slot = @(indexPath.row);
    cell.textLabel.text = CCBGModuleDisplayNames()[(NSUInteger)indexPath.row];
    cell.textLabel.textColor = indexPath.row == self.excludedSlot ? UIColor.secondaryLabelColor : UIColor.labelColor;
    cell.selectionStyle = indexPath.row == self.excludedSlot ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.accessoryType = [self.selectedSlots containsObject:slot] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == self.excludedSlot) return;
    NSNumber *slot = @(indexPath.row);
    if ([self.selectedSlots containsObject:slot]) [self.selectedSlots removeObject:slot];
    else [self.selectedSlots addObject:slot];
    [tableView reloadData];
}
- (void)finishSelection {
    if (!self.selectedSlots.count) { CCBGQuickShowResult(self, @"未选择模块", @"至少选择一个目标模块。"); return; }
    NSArray<NSNumber *> *slots = self.selectedSlots.array;
    void (^completion)(NSArray<NSNumber *> *) = self.completion;
    [self.navigationController popViewControllerAnimated:YES];
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(slots); });
}
@end

@interface CCBGQuickHistoryController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *history;
@end

@implementation CCBGQuickHistoryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"修改历史";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.history = CCBGQuickConfigurationHistory(); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.history.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.history.count ? @"撤销始终从最近一次修改开始。" : @"暂无可撤销的快捷修改。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = self.history[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"history"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"history"];
    cell.textLabel.text = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"快捷修改";
    NSTimeInterval time = [entry[@"createdAt"] respondsToSelector:@selector(doubleValue)] ? [entry[@"createdAt"] doubleValue] : 0;
    NSUInteger count = [entry[@"changedKeys"] isKindOfClass:NSArray.class] ? [entry[@"changedKeys"] count] : 0;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu 项", time > 0 ? [NSDate dateWithTimeIntervalSince1970:time].description : @"未知时间", (unsigned long)count];
    cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"arrow.uturn.backward.circle.fill" : @"clock"];
    return cell;
}
- (void)clearHistory {
    CCBGClearQuickConfigurationHistory();
    self.history = @[];
    [self.tableView reloadData];
}
@end

@interface CCBGQuickConflictController : UITableViewController
@property(nonatomic, copy) NSDictionary *context;
@property(nonatomic, copy) NSArray<NSDictionary *> *matchingScenes;
@property(nonatomic, copy) NSArray<NSDictionary *> *allScenes;
@property(nonatomic, copy) NSDictionary *resolvedScene;
@property(nonatomic, copy) NSArray<NSDictionary *> *catalog;
@end

@implementation CCBGQuickConflictController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"当前生效与冲突"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadEvaluation]; }
- (void)reloadEvaluation {
    CCBGInvalidateSceneRuntimeCaches();
    self.context = CCBGSceneRuntimeContext(self.view);
    self.matchingScenes = CCBGSceneDirectorMatchingScenes(self.context);
    self.resolvedScene = CCBGSceneDirectorResolvedScene(self.context) ?: @{};
    self.allScenes = CCBGQuickDictionaryArray(CCBGReadPreference(@"sceneDirectorScenes", @[]));
    self.catalog = CCBGLoadMediaCatalog();
    [self.tableView reloadData];
}
- (NSArray<NSDictionary *> *)unmatchedEnabledScenes {
    NSMutableArray *items = [NSMutableArray array];
    NSSet *matchingIDs = [NSSet setWithArray:[self.matchingScenes valueForKey:@"id"] ?: @[]];
    for (NSDictionary *scene in self.allScenes) {
        if (![scene[@"enabled"] respondsToSelector:@selector(boolValue)] || ![scene[@"enabled"] boolValue] || [matchingIDs containsObject:scene[@"id"] ?: @""]) continue;
        [items addObject:scene];
    }
    return items;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.matchingScenes.count > 1 ? 5 : 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5;
    if (section == 1) return 2;
    if (section == 2) return MAX((NSUInteger)1, self.matchingScenes.count);
    if (section == 3) return MAX((NSUInteger)1, self.unmatchedEnabledScenes.count);
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"运行环境", @"当前生效状态", @"自动化冲突", @"未命中原因", @"修复"][(NSUInteger)section];
}
- (UITableViewCell *)infoCell:(UITableView *)tableView title:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"info"];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSArray *titles = @[@"锁屏", @"深色模式", @"充电", @"方向", @"专注模式"];
        NSArray *details = @[
            [self.context[@"locked"] boolValue] ? @"是" : @"否",
            [self.context[@"dark"] boolValue] ? @"深色" : @"浅色",
            [self.context[@"charging"] boolValue] ? @"正在充电" : @"未充电",
            [self.context[@"landscape"] boolValue] ? @"横屏" : @"竖屏",
            [self.context[@"focus"] isKindOfClass:NSString.class] && [self.context[@"focus"] length] ? self.context[@"focus"] : @"未开启",
        ];
        return [self infoCell:tableView title:titles[(NSUInteger)indexPath.row] detail:details[(NSUInteger)indexPath.row]];
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return [self infoCell:tableView title:@"场景" detail:[self.resolvedScene[@"name"] isKindOfClass:NSString.class] ? self.resolvedScene[@"name"] : @"没有命中场景"];
        NSInteger slot = CCBGActiveModuleSlot();
        NSString *sceneTarget = [NSString stringWithFormat:@"module%ld", (long)slot];
        NSDictionary *targets = [self.resolvedScene[@"targets"] isKindOfClass:NSDictionary.class] ? self.resolvedScene[@"targets"] : @{};
        NSString *sceneMedia = [targets[sceneTarget] isKindOfClass:NSString.class] ? targets[sceneTarget] : @"";
        NSString *media = sceneMedia.length ? sceneMedia : CCBGActiveModuleMediaName(slot);
        NSString *source = sceneMedia.length ? @"场景素材" : @"模块设置";
        NSDictionary *item = CCBGMediaItemNamed(self.catalog, media);
        return [self infoCell:tableView title:@"当前模块素材" detail:[NSString stringWithFormat:@"%@ · %@", CCBGDisplayNameForItem(item) ?: @"无", source]];
    }
    if (indexPath.section == 2) {
        if (!self.matchingScenes.count) return [self infoCell:tableView title:@"没有同时命中的自动场景" detail:@""];
        NSDictionary *scene = self.matchingScenes[(NSUInteger)indexPath.row];
        NSString *detail = [NSString stringWithFormat:@"优先级 %@%@", scene[@"priority"] ?: @1, indexPath.row == 0 ? @" · 当前优先" : @" · 被覆盖"];
        return [self infoCell:tableView title:[scene[@"name"] isKindOfClass:NSString.class] ? scene[@"name"] : @"未命名场景" detail:detail];
    }
    if (indexPath.section == 3) {
        NSArray *unmatched = self.unmatchedEnabledScenes;
        if (!unmatched.count) return [self infoCell:tableView title:@"其他启用场景均已命中" detail:@""];
        NSDictionary *scene = unmatched[(NSUInteger)indexPath.row];
        NSDictionary *evaluation = CCBGSceneDirectorEvaluationForScene(scene, self.context);
        NSArray *reasons = [evaluation[@"reasons"] isKindOfClass:NSArray.class] ? evaluation[@"reasons"] : @[];
        return [self infoCell:tableView title:[scene[@"name"] isKindOfClass:NSString.class] ? scene[@"name"] : @"未命名场景" detail:[reasons componentsJoinedByString:@"；"]];
    }
    UITableViewCell *cell = [self infoCell:tableView title:@"禁用其他命中场景" detail:@"保留优先级最高的当前场景"];
    cell.textLabel.textColor = UIColor.systemOrangeColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 4 || self.matchingScenes.count < 2) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"解决自动化冲突" message:@"将保留优先级最高的场景，并停用其他当前同时命中的场景。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确认停用" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf resolveMatchingSceneConflicts]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)resolveMatchingSceneConflicts {
    if (self.matchingScenes.count < 2) return;
    NSString *keptID = [self.matchingScenes.firstObject[@"id"] isKindOfClass:NSString.class] ? self.matchingScenes.firstObject[@"id"] : @"";
    NSMutableSet *disabledIDs = [NSMutableSet set];
    for (NSUInteger index = 1; index < self.matchingScenes.count; index++) {
        NSString *identifier = self.matchingScenes[index][@"id"];
        if ([identifier isKindOfClass:NSString.class] && identifier.length) [disabledIDs addObject:identifier];
    }
    NSMutableArray *updated = [NSMutableArray array];
    for (NSDictionary *scene in self.allScenes) {
        NSMutableDictionary *copy = [scene mutableCopy];
        if ([disabledIDs containsObject:copy[@"id"] ?: @""]) copy[@"enabled"] = @NO;
        [updated addObject:copy];
    }
    if (CCBGApplyQuickConfigurationChanges(@{@"sceneDirectorScenes": updated}, @"解决场景冲突")) {
        CCBGQuickShowResult(self, @"冲突已处理", [NSString stringWithFormat:@"已保留 %@，其他同时命中的场景已停用。", keptID.length ? self.matchingScenes.firstObject[@"name"] ?: keptID : @"当前场景"]);
        [self reloadEvaluation];
    }
}
@end

@interface CCBGQuickCompositionController : UIViewController
- (instancetype)initWithMediaItem:(NSDictionary *)item slot:(NSInteger)slot;
@end

@interface CCBGQuickCompositionController ()
@property(nonatomic, strong) NSMutableDictionary *workingItem;
@property(nonatomic, strong) UIImage *previewImage;
@property(nonatomic, copy) NSArray<UIImageView *> *previewViews;
@property(nonatomic, strong) UISegmentedControl *modeControl;
@property(nonatomic, strong) UISlider *focalXSlider;
@property(nonatomic, strong) UISlider *focalYSlider;
@property(nonatomic, strong) UILabel *focalXLabel;
@property(nonatomic, strong) UILabel *focalYLabel;
@property(nonatomic) NSInteger moduleSlot;
@property(nonatomic) CGSize sourcePixelSize;
@property(nonatomic) BOOL hasRenderedCompositionPreview;
@property(nonatomic) CGSize lastCompositionPreviewBounds;
@property(nonatomic) CGFloat lastCompositionFocalX;
@property(nonatomic) CGFloat lastCompositionFocalY;
@property(nonatomic) NSInteger lastCompositionMode;
@property(nonatomic, strong) UIImage *lastCompositionPreviewImage;
@end

@implementation CCBGQuickCompositionController
- (instancetype)initWithMediaItem:(NSDictionary *)item slot:(NSInteger)slot {
    self = [super init];
    if (self) {
        _moduleSlot = MIN((NSInteger)CCBGModuleDisplayNames().count - 1, MAX(0, slot));
        _workingItem = [CCBGMediaItemForModule(item, _moduleSlot) mutableCopy];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"素材适配助手";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"自动" style:UIBarButtonItemStylePlain target:self action:@selector(autoCompose)];
    UIScrollView *scroll = [UIScrollView new];
    UIStackView *stack = [UIStackView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    [scroll addSubview:stack];
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20], [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
    ]];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"完整", @"填充"]];
    self.modeControl.selectedSegmentIndex = [self.workingItem[@"contentMode"] integerValue] == 0 ? 0 : 1;
    [self.modeControl addTarget:self action:@selector(compositionChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.modeControl];
    self.focalXLabel = [UILabel new];
    self.focalYLabel = [UILabel new];
    self.focalXSlider = [self sliderWithValue:[self.workingItem[@"focalX"] floatValue]];
    self.focalYSlider = [self sliderWithValue:[self.workingItem[@"focalY"] floatValue]];
    [stack addArrangedSubview:self.focalXLabel]; [stack addArrangedSubview:self.focalXSlider];
    [stack addArrangedSubview:self.focalYLabel]; [stack addArrangedSubview:self.focalYSlider];
    NSMutableArray *views = [NSMutableArray array];
    NSArray *names = @[@"1x2", @"2x2", @"2x3", @"3x2", @"3x3"];
    NSArray *ratios = @[@0.5, @1.0, @(2.0 / 3.0), @(3.0 / 2.0), @1.0];
    for (NSUInteger index = 0; index < names.count; index++) {
        UILabel *label = [UILabel new]; label.text = names[index]; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        [stack addArrangedSubview:label];
        UIImageView *preview = [UIImageView new]; preview.clipsToBounds = YES; preview.layer.cornerRadius = 8; preview.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        [stack addArrangedSubview:preview];
        [preview.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:1.0 / [ratios[index] doubleValue]].active = YES;
        [views addObject:preview];
    }
    self.previewViews = views;
    UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
    [apply setTitle:@"应用到当前模块" forState:UIControlStateNormal];
    apply.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [apply addTarget:self action:@selector(applyComposition) forControlEvents:UIControlEventTouchUpInside];
    [apply.heightAnchor constraintEqualToConstant:50].active = YES;
    [stack addArrangedSubview:apply];
    __weak typeof(self) weakSelf = self;
    CCBGLoadThumbnailForItem(self.workingItem, CGSizeMake(900, 900), ^(UIImage *thumbnail) {
        weakSelf.previewImage = thumbnail;
        [weakSelf updateCompositionPreview];
    });
    [self loadSourcePixelSize];
    [self updateCompositionPreview];
}
- (void)loadSourcePixelSize {
    NSString *path = CCBGPathForItem(self.workingItem);
    NSString *fileName = self.workingItem[@"fileName"];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __block CGSize size = CGSizeZero;
        if (CCBGIsVideoName(fileName)) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
                AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
                if (track) {
                    CGSize naturalSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
                    size = CGSizeMake(fabs(naturalSize.width), fabs(naturalSize.height));
                }
                dispatch_semaphore_signal(semaphore);
            }];
            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)));
        } else {
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
            if (source) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
                size = CGSizeMake([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue], [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue]);
                CFRelease(source);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.sourcePixelSize = size; });
    });
}
- (UISlider *)sliderWithValue:(float)value {
    UISlider *slider = [UISlider new]; slider.minimumValue = 0; slider.maximumValue = 1; slider.value = MIN(1, MAX(0, value));
    [slider addTarget:self action:@selector(compositionChanged) forControlEvents:UIControlEventValueChanged];
    return slider;
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self updateCompositionPreview]; }
- (void)compositionChanged { [self updateCompositionPreview]; }
- (void)updateCompositionPreview {
    BOOL fill = self.modeControl.selectedSegmentIndex == 1;
    CGFloat focalX = self.focalXSlider.value;
    CGFloat focalY = self.focalYSlider.value;
    UIImage *image = self.previewImage ?: CCBGPlaceholderImageForItem(self.workingItem);
    CGSize bounds = self.previewViews.firstObject.bounds.size;
    BOOL stateChanged = !self.hasRenderedCompositionPreview ||
        !CGSizeEqualToSize(self.lastCompositionPreviewBounds, bounds) ||
        fabs(self.lastCompositionFocalX - focalX) > 0.001 ||
        fabs(self.lastCompositionFocalY - focalY) > 0.001 ||
        self.lastCompositionMode != (fill ? 1 : 0) ||
        self.lastCompositionPreviewImage != image;
    if (!stateChanged) return;
    self.focalXLabel.text = [NSString stringWithFormat:@"焦点 X · %.2f", focalX];
    self.focalYLabel.text = [NSString stringWithFormat:@"焦点 Y · %.2f", focalY];
    self.hasRenderedCompositionPreview = YES;
    self.lastCompositionPreviewBounds = bounds;
    self.lastCompositionFocalX = focalX;
    self.lastCompositionFocalY = focalY;
    self.lastCompositionMode = fill ? 1 : 0;
    self.lastCompositionPreviewImage = image;
    for (UIImageView *preview in self.previewViews) {
        preview.image = image;
        preview.contentMode = fill ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        CGFloat dx = (0.5 - focalX) * preview.bounds.size.width * 0.22;
        CGFloat dy = (0.5 - focalY) * preview.bounds.size.height * 0.22;
        preview.transform = CGAffineTransformIdentity;
        preview.layer.contentsRect = fill ? CGRectMake(MIN(0.12, MAX(0, 0.06 + dx / MAX(1.0, preview.bounds.size.width))), MIN(0.12, MAX(0, 0.06 + dy / MAX(1.0, preview.bounds.size.height))), 0.88, 0.88) : CGRectMake(0, 0, 1, 1);
    }
}
- (void)autoCompose {
    NSArray *moduleRatios = @[@1.0, @0.5, @(2.0 / 3.0), @(3.0 / 2.0), @1.0];
    CGFloat targetRatio = [moduleRatios[(NSUInteger)self.moduleSlot] doubleValue];
    CGFloat sourceRatio = self.sourcePixelSize.height > 0 ? self.sourcePixelSize.width / self.sourcePixelSize.height : targetRatio;
    CGFloat mismatch = sourceRatio / MAX(0.01, targetRatio);
    self.modeControl.selectedSegmentIndex = mismatch > 1.75 || mismatch < 0.57 ? 0 : 1;
    self.focalXSlider.value = 0.5;
    self.focalYSlider.value = 0.5;
    [self updateCompositionPreview];
}
- (void)applyComposition {
    NSInteger slot = self.moduleSlot;
    NSString *fileName = self.workingItem[@"fileName"];
    if (!fileName.length) return;
    self.workingItem[@"contentMode"] = @(self.modeControl.selectedSegmentIndex);
    self.workingItem[@"focalX"] = @(self.focalXSlider.value);
    self.workingItem[@"focalY"] = @(self.focalYSlider.value);
    self.workingItem[@"portraitContentMode"] = @(self.modeControl.selectedSegmentIndex);
    self.workingItem[@"landscapeContentMode"] = @(self.modeControl.selectedSegmentIndex);
    self.workingItem[@"portraitFocalX"] = @(self.focalXSlider.value); self.workingItem[@"portraitFocalY"] = @(self.focalYSlider.value);
    self.workingItem[@"landscapeFocalX"] = @(self.focalXSlider.value); self.workingItem[@"landscapeFocalY"] = @(self.focalYSlider.value);
    NSDictionary *stored = CCBGReadModulePreference(@"mediaOverrides", slot, @{});
    NSMutableDictionary *overrides = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];
    for (NSString *key in CCBGModuleMediaConfigurationKeys()) if (self.workingItem[key]) configuration[key] = self.workingItem[key];
    overrides[fileName] = configuration;
    NSString *preferenceKey = CCBGPreferenceKeyForModule(@"mediaOverrides", slot);
    if (CCBGApplyQuickConfigurationChanges(@{preferenceKey: overrides}, @"应用素材适配")) CCBGQuickShowResult(self, @"已应用", @"当前模块的显示方式与焦点已更新。");
}
@end

@interface CCBGQuickConfigController () <UISearchResultsUpdating>
@property(nonatomic) NSInteger selectedSlot;
@property(nonatomic, copy) NSArray<NSDictionary *> *catalog;
@property(nonatomic, copy) NSArray<NSDictionary *> *searchResults;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSDictionary *latestUndoEntry;
@property(nonatomic) NSInteger performancePreset;
@property(nonatomic) NSUInteger matchingSceneCount;
@property(nonatomic) NSUInteger searchReloadGeneration;
@end

static NSArray<NSArray<NSDictionary *> *> *CCBGQuickWorkspaceSections(void) {
    static NSArray<NSArray<NSDictionary *> *> *sections;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sections = @[
            @[
                @{@"id": @"slot", @"title": @"当前五模块", @"detail": @"选择设置目标"},
                @{@"id": @"media", @"title": @"当前素材", @"detail": @"选择并立即应用", @"icon": @"photo"},
                @{@"id": @"preview", @"title": @"预览当前素材", @"detail": @"播放或查看原素材", @"icon": @"play.rectangle"},
                @{@"id": @"adapt", @"title": @"素材适配助手", @"detail": @"自动构图与五尺寸预览", @"icon": @"crop"},
            ],
            @[
                @{@"id": @"batchMedia", @"title": @"批量设置素材", @"detail": @"一次应用到多个五模块", @"icon": @"checklist"},
                @{@"id": @"copy", @"title": @"复制模块设置", @"detail": @"复制素材或完整配置", @"icon": @"doc.on.doc"},
                @{@"id": @"batchEdit", @"title": @"素材批量编辑", @"detail": @"收藏、启用与画面参数", @"icon": @"square.and.pencil"},
            ],
            @[
                @{@"id": @"profiles", @"title": @"配置模板与回滚", @"detail": @"保存和一键切换配置模板", @"icon": @"square.stack.3d.up"},
                @{@"id": @"visualThemes", @"title": @"视觉主题", @"detail": @"保存整套素材与外观", @"icon": @"paintpalette.fill"},
                @{@"id": @"visualStyles", @"title": @"模块外观方案", @"detail": @"只复制视觉参数", @"icon": @"paintbrush.pointed"},
                @{@"id": @"shortcutURLs", @"title": @"快捷指令 URL", @"detail": @"用于 NFC、快捷指令和自动化", @"icon": @"link"},
                @{@"id": @"backupTimeline", @"title": @"备份时间机", @"detail": @"查看、核对和恢复自动快照", @"icon": @"clock.badge.checkmark"},
                @{@"id": @"undo", @"title": @"撤销上次修改", @"detail": @"恢复最近一次快捷操作", @"icon": @"arrow.uturn.backward"},
                @{@"id": @"history", @"title": @"修改历史", @"detail": @"查看最近 20 次操作", @"icon": @"clock.arrow.circlepath"},
            ],
            @[
                @{@"id": @"status", @"title": @"当前生效状态", @"detail": @"素材、场景与环境", @"icon": @"gauge.with.dots.needle.50percent"},
                @{@"id": @"conflicts", @"title": @"自动化冲突", @"detail": @"覆盖关系与未命中原因", @"icon": @"exclamationmark.triangle"},
                @{@"id": @"performance", @"title": @"性能档位", @"detail": @"流畅、均衡或画质", @"icon": @"speedometer"},
            ],
            @[
                @{@"id": @"automationPause", @"title": @"暂停自动场景", @"detail": @"手动场景仍可使用", @"icon": @"pause.circle"},
                @{@"id": @"recordSnapshot", @"title": @"记录当前状态", @"detail": @"保存五模块和系统模块的恢复点", @"icon": @"record.circle"},
                @{@"id": @"replayLatest", @"title": @"恢复最近状态", @"detail": @"一键回到最新视觉状态", @"icon": @"backward.end"},
                @{@"id": @"endReplay", @"title": @"结束当前回放", @"detail": @"重新按自动条件运行", @"icon": @"stop.circle"},
            ],
            @[
                @{@"id": @"system", @"title": @"系统模块", @"detail": @"连接、音乐、亮度与音量", @"icon": @"switch.2"},
                @{@"id": @"generic", @"title": @"第三方模块", @"detail": @"已发现的控制中心模块", @"icon": @"puzzlepiece.extension"},
                @{@"id": @"more", @"title": @"更多设置", @"detail": @"诊断、备份与维护工具", @"icon": @"ellipsis.circle"},
            ],
        ];
    });
    return sections;
}

@implementation CCBGQuickConfigController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"快捷配置";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.selectedSlot = CCBGActiveModuleSlot();
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"配置搜索";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadWorkspaceSnapshot];
    self.selectedSlot = MIN((NSInteger)CCBGModuleDisplayNames().count - 1, MAX(0, self.selectedSlot));
    [self.tableView reloadData];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // A queued search refresh must not repaint a table after its navigation
    // transition has started.
    self.searchReloadGeneration++;
}
- (void)reloadWorkspaceSnapshot {
    self.catalog = CCBGLoadMediaCatalog();
    self.latestUndoEntry = CCBGQuickConfigurationHistory().firstObject;
    id preset = CCBGReadPreference(@"quickPerformancePreset", @1);
    self.performancePreset = [preset respondsToSelector:@selector(integerValue)] ? MIN(2, MAX(0, [preset integerValue])) : 1;
    self.matchingSceneCount = CCBGSceneDirectorMatchingScenes(CCBGSceneRuntimeContext(self.view)).count;
}
- (NSArray<NSArray<NSDictionary *> *> *)sections {
    return CCBGQuickWorkspaceSections();
}
- (NSArray<NSDictionary *> *)searchableActions {
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *section in self.sections) for (NSDictionary *item in section) if (![item[@"id"] isEqualToString:@"slot"]) [items addObject:item];
    return items;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    if (!query.length) self.searchResults = nil;
    else self.searchResults = [self.searchableActions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return [item[@"title"] localizedCaseInsensitiveContainsString:query] || [item[@"detail"] localizedCaseInsensitiveContainsString:query];
    }]];
    NSUInteger generation = ++self.searchReloadGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.searchReloadGeneration || !self.viewIfLoaded.window) return;
        [self.tableView reloadData];
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.searchResults ? 1 : self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.searchResults ? self.searchResults.count : self.sections[(NSUInteger)section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.searchResults) return @"搜索结果";
    return @[@"快速应用", @"批量与复制", @"方案与恢复", @"状态与性能", @"全局控制", @"系统与工具"][(NSUInteger)section];
}
- (NSDictionary *)descriptorAtIndexPath:(NSIndexPath *)indexPath { return self.searchResults ? self.searchResults[(NSUInteger)indexPath.row] : self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *descriptor = [self descriptorAtIndexPath:indexPath];
    NSString *identifier = descriptor[@"id"];
    if ([identifier isEqualToString:@"slot"]) {
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"quickSlot"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"quickSlot"];
        [cell configureWithTitle:@"五模块" key:@"quickSlot" items:CCBGModuleDisplayNames() selected:self.selectedSlot target:self action:@selector(slotChanged:)];
        return cell;
    }
    if ([identifier isEqualToString:@"automationPause"]) {
        CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"quickAutomationPause"] ?: [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"quickAutomationPause"];
        [cell configureWithTitle:@"暂停自动场景" key:@"quickAutomationPause" value:CCBGSceneDirectorAutomationPaused() target:self action:@selector(globalAutomationChanged:)];
        return cell;
    }
    NSString *reuseIdentifier = [identifier isEqualToString:@"media"] ? @"quickMedia" : @"quick";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    cell.contentConfiguration = nil;
    cell.textLabel.text = descriptor[@"title"];
    cell.detailTextLabel.text = descriptor[@"detail"];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.imageView.image = [UIImage systemImageNamed:descriptor[@"icon"] ?: @"circle"];
    cell.imageView.tintColor = CCBGAppAccentColor();
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if ([identifier isEqualToString:@"media"]) {
        NSString *name = CCBGActiveModuleMediaName(self.selectedSlot);
        NSDictionary *item = CCBGMediaItemNamed(self.catalog, name);
        cell.detailTextLabel.text = CCBGDisplayNameForItem(item) ?: @"跟随默认选择";
        CCBGApplyThumbnailToCell(cell, item, CGSizeMake(44, 44), @"quick-current-");
    } else if ([identifier isEqualToString:@"undo"]) {
        NSDictionary *entry = self.latestUndoEntry;
        cell.detailTextLabel.text = entry ? [NSString stringWithFormat:@"撤销：%@", entry[@"title"] ?: @"快捷修改"] : @"暂无可撤销修改";
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if ([identifier isEqualToString:@"performance"]) {
        cell.detailTextLabel.text = @[@"流畅", @"均衡", @"画质"][(NSUInteger)self.performancePreset];
    } else if ([identifier isEqualToString:@"conflicts"]) {
        cell.detailTextLabel.text = self.matchingSceneCount > 1 ? [NSString stringWithFormat:@"%lu 个场景同时命中", (unsigned long)self.matchingSceneCount] : @"未发现同时命中";
    } else if ([identifier isEqualToString:@"endReplay"]) {
        BOOL active = [CCBGReadPreference(@"sceneDirectorReplayActive", @NO) boolValue];
        cell.detailTextLabel.text = active ? @"解除固定场景，恢复自动条件" : @"当前没有固定的回放状态";
        cell.accessoryType = active ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = active ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)slotChanged:(UISegmentedControl *)sender {
    self.selectedSlot = sender.selectedSegmentIndex;
    CCBGQuickSetActiveModuleSlotWithoutReload(self.selectedSlot);
    [self.tableView reloadData];
}
- (void)globalAutomationChanged:(UISwitch *)sender {
    CCBGWritePreference(@"sceneDirectorAutomationPaused", @(sender.on));
    CCBGInvalidateSceneRuntimeCaches();
    [self reloadWorkspaceSnapshot];
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *identifier = [self descriptorAtIndexPath:indexPath][@"id"];
    if ([identifier isEqualToString:@"media"]) [self chooseCurrentMedia];
    else if ([identifier isEqualToString:@"preview"]) [self previewCurrentMedia];
    else if ([identifier isEqualToString:@"adapt"]) [self openCompositionAssistant];
    else if ([identifier isEqualToString:@"batchMedia"]) [self chooseBatchMedia];
    else if ([identifier isEqualToString:@"copy"]) [self chooseCopyMode];
    else if ([identifier isEqualToString:@"batchEdit"]) [self.navigationController pushViewController:[CCBGBatchEditController new] animated:YES];
    else if ([identifier isEqualToString:@"profiles"]) [self.navigationController pushViewController:[CCBGProfilesController new] animated:YES];
    else if ([identifier isEqualToString:@"visualThemes"]) [self.navigationController pushViewController:[CCBGVisualThemesController new] animated:YES];
    else if ([identifier isEqualToString:@"visualStyles"]) [self.navigationController pushViewController:[CCBGVisualStylePresetsController new] animated:YES];
    else if ([identifier isEqualToString:@"shortcutURLs"]) [self.navigationController pushViewController:[CCBGShortcutActionsController new] animated:YES];
    else if ([identifier isEqualToString:@"backupTimeline"]) [self.navigationController pushViewController:[CCBGBackupTimelineController new] animated:YES];
    else if ([identifier isEqualToString:@"undo"]) [self undoLastChange];
    else if ([identifier isEqualToString:@"history"]) [self.navigationController pushViewController:[CCBGQuickHistoryController new] animated:YES];
    else if ([identifier isEqualToString:@"status"] || [identifier isEqualToString:@"conflicts"]) [self.navigationController pushViewController:[CCBGQuickConflictController new] animated:YES];
    else if ([identifier isEqualToString:@"performance"]) [self choosePerformancePreset];
    else if ([identifier isEqualToString:@"recordSnapshot"]) [self recordCurrentSnapshot];
    else if ([identifier isEqualToString:@"replayLatest"]) [self replayLatestSnapshot];
    else if ([identifier isEqualToString:@"endReplay"]) [self endCurrentReplay];
    else if ([identifier isEqualToString:@"system"]) [self.navigationController pushViewController:[[CCBGSystemModulesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    else if ([identifier isEqualToString:@"generic"]) [self.navigationController pushViewController:[[CCBGGenericSystemModulesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    else if ([identifier isEqualToString:@"more"]) [self.navigationController pushViewController:[[CCBGMoreController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
- (void)recordCurrentSnapshot {
    CCBGRecordSceneTimelineEvent(@"manual-snapshot", @{ @"source": @"quick-controls" });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CCBGQuickShowResult(self, @"已记录", @"当前视觉状态已保存，可随时恢复。");
    });
}
- (void)replayLatestSnapshot {
    NSDictionary *entry = CCBGSceneTimeline().firstObject;
    if (![entry isKindOfClass:NSDictionary.class]) { CCBGQuickShowResult(self, @"没有可恢复状态", @"先记录一次当前状态。" ); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复最近状态" message:@"将恢复最近一次保存的五模块和系统模块状态，并固定当时命中的场景。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        CCBGReplaySceneTimelineEntry(entry);
        [self reloadWorkspaceSnapshot];
        [self.tableView reloadData];
        CCBGQuickShowResult(self, @"已恢复", @"可在全局控制中结束回放，恢复自动条件。" );
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)endCurrentReplay {
    if (![CCBGReadPreference(@"sceneDirectorReplayActive", @NO) boolValue]) return;
    CCBGExitSceneTimelineReplay();
    [self reloadWorkspaceSnapshot];
    [self.tableView reloadData];
    CCBGQuickShowResult(self, @"已结束回放", @"自动场景条件已恢复。" );
}
- (void)chooseCurrentMedia {
    NSString *selected = CCBGActiveModuleMediaName(self.selectedSlot);
    __weak typeof(self) weakSelf = self;
    CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:@"选择当前素材" selected:selected completion:^(NSString *name) {
        [weakSelf applyMediaToSlots:@[@(weakSelf.selectedSlot)] mediaName:name title:@"设置当前模块素材"];
    }];
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)applyMediaToSlots:(NSArray<NSNumber *> *)slots mediaName:(NSString *)mediaName title:(NSString *)title {
    NSArray *validSlots = CCBGQuickValidSlots(slots, -1);
    if (!validSlots.count) return;
    if (mediaName.length && !CCBGMediaItemNamed(self.catalog, mediaName)) { CCBGQuickShowResult(self, @"素材不存在", mediaName); return; }
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSNumber *slotValue in validSlots) {
        NSInteger slot = slotValue.integerValue;
        changes[CCBGPreferenceKeyForModule(@"selectedMedia", slot)] = mediaName.length ? mediaName : NSNull.null;
        changes[CCBGPreferenceKeyForModule(@"currentMedia", slot)] = mediaName.length ? mediaName : NSNull.null;
        changes[CCBGPreferenceKeyForModule(@"playbackMode", slot)] = @0;
        changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", slot)] = @YES;
    }
    if (CCBGApplyQuickConfigurationChanges(changes, title)) { [self reloadWorkspaceSnapshot]; [self.tableView reloadData]; }
}
- (NSDictionary *)currentMediaItem {
    return CCBGMediaItemNamed(self.catalog, CCBGActiveModuleMediaName(self.selectedSlot));
}
- (NSDictionary *)effectiveCurrentMediaItem {
    NSDictionary *item = self.currentMediaItem;
    return item ? CCBGMediaItemForModule(item, self.selectedSlot) : nil;
}
- (void)previewCurrentMedia {
    NSDictionary *item = self.effectiveCurrentMediaItem;
    if (!item) { CCBGQuickShowResult(self, @"没有当前素材", @"请先选择一个素材。"); return; }
    [self.navigationController pushViewController:[[CCBGPreviewController alloc] initWithMediaItem:item] animated:YES];
}
- (void)openCompositionAssistant {
    NSDictionary *item = self.effectiveCurrentMediaItem;
    if (!item) { CCBGQuickShowResult(self, @"没有当前素材", @"请先选择一个素材。"); return; }
    [self.navigationController pushViewController:[[CCBGQuickCompositionController alloc] initWithMediaItem:item slot:self.selectedSlot] animated:YES];
}
- (void)chooseBatchMedia {
    __weak typeof(self) weakSelf = self;
    CCBGMediaPickerController *picker = [[CCBGMediaPickerController alloc] initWithTitle:@"批量素材" selected:@"" completion:^(NSString *name) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CCBGQuickSlotPickerController *targets = [[CCBGQuickSlotPickerController alloc] initWithTitle:@"选择目标模块" excludedSlot:-1 completion:^(NSArray<NSNumber *> *slots) {
                [weakSelf applyMediaToSlots:slots mediaName:name title:@"批量设置模块素材"];
            }];
            [weakSelf.navigationController pushViewController:targets animated:YES];
        });
    }];
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)chooseCopyMode {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"从 %@ 复制", CCBGModuleDisplayNames()[(NSUInteger)self.selectedSlot]] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *fullValue in @[@NO, @YES]) {
        NSString *title = fullValue.boolValue ? @"复制完整设置" : @"仅复制素材";
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            CCBGQuickSlotPickerController *targets = [[CCBGQuickSlotPickerController alloc] initWithTitle:@"选择目标模块" excludedSlot:weakSelf.selectedSlot completion:^(NSArray<NSNumber *> *slots) {
                [weakSelf copyConfigurationFromSlot:weakSelf.selectedSlot toSlots:slots full:fullValue.boolValue];
            }];
            [weakSelf.navigationController pushViewController:targets animated:YES];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)copyConfigurationFromSlot:(NSInteger)sourceSlot toSlots:(NSArray<NSNumber *> *)slots full:(BOOL)full {
    NSArray *validSlots = CCBGQuickValidSlots(slots, sourceSlot);
    NSDictionary *preferences = CCBGReadAllPreferences();
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    NSArray *keys = full ? CCBGModuleConfigurationKeys() : @[@"selectedMedia", @"currentMedia", @"playbackMode"];
    NSSet *excluded = [NSSet setWithArray:@[@"playbackHistory", @"recentMedia"]];
    for (NSNumber *slotValue in validSlots) {
        NSInteger destinationSlot = slotValue.integerValue;
        for (NSString *key in keys) {
            if ([excluded containsObject:key]) continue;
            NSString *sourceKey = CCBGPreferenceKeyForModule(key, sourceSlot);
            NSString *destinationKey = CCBGPreferenceKeyForModule(key, destinationSlot);
            changes[destinationKey] = preferences[sourceKey] ?: NSNull.null;
        }
        changes[CCBGPreferenceKeyForModule(@"currentMedia", destinationSlot)] = CCBGActiveModuleMediaName(sourceSlot).length ? CCBGActiveModuleMediaName(sourceSlot) : NSNull.null;
        changes[CCBGPreferenceKeyForModule(@"forcePreferenceMediaOnReload", destinationSlot)] = @YES;
    }
    NSString *title = full ? @"复制完整模块设置" : @"复制模块素材";
    if (CCBGApplyQuickConfigurationChanges(changes, title)) {
        [self reloadWorkspaceSnapshot];
        [self.tableView reloadData];
        CCBGQuickShowResult(self, @"复制完成", [NSString stringWithFormat:@"已应用到 %lu 个模块。", (unsigned long)validSlots.count]);
    }
}
- (void)undoLastChange {
    NSString *title = nil;
    if (!CCBGUndoLastQuickConfiguration(&title)) { CCBGQuickShowResult(self, @"没有可撤销修改", @""); return; }
    CCBGQuickShowResult(self, @"已撤销", title ?: @"快捷修改");
    [self reloadWorkspaceSnapshot];
    [self.tableView reloadData];
}
- (void)choosePerformancePreset {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"性能档位" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"流畅", @"均衡", @"画质"];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger index = 0; index < titles.count; index++) {
        [menu addAction:[UIAlertAction actionWithTitle:titles[index] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf applyPerformancePreset:(NSInteger)index]; }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)applyPerformancePreset:(NSInteger)preset {
    preset = MIN(2, MAX(0, preset));
    NSArray *preload = @[@NO, @YES, @YES];
    NSArray *performance = @[@YES, @NO, @NO];
    NSArray *transition = @[@3, @0, @2];
    NSArray *duration = @[@0.16, @0.30, @0.50];
    NSArray *noRepeat = @[@1, @3, @5];
    NSMutableDictionary *changes = [@{@"quickPerformancePreset": @(preset)} mutableCopy];
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        changes[CCBGPreferenceKeyForModule(@"preloadEnabled", slot)] = preload[(NSUInteger)preset];
        changes[CCBGPreferenceKeyForModule(@"performanceMode", slot)] = performance[(NSUInteger)preset];
        changes[CCBGPreferenceKeyForModule(@"transitionStyle", slot)] = transition[(NSUInteger)preset];
        changes[CCBGPreferenceKeyForModule(@"crossfadeDuration", slot)] = duration[(NSUInteger)preset];
        changes[CCBGPreferenceKeyForModule(@"noRepeatCount", slot)] = noRepeat[(NSUInteger)preset];
    }
    if (CCBGApplyQuickConfigurationChanges(changes, @"切换性能档位")) { [self reloadWorkspaceSnapshot]; [self.tableView reloadData]; }
}
@end
