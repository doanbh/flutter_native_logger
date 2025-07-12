import Flutter
import UIKit

@objc(SwiftNativeLoggerPlugin)
public class SwiftNativeLoggerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.sharitek.native_logger/methods", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "com.sharitek.native_logger/events", binaryMessenger: registrar.messenger())
        
        let instance = SwiftNativeLoggerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    @objc public static func prepareLogger() {
        // Initialize the logger for usage in other native code (non-blocking)
        DispatchQueue.global(qos: .background).async {
            NativeLogger.log(message: "=== Native Logger prepared for use outside Flutter ===")
            // Register for application lifecycle events
            NativeLogger.registerApplicationLifecycleEvents()
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializeLogger":
            // Respond immediately to avoid blocking Flutter
            result(true)
            // Log initialization in background
            DispatchQueue.global(qos: .background).async {
                NativeLogger.log(message: "=== Native Logger initialized from Flutter ===")
            }
            
        case "logMessage":
            // Validate arguments first
            guard let args = call.arguments as? [String: Any],
                  let message = args["message"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing message", details: nil))
                return
            }

            // Respond immediately to avoid blocking Flutter
            result(true)

            // Process logging in background
            DispatchQueue.global(qos: .background).async {
                let level = args["level"] as? String ?? "INFO"
                let tag = args["tag"] as? String ?? "Flutter"
                let isBackground = args["isBackground"] as? Bool ?? false

                NativeLogger.log(
                    message: message,
                    level: level,
                    tag: tag,
                    isBackground: isBackground
                )
            }
            
        case "readLogs":
            // Respond immediately to avoid blocking Flutter
            result(true)
            // Process file reading in background
            DispatchQueue.global(qos: .background).async {
                let logs = NativeLogger.readLogs()
                // Send logs via event sink to avoid blocking method channel
                DispatchQueue.main.async {
                    if let sink = NativeLogger.getEventSink() {
                        sink(["action": "readLogs", "data": logs])
                    }
                }
            }

        case "clearLogs":
            // Respond immediately to avoid blocking Flutter
            result(true)
            // Process file clearing in background
            DispatchQueue.global(qos: .background).async {
                let success = NativeLogger.clearLogs()
                // Send result via event sink
                DispatchQueue.main.async {
                    if let sink = NativeLogger.getEventSink() {
                        sink(["action": "clearLogs", "success": success])
                    }
                }
            }

        case "getLogFilePath":
            // This is fast, can remain synchronous
            result(NativeLogger.getLogFilePath())

        case "shareLogFile":
            // Respond immediately to avoid blocking Flutter
            result(true)
            // Process file sharing in background
            DispatchQueue.global(qos: .background).async {
                let success = NativeLogger.shareLogFile()
                // Send result via event sink
                DispatchQueue.main.async {
                    if let sink = NativeLogger.getEventSink() {
                        sink(["action": "shareLogFile", "success": success])
                    }
                }
            }

            case "getDeviceInfo":
                result(NativeLogger.getDeviceInfo())

            case "getAppVersion":
                result(NativeLogger.getAppVersion())

            case "filterLogs":
                guard let args = call.arguments as? [String: Any],
                      let keyword = args["keyword"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing keyword", details: nil))
                    return
                }

                // Respond immediately to avoid blocking Flutter
                result(true)
                // Process filtering in background
                DispatchQueue.global(qos: .background).async {
                    let filteredLogs = NativeLogger.filterLogs(keyword: keyword)
                    // Send result via event sink
                    DispatchQueue.main.async {
                        if let sink = NativeLogger.getEventSink() {
                            sink(["action": "filterLogs", "data": filteredLogs, "keyword": keyword])
                        }
                    }
                }

            case "archiveLogs":
                // Respond immediately to avoid blocking Flutter
                result(true)
                // Process archiving in background
                DispatchQueue.global(qos: .background).async {
                    if let archiveUrl = NativeLogger.archiveLogs() {
                        DispatchQueue.main.async {
                            if let sink = NativeLogger.getEventSink() {
                                sink(["action": "archiveLogs", "data": archiveUrl.path])
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            if let sink = NativeLogger.getEventSink() {
                                sink(["action": "archiveLogs", "data": NSNull()])
                            }
                        }
                    }
                }

            case "testShareFunctionality":
                result(NativeLogger.testShareFunctionality())

        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        NativeLogger.setEventSink(events)
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NativeLogger.setEventSink({ _ in })
        return nil
    }
}