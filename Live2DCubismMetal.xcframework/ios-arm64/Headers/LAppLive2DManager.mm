/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import "LAppLive2DManager.h"
#import <string.h>
#import <stdlib.h>
#import <Foundation/Foundation.h>
#import "AppDelegate.h"
#import "ViewController.h"
#import "LAppModel.h"
#import "LAppDefine.h"
#import "LAppPal.h"
#import "Live2DCallbackBridge.h"
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import "Rendering/Metal/CubismRenderingInstanceSingleton_Metal.h"

@interface LAppLive2DManager()
@property (nonatomic, assign) float modelScale;   // 模型缩放
@property (nonatomic, assign) float modelPositionX;   // 模型X坐标
@property (nonatomic, assign) float modelPositionY;   // 模型Y坐标
@property (nonatomic, assign) float modelMouth;   // 模型口型
- (id)init;
- (void)dealloc;
@end

@implementation LAppLive2DManager

static LAppLive2DManager* s_instance = nil;

void BeganMotion(Csm::ACubismMotion* self)
{
    LAppPal::PrintLogLn("Motion began: %x", self);
}

void FinishedMotion(Csm::ACubismMotion* self)
{
    LAppPal::PrintLogLn("Motion Finished: %x", self);
}

int CompareCsmString(const void* a, const void* b)
{
    return strcmp(reinterpret_cast<const Csm::csmString*>(a)->GetRawString(),
        reinterpret_cast<const Csm::csmString*>(b)->GetRawString());
}

Csm::csmString GetPath(CFURLRef url)
{
  CFStringRef cfstr = CFURLCopyFileSystemPath(url, CFURLPathStyle::kCFURLPOSIXPathStyle);
  CFIndex size = CFStringGetLength(cfstr) * 4 + 1; // Length * UTF-16 Max Character size + null-terminated-byte
  char* buf = new char[size];
  CFStringGetCString(cfstr, buf, size, CFStringBuiltInEncodings::kCFStringEncodingUTF8);
  Csm::csmString result(buf);
  delete[] buf;
  return result;
}

+ (LAppLive2DManager*)getInstance
{
    @synchronized(self)
    {
        if (s_instance == nil)
        {
            s_instance = [[LAppLive2DManager alloc] init];
        }
    }
    return s_instance;
}

+ (void)releaseInstance
{
    if (s_instance != nil)
    {
        [s_instance release];
        s_instance = nil;
    }
}

- (id)init
{
    self = [super init];
    if ( self ) {
        _renderBuffer = nil;
        _modelSprite = nil;
        _sprite = nil;
        _viewMatrix = nil;
        _sceneIndex = 0;
        _modelScale = 1.0f;   // 默认不放大
        _modelPositionX = 0.0f; // 模型X坐标
        _modelPositionY = 0.0f; // 模型Y坐标
        _modelMouth = 0.0f; // 闭嘴状态，办张0.5f，张嘴1.0f
        _viewMatrix = new Csm::CubismMatrix44();

        _renderPassDescriptor = [[MTLRenderPassDescriptor alloc] init];
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.f, 0.f, 0.f, 0.f);
        _renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _renderPassDescriptor.depthAttachment.clearDepth = 1.0;

        [self setUpModel];

        [self changeScene:_sceneIndex];
    }
    return self;
}

- (void)dealloc
{
    if (_renderBuffer)
    {
        _renderBuffer->DestroyOffscreenSurface();
        delete _renderBuffer;
        _renderBuffer = NULL;
    }

    if (_renderPassDescriptor != nil)
    {
        [_renderPassDescriptor release];
        _renderPassDescriptor = nil;
    }

    if (_modelSprite != nil)
    {
        [_modelSprite release];
        _modelSprite = nil;
    }

    if (_sprite != nil)
    {
       [_sprite release];
        _sprite = nil;
    }

    delete _viewMatrix;
    _viewMatrix = nil;

    [self releaseAllModel];
    [super dealloc];
}

- (void)releaseAllModel
{
    for (Csm::csmUint32 i = 0; i < _models.GetSize(); i++)
    {
        delete _models[i];
    }

    _models.Clear();
}

