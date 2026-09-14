/// 一键排版（FR-25）。
///
/// 提供三项可独立开关的处理：清除多余空行/空格、统一中文标点、段首缩进。
/// 调用方需先展示预览，应用前自动创建快照以保证可撤销。
class TextFormatter {
  TextFormatter._();

  /// 清除多余空行与行尾空格：连续空行压缩为一个空行。
  static String collapseBlankLines(String text) {
    final lines = text.split('\n').map((l) => l.replaceAll('\r', '').trimRight()).toList();
    final out = <String>[];
    var blankRun = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        blankRun++;
        if (blankRun <= 1) out.add('');
      } else {
        blankRun = 0;
        out.add(line);
      }
    }
    while (out.isNotEmpty && out.first.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }

  /// 统一中文标点：半角标点转全角（数字间的小数点除外）。
  static String normalizePunctuation(String text) {
    final sb = StringBuffer();
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final ch = String.fromCharCode(runes[i]);
      final prev = i > 0 ? String.fromCharCode(runes[i - 1]) : '';
      final next = i + 1 < runes.length ? String.fromCharCode(runes[i + 1]) : '';
      switch (ch) {
        case ',':
          sb.write('，');
          break;
        case '!':
          sb.write('！');
          break;
        case '?':
          sb.write('？');
          break;
        case ';':
          sb.write('；');
          break;
        case ':':
          sb.write('：');
          break;
        case '.':
          final isDecimal =
              _isDigit(prev) && _isDigit(next);
          sb.write(isDecimal ? '.' : '。');
          break;
        default:
          sb.write(ch);
      }
    }
    return sb.toString();
  }

  /// 段首缩进：每个非空段落前加两个全角空格。
  static String indentParagraphs(String text) {
    return text.split('\n').map((line) {
      if (line.trim().isEmpty) return line;
      if (line.startsWith('　　')) return line;
      return '　　$line';
    }).join('\n');
  }

  /// 组合排版。
  static String format(
    String text, {
    bool collapseBlank = true,
    bool normalizePunct = true,
    bool indent = true,
  }) {
    var result = text;
    if (normalizePunct) result = normalizePunctuation(result);
    if (collapseBlank) result = collapseBlankLines(result);
    if (indent) result = indentParagraphs(result);
    return result;
  }

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
}