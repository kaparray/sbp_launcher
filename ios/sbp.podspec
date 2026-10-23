#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sbp.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'sbp'
  s.version          = '0.2.0'
  s.summary          = 'Installed SBP bank apps detection and SBP payment links.'
  s.description      = <<-DESC
Flutter plugin: list of SBP bank apps installed on the device and opening SBP payment links (https://qr.nspk.ru/...).
                       DESC
  s.homepage         = 'https://github.com/smenateam/sbp'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'smenateam' => 'https://github.com/smenateam' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