- (void)setUpModel
{
    _modelDir.Clear();

    NSBundle* bundle = [NSBundle mainBundle];
    NSString* resPath = [NSString stringWithUTF8String:LAppDefine::ResourcesPath];
    NSArray* resArr = [bundle pathsForResourcesOfType:NULL inDirectory:resPath];
    NSUInteger cnt = [resArr count];

    for (NSUInteger i = 0; i < cnt; i++)
    {
        NSString* modelName = [[resArr objectAtIndex:i] lastPathComponent];
        NSMutableString* modelDirPath = [NSMutableString stringWithString:resPath];
        [modelDirPath appendString:@"/"];
        [modelDirPath appendString:modelName];
        NSArray* model3json = [bundle pathsForResourcesOfType:@".model3.json" inDirectory:modelDirPath];
        if ([model3json count] == 1)
        {
            _modelDir.PushBack(Csm::csmString([modelName UTF8String]));
        }
    }
    qsort(_modelDir.GetPtr(), _modelDir.GetSize(), sizeof(Csm::csmString), CompareCsmString);
}

- (LAppModel*)getModel:(Csm::csmUint32)no
{
    if (no < _models.GetSize())
    {
        return _models[no];
    }
    return nil;
}

- (void)onDrag:(Csm::csmFloat32)x floatY:(Csm::csmFloat32)y
{
    for (Csm::csmUint32 i = 0; i < _models.GetSize(); i++)
    {
        Csm::CubismUserModel* model = static_cast<Csm::CubismUserModel*>([self getModel:i]);
        model->SetDragging(x,y);
    }
}

