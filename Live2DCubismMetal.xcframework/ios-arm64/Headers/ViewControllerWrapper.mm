#import "ViewControllerWrapper.h"
#import <UIKit/UIKit.h>

@interface ViewControllerWrapper ()
@property (nonatomic, strong) id internalViewController;
@property (nonatomic, assign) CGRect lastBounds;
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
            NSLog(@"[Live2D] Warning: ViewController class not found");
        }
    }
    return self;
}

- (void)initializeSprite {
    if ([_internalViewController respondsToSelector:@selector(initializeSprite)]) {
        [_internalViewController initializeSprite];
    } else {
        NSLog(@"[Live2D] Warning: initializeSprite method not available");
    }
}

- (void)releaseView {
    if ([_internalViewController respondsToSelector:@selector(releaseView)]) {
        [_internalViewController releaseView];
    } else {
        NSLog(@"[Live2D] Warning: releaseView method not available");
    }
}

- (void)resizeScreen {
    if ([_internalViewController respondsToSelector:@selector(resizeScreen)]) {
        [_internalViewController resizeScreen];
    } else {
        NSLog(@"[Live2D] Warning: resizeScreen method not available");
    }
}

- (float)transformViewX:(float)deviceX {
    if ([_internalViewController respondsToSelector:@selector(transformViewX:)]) {
        return [_internalViewController transformViewX:deviceX];
    }
    NSLog(@"[Live2D] Warning: transformViewX method not available, returning original value");
    return deviceX;
}

- (float)transformViewY:(float)deviceY {
    if ([_internalViewController respondsToSelector:@selector(transformViewY:)]) {
        return [_internalViewController transformViewY:deviceY];
    }
    NSLog(@"[Live2D] Warning: transformViewY method not available, returning original value");
    return deviceY;
}

- (void)switchToNextModel {
    if ([_internalViewController respondsToSelector:@selector(switchToNextModel)]) {
        [_internalViewController switchToNextModel];
    } else {
        NSLog(@"[Live2D] Warning: switchToNextModel method not available, fallback to call LAppLive2DManager");
        // Fallback: directly call LAppLive2DManager
        Class LAppLive2DManagerClass = NSClassFromString(@"LAppLive2DManager");
        if (LAppLive2DManagerClass && [LAppLive2DManagerClass respondsToSelector:@selector(getInstance)]) {
            id manager = [LAppLive2DManagerClass performSelector:@selector(getInstance)];
            if ([manager respondsToSelector:@selector(nextScene)]) {
                [manager performSelector:@selector(nextScene)];
            }
        }
    }
}

- (void)switchToPreviousModel {
    if ([_internalViewController respondsToSelector:@selector(switchToPreviousModel)]) {
        [_internalViewController switchToPreviousModel];
    } else {
        NSLog(@"[Live2D] Warning: switchToPreviousModel method not available, fallback to call LAppLive2DManager");
        // Fallback: directly call LAppLive2DManager with index calculation
        Class LAppLive2DManagerClass = NSClassFromString(@"LAppLive2DManager");
        if (LAppLive2DManagerClass && [LAppLive2DManagerClass respondsToSelector:@selector(getInstance)]) {
            id manager = [LAppLive2DManagerClass performSelector:@selector(getInstance)];
            
            // Get current index and model count to calculate previous
            if ([manager respondsToSelector:@selector(changeScene:)]) {
                NSMethodSignature *countSignature = [manager methodSignatureForSelector:@selector(GetModelNum)];
                if (countSignature) {
                    NSInvocation *countInvocation = [NSInvocation invocationWithMethodSignature:countSignature];
                    [countInvocation setTarget:manager];
                    [countInvocation setSelector:@selector(GetModelNum)];
                    [countInvocation invoke];
                    
                    unsigned int modelCount;
                    [countInvocation getReturnValue:&modelCount];
                    
                    // For previous model, we'll use a simplified approach since we can't easily get current index
                    // This will require exposing the sceneIndex or implementing the logic differently
                    [manager performSelector:@selector(nextScene)]; // Temporary fallback
                }
            }
        }
    }
}

