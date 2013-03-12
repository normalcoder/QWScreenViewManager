#import "QWScreenViewManager.h"
#import <QWWeakMutableArray.h>


@interface QWSizeSet : NSObject
@property (nonatomic) CGSize initialSize;
@property (nonatomic) CGSize normalSize;
@end
@implementation QWSizeSet @end

@interface QWScreenViewManager () {
    QWWeakMutableArray * _views;
    NSMutableDictionary * _sizeSets;
}

@end


@implementation QWScreenViewManager

+ (instancetype)sharedInstance {
    static dispatch_once_t pred;
    static id instance;
    dispatch_once(&pred, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)commonInit {
    _views = [[QWWeakMutableArray alloc] init];
    _sizeSets = [[NSMutableDictionary alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputViewWillAppear:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputViewWillDisappear:) name:UIKeyboardWillHideNotification object:nil];
}

- (id)init {
    if ((self = [super init])) {
        [self commonInit];
    }
    return self;
}

#pragma mark -

static QWSizeSet * (^getSizeSet)(NSDictionary *, UIView *) = ^(NSDictionary * sizeSets, UIView * view) {
    QWSizeSet * oldSizeSet = sizeSets[@(((unsigned int)view))];
    if (oldSizeSet) {
        return oldSizeSet;
    } else {
        return [[QWSizeSet alloc] init];
    }
};

- (void)setNormalSize:(CGSize)size forView:(UIView *)view {
    QWSizeSet * (^newSizeSet)() = ^{
        QWSizeSet * sizeSet = getSizeSet(_sizeSets, view);
        sizeSet.normalSize = size;
        return sizeSet;
    };
    
    _sizeSets[@(((unsigned int)view))] = newSizeSet();
}

- (BOOL)isNormalSetForView:(UIView *)view {
    return _sizeSets[@(((unsigned int)view))] != nil;
}

- (CGSize)normalSizeForView:(UIView *)view {
    QWSizeSet * sizeSet = _sizeSets[@(((unsigned int)view))];
    return sizeSet.normalSize;
}

static UIScrollView * getScrollView(UIView * view) {
    BOOL (^isMainScrollView)(UIScrollView *) = ^BOOL (UIScrollView * scrollView){
        return
        [scrollView isKindOfClass:[UIScrollView class]]
        && ![scrollView isKindOfClass:[UITableView class]]
        && scrollView.bounds.size.width == view.bounds.size.width;
    };
    
    UIScrollView * (^scrollSubview)() = ^{
        for (UIScrollView * scrollSubview in [view subviews]) {
            if (isMainScrollView(scrollSubview)) {
                return scrollSubview;
            }
        }
        return (UIScrollView *)nil;
    };
    
    if ([view isKindOfClass:[UIScrollView class]] && ![view isKindOfClass:[UITableView class]]) {
        return (UIScrollView *)view;
    } else {
        return scrollSubview();
    }
}

- (void)addView:(UIView *)view {
    UIScrollView * scrollView = getScrollView(view);
    
    [_views addObject:view];
    scrollView.contentSize = scrollView.frame.size;
    
    [view addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([object isKindOfClass:[UIView class]]) {
        if ([keyPath isEqual:@"frame"]) {
            UIView * view = (UIView *)object;
            CGRect newFrame = [[change objectForKey:NSKeyValueChangeNewKey] CGRectValue];
            UIScrollView * scrollView = getScrollView(view);
            
            if (view != scrollView) {
                scrollView.frame = (CGRect){0, 0, newFrame.size};
            }
        }
    }
}

#pragma mark -

static BOOL doesViewContainView(UIView * rootView, UIView * viewToFind) {
    if (rootView == viewToFind) {
        return YES;
    }
    
    for (UIView * subview in [rootView subviews]) {
        if (doesViewContainView(subview, viewToFind)) {
            return YES;
        }
    }
    
    return NO;
}

- (UIView *)findViewInsideView:(UIView *)rootView {
    for (UIView * view in [_views objects]) {
        if (doesViewContainView(rootView, view)) {
            return view;
        }
    }
    
    return nil;
}

- (void)inputViewWillAppear:(NSNotification *)notification {
    UIWindow * window = [[UIApplication sharedApplication] windows][0];
    UIView * screenView = [self findViewInsideView:window];
    
    CGFloat (^scrollViewDiff)() = ^{
        if ([screenView isKindOfClass:[UIScrollView class]]) {
            return ((UIScrollView *)screenView).contentOffset.y;
        } else {
            return 0.f;
        }
    };
    
    CGRect (^newScreenViewFrame)() = ^{
        CGRect screenFrameW = [screenView convertRect:screenView.frame toView:window];
        CGRect inputFrameW = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        
        CGRect newScreenFrameW = (CGRect){
            screenFrameW.origin,
            screenFrameW.size.width,
            inputFrameW.origin.y - screenFrameW.origin.y - scrollViewDiff()
        };
        
        return [screenView convertRect:newScreenFrameW fromView:window];
    };
    
    void (^updateFrames)() = ^{
        UIScrollView * scrollView = getScrollView(screenView);
        CGRect frame = newScreenViewFrame();
        scrollView.frame = (CGRect){0, 0, frame.size};
        screenView.frame = frame;
    };
    
    void (^updateScreenViewFrame)() = ^{
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationCurve:[[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationDelay:0.1];
        [UIView setAnimationDuration:[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
        updateFrames();
        [UIView commitAnimations];
    };
    
    [self setNormalSize:screenView.bounds.size forView:screenView];
    updateScreenViewFrame();
}

- (void)inputViewWillDisappear:(NSNotification *)notification {
    UIWindow * window = [[UIApplication sharedApplication] windows][0];
    UIView * screenView = [self findViewInsideView:window];
    
    CGRect (^newScreenViewFrame)() = ^{
        CGSize normalSize = [self normalSizeForView:screenView];
        
        CGRect screenFrameW = [screenView convertRect:screenView.frame toView:window];
        
        CGRect newScreenFrameW = (CGRect){screenFrameW.origin, normalSize};
        
        return [screenView convertRect:newScreenFrameW fromView:window];
    };
    
    void (^updateFrames)() = ^{
        UIScrollView * scrollView = getScrollView(screenView);
        CGRect frame = newScreenViewFrame();
        scrollView.frame = (CGRect){0, 0, frame.size};
        screenView.frame = frame;
    };
    
    void (^updateScreenViewFrame)() = ^{
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationCurve:[[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationDuration:0.1];
        updateFrames();
        [UIView commitAnimations];
    };
    
    if (![self isNormalSetForView:screenView]) {
        [self setNormalSize:screenView.bounds.size forView:screenView];
    }
    updateScreenViewFrame();
}

@end
