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
        _showClickableAreas = NO; // 默认不显示可点击区域，调试情况下设为YES
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

    [_wireSprites removeAllObjects];
    _wireSprites = nil;

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
            if ([self hasClickableAreas])
            {
                return;
            }
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

        // 如果需要显示并且有可点击的区域则绘制可点击区域
        if (_showClickableAreas && [self hasClickableAreas])
        {
            // FIXME 不同于Android的渲染方式，iOS不能使用drawClickableAreas来渲染线框到Metal中，在LAppLive2DManager中使用 drawWireFrameForModel 进行处理
            // [self drawClickableAreas:model];
            // 创建新的渲染命令编码器用于线框绘制
            MTLRenderPassDescriptor *wireframeRenderPass = [[[MTLRenderPassDescriptor alloc] init] autorelease];
            wireframeRenderPass.colorAttachments[0].texture = drawable.texture;
            wireframeRenderPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
            wireframeRenderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
            wireframeRenderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
            id<MTLRenderCommandEncoder> wireframeEncoder = [commandBuffer renderCommandEncoderWithDescriptor:wireframeRenderPass];

            // 使用改进的wireframe绘制方法
            [self drawWireFrameForModel:model currentDrawable:drawable renderEncoder:wireframeEncoder];

            [wireframeEncoder endEncoding];
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

- (BOOL)hasClickableAreas
{
    if (_models.GetSize() == 0) return NO;
    
    LAppModel* model = [self getModel:0];
    if (!model || !model->GetModelSetting()) return NO;
    
    const Csm::csmInt32 hitAreaCount = model->GetModelSetting()->GetHitAreasCount();
    return hitAreaCount > 0;
}

- (void)setShowClickableAreas:(BOOL)show
{
    _showClickableAreas = show;
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG] Set show clickable areas: %s", show ? "YES" : "NO");
    }
}

- (BOOL)isShowingClickableAreas
{
    return _showClickableAreas;
}

