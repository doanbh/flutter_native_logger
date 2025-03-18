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
    s.platform = :ios, '11.0'
    s.swift_version = '5.0'
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  end