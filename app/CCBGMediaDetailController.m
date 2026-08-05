#import "CCBGAppControllers.h"
#import "CCBGControls.h"
#import "CCBGMediaCatalog.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

static BOOL CCBGPreferenceValueContainsMediaName(id value, NSString *fileName) {
    if (!fileName.length || !value) return NO;
    if ([value isKindOfClass:NSString.class]) return [value isEqualToString:fileName];
    if ([value isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)value) if (CCBGPreferenceValueContainsMediaName(entry, fileName)) return YES;
        return NO;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        for (id entry in [(NSDictionary *)value allValues]) if (CCBGPreferenceValueContainsMediaName(entry, fileName)) return YES;
    }
    return NO;
}

@interface CCBGMediaDetailController () <UITextFieldDelegate>
@property(nonatomic, strong) NSMutableDictionary *item;
@property(nonatomic, strong) UITextField *nameField;
@property(nonatomic) NSTimeInterval videoDuration;
@property(nonatomic) unsigned long long fileBytes;
@property(nonatomic) CGSize pixelSize;
@property(nonatomic) NSInteger moduleSlot;
@property(nonatomic) NSUInteger metadataGeneration;
@end

@implementation CCBGMediaDetailController
- (instancetype)initWithMediaItem:(NSDictionary *)item {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _moduleSlot = CCBGActiveModuleSlot();
        _item = [CCBGMediaItemForModule(item, _moduleSlot) mutableCopy];
        self.title = [NSString stringWithFormat:@"%@ 素材参数", CCBGModuleDisplayNames()[(NSUInteger)_moduleSlot]];
        _videoDuration = 1.0;
    }
    return self;
}