- (void) drawWireFrameForModel:(LAppModel*)model currentDrawable:(id<CAMetalDrawable>)drawable renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
{
    if (!model || !model->GetModelSetting() || !renderEncoder)
    {
        return;
    }

    const Csm::csmInt32 hitAreaCount = model->GetModelSetting()->GetHitAreasCount();
    if (hitAreaCount <= 0) return;

    // 获取设备信息和尺寸
//    CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
//    id<MTLDevice> device = [single getMTLDevice];
    
//    AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
//    ViewController* view = [delegate viewController];

//    const CGFloat retinaScale = [[UIScreen mainScreen] scale];
//    const float width = view.view.frame.size.width;
//    const float height = view.view.frame.size.height;

//    const float deviceWidth = width * retinaScale;
//    const float deviceHeight = height * retinaScale;
    // FIXME 注意，这里必须使用drawable的宽高，因为设备的宽高是固定不变的，在横屏切换的时候就会出现异常
    const float width = (float)drawable.texture.width;
    const float height = (float)drawable.texture.height;

    // 获取当前模型的变换矩阵
    Csm::CubismMatrix44 modelMatrix;
    modelMatrix.LoadIdentity();

    // 应用模型的缩放和位移
    const float canvasWidth = model->GetModel()->GetCanvasWidth();
    const float canvasHeight = model->GetModel()->GetCanvasHeight();

    const float windowAspect = width / height;
    const float canvasAspect = canvasWidth / canvasHeight;

    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG] Window: %.1fx%.1f, Aspect: (%f); Canvas: %.1fx%.1f, Aspect: (%.1f), Position: (%.1f,%.1f)",
                width, height, windowAspect, canvasWidth, canvasHeight, canvasAspect, _modelPositionX, _modelPositionY);
    }

    // 根据宽高比调整投影矩阵，保持模型比例
    if (width < height)
    {
        if (canvasWidth < canvasHeight) {
            const float scaleX = (1.0f / windowAspect) / canvasWidth * _modelScale;
            const float scaleY = 2.0f / canvasHeight * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate(scaleX * _modelPositionX, scaleY * _modelPositionY);
        } else {
            // Rice
            const float scaleX = (1.0f / windowAspect) / canvasHeight * _modelScale;
            const float scaleY = canvasAspect / canvasWidth * _modelScale;
            if(canvasWidth == canvasHeight) {
                modelMatrix.Scale(2.0f * scaleX, 2.0f * scaleY);
                modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, _modelPositionY);
            } else {
                modelMatrix.Scale(scaleX, scaleY);
                // 模型尺寸只需要水平方向平移就可以了，垂直方向需要x屏幕的比例
                modelMatrix.Translate(_modelPositionX, windowAspect * _modelPositionY);
            }
        }
    }
    else
    {
        // 横屏模式
        // 确保线框绘制的宽高比例正常
        if (canvasWidth < canvasHeight) {
            const float scaleX = (1.0f / windowAspect) / canvasWidth * _modelScale;
            const float scaleY = 2.0f / canvasHeight * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, (1.0f / canvasWidth * _modelScale) * _modelPositionY);
            if (LAppDefine::DebugLogEnable) {
                LAppPal::PrintLogLn("[DEBUG] Horizonal[0] Canvas Draw And Translate scaleX: [%.1f] scaleY: [%.1f]", scaleX, scaleY);
            }
        } else {
            // Rice
            const float scaleX = (2.0f / windowAspect) / canvasHeight * _modelScale;
            const float scaleY = (2.0f * canvasAspect) / canvasWidth * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, _modelPositionY);
            if (LAppDefine::DebugLogEnable) {
                LAppPal::PrintLogLn("[DEBUG] Horizonal[1] Canvas Draw And Translate scaleX: [%.1f] scaleY: [%.1f]", scaleX, scaleY);
            }
        }
    }

    // 检查当前矩阵
    const float* matrix = modelMatrix.GetArray();

    // 遍历所有可点击区域并绘制线框
    for (Csm::csmInt32 i = 0; i < hitAreaCount; i++)
    {
        const Csm::csmChar *hitAreaName = model->GetModelSetting()->GetHitAreaName(i);
        const Csm::CubismIdHandle drawID = model->GetModelSetting()->GetHitAreaId(i);

        if (model->GetModel() && drawID)
        {
            const Csm::csmInt32 drawableIndex = model->GetModel()->GetDrawableIndex(drawID);
            if (drawableIndex >= 0)
            {
                const Csm::csmInt32 vertexCount = model->GetModel()->GetDrawableVertexCount(drawableIndex);
                const Csm::csmFloat32 *vertices = model->GetModel()->GetDrawableVertices(drawableIndex);

                if (vertexCount >= 3 && vertices)
                {
                    // 记录边界框信息
                    Csm::csmFloat32 minX = vertices[0];
                    Csm::csmFloat32 maxX = vertices[0];
                    Csm::csmFloat32 minY = vertices[1];
                    Csm::csmFloat32 maxY = vertices[1];

                    for (Csm::csmInt32 j = 1; j < vertexCount; j++)
                    {
                        Csm::csmFloat32 x = vertices[j * 2];
                        Csm::csmFloat32 y = vertices[j * 2 + 1];

                        minX = x < minX ? x : minX;
                        maxX = x > maxX ? x : maxX;
                        minY = y < minY ? y : minY;
                        maxY = y > maxY ? y : maxY;
                    }

                    // 应用模型变换到边界框顶点（转换为标准化设备坐标）
                    Csm::csmFloat32 boundaryVertices[8] = {
                        minX, minY,
                        maxX, minY,
                        maxX, maxY,
                        minX, maxY
                    };

                    // 应用模型变换矩阵到边界框顶点，使用与模型渲染相同的变换
                    for (int k = 0; k < 4; k++) {
                        float x = boundaryVertices[k * 2]; // 原始 x
                        float y = boundaryVertices[k * 2 + 1]; // 原始 y

                        // 直接转换为NDC坐标（-1到1）
                        // 1. 先得到正确的 NDC
                        float ndcX = matrix[0] * x + matrix[12];
                        float ndcY = matrix[5] * y + matrix[13];
                        // 因为matrix已经包含了正确的变换
                        // 只用了 matrix[0] 和 matrix[5]（缩放）+ matrix[12]、matrix[13]（平移）
                        boundaryVertices[k * 2] = ndcX; // 第 k 个顶点的 x
                        boundaryVertices[k * 2 + 1] = -ndcY; // 第 k 个顶点的 y， 关键：直接取反，否则会导致整个线框绘制倒置180度

                        if (LAppDefine::DebugLogEnable) {
                            LAppPal::PrintLogLn("[DEBUG] Transform[%d]: (%f, %f) -> (%f, %f)", k, x, y,
                                boundaryVertices[k * 2], boundaryVertices[k * 2 + 1]);
                        }
                    }

                    // 根据区域名称选择颜色（使用更亮的颜色）
                    float colorR = 0.0f, colorG = 1.0f, colorB = 0.0f; // 默认绿色
                    if (strcmp(hitAreaName, "Head") == 0) {
                        colorR = 1.0f; colorG = 0.2f; colorB = 0.2f; // 头部亮红色
                    } else if (strcmp(hitAreaName, "Body") == 0) {
                        colorR = 0.2f; colorG = 0.2f; colorB = 1.0f; // 身体亮蓝色
                    }

                    // 通过 ViewController 绘制边界框线框
                    if (LAppDefine::DebugLogEnable)
                    {
                        LAppPal::PrintLogLn("[DEBUG] Drawing boundary box for area: %s, bounds=[%.2f,%.2f,%.2f,%.2f]",
                                hitAreaName, minX, minY, maxX, maxY);
                    }
                    // 计算边界框中心（NDC 坐标）
                    float centerX = (boundaryVertices[0] + boundaryVertices[2] + boundaryVertices[4] + boundaryVertices[6]) / 4.0f;
                    float centerY = (boundaryVertices[1] + boundaryVertices[3] + boundaryVertices[5] + boundaryVertices[7]) / 4.0f;

                    // 将 NDC (-1~1) 转换为屏幕坐标 (0~width, 0~height)
                    float screenX = (centerX + 1.0f) * 0.5f * width;
                    float screenY = (1.0f - centerY) * 0.5f * height; // Y 轴翻转

                    // 计算边界框在屏幕上的实际宽高（用于 LAppSprite 的 Width/Height）
                    float boxWidth = (maxX - minX) * matrix[0] * 0.5f * width;
                    float boxHeight = (maxY - minY) * matrix[5] * 0.5f * height;
                    if (LAppDefine::DebugLogEnable)
                    {
                        LAppPal::PrintLogLn("[DEBUG] Drawing wireframeSprite: %s, centerX=%.2f, centerY=%.2f, Width= %.2f,Height=%.2f,MaxWidth=%.2f, MaxHeight=%.2f",
                                hitAreaName, screenX, screenY, boxWidth, boxHeight, width, height);

                    }

                    LAppSprite *wireframeSprite = _wireSprites[[NSString stringWithUTF8String:hitAreaName]];
                    if (!wireframeSprite) {
                        wireframeSprite = [[LAppSprite alloc] initWithMyVar:screenX Y:screenY Width:boxWidth Height:boxHeight
                                                                   MaxWidth:width MaxHeight:height Texture:nil];
                    }
                    // 使用LAppSprite直接绘制线框 - 准备顶点数据
                    [wireframeSprite renderWireframe:boundaryVertices count:4
                                           r:colorR g:colorG b:colorB a:0.9f];
                    // 使用提供的renderEncoder进行立即绘制
                    [wireframeSprite renderImmidiate:renderEncoder];
                }
            }
        }
    }
    
    // ARC handles memory management automatically
}

