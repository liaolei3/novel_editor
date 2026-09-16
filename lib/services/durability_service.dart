import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/db.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import 'logger.dart';

/// 防丢稿三重保障（FR-9 / FR-10 / FR-11）：
/// - 快照：手动 / 每日自动，保留最近 30 个；
/// - 本地多副本备份：主存（SQLite）+ 备份目录文件，保留 7 天；
/// - 崩溃恢复：异常退出标记检测 + 恢复至最后保存点。
class DurabilityService {
  DurabilityService(this._snapshots, this._chapters);

  final SnapshotRepository _snapshots;
  final ChapterRepository _chapters;

  String? _backupDir;

  Future<String> _ensureBackupDir() async {
    if (_backupDir != null) return _backupDir!;
    final support = await Db.supportDir();
    _backupDir = p.join(support, 'backups');
    await Directory(_backupDir!).create(recursive: true);
    return _backupDir!;
  }

  /// 每日自动快照：当天已有自动快照则跳过。
  Future<Snapshot?> autoSnapshotIfNeeded(Chapter chapter) async {
    final list = await _snapshots.listByChapter(chapter.id);
    final today = DateTime.now();
    final hasToday = list.any((s) =>
        s.type == SnapshotType.auto &&
        s.createdAt.year == today.year &&
        s.createdAt.month == today.month &&
        s.createdAt.day == today.day);
    if (hasToday) return null;
    return _snapshots.add(SnapshotType.auto, chapter);
  }

  Future<Snapshot> manualSnapshot(Chapter chapter) =>
      _snapshots.add(SnapshotType.manual, chapter);

  /// 回滚前先保存当前版本快照，保证操作可逆（12.4）。
  Future<Chapter> rollbackTo(Chapter chapter, Snapshot target) async {
    if (chapter.content != target.content) {
      await _snapshots.add(SnapshotType.rollback, chapter);
    }
    chapter.content = target.content;
    await _chapters.updateContent(chapter);
    await backupChapter(chapter);
    return chapter;
  }

  /// 双副本备份：把章节正文写入备份目录（临时文件 → 原子替换，NFR-R2）。
  Future<void> backupChapter(Chapter chapter) async {
    try {
      final dir = await _ensureBackupDir();
      final bookDir = p.join(dir, chapter.bookId);
      await Directory(bookDir).create(recursive: true);
      final file = File(p.join(bookDir, '${chapter.id}.txt'));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(chapter.content, flush: true);
      await tmp.rename(file.path);
      await _cleanOldBackups(bookDir);
    } catch (e, s) {
      Logger.error('章节备份失败: ${chapter.id}',
          error: e, stackTrace: s, tag: 'Durability');
    }
  }

  /// 从备份副本恢复章节内容（任一副本损坏时兜底，NFR-R1）。
  Future<String?> restoreFromBackup(Chapter chapter) async {
    final dir = await _ensureBackupDir();
    final file = File(p.join(dir, chapter.bookId, '${chapter.id}.txt'));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  Future<void> _cleanOldBackups(String bookDir) async {
    final dir = Directory(bookDir);
    if (!dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final stat = await f.stat();
      if (stat.modified.isBefore(cutoff)) {
        await f.delete();
      }
    }
  }
}

/// 崩溃恢复（FR-11 / S3）：
/// 启动时检测崩溃标记 → 提示恢复；正常退出时清除标记。
class CrashRecovery {
  CrashRecovery();

  static const _flagName = 'crash.flag';
  String? _flagPath;

  Future<String> _flagFile() async {
    if (_flagPath != null) return _flagPath!;
    final support = await Db.supportDir();
    _flagPath = p.join(support, _flagName);
    return _flagPath!;
  }

  /// 应用启动时调用：返回是否检测到上次异常退出。
  Future<CrashReport?> detect() async {
    final file = File(await _flagFile());
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, Object?>;
      final exitedAt = DateTime.fromMillisecondsSinceEpoch(json['time'] as int);
      return CrashReport(exitedAt: exitedAt, chapterId: json['chapter'] as String?);
    } catch (_) {
      return CrashReport(exitedAt: DateTime.now(), chapterId: null);
    }
  }

  /// 写入“正在运行”标记（心跳式：每次自动保存时刷新时间戳）。
  Future<void> markAlive({String? chapterId}) async {
    final file = File(await _flagFile());
    await file.writeAsString(jsonEncode({
      'time': DateTime.now().millisecondsSinceEpoch,
      'chapter': chapterId,
    }), flush: true);
  }

  /// 正常退出时清除标记。
  Future<void> clear() async {
    final file = File(await _flagFile());
    if (file.existsSync()) await file.delete();
  }
}

class CrashReport {
  CrashReport({required this.exitedAt, this.chapterId});

  final DateTime exitedAt;
  final String? chapterId;
}