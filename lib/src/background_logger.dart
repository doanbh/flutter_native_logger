import 'native_logger_base.dart';

/// Helper class for background FCM handler
class BackgroundLogger {
  /// Log message from background handler - static shorthand with timeout
  static Future<void> log(String message) async {
    try {
      await NativeLogger.log(
          message,
          tag: 'FCM_BG',
          level: LogLevel.info,
          isBackground: true
      ).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          // Silent timeout for background operations
          print('Background log timeout: $message');
        },
      );
    } catch (e) {
      // Never crash background handlers due to logging
      print('Background log error: $e');
    }
  }

  /// Log error from background handler - static shorthand with timeout
  static Future<void> error(String message, [dynamic errorObj]) async {
    try {
      final errorMsg = errorObj != null ? '$message: $errorObj' : message;
      await NativeLogger.log(
          errorMsg,
          tag: 'FCM_BG',
          level: LogLevel.error,
          isBackground: true
      ).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          // Silent timeout for background operations
          print('Background error log timeout: $errorMsg');
        },
      );
    } catch (e) {
      // Never crash background handlers due to logging
      print('Background error log error: $e');
    }
  }
}