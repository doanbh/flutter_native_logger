Pod::Spec.new do |s|
    s.name             = 'native_logger'
    s.version          = '0.1.0'
    s.summary          = 'Native logging implementation for Flutter'
    s.description      = 'A Flutter plugin that provides native logging capabilities on iOS and Android'
    s.homepage         = 'https://github.com/yourusername/native_logger'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'Your Name' => 'your.email@example.com' }
    s.source           = { :path => '.' }
    s.source_files = 'Classes/**/*'
    s.dependency 'Flutter'
    s.platform = :ios, '14.0'
    s.swift_version = '5.0'
    s.pod_target_xcconfig = { 
      'DEFINES_MODULE' => 'YES', 
      'IPHONEOS_DEPLOYMENT_TARGET' => '14.0',
      'SWIFT_OBJC_INTERFACE_HEADER_NAME' => 'native_logger-Swift.h',
      'MODULEMAP_FILE' => '${PODS_TARGET_SRCROOT}/Classes/native_logger.modulemap'
    }
    s.user_target_xcconfig = { 'IPHONEOS_DEPLOYMENT_TARGET' => '14.0' }
    s.public_header_files = 'Classes/**/*.h'
    s.preserve_paths = ['Classes/**/*.swift', 'Classes/native_logger.modulemap']
  end