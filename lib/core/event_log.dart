import 'package:flutter/foundation.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  LogEntry(this.time, this.level, this.tag, this.message);
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String format() {
    final t = time.toIso8601String().substring(11, 23);
    final l = switch (level) { LogLevel.info => 'I', LogLevel.warn => 'W', LogLevel.error => 'E' };
    return '$t $l [$tag] $message';
  }
}

/// In-memory ring buffer of technical events for the diagnostics screen.
/// Never receives media content — only states, parameters and errors.
class EventLog extends ChangeNotifier {
  EventLog._();
  static final EventLog instance = EventLog._();

  static const int capacity = 400;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(String tag, String message, {LogLevel level = LogLevel.info}) {
    _entries.add(LogEntry(DateTime.now(), level, tag, message));
    if (_entries.length > capacity) _entries.removeRange(0, _entries.length - capacity);
    if (kDebugMode) debugPrint('[$tag] $message');
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String dump() => _entries.map((e) => e.format()).join('\n');
}

void logI(String tag, String msg) => EventLog.instance.add(tag, msg);
void logW(String tag, String msg) => EventLog.instance.add(tag, msg, level: LogLevel.warn);
void logE(String tag, String msg) => EventLog.instance.add(tag, msg, level: LogLevel.error);
