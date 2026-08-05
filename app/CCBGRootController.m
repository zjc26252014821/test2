#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <PhotosUI/PhotosUI.h>
#import <Photos/Photos.h>

@interface CCBGRootController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UISearchResultsUpdating, UISearchBarDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) NSArray<NSDictionary *> *filteredItems;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) UIImageView *libraryIconView;
@property(nonatomic, strong) UILabel *libraryTitleLabel;
@property(nonatomic, strong) UILabel *librarySummaryLabel;
@property(nonatomic, copy) NSArray<UIImageView *> *coverPreviewViews;
@property(nonatomic) BOOL mediaLibraryExpanded;
@property(nonatomic) NSUInteger searchReloadGeneration;
@property(nonatomic, copy) NSString *catalogSignature;
@property(nonatomic, copy) NSString *renderedFilterSignature;
- (BOOL)deleteItemAtIndex:(NSUInteger)index;
- (void)showMediaTools;
- (void)openMediaDirectoryInFilza;
- (NSString *)thumbnailCacheKeyForItem:(NSDictionary *)item size:(CGSize)size prefix:(NSString *)prefix;
@end

@implementation CCBGRootController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"素材";
    self.mediaLibraryExpanded = [CCBGReadPreference(@"mediaLibraryExpanded", @YES) boolValue];
    self.thumbnailCache = [NSCache new];
    self.thumbnailCache.countLimit = 160;
    self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(showImportOptions)],
        self.editButtonItem,
    ];
    UIBarButtonItem *toolsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMediaTools)];
    toolsItem.accessibilityLabel = @"素材工具";
    self.navigationItem.leftBarButtonItem = toolsItem;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.placeholder = @"搜索素材名称";
    self.searchController.searchBar.scopeButtonTitles = @[@"全部", @"图片", @"视频", @"收藏", @"最近", @"故障"];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.sectionHeaderTopPadding = 12;
    [self buildLibraryHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateModulePrompt];
    self.libraryIconView.tintColor = CCBGAppAccentColor();
    NSArray<NSDictionary *> *catalog = CCBGLoadMediaCatalog();
    NSMutableString *signature = [NSMutableString stringWithCapacity:catalog.count * 64];
    for (NSDictionary *item in catalog) {
        id tags = item[@"tags"];
        NSString *tagSignature = [tags isKindOfClass:NSArray.class] ? [tags componentsJoinedByString:@","] : @"";
        [signature appendFormat:@"%@|%@|%@|%@|%@|%@|%@|%@|%@;",
            item[@"fileName"] ?: @"", CCBGDisplayNameForItem(item),
            [item[@"enabled"] boolValue] ? @"1" : @"0",
            [item[@"favorite"] boolValue] ? @"1" : @"0",
            item[@"fileSize"] ?: @0, item[@"fileModifiedAt"] ?: @0,
            item[@"lastPlayedAt"] ?: @0, item[@"failureReason"] ?: @"",
            tagSignature];
    }
    NSString *filterSignature = [NSString stringWithFormat:@"%@|%ld|%d",
        self.searchController.searchBar.text ?: @"",
        (long)self.searchController.searchBar.selectedScopeButtonIndex,
        self.mediaLibraryExpanded];
    BOOL catalogChanged = ![signature isEqualToString:self.catalogSignature];
    BOOL filterChanged = ![filterSignature isEqualToString:self.renderedFilterSignature];
    self.catalogSignature = signature.copy;
    self.renderedFilterSignature = filterSignature.copy;
    self.items = catalog;
    [self applyMediaFilters];
    [self updateLibraryHeader];
    [self updateCoverPreviews];
    if (catalogChanged || filterChanged || self.tableView.numberOfSections == 0) {
        [self.tableView reloadData];
    } else {
        NSMutableArray<NSIndexPath *> *visibleRows = [NSMutableArray array];
        for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows ?: @[]) {
            if (indexPath.section < [self.tableView numberOfSections] &&
                indexPath.row < [self.tableView numberOfRowsInSection:indexPath.section]) {
                [visibleRows addObject:indexPath];
            }
        }
        if (visibleRows.count) [self.tableView reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Do not let a queued search refresh wake a controller that is already
    // leaving the screen and rebuild cells behind the transition.
    self.searchReloadGeneration++;
}

