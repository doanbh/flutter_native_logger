import Foundation
import UIKit
import Flutter

@objc public class NativeLogger: NSObject {
    private static let LOG_DIRECTORY = "native_logs"
    private static let LOG_FILENAME = "app_native_log.txt"
    private static let MAX_LOG_SIZE = 5 * 1024 * 1024 // 5MB
    private static let MAX_BUFFER_SIZE = 4 * 1024 // 4KB
    
    private static var memoryBuffer = NSMutableString()
    private static let bufferLock = NSLock()
    private static var lastFlushTime = Date()
    
    private static var eventSink: FlutterEventSink?
    
    // Singleton instance
    @objc public static let shared = NativeLogger()
    
    // MARK: - Public API
    
    @objc public static func log(message: String, level: String = "INFO", tag: String = "iOS", isBackground: Bool = false) {
        // Ensure this method never blocks by running everything in background
        DispatchQueue.global(qos: .background).async {
            autoreleasepool {
                do {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                    let timestamp = dateFormatter.string(from: Date())

                    let prefix = isBackground ? "[$tag-BG]" : "[$tag]"
                    let formattedMessage = "[\(timestamp)]\(prefix)[\(level)] \(message)\n"

                    // Add to memory buffer (thread-safe)
                    bufferLock.lock()
                    memoryBuffer.append(formattedMessage)

                    // Check buffer size or time for flushing
                    let currentTime = Date()
                    let timeSinceLastFlush = currentTime.timeIntervalSince(lastFlushTime)
                    let bufferSize = memoryBuffer.length

                    // Flush if buffer is big enough or enough time has passed
                    if bufferSize >= MAX_BUFFER_SIZE || timeSinceLastFlush >= 5.0 {
                        flushBuffer()
                    }
                    bufferLock.unlock()

                    // Send to event sink if available (on main thread)
                    DispatchQueue.main.async {
                        if let sink = eventSink {
                            do {
                                sink(message)
                            } catch {
                                // Ignore event sink errors to prevent crashes
                                NSLog("Event sink error: \(error.localizedDescription)")
                            }
                        }
                    }

                    // Also print to console for debugging
                    NSLog("NativeLogger: \(formattedMessage)")
                } catch {
                    // Never crash the app due to logging errors
                    NSLog("Error in NativeLogger.log: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc public static func readLogs() -> String {
        flushBuffer(force: true)
        
        let logFilePath = getLogFilePath()
        do {
            if FileManager.default.fileExists(atPath: logFilePath) {
                return try String(contentsOfFile: logFilePath, encoding: .utf8)
            } else {
                return "No log file exists"
            }
        } catch {
            return "Error reading logs: \(error.localizedDescription)"
        }
    }
    
    @objc public static func clearLogs() -> Bool {
        bufferLock.lock()
        memoryBuffer.setString("")
        bufferLock.unlock()
        
        let logFilePath = getLogFilePath()
        
        do {
            if FileManager.default.fileExists(atPath: logFilePath) {
                try FileManager.default.removeItem(atPath: logFilePath)
            }
            
            // Create new empty log file
            let header = "=== Log cleared at \(Date()) ===\n"
            try header.write(toFile: logFilePath, atomically: true, encoding: .utf8)
            
            return true
        } catch {
            NSLog("Error clearing logs: \(error.localizedDescription)")
            return false
        }
    }
    
    @objc public static func shareLogFile() -> Bool {
        // Force flush to ensure all logs are written
        flushBuffer(force: true)

        let logFilePath = getLogFilePath()

        // Check if file exists
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            NSLog("NativeLogger: Log file does not exist at path: \(logFilePath)")
            return false
        }

        // Create proper file URL
        let fileURL = URL(fileURLWithPath: logFilePath)

        // Get the top view controller using modern approach
        guard let topVC = getTopViewController() else {
            NSLog("NativeLogger: Could not find top view controller for sharing")
            return false
        }

        DispatchQueue.main.async {
            // Create activity view controller with proper error handling
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )

            // Configure for iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(
                    x: topVC.view.bounds.midX,
                    y: topVC.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }

            // Present with completion handler
            topVC.present(activityVC, animated: true) {
                NSLog("NativeLogger: Share sheet presented successfully")
            }
        }

        return true
    }
    
    @objc public static func getLogFilePath() -> String {
        do {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDirectory = paths[0]
            let directory = documentsDirectory.appendingPathComponent(LOG_DIRECTORY)

            // Create directory if needed (safe operation)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                NSLog("NativeLogger: Created log directory at: \(directory.path)")
            }

            let logFilePath = directory.appendingPathComponent(LOG_FILENAME).path

            // Ensure log file exists for sharing
            if !FileManager.default.fileExists(atPath: logFilePath) {
                let initialContent = "=== Native Logger initialized at \(Date()) ===\n"
                try initialContent.write(toFile: logFilePath, atomically: true, encoding: .utf8)
                NSLog("NativeLogger: Created initial log file at: \(logFilePath)")
            }

            return logFilePath
        } catch {
            NSLog("NativeLogger: Error creating log directory: \(error.localizedDescription)")
            // Return a fallback path in case of error
            let fallbackPath = NSTemporaryDirectory() + LOG_FILENAME

            // Try to create fallback file
            do {
                let initialContent = "=== Native Logger fallback file at \(Date()) ===\n"
                try initialContent.write(toFile: fallbackPath, atomically: true, encoding: .utf8)
            } catch {
                NSLog("NativeLogger: Failed to create fallback file: \(error.localizedDescription)")
            }

            return fallbackPath
        }
    }
    
