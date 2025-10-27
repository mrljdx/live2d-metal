/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import "ViewController.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <string>
#import "CubismFramework.hpp"
#import "AppDelegate.h"
#import "L2DCubism.h"
#import "LAppSprite.h"
#import "LAppDefine.h"
#import "LAppLive2DManager.h"
#import "LAppTextureManager.h"
#import "LAppPal.h"
#import "LAppModel.h"
#import "TouchManager.h"
#import "MetalUIView.h"
#import <Math/CubismMatrix44.hpp>
#import <Math/CubismViewMatrix.hpp>
#import "Rendering/Metal/CubismRenderingInstanceSingleton_Metal.h"
#import "LAppWavFileHandler_Common.hpp"

#define BUFFER_OFFSET(bytes) ((GLubyte *)NULL + (bytes))

using namespace std;
using namespace LAppDefine;

// Global WAV handler instance
static LAppWavFileHandler_Common* g_wavHandler = nullptr;

@interface ViewController ()
//@property (nonatomic) LAppSprite *back; //背景画像
//@property (nonatomic) LAppSprite *gear; //歯車画像
//@property (nonatomic) LAppSprite *power; //電源画像
@property (nonatomic) LAppModelSprite *renderSprite; //レンダリングターゲット描画用
@property (nonatomic) TouchManager *touchManager; ///< タッチマネージャー
@property (nonatomic) Csm::CubismMatrix44 *deviceToScreen;///< デバイスからスクリーンへの行列
@property (nonatomic) Csm::CubismViewMatrix *viewMatrix;
@property (nonatomic, assign) CGRect lastBounds;
@property (nonatomic, assign) BOOL isViewValid;

@end

@implementation ViewController

- (void)releaseView
{
    self.isViewValid = NO;
    _renderSprite = nil;
//    [_gear release];
//    [_back release];
//    [_power release];
//    _gear = nil;
//    _back = nil;
//    _power = nil;

    MetalUIView *view = (MetalUIView*)self.view;
    if (view)
    {
        view.delegate = nil;
        [view stopRenderLoop];
        [view removeFromSuperview];
        view = nil;
        NSLog(@"[Live2D] ViewController: releaseView -> stopRenderLoop called");
    }

    delete(_viewMatrix);
    _viewMatrix = nil;
    delete(_deviceToScreen);
    _deviceToScreen = nil;
    _touchManager = nil;

    if (_depthTexture)
    {
        [_depthTexture release];
        _depthTexture = nil;
    }
    if (_commandQueue)
    {
        _commandQueue = nil;
    }
    NSLog(@"[Live2D] ViewController: releaseView called");
}

// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView
{
    MetalUIView *metalUiView = [[MetalUIView alloc] init];
    [self setView:metalUiView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.isViewValid = YES;

#if TARGET_OS_MACCATALYST
//    if (AppDelegate* appDelegate = (AppDelegate*)[[UIApplication sharedApplication] delegate])
    if (L2DCubism* appDelegate = [L2DCubism sharedInstance])
    {
        appDelegate.window.windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
    }
#endif

    //Fremework層でもMTLDeviceを参照するためシングルトンオブジェクトに登録
    CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    [single setMTLDevice:device];

    MetalUIView *view = (MetalUIView*)self.view;

    // Set the device for the layer so the layer can create drawable textures that can be rendered to
    // on this device.
    view.metalLayer.device = device;

    // Set this class as the delegate to receive resize and render callbacks.
    view.delegate = self;

    view.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    [single setMetalLayer:view.metalLayer];

    _commandQueue = [device newCommandQueue];

    _anotherTarget = false;
    _clearColorR = _clearColorG = _clearColorB = 1.0f;
    _clearColorA = 0.0f;

    // タッチ関係のイベント管理
    _touchManager = [[TouchManager alloc]init];

    // デバイス座標からスクリーン座標に変換するための
    _deviceToScreen = new CubismMatrix44();

    // 画面の表示の拡大縮小や移動の変換を行う行列
    _viewMatrix = new CubismViewMatrix();

    [self initializeScreen];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self resizeScreen];
}

