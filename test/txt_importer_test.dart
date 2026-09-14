import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/txt_importer.dart';

void main() {
  test('按“第X章”切分', () {
    final raw = '第一章 开始\n正文一\n第二章 继续\n正文二\n第三章 结束\n正文三';
    final parts = TxtImporter.splitChapters(raw);
    expect(parts.length, 3);
    expect(parts[0].key, '第一章 开始');
    expect(parts[0].value, '正文一');
    expect(parts[2].key, '第三章 结束');
  });

  test('无匹配整篇作为一章', () {
    final parts = TxtImporter.splitChapters('一段没有章节标记的正文');
    expect(parts.length, 1);
    expect(parts.first.value, contains('一段没有章节标记'));
  });

  test('章前序章内容归入序章', () {
    final raw = '序言内容\n第一章 正章\n正文';
    final parts = TxtImporter.splitChapters(raw);
    expect(parts.length, 2);
    expect(parts.first.key, '序章');
    expect(parts.last.key, '第一章 正章');
  });

  test('中文数字章节标题识别', () {
    final parts = TxtImporter.splitChapters('第十二章 标题\n内容');
    expect(parts.length, 1);
    expect(parts.first.key, '第十二章 标题');
  });
}