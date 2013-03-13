#import <UIKit/UIKit.h>

@interface QWScreenViewManager : NSObject

+ (instancetype)sharedInstance;

- (void)addView:(UIView *)view;
- (void)removeView:(UIView *)view;

@end
