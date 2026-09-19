import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite 连接与建表（桌面端走 ffi，移动端走 sqflite）。
class Db {
  Db._();

  static Database? _db;
  static String? _resolvedRoot;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = p.join(await supportDir(), 'novel_editor.db');
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        pen_name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        last_chapter_id TEXT,
        last_cursor INTEGER,
        cover_path TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE volumes (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        volume_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        outline TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        char_count INTEGER NOT NULL DEFAULT 0,
        last_edited_at INTEGER NOT NULL,
        cursor_offset INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (book_id) REFERENCES books(id),
        FOREIGN KEY (volume_id) REFERENCES volumes(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_chapters_book ON chapters(book_id, volume_id, sort)');
    await db.execute('''
      CREATE TABLE snapshots (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('CREATE INDEX idx_snap_chapter ON snapshots(chapter_id, created_at)');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE write_records (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        chars INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_wr_date ON write_records(date)');
    await db.execute('''
      CREATE TABLE recycle_bin (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        origin_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        expire_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_state (
        entity_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        local_version INTEGER NOT NULL,
        cloud_version INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL DEFAULT '',
        dirty INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE characters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        aliases TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'other',
        gender TEXT NOT NULL DEFAULT 'male',
        attributes TEXT NOT NULL DEFAULT '',
        avatar TEXT NOT NULL DEFAULT '',
        color TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_characters_book ON characters(book_id)');
    await db.execute('''
      CREATE TABLE foreshadowings (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        remark TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'undone',
        sort INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_foreshadow_book ON foreshadowings(book_id)');
    await db.execute('''
      CREATE TABLE fs_segments (
        id TEXT PRIMARY KEY,
        fs_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        excerpt TEXT NOT NULL DEFAULT '',
        remark TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_fsseg_fs ON fs_segments(fs_id)');
  }

  /// 增量迁移。
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      final cols = await db.rawQuery('PRAGMA table_info(books)');
      final hasCol = cols.any((c) => c['name'] == 'cover_path');
      if (!hasCol) {
        await db.execute("ALTER TABLE books ADD COLUMN cover_path TEXT NOT NULL DEFAULT ''");
      }
    }
    if (oldVersion < 5) {
      final cols = await db.rawQuery('PRAGMA table_info(characters)');
      final hasCol = cols.any((c) => c['name'] == 'attributes');
      if (!hasCol) {
        await db.execute(
            "ALTER TABLE characters ADD COLUMN attributes TEXT NOT NULL DEFAULT ''");
      }
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS foreshadowings (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          remark TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'undone',
          sort INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_foreshadow_book ON foreshadowings(book_id)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS fs_segments (
          id TEXT PRIMARY KEY,
          fs_id TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          excerpt TEXT NOT NULL DEFAULT '',
          remark TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_fsseg_fs ON fs_segments(fs_id)');
    }
  }

  /// 数据存储根目录（数据库 / 备份 / 配置 / 崩溃标记）。
  /// 优先级：exe 旁指针文件 > 默认目录 config.json 的 dataDir > 应用默认目录。
  static Future<String> supportDir() async {
    if (_resolvedRoot != null) return _resolvedRoot!;
    final fallback = (await getApplicationSupportDirectory()).path;
    String? root = await _rootFromPointer();
    root ??= await _rootFromConfig(fallback);
    if (root != null) {
      try {
        final dir = Directory(root);
        if (!dir.existsSync()) await dir.create(recursive: true);
      } catch (_) {
        root = null; // 自定义目录不可用时回退默认目录。
      }
    }
    root ??= fallback;
    _resolvedRoot = root;
    return root;
  }

  static Future<String?> _rootFromPointer() async {
    try {
      final pf = _pointerFile();
      if (!pf.existsSync()) return null;
      final saved = pf.readAsStringSync().trim();
      return saved.isEmpty ? null : saved;
    } catch (_) {
      return null;
    }
  }

  /// exe 目录不可写导致指针缺失时，从默认目录 config.json 兜底。
  static Future<String?> _rootFromConfig(String dir) async {
    try {
      final f = File(p.join(dir, 'config.json'));
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map) {
        final v = decoded['dataDir'];
        if (v is String && v.isNotEmpty) return v;
      }
    } catch (_) {}
    return null;
  }

  /// 应用默认数据目录（未设置自定义目录时使用）。
  static Future<String> defaultDir() async =>
      (await getApplicationSupportDirectory()).path;

  /// exe 同目录下的指针文件，记录当前数据目录。
  static File _pointerFile() => File(
      p.join(p.dirname(Platform.resolvedExecutable), 'novel_editor.data_dir'));

  /// 切换存储目录时立即写入指针文件。
  static Future<void> anchorDataDir(String dir) async {
    try {
      await _pointerFile().writeAsString(dir, flush: true);
    } catch (_) {
      // exe 目录不可写时忽略，由 config.json 的 dataDir 兜底。
    }
  }

  /// 将当前数据库与备份迁移到目标目录（VACUUM INTO 生成一致性副本，主库不动）。
  /// 目标目录已有 novel_editor.db 时会抛出异常，由调用方先行判断。
  static Future<void> migrateDataTo(String targetDir) async {
    final dir = Directory(targetDir);
    if (!dir.existsSync()) await dir.create(recursive: true);
    final targetDb = p.join(targetDir, 'novel_editor.db');
    if (File(targetDb).existsSync()) {
      throw StateError('目标目录已存在 novel_editor.db');
    }
    final db = await instance();
    final safePath = targetDb.replaceAll("'", "''");
    await db.execute("VACUUM INTO '$safePath'");
    try {
      final src = Directory(p.join(await supportDir(), 'backups'));
      if (src.existsSync()) {
        await _copyDirectory(src, Directory(p.join(targetDir, 'backups')));
      }
    } catch (_) {
      // 备份迁移尽力而为，失败不影响主库迁移。
    }
  }

  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(recursive: true)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: src.path);
      final target = File(p.join(dst.path, rel));
      await target.parent.create(recursive: true);
      await e.copy(target.path);
    }
  }
}