- (void)onTap:(Csm::csmFloat32)x floatY:(Csm::csmFloat32)y;
{
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[APP]tap point: {x:%.2f y:%.2f}", x, y);
    }

    for (Csm::csmUint32 i = 0; i < _models.GetSize(); i++)
    {
        if (_models[i]->HitTest(LAppDefine::HitAreaNameHead,x,y))
        {
            if (LAppDefine::DebugLogEnable)
            {
                LAppPal::PrintLogLn("[APP]hit area: [%s]", LAppDefine::HitAreaNameHead);
            }
            
            // 触发点击回调
            [[Live2DCallbackBridge sharedInstance] onHitArea:LAppDefine::HitAreaNameHead 
                                                   modelName:[NSString stringWithUTF8String:_modelDir[_sceneIndex].GetRawString()].UTF8String 
                                                           x:x y:y];
            
            _models[i]->SetRandomExpression();

        }
        else if (_models[i]->HitTest(LAppDefine::HitAreaNameBody, x, y))
        {
            if (LAppDefine::DebugLogEnable)
            {
                LAppPal::PrintLogLn("[APP]hit area: [%s]", LAppDefine::HitAreaNameBody);
            }
            
            // 触发点击回调
            [[Live2DCallbackBridge sharedInstance] onHitArea:LAppDefine::HitAreaNameBody 
                                                   modelName:[NSString stringWithUTF8String:_modelDir[_sceneIndex].GetRawString()].UTF8String 
                                                           x:x y:y];
            
            // _models[i]->StartRandomMotion(LAppDefine::MotionGroupTapBody, LAppDefine::PriorityNormal, FinishedMotion, BeganMotion);

            // 触发动画开始回调 - 获取实际的motion文件路径
            const Csm::csmChar* motionGroup = LAppDefine::MotionGroupTapBody;
            Csm::csmInt32 motionCount = _models[i]->GetModelSetting()->GetMotionCount(motionGroup);
            LAppPal::PrintLogLn("[DEBUG] motionCount: %d", motionCount);
            if (motionCount > 0) {
                Csm::csmInt32 selectedIndex = rand() % motionCount;

                _models[i]->StartMotion(motionGroup, selectedIndex, LAppDefine::PriorityNormal, FinishedMotion, BeganMotion);

                const Csm::csmString fileName = _models[i]->GetModelSetting()->GetMotionFileName(motionGroup, selectedIndex);
                Csm::csmString motionPath = Csm::csmString(_models[i]->GetModelHomeDir()) + fileName;
                const Csm::csmChar* filePath = motionPath.GetRawString();
                if (LAppDefine::DebugLogEnable)
                {
                    // 添加调试日志
                    LAppPal::PrintLogLn("[DEBUG] fileName: %s", fileName.GetRawString());
                    LAppPal::PrintLogLn("[DEBUG] modelHomeDir: %s", _models[i]->GetModelHomeDir().GetRawString());
                    LAppPal::PrintLogLn("[DEBUG] full motionPath: %s", filePath);
                    LAppPal::PrintLogLn("[DEBUG] motionGroup: %s, selectedIndex: %d", motionGroup, selectedIndex);
                }

                // 创建静态缓冲区来存储字符串，确保生命周期足够长
                static char staticBuffer[512];
                strncpy(staticBuffer, filePath, sizeof(staticBuffer) - 1);
                staticBuffer[sizeof(staticBuffer) - 1] = '\0';
                
                [[Live2DCallbackBridge sharedInstance] onMotionStart:motionGroup
                                                        motionIndex:selectedIndex
                                                      motionFilePath:staticBuffer];
            }
        }
        else
        {
            if (LAppDefine::DebugLogEnable)
            {
                LAppPal::PrintLogLn("[APP]no hit areas found, triggering motion directly");
            }

            // 处理无HitAreas的模型，直接触发Motion
            Csm::ICubismModelSetting* setting = _models[i]->GetModelSetting();
            if (setting)
            {
                // 定义支持的motion分组
                const Csm::csmChar* motionGroups[] = { "Tap", "Flick", "FlickRight", "FlickLeft", "Flick3", "Shake" };
                Csm::csmInt32 groupCount = sizeof(motionGroups) / sizeof(motionGroups[0]);
                
                // 先检查Tap分组，如果没有再随机选择其他分组
                Csm::csmInt32 tapMotionCount = setting->GetMotionCount(LAppDefine::MotionGroupTapBody);
                if (tapMotionCount > 0) {
                    // 优先使用Tap分组
                    Csm::csmInt32 selectedIndex = rand() % tapMotionCount;
                    _models[i]->StartMotion(LAppDefine::MotionGroupTapBody, selectedIndex, LAppDefine::PriorityNormal, FinishedMotion, BeganMotion);

                    const Csm::csmString fileName = setting->GetMotionFileName(LAppDefine::MotionGroupTapBody, selectedIndex);
                    Csm::csmString motionPath = Csm::csmString(_models[i]->GetModelHomeDir()) + fileName;
                    const Csm::csmChar* filePath = motionPath.GetRawString();
                    
                    if (LAppDefine::DebugLogEnable)
                    {
                        LAppPal::PrintLogLn("[DEBUG] Using Tap motion: %s", fileName.GetRawString());
                    }
                    
                    // 创建静态缓冲区来存储字符串，确保生命周期足够长
                    static char staticBuffer[512];
                    strncpy(staticBuffer, filePath, sizeof(staticBuffer) - 1);
                    staticBuffer[sizeof(staticBuffer) - 1] = '\0';
                    
                    [[Live2DCallbackBridge sharedInstance] onMotionStart:LAppDefine::MotionGroupTapBody
                                                            motionIndex:selectedIndex
                                                          motionFilePath:staticBuffer];
                } else {
                    // Tap分组为空，尝试其他分组
                    for (Csm::csmInt32 j = 0; j < groupCount; j++)
                    {
                        Csm::csmInt32 motionCount = setting->GetMotionCount(motionGroups[j]);
                        if (motionCount > 0) {
                            Csm::csmInt32 selectedIndex = rand() % motionCount;
                            _models[i]->StartMotion(motionGroups[j], selectedIndex, LAppDefine::PriorityNormal, FinishedMotion, BeganMotion);

                            const Csm::csmString fileName = setting->GetMotionFileName(motionGroups[j], selectedIndex);
                            Csm::csmString motionPath = Csm::csmString(_models[i]->GetModelHomeDir()) + fileName;
                            const Csm::csmChar* filePath = motionPath.GetRawString();
                            
                            if (LAppDefine::DebugLogEnable)
                            {
                                LAppPal::PrintLogLn("[DEBUG] Using %s motion: %s", motionGroups[j], fileName.GetRawString());
                            }
                            
                            // 创建静态缓冲区来存储字符串，确保生命周期足够长
                            static char staticBuffer[512];
                            strncpy(staticBuffer, filePath, sizeof(staticBuffer) - 1);
                            staticBuffer[sizeof(staticBuffer) - 1] = '\0';
                            
                            [[Live2DCallbackBridge sharedInstance] onMotionStart:motionGroups[j]
                                                                    motionIndex:selectedIndex
                                                                  motionFilePath:staticBuffer];
                            break; // 找到第一个有motion的分组就停止
                        }
                    }
                }
            }
        }
    }
}

