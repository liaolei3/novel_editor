import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';

/// 云同步引擎（FR-12 / FR-13 / 12.2）。
///
/// 设计要点：
/// - 本地优先，联网自动增量同步（按章节粒度 + 版本号比对）；
/// - 冲突绝不静默覆盖（NFR-R3），检测到双向修改时进入冲突解决流程；
/// - MVP 无服务端：[CloudGateway] 为抽象接口，本地以 [MockCloudGateway]
///   模拟云端存储（独立镜像区），后续替换为真实 HTTP 实现即可。
class SyncEngine {
  SyncEngine(this._chapters, {CloudGateway? gateway})
      : _cloud = gateway ?? MockCloudGateway();

  final ChapterRepository _chapters;
  final CloudGateway _cloud;

  bool _syncing = false;
  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  Future<List<SyncConflict>> syncAll(String bookId) async {
    if (_syncing) return const [];
    _syncing = true;
    final conflicts = <SyncConflict>[];
    try {
      final chapters = await _chapters.listByBook(bookId);
      for (final chapter in chapters) {
        final conflict = await _syncChapter(chapter);
        if (conflict != null) conflicts.add(conflict);
      }
      _events.add(SyncEvent(SyncStatus.completed, chapterCount: chapters.length));
    } catch (e) {
      _events.add(SyncEvent(SyncStatus.failed, error: e.toString()));
    } finally {
      _syncing = false;
    }
    return conflicts;
  }

  Future<SyncConflict?> _syncChapter(Chapter chapter) async {
    final db = await Db.instance();
    final rows = await db.query('sync_state',
        where: 'entity_id = ?', whereArgs: [chapter.id]);
    final hasLocal = rows.isNotEmpty;
    final localVersion =
        hasLocal ? rows.first['local_version'] as int : chapter.version;
    final cloudVersion =
        hasLocal ? rows.first['cloud_version'] as int : 0;
    final dirty = hasLocal ? (rows.first['dirty'] as int) == 1 : true;

    final cloudDoc = await _cloud.fetch(chapter.id);
    final cloudContent = cloudDoc?.content ?? '';
    final cloudRev = cloudDoc?.version ?? 0;

    if (dirty && cloudRev > cloudVersion) {
      // 双端均修改 → 冲突。
      if (chapter.content != cloudContent) {
        _events.add(SyncEvent(SyncStatus.conflict, chapterId: chapter.id));
        return SyncConflict(
          chapterId: chapter.id,
          chapterTitle: chapter.title,
          localContent: chapter.content,
          localVersion: localVersion,
          cloudContent: cloudContent,
          cloudVersion: cloudRev,
        );
      }
    }

    if (dirty) {
      final newRev = await _cloud.push(chapter.id, chapter.content, chapter.version);
      await _upsertSyncState(db, chapter.id, chapter.version, newRev, false);
      _events.add(SyncEvent(SyncStatus.pushed, chapterId: chapter.id));
      return null;
    }

    if (cloudRev > cloudVersion) {
      chapter.content = cloudContent;
      await _chapters.updateContent(chapter);
      await _upsertSyncState(db, chapter.id, chapter.version, cloudRev, false);
      _events.add(SyncEvent(SyncStatus.pulled, chapterId: chapter.id));
    }
    return null;
  }

  Future<void> _upsertSyncState(Database db, String chapterId, int localVersion,
      int cloudVersion, bool dirty) async {
    await db.insert(
      'sync_state',
      {
        'entity_id': chapterId,
        'entity_type': 'chapter',
        'local_version': localVersion,
        'cloud_version': cloudVersion,
        'content_hash': '',
        'dirty': dirty ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> resolveConflict(
      Chapter chapter, ConflictChoice choice) async {
    final db = await Db.instance();
    switch (choice) {
      case ConflictChoice.keepLocal:
        await _chapters.updateContent(chapter);
        break;
      case ConflictChoice.useCloud:
        final cloud = await _cloud.fetch(chapter.id);
        if (cloud != null) {
          chapter.content = cloud.content;
          await _chapters.updateContent(chapter);
        }
        break;
      case ConflictChoice.keepBoth:
        await _chapters.updateContent(chapter);
        final cloud = await _cloud.fetch(chapter.id);
        final copy = await _chapters.create(
          bookId: chapter.bookId,
          volumeId: chapter.volumeId,
          title: '${chapter.title}（云端副本）',
          content: cloud?.content ?? '',
          sort: chapter.sort + 10000,
        );
        await _upsertSyncState(db, copy.id, 1, 0, false);
        break;
    }
    final rev = await _cloud.push(chapter.id, chapter.content, chapter.version);
    await _upsertSyncState(db, chapter.id, chapter.version, rev, false);
  }
}

enum ConflictChoice { keepLocal, useCloud, keepBoth }

class SyncConflict {
  SyncConflict({
    required this.chapterId,
    required this.chapterTitle,
    required this.localContent,
    required this.localVersion,
    required this.cloudContent,
    required this.cloudVersion,
  });

  final String chapterId;
  final String chapterTitle;
  final String localContent;
  final int localVersion;
  final String cloudContent;
  final int cloudVersion;
}

enum SyncStatus { pushed, pulled, conflict, completed, failed }

class SyncEvent {
  SyncEvent(this.status, {this.chapterId, this.chapterCount, this.error});

  final SyncStatus status;
  final String? chapterId;
  final int? chapterCount;
  final String? error;
}

/// 云端文档镜像。
class CloudDoc {
  CloudDoc({required this.version, required this.content});

  final int version;
  final String content;
}

abstract class CloudGateway {
  Future<CloudDoc?> fetch(String chapterId);
  Future<int> push(String chapterId, String content, int localVersion);
}

/// 本地模拟云端：独立内存区模拟服务端版本号递增。
class MockCloudGateway implements CloudGateway {
  final Map<String, CloudDoc> _store = {};

  @override
  Future<CloudDoc?> fetch(String chapterId) async => _store[chapterId];

  @override
  Future<int> push(String chapterId, String content, int localVersion) async {
    final current = _store[chapterId];
    final version = (current?.version ?? 0) + 1;
    _store[chapterId] = CloudDoc(version: version, content: content);
    return version;
  }
}
