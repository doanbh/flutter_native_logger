import 'native_logger_base.dart';

/// Helper class for background FCM handler
class BackgroundLogger {
  /// Log message from background handler - static shorthand
  static Future<void> log(String message) async {
    await NativeLogger.log(
        message,
        tag: 'FCM_BG',
        level: LogLevel.info,
        isBackground: true
    );
  }

  /// Log error from background handler - static shorthand
  static Future<void> error(String message, [dynamic errorObj]) async {
    final errorMsg = errorObj != null ? '$message: $errorObj' : message;
    await NativeLogger.log(
        errorMsg,
        tag: 'FCM_BG',
        level: LogLevel.error,
        isBackground: true
    );
  }
}