/**
 * Live2D回调桥接实现文件
 * 用于将iOS的点击事件回调到Kotlin层
 */

#import "Live2DCallbackBridge.h"

@implementation Live2DCallbackBridge {
    HitAreaCallback _hitAreaCallback;
    MotionStartCallback _motionStartCallback;
    ResourceInfoCallback _resourceInfoCallback;
}

+ (instancetype)sharedInstance {
    static Live2DCallbackBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hitAreaCallback = nullptr;
        _motionStartCallback = nullptr;
        _resourceInfoCallback = nullptr;
    }
    return self;
}

- (void)setHitAreaCallback:(HitAreaCallback)callback {
    _hitAreaCallback = callback;
}

- (void)setMotionStartCallback:(MotionStartCallback)callback {
    _motionStartCallback = callback;
}

- (void)setResourceInfoCallback:(ResourceInfoCallback)callback {
    _resourceInfoCallback = callback;
}

- (void)clearCallbacks {
    _hitAreaCallback = nullptr;
    _motionStartCallback = nullptr;
    _resourceInfoCallback = nullptr;
}

- (void)onHitArea:(const char*)hitAreaName modelName:(const char*)modelName x:(float)x y:(float)y {
    if (_hitAreaCallback) {
        _hitAreaCallback(hitAreaName, modelName, x, y);
    }
}

- (void)onMotionStart:(const char*)motionGroup motionIndex:(int)motionIndex motionFilePath:(const char*)motionFilePath {
    if (_motionStartCallback) {
        _motionStartCallback(motionGroup, motionIndex, motionFilePath);
    }
}

- (void)onResourceInfo:(const char*)modelName resourceType:(const char*)resourceType resourcePath:(const char*)resourcePath {
    if (_resourceInfoCallback) {
        _resourceInfoCallback(modelName, resourceType, resourcePath);
    }
}

@end