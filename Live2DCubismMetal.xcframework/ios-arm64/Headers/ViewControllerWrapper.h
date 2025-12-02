#import <UIKit/UIKit.h>

@interface ViewControllerWrapper : UIViewController

- (instancetype)init;
- (void)releaseView;
- (void)resizeScreen;
- (void)initializeSprite;
- (float)transformViewX:(float)deviceX;
- (float)transformViewY:(float)deviceY;
- (float)transformScreenX:(float)deviceX;
- (float)transformScreenY:(float)deviceY;
- (void)switchToNextModel;
- (void)switchToPreviousModel;
- (void)switchToModel:(int)index;
- (void)setModelScale:(float)scale;
- (void)moveModel:(float)x y:(float)y;
- (BOOL)loadWavFile:(NSString *)filePath;
- (float)getAudioRms;
- (BOOL)updateAudio:(float)deltaTime;
- (void)releaseWavHandler;
- (void)lipSync:(float)mouth;
- (void)updateLipSync;
- (BOOL)hasClickableAreas;
- (void)setShowClickableAreas:(BOOL)show;
- (BOOL)isShowingClickableAreas;
- (BOOL)loadModels:(NSString *)rootPath;
- (BOOL)loadModelPath:(NSString *)dir jsonName:(NSString*)jsonName;
- (BOOL)removeAllModels;
- (int32_t)getLoadedModelNum;
- (void)resetModelPosition;
- (void)onStartMotion:(NSString *)motionGroup
          motionIndex:(int)motionIndex
             priority:(int)priority;

@end