- (void)buildLibraryHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 214)];
    header.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    header.layer.cornerRadius = 22.0;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    header.layer.borderWidth = 0.5;
    header.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.24].CGColor;
    header.layer.masksToBounds = YES;
    header.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 20);
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"photo.on.rectangle.angled"]];
    self.libraryIconView = icon;
    icon.tintColor = CCBGAppAccentColor();
    icon.backgroundColor = [CCBGAppAccentColor() colorWithAlphaComponent:0.14];
    icon.layer.cornerRadius = 12.0;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.layer.masksToBounds = YES;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    self.libraryTitleLabel = [UILabel new];
    self.libraryTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.libraryTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.libraryTitleLabel.adjustsFontSizeToFitWidth = YES;
    self.libraryTitleLabel.minimumScaleFactor = 0.85;
    self.libraryTitleLabel.text = @"共享素材库";
    self.libraryTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.librarySummaryLabel = [UILabel new];
    self.librarySummaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.librarySummaryLabel.adjustsFontForContentSizeCategory = YES;
    self.librarySummaryLabel.textColor = UIColor.secondaryLabelColor;
    self.librarySummaryLabel.numberOfLines = 2;
    self.librarySummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *covers = [[UIStackView alloc] init];
    covers.axis = UILayoutConstraintAxisHorizontal;
    covers.spacing = 8;
    covers.distribution = UIStackViewDistributionFillEqually;
    covers.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray *coverViews = [NSMutableArray array];
    NSArray<NSString *> *moduleNames = CCBGModuleDisplayNames();
    for (NSUInteger index = 0; index < moduleNames.count; index++) {
        UIImageView *cover = [UIImageView new];
        cover.contentMode = UIViewContentModeScaleAspectFill;
        cover.clipsToBounds = YES;
        cover.backgroundColor = UIColor.tertiarySystemFillColor;
        cover.layer.cornerRadius = 12;
        if (@available(iOS 13.0, *)) cover.layer.cornerCurve = kCACornerCurveContinuous;
        cover.layer.borderWidth = 0.5;
        cover.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.30].CGColor;
        UILabel *label = [UILabel new];
        label.text = moduleNames[index];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        label.textColor = UIColor.secondaryLabelColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.75;
        UIStackView *tile = [[UIStackView alloc] initWithArrangedSubviews:@[cover, label]];
        tile.axis = UILayoutConstraintAxisVertical;
        tile.spacing = 5;
        [cover.heightAnchor constraintEqualToConstant:54].active = YES;
        [covers addArrangedSubview:tile];
        [coverViews addObject:cover];
    }
    self.coverPreviewViews = coverViews;
    [header addSubview:icon];
    [header addSubview:self.libraryTitleLabel];
    [header addSubview:self.librarySummaryLabel];
    [header addSubview:covers];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [icon.topAnchor constraintEqualToAnchor:header.topAnchor constant:20],
        [icon.widthAnchor constraintEqualToConstant:34],
        [icon.heightAnchor constraintEqualToConstant:34],
        [self.libraryTitleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [self.libraryTitleLabel.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [self.libraryTitleLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:18],
        [self.librarySummaryLabel.leadingAnchor constraintEqualToAnchor:self.libraryTitleLabel.leadingAnchor],
        [self.librarySummaryLabel.trailingAnchor constraintEqualToAnchor:self.libraryTitleLabel.trailingAnchor],
        [self.librarySummaryLabel.topAnchor constraintEqualToAnchor:self.libraryTitleLabel.bottomAnchor constant:4],
        [covers.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [covers.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [covers.topAnchor constraintEqualToAnchor:self.librarySummaryLabel.bottomAnchor constant:12],
        [covers.heightAnchor constraintEqualToConstant:76],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)updateLibraryHeader {
    NSString *moduleName = CCBGModuleDisplayNames()[CCBGActiveModuleSlot()];
    self.librarySummaryLabel.text = [NSString stringWithFormat:@"%lu 项 · %@ · 正在配置 %@\n五个模块当前素材", (unsigned long)self.items.count, CCBGReadableBytes(CCBGMediaStorageBytes()), moduleName];
}

- (void)updateModulePrompt {
    self.navigationItem.prompt = nil;
}

- (NSArray *)activeModulePreviewItems {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:CCBGModuleDisplayNames().count];
    for (NSInteger slot = 0; slot < (NSInteger)CCBGModuleDisplayNames().count; slot++) {
        NSArray<NSDictionary *> *moduleItems = CCBGMediaItemsForModule(self.items ?: @[], slot);
        NSDictionary *item = CCBGMediaItemNamed(moduleItems, CCBGActiveModuleMediaName(slot));
        [result addObject:item ?: NSNull.null];
    }
    return result;
}

- (void)updateCoverPreviews {
    NSArray *previewItems = [self activeModulePreviewItems];
    [self.coverPreviewViews enumerateObjectsUsingBlock:^(UIImageView *cover, NSUInteger index, BOOL *stop) {
        if (index >= previewItems.count) {
            cover.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            cover.tintColor = UIColor.tertiaryLabelColor;
            cover.contentMode = UIViewContentModeScaleAspectFit;
            return;
        }
        id candidate = previewItems[index];
        if (![candidate isKindOfClass:NSDictionary.class]) {
            cover.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
            cover.tintColor = UIColor.tertiaryLabelColor;
            cover.contentMode = UIViewContentModeScaleAspectFit;
            return;
        }
        NSDictionary *item = candidate;
        CGSize thumbnailSize = CGSizeMake(180, 100);
        NSString *cacheKey = [self thumbnailCacheKeyForItem:item size:thumbnailSize prefix:@"cover-"];
        UIImage *thumbnail = [self.thumbnailCache objectForKey:cacheKey];
        cover.tintColor = UIColor.tertiaryLabelColor;
        cover.contentMode = thumbnail ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        cover.image = thumbnail ?: CCBGPlaceholderImageForItem(item);
        cover.accessibilityIdentifier = cacheKey;
        __weak UIImageView *weakCover = cover;
        CCBGLoadThumbnailForItem(item, thumbnailSize, ^(UIImage *loaded) {
            UIImageView *strongCover = weakCover;
            if (!loaded || ![strongCover.accessibilityIdentifier isEqualToString:cacheKey]) return;
            if (strongCover.image == loaded) return;
            [self.thumbnailCache setObject:loaded forKey:cacheKey];
            strongCover.contentMode = UIViewContentModeScaleAspectFill;
            if (UIAccessibilityIsReduceMotionEnabled()) {
                strongCover.image = loaded;
            } else {
                [UIView transitionWithView:strongCover
                                  duration:0.18
                                   options:UIViewAnimationOptionTransitionCrossDissolve |
                                           UIViewAnimationOptionBeginFromCurrentState |
                                           UIViewAnimationOptionAllowUserInteraction
                                animations:^{ strongCover.image = loaded; }
                                completion:nil];
            }
        });
    }];
}

- (NSArray<NSDictionary *> *)visibleItems { return self.filteredItems ?: self.items ?: @[]; }

- (NSString *)thumbnailCacheKeyForItem:(NSDictionary *)item size:(CGSize)size prefix:(NSString *)prefix {
    return CCBGThumbnailCacheKeyForItem(item, size, prefix ?: @"");
}

- (NSUInteger)catalogIndexForItem:(NSDictionary *)item {
    NSString *fileName = item[@"fileName"];
    return [self.items indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
        return [candidate[@"fileName"] isEqualToString:fileName];
    }];
}

- (void)reloadMediaSectionWithAnimation:(UITableViewRowAnimation)animation {
    [self applyMediaFilters];
    // This path already owns the immediate animated reload; invalidate the
    // coalesced search pass scheduled by updateSearchResultsForSearchController:.
    self.searchReloadGeneration++;
    [self updateLibraryHeader];
    [self updateCoverPreviews];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:animation];
}

