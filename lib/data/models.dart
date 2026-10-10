/// 核心数据模型（对齐 PRD 第 8 节）。
library;

import 'dart:convert';

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
    this.coverPath = '',
    this.goal = 0,
    this.chapterGoal = 0,
    this.goalNotified = false,
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

  /// 封面图片相对数据目录的路径（如 'covers/xxx.png'），空 = 未设置。
  String coverPath;

  /// 整书累计字数目标（0 = 未设置/关闭）。
  int goal;

  /// 全书统一的单章累计字数目标（0 = 未设置/关闭），章节可用自身 goal 覆盖。
  int chapterGoal;

  /// 整书目标是否已提示达成。
  bool goalNotified;

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
        'cover_path': coverPath,
        'goal': goal,
        'chapter_goal': chapterGoal,
        'goal_notified': goalNotified ? 1 : 0,
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
        coverPath: (map['cover_path'] as String?) ?? '',
        goal: (map['goal'] as int?) ?? 0,
        chapterGoal: (map['chapter_goal'] as int?) ?? 0,
        goalNotified: (map['goal_notified'] as int? ?? 0) == 1,
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
    this.outlineEditedAt,
    this.goal,
    this.goalNotified = false,
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

  /// 大纲最后修改时间（null = 从未编辑过大纲）。
  DateTime? outlineEditedAt;

  /// 单章累计字数目标三态：null = 跟随全书默认；0 = 关闭；>0 = 自定义。
  int? goal;

  /// 本章目标是否已提示达成。
  bool goalNotified;

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
        'outline_edited_at': outlineEditedAt?.millisecondsSinceEpoch,
        'goal': goal,
        'goal_notified': goalNotified ? 1 : 0,
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
        outlineEditedAt: map['outline_edited_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                map['outline_edited_at'] as int),
        goal: map['goal'] as int?,
        goalNotified: (map['goal_notified'] as int? ?? 0) == 1,
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
    this.idleMs = 0,
    this.idleCount = 0,
    this.goalNotified = false,
  });

  final String id;
  final DateTime date;
  int chars;
  int durationMs;
  int idleMs;
  int idleCount;

  /// 当日目标是否已提示达成。
  bool goalNotified;

  Map<String, Object?> toMap() => {
        'id': id,
        'date': _dateKey(date),
        'chars': chars,
        'duration_ms': durationMs,
        'idle_ms': idleMs,
        'idle_count': idleCount,
        'goal_notified': goalNotified ? 1 : 0,
      };

  static WriteRecord fromMap(Map<String, Object?> map) => WriteRecord(
        id: map['id'] as String,
        date: DateTime.parse('${map['date']}'),
        chars: map['chars'] as int,
        durationMs: map['duration_ms'] as int,
        idleMs: (map['idle_ms'] as int?) ?? 0,
        idleCount: (map['idle_count'] as int?) ?? 0,
        goalNotified: (map['goal_notified'] as int? ?? 0) == 1,
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

enum CharacterType { protagonist, supporting, antagonist }

enum Gender { male, female }

/// 角色自定义属性：用户自行指定属性名与值。
class CharacterAttribute {
  CharacterAttribute({required this.name, this.value = ''});

  String name;
  String value;

  Map<String, Object?> toJson() => {'name': name, 'value': value};

  static CharacterAttribute fromJson(Map<String, Object?> json) =>
      CharacterAttribute(
        name: (json['name'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
      );
}

/// 解析 characters.attributes JSON 文本；非法内容容错返回空列表。
List<CharacterAttribute> parseCharacterAttributes(String raw) {
  if (raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<Object?>;
    return [
      for (final item in list)
        if (item is Map<String, Object?>)
          CharacterAttribute.fromJson(item)
        else if (item is Map)
          CharacterAttribute.fromJson(Map<String, Object?>.from(item)),
    ];
  } catch (_) {
    return [];
  }
}

/// 将属性列表编码为 JSON 文本（空列表编码为空字符串）。
String encodeCharacterAttributes(List<CharacterAttribute> list) {
  if (list.isEmpty) return '';
  return jsonEncode([for (final a in list) a.toJson()]);
}

class Character {
  Character({
    required this.id,
    required this.bookId,
    required this.name,
    this.aliases = '',
    this.type = CharacterType.protagonist,
    this.gender = Gender.male,
    this.attributes = '',
    this.avatar = '',
    this.color = '',
    this.tags = '',
    this.sort = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  String name;
  String aliases;
  CharacterType type;
  Gender gender;

  /// 自定义属性列表的 JSON 文本，格式 [{"name":"...","value":"..."}]。
  String attributes;
  String avatar;
  String color;
  String tags;
  int sort;
  DateTime createdAt;
  DateTime updatedAt;

  List<CharacterAttribute> get attrList => parseCharacterAttributes(attributes);
  set attrList(List<CharacterAttribute> list) =>
      attributes = encodeCharacterAttributes(list);

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'name': name,
        'aliases': aliases,
        'type': type.name,
        'gender': gender.name,
        'attributes': attributes,
        'avatar': avatar,
        'color': color,
        'tags': tags,
        'sort': sort,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static Character fromMap(Map<String, Object?> map) => Character(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        name: (map['name'] as String?) ?? '',
        aliases: (map['aliases'] as String?) ?? '',
        type: CharacterType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => CharacterType.protagonist,
        ),
        gender: Gender.values.firstWhere(
          (g) => g.name == map['gender'],
          orElse: () => Gender.male,
        ),
        attributes: (map['attributes'] as String?) ?? '',
        avatar: (map['avatar'] as String?) ?? '',
        color: (map['color'] as String?) ?? '',
        tags: (map['tags'] as String?) ?? '',
        sort: (map['sort'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}

enum ForeshadowStatus { undone, done }

class Foreshadow {
  Foreshadow({
    required this.id,
    required this.bookId,
    this.name = '',
    this.content = '',
    this.status = ForeshadowStatus.undone,
    this.sort = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String bookId;
  String name;

  /// 伏笔内容（铺垫/回收计划），存 foreshadowings.remark 列，必填。
  String content;
  ForeshadowStatus status;
  int sort;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'name': name,
        'remark': content,
        'status': status.name,
        'sort': sort,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static Foreshadow fromMap(Map<String, Object?> map) => Foreshadow(
        id: map['id'] as String,
        bookId: map['book_id'] as String,
        name: (map['name'] as String?) ?? '',
        content: (map['remark'] as String?) ?? '',
        status: ForeshadowStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => ForeshadowStatus.undone,
        ),
        sort: (map['sort'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}

/// 伏笔与正文的一次关联（一个剧情片段）。
/// 正文 Delta 以内联属性 fsid=片段id 标注对应文字。
class ForeshadowSegment {
  ForeshadowSegment({
    required this.id,
    required this.fsId,
    required this.chapterId,
    this.excerpt = '',
    this.remark = '',
    required this.createdAt,
  });

  final String id;

  /// 所属伏笔 id。
  final String fsId;

  /// 片段所在章节 id；章节被删除后记录保留（失锚状态）。
  final String chapterId;

  /// 标注文字快照：正文删改后仍可在面板中识别片段内容。
  String excerpt;
  String remark;
  DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'fs_id': fsId,
        'chapter_id': chapterId,
        'excerpt': excerpt,
        'remark': remark,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static ForeshadowSegment fromMap(Map<String, Object?> map) =>
      ForeshadowSegment(
        id: map['id'] as String,
        fsId: map['fs_id'] as String,
        chapterId: map['chapter_id'] as String,
        excerpt: (map['excerpt'] as String?) ?? '',
        remark: (map['remark'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

enum RecycleType { volume, chapter, note, character, foreshadow, book }

/// 敏感词词条（全局共享，不隶属单本书）。
class SensitiveWord {
  SensitiveWord({
    required this.id,
    required this.word,
    this.suggestion = '',
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String word;

  /// 一键替换的目标词；空串表示仅提示、不参与自动替换。
  String suggestion;
  bool enabled;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'word': word,
        'suggestion': suggestion,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static SensitiveWord fromMap(Map<String, Object?> map) => SensitiveWord(
        id: map['id'] as String,
        word: (map['word'] as String?) ?? '',
        suggestion: (map['suggestion'] as String?) ?? '',
        enabled: (map['enabled'] as int? ?? 1) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}