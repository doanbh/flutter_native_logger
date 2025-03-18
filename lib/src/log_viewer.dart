import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'native_logger_base.dart';

class LogViewer extends StatefulWidget {
  /// Custom theme color
  final Color themeColor;

  /// Log title
  final String title;

  /// Show auto-scroll toggle
  final bool showAutoScrollToggle;

  const LogViewer({
    Key? key,
    this.themeColor = Colors.blue,
    this.title = 'Native Logs',
    this.showAutoScrollToggle = true,
  }) : super(key: key);

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  String _logs = '';
  bool _isLoading = true;
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  final _nativeLogger = NativeLogger();
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _startListening();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _logSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });

    final logs = await NativeLogger.readLogs();

    setState(() {
      _logs = logs;
      _isLoading = false;
    });

    if (_autoScroll) {
      _scrollToBottom();
    }
  }

  void _startListening() {
    _logSubscription = _nativeLogger.logStream.listen((newLog) {
      setState(() {
        _logs += '\n$newLog';
      });

      if (_autoScroll) {
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.themeColor,
        title: Text(widget.title),
        actions: [
          if (widget.showAutoScrollToggle)
            IconButton(
              icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  _autoScroll = !_autoScroll;
                  if (_autoScroll) _scrollToBottom();
                });
              },
              tooltip: _autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: 'Reload logs',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => NativeLogger.shareLogFile(),
            tooltip: 'Share logs',
          ),
          IconButton(
            icon: const Icon(Icons.content_copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
            tooltip: 'Copy logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs'),
                  content: const Text('Are you sure you want to clear all logs?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (result == true) {
                await NativeLogger.clearLogs();
                _loadLogs();
              }
            },
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (widget.showAutoScrollToggle)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_autoScroll ? 'Auto-scroll enabled' : 'Auto-scroll disabled'),
                  Switch(
                    value: _autoScroll,
                    onChanged: (value) {
                      setState(() {
                        _autoScroll = value;
                        if (_autoScroll) _scrollToBottom();
                      });
                    },
                    activeColor: widget.themeColor,
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SelectableText(
                    _logs,
                    style: const TextStyle(
                      color: Colors.lightGreenAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.themeColor,
        onPressed: () async {
          await NativeLogger.log("Test log from UI", tag: "UI_TEST");
        },
        child: const Icon(Icons.add),
        tooltip: 'Add test log',
      ),
    );
  }
}