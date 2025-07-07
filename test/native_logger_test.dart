import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:native_logger/native_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeLogger Tests', () {
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      // Mock the method channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sharitek.native_logger/methods'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          switch (methodCall.method) {
            case 'initializeLogger':
              return true;
            case 'logMessage':
              return true;
            case 'readLogs':
              return 'Test log content';
            case 'clearLogs':
              return true;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sharitek.native_logger/methods'),
        null,
      );
    });

    test('should initialize logger without blocking', () async {
      final logger = NativeLogger();
      final result = await logger.initialize();

      expect(result, isTrue);
      expect(methodCalls.length, greaterThanOrEqualTo(1));
      expect(methodCalls.first.method, equals('initializeLogger'));
    });

    test('should log message with timeout', () async {
      await NativeLogger.log('Test message');

      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('logMessage'));
      expect(methodCalls.first.arguments['message'], equals('Test message'));
    });

    test('should handle background logging', () async {
      await BackgroundLogger.log('Background test');

      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('logMessage'));
      expect(methodCalls.first.arguments['isBackground'], isTrue);
      expect(methodCalls.first.arguments['tag'], equals('FCM_BG'));
    });

    test('should read logs', () async {
      final logs = await NativeLogger.readLogs();

      expect(logs, equals('Test log content'));
      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('readLogs'));
    });

    test('should clear logs', () async {
      final result = await NativeLogger.clearLogs();

      expect(result, isTrue);
      expect(methodCalls.length, equals(1));
      expect(methodCalls.first.method, equals('clearLogs'));
    });
  });
}
