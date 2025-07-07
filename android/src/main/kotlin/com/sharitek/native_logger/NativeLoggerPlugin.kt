package com.sharitek.native_logger

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class NativeLoggerPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var eventSink: EventChannel.EventSink? = null

    // Thread pool for I/O operations
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Constants
    private val LOG_DIRECTORY = "native_logs"
    private val LOG_FILENAME = "app_native_log.txt"
    private val MAX_LOG_SIZE = 5 * 1024 * 1024 // 5MB
    private val MAX_LOG_FILES = 5

    // Memory log buffer for performance optimization
    private val memoryLogBuffer = StringBuilder()
    private val logBufferLock = Object()
    private val LOG_BUFFER_FLUSH_SIZE = 4 * 1024 // 4KB
    private var lastFlushTime = System.currentTimeMillis()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.sharitek.native_logger/methods")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.sharitek.native_logger/events")
        eventChannel.setStreamHandler(this)

        // Initialize in background to avoid blocking main thread
        executor.execute {
            createLogDirectoryIfNeeded()
            logToFile("=== Native Logger initialized ===")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        flushBuffer(force = true) // Ensure data is written before detaching
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeLogger" -> {
                // Respond immediately to avoid blocking Flutter
                result.success(true)
                // Log in background
                executor.execute {
                    logToFile("=== Native Logger initialized from Flutter ===")
                }
            }
            "logMessage" -> {
                // Respond immediately to avoid blocking Flutter
                result.success(true)

                // Process logging in background
                executor.execute {
                    val message = call.argument<String>("message") ?: "No message"
                    val level = call.argument<String>("level") ?: "INFO"
                    val tag = call.argument<String>("tag") ?: "Flutter"
                    val isBackground = call.argument<Boolean>("isBackground") ?: false

                    val formattedMessage = if (isBackground) "[$tag-BG][$level] $message" else "[$tag][$level] $message"
                    logToFile(formattedMessage)
                }
            }
            "readLogs" -> {
                flushBuffer(force = true) // Ensure all logs are saved before reading
                executor.execute {
                    val logs = readLogFile()
                    mainHandler.post {
                        result.success(logs)
                    }
                }
            }
            "clearLogs" -> {
                executor.execute {
                    val success = clearLogFiles()
                    mainHandler.post {
                        result.success(success)
                    }
                }
            }
            "getLogFilePath" -> {
                result.success(getLogFilePath())
            }
            "shareLogFile" -> {
                flushBuffer(force = true)
                executor.execute {
                    val success = shareLogFile()
                    mainHandler.post {
                        result.success(success)
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun logToFile(message: String) {
        try {
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
            val logEntry = "[$timestamp] $message\n"

            // Add to in-memory buffer (this is fast, no I/O)
            synchronized(logBufferLock) {
                memoryLogBuffer.append(logEntry)

                // Auto-flush based on size or time
                val currentTime = System.currentTimeMillis()
                val bufferSize = memoryLogBuffer.length
                val timeSinceLastFlush = currentTime - lastFlushTime

                // Write to file if buffer reaches threshold or time passed 5s
                if (bufferSize >= LOG_BUFFER_FLUSH_SIZE || timeSinceLastFlush >= 5000) {
                    // Always flush in background to avoid blocking
                    executor.execute {
                        flushBuffer()
                    }
                }
            }

            // Send log to Flutter if event sink available (non-blocking)
            eventSink?.let { sink ->
                mainHandler.post {
                    try {
                        sink.success(message)
                    } catch (e: Exception) {
                        // Ignore event sink errors to prevent crashes
                        android.util.Log.w("NativeLogger", "Event sink error: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            // Never crash the app due to logging errors
            android.util.Log.e("NativeLogger", "Error in logToFile: ${e.message}")
        }
    }

    private fun flushBuffer(force: Boolean = false) {
        synchronized(logBufferLock) {
            if (memoryLogBuffer.isEmpty() && !force) return

            val currentBuffer = memoryLogBuffer.toString()
            memoryLogBuffer.setLength(0) // Clear buffer
            lastFlushTime = System.currentTimeMillis()

            if (currentBuffer.isNotEmpty()) {
                try {
                    // Check log file size
                    val logFile = getLogFile()
                    if (logFile.exists() && logFile.length() > MAX_LOG_SIZE) {
                        rotateLogFiles()
                    }

                    // Append to log file
                    FileOutputStream(logFile, true).use { fos ->
                        fos.write(currentBuffer.toByteArray())
                        fos.flush()
                    }
                } catch (e: Exception) {
                    android.util.Log.e("NativeLogger", "Error writing to log file", e)
                }
            }
        }
    }

    private fun readLogFile(): String {
        val logFile = getLogFile()
        return if (logFile.exists()) {
            try {
                logFile.readText()
            } catch (e: Exception) {
                "Error reading log file: ${e.message}"
            }
        } else {
            "No log file exists."
        }
    }

    private fun rotateLogFiles() {
        try {
            val logDir = getLogDirectory()
            val logFiles = logDir.listFiles { file ->
                file.isFile && file.name.startsWith("app_native_log")
            }?.toMutableList() ?: mutableListOf()

            // Rename current file
            val logFile = getLogFile()
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val archivedFile = File(logDir, "app_native_log_$timestamp.txt")
            if (logFile.exists()) {
                logFile.renameTo(archivedFile)
            }

            // If too many files, delete oldest ones
            logFiles.add(archivedFile)
            if (logFiles.size > MAX_LOG_FILES) {
                logFiles.sortBy { it.lastModified() }
                for (i in 0 until (logFiles.size - MAX_LOG_FILES)) {
                    logFiles[i].delete()
                }
            }

            // Create new log file
            val newLogFile = getLogFile()
            newLogFile.createNewFile()

            // Write header to new log file
            val header = "=== New log file created at ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())} ===\n"
            FileOutputStream(newLogFile).use { fos ->
                fos.write(header.toByteArray())
            }
        } catch (e: Exception) {
            android.util.Log.e("NativeLogger", "Error rotating log files", e)
        }
    }

    private fun clearLogFiles(): Boolean {
        return try {
            val logDir = getLogDirectory()
            val logFiles = logDir.listFiles { file ->
                file.isFile && file.name.startsWith("app_native_log")
            }

            if (logFiles != null) {
                for (file in logFiles) {
                    file.delete()
                }
            }

            // Create new log file
            val newLogFile = getLogFile()
            newLogFile.createNewFile()

            // Write header to new log file
            val header = "=== Log cleared at ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())} ===\n"
            FileOutputStream(newLogFile).use { fos ->
                fos.write(header.toByteArray())
            }

            true
        } catch (e: Exception) {
            android.util.Log.e("NativeLogger", "Error clearing log files", e)
            false
        }
    }

    private fun getLogFile(): File {
        val logDir = getLogDirectory()
        return File(logDir, LOG_FILENAME)
    }

    private fun getLogDirectory(): File {
        val dir = File(context.getExternalFilesDir(null), LOG_DIRECTORY)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun createLogDirectoryIfNeeded() {
        val logDir = getLogDirectory()
        if (!logDir.exists()) {
            logDir.mkdirs()
        }

        val logFile = getLogFile()
        if (!logFile.exists()) {
            try {
                logFile.createNewFile()
                val header = "=== Native Logger initialized at ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())} ===\n"
                FileOutputStream(logFile).use { fos ->
                    fos.write(header.toByteArray())
                }
            } catch (e: Exception) {
                android.util.Log.e("NativeLogger", "Error creating log file", e)
            }
        }
    }

    private fun getLogFilePath(): String {
        return getLogFile().absolutePath
    }

    private fun shareLogFile(): Boolean {
        try {
            val logFile = getLogFile()
            if (!logFile.exists()) {
                return false
            }

            val fileUri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.native_logger.fileprovider",
                logFile
            )

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, fileUri)
                putExtra(Intent.EXTRA_SUBJECT, "Native Logs - ${SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())}")
                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            }

            val chooserIntent = Intent.createChooser(shareIntent, "Share log file")
            chooserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooserIntent)

            return true
        } catch (e: Exception) {
            android.util.Log.e("NativeLogger", "Error sharing log file", e)
            return false
        }
    }
}