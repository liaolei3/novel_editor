import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/global_search.dart';
import 'package:novel_editor/data/models.dart';

Volume _vol(String id, String name, int sort) => Volume(
      id: id,
      bookId: 'b',
      name: name,
      sort: sort,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Chapter _ch(
  String id,
  String volId,
  String title,
  int sort, {
  String content = '',
  String outline = '',
  bool pinned = false,
}) =>
    Chapter(
      id: id,
      bookId: 'b',
      volumeId: volId,
      title: title,
      content: content,
      outline: outline,
      sort: sort,
      pinned: pinned,
      lastEditedAt: DateTime(2026),
    );

Character _character(String id, String name,
        {String aliases = '', String tags = ''}) =>
    Character(
      id: id,
      bookId: 'b',
      name: name,
      aliases: aliases,
      tags: tags,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Foreshadow _foreshadow(String id, String name, String content) => Foreshadow(
      id: id,
      bookId: 'b',
      name: name,
      content: content,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('GlobalSearch.search', () {
    test('空查询返回空结果', () {
      final hits = GlobalSearch.search(
        query: '',
        chapters: [_ch('c1', 'v1', '第一章', 0, content: '猎魔')],
        volumes: [_vol('v1', '第一卷', 0)],
        characters: [_character('p1', '猎魔人')],
        foreshadows: [_foreshadow('f1', '猎魔伏笔', '猎魔铺垫')],
      );
      expect(hits, isEmpty);
    });

    test('四类命中按 scope 分类；正文/章纲带卷与章节 id，角色/伏笔不带', () {
      final hits = GlobalSearch.search(
        query: '猎魔',
        chapters: [
          _ch('c1', 'v1', '第一章', 0,
              content: '猎魔人来了', outline: '猎魔计划'),
          _ch('c2', 'v1', '第二章', 1, content: '无关内容'),
        ],
        volumes: [_vol('v1', '第一卷', 0)],
        characters: [_character('p1', '猎魔人')],
        foreshadows: [_foreshadow('f1', '猎魔伏笔', '猎魔的铺垫')],
      );
      expect(
        hits.map((h) => h.scope),
        [
          SearchScope.content,
          SearchScope.outline,
          SearchScope.character,
          SearchScope.foreshadow,
        ],
      );

      final content = hits.first;
      expect(content.label, '第一章');
      expect(content.chapterId, 'c1');
      expect(content.volumeId, 'v1');
      expect(content.count, 1);

      final outline = hits[1];
      expect(outline.label, '第一章');
      expect(outline.chapterId, 'c1');
      expect(outline.volumeId, 'v1');

      final character = hits[2];
      expect(character.chapterId, isNull);
      expect(character.fields.single.fieldLabel, '名字');

      final foreshadow = hits[3];
      expect(foreshadow.chapterId, isNull);
      expect(foreshadow.fields.map((f) => f.fieldLabel), ['名称', '内容']);
    });

    test('正文命中按「卷序 → 章序」排列，置顶章节不提前', () {
      final hits = GlobalSearch.search(
        query: 'X',
        // 输入顺序刻意打乱，c2 置顶（模拟书树 pinned DESC 的顺序）。
        chapters: [
          _ch('c2', 'v1', '第二章', 1, content: 'X', pinned: true),
          _ch('c3', 'v2', '第三章', 0, content: 'X'),
          _ch('c1', 'v1', '第一章', 0, content: 'X'),
        ],
        volumes: [_vol('v1', '第一卷', 0), _vol('v2', '第二卷', 1)],
        characters: <Character>[],
        foreshadows: <Foreshadow>[],
      );
      expect(hits.map((h) => h.chapterId), ['c1', 'c2', 'c3']);
      expect(hits.map((h) => h.volumeId), ['v1', 'v1', 'v2']);
    });

    test('章纲命中同样按卷章排序', () {
      final hits = GlobalSearch.search(
        query: 'X',
        chapters: [
          _ch('c2', 'v2', '第二章', 0, outline: 'X'),
          _ch('c1', 'v1', '第一章', 0, outline: 'X'),
        ],
        volumes: [_vol('v2', '第二卷', 1), _vol('v1', '第一卷', 0)],
        characters: <Character>[],
        foreshadows: <Foreshadow>[],
      );
      expect(hits.map((h) => h.chapterId), ['c1', 'c2']);
    });

    test('伏笔只匹配名称与内容，命中字段名随之区分', () {
      final hits = GlobalSearch.search(
        query: '伏',
        chapters: <Chapter>[],
        volumes: <Volume>[],
        characters: <Character>[],
        foreshadows: [
          _foreshadow('f1', '无关', '这里埋下伏笔'),
          _foreshadow('f2', '伏击', ''),
        ],
      );
      expect(hits.length, 2);
      expect(hits.first.fields.single.fieldLabel, '内容');
      expect(hits.last.fields.single.fieldLabel, '名称');
    });

    test('伏笔名称为空时 label 回退「未命名伏笔」', () {
      final hits = GlobalSearch.search(
        query: '伏',
        chapters: <Chapter>[],
        volumes: <Volume>[],
        characters: <Character>[],
        foreshadows: [_foreshadow('f1', '', '伏笔内容')],
      );
      expect(hits.single.label, '未命名伏笔');
    });

    test('角色多字段命中聚合成一条，命中次数累加', () {
      final hits = GlobalSearch.search(
        query: '晚',
        chapters: <Chapter>[],
        volumes: <Volume>[],
        characters: [_character('p1', '林晚', aliases: '晚晚', tags: '晚')],
        foreshadows: <Foreshadow>[],
      );
      // '晚'：名字 ×1 + 别名「晚晚」×2 + 标签 ×1 = 4。
      expect(hits.single.count, 4);
      expect(hits.single.fields.map((f) => f.fieldLabel), ['名字', '别名', '标签']);
    });
  });
}