- (void)onUpdate:(id <MTLCommandBuffer>)commandBuffer currentDrawable:(id<CAMetalDrawable>)drawable depthTexture:(id<MTLTexture>)depthTarget;
{
    AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
    ViewController* view = [delegate viewController];

    const CGFloat retinaScale = [[UIScreen mainScreen] scale];
    // Retinaディスプレイサイズにするため倍率をかける
    const float width = view.view.frame.size.width * retinaScale;
    const float height = view.view.frame.size.height * retinaScale;

    Csm::CubismMatrix44 projection;
    Csm::csmUint32 modelCount = _models.GetSize();

    CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
    id<MTLDevice> device = [single getMTLDevice];

    _renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
    _renderPassDescriptor.depthAttachment.texture = depthTarget;

    if (_renderTarget != SelectTarget_None)
    {
        if (!_renderBuffer)
        {
            _renderBuffer = new Csm::Rendering::CubismOffscreenSurface_Metal;
            _renderBuffer->SetMTLPixelFormat(MTLPixelFormatBGRA8Unorm);
            _renderBuffer->SetClearColor(0.0, 0.0, 0.0, 0.0);
            _renderBuffer->CreateOffscreenSurface(static_cast<LAppDefine::csmUint32>(width), static_cast<LAppDefine::csmUint32>(height), nil);

            if (_renderTarget == SelectTarget_ViewFrameBuffer)
            {
                _sprite = [[LAppSprite alloc] initWithMyVar:width * 0.5f Y:height * 0.5f Width:width Height:height
                                                   MaxWidth:width MaxHeight:height Texture:_renderBuffer->GetColorBuffer()];
                _modelSprite = [[LAppModelSprite alloc] initWithMyVar:width * 0.5f Y:height * 0.5f Width:width Height:height
                                                   MaxWidth:width MaxHeight:height Texture:_renderBuffer->GetColorBuffer()];
            }
        }

        if (_renderTarget == SelectTarget_ViewFrameBuffer)
        {
            _renderPassDescriptor.colorAttachments[0].texture = _renderBuffer->GetColorBuffer();
            _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        }

        //画面クリア
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderBuffer->GetRenderPassDescriptor()];
        [renderEncoder endEncoding];
    }

    Csm::Rendering::CubismRenderer_Metal::StartFrame(device, commandBuffer, _renderPassDescriptor);

    for (Csm::csmUint32 i = 0; i < modelCount; ++i)
    {
        LAppModel* model = [self getModel:i];

        if (model->GetModel() == NULL)
        {
            LAppPal::PrintLogLn("Failed to model->GetModel().");
            continue;
        }

        // 1. 画布原始尺寸
        const float canvasWidth  = model->GetModel()->GetCanvasWidth();
        const float canvasHeight = model->GetModel()->GetCanvasHeight();

        // 2. 让模型整体落在 -1~1 范围内，保持比例
        const float baseScale = 2.0f / canvasHeight;

        // 2. drawable 实际像素宽高
        const float drawableW = (float)drawable.texture.width;
        const float drawableH = (float)drawable.texture.height;

        // 3. 投影矩阵补偿屏幕宽高比（防止圆形变椭圆）
        const float aspect = drawableW / drawableH;
        // 投影矩阵补偿： *2 抵消官方内部 *0.5，再乘 aspect
        if (model->GetModel()->GetCanvasWidth() > 1.0f && drawableW < drawableH) {
            model->GetModelMatrix()->SetWidth(2.0f);
            projection.Scale(1.0f, aspect);
        } else {
            projection.Scale(1.0f / aspect, 1.0f);
        }

        // TODO 提供一个全局的变量可以通过方法修改这个值从而实现自定义缩放大小
        // 4. 模型矩阵只做这一次等比缩放，重置模型矩阵
        model->GetModelMatrix()->LoadIdentity();
        // 注意Scale方法的调用一定要在LoadIdentify之后，否则会失效
        model->GetModelMatrix()->Scale(baseScale * _modelScale, baseScale * _modelScale);
        model->GetModelMatrix()->Translate(_modelPositionX, _modelPositionY);
        model->SetLipSyncValue(_modelMouth);
//        if (model->GetModel()->GetCanvasWidth() > 1.0f && width < height)
//        {
//            // 横に長いモデルを縦長ウィンドウに表示する際モデルの横サイズでscaleを算出する
//            model->GetModelMatrix()->SetWidth(2.0f);
//            projection.Scale(1.0f, static_cast<float>(width) / static_cast<float>(height));
//        }
//        else
//        {
//            projection.Scale(static_cast<float>(height) / static_cast<float>(width), 1.0f);
//        }

        // 获取模型原始尺寸（Canvas尺寸）
//        float modelWidth = model->GetModel()->GetCanvasWidth();
//        float modelHeight = model->GetModel()->GetCanvasHeight();
//
//        model->GetModelMatrix()->SetWidth(2.0f);
//        // 直接根据宽高比进行缩放，无需>1.0f判断
//        if (modelWidth > modelHeight) {
//            // 横长模型
//            float scale = height / modelHeight;
//            model->GetModelMatrix()->Scale(scale, scale);
//        } else {
//            // 竖长或方形模型
//            float scale = width / modelWidth;
//            model->GetModelMatrix()->Scale(scale, scale);
//        }

        // 重置模型矩阵
//        model->GetModelMatrix()->LoadIdentity();

        // 必要があればここで乗算
        if (_viewMatrix != NULL)
        {
            projection.MultiplyByMatrix(_viewMatrix);
        }

        if (_renderTarget == SelectTarget_ModelFrameBuffer)
        {
            Csm::Rendering::CubismOffscreenSurface_Metal& useTarget = model->GetRenderBuffer();

            if (!useTarget.IsValid())
            {// 描画ターゲット内部未作成の場合はここで作成
                // モデル描画キャンバス
                useTarget.SetMTLPixelFormat(MTLPixelFormatBGRA8Unorm);
                useTarget.CreateOffscreenSurface(static_cast<LAppDefine::csmUint32>(width), static_cast<LAppDefine::csmUint32>(height));
            }
            _renderPassDescriptor.colorAttachments[0].texture = useTarget.GetColorBuffer();
            _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;

            Csm::Rendering::CubismRenderer_Metal::StartFrame(device, commandBuffer, _renderPassDescriptor);
        }

        model->Update();
        model->Draw(projection);///< 参照渡しなのでprojectionは変質する

        if (_renderTarget == SelectTarget_ViewFrameBuffer && _renderBuffer && _modelSprite)
        {
            MTLRenderPassDescriptor *renderPassDescriptor = [[[MTLRenderPassDescriptor alloc] init] autorelease];
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            float alpha = 0.4f;
            [_modelSprite SetColor:1.0f * alpha g:1.0f * alpha b:1.0f * alpha a:alpha];
            [_modelSprite renderImmidiate:renderEncoder];
            [renderEncoder endEncoding];
        }

        // 各モデルが持つ描画ターゲットをテクスチャとする場合はスプライトへの描画はここ
        if (_renderTarget == SelectTarget_ModelFrameBuffer)
        {
            if (!model)
            {
                return;
            }

            MTLRenderPassDescriptor *renderPassDescriptor = [[[MTLRenderPassDescriptor alloc] init] autorelease];
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

            Csm::Rendering::CubismOffscreenSurface_Metal& useTarget = model->GetRenderBuffer();
            LAppModelSprite* depthSprite = [[LAppModelSprite alloc] initWithMyVar:width * 0.5f Y:height * 0.5f Width:width Height:height
                                                               MaxWidth:width MaxHeight:height Texture:useTarget.GetColorBuffer()];
            float a = i < 1 ? 1.0f : model->GetOpacity(); // 片方のみ不透明度を取得できるようにする
            [depthSprite SetColor:1.0f * a g:1.0f * a b:1.0f * a a:a];
            [depthSprite renderImmidiate:renderEncoder];
            [renderEncoder endEncoding];
            [depthSprite dealloc];
        }
    }
}

