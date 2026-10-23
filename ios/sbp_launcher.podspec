#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sbp_launcher.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'sbp_launcher'
  s.version          = '1.0.1'
  s.summary          = 'Detects installed SBP bank apps and opens qr.nspk.ru payment links.'
  s.description      = <<-DESC
Flutter plugin for SBP payments: detects installed bank apps by their SBP scheme, loads the NSPK bank registry and opens qr.nspk.ru links.
                       DESC
  s.homepage         = 'https://github.com/kaparray/sbp_launcher'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'kaparray' => 'https://github.com/kaparray' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
