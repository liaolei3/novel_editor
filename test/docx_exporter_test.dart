import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/docx_exporter.dart';

void main() {
  test('生成合法 zip 容器且包含 document.xml', () {
    final bytes = DocxExporter.build(
      bookTitle: '测试书',
      penName: '佚名',
      chapters: const [
        MapEntry('第一章', '正文一\n第二行'),
        MapEntry('第二章', '正文二'),
      ],
    );
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.map((f) => f.name).toSet();
    expect(names, contains('[Content_Types].xml'));
    expect(names, contains('word/document.xml'));
    expect(names, contains('_rels/.rels'));

    final doc = archive.findFile('word/document.xml')!;
    final xml = utf8.decode(doc.content as List<int>);
    expect(xml, contains('测试书'));
    expect(xml, contains('正文一'));
    expect(xml, contains('正文二'));
  });

  test('保留空行与段首全角空格缩进', () {
    final bytes = DocxExporter.build(
      bookTitle: '书',
      penName: '佚名',
      chapters: const [MapEntry('第一章', '　　缩进段\n\n　　第二段')],
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );
    expect(xml, contains('<w:t xml:space="preserve">　　缩进段</w:t>'));
    expect(xml, contains('<w:t xml:space="preserve">　　第二段</w:t>'));
    expect(xml, contains('<w:p/>'));
    // 书名 + 作者 + 章节标题 + 两段 + 一个空段落
    expect('<w:p'.allMatches(xml).length, 6);
  });
}