import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../services/logger.dart';

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
    } catch (e) {
      Logger.warn('章节内容解码为纯文本失败（长度 ${s.length}）',
          error: e, tag: 'RichText');
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
    } catch (e) {
      Logger.warn('章节内容构造文档失败，降级为纯文本（长度 ${content.length}）',
          error: e, tag: 'RichText');
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

  /// 将 Delta 在纯文本偏移 [offset] 处切分为（前段, 后段），用于「一键分章」。
  ///
  /// 坐标规则与编辑器选区一致：每个字符（含 '\n'）记 1，embed 记 1。
  /// - 前段保证以 '\n' 结尾：切点停在段落中间时补一个换行，其块属性取
  ///   切点之后第一个换行所在段落的块属性（原段落样式留在原章节）；
  /// - 后段去掉紧随切点的一个 '\n'（光标停在段尾时避免新章节出现空行）。
  static (Delta, Delta) splitDelta(Delta delta, int offset) {
    final head = Delta();
    final tail = Delta();
    var pos = 0;
    for (final op in delta.operations) {
      final text = op.data is String ? op.data as String : null;
      final len = text?.length ?? 1; // embed 记 1 字符，不可拆分
      if (pos >= offset) {
        tail.push(op);
      } else if (pos + len <= offset) {
        head.push(op);
      } else {
        final cut = offset - pos;
        if (text != null) {
          head.push(Operation.insert(text.substring(0, cut), op.attributes));
          tail.push(Operation.insert(text.substring(cut), op.attributes));
        } else {
          head.push(op);
        }
      }
      pos += len;
    }

    // 前段末尾补换行（切点停在段中间时），块属性取切点后第一个换行所在段落。
    var headEndsWithNewline = false;
    for (final op in head.operations.reversed) {
      final text = op.data is String ? op.data as String : null;
      headEndsWithNewline = text != null && text.endsWith('\n');
      break; // 只看最后一个 op（embed 视作未以换行结尾）
    }
    if (!headEndsWithNewline) {
      Map<String, dynamic>? blockAttrs;
      for (final op in tail.operations) {
        final text = op.data is String ? op.data as String : null;
        if (text != null && text.contains('\n')) {
          blockAttrs = op.attributes;
          break;
        }
      }
      head.push(Operation.insert('\n', blockAttrs));
    }

    // 后段去掉紧随切点的一个换行。
    if (tail.operations.isNotEmpty) {
      final first = tail.operations.first;
      final text = first.data is String ? first.data as String : null;
      if (text != null && text.startsWith('\n')) {
        final trimmed = Delta();
        if (text.length > 1) {
          trimmed.push(Operation.insert(text.substring(1), first.attributes));
        }
        for (var i = 1; i < tail.operations.length; i++) {
          trimmed.push(tail.operations[i]);
        }
        return (head, trimmed);
      }
    }
    return (head, tail);
  }

  /// 判断纯文本偏移 [offset] 之后是否还有非空白内容
  /// （编辑器右键「一键分章」菜单的可见性依据）。
  static bool hasContentAfter(Delta delta, int offset) {
    var pos = 0;
    for (final op in delta.operations) {
      final text = op.data is String ? op.data as String : null;
      final len = text?.length ?? 1;
      if (pos + len > offset) {
        if (text == null) return true;
        final start = (offset - pos).clamp(0, text.length);
        if (text.substring(start).trim().isNotEmpty) return true;
      }
      pos += len;
    }
    return false;
  }
}