- (void)nextScene;
{
    Csm::csmInt32 no = (_sceneIndex + 1) % _modelDir.GetSize();
    [self changeScene:no];
}

- (void)changeScene:(Csm::csmInt32)index;
{
    _sceneIndex = index;
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[APP]model index: %d", _sceneIndex);
    }

    // model3.jsonのパスを決定する.
    // ディレクトリ名とmodel3.jsonの名前を一致させておくこと.
    const Csm::csmString& model = _modelDir[index];

    Csm::csmString modelPath(LAppDefine::ResourcesPath);
    modelPath += model;
    modelPath.Append(1, '/');

    Csm::csmString modelJsonName(model);
    modelJsonName += ".model3.json";

    [self releaseAllModel];
    _models.PushBack(new LAppModel());
    _models[0]->LoadAssets(modelPath.GetRawString(), modelJsonName.GetRawString());

    /*
     * モデル半透明表示を行うサンプルを提示する。
     * ここでUSE_RENDER_TARGET、USE_MODEL_RENDER_TARGETが定義されている場合
     * 別のレンダリングターゲットにモデルを描画し、描画結果をテクスチャとして別のスプライトに張り付ける。
     */
    {
#if defined(USE_RENDER_TARGET)
        // LAppViewの持つターゲットに描画を行う場合、こちらを選択
        SelectTarget useRenderTarget = SelectTarget_ViewFrameBuffer;
#elif defined(USE_MODEL_RENDER_TARGET)
        // 各LAppModelの持つターゲットに描画を行う場合、こちらを選択
        SelectTarget useRenderTarget = SelectTarget_ModelFrameBuffer;
#else
        // デフォルトのメインフレームバッファへレンダリングする(通常)
        SelectTarget useRenderTarget = SelectTarget_None;
#endif

#if defined(USE_RENDER_TARGET) || defined(USE_MODEL_RENDER_TARGET)
        // モデル個別にαを付けるサンプルとして、もう1体モデルを作成し、少し位置をずらす
        _models.PushBack(new LAppModel());
        _models[1]->LoadAssets(modelPath.GetRawString(), modelJsonName.GetRawString());
        _models[1]->GetModelMatrix()->TranslateX(0.2f);
#endif

        float clearColorR = 0.0f;
        float clearColorG = 0.0f;
        float clearColorB = 0.0f;

        AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
        ViewController* view = [delegate viewController];

        [self SwitchRenderingTarget:useRenderTarget];
        [self SetRenderTargetClearColor:clearColorR g:clearColorG b:clearColorB];
    }
}

