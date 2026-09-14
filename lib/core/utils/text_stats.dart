/// 字数统计工具。
///
/// 统一口径：**字符数（含标点，不含空白字符）**。
/// UI 需显式标注口径（NFR-U1 / FR-5）。
class TextStats {
  TextStats._();

  /// 字符数（含标点，不含空白）。
  static int charCount(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (!ch.trim().isEmpty) buffer.writeCharCode(rune);
    }
    return buffer.length;
  }

  /// 段落数（以换行划分，忽略空段）。
  static int paragraphCount(String text) =>
      text.split('\n').where((l) => l.trim().isNotEmpty).length;

  /// 预估阅读时长（按每分钟 500 字）。
  static int readingMinutes(int charCount) => (charCount / 500).ceil();
}