- (void)loadMediaMetadata {
    NSString *path = [CCBGPathForItem(self.item) copy];
    BOOL video = CCBGIsVideoName(self.item[@"fileName"]);
    NSUInteger generation = ++self.metadataGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        unsigned long long fileBytes = [attributes[NSFileSize] unsignedLongLongValue];
        NSTimeInterval duration = 1.0;
        CGSize pixelSize = CGSizeZero;
        if (video) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            duration = MAX(1.0, CMTimeGetSeconds(asset.duration));
            if (!isfinite(duration)) duration = 300.0;
            AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
            if (track) {
                pixelSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
                pixelSize = CGSizeMake(fabs(pixelSize.width), fabs(pixelSize.height));
            }
        } else {
            CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
            if (source) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
                pixelSize = CGSizeMake([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],
                                        [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue]);
                CFRelease(source);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.metadataGeneration) return;
            self.fileBytes = fileBytes;
            self.videoDuration = duration;
            self.pixelSize = pixelSize;
            if (self.isViewLoaded) {
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)] withRowAnimation:UITableViewRowAnimationNone];
            }
        });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *fileName = self.item[@"fileName"];
    NSDictionary *sharedItem = CCBGMediaItemNamed(CCBGLoadMediaCatalog(), fileName);
    if (sharedItem) self.item = [CCBGMediaItemForModule(sharedItem, self.moduleSlot) mutableCopy];
    [self.tableView reloadData];
    [self loadMediaMetadata];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveCurrentItem) object:nil];
    [self saveCurrentItem];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 6;
    if (section == 1) return CCBGIsVideoName(self.item[@"fileName"]) ? 8 : 0;
    if (section == 2) return 15;
    if (section == 3) return 7;
    return 7;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger mode = [CCBGReadModulePreference(@"playbackMode", self.moduleSlot, @0) integerValue];
    BOOL slideshow = [CCBGReadModulePreference(@"slideshowEnabled", self.moduleSlot, @NO) boolValue];
    if (indexPath.section == 0 && indexPath.row == 3 && mode != 2) return 0.01;
    if (indexPath.section == 1 && indexPath.row >= 6 && (mode == 0 || !slideshow)) return 0.01;
    if (indexPath.section == 3 && indexPath.row == 3 && (mode == 0 || !slideshow)) return 0.01;
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = [self tableView:tableView heightForRowAtIndexPath:indexPath];
    cell.hidden = height >= 0 && height < 1.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"基本信息", @"视频播放", @"画面效果", @"文件信息", @"操作"][(NSUInteger)section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) return [self nameCell:tableView];
    if (indexPath.section == 0 && indexPath.row == 1) return [self switchCell:tableView title:@"启用此素材" key:@"enabled"];
    if (indexPath.section == 0 && indexPath.row == 2) return [self switchCell:tableView title:@"收藏" key:@"favorite"];
    if (indexPath.section == 0 && indexPath.row == 3) return [self sliderCell:tableView title:@"随机权重" key:@"randomWeight" minimum:0.1 maximum:10.0 format:@"%.1fx"];
    if (indexPath.section == 0 && indexPath.row == 4) return [self metadataTextCell:tableView title:@"分组" key:@"group"];
    if (indexPath.section == 0) return [self metadataTextCell:tableView title:@"标签" key:@"tags"];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return [self switchCell:tableView title:@"静音" key:@"mute"];
        if (indexPath.row == 1) return [self switchCell:tableView title:@"循环播放" key:@"loop"];
        if (indexPath.row == 2) return [self sliderCell:tableView title:@"播放速度" key:@"playbackRate" minimum:0.5 maximum:2.0 format:@"%.2fx"];
        if (indexPath.row == 3) return [self sliderCell:tableView title:@"开始时间" key:@"startTime" minimum:0 maximum:self.videoDuration format:@"%.1f 秒"];
        if (indexPath.row == 4) return [self sliderCell:tableView title:@"结束时间（0 为完整）" key:@"endTime" minimum:0 maximum:self.videoDuration format:@"%.1f 秒"];
        if (indexPath.row == 5) return [self sliderCell:tableView title:@"封面帧时间" key:@"coverFrameTime" minimum:0 maximum:self.videoDuration format:@"%.1f 秒"];
        if (indexPath.row == 6) {
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"videoPolicy"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"videoPolicy"];
            [cell configureWithTitle:@"视频衔接" key:@"videoAdvancePolicy" items:@[@"播完切换", @"播放次数"] selected:[self.item[@"videoAdvancePolicy"] integerValue] target:self action:@selector(segmentChanged:)];
            return cell;
        }
        return [self sliderCell:tableView title:@"切换前播放次数" key:@"videoPlayCount" minimum:1 maximum:10 format:@"%.0f 次"];
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"segment"];
            if (!cell) cell = [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"segment"];
            [cell configureWithTitle:@"显示方式" key:@"contentMode" items:@[@"完整", @"填充"] selected:[self.item[@"contentMode"] integerValue] target:self action:@selector(segmentChanged:)];
            return cell;
        }
        if (indexPath.row == 8) return [self switchCell:tableView title:@"自动取色背景" key:@"autoColor"];
        if (indexPath.row == 9 || indexPath.row == 10) {
            NSString *key = indexPath.row == 9 ? @"portraitContentMode" : @"landscapeContentMode";
            CCBGSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"orientationMode"] ?: [[CCBGSegmentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"orientationMode"];
            [cell configureWithTitle:indexPath.row == 9 ? @"竖屏显示" : @"横屏显示" key:key items:@[@"默认", @"完整", @"填充"] selected:[self.item[key] integerValue] + 1 target:self action:@selector(orientationSegmentChanged:)];
            return cell;
        }
        if (indexPath.row >= 11) {
            NSArray *titles = @[@"竖屏焦点 X", @"竖屏焦点 Y", @"横屏焦点 X", @"横屏焦点 Y"];
            NSArray *keys = @[@"portraitFocalX", @"portraitFocalY", @"landscapeFocalX", @"landscapeFocalY"];
            NSUInteger index = indexPath.row - 11;
            return [self sliderCell:tableView title:titles[index] key:keys[index] minimum:-1 maximum:1 format:@"%.2f"];
        }
        NSArray *titles = @[@"模糊", @"压暗", @"饱和度", @"对比度", @"透明度", @"焦点 X", @"焦点 Y"];
        NSArray *keys = @[@"blurIntensity", @"dim", @"saturation", @"contrast", @"opacity", @"focalX", @"focalY"];
        NSArray *mins = @[@0, @0, @0, @0.5, @0.05, @0, @0];
        NSArray *maxs = @[@1, @0.9, @2, @2, @1, @1, @1];
        NSUInteger i = indexPath.row - 1;
        return [self sliderCell:tableView title:titles[i] key:keys[i] minimum:[mins[i] floatValue] maximum:[maxs[i] floatValue] format:@"%.2f"];
    }
    if (indexPath.section == 3) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"info"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"格式";
            cell.detailTextLabel.text = [self.item[@"fileName"] pathExtension].uppercaseString;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"分辨率";
            cell.detailTextLabel.text = self.pixelSize.width > 0 ? [NSString stringWithFormat:@"%.0f × %.0f", self.pixelSize.width, self.pixelSize.height] : @"未知";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"文件大小";
            cell.detailTextLabel.text = CCBGReadableBytes(self.fileBytes);
        } else if (indexPath.row == 3) {
            return [self sliderCell:tableView title:@"图片独立停留" key:@"imageDuration" minimum:0 maximum:120 format:@"%.0f 秒"];
        } else if (indexPath.row == 4 || indexPath.row == 5) {
            return [self dateCell:tableView title:indexPath.row == 4 ? @"生效日期" : @"失效日期" key:indexPath.row == 4 ? @"validFrom" : @"validUntil"];
        } else {
            cell.textLabel.text = @"故障隔离";
            cell.detailTextLabel.text = [self.item[@"failureReason"] length] ? self.item[@"failureReason"] : @"正常";
            cell.accessoryType = [self.item[@"failureReason"] length] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        }
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = indexPath.row == 6 ? UIColor.systemRedColor : self.view.tintColor;
    cell.textLabel.text = @[@"预览", @"可视化构图", @"设为常显背景", @"查看使用位置", @"重置此素材参数", @"在 Filza 中打开", @"删除素材"][indexPath.row];
    return cell;
}

