import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/docx_importer.dart';
import 'package:novel_editor/core/utils/txt_importer.dart';

/// 用给定 body 组装最小 docx（zip 容器）。
Uint8List _docx(String body, {String part = 'word/document.xml'}) {
  final xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<w:body>$body</w:body></w:document>';
  final data = utf8.encode(xml);
  final archive = Archive()..addFile(ArchiveFile(part, data.length, data));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _p(String text) =>
    '<w:p><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>';

void main() {
  test('每个段落输出一行，实体转义还原', () {
    final text = DocxImporter.extractText(_docx(
      _p('第一卷 风起') + _p('第一章 开始') + _p('正文 &lt;上&gt; &amp; 下'),
    ));

    expect(text, '第一卷 风起\n第一章 开始\n正文 <上> & 下\n');
  });

  test('段内 w:br 转换行、w:tab 转空格', () {
    final text = DocxImporter.extractText(_docx(
      '<w:p><w:r><w:t>上</w:t><w:br/><w:t>下</w:t><w:tab/><w:t>右</w:t></w:r></w:p>',
    ));

    expect(text, '上\n下 右\n');
  });

  test('表格单元格按文档顺序取出', () {
    final text = DocxImporter.extractText(_docx(
      '<w:tbl><w:tr><w:tc>${_p('格子一')}</w:tc><w:tc>${_p('格子二')}</w:tc></w:tr></w:tbl>',
    ));

    expect(text, '格子一\n格子二\n');
  });

  test('DrawingML 的同名 a:t 不混入正文', () {
    final text = DocxImporter.extractText(_docx(
      '<w:p><w:r><w:t>正文</w:t></w:r>'
      '<w:r><w:drawing><a:t>图注</a:t></w:drawing></w:r></w:p>',
    ));

    expect(text, '正文\n');
  });

  test('文本框内段落随外层取出，不重复', () {
    final text = DocxImporter.extractText(_docx(
      '<w:p><w:r><w:t>外</w:t></w:r>'
      '<w:r><w:txbxContent>${_p('内')}</w:txbxContent></w:r></w:p>',
    ));

    expect(text, '外内\n');
  });

  test('无段落时返回空串', () {
    expect(DocxImporter.extractText(_docx('')), '');
  });

  test('非 zip 内容抛 FormatException', () {
    expect(
      () => DocxImporter.extractText(utf8.encode('这不是一个 zip 文件')),
      throwsFormatException,
    );
  });

  test('缺少 document.xml 抛 FormatException', () {
    expect(
      () => DocxImporter.extractText(_docx(_p('正文'), part: 'word/other.xml')),
      throwsFormatException,
    );
  });

  test('docx 抽出的文本与等价 txt 得到相同的卷章结构', () {
    const raw = '第一卷 风起\n'
        '第一章 开始\n正文一\n'
        '第二章 继续\n正文二\n'
        '第二卷 云涌\n'
        '第一章 转折\n正文三';
    final docxText = DocxImporter.extractText(
      _docx(raw.split('\n').map(_p).join()),
    );

    final fromDocx = TxtImporter.parse(docxText);
    final fromTxt = TxtImporter.parse(raw);

    expect(docxText, '$raw\n');
    expect(fromDocx.volumeCount, fromTxt.volumeCount);
    expect(fromDocx.chapterCount, fromTxt.chapterCount);
    for (var i = 0; i < fromTxt.volumes.length; i++) {
      expect(fromDocx.volumes[i].name, fromTxt.volumes[i].name);
      expect(
        fromDocx.volumes[i].chapters.map((c) => c.title),
        fromTxt.volumes[i].chapters.map((c) => c.title),
      );
      expect(
        fromDocx.volumes[i].chapters.map((c) => c.body),
        fromTxt.volumes[i].chapters.map((c) => c.body),
      );
    }
  });
}