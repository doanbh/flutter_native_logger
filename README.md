# Native Logger

A high-performance, cross-platform logging solution for Flutter applications that seamlessly works in both foreground and background contexts.

[![pub package](https://img.shields.io/pub/v/native_logger.svg)](https://pub.dev/packages/native_logger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Features

- ✅ **High-performance** native implementation (Swift for iOS, Kotlin for Android)
- ✅ **Background logging** support for silent notifications, scheduled tasks, and broadcast receivers
- ✅ **Memory buffering** to minimize I/O operations
- ✅ **Customizable log levels** (debug, info, warning, error)
- ✅ **Automatic log rotation** and archiving
- ✅ **Built-in log viewer** with filtering capabilities
- ✅ **Thread-safe** implementation

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  native_logger: ^0.1.0
```

## Setup and Usage Information

### iOS Setup
- Update your ios/Podfile to use a minimum iOS version of 11.0:
- Add the following permission to ios/Runner/Info.plist:
- Initialize Plugin in AppDelegate:
- For early initialization or iOS-specific configuration, update your AppDelegate.swift:

```swift
import UIKit
import Flutter
import native_logger

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Optional early iOS-specific logger initialization
    SwiftNativeLoggerPlugin.prepareLogger()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### Android Setup
- No additional setup required for basic functionality. The library handles necessary permissions automatically.

### Basic Usage
- **Initialization**
- **Logging Messages**
- **Displaying Logs in Your App:**  
  Add a log viewer to your app's debug menu or settings screen.
- **Background Logging:**  
  Native Logger is designed to work seamlessly in background contexts:
  - FCM Background Messages
  - WorkManager Tasks (Android)
  - Background Fetch (iOS)

#### Initialization

```dart
import 'package:native_logger/native_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the logger
  final logger = NativeLogger();
  await logger.initialize();
  
  runApp(MyApp());
}
```

#### Logging Messages
```dart
// Simple logging
await NativeLogger.log('User signed in');

// With tag and level
await NativeLogger.log(
  'Payment processed',
  tag: 'PAYMENT',
  level: LogLevel.info,
);

// Error logging
try {
  // Some operation
} catch (e, stackTrace) {
  await NativeLogger.log(
    'Error: $e\n$stackTrace',
    level: LogLevel.error,
    tag: 'API',
  );
}
```

#### Displaying Logs in Your App
Add a log viewer to your app's debug menu or settings screen:
```dart
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogViewer(
          themeColor: Colors.blue,
          title: 'Application Logs',
        ),
      ),
    );
  },
  child: const Text('View Logs'),
)
```

#### Background Logging
Native Logger is designed to work seamlessly in background contexts:
```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize logger for background context if needed
  final logger = NativeLogger();
  await logger.initialize();
  
  // Log the event
  await BackgroundLogger.log(
    'Received background message: ${message.messageId}',
    tag: 'FCM',
  );
  
  // Process the message...
}
```

### API Reference

#### NativeLogger Class
| Method | Description |
| --- | --- |
| initialize() | Initializes the logger. Must be called before using other methods. |
| log(String message, {String tag, LogLevel level}) | Logs a message with optional tag and level. |
| getLogEntries({String? search}) | Retrieves log entries, optionally filtered by search term. |
| clearLogs() | Clears all logs from storage. |

#### BackgroundLogger Class
Static utility for background contexts.
| Method | Description |
| --- | --- |
| log(String message, {String tag, LogLevel level}) | Logs from background contexts. |

#### LogLevel Enum
| Level | Description |
| --- | --- |
| debug | Detailed information for debugging. |
| info | General information about application flow. |
| warning | Potential issues that aren't critical. |
| error | Error conditions. |

#### LogViewer Widget
A pre-built UI component to display and filter logs.
- **Parameters:**
  - title: The title of the log viewer screen.
  - themeColor: Primary color for the viewer UI.

### Troubleshooting
- **Logs Not Persisting in Background:**  
  Ensure initialize() is called before logging. For iOS, ensure background tasks have sufficient execution time. Consider using BackgroundLogger class which optimizes for background contexts.
- **iOS Specific Issues:**  
  Verify podspec file is correctly configured. Check Info.plist contains the necessary permissions. Ensure logs directory is within app's sandbox restrictions.

### Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

### License
This project is licensed under the MIT License - see the LICENSE file for details.