- (UITableViewCell *)nameCell:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"name"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"name"];
        self.nameField = [UITextField new];
        self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        self.nameField.returnKeyType = UIReturnKeyDone;
        self.nameField.delegate = self;
        [self.nameField addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
        [cell.contentView addSubview:self.nameField];
        [NSLayoutConstraint activateConstraints:@[
            [self.nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [self.nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [self.nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [self.nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [self.nameField.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
    }
    self.nameField.text = CCBGDisplayNameForItem(self.item);
    return cell;
}

- (CCBGSwitchCell *)switchCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key {
    CCBGSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch"];
    if (!cell) cell = [[CCBGSwitchCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"switch"];
    [cell configureWithTitle:title key:key value:[self.item[key] boolValue] target:self action:@selector(switchChanged:)];
    return cell;
}

- (UITableViewCell *)metadataTextCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:key];
    UITextField *field = nil;
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:key];
        field = [UITextField new]; field.textAlignment = NSTextAlignmentRight; field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.accessibilityIdentifier = key; [field addTarget:self action:@selector(metadataChanged:) forControlEvents:UIControlEventEditingChanged];
        cell.accessoryView = field; field.frame = CGRectMake(0, 0, 210, 36);
    } else field = (UITextField *)cell.accessoryView;
    cell.textLabel.text = title;
    field.placeholder = [key isEqualToString:@"tags"] ? @"逗号分隔" : @"未分组";
    field.text = [key isEqualToString:@"tags"] ? [self.item[key] componentsJoinedByString:@", "] : self.item[key];
    return cell;
}

- (UITableViewCell *)dateCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:key];
    UIDatePicker *picker = nil;
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:key]; picker = [UIDatePicker new]; picker.datePickerMode = UIDatePickerModeDate; picker.preferredDatePickerStyle = UIDatePickerStyleCompact; picker.accessibilityIdentifier = key; [picker addTarget:self action:@selector(dateChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = picker; } else picker = (UIDatePicker *)cell.accessoryView;
    cell.textLabel.text = title; NSTimeInterval value = [self.item[key] doubleValue]; picker.date = value > 0 ? [NSDate dateWithTimeIntervalSince1970:value] : NSDate.date; return cell;
}

- (CCBGSliderCell *)sliderCell:(UITableView *)tableView title:(NSString *)title key:(NSString *)key minimum:(float)minimum maximum:(float)maximum format:(NSString *)format {
    CCBGSliderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider"];
    if (!cell) cell = [[CCBGSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"slider"];
    [cell configureWithTitle:title key:key value:[self.item[key] floatValue] minimum:minimum maximum:maximum format:format target:self action:@selector(sliderChanged:)];
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    self.item[sender.accessibilityIdentifier] = @(sender.on);
    [self saveCurrentItem];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    self.item[sender.accessibilityIdentifier] = @(sender.selectedSegmentIndex);
    [self saveCurrentItem];
}

- (void)orientationSegmentChanged:(UISegmentedControl *)sender { self.item[sender.accessibilityIdentifier] = @(sender.selectedSegmentIndex - 1); [self saveCurrentItem]; }
- (void)metadataChanged:(UITextField *)sender { if ([sender.accessibilityIdentifier isEqualToString:@"tags"]) { NSArray *parts = [sender.text componentsSeparatedByString:@","]; NSMutableArray *tags = [NSMutableArray array]; for (NSString *part in parts) { NSString *tag = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (tag.length) [tags addObject:tag]; } self.item[@"tags"] = tags; } else self.item[sender.accessibilityIdentifier] = sender.text ?: @""; [self saveCurrentItem]; }
- (void)dateChanged:(UIDatePicker *)sender { self.item[sender.accessibilityIdentifier] = @(sender.date.timeIntervalSince1970); [self saveCurrentItem]; }

- (void)sliderChanged:(UISlider *)sender {
    self.item[sender.accessibilityIdentifier] = @(sender.value);
    UIView *view = sender;
    while (view && ![view isKindOfClass:CCBGSliderCell.class]) view = view.superview;
    [(CCBGSliderCell *)view refreshValueLabel];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveCurrentItem) object:nil];
    [self performSelector:@selector(saveCurrentItem) withObject:nil afterDelay:0.12];
}