- (void)initializeScreen
{
//    CGRect screenRect = [[UIScreen mainScreen] bounds];
//    int width = screenRect.size.width;
//    int height = screenRect.size.height;
    CGRect bounds = self.view.bounds;   // ← 容器尺寸
    int width  = (int)bounds.size.width;
    int height = (int)bounds.size.height;

    // 縦サイズを基準とする
    float ratio = static_cast<float>(width) / static_cast<float>(height);
    float left = -ratio;
    float right = ratio;
    float bottom = ViewLogicalLeft;
    float top = ViewLogicalRight;

    // デバイスに対応する画面の範囲。 Xの左端, Xの右端, Yの下端, Yの上端
    _viewMatrix->SetScreenRect(left, right, bottom, top);
    _viewMatrix->Scale(ViewScale, ViewScale);

    _deviceToScreen->LoadIdentity(); // サイズが変わった際などリセット必須
    if (width > height)
    {
        float screenW = fabsf(right - left);
        _deviceToScreen->ScaleRelative(screenW / width, -screenW / width);
    }
    else
    {
        float screenH = fabsf(top - bottom);
        _deviceToScreen->ScaleRelative(screenH / height, -screenH / height);
    }
    _deviceToScreen->TranslateRelative(-width * 0.5f, -height * 0.5f);

    // 表示範囲の設定
    _viewMatrix->SetMaxScale(ViewMaxScale); // 限界拡大率
    _viewMatrix->SetMinScale(ViewMinScale); // 限界縮小率

    // 表示できる最大範囲
    _viewMatrix->SetMaxScreenRect(
                                  ViewLogicalMaxLeft,
                                  ViewLogicalMaxRight,
                                  ViewLogicalMaxBottom,
                                  ViewLogicalMaxTop
                                  );
}

- (void)resizeScreen
{
//    AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
//    ViewController* view = [delegate viewController];
//    int width = view.view.frame.size.width;
//    int height = view.view.frame.size.height;
    if (CGRectEqualToRect(self.view.bounds, self.lastBounds)) {
        NSLog(@"[Live2D] ViewController: Bounds are equal, skipping resize");
        return;
    }
    NSLog(@"[Live2D] ViewController: Bounds changed, updating");
    self.lastBounds = self.view.bounds;

    // 直接用 self.view，而不是再兜圈子拿 AppDelegate.viewController
    int width  = (int)self.lastBounds.size.width;
    int height = (int)self.lastBounds.size.height;

    // 縦サイズを基準とする
    float ratio = static_cast<float>(width) / static_cast<float>(height);
    float left = -ratio;
    float right = ratio;
    float bottom = ViewLogicalLeft;
    float top = ViewLogicalRight;

    // デバイスに対応する画面の範囲。 Xの左端, Xの右端, Yの下端, Yの上端
    _viewMatrix->SetScreenRect(left, right, bottom, top);
    _viewMatrix->Scale(ViewScale, ViewScale);

    _deviceToScreen->LoadIdentity(); // サイズが変わった際などリセット必須
    if (width > height)
    {
        float screenW = fabsf(right - left);
        _deviceToScreen->ScaleRelative(screenW / width, -screenW / width);
    }
    else
    {
        float screenH = fabsf(top - bottom);
        _deviceToScreen->ScaleRelative(screenH / height, -screenH / height);
    }
    _deviceToScreen->TranslateRelative(-width * 0.5f, -height * 0.5f);

    // 表示範囲の設定
    _viewMatrix->SetMaxScale(ViewMaxScale); // 限界拡大率
    _viewMatrix->SetMinScale(ViewMinScale); // 限界縮小率

    // 表示できる最大範囲
    _viewMatrix->SetMaxScreenRect(
                                  ViewLogicalMaxLeft,
                                  ViewLogicalMaxRight,
                                  ViewLogicalMaxBottom,
                                  ViewLogicalMaxTop
                                  );

#if TARGET_OS_MACCATALYST
    [self resizeSprite:width Height:height];
#endif

}

