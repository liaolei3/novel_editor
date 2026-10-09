import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/sensitive_words.dart';

void main() {
  test('scan 返回命中区间与上下文', () {
    final scanner =
        SensitiveWordScanner([const SensitiveEntry(word: '赌博', suggestion: '○○')]);
    final hits = scanner.scan('这里有赌博网站');
    final occ = hits.single.occurrences.single;
    expect(occ.start, 3);
    expect(occ.end, 5);
    expect(occ.match, '赌博');
    expect(occ.before, '这里有');
    expect(occ.after, '网站');
  });

  test('英文忽略大小写命中', () {
    final scanner =
        SensitiveWordScanner([const SensitiveEntry(word: 'qq', suggestion: 'x')]);
    final hits = scanner.scan('QQ群和qq');
    expect(hits.single.count, 2);
  });

  test('建议词为空的词只提示不替换', () {
    final scanner = SensitiveWordScanner([
      const SensitiveEntry(word: '赌博'),
      const SensitiveEntry(word: '色情', suggestion: '情感'),
    ]);
    final (out, n) = scanner.replacePlainText('赌博与色情');
    expect(n, 1);
    expect(out, '赌博与情感');
  });

  test('replaceInDeltaJson 保留富文本格式', () {
    final scanner =
        SensitiveWordScanner([const SensitiveEntry(word: '赌博', suggestion: '○○')]);
    final json = jsonEncode([
      {
        'insert': '赌博',
        'attributes': {'bold': true},
      },
      {'insert': '网站\n'},
    ]);
    final (out, n) = scanner.replaceInDeltaJson(json);
    expect(n, 1);
    final ops = jsonDecode(out) as List;
    expect(ops[0]['insert'], '○○');
    expect(ops[0]['attributes'], {'bold': true});
    expect(ops[1]['insert'], '网站\n');
  });

  test('replaceInDeltaJson 大小写不敏感替换', () {
    final scanner =
        SensitiveWordScanner([const SensitiveEntry(word: 'qq', suggestion: '某社交平台')]);
    final json = jsonEncode([
      {'insert': 'QQ群\n'},
    ]);
    final (out, n) = scanner.replaceInDeltaJson(json);
    expect(n, 1);
    expect((jsonDecode(out) as List)[0]['insert'], '某社交平台群\n');
  });

  test('parseImport 解析词与建议词、忽略注释、去重', () {
    final entries = SensitiveWordScanner.parseImport(
        '\uFEFF# 注释\n自杀|自尽\n翻墙\t翻围墙\nQQ群,读者群\n自杀|其它\n');
    expect(entries.length, 3);
    expect(entries[0].word, '自杀');
    expect(entries[0].suggestion, '自尽');
    expect(entries[1].word, '翻墙');
    expect(entries[1].suggestion, '翻围墙');
    expect(entries[2].word, 'QQ群');
    expect(entries[2].suggestion, '读者群');
  });

  test('parseImport 单词行建议词为空', () {
    final entries = SensitiveWordScanner.parseImport('赌博\n色情\n');
    expect(entries.length, 2);
    expect(entries[0].suggestion, '');
  });

  test('空文本或无词条不产生命中', () {
    final scanner = SensitiveWordScanner([const SensitiveEntry(word: '赌博')]);
    expect(scanner.scan(''), isEmpty);
    expect(SensitiveWordScanner(const []).scan('赌博'), isEmpty);
  });
}