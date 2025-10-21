#import "L2DCubism.h"
#import <iostream>
#import "ViewController.h"
#import "LAppAllocator.h"
#import "LAppPal.h"
#import "LAppDefine.h"
#import "LAppLive2DManager.h"
#import "LAppTextureManager.h"

@interface L2DCubism ()

@property(nonatomic) LAppAllocator cubismAllocator; // Cubism SDK Allocator
@property(nonatomic) Csm::CubismFramework::Option cubismOption; // Cubism SDK Option
@property(nonatomic) bool captured; // クリックしているか
@property(nonatomic) float mouseX; // マウスX座標
@property(nonatomic) float mouseY; // マウスY座標
@property(nonatomic) bool isEnd; // APPを終了しているか
@property(nonatomic, readwrite) LAppTextureManager *textureManager; // テクスチャマネージャー
@property(nonatomic) Csm::csmInt32 sceneIndex;  //アプリケーションをバッググラウンド実行するときに一時的にシーンインデックス値を保存する

@end

@implementation L2DCubism

+ (instancetype)sharedInstance {
    static L2DCubism *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _textureManager = nil;
        _isEnd = false;
    }
    return self;
}

- (void)initCubism {
    NSLog(@"[Live2D] L2DCubism: initCubism start");
    if (!_textureManager) {
        _textureManager = [[LAppTextureManager alloc] init];
    }
    // 重置isEnd
    self.isEnd = false;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.viewController = [[ViewController alloc] initWithNibName:nil bundle:nil];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];

    _cubismOption.LogFunction = LAppPal::PrintMessageLn;
    _cubismOption.LoggingLevel = LAppDefine::CubismLoggingLevel;
    _cubismOption.LoadFileFunction = LAppPal::LoadFileAsBytes;
    _cubismOption.ReleaseBytesFunction = LAppPal::ReleaseBytes;

    Csm::CubismFramework::StartUp(&_cubismAllocator, &_cubismOption);

    Csm::CubismFramework::Initialize();

    [LAppLive2DManager getInstance];

    Csm::CubismMatrix44 projection;

    LAppPal::UpdateTime();
    NSLog(@"[Live2D] L2DCubism: initCubism success");
}

- (bool)getIsEnd {
    return _isEnd;
}

- (void)disposeCubism {

    // 1. 停止渲染并移除视图
    if ([self.viewController respondsToSelector:@selector(releaseView)]) {
        [self.viewController releaseView];
    }

    // 2. 把 window 置空，UIKit 会立即释放整个视图层级
    self.window.rootViewController = nil;
    self.window = nil;
    self.viewController = nil;

    if (_textureManager) {
        [_textureManager releaseTextures];
        _textureManager = nil;
    }

    // 3. 清理 Cubism SDK 及单例
    [LAppLive2DManager releaseInstance];

    Csm::CubismFramework::Dispose();

    _isEnd = true;

    _viewController = nil;

    NSLog(@"[Live2D] L2DCubism: disposeCubism called");
}

- (bool)loadModels:(NSString *)rootPath {
    // NSString → std::string → Csm::csmString
    std::string utf8Path = [rootPath UTF8String];
    Csm::csmString csmPath(utf8Path.c_str());
    [[LAppLive2DManager getInstance] loadModels:csmPath];
    return true;
}

- (bool)loadModelPath:(NSString *)dir
             jsonName:(NSString *)jsonName {
    // NSString → std::string → Csm::csmString
    std::string utf8Path = [dir UTF8String];
    Csm::csmString csmPath(utf8Path.c_str());
    std::string utf8Name = [jsonName UTF8String];
    Csm::csmString csmName(utf8Name.c_str());
    [[LAppLive2DManager getInstance] loadModelPath:csmPath
                                          jsonName:csmName];
    return true;
}

@end