- (void)switchToModel:(int)index {
    if ([_internalViewController respondsToSelector:@selector(switchToModel:)]) {
        [_internalViewController switchToModel:index];
    } else {
        NSLog(@"[Live2D] Warning: switchToModel method not available, fallback to call LAppLive2DManager");
        // Fallback: directly call LAppLive2DManager
        Class LAppLive2DManagerClass = NSClassFromString(@"LAppLive2DManager");
        if (LAppLive2DManagerClass && [LAppLive2DManagerClass respondsToSelector:@selector(getInstance)]) {
            id manager = [LAppLive2DManagerClass performSelector:@selector(getInstance)];
            if ([manager respondsToSelector:@selector(changeScene:)]) {
                NSMethodSignature *signature = [manager methodSignatureForSelector:@selector(changeScene:)];
                if (signature) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setTarget:manager];
                    [invocation setSelector:@selector(changeScene:)];
                    [invocation setArgument:&index atIndex:2];
                    [invocation invoke];
                }
            }
        }
    }
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

        // 设置内容模式为Aspect Fit以保持宽高比
        vc.view.contentMode = UIViewContentModeScaleAspectFit;

        // 确保内部视图也透明
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.opaque = NO;
    }
    
    // 添加屏幕旋转通知监听
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    // 确保设备方向通知已启用
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
}

// 加到 ViewControllerWrapper.m 里
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // 如果 bounds 没变化就不重复调用
    if (CGRectEqualToRect(self.view.bounds, self.lastBounds)) { return; }
    self.lastBounds = self.view.bounds;

    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;

        // 1. 让内部 view 跟随父视图大小
        vc.view.frame = self.view.bounds;

        // 2. 通知内部重新计算 Live2D 画布
        [self resizeScreen];

        NSLog(@"[Live2D] ViewControllerWrapper: layout updated, new bounds %@", NSStringFromCGRect(self.view.bounds));
    }
}

- (void)orientationChanged:(NSNotification *)notification {
    // 延迟执行以确保布局已经完成更新
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self handleRotation];
    });
}

- (void)handleRotation {
    if (CGRectEqualToRect(self.view.bounds, self.lastBounds)) {
        NSLog(@"[Live2D] ViewControllerWrapper: rotation skipped (duplicate)");
        return;
    }
    // 强制重新计算屏幕尺寸
    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;

        // 更新视图框架
        vc.view.frame = self.view.bounds;

        // 调用内部控制器的resize方法来重新计算模型尺寸
        [self resizeScreen];

        NSLog(@"[Live2D] ViewControllerWrapper: Screen rotated, new bounds: %@", NSStringFromCGRect(self.view.bounds));
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    // 在旋转动画完成后重新计算
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // 动画过程中的更新
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // 旋转完成后重新计算
        [self handleRotation];
    }];
}

- (void)dealloc {
    // 移除通知监听
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    
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

- (void)setModelScale:(float)scale
{
    if ([_internalViewController respondsToSelector:@selector(setModelScale:)]) {
        [_internalViewController setModelScale:scale];
    } else {
        NSLog(@"[Live2D] Warning: setModelScale method not available");
    }
}

- (void)moveModel:(float)x y:(float)y
{
    if ([_internalViewController respondsToSelector:@selector(moveModel:y:)]) {
        [_internalViewController moveModel:x y:y];
    } else {
        NSLog(@"[Live2D] Warning: moveModel method not available");
    }
}

- (BOOL)loadWavFile:(NSString *)filePath {
    if ([_internalViewController respondsToSelector:@selector(loadWavFile:)]) {
        [_internalViewController loadWavFile:filePath];
        return YES;
    } else {
        NSLog(@"[Live2D] Warning: loadWavFile method not available");
        return NO;
    }
}

- (float)getAudioRms {
    if ([_internalViewController respondsToSelector:@selector(getAudioRms)]) {
        return [_internalViewController getAudioRms];
    } else {
        NSLog(@"[Live2D] Warning: getAudioRms method not available");
        return 0.0f;
    }
}

- (BOOL)updateAudio:(float)deltaTime {
    if ([_internalViewController respondsToSelector:@selector(updateAudio:)]) {
        [_internalViewController updateAudio:deltaTime];
        return YES;
    } else {
        NSLog(@"[Live2D] Warning: updateAudio method not available");
        return NO;
    }
}

- (void)releaseWavHandler {
    if ([_internalViewController respondsToSelector:@selector(releaseWavHandler)]) {
        [_internalViewController releaseWavHandler];
    } else {
        NSLog(@"[Live2D] Warning: releaseWavHandler method not available");
    }
}

- (void)updateLipSync:(float)mouth
{
    if ([_internalViewController respondsToSelector:@selector(updateLipSync:)]) {
        [_internalViewController updateLipSync:mouth];
    } else {
        NSLog(@"[Live2D] Warning: updateLipSync method not available");
    }
}

- (void)updateLipSync
{
    // 获取音频的RMS值用于唇形同步
    float rms = [self getAudioRms];

    // 调用实际的唇形同步更新方法
    [self updateLipSync:rms];
}

@end