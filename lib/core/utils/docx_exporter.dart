import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';


/// Word (.docx) 导出（FR-23）。
///
/// 生成符合 OOXML 最小结构的 .docx（zip 容器）。
class DocxExporter {
  DocxExporter._();

  /// [chapters]：(标题, 正文) 列表；正文按 \n 分段。
  static Uint8List build({
    required String bookTitle,
    required String penName,
    required List<MapEntry<String, String>> chapters,
    bool includeChapterTitle = true,
  }) {
    final body = StringBuffer();
    body.write(_paragraph(_escape(bookTitle), bold: true, size: 36));
    body.write(_paragraph(_escape('作者：$penName'), size: 24));
    for (final chapter in chapters) {
      if (includeChapterTitle) {
        body.write(_paragraph(_escape(chapter.key), bold: true, size: 28));
      }
      for (final line in chapter.value.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        body.write(_paragraph(_escape(t)));
      }
    }

    final document = _documentXml(body.toString());
    final contentTypes = _contentTypesXml();
    final rels = _rootRelsXml();
    final docRels = _documentRelsXml();

    final archive = Archive()
      ..addFile(_entry('[Content_Types].xml', utf8.encode(contentTypes)))
      ..addFile(_entry('_rels/.rels', utf8.encode(rels)))
      ..addFile(_entry('word/document.xml', utf8.encode(document)))
      ..addFile(_entry('word/_rels/document.xml.rels', utf8.encode(docRels)));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static ArchiveFile _entry(String name, List<int> data) =>
      ArchiveFile(name, data.length, data);

  static String _documentXml(String body) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body</w:body></w:document>';

  static String _contentTypesXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

  static String _rootRelsXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';

  static String _documentRelsXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
''';

  static String _paragraph(String text, {bool bold = false, int size = 24}) {
    final rPr = bold || size != 24
        ? '<w:rPr>${bold ? '<w:b/>' : ''}${size != 24 ? '<w:sz w:val="$size"/>' : ''}</w:rPr>'
        : '';
    return '<w:p><w:r>$rPr<w:t xml:space="preserve">$text</w:t></w:r></w:p>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}