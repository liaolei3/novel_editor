/// TXT 批量导入切章（FR-24）。
///
/// 按"第X章 / 第X节 / 第X回 / 卷"规则自动切分为章节。
class TxtImporter {
  TxtImporter._();

  static final RegExp chapterPattern = RegExp(
    r'^\s*(第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章节回节卷部篇][^\n]*)$',
    multiLine: true,
  );

  /// 切分结果：每个元素为 (标题, 正文)。
  static List<MapEntry<String, String>> splitChapters(String raw) {
    final text = raw.replaceAll('\r\n', '\n');
    final matches = chapterPattern.allMatches(text).toList();
    final result = <MapEntry<String, String>>[];

    if (matches.isEmpty) {
      final title = _firstLine(text);
      result.add(MapEntry(title, text));
      return result;
    }

    if (matches.first.start > 0) {
      final prologue = text.substring(0, matches.first.start).trim();
      if (prologue.isNotEmpty) {
        result.add(MapEntry('序章', prologue));
      }
    }

    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final start = m.start;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final block = text.substring(start, end);
      final titleEnd = block.indexOf('\n');
      final title = (titleEnd < 0 ? block : block.substring(0, titleEnd)).trim();
      final body = titleEnd < 0 ? '' : block.substring(titleEnd + 1).trim();
      result.add(MapEntry(title, body));
    }
    return result;
  }

  static String _firstLine(String text) {
    final idx = text.indexOf('\n');
    final line = idx < 0 ? text : text.substring(0, idx);
    final t = line.trim();
    return t.isEmpty ? '未命名章节' : (t.length > 50 ? t.substring(0, 50) : t);
  }
}