/**
 * Live2D回调桥接头文件
 * 用于将iOS的点击事件回调到Kotlin层
 */

#import <Foundation/Foundation.h>

// 定义回调函数指针类型
typedef void (*HitAreaCallback)(const char* hitAreaName, const char* modelName, float x, float y);
typedef void (*MotionStartCallback)(const char* motionGroup, int motionIndex, const char* motionFilePath);
typedef void (*ResourceInfoCallback)(const char* modelName, const char* resourceType, const char* resourcePath);
typedef void (*MotionBeganCallback)(void);
typedef void (*MotionFinishedCallback)(void);

@interface Live2DCallbackBridge : NSObject

+ (instancetype)sharedInstance;

// 设置回调函数
- (void)setHitAreaCallback:(HitAreaCallback)callback;
- (void)setMotionStartCallback:(MotionStartCallback)callback;
- (void)setResourceInfoCallback:(ResourceInfoCallback)callback;
- (void)setMotionBeganCallback:(MotionBeganCallback)callback;
- (void)setMotionFinishedCallback:(MotionFinishedCallback)callback;

// 清除回调函数
- (void)clearCallbacks;

// 触发回调
- (void)onHitArea:(const char*)hitAreaName modelName:(const char*)modelName x:(float)x y:(float)y;
- (void)onMotionStart:(const char*)motionGroup motionIndex:(int)motionIndex motionFilePath:(const char*)motionFilePath;
- (void)onResourceInfo:(const char*)modelName resourceType:(const char*)resourceType resourcePath:(const char*)resourcePath;
- (void)onMotionBegan;
- (void)onMotionFinished;

@end