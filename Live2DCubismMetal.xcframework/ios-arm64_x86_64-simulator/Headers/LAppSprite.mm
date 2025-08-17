/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import "LAppSprite.h"
#import <Foundation/Foundation.h>
#import "LAppDefine.h"
#import "LAppPal.h"
#import <CubismFramework.hpp>
#import <Rendering/Metal/CubismRenderer_Metal.hpp>
#import "Rendering/Metal/CubismRenderingInstanceSingleton_Metal.h"

#define BUFFER_OFFSET(bytes) ((GLubyte *)NULL + (bytes))


@interface LAppSprite()

@property (nonatomic, readwrite) id <MTLTexture> texture; // テクスチャ
@property (nonatomic) SpriteRect rect; // 矩形
@property (nonatomic) id <MTLBuffer> vertexBuffer;
@property (nonatomic) id <MTLBuffer> fragmentBuffer;

@end

@implementation LAppSprite

typedef struct
{
    vector_float4 baseColor;

} BaseColor;

- (id)initWithMyVar:(float)x Y:(float)y Width:(float)width Height:(float)height
                    MaxWidth:(float)maxWidth MaxHeight:(float)maxHeight Texture:(id <MTLTexture>) texture
{
    self = [super self];

    if (self != nil)
    {
        _rect.left = (x - width * 0.5f);
        _rect.right = (x + width * 0.5f);
        _rect.up = (y + height * 0.5f);
        _rect.down = (y - height * 0.5f);
        _texture = texture;

        _spriteColorR = _spriteColorG = _spriteColorB = _spriteColorA = 1.0f;

        _pipelineState = nil;
        _vertexBuffer = nil;
        _fragmentBuffer = nil;
        _wireframePipeline = nil;

        CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
        id <MTLDevice> device = [single getMTLDevice];

        [self SetMTLBuffer:device MaxWidth:maxWidth MaxHeight:maxHeight];

        [self SetMTLFunction:device];

        [self SetWireframePipeline:device];
    }

    return self;
}

- (void)dealloc
{
    if (_pipelineState != nil)
    {
        [_pipelineState release];
        _pipelineState = nil;
    }

    if (_vertexBuffer != nil)
    {
        [_vertexBuffer release];
        _vertexBuffer = nil;
    }

    if (_fragmentBuffer != nil)
    {
        [_fragmentBuffer release];
        _fragmentBuffer = nil;
    }

    if (_wireframePipeline != nil)
    {
        _wireframePipeline = nil;
    }

    [super dealloc];
}

- (void)renderImmidiate:(id<MTLRenderCommandEncoder>)renderEncoder
{
    if (_texture == nil) {
        /* ---------- 线框渲染 ---------- */
        if (_wireframeVertexCount < 2 || !_vertexBuffer) return;

        // 1️⃣ 使用线框专用 pipeline（无纹理，直接 RGBA）
        [renderEncoder setRenderPipelineState:_wireframePipeline];
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        if(_wireframePipeline == NULL)
        {
            NSLog(@" ERROR: _wireframePipeline is NULL");
            return;
        }
        // 2️⃣ 传入颜色（来自 SetRenderWireframe 设置的 RGBA）
        vector_float4 color = { _spriteColorR, _spriteColorG, _spriteColorB, _spriteColorA };
        [renderEncoder setFragmentBytes:&color length:sizeof(color) atIndex:2];

        // 3️⃣ 画线
        [renderEncoder drawPrimitives:MTLPrimitiveTypeLineStrip
                          vertexStart:0
                          vertexCount:_wireframeVertexCount];

//        LAppPal::PrintLogLn("[DEBUG] LAppSprite::renderImmidiate rendering wireframe with %d vertices，color=(%.1f,%.1f,%.1f,%.1f)",
//                _wireframeVertexCount, _spriteColorR, _spriteColorG, _spriteColorB, _spriteColorA);
    }
    else
    {
        CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
        id <MTLDevice> device = [single getMTLDevice];

        float width = _rect.right - _rect.left;
        float height = _rect.up - _rect.down;

        //テクスチャ設定
        [renderEncoder setFragmentTexture:_texture atIndex:0];

        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:_fragmentBuffer offset:0 atIndex:1];
        if(_pipelineState == NULL)
        {
            return;
        }
        // パイプライン状態オブジェクトを設定する
        [renderEncoder setRenderPipelineState:_pipelineState];

        vector_float2 metalUniforms = (vector_float2){width,height};
        [renderEncoder setVertexBytes:&metalUniforms length:sizeof(vector_float2) atIndex:2];

        BaseColor uniform;
        uniform.baseColor = (vector_float4){ _spriteColorR, _spriteColorG, _spriteColorB, _spriteColorA };
        [renderEncoder setFragmentBytes:&uniform length:sizeof(BaseColor) atIndex:2];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    }
}

