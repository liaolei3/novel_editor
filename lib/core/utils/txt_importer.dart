import 'text_stats.dart';

/// TXT 导入切分（FR-24）。
///
/// 行首「第X卷/集/册」识别为卷、「第X章/回/话」识别为章，切分为
/// 卷→章两级结构，供书架导入预览确认后再落库。
class TxtImporter {
  TxtImporter._();

  static const String _numeral = r'[0-9零一二三四五六七八九十百千万两]';
  static const String _volumeChars = '卷集册';
  static const String _chapterChars = '章回话';

  // 标记行须以「第X + 卷/章类字」开头。附加标题部分不得含句末标点、整行不超过
  // 30 字，否则视为正文——挡住「第一章讲的是……」这类整句被误切成标题。
  static final RegExp _markPattern = RegExp(
    '^\\s*(第\\s*$_numeral+\\s*(?<kind>[$_volumeChars$_chapterChars])[^\\n]*)\$',
    multiLine: true,
  );
  static final RegExp _sentenceMarkPattern = RegExp(r'[。！？；.!?;]');
  static const int _maxTitleLength = 30;

  /// 切分为卷→章两级；无任何标记时整篇作为一卷一章。
  static ImportPreview parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n');
    final marks = _validMarks(text);
    if (marks.isEmpty) return _fallback(text);

    final volumes = <ImportVolume>[];
    final leading = <ImportChapter>[]; // 首个卷标记之前的序章 / 章
    final head = text.substring(0, marks.first.start).trim();
    if (head.isNotEmpty) leading.add(ImportChapter(title: '序章', body: head));

    ImportVolume? current;
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final title = m.group(1)!.trim();
      final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
      final body = text.substring(m.end, end).trim();

      if (_volumeChars.contains(m.namedGroup('kind')!)) {
        current = ImportVolume(name: title, chapters: []);
        volumes.add(current);
        // 卷标记后、首个章标记前的正文：作为该卷的「正文」章。
        if (body.isNotEmpty) {
          current.chapters.add(ImportChapter(title: '正文', body: body));
        }
      } else if (current == null) {
        leading.add(ImportChapter(title: title, body: body));
      } else {
        current.chapters.add(ImportChapter(title: title, body: body));
      }
    }

    if (volumes.isEmpty) {
      volumes.add(ImportVolume(name: '第一卷', chapters: leading));
    } else if (leading.isNotEmpty) {
      // 卷标记前的内容并入首个卷，置于该卷原有章之前。
      volumes.first.chapters.insertAll(0, leading);
    }
    // 无内容的空卷不落地，避免左侧出现空卷节点。
    volumes.removeWhere((v) => v.chapters.isEmpty);
    return ImportPreview(volumes: volumes.isEmpty ? _fallback(text).volumes : volumes);
  }

  static List<RegExpMatch> _validMarks(String text) => _markPattern
      .allMatches(text)
      .where((m) => _isPlausibleTitle(m.group(1)!.trim()))
      .toList();

  static bool _isPlausibleTitle(String line) =>
      line.length <= _maxTitleLength && !_sentenceMarkPattern.hasMatch(line);

  /// 无标记（或通篇只有卷名）时的兜底：整篇作一卷一章。
  static ImportPreview _fallback(String text) => ImportPreview(volumes: [
        ImportVolume(name: '第一卷', chapters: [
          ImportChapter(title: _firstLine(text), body: text.trim()),
        ]),
      ]);

  static String _firstLine(String text) {
    final idx = text.indexOf('\n');
    final line = idx < 0 ? text : text.substring(0, idx);
    final t = line.trim();
    return t.isEmpty ? '未命名章节' : (t.length > 50 ? t.substring(0, 50) : t);
  }
}

/// 导入切分结果：卷 → 章两级结构。
class ImportPreview {
  ImportPreview({required this.volumes});

  final List<ImportVolume> volumes;

  int get chapterCount => volumes.fold(0, (sum, v) => sum + v.chapters.length);
  int get volumeCount => volumes.length;
  int get charCount => volumes.fold(0, (sum, v) => sum + v.charCount);
}

class ImportVolume {
  ImportVolume({required this.name, required this.chapters});

  final String name;
  final List<ImportChapter> chapters;

  int get charCount => chapters.fold(0, (sum, c) => sum + c.charCount);
}

class ImportChapter {
  ImportChapter({required this.title, required this.body});

  final String title;
  final String body;

  int get charCount => TextStats.charCount(body);
}