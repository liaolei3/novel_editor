import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/sensitive_words.dart';

void main() {
  test('scan 命中位置', () {
    final scanner = SensitiveWordScanner(['赌博', '色情']);
    final hits = scanner.scan('这里有赌博网站和色情内容，赌博再次出现');
    expect(hits['赌博'], hasLength(2));
    expect(hits['色情'], hasLength(1));
  });

  test('replaceAll 替换为建议词', () {
    final scanner = SensitiveWordScanner(['赌博']);
    expect(scanner.replaceAll('赌博网站', '○○'), '○○网站');
  });

  test('parse 忽略注释与空行', () {
    final scanner = SensitiveWordScanner.parse('# 注释\n词A\n\n词B\n');
    expect(scanner.words, containsAll(['词A', '词B']));
    expect(scanner.words.length, 2);
  });

  test('默认词库非空', () {
    expect(SensitiveWordScanner.defaultScanner.words, isNotEmpty);
  });
}