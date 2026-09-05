#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint advanced_haptics.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'advanced_haptics'
  s.version          = '1.0.10'
  s.summary          = 'Custom haptic feedback for Flutter: waveforms, Core Haptics and .ahap files.'
  s.description      = <<-DESC
A Flutter plugin for playing advanced, custom haptic feedback patterns on Android and iOS,
including waveforms and Core Haptics .ahap files.
                       DESC
  s.homepage         = 'https://github.com/miracle101000/advanced_haptics'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'miracle101000' => 'okolomiracle101000@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'advanced_haptics/Sources/advanced_haptics/**/*'
  s.resource_bundles = {'advanced_haptics_privacy' => ['advanced_haptics/Sources/advanced_haptics/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.frameworks = 'CoreHaptics', 'UIKit'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
