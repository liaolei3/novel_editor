import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/text_formatter.dart';

void main() {
  group('collapseBlankLines', () {
    test('压缩连续空行', () {
      expect(TextFormatter.collapseBlankLines('a\n\n\n\nb'), 'a\n\nb');
    });
    test('去除首尾空白行', () {
      expect(TextFormatter.collapseBlankLines('\n\na\n\n'), 'a');
    });
  });

  group('normalizePunctuation', () {
    test('半角转全角', () {
      expect(TextFormatter.normalizePunctuation('hi, ok!'), 'hi， ok！');
      expect(TextFormatter.normalizePunctuation('a:b;c?'), 'a：b；c？');
    });
    test('小数点保留半角', () {
      expect(TextFormatter.normalizePunctuation('3.14'), '3.14');
      expect(TextFormatter.normalizePunctuation('v1.2.3'), 'v1.2.3');
    });
    test('句末点号转句号', () {
      expect(TextFormatter.normalizePunctuation('结束.'), '结束。');
    });
  });

  group('indentParagraphs', () {
    test('段首加两个全角空格', () {
      expect(TextFormatter.indentParagraphs('a\nb'), '　　a\n　　b');
    });
    test('已缩进不重复', () {
      expect(TextFormatter.indentParagraphs('　　a'), '　　a');
    });
  });

  test('format 组合', () {
    final out = TextFormatter.format('hello.\n\n\nworld');
    expect(out, contains('　　hello。'));
    expect(out, contains('　　world'));
    expect(out.contains('\n\n\n'), isFalse);
  });
}