- (BOOL)isFilteringMedia {
    return self.searchController.searchBar.text.length > 0 || self.searchController.searchBar.selectedScopeButtonIndex > 0;
}

- (void)applyMediaFilters {
    NSString *query = self.searchController.searchBar.text ?: @"";
    NSInteger scope = self.searchController.searchBar.selectedScopeButtonIndex;
    if (!query.length && scope == 0) {
        self.filteredItems = nil;
        return;
    }
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *item in self.items) {
        NSString *name = CCBGDisplayNameForItem(item);
        if (query.length && [name localizedCaseInsensitiveContainsString:query] == NO &&
            [item[@"fileName"] localizedCaseInsensitiveContainsString:query] == NO) continue;
        BOOL video = CCBGIsVideoName(item[@"fileName"]);
        if (scope == 1 && video) continue;
        if (scope == 2 && !video) continue;
        if (scope == 3 && ![item[@"favorite"] boolValue]) continue;
        if (scope == 4 && [item[@"lastPlayedAt"] doubleValue] <= 0) continue;
        if (scope == 5 && ![item[@"failureReason"] length]) continue;
        [matches addObject:item];
    }
    if (scope == 4) {
        [matches sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [right[@"lastPlayedAt"] compare:left[@"lastPlayedAt"]];
        }];
    }
    self.filteredItems = matches;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    if ((searchController.searchBar.text.length || searchController.searchBar.selectedScopeButtonIndex > 0) && !self.mediaLibraryExpanded) {
        self.mediaLibraryExpanded = YES;
        CCBGWritePreference(@"mediaLibraryExpanded", @YES);
    }
    [self applyMediaFilters];
    // Search callbacks arrive for every keystroke. Coalesce the table update
    // into one main-thread pass so thumbnail work and cell layout do not fight
    // the keyboard animation while the query is still changing.
    NSUInteger generation = ++self.searchReloadGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.searchReloadGeneration) return;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self updateSearchResultsForSearchController:self.searchController];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return self.mediaLibraryExpanded ? self.visibleItems.count : 0;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return nil;
    if (section == 0) return @"当前模块";
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 1) return nil;
    UITableViewHeaderFooterView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"mediaHeader"];
    if (!header) header = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:@"mediaHeader"];
    UIListContentConfiguration *content = [UIListContentConfiguration groupedHeaderConfiguration];
    content.text = [NSString stringWithFormat:@"媒体库 · %lu", (unsigned long)self.visibleItems.count];
    content.textProperties.color = UIColor.secondaryLabelColor;
    header.contentConfiguration = content;
    UIButton *button = (UIButton *)[header.contentView viewWithTag:713];
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 713;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [header.contentView addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:header.contentView.layoutMarginsGuide.trailingAnchor],
            [button.centerYAnchor constraintEqualToAnchor:header.contentView.centerYAnchor],
            [button.widthAnchor constraintEqualToConstant:36],
            [button.heightAnchor constraintEqualToConstant:36],
        ]];
    }
    [button setImage:[UIImage systemImageNamed:self.mediaLibraryExpanded ? @"chevron.up.circle.fill" : @"chevron.down.circle.fill"] forState:UIControlStateNormal];
    button.tintColor = CCBGAppAccentColor();
    button.accessibilityLabel = self.mediaLibraryExpanded ? @"收起媒体库" : @"展开媒体库";
    [button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [button addTarget:self action:@selector(toggleMediaLibrary) forControlEvents:UIControlEventTouchUpInside];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 1 ? 44.0 : UITableViewAutomaticDimension;
}

