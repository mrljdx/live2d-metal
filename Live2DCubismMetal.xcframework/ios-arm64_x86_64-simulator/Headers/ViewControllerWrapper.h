#import <UIKit/UIKit.h>

@interface ViewControllerWrapper : UIViewController

- (instancetype)init;
- (void)initializeSprite;
- (void)releaseView;
- (void)resizeScreen;
- (float)transformViewX:(float)deviceX;
- (float)transformViewY:(float)deviceY;

@end