- (void)initializeSprite
{
//    AppDelegate *delegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
//    ViewController* view = [delegate viewController];
//    float width = view.view.frame.size.width;
//    float height = view.view.frame.size.height;
    float width  = self.view.bounds.size.width;
    float height = self.view.bounds.size.height;

    NSLog(@"[Live2D] ViewController: initializeSprite - width:%f  height:%f", width, height);

//    LAppTextureManager* textureManager = [delegate getTextureManager];
//    const string resourcesPath = ResourcesPath;

    //背景
//    string imageName = BackImageName;
//    TextureInfo* backgroundTexture = [textureManager createTextureFromPngFile:resourcesPath+imageName];
//    float x = width * 0.5f;
//    float y = height * 0.5f;
//    float fWidth = static_cast<float>(backgroundTexture->width * 2.0f);
//    float fHeight = static_cast<float>(height) * 0.95f;
//    _back = [[LAppSprite alloc] initWithMyVar:x Y:y Width:fWidth Height:fHeight MaxWidth:width MaxHeight:height Texture:backgroundTexture->id];

    //モデル変更ボタン
//    imageName = GearImageName;
//    TextureInfo* gearTexture = [textureManager createTextureFromPngFile:resourcesPath+imageName];
//    x = static_cast<float>(width - gearTexture->width * 0.5f);
//    y = static_cast<float>(height - gearTexture->height * 0.5f);
//    fWidth = static_cast<float>(gearTexture->width);
//    fHeight = static_cast<float>(gearTexture->height);
//    _gear = [[LAppSprite alloc] initWithMyVar:x Y:y Width:fWidth Height:fHeight MaxWidth:width MaxHeight:height Texture:gearTexture->id];

    //電源ボタン
//    imageName = PowerImageName;
//    TextureInfo* powerTexture = [textureManager createTextureFromPngFile:resourcesPath+imageName];
//    x = static_cast<float>(width - powerTexture->width * 0.5f);
//    y = static_cast<float>(powerTexture->height * 0.5f);
//    fWidth = static_cast<float>(powerTexture->width);
//    fHeight = static_cast<float>(powerTexture->height);
//    _power = [[LAppSprite alloc] initWithMyVar:x Y:y Width:fWidth Height:fHeight MaxWidth:width MaxHeight:height Texture:powerTexture->id];
}

- (void)resizeSprite:(float)width Height:(float)height
{
//    AppDelegate *delegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
//    ViewController* view = [delegate viewController];
//    float maxWidth = view.view.frame.size.width;
//    float maxHeight = view.view.frame.size.height;
    float maxWidth  = self.view.bounds.size.width;
    float maxHeight = self.view.bounds.size.height;

    //背景
//    float x = width * 0.5f;
//    float y = height * 0.5f;
//    float fWidth = static_cast<float>(_back.GetTextureId.width * 2.0f);
//    float fHeight = static_cast<float>(height) * 0.95f;
//    [_back resizeImmidiate:x Y:y Width:fWidth Height:fHeight MaxWidth:maxWidth MaxHeight:maxHeight];
//
//    //モデル変更ボタン
//    x = static_cast<float>(width - _gear.GetTextureId.width * 0.5f);
//    y = static_cast<float>(height - _gear.GetTextureId.height * 0.5f);
//    fWidth = static_cast<float>(_gear.GetTextureId.width);
//    fHeight = static_cast<float>(_gear.GetTextureId.height);
//    [_gear resizeImmidiate:x Y:y Width:fWidth Height:fHeight MaxWidth:maxWidth MaxHeight:maxHeight];
//
//    //電源ボタン
//    x = static_cast<float>(width - _power.GetTextureId.width * 0.5f);
//    y = static_cast<float>(_power.GetTextureId.height * 0.5f);
//    fWidth = static_cast<float>(_power.GetTextureId.width);
//    fHeight = static_cast<float>(_power.GetTextureId.height);
//    [_power resizeImmidiate:x Y:y Width:fWidth Height:fHeight MaxWidth:maxWidth MaxHeight:maxHeight];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view];

    [_touchManager touchesBegan:point.x DeciveY:point.y];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view];

    float viewX = [self transformViewX:[_touchManager getX]];
    float viewY = [self transformViewY:[_touchManager getY]];

    [_touchManager touchesMoved:point.x DeviceY:point.y];
    [[LAppLive2DManager getInstance] onDrag:viewX floatY:viewY];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    NSLog(@"%@", touch.view);

    CGPoint point = [touch locationInView:self.view];
    float pointY = [self transformTapY:point.y];

    // タッチ終了
    LAppLive2DManager* live2DManager = [LAppLive2DManager getInstance];
    [live2DManager onDrag:0.0f floatY:0.0f];
    {
        // シングルタップ
        float getX = [_touchManager getX];// 論理座標変換した座標を取得。
        float getY = [_touchManager getY]; // 論理座標変換した座標を取得。
        float x = _deviceToScreen->TransformX(getX);
        float y = _deviceToScreen->TransformY(getY);

        if (DebugTouchLogEnable)
        {
            LAppPal::PrintLogLn("[APP]touchesEnded x:%.2f y:%.2f", x, y);
        }

        [live2DManager onTap:x floatY:y];

        // 歯車にタップしたか
        // if ([_gear isHit:point.x PointY:pointY])
        // {
        //     [live2DManager nextScene];
        // }

        // 電源ボタンにタップしたか
        // if ([_power isHit:point.x PointY:pointY])
        // {
        //     AppDelegate *delegate = (AppDelegate *) [[UIApplication sharedApplication] delegate];
        //     [delegate finishApplication];
        // }
    }
}

