import Flutter
import UIKit

public class SwiftNativeLoggerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.sharitek.soffice/native_logger", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "com.sharitek.soffice/log_events", binaryMessenger: registrar.messenger())
        
        let instance = SwiftNativeLoggerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializeLogger":
            // Log initialization
            NativeLogger.log(message: "=== Native Logger initialized from Flutter ===")
            result(true)
            
        case "logMessage":
            guard let args = call.arguments as? [String: Any],
                  let message = args["message"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing message", details: nil))
                return
            }
            
            let level = args["level"] as? String ?? "INFO"
            let tag = args["tag"] as? String ?? "Flutter"
            let isBackground = args["isBackground"] as? Bool ?? false
            
            NativeLogger.log(
                message: message,
                level: level, 
                tag: tag,
                isBackground: isBackground
            )
            result(true)
            
        case "readLogs":
            result(NativeLogger.readLogs())
            
        case "clearLogs":
            result(NativeLogger.clearLogs())
            
        case "getLogFilePath":
            result(NativeLogger.getLogFilePath())
            
        case "shareLogFile":
            result(NativeLogger.shareLogFile())

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
                result(NativeLogger.filterLogs(keyword: keyword))

            case "archiveLogs":
                if let archiveUrl = NativeLogger.archiveLogs() {
                    result(archiveUrl.path)
                } else {
                    result(nil)
                }
            
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