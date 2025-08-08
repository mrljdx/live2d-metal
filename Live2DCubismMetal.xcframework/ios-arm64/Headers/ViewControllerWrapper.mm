#import "ViewControllerWrapper.h"

@interface ViewControllerWrapper ()
@property (nonatomic, strong) id internalViewController;
@end

@implementation ViewControllerWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        // 使用运行时动态创建 ViewController 实例，避免编译时 C++ 依赖
        Class ViewControllerClass = NSClassFromString(@"ViewController");
        if (ViewControllerClass) {
            _internalViewController = [[ViewControllerClass alloc] init];
        } else {
            NSLog(@"Warning: ViewController class not found");
        }
    }
    return self;
}

- (void)initializeSprite {
    if ([_internalViewController respondsToSelector:@selector(initializeSprite)]) {
        [_internalViewController performSelector:@selector(initializeSprite)];
    } else {
        NSLog(@"Warning: initializeSprite method not available");
    }
}

- (void)releaseView {
    if ([_internalViewController respondsToSelector:@selector(releaseView)]) {
        [_internalViewController performSelector:@selector(releaseView)];
    } else {
        NSLog(@"Warning: releaseView method not available");
    }
}

- (void)resizeScreen {
    if ([_internalViewController respondsToSelector:@selector(resizeScreen)]) {
        [_internalViewController performSelector:@selector(resizeScreen)];
    } else {
        NSLog(@"Warning: resizeScreen method not available");
    }
}

- (float)transformViewX:(float)deviceX {
    if ([_internalViewController respondsToSelector:@selector(transformViewX:)]) {
        NSMethodSignature *signature = [_internalViewController methodSignatureForSelector:@selector(transformViewX:)];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:_internalViewController];
            [invocation setSelector:@selector(transformViewX:)];
            [invocation setArgument:&deviceX atIndex:2];
            [invocation invoke];

            float result;
            [invocation getReturnValue:&result];
            return result;
        }
    }
    NSLog(@"Warning: transformViewX method not available, returning original value");
    return deviceX;
}

- (float)transformViewY:(float)deviceY {
    if ([_internalViewController respondsToSelector:@selector(transformViewY:)]) {
        NSMethodSignature *signature = [_internalViewController methodSignatureForSelector:@selector(transformViewY:)];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:_internalViewController];
            [invocation setSelector:@selector(transformViewY:)];
            [invocation setArgument:&deviceY atIndex:2];
            [invocation invoke];

            float result;
            [invocation getReturnValue:&result];
            return result;
        }
    }
    NSLog(@"Warning: transformViewY method not available, returning original value");
    return deviceY;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;
        [self addChildViewController:vc];
        [self.view addSubview:vc.view];
        [vc didMoveToParentViewController:self];

        // 让内部 ViewController 完全控制自己的视图
        vc.view.frame = self.view.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
}

- (void)dealloc {
    // 清理资源
    [self releaseView];

    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;
        [vc willMoveToParentViewController:nil];
        [vc.view removeFromSuperview];
        [vc removeFromParentViewController];
    }

    _internalViewController = nil;
}

@end