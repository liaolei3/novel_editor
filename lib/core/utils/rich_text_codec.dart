import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// 富文本编解码工具。
///
/// 项目持久化层（SQLite `chapters.content` / `snapshots.content`）以字符串存储
/// 文档内容。引入 flutter_quill 后，正文内容改为存储 **Quill Delta JSON**
/// （形如 `[{"insert":"文本\n"}]` 的数组）。
///
/// 为兼容旧数据（纯文本章节），所有读取方均通过 [plainTextFromDeltaJson]
/// 容错解码：非 Delta JSON 的字符串原样当作纯文本返回。
class RichTextCodec {
  RichTextCodec._();

  /// 空文档 Delta JSON（一个空段落）。
  static String emptyDeltaJson() => '[{"insert":"\\n"}]';

  /// 纯文本 → Delta JSON 字符串。
  static String deltaJsonFromPlainText(String plain) {
    if (plain.isEmpty) return emptyDeltaJson();
    var p = plain;
    if (!p.endsWith('\n')) p = '$p\n';
    final delta = Delta()..insert(p);
    return jsonEncode(delta.toJson());
  }

  /// Delta JSON 字符串 → 纯文本。
  ///
  /// 容错：若 [s] 不是合法 Delta JSON（例如旧的纯文本章节），原样返回。
  static String plainTextFromDeltaJson(String s) {
    if (s.isEmpty) return '';
    try {
      final json = jsonDecode(s);
      if (json is! List) return s;
      final doc = Document.fromJson(json);
      return doc.toPlainText();
    } catch (_) {
      return s;
    }
  }

  /// 从 content（Delta JSON 或旧纯文本）构造 [Document]。
  static Document documentFromContent(String content) {
    if (content.isEmpty) {
      return Document.fromJson(jsonDecode(emptyDeltaJson()) as List<dynamic>);
    }
    try {
      final json = jsonDecode(content);
      if (json is! List) throw const FormatException('not delta json');
      return Document.fromJson(json);
    } catch (_) {
      var p = content;
      if (!p.endsWith('\n')) p = '$p\n';
      return Document.fromDelta(Delta()..insert(p));
    }
  }

  /// 判断字符串是否为合法 Delta JSON。
  static bool isDeltaJson(String s) {
    if (s.isEmpty) return false;
    try {
      return jsonDecode(s) is List;
    } catch (_) {
      return false;
    }
  }
}