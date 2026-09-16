import 'dart:convert';

import '../../data/models.dart';

/// 全局搜索范围。
enum SearchScope { content, outline, character, title }

/// 单个字段内的匹配集合。
class GlobalSearchFieldHit {
  const GlobalSearchFieldHit({
    required this.fieldLabel,
    required this.source,
    required this.starts,
  });

  /// 字段名，如「正文」「章纲」「名字」「外貌」「卷名」「章名」。
  final String fieldLabel;

  /// 字段完整文本（替换与摘要均基于它）。
  final String source;

  /// 全部匹配起点（大小写敏感）。
  final List<int> starts;

  int get count => starts.length;
}

/// 一条全局搜索命中：正文/章纲/标题为单字段；角色为一个角色聚合多字段。
class GlobalSearchHit {
  const GlobalSearchHit({
    required this.scope,
    required this.label,
    required this.fields,
    this.chapterId,
  });

  final SearchScope scope;

  /// 位置标签，如「第一卷 / 第一章」「林晚」「第一卷」。
  final String label;

  /// 命中字段列表（均至少含一处命中）。
  final List<GlobalSearchFieldHit> fields;

  /// 可跳转的章节 id（正文 / 章纲 / 章名命中）。
  final String? chapterId;

  int get count =>
      fields.fold(0, (sum, f) => sum + f.count);

  /// 元信息：单字段显示字段名，多字段显示「名字 等 N 个字段」。
  String get fieldLabel => fields.length == 1
      ? fields.first.fieldLabel
      : '${fields.first.fieldLabel} 等 ${fields.length} 个字段';
}

/// 全局搜索 / 替换核心逻辑（统一大小写敏感）。
class GlobalSearch {
  GlobalSearch._();

  /// 遍历全书执行搜索，返回按 正文 → 章纲 → 角色 → 标题 排序的命中列表。
  static List<GlobalSearchHit> search({
    required String query,
    required Set<SearchScope> scopes,
    required List<Chapter> chapters,
    required List<Volume> volumes,
    required List<Character> characters,
  }) {
    final hits = <GlobalSearchHit>[];
    if (query.isEmpty) return hits;
    final volName = {for (final v in volumes) v.id: v.name};
    String loc(Chapter c) {
      final v = volName[c.volumeId];
      return v == null ? c.title : '$v / ${c.title}';
    }

    if (scopes.contains(SearchScope.content)) {
      for (final c in chapters) {
        final plain = deltaPlainText(c.content);
        final starts = matchStarts(plain, query);
        if (starts.isNotEmpty) {
          hits.add(GlobalSearchHit(
            scope: SearchScope.content,
            label: loc(c),
            fields: [
              GlobalSearchFieldHit(
                  fieldLabel: '正文', source: plain, starts: starts)
            ],
            chapterId: c.id,
          ));
        }
      }
    }
    if (scopes.contains(SearchScope.outline)) {
      for (final c in chapters) {
        final starts = matchStarts(c.outline, query);
        if (starts.isNotEmpty) {
          hits.add(GlobalSearchHit(
            scope: SearchScope.outline,
            label: loc(c),
            fields: [
              GlobalSearchFieldHit(
                  fieldLabel: '章纲', source: c.outline, starts: starts)
            ],
            chapterId: c.id,
          ));
        }
      }
    }
    if (scopes.contains(SearchScope.character)) {
      // 以角色为单位聚合：一个角色一条命中，合并全部命中的字段。
      // 固定字段 + 自定义属性（属性名与属性值均参与匹配）。
      for (final c in characters) {
        final fieldHits = <GlobalSearchFieldHit>[];
        final fixed = <String, String>{
          '名字': c.name,
          '别名': c.aliases,
          '标签': c.tags,
        };
        for (final a in c.attrList) {
          fixed[a.name] = a.value;
        }
        for (final entry in fixed.entries) {
          final starts = matchStarts(entry.value, query);
          if (starts.isNotEmpty) {
            fieldHits.add(GlobalSearchFieldHit(
                fieldLabel: entry.key, source: entry.value, starts: starts));
          }
        }
        if (fieldHits.isNotEmpty) {
          hits.add(GlobalSearchHit(
            scope: SearchScope.character,
            label: c.name,
            fields: fieldHits,
          ));
        }
      }
    }
    if (scopes.contains(SearchScope.title)) {
      for (final v in volumes) {
        final starts = matchStarts(v.name, query);
        if (starts.isNotEmpty) {
          hits.add(GlobalSearchHit(
            scope: SearchScope.title,
            label: v.name,
            fields: [
              GlobalSearchFieldHit(
                  fieldLabel: '卷名', source: v.name, starts: starts)
            ],
          ));
        }
      }
      for (final c in chapters) {
        final starts = matchStarts(c.title, query);
        if (starts.isNotEmpty) {
          hits.add(GlobalSearchHit(
            scope: SearchScope.title,
            label: loc(c),
            fields: [
              GlobalSearchFieldHit(
                  fieldLabel: '章名', source: c.title, starts: starts)
            ],
            chapterId: c.id,
          ));
        }
      }
    }
    return hits;
  }

