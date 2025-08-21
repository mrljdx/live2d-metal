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

// 新增：常驻共享 buffer（一次性创建，永不释放）
@property (nonatomic) id <MTLBuffer> sharedPosBuffer;   // 4 顶点 * vector_float4
@property (nonatomic) id <MTLBuffer> sharedUvBuffer;    // 4 顶点 * vector_float2

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

        CubismRenderingInstanceSingleton_Metal *single = [CubismRenderingInstanceSingleton_Metal sharedManager];
        id <MTLDevice> device = [single getMTLDevice];

        [self SetSharedBuffersOnce:device];

        [self SetMTLBuffer:device MaxWidth:maxWidth MaxHeight:maxHeight];

        [self SetMTLFunction:device];
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

    [super dealloc];
}

- (void)renderImmidiate:(id<MTLRenderCommandEncoder>)renderEncoder
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
        NSLog(@"[DEBUG]: LAppSprite _pipelineState is NULL");
        return;
    }
    // パイプライン状態オブジェクトを設定する
    [renderEncoder setRenderPipelineState:_pipelineState];

    vector_float2 metalUniforms = (vector_float2){width,height};
    [renderEncoder setVertexBytes:&metalUniforms length:sizeof(vector_float2) atIndex:2];

    BaseColor uniform;
    uniform.baseColor = (vector_float4){ _spriteColorR, _spriteColorG, _spriteColorB, _spriteColorA };
    [renderEncoder setFragmentBytes:&uniform length:sizeof(BaseColor) atIndex:2];
    if (_texture) {
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
//        NSLog(@"[DEBUG]: LAppSprite drawPrimitives with _texture");
    } else {
//        [renderEncoder drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:_wireframeVertexCount];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:_wireframeVertexCount];
//        NSLog(@"[DEBUG]: LAppSprite drawPrimitives with vertexCount: %d", _wireframeVertexCount);
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

    // 统一指向共享 buffer
    _vertexBuffer   = _sharedPosBuffer;
    _fragmentBuffer = _sharedUvBuffer;
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
    // DEBUG 调试时开启
    if (!shader)
    {
        NSLog(@" ERROR: shader should not be nil, path=%s, rawString=%s", shaderFilePath.GetRawString(), shaderRawString);
        return;
    }
    // NSAssert(shader, @"shader is nil!");
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

    id <MTLFunction> wireVertexProgram = [shaderLib newFunctionWithName:@"wireVertexShader"];
    if (!wireVertexProgram)
    {
        NSLog(@">> ERROR: Couldn't load wireVertex function from default library");
        return nil;
    }

    id <MTLFunction> wireFragmentProgram = [shaderLib newFunctionWithName:@"wireFragmentShader"];
    if (!wireFragmentProgram)
    {
        NSLog(@" ERROR: Couldn't load wireFragment function from default library");
        return nil;
    }

    if (!_texture) {
        [self SetMTLRenderPipelineDescriptor:device vertexProgram:wireVertexProgram fragmentProgram:wireFragmentProgram];
    } else {
        [self SetMTLRenderPipelineDescriptor:device vertexProgram:vertexProgram fragmentProgram:fragmentProgram];
    }

    [compileOptions release];
    [shaderLib release];
    [vertexProgram release];
    [fragmentProgram release];
    [wireVertexProgram release];
    [wireFragmentProgram release];
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


- (void)SetSharedBuffersOnce:(id<MTLDevice>)device
{
    // 4 个顶点足够普通 Quad / Wireframe 使用
    const NSUInteger kMaxVerts = 24;
    _sharedPosBuffer = [device newBufferWithLength:kMaxVerts * sizeof(vector_float4)
                                           options:MTLResourceStorageModeShared];
    _sharedUvBuffer  = [device newBufferWithLength:kMaxVerts * sizeof(vector_float2)
                                           options:MTLResourceStorageModeShared];
}


- (void)renderWireframe:(const float*)vertices
                  count:(int)vertexCount
                      r:(float)r g:(float)g b:(float)b a:(float)a
              lineWidth:(float)lineWidth
{
    if (vertexCount < 3 || vertexCount >=24 || !vertices) {
        return;
    }

    // 四边形顶点缓冲（最多 64 顶点）
    static vector_float4 quadVtx[64];
    static vector_float2 quadUV [64];

    const int quadCnt = vertexCount * 4;   // 关键：4 条边 * 4 顶点

    // 1. 把每条线段扩展为 2 个三角形（4 顶点）
    float hw = lineWidth * 0.5f;
    // 画所有线段 + 闭合边
    for (int i = 0; i < vertexCount; ++i) {
        int j = (i + 1) % vertexCount;               // 闭合
        vector_float2 a = { vertices[i*2], vertices[i*2+1] };
        vector_float2 b = { vertices[j*2], vertices[j*2+1] };

        vector_float2 dir = b - a;
        vector_float2 n   = vector_normalize((vector_float2){ -dir.y, dir.x }) * hw;

        quadVtx[i*4+0] = { a.x-n.x, a.y-n.y, 0, 1 };
        quadVtx[i*4+1] = { a.x+n.x, a.y+n.y, 0, 1 };
        quadVtx[i*4+2] = { b.x-n.x, b.y-n.y, 0, 1 };
        quadVtx[i*4+3] = { b.x+n.x, b.y+n.y, 0, 1 };
    }

    // 2. 一次性写入共享 buffer
    vector_float4 *vDst = (vector_float4 *)[_sharedPosBuffer contents];
    vector_float2 *uDst = (vector_float2 *)[_sharedUvBuffer contents];
    memcpy(vDst, quadVtx, quadCnt * sizeof(vector_float4));
    memcpy(uDst, quadUV,  quadCnt * sizeof(vector_float2));

    // 3. 绑定并绘制
    _vertexBuffer  = _sharedPosBuffer;
    _fragmentBuffer= _sharedUvBuffer;
    _wireframeVertexCount = quadCnt;

    // 4. 设置颜色
    [self SetColor:r g:g b:b a:a];
}

@end
