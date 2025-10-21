/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#import <UIKit/UIKit.h>

@class ViewController;
@class LAppView;
@class LAppTextureManager;

/// Live2D Cubism framework ObjC wrapper.
@interface L2DCubism: NSObject

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) ViewController *viewController;
@property (nonatomic, readonly, getter=getTextureManager) LAppTextureManager *textureManager; // テクスチャマネージャー

/// Get shared instance
+ (instancetype)sharedInstance;

/// Init cubism framework.
- (void)initCubism;

- (bool)getIsEnd;

/// Dispose cubism framework.
- (void)disposeCubism;

/// Load Models
- (bool)loadModels:(NSString *)rootPath;

/// Load Model Path
- (bool)loadModelPath:(NSString *)dir
             jsonName:(NSString *)jsonName;

@end