- (void)toggleMediaLibrary {
    self.mediaLibraryExpanded = !self.mediaLibraryExpanded;
    if (!self.mediaLibraryExpanded) self.editing = NO;
    CCBGWritePreference(@"mediaLibraryExpanded", @(self.mediaLibraryExpanded));
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"常显模式锁定所选背景并停用左右滑动；顺序和随机模式才允许手势切换。";
    if (section == 1 && !self.items.count) return @"点右上角加号导入图片或视频。";
    if (section == 1 && !self.mediaLibraryExpanded) return @"媒体库已收起，点区头右侧按钮展开。";
    if (section == 1 && !self.visibleItems.count) return @"没有符合当前搜索或筛选条件的素材。";
    if (section == 1) return @"缩略图会在后台生成并缓存；视频会抽取早期画面，列表滑动时先显示占位图。";
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return indexPath.row == 0 ? 50 : 82;
    if (indexPath.section == 1) return 70;
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"moduleSlot"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"moduleSlot"];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.textLabel.text = @"配置模块";
            cell.detailTextLabel.text = CCBGModuleDisplayNames()[CCBGActiveModuleSlot()];
            cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
            cell.imageView.tintColor = CCBGAppAccentColor();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mode"];
        if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"mode"];
        [cell configureWithTitle:@"素材切换方式" key:@"playbackMode" items:@[@"常显", @"顺序", @"随机"] selected:[CCBGReadModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @0) integerValue] target:self action:@selector(modeChanged:)];
        return cell;
    }
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"item"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"item"];
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        NSDictionary *item = self.visibleItems[indexPath.row];
        NSString *name = item[@"fileName"];
        NSString *kind = CCBGIsVideoName(name) ? @"视频" : @"图片";
        NSInteger playbackMode = [CCBGReadModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @0) integerValue];
        NSString *activeName = CCBGActiveModuleMediaName(CCBGActiveModuleSlot());
        BOOL selected = [name isEqualToString:activeName];
        CGSize thumbnailSize = CGSizeMake(54, 54);
        NSString *cacheKey = [self thumbnailCacheKeyForItem:item size:thumbnailSize prefix:@"cell-"];
        UIImage *thumbnail = [self.thumbnailCache objectForKey:cacheKey];
        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = CCBGDisplayNameForItem(item);
        content.secondaryText = [NSString stringWithFormat:@"%@%@%@%@", kind, [item[@"favorite"] boolValue] ? @" · 收藏" : @"", [item[@"enabled"] boolValue] ? @"" : @" · 已停用", selected ? (playbackMode == 0 ? @" · 常显" : @" · 当前") : @""];
        content.image = thumbnail ?: CCBGPlaceholderImageForItem(item);
        content.imageProperties.maximumSize = CGSizeMake(52, 52);
        content.imageProperties.reservedLayoutSize = CGSizeMake(52, 52);
        content.imageProperties.cornerRadius = 7;
        content.textProperties.color = [item[@"enabled"] boolValue] ? UIColor.labelColor : UIColor.secondaryLabelColor;
        content.secondaryTextProperties.color = selected ? CCBGAppAccentColor() : UIColor.secondaryLabelColor;
        cell.contentConfiguration = content;
        cell.accessibilityIdentifier = cacheKey;
        __weak UITableViewCell *weakCell = cell;
        CCBGLoadThumbnailForItem(item, thumbnailSize, ^(UIImage *loaded) {
            UITableViewCell *strongCell = weakCell;
            if (!loaded || ![strongCell.accessibilityIdentifier isEqualToString:cacheKey]) return;
            [self.thumbnailCache setObject:loaded forKey:cacheKey];
            UIListContentConfiguration *updated = (UIListContentConfiguration *)strongCell.contentConfiguration;
            updated.image = loaded;
            strongCell.contentConfiguration = updated;
        });
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nav"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"nav"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 0) {
        [self.navigationController pushViewController:[[CCBGModuleManagerController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
        return;
    }
    if (indexPath.section == 1) {
        NSDictionary *item = self.visibleItems[indexPath.row];
        if (![item[@"enabled"] boolValue]) {
            NSUInteger catalogIndex = [self catalogIndexForItem:item];
            if (catalogIndex != NSNotFound) [self setItemEnabled:YES atIndex:catalogIndex];
        }
        NSInteger slot = CCBGActiveModuleSlot();
        NSInteger mode = [CCBGReadModulePreference(@"playbackMode", slot, @0) integerValue];
        CCBGSelectModuleMedia(item[@"fileName"], slot, mode == 0);
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationAutomatic];
        return;
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return;
    [self.navigationController pushViewController:[[CCBGMediaDetailController alloc] initWithMediaItem:self.visibleItems[indexPath.row]] animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 1 && !self.isFilteringMedia; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 1; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 1) {
        NSUInteger catalogIndex = [self catalogIndexForItem:self.visibleItems[indexPath.row]];
        if (catalogIndex != NSNotFound) [self deleteItemAtIndex:catalogIndex];
    }
}
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source proposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section == 1) return proposed;
    return [NSIndexPath indexPathForRow:proposed.section < 1 ? 0 : MAX(0, (NSInteger)self.items.count - 1) inSection:1];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSMutableArray *items = [self.items mutableCopy];
    NSDictionary *item = items[source.row];
    [items removeObjectAtIndex:source.row];
    [items insertObject:item atIndex:destination.row];
    self.items = items;
    CCBGSaveMediaCatalog(items);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return nil;
    NSDictionary *item = self.visibleItems[indexPath.row];
    NSUInteger catalogIndex = [self catalogIndexForItem:item];
    if (catalogIndex == NSNotFound) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        completion([weakSelf deleteItemAtIndex:catalogIndex]);
    }];
    BOOL enabled = [item[@"enabled"] boolValue];
    UIContextualAction *toggle = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:enabled ? @"停用" : @"启用" handler:^(UIContextualAction *action, UIView *sourceView, void (^completion)(BOOL)) {
        [weakSelf setItemEnabled:!enabled atIndex:catalogIndex];
        completion(YES);
    }];
    toggle.backgroundColor = enabled ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[remove, toggle]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return nil;
    NSDictionary *item = self.visibleItems[indexPath.row];
    NSUInteger catalogIndex = [self catalogIndexForItem:item];
    if (catalogIndex == NSNotFound) return nil;
    BOOL favorite = [item[@"favorite"] boolValue];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:favorite ? @"取消收藏" : @"收藏" handler:^(UIContextualAction *contextAction, UIView *sourceView, void (^completion)(BOOL)) {
        [weakSelf setItemFavorite:!favorite atIndex:catalogIndex];
        completion(YES);
    }];
    action.backgroundColor = UIColor.systemYellowColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (indexPath.section != 1) return nil;
    NSDictionary *item = self.visibleItems[indexPath.row];
    NSUInteger catalogIndex = [self catalogIndexForItem:item];
    if (catalogIndex == NSNotFound) return nil;
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:item[@"fileName"] previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIAction *preview = [UIAction actionWithTitle:@"预览" image:[UIImage systemImageNamed:@"eye"] identifier:nil handler:^(UIAction *action) {
            NSDictionary *effectiveItem = CCBGMediaItemForModule(item, CCBGActiveModuleSlot());
            [weakSelf.navigationController pushViewController:[[CCBGPreviewController alloc] initWithMediaItem:effectiveItem] animated:YES];
        }];
        UIAction *detail = [UIAction actionWithTitle:@"素材设置" image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(UIAction *action) {
            [weakSelf.navigationController pushViewController:[[CCBGMediaDetailController alloc] initWithMediaItem:item] animated:YES];
        }];
        BOOL favorite = [item[@"favorite"] boolValue];
        UIAction *favoriteAction = [UIAction actionWithTitle:favorite ? @"取消收藏" : @"收藏" image:[UIImage systemImageNamed:favorite ? @"star.slash" : @"star"] identifier:nil handler:^(UIAction *action) {
            [weakSelf setItemFavorite:!favorite atIndex:catalogIndex];
        }];
        return [UIMenu menuWithTitle:CCBGDisplayNameForItem(item) children:@[preview, detail, favoriteAction]];
    }];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    NSInteger mode = MIN(2, MAX(0, sender.selectedSegmentIndex));
    CCBGWriteModulePreference(@"playbackMode", CCBGActiveModuleSlot(), @(mode));
    if (mode != 0) CCBGWriteModulePreference(@"slideshowEnabled", CCBGActiveModuleSlot(), @YES);
    [self.tableView reloadData];
}

