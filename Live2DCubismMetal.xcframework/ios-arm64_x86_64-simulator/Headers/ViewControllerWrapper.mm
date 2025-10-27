#import "ViewControllerWrapper.h"
#import <UIKit/UIKit.h>

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
    // 清理Live2DManager的实例
//    Class LAppLive2DManagerClass = NSClassFromString(@"LAppLive2DManager");
//    if (LAppLive2DManagerClass && [LAppLive2DManagerClass respondsToSelector:@selector(releaseInstance)]) {
//        [LAppLive2DManagerClass performSelector:@selector(releaseInstance)];
//    } else {
//        NSLog(@"[Live2D] Warning: LAppLive2DManager releaseInstance method not available");
//    }
    // 清理Live2D的所有资源
//    Class AppDelegateClass = NSClassFromString(@"AppDelegate");
//    if (AppDelegateClass) {
//        id appDelegate = [[UIApplication sharedApplication] delegate];
//        if ([appDelegate respondsToSelector:@selector(finishApplication)]) {
//            [appDelegate performSelector:@selector(finishApplication)];
//        } else {
//            NSLog(@"[Live2D] Warning: AppDelegate finishApplication not available");
//        }
//    } else {
//        NSLog(@"[Live2D] Warning: AppDelegate class not available");
//    }
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

- (float)transformScreenX:(float)deviceX {
    if ([_internalViewController respondsToSelector:@selector(transformScreenX:)]) {
        return [_internalViewController transformScreenX:deviceX];
    }
    NSLog(@"[Live2D] Warning: transformScreenX method not available, returning original value");
    return deviceX;
}

- (float)transformScreenY:(float)deviceY {
    if ([_internalViewController respondsToSelector:@selector(transformScreenY:)]) {
        return [_internalViewController transformScreenY:deviceY];
    }
    NSLog(@"[Live2D] Warning: transformScreenY method not available, returning original value");
    return deviceY;
}

- (float)transformTapY:(float)deviceY
{
    if ([_internalViewController respondsToSelector:@selector(transformTapY:)]) {
        return [_internalViewController transformTapY:deviceY];
    }
    NSLog(@"[Live2D] Warning: transformTapY method not available, returning original value");
    return deviceY;
}

- (void)drawableResize:(CGSize)size
{
    if ([_internalViewController respondsToSelector:@selector(drawableResize:)]) {
        return [_internalViewController drawableResize:size];
    }
    NSLog(@"[Live2D] Warning: drawableResize method not available, returning original value");
}

- (void)switchToNextModel {
    if ([_internalViewController respondsToSelector:@selector(switchToNextModel)]) {
        [_internalViewController switchToNextModel];
    } else {
        NSLog(@"[Live2D] Warning: switchToNextModel method not available");
    }
}

- (void)switchToPreviousModel {
    if ([_internalViewController respondsToSelector:@selector(switchToPreviousModel)]) {
        [_internalViewController switchToPreviousModel];
    } else {
        NSLog(@"[Live2D] Warning: switchToPreviousModel method not available");
    }
}

- (void)switchToModel:(int)index {
    if ([_internalViewController respondsToSelector:@selector(switchToModel:)]) {
        [_internalViewController switchToModel:index];
    } else {
        NSLog(@"[Live2D] Warning: switchToModel method not available");
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
        NSLog(@"[Live2D] Debug: viewDidLoad addSubview for ViewController");
    }
}

- (void)dealloc {
    // 先清理View
    // [self releaseView];

    // 再清理资源
    if (_internalViewController && [_internalViewController isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)_internalViewController;
        [vc willMoveToParentViewController:nil];
        [vc.view removeFromSuperview];
        [vc removeFromParentViewController];
    }
    _internalViewController = nil;

    // 清理现有代码
    [super dealloc];

    NSLog(@"[Live2D] Debug: ViewControllerWrapper dealloc is called");
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
        return [_internalViewController updateAudio:deltaTime];
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

- (void)lipSync:(float)mouth
{
    if ([_internalViewController respondsToSelector:@selector(updateLipSync:)]) {
        [_internalViewController lipSync:mouth];
    } else {
        NSLog(@"[Live2D] Warning: lipSync method not available");
    }
}

- (void)updateLipSync
{
    // 获取音频的RMS值用于唇形同步
    float rms = [self getAudioRms];

    // 调用实际的唇形同步更新方法
    [self lipSync:rms];
}

- (BOOL)hasClickableAreas
{
    if ([_internalViewController respondsToSelector:@selector(hasClickableAreas)]) {
        return [_internalViewController hasClickableAreas];
    } else {
        NSLog(@"[Live2D] Warning: hasClickableAreas method not available");
        return NO;
    }
}

- (void)setShowClickableAreas:(BOOL)show
{
    if ([_internalViewController respondsToSelector:@selector(setShowClickableAreas:)]) {
        [_internalViewController setShowClickableAreas:show];
    } else {
        NSLog(@"[Live2D] Warning: setShowClickableAreas method not available");
    }
}

- (BOOL)isShowingClickableAreas
{
    if ([_internalViewController respondsToSelector:@selector(isShowingClickableAreas)]) {
        return [_internalViewController isShowingClickableAreas];
    } else {
        NSLog(@"[Live2D] Warning: isShowingClickableAreas method not available");
        return NO;
    }
}

- (BOOL)loadModels:(NSString *)rootPath
{
    if ([_internalViewController respondsToSelector:@selector(loadModels:)]) {
        return [_internalViewController loadModels:rootPath];
    } else {
        NSLog(@"[Live2D] Warning: loadModels: method not available");
        return NO;
    }
}

- (BOOL)loadModelPath:(NSString *)dir jsonName:(NSString*)jsonName {
    if ([_internalViewController respondsToSelector:@selector(loadModelPath:jsonName:)]) {
        return [_internalViewController loadModelPath:dir
                                             jsonName:jsonName];
    } else {
        NSLog(@"[Live2D] Warning: loadModelPath: method not available");
        return NO;
    }
}

- (BOOL)removeAllModels
{
    if ([_internalViewController respondsToSelector:@selector(removeAllModels)]) {
        return [_internalViewController removeAllModels];
    } else {
        NSLog(@"[Live2D] Warning: removeAllModels: method not available");
        return NO;
    }
}

- (int32_t)getLoadedModelNum
{
    if ([_internalViewController respondsToSelector:@selector(getLoadedModelNum)]) {
        return [_internalViewController getLoadedModelNum];
    } else {
        NSLog(@"[Live2D] Warning: getLoadedModelNum: method not available");
        return 0;
    }
}

@end