- (void)resizeImmidiate:(float)x Y:(float)y Width:(float)width Height:(float)height MaxWidth:(float)maxWidth MaxHeight:(float)maxHeight
{
    _rect.left = (x - width * 0.5f);
    _rect.right = (x + width * 0.5f);
    _rect.up = (y + height * 0.5f);
    _rect.down = (y - height * 0.5f);

    CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
    id <MTLDevice> device = [single getMTLDevice];
    [self SetMTLBuffer:device MaxWidth:maxWidth MaxHeight:maxHeight];

    return self;
}

- (bool)isHit:(float)pointX PointY:(float)pointY
{
    return (pointX >= _rect.left && pointX <= _rect.right &&
            pointY >= _rect.down && pointY <= _rect.up);
}

- (void)SetColor:(float)r g:(float)g b:(float)b a:(float)a
{
    _spriteColorR = r;
    _spriteColorG = g;
    _spriteColorB = b;
    _spriteColorA = a;
}

- (void)SetMTLBuffer:(id <MTLDevice>)device MaxWidth:(float)maxWidth MaxHeight:(float)maxHeight
{
    vector_float4 positionVertex[] =
    {
        {(_rect.left  - maxWidth * 0.5f) / (maxWidth * 0.5f), (_rect.down - maxHeight * 0.5f) / (maxHeight * 0.5f), 0, 1},
        {(_rect.right - maxWidth * 0.5f) / (maxWidth * 0.5f), (_rect.down - maxHeight * 0.5f) / (maxHeight * 0.5f), 0, 1},
        {(_rect.left  - maxWidth * 0.5f) / (maxWidth * 0.5f), (_rect.up   - maxHeight * 0.5f) / (maxHeight * 0.5f), 0, 1},
        {(_rect.right - maxWidth * 0.5f) / (maxWidth * 0.5f), (_rect.up   - maxHeight * 0.5f) / (maxHeight * 0.5f), 0, 1},
    };

    vector_float2 uvVertex[] =
    {
        {0.0f, 1.0f},
        {1.0f, 1.0f},
        {0.0f, 0.0f},
        {1.0f, 0.0f},
    };

    _vertexBuffer = [device newBufferWithBytes:positionVertex
                                        length:sizeof(positionVertex)
                 options:MTLResourceStorageModeShared];
    _fragmentBuffer = [device newBufferWithBytes:uvVertex
                                          length:sizeof(uvVertex)
                                                options:MTLResourceStorageModeShared];
}

- (void)SetMTLFunction:(id <MTLDevice>)device
{
    MTLCompileOptions* compileOptions = [MTLCompileOptions new];
    compileOptions.languageVersion = MTLLanguageVersion2_1;

    // シェーダをファイルから読みこみ
    unsigned int size;
    Csm::csmString shaderFilePath(LAppDefine::ShaderPath);
    shaderFilePath += LAppDefine::ShaderName;
    unsigned char* shaderRawString = LAppPal::LoadFileAsBytes(shaderFilePath.GetRawString(), &size);
    if(shaderRawString == NULL)
    {
      return;
    }

    NSString* shader = [NSString stringWithUTF8String:(char *)shaderRawString];

    NSError* compileError;
    id<MTLLibrary> shaderLib = [device newLibraryWithSource:shader options:compileOptions error:&compileError];
    if (!shaderLib)
    {
        NSLog(@" ERROR: Couldnt create a Source shader library");
        // assert here because if the shader libary isn't loading, nothing good will happen
        return;
    }
    //頂点シェーダの取得
    id <MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
    if (!vertexProgram)
    {
        NSLog(@">> ERROR: Couldn't load vertex function from default library");
        return nil;
    }

    //フラグメントシェーダの取得
    id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"fragmentShader"];
    if (!fragmentProgram)
    {
        NSLog(@" ERROR: Couldn't load fragment function from default library");
        return nil;
    }

    [self SetMTLRenderPipelineDescriptor:device vertexProgram:vertexProgram fragmentProgram:fragmentProgram];
    [compileOptions release];
    [shaderLib release];
    [vertexProgram release];
    [fragmentProgram release];
}

- (void)SetMTLRenderPipelineDescriptor:(id <MTLDevice>)device vertexProgram:(id <MTLFunction>)vertexProgram fragmentProgram:(id <MTLFunction>)fragmentProgram
{
    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    //パイプライン・ステート・オブジェクトを作成するパイプライン・ステート・ディスクリプターの作成

    //デバッグ時に便利
    pipelineDescriptor.label                           = @"SpritePipeline";
    // Vertexステージで実行する関数を指定する
    pipelineDescriptor.vertexFunction                  = vertexProgram;
    // Fragmentステージで実行する関数を指定する
    pipelineDescriptor.fragmentFunction                = fragmentProgram;
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDescriptor.colorAttachments[0].blendingEnabled = true;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    [self SetMTLRenderPipelineState:device pipelineDescriptor:pipelineDescriptor];
    [pipelineDescriptor release];
}

