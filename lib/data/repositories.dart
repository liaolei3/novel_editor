import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:math';

import '../core/utils/rich_text_codec.dart';
import 'db.dart';
import 'models.dart';

String newId() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String contentHash(String content) => md5.convert(utf8.encode(content)).toString();

class BookRepository {
  Future<List<Book>> listAll() async {
    final db = await Db.instance();
    final rows = await db.query('books',
        where: 'deleted = 0', orderBy: 'updated_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<Book> create(String title, {String penName = ''}) async {
    final now = DateTime.now();
    final book = Book(id: newId(), title: title, penName: penName,
        createdAt: now, updatedAt: now);
    final db = await Db.instance();
    await db.insert('books', book.toMap());
    return book;
  }

  Future<void> rename(String id, String title) => _update(id, {'title': title});

  Future<void> updateMeta(String id, String penName, String summary) =>
      _update(id, {'pen_name': penName, 'summary': summary});

  Future<void> saveLocation(String id, String? chapterId, int? cursor) =>
      _update(id, {'last_chapter_id': chapterId, 'last_cursor': cursor});

  Future<void> touch(String id) =>
      _update(id, {'updated_at': DateTime.now().millisecondsSinceEpoch});

  Future<void> _update(String id, Map<String, Object?> data) async {
    final db = await Db.instance();
    await db.update('books', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> softDelete(String id) async {
    final db = await Db.instance();
    await db.update('books', {'deleted': 1},
        where: 'id = ?', whereArgs: [id]);
  }
}

class VolumeRepository {
  Future<List<Volume>> listByBook(String bookId) async {
    final db = await Db.instance();
    final rows = await db.query('volumes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'sort ASC');
    return rows.map(Volume.fromMap).toList();
  }

  Future<Volume> create(String bookId, String name, {int? sort}) async {
    final db = await Db.instance();
    final count = await db.rawQuery('SELECT COUNT(*) c FROM volumes WHERE book_id = ?',
            [bookId]).then((r) => (r.first['c'] as int?) ?? 0);
    final s = sort ?? count;
    final now = DateTime.now();
    final vol = Volume(
        id: newId(), bookId: bookId, name: name, sort: s,
        createdAt: now, updatedAt: now);
    await db.insert('volumes', vol.toMap());
    return vol;
  }

  Future<void> rename(String id, String name) async {
    final db = await Db.instance();
    await db.update('volumes', {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorder(String bookId, List<String> orderedIds) async {
    final db = await Db.instance();
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('volumes', {'sort': i},
          where: 'id = ? AND book_id = ?', whereArgs: [orderedIds[i], bookId]);
    }
    await batch.commit(noResult: true);
  }
}

class ChapterRepository {
  Future<List<Chapter>> listByBook(String bookId) async {
    final db = await Db.instance();
    final rows = await db.query('chapters',
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'pinned DESC, sort ASC');
    return rows.map(Chapter.fromMap).toList();
  }

  Future<Chapter?> get(String id) async {
    final db = await Db.instance();
    final rows = await db.query('chapters', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Chapter.fromMap(rows.first);
  }

  Future<Chapter> create({
    required String bookId,
    required String volumeId,
    required String title,
    String content = '',
    String outline = '',
    int? sort,
    bool pinned = false,
  }) async {
    final db = await Db.instance();
    final count = await db
        .rawQuery('SELECT COUNT(*) c FROM chapters WHERE volume_id = ?',
            [volumeId])
        .then((r) => (r.first['c'] as int?) ?? 0);
    final s = sort ?? count;
    final ch = Chapter(
      id: newId(),
      bookId: bookId,
      volumeId: volumeId,
      title: title,
      content: content,
      outline: outline,
      sort: s,
      charCount: _countChars(content),
      lastEditedAt: DateTime.now(),
      pinned: pinned,
    );
    await db.insert('chapters', ch.toMap());
    return ch;
  }

  Future<void> updateContent(Chapter chapter) async {
    final db = await Db.instance();
    chapter
      ..charCount = _countChars(chapter.content)
      ..version = chapter.version + 1
      ..lastEditedAt = DateTime.now();
    await db.update('chapters', chapter.toMap(),
        where: 'id = ?', whereArgs: [chapter.id]);
  }

  Future<void> updateTitle(String id, String title) =>
      _patch(id, {'title': title});

  Future<void> updateOutline(String id, String outline) =>
      _patch(id, {'outline': outline});

  Future<void> updateCursor(String id, int offset) =>
      _patch(id, {'cursor_offset': offset});

  Future<void> setPinned(String id, bool pinned) =>
      _patch(id, {'pinned': pinned ? 1 : 0});

  Future<void> reorder(String volumeId, List<String> orderedIds) async {
    final db = await Db.instance();
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('chapters', {'sort': i},
          where: 'id = ? AND volume_id = ?',
          whereArgs: [orderedIds[i], volumeId]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> hardDelete(String id) async {
    final db = await Db.instance();
    await db.delete('snapshots', where: 'chapter_id = ?', whereArgs: [id]);
    await db.delete('chapters', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _patch(String id, Map<String, Object?> data) async {
    final db = await Db.instance();
    await db.update('chapters', data, where: 'id = ?', whereArgs: [id]);
  }

  static int _countChars(String content) {
    final plain = RichTextCodec.plainTextFromDeltaJson(content);
    var n = 0;
    for (final rune in plain.runes) {
      final ch = String.fromCharCode(rune);
      if (ch.trim().isNotEmpty) n++;
    }
    return n;
  }
}

class SnapshotRepository {
  Future<List<Snapshot>> listByChapter(String chapterId) async {
    final db = await Db.instance();
    final rows = await db.query('snapshots',
        where: 'chapter_id = ?', whereArgs: [chapterId],
        orderBy: 'created_at DESC');
    return rows.map(Snapshot.fromMap).toList();
  }

  Future<Snapshot> add(SnapshotType type, Chapter chapter) async {
    final db = await Db.instance();
    final now = DateTime.now();
    final snap = Snapshot(
      id: newId(),
      chapterId: chapter.id,
      content: chapter.content,
      createdAt: now,
      type: type,
      title: '${_typeLabel(type)} ${now.month}/${now.day} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    );
    await db.insert('snapshots', snap.toMap());
    await _trim(db, chapter.id);
    return snap;
  }

  Future<void> delete(String id) async {
    final db = await Db.instance();
    await db.delete('snapshots', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _trim(Database db, String chapterId) async {
    final rows = await db.query('snapshots',
        columns: ['id'],
        where: 'chapter_id = ?',
        whereArgs: [chapterId],
        orderBy: 'created_at DESC',
        limit: 1000);
    if (rows.length <= 50) return;
    final stale = rows.skip(50).map((r) => r['id'] as String).toList();
    for (final id in stale) {
      await db.delete('snapshots', where: 'id = ?', whereArgs: [id]);
    }
  }

  static String _typeLabel(SnapshotType type) =>
      switch (type) { SnapshotType.manual => '手动', SnapshotType.auto => '自动', SnapshotType.rollback => '回滚前' };
}

class NoteRepository {
  Future<List<Note>> listByBook(String bookId, {NoteType? type}) async {
    final db = await Db.instance();
    final rows = await db.query('notes',
        where: type == null ? 'book_id = ?' : 'book_id = ? AND type = ?',
        whereArgs: type == null ? [bookId] : [bookId, type.name],
        orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Note> create({
    required String bookId,
    required NoteType type,
    required String title,
    String content = '',
  }) async {
    final now = DateTime.now();
    final note = Note(
        id: newId(), bookId: bookId, type: type, title: title,
        content: content, createdAt: now, updatedAt: now);
    final db = await Db.instance();
    await db.insert('notes', note.toMap());
    return note;
  }

  Future<void> update(Note note) async {
    note.updatedAt = DateTime.now();
    final db = await Db.instance();
    await db.update('notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> hardDelete(String id) async {
    final db = await Db.instance();
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

class CharacterRepository {
  Future<List<Character>> listByBook(String bookId) async {
    final db = await Db.instance();
    final rows = await db.query('characters',
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'created_at DESC');
    return rows.map(Character.fromMap).toList();
  }

  Future<Character> create({
    required String bookId,
    required String name,
  }) async {
    final now = DateTime.now();
    final char = Character(
        id: newId(), bookId: bookId, name: name,
        createdAt: now, updatedAt: now);
    final db = await Db.instance();
    await db.insert('characters', char.toMap());
    return char;
  }

  Future<void> update(Character char) async {
    char.updatedAt = DateTime.now();
    final db = await Db.instance();
    await db.update('characters', char.toMap(),
        where: 'id = ?', whereArgs: [char.id]);
  }

  Future<Character?> get(String id) async {
    final db = await Db.instance();
    final rows = await db.query('characters',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Character.fromMap(rows.first);
  }

  Future<void> hardDelete(String id) async {
    final db = await Db.instance();
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }
}

class StatsRepository {
  Future<WriteRecord> today() async {
    final key = WriteRecord.dateKeyOf(DateTime.now());
    final db = await Db.instance();
    final rows = await db.query('write_records',
        where: 'date = ?', whereArgs: [key]);
    if (rows.isNotEmpty) return WriteRecord.fromMap(rows.first);
    final rec = WriteRecord(
        id: newId(), date: DateTime.now(), chars: 0, durationMs: 0);
    await db.insert('write_records', rec.toMap());
    return rec;
  }

  Future<void> addChars(int delta, {int durationMs = 0}) async {
    if (delta == 0 && durationMs == 0) return;
    final rec = await today();
    rec.chars += delta > 0 ? delta : 0;
    rec.durationMs += durationMs;
    final db = await Db.instance();
    await db.update('write_records', rec.toMap(),
        where: 'id = ?', whereArgs: [rec.id]);
  }

  /// 最近 [days] 天的记录（旧→新）。
  Future<List<WriteRecord>> recent(int days) async {
    final db = await Db.instance();
    final from = DateTime.now().subtract(Duration(days: days - 1));
    final fromKey = WriteRecord.dateKeyOf(from);
    final rows = await db.query('write_records',
        where: 'date >= ?', whereArgs: [fromKey], orderBy: 'date ASC');
    final byKey = {for (final r in rows.map(WriteRecord.fromMap)) WriteRecord.dateKeyOf(r.date): r};
    final out = <WriteRecord>[];
    for (var i = 0; i < days; i++) {
      final d = from.add(Duration(days: i));
      final key = WriteRecord.dateKeyOf(d);
      out.add(byKey[key] ??
          WriteRecord(id: 'empty-$i', date: d, chars: 0, durationMs: 0));
    }
    return out;
  }

  Future<void> purgeEmpty() async {
    final db = await Db.instance();
    await db.delete('write_records', where: 'chars = 0 AND duration_ms = 0');
  }
}

class RecycleRepository {
  Future<List<RecycleItem>> list() async {
    final db = await Db.instance();
    final rows = await db.query('recycle_bin', orderBy: 'deleted_at DESC');
    return rows.map(RecycleItem.fromMap).toList();
  }

  Future<void> add(RecycleType type, String originId, Map<String, Object?> payload) async {
    final now = DateTime.now();
    final item = RecycleItem(
      id: newId(),
      type: type,
      originId: originId,
      payload: jsonEncode(payload),
      deletedAt: now,
      expireAt: now.add(const Duration(days: 30)),
    );
    final db = await Db.instance();
    await db.insert('recycle_bin', item.toMap());
  }

  Future<void> remove(String id) async {
    final db = await Db.instance();
    await db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> purgeExpired() async {
    final db = await Db.instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query('recycle_bin',
        where: 'expire_at < ?', whereArgs: [now]);
    for (final row in rows.map(RecycleItem.fromMap)) {
      if (row.type == RecycleType.chapter) {
        await db.delete('snapshots',
            where: 'chapter_id = ?', whereArgs: [row.originId]);
      }
      await db.delete('recycle_bin', where: 'id = ?', whereArgs: [row.id]);
    }
  }
}