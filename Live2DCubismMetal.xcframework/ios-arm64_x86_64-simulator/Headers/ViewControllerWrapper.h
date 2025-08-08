#import <UIKit/UIKit.h>

@interface ViewControllerWrapper : UIViewController

- (instancetype)init;
- (void)initializeSprite;
- (void)releaseView;
- (void)resizeScreen;

@end