- (Csm::csmUint32)GetModelNum;
{
    return _models.GetSize();
}

- (void)SetViewMatrix:(Csm::CubismMatrix44*)m;
{
    for (int i = 0; i < 16; i++) {
        _viewMatrix->GetArray()[i] = m->GetArray()[i];
    }
}

- (void)SwitchRenderingTarget:(SelectTarget)targetType
{
    _renderTarget = targetType;
}

- (void)SetRenderTargetClearColor:(float)r g:(float)g b:(float)b
{
    _clearColorR = r;
    _clearColorG = g;
    _clearColorB = b;
}

- (void)setModelScale:(float)scale
{
    _modelScale = scale;
}

- (void)moveModel:(float)x y:(float)y
{
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG]move model: x: [%f]; y: [%f]", x, y);
    }
    AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
    ViewController* view = [delegate viewController];

    const CGFloat retinaScale = [[UIScreen mainScreen] scale];
    // Retinaディスプレイサイズにするため倍率をかける
    const float width = view.view.frame.size.width * retinaScale;
    const float height = view.view.frame.size.height * retinaScale;
    _modelPositionX += x / width * 2.0f;
    _modelPositionY += -y / width * 2.0f;
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG]move model: normalizedX: [%f]; normalizedY: [%f]", _modelPositionX, _modelPositionY);
    }
}

- (void)updateLipSync:(float)mouth
{
    _modelMouth = mouth;
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG]lip sync mouth: [%f]", _modelMouth);
    }

}

@end
