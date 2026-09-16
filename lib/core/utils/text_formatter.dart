/// 一键排版（FR-25）。
///
/// 提供四项可独立开关的处理：清除多余空行/空格、统一中文标点、段首缩进、段间插空行。
/// 调用方需先展示预览，应用前自动创建快照以保证可撤销。
class TextFormatter {
  TextFormatter._();

  /// 删除空行与所有空格：移除全部空行、半角/全角空格与制表符。
  static String collapseBlankLines(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.replaceAll('\r', '').replaceAll(RegExp(r'[\t \u3000]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
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

  /// 段间插空行：相邻段落之间统一保留恰好一个空行，文首文尾不留空行。
  static String joinParagraphsWithBlankLine(String text) {
    final sb = StringBuffer();
    var prevBlank = true;
    for (final line in text.split('\n')) {
      if (line.replaceAll('\r', '').trim().isEmpty) continue;
      if (!prevBlank) sb.write('\n\n');
      sb.write(line);
      prevBlank = false;
    }
    return sb.toString();
  }

  /// 组合排版。
  static String format(
    String text, {
    bool collapseBlank = true,
    bool normalizePunct = true,
    bool indent = true,
    bool joinBlank = true,
  }) {
    var result = text;
    if (normalizePunct) result = normalizePunctuation(result);
    if (collapseBlank) result = collapseBlankLines(result);
    if (indent) result = indentParagraphs(result);
    if (joinBlank) result = joinParagraphsWithBlankLine(result);
    return result;
  }

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
}