- (float)transformViewX:(float)deviceX
{
    float screenX = _deviceToScreen->TransformX(deviceX); // 論理座標変換した座標を取得。
    return _viewMatrix->InvertTransformX(screenX); // 拡大、縮小、移動後の値。
}

- (float)transformViewY:(float)deviceY
{
    float screenY = _deviceToScreen->TransformY(deviceY); // 論理座標変換した座標を取得。
    return _viewMatrix->InvertTransformY(screenY); // 拡大、縮小、移動後の値。
}

- (float)transformScreenX:(float)deviceX
{
    return _deviceToScreen->TransformX(deviceX);
}

- (float)transformScreenY:(float)deviceY
{
    return _deviceToScreen->TransformY(deviceY);
}

- (float)transformTapY:(float)deviceY
{
//    AppDelegate *delegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    L2DCubism* delegate = [L2DCubism sharedInstance];
    ViewController* view = [delegate viewController];
    float height = view.view.frame.size.height;
    return deviceY * -1 + height;
}

- (void)drawableResize:(CGSize)size
{
    if (_depthTexture)
    {
        [_depthTexture release];
        _depthTexture = nil;
        LAppPal::PrintLogLn("[APP]drawableResize _depthTexture release");
    }

    MTLTextureDescriptor* depthTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:size.width height:size.height mipmapped:false];
    depthTextureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    depthTextureDescriptor.storageMode = MTLStorageModePrivate;

    CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
    id <MTLDevice> device = [single getMTLDevice];
    _depthTexture = [device newTextureWithDescriptor:depthTextureDescriptor];

    [self resizeScreen];
}


- (void)renderSprite:(id<MTLRenderCommandEncoder>)renderEncoder
{
    // [_back renderImmidiate:renderEncoder];

    // [_gear renderImmidiate:renderEncoder];

    // [_power renderImmidiate:renderEncoder];
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer *)layer
{
    //NSLog(@"[DEBUG]ViewController: renderToMetalLayer is called");
//    L2DCubism* delegate = [L2DCubism sharedInstance];
//    if ([delegate getIsEnd]) {
    if (!self.isViewValid) {
//        NSLog(@"[DEBUG]ViewController: getIsEnd is true,_commandQueue:%p", _commandQueue);
        NSLog(@"[DEBUG]ViewController: isViewValid :%b", self.isViewValid);
        return;
    }

    LAppPal::UpdateTime();

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<CAMetalDrawable> currentDrawable = [layer nextDrawable];

    MTLRenderPassDescriptor *renderPassDescriptor = [[[MTLRenderPassDescriptor alloc] init] autorelease];
    renderPassDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

    //モデル以外の描画
    [self renderSprite:renderEncoder];

    [renderEncoder endEncoding];

    LAppLive2DManager* Live2DManager = [LAppLive2DManager getInstance];
    [Live2DManager SetViewMatrix:_viewMatrix];
    [Live2DManager onUpdate:commandBuffer currentDrawable:currentDrawable depthTexture:_depthTexture];

    [commandBuffer presentDrawable:currentDrawable];
    [commandBuffer commit];
}

- (void)dealloc
{
    [super dealloc];
}

- (void)switchToNextModel
{
    [[LAppLive2DManager getInstance] nextScene];
}

- (void)switchToPreviousModel
{
    [[LAppLive2DManager getInstance] nextScene];
}

- (void)switchToModel:(int)index
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    Csm::csmInt32 modelCount = manager.modelDir.GetSize();

    if (index >= 0 && index < modelCount) {
        [manager changeScene:index];
    }
}

- (void)setModelScale:(float)scale
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    [manager setModelScale:scale];
}

- (void)moveModel:(float)x y:(float)y
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    [manager moveModel:x y:y];
}