- (void)nameChanged:(UITextField *)sender {
    self.item[@"displayName"] = sender.text.length ? sender.text : self.item[@"fileName"];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveCurrentItem) object:nil];
    [self performSelector:@selector(saveCurrentItem) withObject:nil afterDelay:0.2];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self saveCurrentItem];
    return YES;
}

- (void)saveCurrentItem {
    NSMutableArray *catalog = [CCBGLoadMediaCatalog() mutableCopy];
    NSUInteger index = [catalog indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
        return [candidate[@"fileName"] isEqualToString:self.item[@"fileName"]];
    }];
    if (index != NSNotFound) {
        NSMutableDictionary *sharedItem = [catalog[index] mutableCopy];
        for (NSString *key in @[@"displayName", @"enabled", @"favorite", @"group", @"tags", @"validFrom", @"validUntil", @"failureReason", @"fileHash", @"dominantColor", @"coverFrameTime", @"playCount", @"lastPlayedAt", @"addedAt"]) {
            if (self.item[key]) sharedItem[key] = self.item[key];
        }
        catalog[index] = sharedItem;
        CCBGSaveMediaCatalog(catalog);
        CCBGSaveModuleMediaConfiguration(self.item, self.moduleSlot);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3 && indexPath.row == 6 && [self.item[@"failureReason"] length]) { self.item[@"failureReason"] = @""; CCBGClearMediaFailure(self.item[@"fileName"]); CCBGPostReload(); [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic]; return; }
    if (indexPath.section != 4) return;
    if (indexPath.row == 0) {
        [self.navigationController pushViewController:[[CCBGPreviewController alloc] initWithMediaItem:self.item] animated:YES];
    } else if (indexPath.row == 1) {
        [self.navigationController pushViewController:[[CCBGCompositionEditorController alloc] initWithMediaItem:self.item moduleSlot:self.moduleSlot] animated:YES];
    } else if (indexPath.row == 2) {
        CCBGSelectModuleMedia(self.item[@"fileName"], self.moduleSlot, YES);
    } else if (indexPath.row == 3) {
        [self showMediaUsageLocations];
    } else if (indexPath.row == 4) {
        [self resetCurrentItem];
    } else if (indexPath.row == 5) {
        [self openCurrentItemInFilza];
    } else {
        [self confirmDelete];
    }
}

