/// 字数统计工具。
enum CountStandard {
  withPunctuation,
  withoutPunctuation,
}

extension CountStandardLabel on CountStandard {
  String get label => switch (this) {
        CountStandard.withPunctuation => '含标点',
        CountStandard.withoutPunctuation => '不含标点',
      };
}

class TextStats {
  TextStats._();

  /// 按指定口径统计字数。
  static int count(String text, CountStandard std) => switch (std) {
        CountStandard.withPunctuation => charCount(text),
        CountStandard.withoutPunctuation => _countIf(text, _isLetterOrDigit),
      };

  /// 字符数（含标点，不含空白）。
  static int charCount(String text) =>
      _countIf(text, (r) => String.fromCharCode(r).trim().isNotEmpty);

  /// 段落数（以换行划分，忽略空段）。
  static int paragraphCount(String text) =>
      text.split('\n').where((l) => l.trim().isNotEmpty).length;

  /// 预估阅读时长（按每分钟 500 字）。
  static int readingMinutes(int charCount) => (charCount / 500).ceil();

  static int _countIf(String text, bool Function(int rune) test) {
    var n = 0;
    for (final rune in text.runes) {
      if (test(rune)) n++;
    }
    return n;
  }

  static bool _isAsciiAlnum(int r) =>
      (r >= 0x30 && r <= 0x39) ||
      (r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A);

  static bool _isLetterOrDigit(int r) {
    if (_isAsciiAlnum(r)) return true;
    final ch = String.fromCharCode(r);
    return ch.toUpperCase() != ch.toLowerCase() ||
        (r >= 0x4E00 && r <= 0x9FFF) ||
        (r >= 0x3400 && r <= 0x4DBF) ||
        r >= 0x20000;
  }
}