    // MARK: - Private Methods
    
    public static func setEventSink(_ sink: @escaping FlutterEventSink) {
        eventSink = sink
    }

    // MARK: - Modern View Controller Helper

    private static func getTopViewController() -> UIViewController? {
        // Modern approach for iOS 13+
        if #available(iOS 13.0, *) {
            // Try to get from active window scene
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene,
                   windowScene.activationState == .foregroundActive {
                    for window in windowScene.windows {
                        if window.isKeyWindow,
                           let rootVC = window.rootViewController {
                            return rootVC.topMostViewController()
                        }
                    }
                }
            }

            // Fallback: get from any active window
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        if let rootVC = window.rootViewController {
                            return rootVC.topMostViewController()
                        }
                    }
                }
            }
        }

        // Legacy fallback for iOS 12 and below
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            return rootVC.topMostViewController()
        }

        // Last resort fallback
        if let window = UIApplication.shared.windows.first,
           let rootVC = window.rootViewController {
            return rootVC.topMostViewController()
        }

        return nil
    }

    // MARK: - Testing and Debug Helpers

    @objc public static func testShareFunctionality() -> String {
        let logFilePath = getLogFilePath()

        var status = "Share Test Results:\n"
        status += "Log file path: \(logFilePath)\n"
        status += "File exists: \(FileManager.default.fileExists(atPath: logFilePath))\n"

        if let fileSize = try? FileManager.default.attributesOfItem(atPath: logFilePath)[.size] as? UInt64 {
            status += "File size: \(fileSize) bytes\n"
        }

        let topVC = getTopViewController()
        status += "Top view controller found: \(topVC != nil)\n"

        if let topVC = topVC {
            status += "Top VC type: \(type(of: topVC))\n"
        }

        return status
    }
    
    private static func flushBuffer(force: Bool = false) {
        // Extract buffer content safely
        var contentToWrite: NSString?

        bufferLock.lock()
        if memoryBuffer.length == 0 && !force {
            bufferLock.unlock()
            return
        }

        contentToWrite = memoryBuffer.copy() as? NSString
        memoryBuffer.setString("")
        lastFlushTime = Date()
        bufferLock.unlock()

        // Ensure we have content to write
        guard let content = contentToWrite, content.length > 0 else {
            return
        }

        // Always perform file operations in background
        DispatchQueue.global(qos: .background).async {
            autoreleasepool {
                do {
                    let logFilePath = getLogFilePath()
                    let fileAttr = try? FileManager.default.attributesOfItem(atPath: logFilePath)
                    let fileSize = fileAttr?[.size] as? UInt64 ?? 0

                    if fileSize > MAX_LOG_SIZE {
                        // Rotate log files
                        rotateLogFiles()
                    }

                    // Use modern file writing approach
                    if let data = content.data(using: String.Encoding.utf8.rawValue) {
                        if FileManager.default.fileExists(atPath: logFilePath) {
                            // Append to existing file
                            if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath)) {
                                defer { try? fileHandle.close() }
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                            }
                        } else {
                            // Create new file
                            try data.write(to: URL(fileURLWithPath: logFilePath))
                        }
                    }
                } catch {
                    NSLog("Error writing to log file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private static func rotateLogFiles() {
        do {
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDirectory = paths[0]
            let directory = documentsDirectory.appendingPathComponent(LOG_DIRECTORY)
            
            let currentLogPath = getLogFilePath()
            
            // Generate new filename with timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let archivedPath = directory.appendingPathComponent("app_native_log_\(timestamp).txt").path
            
            // Rename current log file
            if FileManager.default.fileExists(atPath: currentLogPath) {
                try FileManager.default.moveItem(atPath: currentLogPath, toPath: archivedPath)
            }
            
            // Create new log file
            let header = "=== New log file created at \(Date()) ===\n"
            try header.write(toFile: currentLogPath, atomically: true, encoding: .utf8)
            
            // Delete old log files if too many exist
            let fileManager = FileManager.default
            let logFiles = try fileManager.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("app_native_log_") }
                .sorted()
            
            // Keep only the last 5 archived logs
            if logFiles.count > 5 {
                for i in 0..<(logFiles.count - 5) {
                    let oldFilePath = directory.appendingPathComponent(logFiles[i]).path
                    try fileManager.removeItem(atPath: oldFilePath)
                }
            }
        } catch {
            NSLog("Error rotating log files: \(error.localizedDescription)")
        }
    }

    @objc public static func getAppVersion() -> String {
        if let info = Bundle.main.infoDictionary {
            let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
            let build = info["CFBundleVersion"] as? String ?? "Unknown"
            return "\(version) (Build \(build))"
        }
        return "Unknown"
    }

    @objc public static func getDeviceInfo() -> String {
        let device = UIDevice.current
        return "Device: \(device.name), iOS \(device.systemVersion), Model: \(deviceModel())"
    }

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    @objc public static func logWithDetails(message: String, level: String = "INFO", tag: String = "iOS", file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function): \(message)"
        log(message: logMessage, level: level, tag: tag)
    }

    @objc public static func filterLogs(keyword: String) -> String {
        let logs = readLogs()
        if keyword.isEmpty {
            return logs
        }

        let lines = logs.components(separatedBy: "\n")
        let filteredLines = lines.filter { $0.lowercased().contains(keyword.lowercased()) }
        return filteredLines.joined(separator: "\n")
    }

    // Thêm trong lớp NativeLogger

    @objc public static func archiveLogs() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        do {
            let logFilePath = getLogFilePath()
            if !FileManager.default.fileExists(atPath: logFilePath) {
                return nil
            }

            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let documentsDirectory = paths[0]
            let archiveDir = documentsDirectory.appendingPathComponent("log_archives")

            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)

            let archiveFilePath = archiveDir.appendingPathComponent("log_\(timestamp).txt")
            try FileManager.default.copyItem(atPath: logFilePath, toPath: archiveFilePath.path)

            return archiveFilePath
        } catch {
            log(message: "Error archiving logs: \(error.localizedDescription)", level: "ERROR")
            return nil
        }
    }

    @objc public static func registerApplicationLifecycleEvents() {
        let notificationCenter = NotificationCenter.default

        // Register for app lifecycle notifications
        notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            log(message: "App entered background", tag: "Lifecycle")
            flushBuffer(force: true) // Force flush when app goes to background
        }

        notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            log(message: "App will enter foreground", tag: "Lifecycle")
        }

        notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            log(message: "App became active", tag: "Lifecycle")
        }

        notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            log(message: "App will resign active", tag: "Lifecycle")
            flushBuffer(force: true) // Force flush when app resigns active
        }

        notificationCenter.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            log(message: "App will terminate", tag: "Lifecycle")
            flushBuffer(force: true) // Force flush when app terminates
        }

        // Register for device orientation changes
        notificationCenter.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let orientation: String
            switch UIDevice.current.orientation {
            case .portrait:
                orientation = "Portrait"
            case .portraitUpsideDown:
                orientation = "Portrait Upside Down"
            case .landscapeLeft:
                orientation = "Landscape Left"
            case .landscapeRight:
                orientation = "Landscape Right"
            case .faceUp:
                orientation = "Face Up"
            case .faceDown:
                orientation = "Face Down"
            default:
                orientation = "Unknown"
            }
            log(message: "Device orientation changed: \(orientation)", tag: "Orientation")
        }
    }

    @objc public static func optimizeLogStorage() {
        DispatchQueue.global(qos: .background).async {
            autoreleasepool {
                do {
                    let logFilePath = getLogFilePath()
                    let logDirectory = URL(fileURLWithPath: logFilePath).deletingLastPathComponent().path
                    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: logDirectory) else {
                        return
                    }

                    // Lọc ra các file log
                    let logFiles = contents.filter { $0.hasPrefix("app_native_log_") && $0.hasSuffix(".txt") }

                    // Sắp xếp theo thời gian sửa đổi
                    let sortedFiles = logFiles.compactMap { filename -> (String, Date)? in
                        let filePath = (logDirectory as NSString).appendingPathComponent(filename)
                        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
                              let modificationDate = attributes[.modificationDate] as? Date else {
                            return nil
                        }
                        return (filename, modificationDate)
                    }.sorted { $0.1 > $1.1 }

                    // Giữ lại tối đa 5 file gần nhất, xóa các file còn lại
                    if sortedFiles.count > 5 {
                        for i in 5..<sortedFiles.count {
                            let fileToDelete = (logDirectory as NSString).appendingPathComponent(sortedFiles[i].0)
                            try? FileManager.default.removeItem(atPath: fileToDelete)
                            log(message: "Removed old log file: \(sortedFiles[i].0)", tag: "LogMaintenance")
                        }
                    }

                    // Kiểm tra dung lượng thư mục log
                    var totalSize: UInt64 = 0
                    for filename in contents {
                        let filePath = (logDirectory as NSString).appendingPathComponent(filename)
                        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
                              let fileSize = attributes[.size] as? UInt64 else {
                            continue
                        }
                        totalSize += fileSize
                    }

                    // Nếu tổng kích thước vượt quá 50MB, xóa file log cũ nhất
                    let maxDirectorySize: UInt64 = 50 * 1024 * 1024 // 50MB
                    if totalSize > maxDirectorySize && !sortedFiles.isEmpty {
                        let oldestFile = (logDirectory as NSString).appendingPathComponent(sortedFiles.last!.0)
                        try? FileManager.default.removeItem(atPath: oldestFile)
                        log(message: "Removed oldest log file due to space constraints", tag: "LogMaintenance")
                    }
                } catch {
                    log(message: "Error optimizing log storage: \(error.localizedDescription)", level: "ERROR")
                }
            }
        }
    }
}

// Helper extension to get topmost view controller
extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topMostViewController()
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController() ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }
        return self
    }
}