  /// 大小写敏感的全文匹配起点。
  static List<int> matchStarts(String source, String query) {
    if (source.isEmpty || query.isEmpty) return const [];
    final out = <int>[];
    var pos = 0;
    while (true) {
      final i = source.indexOf(query, pos);
      if (i < 0) break;
      out.add(i);
      pos = i + query.length;
    }
    return out;
  }

  /// Delta JSON → 纯文本（与 [replaceInDeltaJson] 的偏移口径一致：
  /// 文本 insert 直接拼接，嵌入对象不计入；非 Delta JSON 原样返回）。
  static String deltaPlainText(String deltaJson) {
    if (deltaJson.isEmpty) return '';
    final ops = _tryParseOps(deltaJson);
    if (ops == null) return deltaJson;
    final buf = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) buf.write(insert);
    }
    return buf.toString();
  }

  /// 在 Delta JSON 内做文本替换并保留富文本格式。
  /// 命中跨格式边界时拆分到各 op：首段写入替换词，其余段删除。
  /// 非 Delta JSON（旧纯文本）退化为纯文本替换。
  /// 返回 (新内容, 替换处数)。
  static (String, int) replaceInDeltaJson(
      String deltaJson, String query, String replacement) {
    if (deltaJson.isEmpty || query.isEmpty) return (deltaJson, 0);
    final ops = _tryParseOps(deltaJson);
    if (ops == null) return replaceInPlainText(deltaJson, query, replacement);

    // 记录每个文本 op 的 (op引用, 在全文中的起点)。
    final spans = <(Map, int)>[];
    final buf = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is! String) continue;
      spans.add((op, buf.length));
      buf.write(insert);
    }
    final plain = buf.toString();
    final starts = matchStarts(plain, query);
    if (starts.isEmpty) return (deltaJson, 0);

    // 倒序替换，保证未处理区段的偏移不失效。
    for (final s in starts.reversed) {
      final e = s + query.length;
      var first = true;
      for (final (op, start) in spans.reversed) {
        final text = op['insert'] as String;
        final end = start + text.length;
        if (end <= s || start >= e) continue;
        final ls = (s - start).clamp(0, text.length);
        final le = (e - start).clamp(0, text.length);
        op['insert'] = first
            ? '${text.substring(0, ls)}$replacement${text.substring(le)}'
            : '${text.substring(0, ls)}${text.substring(le)}';
        first = false;
      }
    }
    return (jsonEncode(ops), starts.length);
  }

  /// 纯文本替换。返回 (新文本, 替换处数)。
  static (String, int) replaceInPlainText(
      String text, String query, String replacement) {
    if (text.isEmpty || query.isEmpty) return (text, 0);
    final n = matchStarts(text, query).length;
    if (n == 0) return (text, 0);
    return (text.replaceAll(query, replacement), n);
  }

  /// 解析 Delta JSON 为 op 列表；不合法（旧纯文本）时返回 null。
  static List<Map>? _tryParseOps(String deltaJson) {
    try {
      final decoded = jsonDecode(deltaJson);
      if (decoded is! List) return null;
      return decoded.whereType<Map>().toList();
    } catch (_) {
      return null;
    }
  }
}
