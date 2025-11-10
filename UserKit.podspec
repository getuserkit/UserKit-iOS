Pod::Spec.new do |s|
  s.name             = 'UserKit'
  s.version          = '1.1.0'
  s.summary          = 'UserKit: Everything you need to talk to your users'
  s.description      = 'UserKit makes it effortless to have real, face-to-face conversations with your users, right inside your app'
  s.homepage         = 'https://github.com/getuserkit/UserKit-iOS'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Peter Nicholls' => 'pete@getuserkit.com' }
  s.source           = { :git => 'https://github.com/getuserkit/UserKit-iOS.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.10'
  s.source_files = 'Sources/UserKit/**/*.swift'
  s.dependency 'WebRTC-SDK', '=125.6422.07'
end
