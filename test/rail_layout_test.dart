import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/state/rail_layout.dart';

void main() {
  group('RailLayout.initial', () {
    test('目录树在左上段展开，其余 7 个图标位于右上段', () {
      final layout = RailLayout.initial();
      expect(layout.panels[RailSlot.leftTop], [RailLayout.tree]);
      expect(layout.panels[RailSlot.rightTop], [
        RailLayout.outline,
        RailLayout.snapshot,
        RailLayout.character,
        RailLayout.foreshadow,
        RailLayout.sensitive,
        RailLayout.recycle,
        RailLayout.preview,
      ]);
      expect(RailLayout.allPanels.length, 8);
      for (final slot in RailSlot.values) {
        if (slot != RailSlot.leftTop && slot != RailSlot.rightTop) {
          expect(layout.panels[slot], isEmpty);
        }
        if (slot != RailSlot.leftTop) {
          expect(layout.active[slot], isNull);
        }
      }
      expect(layout.active[RailSlot.leftTop], RailLayout.tree);
      expect(layout.leftWidth, 360);
      expect(layout.rightWidth, 360);
      expect(layout.leftSplit, 0.5);
      expect(layout.rightSplit, 0.5);
      expect(layout.hasAnyOpenPanel, isTrue);
    });
  });

  group('序列化', () {
    test('toJson/fromJson 往返一致', () {
      final layout = RailLayout.initial();
      layout.move(RailLayout.character, RailSlot.leftTop, 0);
      layout.move(RailLayout.foreshadow, RailSlot.leftTop, 1);
      layout.toggle(RailLayout.character);
      layout.leftWidth = 400;
      layout.rightWidth = 300;
      layout.leftSplit = 0.3;
      layout.rightSplit = 0.7;

      final restored = RailLayout.fromJson(layout.toJson());
      expect(restored.panels, layout.panels);
      expect(restored.active, layout.active);
      expect(restored.leftWidth, layout.leftWidth);
      expect(restored.rightWidth, layout.rightWidth);
      expect(restored.leftSplit, layout.leftSplit);
      expect(restored.rightSplit, layout.rightSplit);
    });

    test('null、空 map、四段全空均回到初始布局', () {
      final expected = RailLayout.initial();
      final cases = <Map<String, dynamic>?>[
        null,
        {},
        {
          'panels': {
            'leftTop': [],
            'leftBottom': [],
            'rightTop': [],
            'rightBottom': [],
          },
        },
      ];
      for (final json in cases) {
        final layout = RailLayout.fromJson(json);
        expect(layout.panels, expected.panels);
        expect(layout.leftWidth, expected.leftWidth);
        expect(layout.rightWidth, expected.rightWidth);
        expect(layout.leftSplit, expected.leftSplit);
        expect(layout.rightSplit, expected.rightSplit);
      }
    });

    test('未知 id 丢弃、重复 id 去重、缺失 id 补到右上段', () {
      final layout = RailLayout.fromJson({
        'panels': {
          'leftTop': ['unknown', 'character', 'character'],
          'leftBottom': ['ai'],
          'rightTop': [],
          'rightBottom': [],
        },
        'active': {
          'leftTop': 'character',
          'leftBottom': 'missing',
          'rightTop': null,
          'rightBottom': null,
        },
      });
      expect(layout.panels[RailSlot.leftTop], [
        RailLayout.tree,
        'character',
      ]);
      expect(layout.panels[RailSlot.leftBottom], isEmpty);
      expect(layout.panels[RailSlot.rightTop], [
        'outline',
        'snapshot',
        'foreshadow',
        'sensitive',
        'recycle',
        'preview',
      ]);
      expect(layout.active[RailSlot.leftTop], 'character');
      expect(layout.active[RailSlot.leftBottom], isNull);
    });

    test('旧版含 AI 面板的配置：丢弃 AI 图标', () {
      final layout = RailLayout.fromJson({
        'panels': {
          'leftTop': [],
          'leftBottom': [],
          'rightTop': [
            'outline',
            'ai',
            'snapshot',
            'character',
            'foreshadow',
            'sensitive',
            'recycle',
            'preview',
          ],
          'rightBottom': [],
        },
        'active': {
          'leftTop': null,
          'leftBottom': null,
          'rightTop': null,
          'rightBottom': null,
        },
      });
      expect(layout.panels[RailSlot.leftTop], [RailLayout.tree]);
      expect(layout.panels[RailSlot.rightTop], [
        'outline',
        'snapshot',
        'character',
        'foreshadow',
        'sensitive',
        'recycle',
        'preview',
      ]);
      expect(layout.active[RailSlot.leftTop], RailLayout.tree);
      for (final slot in RailSlot.values) {
        if (slot != RailSlot.leftTop) expect(layout.active[slot], isNull);
      }
    });

    test('已有目录树但 active.leftTop 为 null 时不强制展开', () {
      final layout = RailLayout.fromJson({
        'panels': {
          'leftTop': ['character', 'tree'],
          'leftBottom': [],
          'rightTop': [
            'outline',
            'snapshot',
            'foreshadow',
            'sensitive',
            'recycle',
            'preview',
          ],
          'rightBottom': [],
        },
        'active': {
          'leftTop': null,
          'leftBottom': null,
          'rightTop': null,
          'rightBottom': null,
        },
      });
      expect(layout.panels[RailSlot.leftTop], ['character', RailLayout.tree]);
      expect(layout.active[RailSlot.leftTop], isNull);
      expect(layout.hasAnyOpenPanel, isFalse);
    });

    test('非法数值被夹取到合法范围', () {
      final layout = RailLayout.fromJson({
        'panels': {
          'leftTop': [],
          'leftBottom': [],
          'rightTop': List<String>.from(RailLayout.allPanels),
          'rightBottom': [],
        },
        'leftWidth': 100,
        'rightWidth': 1000,
        'leftSplit': 0.1,
        'rightSplit': 0.95,
      });
      expect(layout.leftWidth, 300);
      expect(layout.rightWidth, 520);
      expect(layout.leftSplit, 0.2);
      expect(layout.rightSplit, 0.8);
    });

    test('非数值字段回退默认值', () {
      final layout = RailLayout.fromJson({
        'panels': {
          'rightTop': List<String>.from(RailLayout.allPanels),
        },
        'leftWidth': 'wide',
        'rightWidth': true,
        'leftSplit': null,
        'rightSplit': 'half',
      });
      expect(layout.leftWidth, 360);
      expect(layout.rightWidth, 360);
      expect(layout.leftSplit, 0.5);
      expect(layout.rightSplit, 0.5);
    });
  });

  group('move', () {
    test('同段排序：第 0 个移到索引 3', () {
      final layout = RailLayout.initial();
      layout.move(RailLayout.outline, RailSlot.rightTop, 3);
      expect(layout.panels[RailSlot.rightTop], [
        'snapshot',
        'character',
        'foreshadow',
        'outline',
        'sensitive',
        'recycle',
        'preview',
      ]);
    });

    test('跨段移动并清理原段 active', () {
      final layout = RailLayout.initial();
      layout.toggle(RailLayout.snapshot);
      expect(layout.active[RailSlot.rightTop], 'snapshot');

      layout.move(RailLayout.snapshot, RailSlot.leftBottom, 0);
      expect(layout.panels[RailSlot.rightTop], [
        'outline',
        'character',
        'foreshadow',
        'sensitive',
        'recycle',
        'preview',
      ]);
      expect(layout.panels[RailSlot.leftBottom], ['snapshot']);
      expect(layout.active[RailSlot.rightTop], isNull);
      expect(layout.slotOf(RailLayout.snapshot), RailSlot.leftBottom);
    });

    test('移走最后一个图标后该段为空', () {
      final layout = RailLayout.initial();
      for (var i = 0; i < RailLayout.allPanels.length; i++) {
        layout.move(RailLayout.allPanels[i], RailSlot.leftTop, i);
      }
      expect(layout.panels[RailSlot.rightTop], isEmpty);
      expect(layout.panels[RailSlot.leftTop], RailLayout.allPanels);
    });

    test('索引越界夹取到 [0, length]', () {
      final layout = RailLayout.initial();
      layout.move(RailLayout.outline, RailSlot.rightTop, 999);
      expect(layout.panels[RailSlot.rightTop]!.last, RailLayout.outline);

      layout.move(RailLayout.outline, RailSlot.rightTop, -5);
      expect(layout.panels[RailSlot.rightTop]!.first, RailLayout.outline);

      layout.move(RailLayout.outline, RailSlot.leftTop, 99);
      expect(layout.panels[RailSlot.leftTop], [
        RailLayout.tree,
        RailLayout.outline,
      ]);
    });
  });

  group('展开状态', () {
    test('toggle 展开、收起、切换，且不影响其他段', () {
      final layout = RailLayout.initial();
      layout.move(RailLayout.character, RailSlot.leftTop, 0);
      layout.expandInSlot(RailLayout.character);

      layout.toggle(RailLayout.outline);
      expect(layout.active[RailSlot.rightTop], RailLayout.outline);
      expect(layout.isOpen(RailLayout.outline), isTrue);

      layout.toggle(RailLayout.outline);
      expect(layout.active[RailSlot.rightTop], isNull);
      expect(layout.isOpen(RailLayout.outline), isFalse);

      layout.toggle(RailLayout.outline);
      layout.toggle(RailLayout.snapshot);
      expect(layout.active[RailSlot.rightTop], RailLayout.snapshot);
      expect(layout.active[RailSlot.leftTop], RailLayout.character);
    });

    test('expandInSlot 在图标所在段展开', () {
      final layout = RailLayout.initial();
      layout.move(RailLayout.foreshadow, RailSlot.leftBottom, 0);
      layout.expandInSlot(RailLayout.foreshadow);
      expect(layout.active[RailSlot.leftBottom], RailLayout.foreshadow);
      expect(layout.isOpen(RailLayout.foreshadow), isTrue);

      layout.toggle(RailLayout.foreshadow);
      expect(layout.active[RailSlot.leftBottom], isNull);
    });
  });

  test('mergedPanels 按四段顺序合并', () {
    final layout = RailLayout.initial();
    layout.move(RailLayout.character, RailSlot.leftTop, 0);
    layout.move(RailLayout.snapshot, RailSlot.leftBottom, 0);
    layout.move(RailLayout.preview, RailSlot.rightBottom, 0);
    expect(layout.mergedPanels, [
      RailLayout.character,
      RailLayout.tree,
      RailLayout.snapshot,
      RailLayout.outline,
      RailLayout.foreshadow,
      RailLayout.sensitive,
      RailLayout.recycle,
      RailLayout.preview,
    ]);
  });
}
