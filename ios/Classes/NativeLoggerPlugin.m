#import "NativeLoggerPlugin.h"
#if __has_include(<native_logger/native_logger-Swift.h>)
#import <native_logger/native_logger-Swift.h>
#else
#import "native_logger-Swift.h"
#endif

@implementation NativeLoggerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftNativeLoggerPlugin registerWithRegistrar:registrar];
}

+ (void)prepareLogger {
  // Check if SwiftNativeLoggerPlugin responds to prepareLogger
  if ([SwiftNativeLoggerPlugin respondsToSelector:@selector(prepareLogger)]) {
    [SwiftNativeLoggerPlugin prepareLogger];
  } else {
    NSLog(@"Warning: SwiftNativeLoggerPlugin does not respond to prepareLogger");
  }
}
@end 