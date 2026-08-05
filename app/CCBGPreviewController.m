#import "CCBGAppControllers.h"
#import "CCBGMediaCatalog.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

static double CCBGPreviewNumber(NSDictionary *item, NSString *key, double fallback) {
    id value = item[key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

static BOOL CCBGPreviewBool(NSDictionary *item, NSString *key, BOOL fallback) {
    id value = item[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

@interface CCBGPreviewController ()
@property(nonatomic, strong) NSDictionary *item;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerViewController *playerController;
@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIView *dimView;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic) NSUInteger playbackGeneration;
@property(nonatomic) BOOL restartingLoop;
@property(nonatomic) BOOL didPresentPreview;
@property(nonatomic) CGRect lastStatusBounds;
@property(nonatomic) CGRect lastStatusFrame;
@property(nonatomic) BOOL hasStatusLayout;
@end

@implementation CCBGPreviewController
- (instancetype)initWithMediaItem:(NSDictionary *)item {
    self = [super init];
    if (self) {
        _item = [item copy];
        self.title = @"预览";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.clipsToBounds = YES;

    self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.imageView];

    self.blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.blurView.frame = self.view.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurView.userInteractionEnabled = NO;
    [self.view addSubview:self.blurView];

    self.dimView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dimView.backgroundColor = UIColor.blackColor;
    self.dimView.userInteractionEnabled = NO;
    [self.view addSubview:self.dimView];

    self.statusLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = UIColor.whiteColor;
    self.statusLabel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.82];
    self.statusLabel.layer.cornerRadius = 16.0;
    self.statusLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusLabel.layer.masksToBounds = YES;
    self.statusLabel.layer.borderWidth = 0.5;
    self.statusLabel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.hidden = YES;
    self.statusLabel.alpha = 0.0;
    [self.view addSubview:self.statusLabel];

    [self configureDisplay];
    [self loadMedia];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.statusLabel.hidden && self.statusLabel.text.length) {
        if (self.hasStatusLayout && CGRectEqualToRect(self.lastStatusBounds, self.view.bounds)) return;
        CGFloat maxWidth = MAX(140.0, MIN(CGRectGetWidth(self.view.bounds) - 48.0, 320.0));
        CGSize fitting = [self.statusLabel sizeThatFits:CGSizeMake(maxWidth - 28.0, 80.0)];
        CGFloat width = MIN(maxWidth, MAX(140.0, fitting.width + 28.0));
        CGFloat height = MIN(80.0, MAX(44.0, fitting.height + 18.0));
        CGRect frame = CGRectMake(CGRectGetMidX(self.view.bounds) - width * 0.5,
                                  CGRectGetMidY(self.view.bounds) - height * 0.5,
                                  width, height);
        if (!self.hasStatusLayout || !CGRectEqualToRect(self.lastStatusFrame, frame)) self.statusLabel.frame = frame;
        self.lastStatusBounds = self.view.bounds;
        self.lastStatusFrame = frame;
        self.hasStatusLayout = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.didPresentPreview) {
        self.didPresentPreview = YES;
        BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
        self.view.alpha = 0.0;
        self.view.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.985, 0.985);
        if (reduceMotion) {
            [UIView animateWithDuration:0.16
                                  delay:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{ self.view.alpha = 1.0; }
                             completion:nil];
        } else {
            [UIView animateWithDuration:0.28
                                  delay:0.0
                 usingSpringWithDamping:1.0
                  initialSpringVelocity:0.0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                self.view.alpha = 1.0;
                self.view.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    } else {
        self.view.alpha = 1.0;
        self.view.transform = CGAffineTransformIdentity;
    }
    if (!self.player) return;
    [self.player play];
    self.player.rate = MIN(2.0, MAX(0.5, CCBGPreviewNumber(self.item, @"playbackRate", 1.0)));
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.player pause];
    self.didPresentPreview = NO;
}

- (void)dealloc {
    self.playbackGeneration++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.player pause];
}

