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

  group('TextStats.speedPerHour 时速口径', () {
    test('不足 1 小时按 1 小时算，数值等于字数', () {
      expect(TextStats.speedPerHour(500, 0), 500);
      expect(TextStats.speedPerHour(500, 60000), 500);
      expect(TextStats.speedPerHour(500, 59 * 60000), 500);
    });

    test('满 1 小时按实际小时均摊', () {
      expect(TextStats.speedPerHour(1500, 90 * 60000), 1000);
      expect(TextStats.speedPerHour(3000, 120 * 60000), 1500);
    });

    test('未码字为 0', () {
      expect(TextStats.speedPerHour(0, 0), 0);
      expect(TextStats.speedPerHour(0, 120 * 60000), 0);
    });
  });

  group('CountStandard.count', () {
    const text = '你好，world！\n 66 ';

    test('withPunctuation 含标点不含空白', () {
      expect(TextStats.count(text, CountStandard.withPunctuation), 11);
    });

    test('withoutPunctuation 仅汉字/字母/数字', () {
      expect(TextStats.count(text, CountStandard.withoutPunctuation), 9);
      expect(TextStats.count('你好，世界！', CountStandard.withoutPunctuation), 4);
      expect(TextStats.count('a-b_c', CountStandard.withoutPunctuation), 3);
    });

    test('withPunctuation 与 charCount 一致', () {
      expect(TextStats.count('😀哈哈 a', CountStandard.withPunctuation),
          TextStats.charCount('😀哈哈 a'));
    });
  });
}