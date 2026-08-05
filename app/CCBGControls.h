#import <UIKit/UIKit.h>

@interface CCBGSwitchCell : UITableViewCell
@property(nonatomic, strong, readonly) UISwitch *toggle;
- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(BOOL)value target:(id)target action:(SEL)action;
@end

@interface CCBGSliderCell : UITableViewCell
@property(nonatomic, strong, readonly) UISlider *slider;
@property(nonatomic, strong, readonly) UILabel *valueLabel;
- (void)configureWithTitle:(NSString *)title key:(NSString *)key value:(float)value minimum:(float)minimum maximum:(float)maximum format:(NSString *)format target:(id)target action:(SEL)action;
- (void)refreshValueLabel;
@end

@interface CCBGSegmentCell : UITableViewCell
@property(nonatomic, strong, readonly) UISegmentedControl *segments;
- (void)configureWithTitle:(NSString *)title key:(NSString *)key items:(NSArray<NSString *> *)items selected:(NSInteger)selected target:(id)target action:(SEL)action;
@end

@interface CCBGGridSizePickerCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title
                     width:(NSInteger)width
                    height:(NSInteger)height
                 maximum:(NSInteger)maximum
                    target:(id)target
                    action:(SEL)action;
@end

@interface CCBGMediaPickerController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title selected:(NSString *)selected completion:(void (^)(NSString *fileName))completion;
@end

FOUNDATION_EXPORT NSString *CCBGReadableBytes(unsigned long long bytes);
FOUNDATION_EXPORT UIImage *CCBGThumbnailForItem(NSDictionary *item, CGSize size);
FOUNDATION_EXPORT UIImage *CCBGPlaceholderImageForItem(NSDictionary *item);
FOUNDATION_EXPORT NSString *CCBGThumbnailCacheKeyForItem(NSDictionary *item, CGSize size, NSString *prefix);
FOUNDATION_EXPORT void CCBGLoadThumbnailForItem(NSDictionary *item, CGSize size, void (^completion)(UIImage *thumbnail));
FOUNDATION_EXPORT void CCBGApplyThumbnailToCell(UITableViewCell *cell, NSDictionary *item, CGSize size, NSString *prefix);
FOUNDATION_EXPORT NSArray<NSDictionary *> *CCBGAppThemeOptions(void);
FOUNDATION_EXPORT UIColor *CCBGAppAccentColor(void);
FOUNDATION_EXPORT void CCBGApplyAppTheme(UIWindow *window);
FOUNDATION_EXPORT NSURL *CCBGFilzaURLForPath(NSString *path);
