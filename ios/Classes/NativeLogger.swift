import Foundation
import UIKit
import Flutter

@objc public class NativeLogger: NSObject {
    private static let LOG_DIRECTORY = "native_logs"
    private static let LOG_FILENAME = "app_native_log.txt"
    private static let MAX_LOG_SIZE = 5 * 1024 * 1024 // 5MB
    private static let MAX_BUFFER_SIZE = 4 * 1024 // 4KB
    
    // MARK: - Thread-Safe Buffer Management
    /// Thread-safe buffer using concurrent queue with barriers
    /// Replaces NSMutableString to eliminate thread safety issues
    private static var bufferData = Data()
    private static var lastFlushTime = Date()
    private static let bufferQueue = DispatchQueue(
        label: "com.sharitek.native_logger.buffer",
        qos: .background,
        attributes: .concurrent
    )
    
    private static var eventSink: FlutterEventSink?
    
    // MARK: - Performance Optimization: Thread-Safe DateFormatter
    private static let dateFormatterKey = "NativeLogger.DateFormatter"
    
    /// Thread-safe DateFormatter using thread-local storage
    /// Prevents crashes and incorrect timestamps from concurrent access
    private static var threadLocalDateFormatter: DateFormatter {
        // Check if current thread already has a DateFormatter
        if let formatter = Thread.current.threadDictionary[dateFormatterKey] as? DateFormatter {
            return formatter
        }
        
        // Create new DateFormatter for this thread
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Store in thread-local storage
        Thread.current.threadDictionary[dateFormatterKey] = formatter
        return formatter
    }
    
    // Singleton instance
    @objc public static let shared = NativeLogger()
    
    // MARK: - Public API
    
    @objc public static func log(message: String, level: String = "INFO", tag: String = "iOS", isBackground: Bool = false) {
        // Ensure this method never blocks by running everything in background
        DispatchQueue.global(qos: .background).async {
            autoreleasepool {
                do {
                    // Use thread-safe DateFormatter for better performance and safety
                    let timestamp = threadLocalDateFormatter.string(from: Date())
                    
                    let prefix = isBackground ? "[$tag-BG]" : "[$tag]"
                    let formattedMessage = "[\(timestamp)]\(prefix)[\(level)] \(message)\n"
                    
                    // Convert to Data for efficient buffer management
                    guard let messageData = formattedMessage.data(using: .utf8) else {
                        NSLog("Failed to convert log message to UTF-8 data")
                        return
                    }
                    
                    // Add to thread-safe buffer using barrier for write operations
                    bufferQueue.async(flags: .barrier) {
                        bufferData.append(messageData)
                        
                        // Check buffer size or time for flushing
                        let currentTime = Date()
                        let timeSinceLastFlush = currentTime.timeIntervalSince(lastFlushTime)
                        let bufferSize = bufferData.count
                        
                        // Flush if buffer is big enough or enough time has passed
                        if bufferSize >= MAX_BUFFER_SIZE || timeSinceLastFlush >= 5.0 {
                            flushBufferInternal()
                        }
                    }
                    
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
        // Clear buffer using thread-safe barrier operation
        bufferQueue.sync(flags: .barrier) {
            bufferData.removeAll(keepingCapacity: true)
        }
        
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
        guard let topVC = topMostViewController() else {
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
    
    // MARK: - Internal Helper for Plugin
    
    @objc public static func getEventSink() -> FlutterEventSink? {
        return eventSink
    }
    
    // MARK: - Modern View Controller Helper (using new implementation)
    
    // MARK: - Testing and Debug Helpers
    
    @objc public static func testShareFunctionality() -> String {
        let logFilePath = getLogFilePath()
        
        var status = "Share Test Results:\n"
        status += "Log file path: \(logFilePath)\n"
        status += "File exists: \(FileManager.default.fileExists(atPath: logFilePath))\n"
        
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: logFilePath)[.size] as? UInt64 {
            status += "File size: \(fileSize) bytes\n"
        }
        
        let topVC = topMostViewController()
        status += "Top view controller found: \(topVC != nil)\n"
        
        if let topVC = topVC {
            status += "Top VC type: \(type(of: topVC))\n"
        }
        
        return status
    }
    
    /// Public interface for flushing buffer - maintains API compatibility
    private static func flushBuffer(force: Bool = false) {
        bufferQueue.async(flags: .barrier) {
            flushBufferInternal(force: force)
        }
    }
    
    /// Internal thread-safe buffer flushing implementation
    /// Must be called from within bufferQueue barrier
    private static func flushBufferInternal(force: Bool = false) {
        // Check if we have content to write
        if bufferData.isEmpty && !force {
            return
        }
        
        // Extract buffer content safely
        let contentToWrite = bufferData
        bufferData.removeAll(keepingCapacity: true) // Reuse allocated capacity
        lastFlushTime = Date()
        
        // Ensure we have content to write
        guard !contentToWrite.isEmpty else {
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
                    
                    // Use modern file writing approach with Data directly
                    if FileManager.default.fileExists(atPath: logFilePath) {
                        // Append to existing file using modern APIs
                        if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath)) {
                            defer { try? fileHandle.close() }
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(contentToWrite)
                        }
                    } else {
                        // Create new file with Data directly
                        try contentToWrite.write(to: URL(fileURLWithPath: logFilePath))
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
            
            // Generate new filename with timestamp using thread-safe formatter
            let archiveDateFormatter = DateFormatter()
            archiveDateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = archiveDateFormatter.string(from: Date())
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
        let archiveDateFormatter = DateFormatter()
        archiveDateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = archiveDateFormatter.string(from: Date())
        
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
            // Process in background to avoid blocking main thread
            DispatchQueue.global(qos: .background).async {
                log(message: "App entered background", tag: "Lifecycle")
                flushBuffer(force: true) // Force flush when app goes to background
            }
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
            // Process in background to avoid blocking main thread
            DispatchQueue.global(qos: .background).async {
                log(message: "App will resign active", tag: "Lifecycle")
                flushBuffer(force: true) // Force flush when app resigns active
            }
        }
        
        notificationCenter.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Process in background to avoid blocking main thread
            DispatchQueue.global(qos: .background).async {
                log(message: "App will terminate", tag: "Lifecycle")
                flushBuffer(force: true) // Force flush when app terminates
            }
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
    
    // MARK: - Helper Methods
    
    /// Helper method to get topmost view controller
    private static func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            return nil
        }
        
        return getTopMostViewController(from: rootViewController)
    }
    
    private static func getTopMostViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return getTopMostViewController(from: presented)
        }
        if let navigation = viewController as? UINavigationController {
            return getTopMostViewController(from: navigation.visibleViewController ?? navigation)
        }
        if let tab = viewController as? UITabBarController {
            return getTopMostViewController(from: tab.selectedViewController ?? tab)
        }
        return viewController
    }
}