- (void)configureDisplay {
    NSInteger mode = (NSInteger)CCBGPreviewNumber(self.item, @"contentMode", 1.0);
    self.imageView.contentMode = mode == 0 ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    self.playerController.videoGravity = mode == 0 ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    if (self.playerController) {
        // Keep native transport controls clear and readable for video previews.
        self.blurView.alpha = 0;
        self.dimView.alpha = 0;
        self.playerController.view.alpha = 1.0;
        return;
    }
    self.blurView.alpha = MIN(1.0, MAX(0.0, CCBGPreviewNumber(self.item, @"blurIntensity", 0.25)));
    self.dimView.alpha = MIN(0.9, MAX(0.0, CCBGPreviewNumber(self.item, @"dim", 0.0)));
    CGFloat opacity = MIN(1.0, MAX(0.05, CCBGPreviewNumber(self.item, @"opacity", 1.0)));
    self.imageView.alpha = opacity;
    self.playerController.view.alpha = opacity;
}

- (void)loadMedia {
    NSString *path = CCBGPathForItem(self.item);
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showStatus:@"素材文件不存在"];
        return;
    }
    if (!CCBGIsVideoName(self.item[@"fileName"])) {
        NSUInteger generation = ++self.playbackGeneration;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.playbackGeneration) return;
                if (!image) {
                    [self showStatus:@"图片无法读取"];
                    return;
                }
                self.imageView.image = image;
            });
        });
        return;
    }

    NSUInteger generation = ++self.playbackGeneration;
    __weak typeof(self) weakSelf = self;
    CCBGLoadVideoOnlyAsset(path, ^(AVAsset *videoOnlyAsset, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.playbackGeneration) return;
        if (!videoOnlyAsset) {
            [self showStatus:error.localizedDescription ?: @"视频无法读取"];
            return;
        }
        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:videoOnlyAsset];
        self.player = [AVPlayer playerWithPlayerItem:playerItem];
        self.player.preventsDisplaySleepDuringVideoPlayback = NO;
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        self.player.muted = CCBGPreviewBool(self.item, @"mute", YES);
        self.playerController = [AVPlayerViewController new];
        self.playerController.player = self.player;
        self.playerController.showsPlaybackControls = YES;
        self.playerController.allowsPictureInPicturePlayback = YES;
        self.playerController.view.frame = self.view.bounds;
        self.playerController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addChildViewController:self.playerController];
        [self.view insertSubview:self.playerController.view atIndex:0];
        [self.playerController didMoveToParentViewController:self];
        [self configureDisplay];
        self.playerController.view.alpha = 0.0;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(videoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
        NSTimeInterval start = MAX(0.0, CCBGPreviewNumber(self.item, @"startTime", 0.0));
        if (start > 0) [self.player seekToTime:CMTimeMakeWithSeconds(start, 600)];
        if (self.view.window) {
            [self.player play];
            self.player.rate = MIN(2.0, MAX(0.5, CCBGPreviewNumber(self.item, @"playbackRate", 1.0)));
        }
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.12 : 0.22
                              delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self.playerController.view.alpha = 1.0; }
                         completion:nil];
    });
}

- (void)videoEnded:(NSNotification *)notification {
    if (notification.object != self.player.currentItem ||
        !CCBGPreviewBool(self.item, @"loop", YES) || self.restartingLoop) return;
    self.restartingLoop = YES;
    NSTimeInterval start = MAX(0.0, CCBGPreviewNumber(self.item, @"startTime", 0.0));
    AVPlayer *player = self.player;
    [player pause];
    [player seekToTime:CMTimeMakeWithSeconds(start, 600)
       toleranceBefore:kCMTimeZero
        toleranceAfter:kCMTimeZero
     completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.player != player) {
                self.restartingLoop = NO;
                return;
            }
            self.restartingLoop = NO;
            if (!finished || !self.view.window) return;
            [player playImmediatelyAtRate:MIN(2.0, MAX(0.5, CCBGPreviewNumber(self.item, @"playbackRate", 1.0)))];
        });
    }];
}

- (void)showStatus:(NSString *)text {
    self.statusLabel.text = text;
    self.statusLabel.frame = CGRectZero;
    self.hasStatusLayout = NO;
    self.statusLabel.hidden = NO;
    self.blurView.alpha = 0;
    self.dimView.alpha = 0;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    self.statusLabel.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:reduceMotion ? 0.12 : 0.20
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.statusLabel.alpha = 1.0;
        self.statusLabel.transform = CGAffineTransformIdentity;
    } completion:nil];
}
@end
