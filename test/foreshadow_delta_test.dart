import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/foreshadow_delta.dart';

Delta _docDelta(List<Map<String, dynamic>> ops) =>
    Delta.fromJson(ops.map((e) => Map<String, dynamic>.from(e)).toList());

void main() {
  group('deltaRangeHasFsid', () {
    test('范围内含标注返回 true', () {
      final delta = _docDelta([
        {'insert': '前文'},
        {'insert': '他拔出了剑', 'attributes': {'fsid': 's1'}},
        {'insert': '，转身离去\n'},
      ]);
      expect(deltaRangeHasFsid(delta, 2, 7), isTrue);
      expect(deltaRangeHasFsid(delta, 0, 2), isFalse);
      // 部分重叠也算命中
      expect(deltaRangeHasFsid(delta, 0, 4), isTrue);
    });

    test('空选区返回 false', () {
      final delta = _docDelta([
        {'insert': '他拔出了剑', 'attributes': {'fsid': 's1'}},
      ]);
      expect(deltaRangeHasFsid(delta, 2, 2), isFalse);
    });

    test('fsid 为 null 的属性不算标注', () {
      final delta = _docDelta([
        {'insert': 'abc', 'attributes': {'fsid': null}},
      ]);
      expect(deltaRangeHasFsid(delta, 0, 3), isFalse);
    });
  });

  group('deltaFsidRanges', () {
    test('收集单个片段范围', () {
      final delta = _docDelta([
        {'insert': '前文'},
        {'insert': '他拔出了剑', 'attributes': {'fsid': 's1', 'bold': true}},
        {'insert': '，转身离去\n'},
      ]);
      expect(deltaFsidRanges(delta, 's1'), [(2, 7)]);
      expect(deltaFsidRanges(delta, 's2'), isEmpty);
    });

    test('相邻同 id Operation 合并为连续范围', () {
      final delta = _docDelta([
        {'insert': 'A', 'attributes': {'fsid': 's1'}},
        {'insert': 'B', 'attributes': {'fsid': 's1'}},
        {'insert': 'C'},
        {'insert': 'D', 'attributes': {'fsid': 's1'}},
      ]);
      expect(deltaFsidRanges(delta, 's1'), [(0, 2), (3, 4)]);
    });
  });

  group('removeFsidFromDelta', () {
    test('仅移除目标片段的 fsid，保留其他属性', () {
      final delta = _docDelta([
        {'insert': '前文'},
        {'insert': '他拔出了剑', 'attributes': {'fsid': 's1', 'bold': true}},
        {'insert': '其他', 'attributes': {'fsid': 's2'}},
      ]);
      final cleaned = removeFsidFromDelta(delta, 's1');
      expect(cleaned.operations[0].data, '前文');
      final op1 = cleaned.operations[1];
      expect(op1.attributes, {'bold': true});
      final op2 = cleaned.operations[2];
      expect(op2.attributes, {'fsid': 's2'});
      // 原 Delta 不被修改
      expect(delta.operations[1].attributes, {'fsid': 's1', 'bold': true});
    });

    test('属性为空时操作不携带 attributes', () {
      final delta = _docDelta([
        {'insert': '文字', 'attributes': {'fsid': 's1'}},
      ]);
      final cleaned = removeFsidFromDelta(delta, 's1');
      expect(cleaned.operations.single.attributes, isNull);
      expect(deltaFsidRanges(cleaned, 's1'), isEmpty);
    });

    test('清除后再复合写回 JSON 往返一致', () {
      final delta = _docDelta([
        {'insert': '段落\n'},
        {'insert': '标注', 'attributes': {'fsid': 's1'}},
        {'insert': '结束\n'},
      ]);
      final cleaned = removeFsidFromDelta(delta, 's1');
      final json = cleaned.toJson();
      final roundTrip = Delta.fromJson(json);
      expect(roundTrip, cleaned);
    });
  });
}
