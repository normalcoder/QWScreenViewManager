#import <UIKit/UIKit.h>

@interface QWScreenViewManager : NSObject

+ (instancetype)sharedInstance;

- (void)addView:(UIView *)view;

@end
