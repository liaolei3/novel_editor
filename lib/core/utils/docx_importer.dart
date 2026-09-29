import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Word (.docx) 读入：解压取出 `word/document.xml` 并抽成纯文本。
///
/// 只做「docx → 纯文本」这一步，卷/章切分仍交给 [TxtImporter.parse]，
/// 保证与 TXT 导入共用同一套规则。
class DocxImporter {
  DocxImporter._();

  static const String _documentPart = 'word/document.xml';

  /// WordprocessingML（transitional）命名空间。用于排除 DrawingML 等
  /// 局部同名的元素（如 `a:t`）混入正文。
  static const String _wNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// 抽取正文纯文本：按文档顺序遍历 `w:p`，段内 `w:t` 取字、`w:br` 转换行、
  /// `w:tab` 转空格，段落之间以 `\n` 连接；图片无文字、页眉页脚与脚注不在
  /// 本部件内，均自然排除。
  ///
  /// 文件不可解析（非 zip / 损坏 / 加密 / 缺正文部件）时抛 [FormatException]，
  /// 由调用方转成用户提示。
  static String extractText(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final part = archive.findFile(_documentPart);
      if (part == null) throw FormatException('缺少 $_documentPart');
      final data = part.readBytes();
      if (data == null) throw FormatException('$_documentPart 不可读');
      return _paragraphs(XmlDocument.parse(utf8.decode(data)));
    } catch (_) {
      // 外部文件内容不可信，各种解析异常统一按「读不了」处理。
      throw const FormatException('无法解析该 docx 文件');
    }
  }

  static String _paragraphs(XmlDocument document) {
    final buffer = StringBuffer();
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (!_isWord(element, 'p')) continue;
      // 文本框（w:txbxContent）内的段落嵌在外层段落里，文字已随外层取出，
      // 跳过以免重复。
      if (_hasParagraphAncestor(element)) continue;
      buffer
        ..write(_paragraphText(element))
        ..write('\n');
    }
    return buffer.toString();
  }

  static String _paragraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    for (final node in paragraph.descendants.whereType<XmlElement>()) {
      if (node.name.namespaceUri != _wNs) continue;
      switch (node.name.local) {
        case 't':
          buffer.write(node.innerText);
        case 'br':
          buffer.write('\n');
        case 'tab':
          buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  static bool _isWord(XmlElement element, String local) =>
      element.name.local == local && element.name.namespaceUri == _wNs;

  static bool _hasParagraphAncestor(XmlElement element) {
    for (var p = element.parentElement; p != null; p = p.parentElement) {
      if (_isWord(p, 'p')) return true;
    }
    return false;
  }
}