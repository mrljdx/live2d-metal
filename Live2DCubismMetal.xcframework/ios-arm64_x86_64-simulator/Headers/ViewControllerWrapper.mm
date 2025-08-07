#import "ViewControllerWrapper.h"
// 移除 #import "ViewController.h" - 避免 C++ 依赖导致的编译错误

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

- (float)transformScreenX:(float)deviceX {
    if ([_internalViewController respondsToSelector:@selector(transformScreenX:)]) {
        NSMethodSignature *signature = [_internalViewController methodSignatureForSelector:@selector(transformScreenX:)];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:_internalViewController];
            [invocation setSelector:@selector(transformScreenX:)];
            [invocation setArgument:&deviceX atIndex:2];
            [invocation invoke];

            float result;
            [invocation getReturnValue:&result];
            return result;
        }
    }
    NSLog(@"Warning: transformScreenX method not available, returning original value");
    return deviceX;
}

- (float)transformScreenY:(float)deviceY {
    if ([_internalViewController respondsToSelector:@selector(transformScreenY:)]) {
        NSMethodSignature *signature = [_internalViewController methodSignatureForSelector:@selector(transformScreenY:)];
        if (signature) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:_internalViewController];
            [invocation setSelector:@selector(transformScreenY:)];
            [invocation setArgument:&deviceY atIndex:2];
            [invocation invoke];

            float result;
            [invocation getReturnValue:&result];
            return result;
        }
    }
    NSLog(@"Warning: transformScreenY method not available, returning original value");
    return deviceY;
}

// 转发触摸事件方法
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([_internalViewController respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        [_internalViewController performSelector:@selector(touchesBegan:withEvent:) withObject:touches withObject:event];
    } else {
        [super touchesBegan:touches withEvent:event];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([_internalViewController respondsToSelector:@selector(touchesMoved:withEvent:)]) {
        [_internalViewController performSelector:@selector(touchesMoved:withEvent:) withObject:touches withObject:event];
    } else {
        [super touchesMoved:touches withEvent:event];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([_internalViewController respondsToSelector:@selector(touchesEnded:withEvent:)]) {
        [_internalViewController performSelector:@selector(touchesEnded:withEvent:) withObject:touches withObject:event];
    } else {
        [super touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([_internalViewController respondsToSelector:@selector(touchesCancelled:withEvent:)]) {
        [_internalViewController performSelector:@selector(touchesCancelled:withEvent:) withObject:touches withObject:event];
    } else {
        [super touchesCancelled:touches withEvent:event];
    }
}

// 视图生命周期方法
- (void)viewDidLoad {
    [super viewDidLoad];

    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;
        [self addChildViewController:vc];
        [self.view addSubview:vc.view];
        [vc didMoveToParentViewController:self];

        // 使用autoresizing，避免约束冲突
        vc.view.translatesAutoresizingMaskIntoConstraints = YES;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view.frame = self.view.bounds;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if ([_internalViewController respondsToSelector:@selector(viewWillAppear:)]) {
        [_internalViewController performSelector:@selector(viewWillAppear:) withObject:@(animated)];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if ([_internalViewController respondsToSelector:@selector(viewDidAppear:)]) {
        [_internalViewController performSelector:@selector(viewDidAppear:) withObject:@(animated)];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if ([_internalViewController respondsToSelector:@selector(viewWillDisappear:)]) {
        [_internalViewController performSelector:@selector(viewWillDisappear:) withObject:@(animated)];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    if ([_internalViewController respondsToSelector:@selector(viewDidDisappear:)]) {
        [_internalViewController performSelector:@selector(viewDidDisappear:) withObject:@(animated)];
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