/// 敏感词检测与替换（FR-26）。
///
/// 词库由词条（词 + 可选建议替换词）组成；检测只做提示、不强制屏蔽，
/// 替换保留富文本格式。匹配规则：中文逐字精确，英文字母忽略大小写。
library;

import 'dart:convert';

/// 词条：敏感词 + 建议替换词（空串表示仅提示，不参与自动替换）。
class SensitiveEntry {
  const SensitiveEntry({required this.word, this.suggestion = ''});

  final String word;
  final String suggestion;
}

/// 一次命中：区间（纯文本坐标，embed 记 1）+ 用于展示的上下文片段。
class SensitiveOccurrence {
  const SensitiveOccurrence({
    required this.start,
    required this.end,
    required this.before,
    required this.match,
    required this.after,
  });

  final int start;
  final int end;

  /// 上下文片段（换行与 embed 已做展示净化），命中词居中。
  final String before;
  final String match;
  final String after;
}

/// 按词聚合的命中结果。
class SensitiveMatch {
  SensitiveMatch({
    required this.word,
    required this.suggestion,
    required this.occurrences,
  });

  final String word;
  final String suggestion;
  final List<SensitiveOccurrence> occurrences;

  int get count => occurrences.length;
}

/// 敏感词扫描器：检测命中 + 生成替换结果。
class SensitiveWordScanner {
  SensitiveWordScanner(this.entries);

  final List<SensitiveEntry> entries;

  /// 导入解析：每行「词」或「词|建议词」（分隔符兼容 `|`、逗号、制表符），
  /// `#` 起首为注释行；去 BOM、按词忽略大小写去重。
  static List<SensitiveEntry> parseImport(String text) {
    final out = <SensitiveEntry>[];
    final seen = <String>{};
    for (var line in text.split(RegExp(r'[\r\n]+'))) {
      if (line.startsWith('\uFEFF')) line = line.substring(1);
      final s = line.trim();
      if (s.isEmpty || s.startsWith('#')) continue;
      final idx = s.indexOf(RegExp(r'[|\t,]'));
      final word = idx >= 0 ? s.substring(0, idx).trim() : s;
      final suggestion = idx >= 0 ? s.substring(idx + 1).trim() : '';
      if (word.isEmpty) continue;
      if (!seen.add(word.toLowerCase())) continue;
      out.add(SensitiveEntry(word: word, suggestion: suggestion));
    }
    return out;
  }

  /// 扫描 [text]，返回按词条顺序聚合的命中（无命中返回空列表）。
  List<SensitiveMatch> scan(String text, {int contextRadius = 12}) {
    if (text.isEmpty || entries.isEmpty) return const [];
    final folded = _foldAscii(text);
    final matches = <SensitiveMatch>[];
    for (final e in entries) {
      if (e.word.isEmpty) continue;
      final starts = _findStarts(folded, e.word);
      if (starts.isEmpty) continue;
      final occs = <SensitiveOccurrence>[];
      for (final s in starts) {
        final end = s + e.word.length;
        final ctxStart = (s - contextRadius).clamp(0, text.length);
        final ctxEnd = (end + contextRadius).clamp(0, text.length);
        occs.add(SensitiveOccurrence(
          start: s,
          end: end,
          before: _sanitize(text.substring(ctxStart, s)),
          match: _sanitize(text.substring(s, end)),
          after: _sanitize(text.substring(end, ctxEnd)),
        ));
      }
      matches.add(SensitiveMatch(
          word: e.word, suggestion: e.suggestion, occurrences: occs));
    }
    return matches;
  }

  /// 用各词自己的建议词替换 [deltaJson] 中的命中，保留富文本格式。
  /// 建议词为空的词跳过。返回 (新 JSON, 替换处数)。
  (String, int) replaceInDeltaJson(String deltaJson) {
    if (deltaJson.isEmpty || entries.isEmpty) return (deltaJson, 0);
    final ops = _tryParseOps(deltaJson);
    if (ops == null) return replacePlainText(deltaJson);

    // 记录每个 op 的起始位置（纯文本坐标，embed 记 1），并拼出匹配用文本。
    final spans = <(Map<String, Object?>, int)>[];
    final buf = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      spans.add((op, buf.length));
      buf.write(insert is String ? insert : '\uFFFC');
    }

