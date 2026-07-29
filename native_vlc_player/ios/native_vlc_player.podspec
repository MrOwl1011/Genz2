#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint native_vlc_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'native_vlc_player'
  s.version          = '0.0.1'
  s.summary          = 'Local native MobileVLCKit platform view for iOS.'
  s.description      = <<-DESC
Native iOS platform view wrapping MobileVLCKit's VLCMediaPlayer directly, used only by this app's own PlayerBackend abstraction.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'App' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MobileVLCKit'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
