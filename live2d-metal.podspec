Pod::Spec.new do |s|
  s.name             = 'live2d-metal'
  s.version          = '0.1.26'
  s.summary          = 'Live2D Cubism Framework Metal SDK'
  s.description      = 'Live2D Cubism Framework Metal SDK'
  s.homepage         = 'https://github.com/mrljdx/live2d-metal'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Mrljdx' => 'mrljdx@gmail.com' }
  # s.source           = { :path => '.' }
  s.source           = { :git => 'https://github.com/mrljdx/live2d-metal.git', :tag => s.version.to_s }
  s.ios.deployment_target = '12.0'
  s.vendored_frameworks = 'Live2DCubismCore.xcframework', 'Live2DCubismNative.xcframework', 'Live2DCubismMetal.xcframework'
end