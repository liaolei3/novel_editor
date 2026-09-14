/// 敏感词检测（FR-26）。
///
/// 内置示例词库 + 支持外部词库更新（一行一词）。
/// 检测结果只做提示与替换建议，不做强制屏蔽。
class SensitiveWordScanner {
  SensitiveWordScanner(this.words);

  final List<String> words;

  static final SensitiveWordScanner defaultScanner = SensitiveWordScanner([
    '血腥暴力',
    '自杀教程',
    '赌博网站',
    '代开发票',
    '办证刻章',
    '色情',
  ]);

  factory SensitiveWordScanner.parse(String dictionaryText) {
    final words = dictionaryText
        .split(RegExp(r'[\r\n]+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && !w.startsWith('#'))
        .toSet()
        .toList();
    return SensitiveWordScanner(words);
  }

  /// 命中结果：词 + 出现位置列表。
  Map<String, List<int>> scan(String text) {
    final result = <String, List<int>>{};
    if (text.isEmpty || words.isEmpty) return result;
    for (final word in words) {
      if (word.isEmpty) continue;
      final positions = <int>[];
      var start = 0;
      while (true) {
        final idx = text.indexOf(word, start);
        if (idx < 0) break;
        positions.add(idx);
        start = idx + word.length;
      }
      if (positions.isNotEmpty) result[word] = positions;
    }
    return result;
  }

  /// 将所有命中词替换为建议词。
  String replaceAll(String text, String suggestion) {
    var result = text;
    for (final word in words) {
      if (word.isEmpty) continue;
      result = result.replaceAll(word, suggestion);
    }
    return result;
  }
}