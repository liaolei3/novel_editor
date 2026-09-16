import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/db.dart';

enum LogLevel { debug, info, warn, error }

class Logger {
  Logger._();

  static const _keepDays = 7;
  static Directory? _dir;

  static Future<void> _queue = Future.value();

  static Future<void> init() async {
    try {
      final dir = Directory(p.join(await Db.supportDir(), 'logs'));
      if (!dir.existsSync()) await dir.create(recursive: true);
      _dir = dir;
      await _cleanup();
      info('应用启动');
    } catch (_) {
      _dir = null;
    }
  }

  static Future<String> logsDir() async =>
      p.join(await Db.supportDir(), 'logs');

  static void debug(String message, {String tag = 'App'}) =>
      _log(LogLevel.debug, message, null, null, tag);
  static void info(String message, {String tag = 'App'}) =>
      _log(LogLevel.info, message, null, null, tag);
  static void warn(String message, {Object? error, String tag = 'App'}) =>
      _log(LogLevel.warn, message, error, null, tag);
  static void error(String message,
          {Object? error, StackTrace? stackTrace, String tag = 'App'}) =>
      _log(LogLevel.error, message, error, stackTrace, tag);

  static void _log(LogLevel level, String message, Object? error,
      StackTrace? stackTrace, String tag) {
    final dir = _dir;
    if (dir == null) return;
    final now = DateTime.now();
    final ts = now.toIso8601String();
    final buf = StringBuffer('[$ts][$level][$tag] $message');
    if (error != null) buf.write('\n  错误: $error');
    if (stackTrace != null) {
      buf.write('\n  堆栈:\n');
      buf.write(stackTrace
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => '    $l')
          .join('\n'));
    }
    final file = File(p.join(dir.path, _fileName(now)));
    final line = buf.toString();
    _queue = _queue.then((_) async {
      try {
        await file.writeAsString('$line\n',
            mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }

  static String _fileName(DateTime t) =>
      'app-${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}.log';

  static Future<void> _cleanup() async {
    final dir = _dir;
    if (dir == null) return;
    final cutoff = DateTime.now().subtract(const Duration(days: _keepDays));
    final names = await dir.list().toList();
    for (final entity in names) {
      if (entity is! File) continue;
      final m = RegExp(r'^app-(\d{8})\.log$')
          .firstMatch(p.basename(entity.path));
      if (m == null) continue;
      final g = m.group(1)!;
      final day = DateTime(
        int.parse(g.substring(0, 4)),
        int.parse(g.substring(4, 6)),
        int.parse(g.substring(6, 8)),
      );
      if (day.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}
