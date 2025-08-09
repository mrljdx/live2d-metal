#import <UIKit/UIKit.h>

@interface ViewControllerWrapper : UIViewController

- (instancetype)init;
- (void)initializeSprite;
- (void)releaseView;
- (void)resizeScreen;
- (void)switchToNextModel;
- (void)switchToPreviousModel;
- (void)switchToModel:(int)index;

@end