/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import <UIKit/UIKit.h>
#import "LAppModel.h"
#import "MetalView.h"

@interface ViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) bool anotherTarget;
@property (nonatomic) float spriteColorR;
@property (nonatomic) float spriteColorG;
@property (nonatomic) float spriteColorB;
@property (nonatomic) float spriteColorA;
@property (nonatomic) float clearColorR;
@property (nonatomic) float clearColorG;
@property (nonatomic) float clearColorB;
@property (nonatomic) float clearColorA;
@property (nonatomic) id<MTLCommandQueue> commandQueue;
@property (nonatomic) id<MTLTexture> depthTexture;

/**
 * @brief 解放処理
 */
- (void)dealloc;

/**
 * @brief 解放する。
 */
- (void)releaseView;

/**
 * @brief 画面リサイズ処理
 */
- (void)resizeScreen;

/**
 * @brief 画像の初期化を行う。
 */
- (void)initializeSprite;

/**
 * @brief X座標をView座標に変換する。
 *
 * @param[in]       deviceX            デバイスX座標
 */
- (float)transformViewX:(float)deviceX;

/**
 * @brief Y座標をView座標に変換する。
 *
 * @param[in]       deviceY            デバイスY座標
 */
- (float)transformViewY:(float)deviceY;

/**
 * @brief X座標をScreen座標に変換する。
 *
 * @param[in]       deviceX            デバイスX座標
 */
- (float)transformScreenX:(float)deviceX;

/**
 * @brief Y座標をScreen座標に変換する。
 *
 * @param[in]       deviceY            デバイスY座標
 */
- (float)transformScreenY:(float)deviceY;

/**
 * @brief Switch to the next model
 */
- (void)switchToNextModel;

/**
 * @brief Switch to the previous model
 */
- (void)switchToPreviousModel;

/**
 * @brief Switch to a specific model by index
 *
 * @param[in] index The model index to switch to
 */
- (void)switchToModel:(int)index;

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
 * @brief 加载wav文件
 * @param filePath
 */
- (BOOL)loadWavFile:(NSString *)filePath;

- (float)getAudioRms;

- (BOOL)updateAudio:(float)deltaTime;

- (void)releaseWavHandler;

/**
 * @brief 同步音频播放的口型
 * @param mouth 口型值
 */
- (void)lipSync:(float)mouth;

- (BOOL)hasClickableAreas;
- (void)setShowClickableAreas:(BOOL)show;
- (BOOL)isShowingClickableAreas;

/**
 * @brief 绘制可点击区域的线框
 * @param vertices 顶点数组
 * @param vertexCount 顶点数量
 * @param r 红色分量
 * @param g 绿色分量
 * @param b 蓝色分量
 * @param areaName 区域名称
 */
- (void)drawClickableAreaWireframe:(const float*)vertices 
                       vertexCount:(int)vertexCount
                       r:(float)r g:(float)g b:(float)b
                       areaName:(NSString*)areaName;

/**
 * @brief 加载模型
 * @param rootPath
 */
- (BOOL)loadModels:(NSString *)rootPath;

/**
 * @brief 加载指定目录下的模型
 * @param dir
 */
- (BOOL)loadModelPath:(NSString *)dir
             jsonName:(NSString*)jsonName;

/**
 * @brief 移除所有的模型
 */
- (BOOL)removeAllModels;

/**
 * @brief 获取当前已经加载的模型数量
 */
- (int32_t)getLoadedModelNum;

- (void)resetModelPosition;

- (void)onStartMotion:(NSString *)motionGroup
          motionIndex:(int)motionIndex
             priority:(int)priority;

/**
 * @brief 获取模型的X坐标位置
 * @return 模型的X坐标值
 */
- (float)modelPositionX;

/**
 * @brief 获取模型的Y坐标位置
 * @return 模型的Y坐标值
 */
- (float)modelPositionY;

/**
 * @brief 设置模型的绝对位置
 * @param x X坐标值
 * @param y Y坐标值
 */
- (void)setModelPosition:(float)x y:(float)y;

/**
 * @brief 获取模型的缩放值
 * @return 模型的缩放值
 */
- (float)modelScale;

/**
 * @brief 播放指定的 Expression（表情）
 * @param expressionID Expression 的 ID 或名称（如 "angry", "happy", "sad" 等）
 */
- (void)setExpression:(NSString*)expressionID;

@end