    final hits = _collectReplaceSpans(buf.toString());
    if (hits.isEmpty) return (deltaJson, 0);
    // 逆序替换，避免前面的替换使后面区间位移。
    hits.sort((a, b) => b.start.compareTo(a.start));
    for (final hit in hits) {
      var first = true;
      for (final (op, start) in spans) {
        final data = op['insert'];
        if (data is! String) continue;
        final end = start + data.length;
        if (end <= hit.start || start >= hit.end) continue;
        final ls = (hit.start - start).clamp(0, data.length);
        final le = (hit.end - start).clamp(0, data.length);
        op['insert'] = first
            ? '${data.substring(0, ls)}${hit.replacement}${data.substring(le)}'
            : '${data.substring(0, ls)}${data.substring(le)}';
        first = false;
      }
    }
    return (jsonEncode(ops), hits.length);
  }

  /// 纯文本替换（内容不是合法 Delta JSON 时兜底）。
  (String, int) replacePlainText(String text) {
    if (text.isEmpty || entries.isEmpty) return (text, 0);
    final hits = _collectReplaceSpans(text);
    if (hits.isEmpty) return (text, 0);
    hits.sort((a, b) => a.start.compareTo(b.start));
    final buf = StringBuffer();
    var cursor = 0;
    var applied = 0;
    for (final hit in hits) {
      if (hit.start < cursor) continue; // 与前一次命中重叠，跳过。
      buf.write(text.substring(cursor, hit.start));
      buf.write(hit.replacement);
      cursor = hit.end;
      applied++;
    }
    buf.write(text.substring(cursor));
    return (buf.toString(), applied);
  }

  /// 收集所有可替换区间（跳过建议词为空的词），返回值按出现顺序。
  List<_ReplaceSpan> _collectReplaceSpans(String text) {
    final folded = _foldAscii(text);
    final hits = <_ReplaceSpan>[];
    for (final e in entries) {
      if (e.word.isEmpty || e.suggestion.isEmpty) continue;
      for (final s in _findStarts(folded, e.word)) {
        hits.add(_ReplaceSpan(s, s + e.word.length, e.suggestion));
      }
    }
    hits.sort((a, b) => a.start.compareTo(b.start));
    return hits;
  }

  /// 仅折叠 ASCII 大写字母为小写：中文不受影响且长度不变，便于位置映射。
  static String _foldAscii(String s) {
    final units = List<int>.of(s.codeUnits);
    var changed = false;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c >= 0x41 && c <= 0x5A) {
        units[i] = c + 0x20;
        changed = true;
      }
    }
    return changed ? String.fromCharCodes(units) : s;
  }

  /// [word] 在 [foldedText] 中的所有起点；[foldedText] 必须与原文等长。
  static List<int> _findStarts(String foldedText, String word) {
    if (word.isEmpty) return const [];
    final foldedWord = _foldAscii(word);
    final starts = <int>[];
    var from = 0;
    while (true) {
      final idx = foldedText.indexOf(foldedWord, from);
      if (idx < 0) break;
      starts.add(idx);
      from = idx + foldedWord.length;
    }
    return starts;
  }

  static String _sanitize(String s) =>
      s.replaceAll('\n', ' ').replaceAll('\uFFFC', '');

  static List<Map<String, Object?>>? _tryParseOps(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      final ops = <Map<String, Object?>>[];
      for (final item in decoded) {
        if (item is! Map) return null;
        final op = Map<String, Object?>.from(item);
        if (!op.containsKey('insert')) return null;
        ops.add(op);
      }
      return ops;
    } catch (_) {
      return null;
    }
  }
}

class _ReplaceSpan {
  const _ReplaceSpan(this.start, this.end, this.replacement);

  final int start;
  final int end;
  final String replacement;
}