- (BOOL)loadWavFile:(NSString *)filePath {
    LAppPal::PrintLogLn("[APP]loadWavFile called: $s", filePath);
    if (!g_wavHandler) {
        g_wavHandler = new LAppWavFileHandler_Common();
    }

    const char *path = [filePath UTF8String];
    g_wavHandler->Start(Csm::csmString(path));
    LAppPal::PrintLogLn("[APP]loadWavFile %s Success", filePath);
    return YES;
}

- (float)getAudioRms {
    if (!g_wavHandler) {
        return 0.0f;
    }
    return static_cast<float>(g_wavHandler->GetRms());
}

- (BOOL)updateAudio:(float)deltaTime {
    if (!g_wavHandler) {
        return NO;
    }
    return g_wavHandler->Update(static_cast<Csm::csmFloat32>(deltaTime)) ? YES : NO;
}

- (void)releaseWavHandler {
    if (g_wavHandler) {
        delete g_wavHandler;
        g_wavHandler = nullptr;
    }
}

- (void)lipSync:(float)mouth
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    [manager updateLipSync:mouth];
}

- (BOOL)hasClickableAreas
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    return [manager hasClickableAreas];
}

- (void)setShowClickableAreas:(BOOL)show
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    [manager setShowClickableAreas:show];
}

- (BOOL)isShowingClickableAreas
{
    LAppLive2DManager* manager = [LAppLive2DManager getInstance];
    return [manager isShowingClickableAreas];
}

- (void)drawClickableAreaWireframe:(const float*)vertices 
                       vertexCount:(int)vertexCount 
                               r:(float)r g:(float)g b:(float)b 
                       areaName:(NSString*)areaName {
    LAppPal::PrintLogLn("[DEBUG] ViewController::drawClickableAreaWireframe called for: %s, color=(%.1f,%.1f,%.1f)", [areaName UTF8String], r, g, b);
    if (!vertices || vertexCount < 3 || !_renderSprite) {
        LAppPal::PrintLogLn("[DEBUG] ViewController::drawClickableAreaWireframe early return: vertices=%p, vertexCount=%d, _renderSprite=%p",
                           vertices, vertexCount, _renderSprite);
        return;
    }

    // 获取窗口尺寸
    int width = (int)self.view.bounds.size.width;
    int height = (int)self.view.bounds.size.height;
    
    LAppPal::PrintLogLn("[DEBUG] Window size: %dx%d, rendering %d vertices for %s", 
                       width, height, vertexCount, [areaName UTF8String]);

    // 打印所有顶点坐标用于调试
    for (int i = 0; i < (vertexCount < 4 ? vertexCount : 4); i++) {
        LAppPal::PrintLogLn("[DEBUG] Boundary vertex[%d]: (%.2f, %.2f)", i, vertices[i*2], vertices[i*2+1]);
    }

    // 使用 LAppSprite 的线框绘制功能
    // 注意：坐标已经是标准化设备坐标，不需要额外的坐标转换

    // 2. 把顶点直接塞进 sprite 的缓存里
    [_renderSprite renderWireframe:vertices count:vertexCount
                                    r:r g:g b:b a:0.9f
                         lineWidth: 3.0f];

    LAppPal::PrintLogLn("[DEBUG] ViewController::drawClickableAreaWireframe completed for: %s", [areaName UTF8String]);
    
    // 避免未使用参数警告
    (void)areaName;
}

- (BOOL)loadModels:(NSString *)rootPath {
    std::string utf8Path = [rootPath UTF8String];
    Csm::csmString csmPath(utf8Path.c_str());
    return [[LAppLive2DManager getInstance] loadModels:csmPath];
}

- (BOOL)loadModelPath:(NSString *)dir
             jsonName:(NSString *)jsonName {
    // NSString → std::string → Csm::csmString
    std::string utf8Path = [dir UTF8String];
    Csm::csmString csmPath(utf8Path.c_str());
    std::string utf8Name = [jsonName UTF8String];
    Csm::csmString csmName(utf8Name.c_str());
    [[LAppLive2DManager getInstance]loadModelPath:csmPath
                                         jsonName:csmName];
    return true;
}

- (BOOL)removeAllModels {
    return [[LAppLive2DManager getInstance] removeAllModels];
}

- (int32_t)getLoadedModelNum
{
    return [[LAppLive2DManager getInstance] getLoadedModelNum];
}

@end