- (void)SetMTLRenderPipelineState:(id <MTLDevice>)device pipelineDescriptor:(MTLRenderPipelineDescriptor*)pipelineDescriptor
{
    NSError *error;
    if (_pipelineState == nil)
    {
        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                 error:&error];
    }

    if (!_pipelineState)
    {
        NSLog(@"ERROR: Failed aquiring pipeline state: %@", error);
        return nil;
    }
}

- (void)SetWireframePipeline:(id<MTLDevice>)device
{
    if (_wireframePipeline) return;

    MTLCompileOptions *opt = [MTLCompileOptions new];
    opt.languageVersion = MTLLanguageVersion2_1;

    NSString *src = @R"(
        #include <metal_stdlib>
        using namespace metal;
        struct WireInOut { float4 position [[position]]; };
        vertex WireInOut wireVS(constant float4 *pos [[buffer(0)]], uint vid [[vertex_id]]) {
            WireInOut out; out.position = pos[vid]; return out;
        }
        fragment float4 wireFS(constant float4 &color [[buffer(2)]]) { return color; }
    )";

    NSError *err;
    id<MTLLibrary> lib = [device newLibraryWithSource:src options:opt error:&err];
    id<MTLFunction> vs = [lib newFunctionWithName:@"wireVS"];
    id<MTLFunction> fs = [lib newFunctionWithName:@"wireFS"];

    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction   = vs;
    desc.fragmentFunction = fs;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].rgbBlendOperation   = MTLBlendOperationAdd;
    desc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    desc.colorAttachments[0].sourceRGBBlendFactor  = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor= MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor  = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].destinationAlphaBlendFactor= MTLBlendFactorOneMinusSourceAlpha;

    _wireframePipeline = [device newRenderPipelineStateWithDescriptor:desc error:&err];
}

- (void)renderWireframe:(const float*)vertices
                  count:(int)vertexCount
                      r:(float)r g:(float)g b:(float)b a:(float)a
{
    if (vertexCount < 3 || !vertices) {
        return;
    }

    // 计算包围盒，用于更新 _rect
    float minX = vertices[0], maxX = vertices[0];
    float minY = vertices[1], maxY = vertices[1];
    for (int i = 1; i < vertexCount; ++i) {
        float x = vertices[i * 2];
        float y = vertices[i * 2 + 1];
        minX = fminf(minX, x);
        maxX = fmaxf(maxX, x);
        minY = fminf(minY, y);
        maxY = fmaxf(maxY, y);
    }
    _rect.left   = minX;
    _rect.right  = maxX;
    _rect.down   = minY;
    _rect.up     = maxY;

    CubismRenderingInstanceSingleton_Metal *single =
            [CubismRenderingInstanceSingleton_Metal sharedManager];
    id<MTLDevice> device = [single getMTLDevice];

    // ---------- 顶点 buffer ----------
    vector_float4* pos = new vector_float4[vertexCount + 1]; // +1 用于闭合

    // 使用UIScreen获取屏幕尺寸
//    CGRect screenBounds = [[UIScreen mainScreen] bounds];
//    float screenWidth = screenBounds.size.width;
//    float screenHeight = screenBounds.size.height;

    for (int i = 0; i < vertexCount; ++i) {
        // 直接使用标准化设备坐标
        float x = vertices[i * 2];
        float y = vertices[i * 2 + 1];

        // 将NDC坐标直接转换为Metal坐标系
        // 注意：Metal的Y轴向上，范围也是-1到1
        pos[i] = { x, -y, 0.0f, 1.0f }; // 翻转Y轴
    }

    // 闭合线段：重复第一个顶点，也需要翻转Y轴
    pos[vertexCount] = { vertices[0], -vertices[1], 0.0f, 1.0f };
    _vertexBuffer = [device newBufferWithBytes:pos
                                        length:sizeof(vector_float4) * (vertexCount + 1)
                                       options:MTLResourceStorageModeShared];
    delete[] pos;

    _spriteColorR = r;
    _spriteColorG = g;
    _spriteColorB = b;
    _spriteColorA = a;

    _wireframeVertexCount = vertexCount + 1; // 因为要闭合

    // 即使线框渲染不需要UV，但顶点着色器需要texCoords输入，所以提供占位数据
    vector_float2* uv = new vector_float2[vertexCount + 1];
    for (int i = 0; i <= vertexCount; ++i) {
        uv[i] = { 0.0f, 0.0f }; // UV坐标不影响纯色渲染
    }
    _fragmentBuffer = [device newBufferWithBytes:uv
                                          length:sizeof(vector_float2) * (vertexCount + 1)
                                         options:MTLResourceStorageModeShared];
    delete[] uv;

    // 打印调试信息
    LAppPal::PrintLogLn("[DEBUG] LAppSprite::SetRenderWireframe updated with %d vertices, color=(%.1f,%.1f,%.1f,%.1f)",
            vertexCount, r, g, b, a);
}

@end
