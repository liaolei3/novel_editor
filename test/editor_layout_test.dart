import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/state/editor_layout.dart';

/// 经过真实 JSON 编解码的往返解析。
EditorLayout? _roundTrip(EditorLayout layout) =>
    EditorLayout.fromJson(jsonDecode(jsonEncode(layout.toJson())));

String _paneIdOf(EditorLayoutNode node) => (node as EditorPaneNode).paneId;

void main() {
  group('单窗格', () {
    test('toJson/fromJson 往返保持一致', () {
      final layout = EditorLayout.singlePane(
        tabIds: ['c1', 'c2'],
        activeChapterId: 'c2',
      );
      expect(layout.isSinglePane, isTrue);
      expect(layout.paneIdsInOrder, ['pane-1']);

      final restored = _roundTrip(layout)!;
      expect(restored.isSinglePane, isTrue);
      expect(restored.paneIdsInOrder, ['pane-1']);
      expect(restored.activePaneId, 'pane-1');
      expect(restored.panes['pane-1']!.tabIds, ['c1', 'c2']);
      expect(restored.panes['pane-1']!.activeChapterId, 'c2');
    });

    test('活动章节不在标签中时插入首位', () {
      final layout = EditorLayout.singlePane(activeChapterId: 'c9');
      expect(layout.panes['pane-1']!.tabIds, ['c9']);
      expect(layout.panes['pane-1']!.activeChapterId, 'c9');
    });
  });

  group('嵌套分割', () {
    EditorLayout buildNested() {
      var layout = EditorLayout.singlePane(
        tabIds: ['c1'],
        activeChapterId: 'c1',
      );
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newPaneId: 'pane-2',
        newActiveChapterId: 'c2',
      );
      return layout.splitPane(
        'pane-2',
        EditorSplitDirection.bottom,
        newPaneId: 'pane-3',
        newActiveChapterId: 'c3',
      );
    }

    test('左 | 右上 / 右下结构与遍历顺序', () {
      final layout = buildNested();
      expect(layout.paneIdsInOrder, ['pane-1', 'pane-2', 'pane-3']);

      final root = layout.root as EditorSplitNode;
      expect(root.axis, EditorSplitAxis.horizontal);
      expect(_paneIdOf(root.first), 'pane-1');
      final right = root.second as EditorSplitNode;
      expect(right.axis, EditorSplitAxis.vertical);
      expect(_paneIdOf(right.first), 'pane-2');
      expect(_paneIdOf(right.second), 'pane-3');
    });

    test('JSON 往返保持结构、比例与各窗格标签', () {
      final layout = buildNested();
      final restored = _roundTrip(layout)!;

      expect(restored.isSinglePane, isFalse);
      expect(restored.paneIdsInOrder, ['pane-1', 'pane-2', 'pane-3']);
      expect(restored.activePaneId, 'pane-3');

      final root = restored.root as EditorSplitNode;
      expect(root.axis, EditorSplitAxis.horizontal);
      expect(root.ratio, 0.5);
      final right = root.second as EditorSplitNode;
      expect(right.axis, EditorSplitAxis.vertical);
      expect(restored.panes['pane-1']!.tabIds, ['c1']);
      expect(restored.panes['pane-2']!.tabIds, ['c2']);
      expect(restored.panes['pane-3']!.tabIds, ['c3']);
      expect(restored.panes['pane-3']!.activeChapterId, 'c3');
    });
  });

  group('比例夹取', () {
    test('构造时超界比例被夹取到 15%–85%', () {
      final low = EditorSplitNode(
        axis: EditorSplitAxis.horizontal,
        ratio: 0.01,
        first: const EditorPaneNode('p1'),
        second: const EditorPaneNode('p2'),
      );
      final high = EditorSplitNode(
        axis: EditorSplitAxis.vertical,
        ratio: 5,
        first: const EditorPaneNode('p1'),
        second: const EditorPaneNode('p2'),
      );
      expect(low.ratio, EditorLayout.minSplitRatio);
      expect(high.ratio, EditorLayout.maxSplitRatio);
    });

    test('解析时超界比例被夹取', () {
      final layout = EditorLayout.fromJson(<String, Object?>{
        'root': <String, Object?>{
          'type': 'split',
          'axis': 'horizontal',
          'ratio': -3,
          'first': <String, Object?>{'type': 'pane', 'paneId': 'p1'},
          'second': <String, Object?>{'type': 'pane', 'paneId': 'p2'},
        },
        'panes': <String, Object?>{},
      })!;
      expect((layout.root as EditorSplitNode).ratio,
          EditorLayout.minSplitRatio);
    });
  });

  group('损坏数据', () {
    test('非 Map 或缺少根节点返回 null', () {
      expect(EditorLayout.fromJson(null), isNull);
      expect(EditorLayout.fromJson('broken'), isNull);
      expect(EditorLayout.fromJson(<String, Object?>{}), isNull);
      expect(
        EditorLayout.fromJson(<String, Object?>{
          'root': <String, Object?>{'type': 'pane'},
        }),
        isNull,
      );
    });

    test('分割节点跳过非法分支', () {
      final node = EditorLayoutNode.fromJson(<String, Object?>{
        'type': 'split',
        'axis': 'vertical',
        'ratio': 0.4,
        'first': <String, Object?>{'type': 'pane'},
        'second': <String, Object?>{'type': 'pane', 'paneId': 'p2'},
      });
      expect(node, isA<EditorPaneNode>());
      expect(_paneIdOf(node!), 'p2');
    });

    test('重复窗格 id 只保留首个分支', () {
      final node = EditorLayoutNode.fromJson(<String, Object?>{
        'type': 'split',
        'axis': 'horizontal',
        'ratio': 0.5,
        'first': <String, Object?>{'type': 'pane', 'paneId': 'p1'},
        'second': <String, Object?>{'type': 'pane', 'paneId': 'p1'},
      });
      expect(node, isA<EditorPaneNode>());
      expect(_paneIdOf(node!), 'p1');
    });

    test('缺少窗格状态时回退为空窗格', () {
      final layout = EditorLayout.fromJson(<String, Object?>{
        'root': <String, Object?>{'type': 'pane', 'paneId': 'p1'},
      })!;
      expect(layout.isSinglePane, isTrue);
      expect(layout.activePaneId, 'p1');
      expect(layout.panes['p1']!.tabIds, isEmpty);
      expect(layout.panes['p1']!.activeChapterId, isNull);
    });
  });

  group('prune', () {
    test('剔除无效章节、折叠空窗格并回退活动窗格', () {
      var layout = EditorLayout.singlePane(
        tabIds: ['c1', 'c2'],
        activeChapterId: 'c2',
      );
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newPaneId: 'pane-2',
        newActiveChapterId: 'c3',
      );

      final pruned = layout.prune(
        validChapterIds: {'c1'},
        fallbackChapterId: 'c9',
        fallbackPaneId: 'pane-x',
      );
      expect(pruned.isSinglePane, isTrue);
      expect(pruned.paneIdsInOrder, ['pane-1']);
      expect(pruned.panes['pane-1']!.tabIds, ['c1']);
      expect(pruned.panes['pane-1']!.activeChapterId, 'c1');
      expect(pruned.activePaneId, 'pane-1');
    });

    test('全部失效时生成单窗格并使用回退章节', () {
      var layout = EditorLayout.singlePane(tabIds: ['dead1']);
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.bottom,
        newPaneId: 'pane-2',
        newActiveChapterId: 'dead2',
      );

      final pruned = layout.prune(
        validChapterIds: const {},
        fallbackChapterId: 'c9',
        fallbackPaneId: 'pane-9',
      );
      expect(pruned.isSinglePane, isTrue);
      expect(pruned.paneIdsInOrder, ['pane-9']);
      expect(pruned.activePaneId, 'pane-9');
      expect(pruned.panes['pane-9']!.tabIds, ['c9']);
      expect(pruned.panes['pane-9']!.activeChapterId, 'c9');
    });

    test('唯一窗格允许保留为空', () {
      final layout = EditorLayout.singlePane();
      final pruned = layout.prune(
        validChapterIds: const {},
        fallbackChapterId: 'c9',
        fallbackPaneId: 'pane-9',
      );
      expect(pruned.isSinglePane, isTrue);
      expect(pruned.paneIdsInOrder, ['pane-1']);
      expect(pruned.panes['pane-1']!.tabIds, isEmpty);
      expect(pruned.activePaneId, 'pane-1');
    });

    test('唯一窗格标签全部失效时改用回退章节', () {
      final layout = EditorLayout.singlePane(
        tabIds: ['dead1'],
        activeChapterId: 'dead1',
      );
      final pruned = layout.prune(
        validChapterIds: const {},
        fallbackChapterId: 'c9',
        fallbackPaneId: 'pane-9',
      );
      expect(pruned.isSinglePane, isTrue);
      expect(pruned.paneIdsInOrder, ['pane-1']);
      expect(pruned.activePaneId, 'pane-1');
      expect(pruned.panes['pane-1']!.tabIds, ['c9']);
      expect(pruned.panes['pane-1']!.activeChapterId, 'c9');
    });

    test('多窗格中失效章节被剔除，空窗格折叠且活动窗格回退', () {
      var layout = EditorLayout.singlePane(
        tabIds: ['c1', 'c2'],
        activeChapterId: 'c1',
      );
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newPaneId: 'pane-2',
        newActiveChapterId: 'c3',
      );

      final pruned = layout.prune(
        validChapterIds: {'c1', 'c2', 'c4'},
        fallbackChapterId: null,
        fallbackPaneId: 'pane-1',
      );
      expect(pruned.isSinglePane, isTrue);
      expect(pruned.paneIdsInOrder, ['pane-1']);
      expect(pruned.panes['pane-1']!.tabIds, ['c1', 'c2']);
      expect(pruned.activePaneId, 'pane-1');
    });
  });

  group('removePane', () {
    EditorLayout buildNested() {
      var layout = EditorLayout.singlePane(tabIds: ['c1']);
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newPaneId: 'pane-2',
        newActiveChapterId: 'c2',
      );
      return layout.splitPane(
        'pane-2',
        EditorSplitDirection.bottom,
        newPaneId: 'pane-3',
        newActiveChapterId: 'c3',
      );
    }

    test('删除窗格后由兄弟节点顶替分割节点', () {
      final layout = buildNested().removePane('pane-2');
      expect(layout.paneIdsInOrder, ['pane-1', 'pane-3']);
      final root = layout.root as EditorSplitNode;
      expect(root.axis, EditorSplitAxis.horizontal);
      expect(_paneIdOf(root.first), 'pane-1');
      expect(_paneIdOf(root.second), 'pane-3');
      expect(layout.panes.containsKey('pane-2'), isFalse);
      expect(layout.activePaneId, 'pane-3');
    });

    test('删除非活动窗格时活动窗格保持不变', () {
      final layout =
          buildNested().withActivePane('pane-1').removePane('pane-3');
      expect(layout.paneIdsInOrder, ['pane-1', 'pane-2']);
      expect(layout.activePaneId, 'pane-1');
    });

    test('删除活动窗格后转移到相邻兄弟窗格', () {
      final layout = buildNested().removePane('pane-3');
      expect(layout.paneIdsInOrder, ['pane-1', 'pane-2']);
      expect(layout.activePaneId, 'pane-2');
    });

    test('删除最后一个窗格回退单窗格并保留首个有效标签', () {
      final layout = EditorLayout.singlePane(
        tabIds: ['c1', 'c2'],
        activeChapterId: 'c2',
      ).removePane('pane-1');
      expect(layout.isSinglePane, isTrue);
      expect(layout.panes.length, 1);
      expect(layout.panes['pane-1']!.tabIds, ['c1']);
      expect(layout.activePaneId, 'pane-1');
    });
  });

  group('splitPane 方向', () {
    test('top/bottom 产生垂直分割，left/right 产生水平分割', () {
      final base = EditorLayout.singlePane(tabIds: ['c1']);

      EditorSplitNode rootOf(EditorSplitDirection direction) =>
          base.splitPane(
            'pane-1',
            direction,
            newPaneId: 'pane-2',
            newActiveChapterId: 'c2',
          ).root as EditorSplitNode;

      final top = rootOf(EditorSplitDirection.top);
      expect(top.axis, EditorSplitAxis.vertical);
      expect(_paneIdOf(top.first), 'pane-2');
      expect(_paneIdOf(top.second), 'pane-1');

      final bottom = rootOf(EditorSplitDirection.bottom);
      expect(bottom.axis, EditorSplitAxis.vertical);
      expect(_paneIdOf(bottom.first), 'pane-1');
      expect(_paneIdOf(bottom.second), 'pane-2');

      final left = rootOf(EditorSplitDirection.left);
      expect(left.axis, EditorSplitAxis.horizontal);
      expect(_paneIdOf(left.first), 'pane-2');
      expect(_paneIdOf(left.second), 'pane-1');

      final right = rootOf(EditorSplitDirection.right);
      expect(right.axis, EditorSplitAxis.horizontal);
      expect(_paneIdOf(right.first), 'pane-1');
      expect(_paneIdOf(right.second), 'pane-2');
    });

    test('新窗格成为活动窗格并打开指定章节', () {
      final layout = EditorLayout.singlePane(tabIds: ['c1']).splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newActiveChapterId: 'c2',
      );
      expect(layout.activePaneId, 'pane-2');
      expect(layout.panes['pane-2']!.tabIds, ['c2']);
      expect(layout.panes['pane-2']!.activeChapterId, 'c2');
      expect(layout.panes['pane-1']!.tabIds, ['c1']);
    });
  });

  group('withSplitRatioAt', () {
    EditorLayout buildNested() {
      var layout = EditorLayout.singlePane(tabIds: ['c1']);
      layout = layout.splitPane(
        'pane-1',
        EditorSplitDirection.right,
        newPaneId: 'pane-2',
        newActiveChapterId: 'c2',
      );
      return layout.splitPane(
        'pane-2',
        EditorSplitDirection.bottom,
        newPaneId: 'pane-3',
        newActiveChapterId: 'c3',
      );
    }

    test('按路径修改嵌套分割比例', () {
      final layout = buildNested().withSplitRatioAt(const [1], 0.7);
      final root = layout.root as EditorSplitNode;
      expect(root.ratio, 0.5);
      final right = root.second as EditorSplitNode;
      expect(right.ratio, 0.7);
    });

    test('空路径修改根分割比例', () {
      final layout = buildNested().withSplitRatioAt(const [], 0.7);
      expect((layout.root as EditorSplitNode).ratio, 0.7);
    });

    test('超界比例被夹取到 15%–85%', () {
      final low = buildNested().withSplitRatioAt(const [], 0.01);
      final high = buildNested().withSplitRatioAt(const [], 5);
      expect((low.root as EditorSplitNode).ratio, EditorLayout.minSplitRatio);
      expect((high.root as EditorSplitNode).ratio, EditorLayout.maxSplitRatio);
    });

    test('路径非法或无分割节点时返回原布局', () {
      final base = buildNested();
      expect(base.withSplitRatioAt(const [0], 0.3), same(base));
      expect(base.withSplitRatioAt(const [1, 0], 0.3), same(base));
      expect(base.withSplitRatioAt(const [2], 0.3), same(base));
      expect(base.withSplitRatioAt(const [1, 2], 0.3), same(base));
      final single = EditorLayout.singlePane();
      expect(single.withSplitRatioAt(const [], 0.3), same(single));
    });
  });

  group('withPaneStates / withActivePane', () {
    test('替换窗格标签并保留结构与其他窗格', () {
      final layout = EditorLayout.singlePane(tabIds: ['c1'])
          .splitPane(
            'pane-1',
            EditorSplitDirection.right,
            newPaneId: 'pane-2',
            newActiveChapterId: 'c2',
          )
          .withPaneStates(
            {
              'pane-1': EditorPaneState(tabIds: ['c1', 'c3'], activeChapterId: 'c3'),
            },
            activePaneId: 'pane-1',
          );
      expect(layout.paneIdsInOrder, ['pane-1', 'pane-2']);
      expect(layout.panes['pane-1']!.tabIds, ['c1', 'c3']);
      expect(layout.panes['pane-1']!.activeChapterId, 'c3');
      expect(layout.panes['pane-2']!.tabIds, ['c2']);
      expect(layout.activePaneId, 'pane-1');
    });

    test('切换活动窗格忽略不存在的窗格', () {
      final base = EditorLayout.singlePane(tabIds: ['c1']);
      expect(base.withActivePane('missing'), same(base));
    });
  });
}
