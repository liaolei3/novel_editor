import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/txt_importer.dart';

void main() {
  test('卷 / 章两级切分', () {
    final raw = '第一卷 风起\n'
        '第一章 开始\n正文一\n'
        '第二章 继续\n正文二\n'
        '第二卷 云涌\n'
        '第一章 转折\n正文三';
    final preview = TxtImporter.parse(raw);

    expect(preview.volumeCount, 2);
    expect(preview.chapterCount, 3);
    expect(preview.volumes[0].name, '第一卷 风起');
    expect(preview.volumes[0].chapters.map((c) => c.title),
        ['第一章 开始', '第二章 继续']);
    expect(preview.volumes[0].chapters[0].body, '正文一');
    expect(preview.volumes[1].name, '第二卷 云涌');
    expect(preview.volumes[1].chapters.first.title, '第一章 转折');
  });

  test('集 亦识别为卷', () {
    final preview = TxtImporter.parse('第一集 启程\n第一章 出发\n正文');
    expect(preview.volumeCount, 1);
    expect(preview.volumes.first.name, '第一集 启程');
    expect(preview.volumes.first.chapters.single.title, '第一章 出发');
  });

  test('无卷标记：全部归入默认卷，卷前内容为序章', () {
    final raw = '序言内容\n第一章 开始\n正文一\n第二章 继续\n正文二';
    final preview = TxtImporter.parse(raw);

    expect(preview.volumeCount, 1);
    expect(preview.volumes.first.name, '第一卷');
    expect(preview.volumes.first.chapters.map((c) => c.title),
        ['序章', '第一章 开始', '第二章 继续']);
    expect(preview.volumes.first.chapters.first.body, '序言内容');
  });

  test('卷标记前的内容并入首个卷作序章', () {
    final raw = '序言内容\n第一卷 风起\n第一章 开始\n正文';
    final preview = TxtImporter.parse(raw);

    expect(preview.volumeCount, 1);
    expect(preview.volumes.first.chapters.map((c) => c.title),
        ['序章', '第一章 开始']);
  });

  test('卷内无章标记的正文归入「正文」章', () {
    final raw = '第一卷 风起\n一段没有章节标记的正文\n'
        '第二卷 云涌\n第一章 开始\n正文';
    final preview = TxtImporter.parse(raw);

    expect(preview.volumeCount, 2);
    expect(preview.volumes.first.chapters.single.title, '正文');
    expect(preview.volumes.first.chapters.single.body, '一段没有章节标记的正文');
  });

  test('无内容的空卷不落地', () {
    final raw = '第一卷 上空\n第二卷 云涌\n第一章 开始\n正文';
    final preview = TxtImporter.parse(raw);

    expect(preview.volumeCount, 1);
    expect(preview.volumes.first.name, '第二卷 云涌');
  });

  test('整篇无标记时作为一卷一章', () {
    final preview = TxtImporter.parse('一段没有章节标记的正文');

    expect(preview.volumeCount, 1);
    expect(preview.chapterCount, 1);
    expect(preview.volumes.first.chapters.single.title, '一段没有章节标记的正文');
  });

  test('中文数字章标题识别', () {
    final preview = TxtImporter.parse('第十二章 标题\n内容');
    expect(preview.volumes.first.chapters.single.title, '第十二章 标题');
  });

  test('含句末标点或超长的整行不算标题', () {
    final raw = '第一章 开始\n正文一\n'
        '第二章的内容详见上一章。这一点请读者注意。\n'
        '第三章${'后' * 40}\n尾段';
    final preview = TxtImporter.parse(raw);

    expect(preview.chapterCount, 1);
    expect(preview.volumes.first.chapters.single.title, '第一章 开始');
  });

  test('字数统计不含空白', () {
    final preview = TxtImporter.parse('第一章 开始\n正文 一\n');
    // 正文「正文 一」去掉空格与换行后为 3 字。
    expect(preview.volumes.first.chapters.single.charCount, 3);
    expect(preview.charCount, 3);
  });
}