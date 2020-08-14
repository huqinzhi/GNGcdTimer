Pod::Spec.new do |spec|
  spec.name         = "GNGcdTimer"
  spec.version      = "1.0.2"
  spec.summary      = "A short description of GNGcdTimer SDK for iOS."
  spec.description  = <<-DESC
            QZ SDK for developer
                   DESC
  spec.homepage     = "https://github.com/huqinzhi/GNGcdTimer"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "hqz" => "576188937@qq.com" }
  spec.source       = { :git => "https://github.com/huqinzhi/GNGcdTimer.git", :tag => spec.version }
  spec.platform     = :ios, '8.0'
  spec.ios.deployment_target = '8.0'
  spec.requires_arc = true
  spec.frameworks = 'SystemConfiguration','Foundation','UIKit'
  
  spec.user_target_xcconfig =   {'OTHER_LDFLAGS' => ['-lObjC']}
  spec.libraries = 'c++', 'z'
  spec.default_subspecs = 'GNGcdTimer'

  spec.subspec 'GNGcdTimer' do |ss|
     ss.ios.deployment_target = '8.0'
     ss.source_files = 'GN*.h','GN*.m'
  end

end