- (void)setItemEnabled:(BOOL)enabled atIndex:(NSUInteger)index {
    NSMutableArray *items = [self.items mutableCopy];
    NSMutableDictionary *item = [items[index] mutableCopy];
    item[@"enabled"] = @(enabled);
    items[index] = item;
    self.items = items;
    CCBGSaveMediaCatalog(items);
    [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
}

- (void)setItemFavorite:(BOOL)favorite atIndex:(NSUInteger)index {
    NSMutableArray *items = [self.items mutableCopy];
    NSMutableDictionary *item = [items[index] mutableCopy];
    item[@"favorite"] = @(favorite);
    items[index] = item;
    self.items = items;
    CCBGSaveMediaCatalog(items);
    CCBGRecordSceneTimelineEvent(@"favorite-changed", @{ @"media": item[@"fileName"] ?: @"", @"favorite": @(favorite) });
    [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
}

- (BOOL)deleteItemAtIndex:(NSUInteger)index {
    if (index >= self.items.count) return NO;
    NSDictionary *item = self.items[index];
    NSString *path = CCBGPathForItem(item);
    NSError *error = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法删除素材" message:error.localizedDescription ?: path preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return NO;
    }
    NSMutableArray *items = [self.items mutableCopy];
    [items removeObjectAtIndex:index];
    self.items = items;
    CCBGSaveMediaCatalog(items);
    CCBGRemoveMediaConfigurationFromAllModules(item[@"fileName"]);
    [self.thumbnailCache removeAllObjects];
    [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
    return YES;
}

- (void)showPreview {
    NSInteger slot = CCBGActiveModuleSlot();
    NSDictionary *item = CCBGMediaItemNamed(self.items, CCBGActiveModuleMediaName(slot)) ?: self.items.firstObject;
    if (!item) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"暂无可预览素材" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSDictionary *effectiveItem = CCBGMediaItemForModule(item, slot);
    [self.navigationController pushViewController:[[CCBGPreviewController alloc] initWithMediaItem:effectiveItem] animated:YES];
}

- (void)showMediaTools {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"素材工具" message:@"管理共享素材目录与索引" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"在 Filza 打开素材目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openMediaDirectoryInFilza];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"重建素材索引" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CCBGPruneMissingMediaConfigurations();
        self.items = CCBGLoadMediaCatalog();
        CCBGSaveMediaCatalog(self.items);
        [self.thumbnailCache removeAllObjects];
        [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清除搜索与筛选" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.searchController.searchBar.text = @"";
        self.searchController.searchBar.selectedScopeButtonIndex = 0;
        [self applyMediaFilters];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)openMediaDirectoryInFilza {
    NSURL *url = CCBGFilzaURLForPath(CCBGMediaDirectoryPath);
    if (url && [UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSString *message = [NSString stringWithFormat:@"此功能用于在 Filza 文件管理器中查看共享素材目录。\n\n%@", CCBGMediaDirectoryPath];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未检测到 Filza" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showImportOptions {
    if (!self.mediaLibraryExpanded) {
        self.mediaLibraryExpanded = YES;
        CCBGWritePreference(@"mediaLibraryExpanded", @YES);
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"导入素材" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"从相册导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self importMediaFromPhotos];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"从文件导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self importMediaFromFiles];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)importMediaFromFiles {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage, UTTypeMovie] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importMediaFromPhotos {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter, PHPickerFilter.livePhotosFilter]];
    configuration.selectionLimit = 0;
    configuration.selection = PHPickerConfigurationSelectionOrdered;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!results.count) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:CCBGMediaDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray<NSDictionary *> *importedItems = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        PHAsset *asset = result.assetIdentifier.length ? [PHAsset fetchAssetsWithLocalIdentifiers:@[result.assetIdentifier] options:nil].firstObject : nil;
        if (asset && (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive)) {
            PHAssetResource *pairedVideo = nil;
            for (PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset]) {
                if (resource.type == PHAssetResourceTypePairedVideo || resource.type == PHAssetResourceTypeFullSizePairedVideo) { pairedVideo = resource; break; }
            }
            if (pairedVideo) {
                NSString *fileName = [NSString stringWithFormat:@"live-%@.mov", NSUUID.UUID.UUIDString];
                NSURL *destinationURL = [NSURL fileURLWithPath:[CCBGMediaDirectoryPath stringByAppendingPathComponent:fileName]];
                dispatch_group_enter(group);
                [[PHAssetResourceManager defaultManager] writeDataForAssetResource:pairedVideo toFile:destinationURL options:nil completionHandler:^(NSError *error) {
                    @synchronized (importedItems) {
                        if (!error) { NSMutableDictionary *item = [CCBGDefaultMediaItem(fileName) mutableCopy]; item[@"displayName"] = provider.suggestedName.length ? provider.suggestedName : @"Live Photo"; item[@"group"] = @"Live Photo"; [importedItems addObject:item]; }
                        else [failures addObject:provider.suggestedName ?: @"Live Photo"];
                    }
                    dispatch_group_leave(group);
                }];
                continue;
            }
        }
        BOOL video = [provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
        NSString *typeIdentifier = video ? UTTypeMovie.identifier : UTTypeImage.identifier;
        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL *url, NSError *error) {
            NSString *extension = url.pathExtension.lowercaseString;
            if (!extension.length) extension = video ? @"mov" : @"jpg";
            NSString *fileName = [NSString stringWithFormat:@"photo-%@.%@", NSUUID.UUID.UUIDString, extension];
            NSString *destination = [CCBGMediaDirectoryPath stringByAppendingPathComponent:fileName];
            NSError *copyError = nil;
            BOOL copied = url && [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&copyError];
            @synchronized (importedItems) {
                if (copied) {
                    NSMutableDictionary *item = [CCBGDefaultMediaItem(fileName) mutableCopy];
                    item[@"displayName"] = provider.suggestedName.length ? provider.suggestedName : (video ? @"相册视频" : @"相册图片");
                    item[@"group"] = @"相册";
                    [importedItems addObject:item];
                } else {
                    [failures addObject:provider.suggestedName ?: @"相册素材"];
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSMutableArray *catalog = [CCBGLoadMediaCatalog() mutableCopy];
        for (NSDictionary *importedItem in importedItems) {
            NSUInteger existingIndex = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
                return [candidate[@"fileName"] isEqualToString:importedItem[@"fileName"]];
            }];
            if (existingIndex == NSNotFound) {
                [catalog addObject:importedItem];
            } else {
                NSMutableDictionary *merged = [catalog[existingIndex] mutableCopy];
                [merged addEntriesFromDictionary:importedItem];
                catalog[existingIndex] = merged;
            }
        }
        self.items = catalog;
        CCBGSaveMediaCatalog(catalog);
        [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
        if (failures.count) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"部分相册素材导入失败" message:[failures componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [[NSFileManager defaultManager] createDirectoryAtPath:CCBGMediaDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *items = [CCBGLoadMediaCatalog() mutableCopy];
    NSMutableArray *failures = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSString *extension = url.pathExtension.lowercaseString;
        NSString *name = [NSString stringWithFormat:@"media-%.0f-%lu.%@", NSDate.date.timeIntervalSince1970 * 1000.0, (unsigned long)index++, extension];
        NSString *destination = [CCBGMediaDirectoryPath stringByAppendingPathComponent:name];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&error]) {
            [failures addObject:url.lastPathComponent ?: @"未知文件"];
        } else {
            NSMutableDictionary *item = [CCBGDefaultMediaItem(name) mutableCopy];
            item[@"displayName"] = url.lastPathComponent.stringByDeletingPathExtension ?: name.stringByDeletingPathExtension;
            item[@"group"] = url.URLByDeletingLastPathComponent.lastPathComponent ?: @"文件导入";
            [items addObject:item];
        }
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
    self.items = items;
    CCBGSaveMediaCatalog(items);
    [self reloadMediaSectionWithAnimation:UITableViewRowAnimationAutomatic];
    if (failures.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"部分文件导入失败" message:[failures componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
