/// 核心数据模型（对齐 PRD 第 8 节）。
library;

class Book {
  Book({
    required this.id,
    required this.title,
    this.penName = '',
    this.summary = '',
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.lastChapterId,
    this.lastCursor,
  });

  final String id;
  String title;
  String penName;
  String summary;
  DateTime createdAt;
  DateTime updatedAt;
  bool deleted;
  String? lastChapterId;
  int? lastCursor;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'pen_name': penName,
        'summary': summary,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted': deleted ? 1 : 0,
        'last_chapter_id': lastChapterId,
        'last_cursor': lastCursor,
      };

  static Book fromMap(Map<String, Object?> map) => Book(
        id: map['id'] as String,
        title: map['title'] as String,
        penName: (map['pen_name'] as String?) ?? '',
        summary: (map['summary'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        deleted: (map['deleted'] as int? ?? 0) == 1,
        lastChapterId: map['last_chapter_id'] as String?,
        lastCursor: map['last_cursor'] as int?,
      );
}

class Volume {
  Volume({
    required this.id,
    required this.bookId,
    required this.name,
    required this.sort,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  String name;
  int sort;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'name': name,
        'sort': sort,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static Volume fromMap(Map<String, Object?> map) => Volume(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        name: map['name'] as String,
        sort: map['sort'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}

class Chapter {
  Chapter({
    required this.id,
    required this.bookId,
    required this.volumeId,
    required this.title,
    this.content = '',
    this.outline = '',
    required this.sort,
    this.version = 1,
    this.charCount = 0,
    required this.lastEditedAt,
    this.cursorOffset = 0,
    this.pinned = false,
  });

  final String id;
  final String bookId;
  final String volumeId;
  String title;
  String content;
  String outline;
  int sort;
  int version;
  int charCount;
  DateTime lastEditedAt;
  int cursorOffset;
  bool pinned;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'volume_id': volumeId,
        'title': title,
        'content': content,
        'outline': outline,
        'sort': sort,
        'version': version,
        'char_count': charCount,
        'last_edited_at': lastEditedAt.millisecondsSinceEpoch,
        'cursor_offset': cursorOffset,
        'pinned': pinned ? 1 : 0,
      };

  static Chapter fromMap(Map<String, Object?> map) => Chapter(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        volumeId: map['volume_id'] as String,
        title: map['title'] as String,
        content: (map['content'] as String?) ?? '',
        outline: (map['outline'] as String?) ?? '',
        sort: map['sort'] as int,
        version: map['version'] as int? ?? 1,
        charCount: map['char_count'] as int? ?? 0,
        lastEditedAt:
            DateTime.fromMillisecondsSinceEpoch(map['last_edited_at'] as int),
        cursorOffset: map['cursor_offset'] as int? ?? 0,
        pinned: (map['pinned'] as int? ?? 0) == 1,
      );
}

enum SnapshotType { manual, auto, rollback }

class Snapshot {
  Snapshot({
    required this.id,
    required this.chapterId,
    required this.content,
    required this.createdAt,
    required this.type,
    required this.title,
  });

  final String id;
  final String chapterId;
  final String content;
  final DateTime createdAt;
  final SnapshotType type;
  final String title;

  Map<String, Object?> toMap() => {
        'id': id,
        'chapter_id': chapterId,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'type': type.name,
        'title': title,
      };

  static Snapshot fromMap(Map<String, Object?> map) => Snapshot(
        id: map['id'] as String,
        chapterId: map['chapter_id'] as String,
        content: map['content'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        type: SnapshotType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => SnapshotType.manual,
        ),
        title: (map['title'] as String?) ?? '',
      );
}

enum NoteType { role, world, idea }

class Note {
  Note({
    required this.id,
    required this.bookId,
    required this.type,
    required this.title,
    required this.content,
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  NoteType type;
  String title;
  String content;
  String tags;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'type': type.name,
        'title': title,
        'content': content,
        'tags': tags,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static Note fromMap(Map<String, Object?> map) => Note(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        type: NoteType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => NoteType.idea,
        ),
        title: map['title'] as String,
        content: (map['content'] as String?) ?? '',
        tags: (map['tags'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}

class WriteRecord {
  WriteRecord({
    required this.id,
    required this.date,
    required this.chars,
    required this.durationMs,
  });

  final String id;
  final DateTime date;
  int chars;
  int durationMs;

  Map<String, Object?> toMap() => {
        'id': id,
        'date': _dateKey(date),
        'chars': chars,
        'duration_ms': durationMs,
      };

  static WriteRecord fromMap(Map<String, Object?> map) => WriteRecord(
        id: map['id'] as String,
        date: DateTime.parse('${map['date']}'),
        chars: map['chars'] as int,
        durationMs: map['duration_ms'] as int,
      );

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String dateKeyOf(DateTime d) => _dateKey(d);
}

class RecycleItem {
  RecycleItem({
    required this.id,
    required this.type,
    required this.originId,
    required this.payload,
    required this.deletedAt,
    required this.expireAt,
  });

  final String id;
  final RecycleType type;
  final String originId;
  final String payload;
  final DateTime deletedAt;
  final DateTime expireAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'origin_id': originId,
        'payload': payload,
        'deleted_at': deletedAt.millisecondsSinceEpoch,
        'expire_at': expireAt.millisecondsSinceEpoch,
      };

  static RecycleItem fromMap(Map<String, Object?> map) => RecycleItem(
        id: map['id'] as String,
        type: RecycleType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => RecycleType.chapter,
        ),
        originId: map['origin_id'] as String,
        payload: map['payload'] as String,
        deletedAt:
            DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
        expireAt: DateTime.fromMillisecondsSinceEpoch(map['expire_at'] as int),
      );
}

enum RecycleType { volume, chapter, note }