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

  // Initialization state
  bool _isInitialized = false;
  bool _isInitializing = false;

  // Performance monitoring
  static int _logCount = 0;
  static int _timeoutCount = 0;
  static int _errorCount = 0;

  /// Initialize the logger with timeout and non-blocking approach
  Future<bool> initialize() async {
    // Prevent multiple initialization attempts
    if (_isInitialized) return true;
    if (_isInitializing) {
      // Wait for ongoing initialization
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _isInitialized;
    }

    _isInitializing = true;

    try {
      // Add timeout to prevent indefinite blocking
      await _channel.invokeMethod('initializeLogger').timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print('Logger initialization timeout - continuing anyway');
          return true; // Continue even if timeout
        },
      );

      // Delay event channel setup to avoid blocking initialization
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          // Listen for log events from native platforms
          _eventChannel.receiveBroadcastStream().listen(
                  (dynamic event) {
                if (event is String) {
                  _logStreamController.add(event);
                }
              },
              onError: (dynamic error) {
                print('Native logger stream error: $error');
                // Don't crash - just log the error
              }
          );
        } catch (e) {
          print('Failed to setup event channel: $e');
          // Continue without event streaming
        }
      });

      _isInitialized = true;
      return true;
    } catch (e) {
      print('Failed to initialize native logger: $e');
      // Return true to allow app to continue even if logger fails
      _isInitialized = true; // Mark as initialized to prevent retries
      return true;
    } finally {
      _isInitializing = false;
    }
  }

  /// Log a message - optimized for background operations with timeout
  static Future<void> log(
      String message, {
        LogLevel level = LogLevel.info,
        String tag = 'Flutter',
        bool isBackground = false
      }) async {
    try {
      // Auto-initialize if not already done (lazy initialization)
      final instance = NativeLogger();
      if (!instance._isInitialized && !instance._isInitializing) {
        // Fire and forget initialization - don't wait for it
        instance.initialize();
      }

      // Add timeout to prevent blocking
      await _channel.invokeMethod('logMessage', {
        'message': message,
        'level': level.toString().split('.').last.toUpperCase(),
        'tag': tag,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isBackground': isBackground
      }).timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          // Silent timeout - don't block app execution
          _timeoutCount++;
          print('Log timeout for: $message (Total timeouts: $_timeoutCount)');
          return null;
        },
      );

      _logCount++;
    } catch (e) {
      // Silent failure - can't log errors from logger
      _errorCount++;
      print('Failed to log: $e (Total errors: $_errorCount)');
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

  /// Get performance statistics
  static Map<String, int> getPerformanceStats() {
    return {
      'totalLogs': _logCount,
      'timeouts': _timeoutCount,
      'errors': _errorCount,
      'successRate': _logCount > 0 ? ((_logCount - _errorCount - _timeoutCount) * 100 / _logCount).round() : 100,
    };
  }

  /// Reset performance counters
  static void resetPerformanceStats() {
    _logCount = 0;
    _timeoutCount = 0;
    _errorCount = 0;
  }

  /// Close the logger when no longer needed
  void dispose() {
    _logStreamController.close();
  }
}