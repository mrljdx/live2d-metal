#import <UIKit/UIKit.h>

@interface ViewControllerWrapper : UIViewController

- (instancetype)init;
- (void)initializeSprite;
- (void)releaseView;
- (void)resizeScreen;
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