/**
 * 此方法以标记为废弃
 * @deprecated 使用 drawWireFrameForModel 来绘制Live2D模型可点击区域
 * @param model
 */
- (void) drawClickableAreas:(LAppModel*)model
{
    if (!model || !model->GetModelSetting()) return;

    const Csm::csmInt32 hitAreaCount = model->GetModelSetting()->GetHitAreasCount();
    if (hitAreaCount <= 0) return;

    AppDelegate* delegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
    ViewController* view = [delegate viewController];
    
    // 获取屏幕尺寸（使用实际视图尺寸，不是retina scale）
    const CGFloat retinaScale = [[UIScreen mainScreen] scale];
    const float width = view.view.frame.size.width;
    const float height = view.view.frame.size.height;

    // 获取当前模型的变换矩阵
    Csm::CubismMatrix44 modelMatrix;
    modelMatrix.LoadIdentity();

    // 应用模型的缩放和位移，同时对绘制的线框也需要同步缩放和移动
    const float canvasWidth = model->GetModel()->GetCanvasWidth() * retinaScale;
    const float canvasHeight = model->GetModel()->GetCanvasHeight() * retinaScale;
    const float deviceWidth = width * retinaScale;
    const float deviceHeight = height * retinaScale;
    
    // 计算正确的缩放比例，匹配C++实现
    const float windowAspect = deviceWidth / deviceHeight;
    // 4. 投影矩阵补偿屏幕宽高比（防止圆形变椭圆）
    const float canvasAspect = canvasWidth / canvasHeight;
    if (LAppDefine::DebugLogEnable)
    {
        LAppPal::PrintLogLn("[DEBUG] Window: %.1fx%.1f, Aspect: (%f); Canvas: %.1fx%.1f, Aspect: (%.1f), Position: (%.1f,%.1f)",
                deviceWidth, deviceHeight, windowAspect, canvasWidth, canvasHeight, canvasAspect, _modelPositionX, _modelPositionY);
    }
    // 根据宽高比调整投影矩阵，保持模型比例
    if (deviceWidth < deviceHeight)
    {
        if (canvasWidth < canvasHeight) {
            const float scaleX = (1.0f / windowAspect) / canvasWidth * _modelScale;
            const float scaleY = 2.0f / canvasHeight * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate(scaleX*_modelPositionX, scaleY*_modelPositionY);
        } else {
            // Rice
            const float scaleX = (1.0f / windowAspect) / canvasHeight * _modelScale;
            const float scaleY = canvasAspect / canvasWidth * _modelScale;
            if(canvasWidth == canvasHeight) {
                modelMatrix.Scale(2.0f * scaleX, 2.0f * scaleY);
                modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, _modelPositionY);
            } else {
                modelMatrix.Scale(scaleX, scaleY);
                // 模型尺寸只需要水平方向平移就可以了，垂直方向需要x屏幕的比例
                modelMatrix.Translate(_modelPositionX, windowAspect * _modelPositionY);
            }
        }
    }
    else
    {
        // 横屏模式
        // 确保线框绘制的宽高比例正常
        if (canvasWidth < canvasHeight) {
            const float scaleX = (1.0f / windowAspect) / canvasWidth * _modelScale;
            const float scaleY = 2.0f / canvasHeight * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, (1.0f / canvasWidth * _modelScale) * _modelPositionY);
        } else {
            // Rice
            const float scaleX = (2.0f / windowAspect) / canvasHeight * _modelScale;
            const float scaleY = (2.0f * canvasAspect) / canvasWidth * _modelScale;
            modelMatrix.Scale(scaleX, scaleY);
            modelMatrix.Translate((1.0f / windowAspect) * _modelPositionX, _modelPositionY);
        }
    }

    // 检查当前矩阵
    const float* matrix = modelMatrix.GetArray();

    // 遍历所有可点击区域并绘制
    for (Csm::csmInt32 i = 0; i < hitAreaCount; i++)
    {
        const Csm::csmChar *hitAreaName = model->GetModelSetting()->GetHitAreaName(i);
        const Csm::CubismIdHandle drawID = model->GetModelSetting()->GetHitAreaId(i);

        if (model->GetModel() && drawID)
        {
            const Csm::csmInt32 drawableIndex = model->GetModel()->GetDrawableIndex(drawID);
            if (drawableIndex >= 0)
            {
                const Csm::csmInt32 vertexCount = model->GetModel()->GetDrawableVertexCount(drawableIndex);
                const Csm::csmFloat32 *vertices = model->GetModel()->GetDrawableVertices(drawableIndex);

                if (vertexCount >= 3 && vertices)
                {
                    // 记录边界框信息
                    Csm::csmFloat32 minX = vertices[0];
                    Csm::csmFloat32 maxX = vertices[0];
                    Csm::csmFloat32 minY = vertices[1];
                    Csm::csmFloat32 maxY = vertices[1];

                    for (Csm::csmInt32 j = 1; j < vertexCount; j++)
                    {
                        Csm::csmFloat32 x = vertices[j * 2];
                        Csm::csmFloat32 y = vertices[j * 2 + 1];

                        minX = x < minX ? x : minX;
                        maxX = x > maxX ? x : maxX;
                        minY = y < minY ? y : minY;
                        maxY = y > maxY ? y : maxY;
                    }

                    if (LAppDefine::DebugLogEnable)
                    {
                        LAppPal::PrintLogLn("[DEBUG] Clickable Area[%d]: %s [%.2f, %.2f, %.2f, %.2f] (Raw)",
                                i, hitAreaName, minX, minY, maxX, maxY);
                    }

                    // 创建边界框顶点（矩形）
                    // 一个 长度为 8 的 float 数组，用来存放一个 矩形边界框的 4 个顶点坐标
                    float boundaryVertices[8] = {
                        minX, minY,  // 左下角
                        maxX, minY,  // 右下角
                        maxX, maxY,  // 右上角
                        minX, maxY   // 左上角
                    };

                    // 应用模型变换矩阵到边界框顶点，使用与模型渲染相同的变换
                    for (int k = 0; k < 4; k++) {
                        float x = boundaryVertices[k * 2]; // 原始 x
                        float y = boundaryVertices[k * 2 + 1]; // 原始 y

                        // 直接转换为NDC坐标（-1到1），不需要额外的屏幕坐标转换
                        // 因为matrix已经包含了正确的变换
                        // 只用了 matrix[0] 和 matrix[5]（缩放）+ matrix[12]、matrix[13]（平移）
                        boundaryVertices[k * 2] = matrix[0] * x + matrix[12]; // 第 k 个顶点的 x
                        boundaryVertices[k * 2 + 1] = matrix[5] * y + matrix[13]; // 第 k 个顶点的 y

                        if (LAppDefine::DebugLogEnable) {
                            LAppPal::PrintLogLn("[DEBUG] Transform[%d]: (%f, %f) -> (%f, %f)", k, x, y,
                                boundaryVertices[k * 2], boundaryVertices[k * 2 + 1]);
                        }
                    }

                    // 根据区域名称选择颜色（使用更亮的颜色）
                    float r = 0.0f, g = 1.0f, b = 0.0f; // 默认绿色
                    if (strcmp(hitAreaName, "Head") == 0) {
                        r = 1.0f; g = 0.2f; b = 0.2f; // 头部亮红色
                    } else if (strcmp(hitAreaName, "Body") == 0) {
                        r = 0.2f; g = 0.2f; b = 1.0f; // 身体亮蓝色
                    }

                    // 通过 ViewController 绘制边界框线框
                    if (LAppDefine::DebugLogEnable)
                    {
                        LAppPal::PrintLogLn("[DEBUG] Drawing boundary box for area: %s, bounds=[%.2f,%.2f,%.2f,%.2f]",
                                hitAreaName, minX, minY, maxX, maxY);
                    }

                    [view drawClickableAreaWireframe:boundaryVertices
                                           vertexCount:4
                                           r:r g:g b:b
                                           areaName:[NSString stringWithUTF8String:hitAreaName]];
                }
            }
        }
    }
}

@end
