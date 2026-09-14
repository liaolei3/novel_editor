import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/text_stats.dart';

void main() {
  group('TextStats.charCount', () {
    test('含标点不含空白', () {
      expect(TextStats.charCount('你好，世界！'), 6);
      expect(TextStats.charCount('a b c'), 3);
      expect(TextStats.charCount('  \n\t'), 0);
      expect(TextStats.charCount('第1章 标题'), 5);
    });

    test('emoji 按码点计数', () {
      expect(TextStats.charCount('😀哈哈'), 3);
    });
  });

  test('paragraphCount 忽略空段', () {
    expect(TextStats.paragraphCount('a\n\nb\n\n\n'), 2);
  });

  test('readingMinutes 向上取整', () {
    expect(TextStats.readingMinutes(0), 0);
    expect(TextStats.readingMinutes(500), 1);
    expect(TextStats.readingMinutes(1200), 3);
  });
}