/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#ifndef LAppLive2DManager_h
#define LAppLive2DManager_h

#import <CubismFramework.hpp>
#import <Math/CubismMatrix44.hpp>
#import <Type/csmVector.hpp>
#import <Type/csmString.hpp>
#import "LAppModel.h"
#import "LAppModelSprite.h"

@interface LAppLive2DManager : NSObject

typedef NS_ENUM(NSUInteger, SelectTarget)
{
    SelectTarget_None,                ///< デフォルトのフレームバッファにレンダリング
    SelectTarget_ModelFrameBuffer,    ///< LAppModelが各自持つフレームバッファにレンダリング
    SelectTarget_ViewFrameBuffer,     ///< LAppViewの持つフレームバッファにレンダリング
};

@property (nonatomic) Csm::CubismMatrix44 *viewMatrix; //モデル描画に用いるView行列
@property (nonatomic) Csm::csmVector<LAppModel*> models; //モデルインスタンスのコンテナ
@property (nonatomic) Csm::csmInt32 sceneIndex; //表示するシーンのインデックス値
@property (nonatomic) SelectTarget renderTarget;
@property (nonatomic) Csm::Rendering::CubismOffscreenSurface_Metal* renderBuffer;
@property (nonatomic) LAppSprite* sprite;
@property (nonatomic) LAppModelSprite* modelSprite;
@property (nonatomic) MTLRenderPassDescriptor* renderPassDescriptor;
@property (nonatomic) float clearColorR;
@property (nonatomic) float clearColorG;
@property (nonatomic) float clearColorB;

@property (nonatomic) Csm::csmVector<Csm::csmString> modelDir; ///< モデルディレクトリ名のコンテナ
@property (nonatomic) BOOL showClickableAreas; ///< 是否显示可点击区域
@property (nonatomic, strong) NSMutableDictionary<NSString *, LAppSprite *> *wireSprites; // 专门画线框

/**
 * @brief クラスのインスタンスを返す。
 *        インスタンスが生成されていない場合は内部でインスタンスを生成する。
 */
+ (LAppLive2DManager*)getInstance;

/**
 * @brief クラスのインスタンスを解放する。
 */
+ (void)releaseInstance;

/**
 * @brief 現在のシーンで保持しているモデルを返す。
 *
 * @param[in] no モデルリストのインデックス値
 * @return モデルのインスタンスを返す。インデックス値が範囲外の場合はNULLを返す。
 */
- (LAppModel*)getModel:(Csm::csmUint32)no;

/**
 * @brief 現在のシーンで保持している全てのモデルを解放する
 */
- (void)releaseAllModel;

/**
 * @brief Resources フォルダにあるモデルフォルダ名をセットする
 */
- (void)setUpModel;

/**
 * @brief   画面をドラッグしたときの処理
 *
 * @param[in]   x   画面のX座標
 * @param[in]   y   画面のY座標
 */
- (void)onDrag:(Csm::csmFloat32)x floatY:(Csm::csmFloat32)y;

/**
 * @brief   画面をタップしたときの処理
 *
 * @param[in]   x   画面のX座標
 * @param[in]   y   画面のY座標
 */
- (void)onTap:(Csm::csmFloat32)x floatY:(Csm::csmFloat32)y;

/**
 * @brief   画面を更新するときの処理
 *          モデルの更新処理および描画処理を行う
 */
- (void)onUpdate:(id <MTLCommandBuffer>)commandBuffer currentDrawable:(id<CAMetalDrawable>)drawable depthTexture:(id<MTLTexture>)depthTarget;

/**
 * @brief   次のシーンに切り替える
 *          サンプルアプリケーションではモデルセットの切り替えを行う。
 */
- (void)nextScene;

/**
 * @brief   シーンを切り替える
 *           サンプルアプリケーションではモデルセットの切り替えを行う。
 */
- (void)changeScene:(Csm::csmInt32)index;

/**
 * @brief   モデル個数を得る
 * @return  所持モデル個数
 */
- (Csm::csmUint32)GetModelNum;

/**
 * @brief   viewMatrixをセットする
 */
- (void)SetViewMatrix:(Csm::CubismMatrix44*)m;

/**
 * @brief レンダリング先を切り替える
 */
- (void)SwitchRenderingTarget:(SelectTarget) targetType;

/**
 * @brief レンダリング先をデフォルト以外に切り替えた際の背景クリア色設定
 * @param[in]   r   赤(0.0~1.0)
 * @param[in]   g   緑(0.0~1.0)
 * @param[in]   b   青(0.0~1.0)
 */
- (void)SetRenderTargetClearColor:(float)r g:(float)g b:(float)b;

/**
 * @brief 设置指定模型的缩放
 * @param scale 目标缩放值（1.0 为原始大小）
 */
- (void)setModelScale:(float)scale;

/**
 * @brief 设置指定模型的缩放
 * @param x 目标位置值（0.0 为原始位置）
 * @param y 目标位置值（0.0 为原始位置）
 */
- (void)moveModel:(float)x y:(float)y;

/**
 * @brief 同步音频播放的口型
 * @param mouth 口型值
 */
- (void)updateLipSync:(float)mouth;

/**
 * @brief 检查是否有可点击区域
 * @return 如果有可点击区域返回YES，否则返回NO
 */
- (BOOL)hasClickableAreas;

/**
 * @brief 设置是否显示可点击区域
 * @param show 是否显示
 */
- (void)setShowClickableAreas:(BOOL)show;

/**
 * @brief 检查是否正在显示可点击区域
 * @return 如果正在显示返回YES，否则返回NO
 */
- (BOOL)isShowingClickableAreas;

/**
 * 绘制可点击区域
 * @param model
 */
- (void) drawClickableAreas:(LAppModel*)model;

@end

#endif /* LAppLive2DManager_h */