- (NSString *)usageLabelForPreferenceKey:(NSString *)key {
    if ([key hasPrefix:@"module"] && key.length > 7) {
        NSRange dot = [key rangeOfString:@"."];
        NSInteger slot = dot.location != NSNotFound ? [[key substringWithRange:NSMakeRange(6, dot.location - 6)] integerValue] : NSNotFound;
        if (slot >= 0 && slot < (NSInteger)CCBGModuleDisplayNames().count) {
            NSString *suffix = [key substringFromIndex:dot.location + 1];
            NSDictionary *labels = @{
                @"selectedMedia": @"固定素材", @"currentMedia": @"当前素材",
                @"portraitMedia": @"竖屏素材", @"landscapeMedia": @"横屏素材",
                @"privateMedia": @"隐私素材", @"lightModeMedia": @"浅色素材",
                @"darkModeMedia": @"深色素材",
            };
            return [NSString stringWithFormat:@"五模块 · %@ · %@", CCBGModuleDisplayNames()[(NSUInteger)slot], labels[suffix] ?: suffix];
        }
    }
    NSDictionary<NSString *, NSString *> *overlays = @{
        @"connectivityOverlay": @"连接", @"musicOverlay": @"音乐",
        @"brightnessOverlay": @"亮度", @"volumeOverlay": @"音量",
    };
    for (NSString *prefix in overlays) {
        if ([key hasPrefix:prefix]) return [NSString stringWithFormat:@"系统模块 · %@ · %@", overlays[prefix], [key substringFromIndex:prefix.length]];
    }
    if ([key localizedCaseInsensitiveContainsString:@"sceneDirector"]) return @"场景导演";
    if ([key localizedCaseInsensitiveContainsString:@"visualTheme"]) return @"视觉主题";
    if ([key localizedCaseInsensitiveContainsString:@"playlist"]) return @"播放列表";
    if ([key localizedCaseInsensitiveContainsString:@"profile"]) return @"配置方案";
    return [NSString stringWithFormat:@"其他配置 · %@", key];
}

- (NSArray<NSString *> *)mediaUsageLocations {
    NSString *fileName = self.item[@"fileName"];
    NSDictionary<NSString *, id> *preferences = CCBGReadAllPreferences();
    NSMutableOrderedSet<NSString *> *locations = [NSMutableOrderedSet orderedSet];
    [preferences enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key isEqualToString:@"mediaCatalog"] || [key hasSuffix:@".mediaOverrides"] ||
            [key hasSuffix:@"FailureCounts"] || [key hasSuffix:@"RecentMedia"]) return;
        if (CCBGPreferenceValueContainsMediaName(value, fileName)) [locations addObject:[self usageLabelForPreferenceKey:key]];
    }];
    return [locations.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)showMediaUsageLocations {
    NSArray<NSString *> *locations = [self mediaUsageLocations];
    NSString *message = @"当前没有模块、场景或播放列表引用此素材。";
    if (locations.count) {
        NSUInteger visibleCount = MIN((NSUInteger)24, locations.count);
        message = [[locations subarrayWithRange:NSMakeRange(0, visibleCount)] componentsJoinedByString:@"\n"];
        if (locations.count > visibleCount) message = [message stringByAppendingFormat:@"\n…另外 %lu 处", (unsigned long)(locations.count - visibleCount)];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"使用位置（%lu）", (unsigned long)locations.count] message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openCurrentItemInFilza {
    NSString *path = CCBGPathForItem(self.item);
    NSURL *url = CCBGFilzaURLForPath(path);
    if (url && [UIApplication.sharedApplication canOpenURL:url]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开 Filza" message:path preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetCurrentItem {
    CCBGResetModuleMediaConfiguration(self.item[@"fileName"], self.moduleSlot);
    NSMutableDictionary *defaults = [CCBGMediaItemForModule(CCBGDefaultMediaItem(self.item[@"fileName"]), self.moduleSlot) mutableCopy];
    defaults[@"displayName"] = self.item[@"displayName"] ?: defaults[@"displayName"];
    defaults[@"enabled"] = self.item[@"enabled"] ?: @YES;
    defaults[@"favorite"] = self.item[@"favorite"] ?: @NO;
    self.item = defaults;
    [self saveCurrentItem];
    [self.tableView reloadData];
}

- (void)confirmDelete {
    NSArray<NSString *> *locations = [self mediaUsageLocations];
    NSString *message = nil;
    if (locations.count) {
        NSUInteger visibleCount = MIN((NSUInteger)6, locations.count);
        NSString *summary = [[locations subarrayWithRange:NSMakeRange(0, visibleCount)] componentsJoinedByString:@"\n"];
        message = [NSString stringWithFormat:@"此素材仍被 %lu 处配置引用。删除后这些位置将无法继续使用它。\n\n%@%@", (unsigned long)locations.count, summary,
                   locations.count > visibleCount ? @"\n…" : @""];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除这个素材？" message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *path = CCBGPathForItem(weakSelf.item);
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path] && ![[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
            UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"无法删除素材" message:error.localizedDescription ?: path preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:failure animated:YES completion:nil];
            return;
        }
        CCBGRemoveMediaConfigurationFromAllModules(weakSelf.item[@"fileName"]);
        CCBGSaveMediaCatalog(CCBGLoadMediaCatalog());
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
