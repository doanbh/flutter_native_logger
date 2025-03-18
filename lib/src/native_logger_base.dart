import 'dart:async';
import 'package:flutter/services.dart';

enum LogLevel { verbose, debug, info, warning, error, critical }

/// High-performance native logger for Flutter
class NativeLogger {
  // Singleton pattern
  static final NativeLogger _instance = NativeLogger._internal();
  factory NativeLogger() => _instance;
  NativeLogger._internal();

  // Method channel for native communication
  static const MethodChannel _channel = MethodChannel('com.sharitek.native_logger/methods');

  // Event channel for real-time log streaming
  static const EventChannel _eventChannel = EventChannel('com.sharitek.native_logger/events');

  // Stream controller for exposed stream
  final StreamController<String> _logStreamController = StreamController<String>.broadcast();

  /// Initialize the logger
  Future<bool> initialize() async {
    try {
      await _channel.invokeMethod('initializeLogger');

      // Listen for log events from native platforms
      _eventChannel.receiveBroadcastStream().listen(
              (dynamic event) {
            if (event is String) {
              _logStreamController.add(event);
            }
          },
          onError: (dynamic error) {
            print('Native logger stream error: $error');
          }
      );

      return true;
    } catch (e) {
      print('Failed to initialize native logger: $e');
      return false;
    }
  }

  /// Log a message - optimized for background operations
  static Future<void> log(
      String message, {
        LogLevel level = LogLevel.info,
        String tag = 'Flutter',
        bool isBackground = false
      }) async {
    try {
      await _channel.invokeMethod('logMessage', {
        'message': message,
        'level': level.toString().split('.').last.toUpperCase(),
        'tag': tag,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isBackground': isBackground
      });
    } catch (e) {
      // Silent failure - can't log errors from logger
      print('Failed to log: $e');
    }
  }

  /// Read all logs from native storage
  static Future<String> readLogs() async {
    try {
      final String logs = await _channel.invokeMethod('readLogs');
      return logs;
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  /// Clear all logs
  static Future<bool> clearLogs() async {
    try {
      final bool result = await _channel.invokeMethod('clearLogs');
      return result;
    } catch (e) {
      print('Error clearing logs: $e');
      return false;
    }
  }

  /// Get log file path
  static Future<String?> getLogFilePath() async {
    try {
      final String? path = await _channel.invokeMethod('getLogFilePath');
      return path;
    } catch (e) {
      print('Error getting log file path: $e');
      return null;
    }
  }

  /// Share log file
  static Future<bool> shareLogFile() async {
    try {
      final bool result = await _channel.invokeMethod('shareLogFile');
      return result;
    } catch (e) {
      print('Error sharing log file: $e');
      return false;
    }
  }

  /// Stream of real-time log events
  Stream<String> get logStream => _logStreamController.stream;

  /// Close the logger when no longer needed
  void dispose() {
    _logStreamController.close();
  }
}