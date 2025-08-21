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
- (void)updateLipSync:(float)mouth;
- (void)updateLipSync;
- (BOOL)hasClickableAreas;
- (void)setShowClickableAreas:(BOOL)show;
- (BOOL)isShowingClickableAreas;

@end