/// 编辑区分屏布局数据模型：窗格叶子、水平 / 垂直分割节点、窗格标签状态。
/// 纯 Dart 实现，不依赖 Flutter UI；所有修改方法返回新实例。
library;

/// 分割方向：horizontal 为左右分栏，vertical 为上下分栏。
enum EditorSplitAxis { horizontal, vertical }

/// 新窗格相对目标窗格的投放方向。
enum EditorSplitDirection { top, bottom, left, right }

/// 布局树节点：叶子为窗格，分支为两个子节点的分割。
sealed class EditorLayoutNode {
  const EditorLayoutNode();

  Map<String, Object?> toJson();

  /// 容错解析，非法节点返回 null；分割节点会跳过非法分支。
  static EditorLayoutNode? fromJson(Object? json) =>
      _parseNode(json, <String>{});

  static EditorLayoutNode? _parseNode(Object? json, Set<String> seen) {
    if (json is! Map) return null;
    final type = json['type'];
    if (type == 'pane') {
      final paneId = json['paneId'];
      if (paneId is! String || paneId.isEmpty || !seen.add(paneId)) {
        return null;
      }
      return EditorPaneNode(paneId);
    }
    if (type == 'split') {
      final axis = _axisFromName(json['axis']);
      if (axis == null) return null;
      final rawRatio = json['ratio'];
      final ratio = rawRatio is num ? rawRatio.toDouble() : 0.5;
      final first = _parseNode(json['first'], seen);
      final second = _parseNode(json['second'], seen);
      if (first == null) return second;
      if (second == null) return first;
      return EditorSplitNode(
        axis: axis,
        ratio: ratio,
        first: first,
        second: second,
      );
    }
    return null;
  }

  static EditorSplitAxis? _axisFromName(Object? value) {
    for (final axis in EditorSplitAxis.values) {
      if (axis.name == value) return axis;
    }
    return null;
  }
}

/// 窗格叶子节点，持有窗格 id。
final class EditorPaneNode extends EditorLayoutNode {
  const EditorPaneNode(this.paneId);

  final String paneId;

  @override
  Map<String, Object?> toJson() => {'type': 'pane', 'paneId': paneId};
}

/// 分割节点，按 [ratio] 划分 [first] 与 [second]。
final class EditorSplitNode extends EditorLayoutNode {
  EditorSplitNode({
    required this.axis,
    required double ratio,
    required this.first,
    required this.second,
  }) : ratio = _normalizeRatio(ratio);

  final EditorSplitAxis axis;

  /// 第一个子节点所占比例，限制在 0.15–0.85。
  final double ratio;

  final EditorLayoutNode first;
  final EditorLayoutNode second;

  static double _normalizeRatio(double value) {
    if (value.isNaN || value.isInfinite) return 0.5;
    return value
        .clamp(EditorLayout.minSplitRatio, EditorLayout.maxSplitRatio)
        .toDouble();
  }

  @override
  Map<String, Object?> toJson() => {
        'type': 'split',
        'axis': axis.name,
        'ratio': ratio,
        'first': first.toJson(),
        'second': second.toJson(),
      };
}

/// 单个窗格的标签状态。
class EditorPaneState {
  factory EditorPaneState({
    List<String> tabIds = const [],
    String? activeChapterId,
  }) {
    final tabs = <String>[];
    final seen = <String>{};
    for (final id in tabIds) {
      if (id.isNotEmpty && seen.add(id)) tabs.add(id);
    }
    final active =
        activeChapterId != null && tabs.contains(activeChapterId)
            ? activeChapterId
            : (tabs.isEmpty ? null : tabs.first);
    return EditorPaneState._(tabs, active);
  }

  EditorPaneState._(this.tabIds, this.activeChapterId);

  final List<String> tabIds;
  final String? activeChapterId;

  /// 复制并替换字段；[clearActiveChapter] 为 true 时清空当前章节。
  EditorPaneState copy({
    List<String>? tabIds,
    String? activeChapterId,
    bool clearActiveChapter = false,
  }) =>
      EditorPaneState(
        tabIds: tabIds ?? this.tabIds,
        activeChapterId:
            clearActiveChapter ? null : (activeChapterId ?? this.activeChapterId),
      );

  /// 容错解析，非 Map 返回 null。
  static EditorPaneState? fromJson(Object? json) {
    if (json is! Map) return null;
    final tabs = <String>[];
    final rawTabs = json['tabIds'];
    if (rawTabs is List) {
      for (final value in rawTabs) {
        if (value is String && value.isNotEmpty) tabs.add(value);
      }
    }
    final rawActive = json['activeChapterId'];
    return EditorPaneState(
      tabIds: tabs,
      activeChapterId: rawActive is String ? rawActive : null,
    );
  }

  Map<String, Object?> toJson() => {
        'tabIds': List<String>.of(tabIds),
        'activeChapterId': activeChapterId,
      };
}

/// 单本书的编辑区分屏布局。
class EditorLayout {
  EditorLayout._(this.root, this.panes, this.activePaneId);

  static const double minSplitRatio = 0.15;
  static const double maxSplitRatio = 0.85;
  static const double minPaneWidth = 240;
  static const double minPaneHeight = 160;

  final EditorLayoutNode root;
  final Map<String, EditorPaneState> panes;
  final String activePaneId;

  /// 默认单窗格布局；活动章节不在标签中时插入首位。
  factory EditorLayout.singlePane({
    List<String> tabIds = const [],
    String? activeChapterId,
    String paneId = 'pane-1',
  }) {
    final tabs = List<String>.of(tabIds);
    if (activeChapterId != null && !tabs.contains(activeChapterId)) {
      tabs.insert(0, activeChapterId);
    }
    return EditorLayout._(
      EditorPaneNode(paneId),
      {paneId: EditorPaneState(tabIds: tabs, activeChapterId: activeChapterId)},
      paneId,
    );
  }

  /// 容错解析，非法根节点返回 null。
  static EditorLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    final root = EditorLayoutNode.fromJson(json['root'] ?? json);
    if (root == null) return null;
    final ids = _leafIds(root);
    if (ids.isEmpty) return null;
    final rawPanes = json['panes'];
    final parsedPanes = <String, EditorPaneState>{
      for (final id in ids)
        id: EditorPaneState.fromJson(rawPanes is Map ? rawPanes[id] : null) ??
            EditorPaneState(),
    };
    final rawActive = json['activePaneId'];
    final active =
        rawActive is String && ids.contains(rawActive) ? rawActive : ids.first;
    return EditorLayout._(root, parsedPanes, active);
  }

  bool get isSinglePane => root is EditorPaneNode;

  /// 按树从左到右、从上到下的顺序返回窗格 id。
  List<String> get paneIdsInOrder => _leafIds(root);

  /// 按方向分割目标窗格，新窗格成为活动窗格。
  EditorLayout splitPane(
    String targetPaneId,
    EditorSplitDirection direction, {
    String? newPaneId,
    String? newActiveChapterId,
  }) {
    if (!panes.containsKey(targetPaneId)) return this;
    final id = _uniquePaneId(newPaneId);
    final isVertical = direction == EditorSplitDirection.top ||
        direction == EditorSplitDirection.bottom;
    final newFirst = direction == EditorSplitDirection.top ||
        direction == EditorSplitDirection.left;
    final targetNode = EditorPaneNode(targetPaneId);
    final newNode = EditorPaneNode(id);
    final replacement = EditorSplitNode(
      axis: isVertical ? EditorSplitAxis.vertical : EditorSplitAxis.horizontal,
      ratio: 0.5,
      first: newFirst ? newNode : targetNode,
      second: newFirst ? targetNode : newNode,
    );
    final newRoot = _replacePane(root, targetPaneId, replacement);
    final newPaneState = EditorPaneState(
      tabIds: newActiveChapterId == null
          ? const []
          : <String>[newActiveChapterId],
      activeChapterId: newActiveChapterId,
    );
    return EditorLayout._(
      newRoot,
      {...panes, id: newPaneState},
      id,
    );
  }

  /// 删除窗格，父分割节点由兄弟节点顶替；删光时回退单窗格。
  EditorLayout removePane(String paneId) {
    if (!panes.containsKey(paneId)) return this;
    final newRoot = _removeLeaf(root, paneId);
    if (newRoot == null) {
      String? firstTab;
      for (final id in paneIdsInOrder) {
        final state = panes[id];
        if (state != null && state.tabIds.isNotEmpty) {
          firstTab = state.tabIds.first;
          break;
        }
      }
      return EditorLayout.singlePane(
        tabIds: firstTab == null ? const [] : <String>[firstTab],
        paneId: paneId,
      );
    }
    final ids = _leafIds(newRoot);
    final newPanes = <String, EditorPaneState>{
      for (final id in ids) id: panes[id] ?? EditorPaneState(),
    };
    final nextActive = ids.contains(activePaneId)
        ? activePaneId
        : (_adjacentPaneId(root, activePaneId) ?? ids.first);
    return EditorLayout._(newRoot, newPanes, nextActive);
  }

  /// 剔除失效章节与空窗格，折叠空分支，全部失效时回退单窗格。
  EditorLayout prune({
    required Set<String> validChapterIds,
    required String? fallbackChapterId,
    required String fallbackPaneId,
  }) {
    final prunedPanes = <String, EditorPaneState>{};
    for (final entry in panes.entries) {
      final tabs = entry.value.tabIds
          .where(validChapterIds.contains)
          .toList(growable: false);
      final active = entry.value.activeChapterId;
      prunedPanes[entry.key] = EditorPaneState(
        tabIds: tabs,
        activeChapterId:
            active != null && tabs.contains(active) ? active : null,
      );
    }

    // 唯一窗格允许保留为空；原有标签被全部剔除时改用回退章节。
    final singleRoot = root;
    if (singleRoot is EditorPaneNode) {
      final paneId = singleRoot.paneId;
      final state = prunedPanes[paneId] ?? EditorPaneState();
      final hadTabs = panes[paneId]?.tabIds.isNotEmpty ?? false;
      if (hadTabs && state.tabIds.isEmpty && fallbackChapterId != null) {
        return EditorLayout.singlePane(
          tabIds: <String>[fallbackChapterId],
          activeChapterId: fallbackChapterId,
          paneId: paneId,
        );
      }
      return EditorLayout._(
        root,
        {paneId: state},
        paneId,
      );
    }

    final newRoot = _pruneNode(root, prunedPanes);
    if (newRoot == null) {
      return EditorLayout.singlePane(
        tabIds: fallbackChapterId == null
            ? const []
            : <String>[fallbackChapterId],
        paneId: fallbackPaneId,
      );
    }
    final ids = _leafIds(newRoot);
    final newPanes = <String, EditorPaneState>{
      for (final id in ids) id: prunedPanes[id] ?? EditorPaneState(),
    };
    return EditorLayout._(
      newRoot,
      newPanes,
      ids.contains(activePaneId) ? activePaneId : ids.first,
    );
  }

  /// 以新的窗格标签状态重建布局；缺失窗格沿用原状态。
  EditorLayout withPaneStates(
    Map<String, EditorPaneState> panes, {
    String? activePaneId,
  }) {
    final ids = paneIdsInOrder;
    final next = <String, EditorPaneState>{
      for (final id in ids) id: panes[id] ?? this.panes[id] ?? EditorPaneState(),
    };
    final wanted = activePaneId ?? this.activePaneId;
    return EditorLayout._(
      root,
      next,
      next.containsKey(wanted) ? wanted : ids.first,
    );
  }

  /// 切换活动窗格；窗格不存在时返回原布局。
  EditorLayout withActivePane(String paneId) {
    if (!panes.containsKey(paneId) || paneId == activePaneId) return this;
    return EditorLayout._(root, panes, paneId);
  }

  /// 修改由 0/1 索引路径定位的分割节点比例，根节点路径为空。
  EditorLayout withSplitRatioAt(List<int> path, double ratio) {
    final newRoot = _withRatioAt(root, path, 0, ratio);
    if (identical(newRoot, root)) return this;
    return EditorLayout._(newRoot, panes, activePaneId);
  }

  Map<String, Object?> toJson() => {
        'root': root.toJson(),
        'panes': {
          for (final entry in panes.entries) entry.key: entry.value.toJson(),
        },
        'activePaneId': activePaneId,
      };

  static EditorLayoutNode _withRatioAt(
    EditorLayoutNode node,
    List<int> path,
    int depth,
    double ratio,
  ) {
    if (depth == path.length) {
      if (node is! EditorSplitNode) return node;
      return EditorSplitNode(
        axis: node.axis,
        ratio: ratio,
        first: node.first,
        second: node.second,
      );
    }
    if (node is! EditorSplitNode) return node;
    final index = path[depth];
    if (index != 0 && index != 1) return node;
    if (index == 0) {
      final first = _withRatioAt(node.first, path, depth + 1, ratio);
      if (identical(first, node.first)) return node;
      return EditorSplitNode(
        axis: node.axis,
        ratio: node.ratio,
        first: first,
        second: node.second,
      );
    }
    if (index == 1) {
      final second = _withRatioAt(node.second, path, depth + 1, ratio);
      if (identical(second, node.second)) return node;
      return EditorSplitNode(
        axis: node.axis,
        ratio: node.ratio,
        first: node.first,
        second: second,
      );
    }
    return node;
  }

  static List<String> _leafIds(EditorLayoutNode node) {
    if (node is EditorPaneNode) return [node.paneId];
    final split = node as EditorSplitNode;
    return [
      ..._leafIds(split.first),
      ..._leafIds(split.second),
    ];
  }

  /// 被删窗格所在最近分割节点的兄弟子树首个叶子；找不到返回 null。
  static String? _adjacentPaneId(EditorLayoutNode node, String paneId) {
    if (node is! EditorSplitNode) return null;
    final firstIds = _leafIds(node.first);
    final secondIds = _leafIds(node.second);
    final inFirst = firstIds.contains(paneId);
    final inSecond = secondIds.contains(paneId);
    if (!inFirst && !inSecond) return null;
    final deeper = _adjacentPaneId(
      inFirst ? node.first : node.second,
      paneId,
    );
    if (deeper != null) return deeper;
    final siblingIds = inFirst ? secondIds : firstIds;
    return siblingIds.isEmpty ? null : siblingIds.first;
  }

  static EditorLayoutNode _replacePane(
    EditorLayoutNode node,
    String paneId,
    EditorLayoutNode replacement,
  ) {
    if (node is EditorPaneNode) {
      return node.paneId == paneId ? replacement : node;
    }
    final split = node as EditorSplitNode;
    final first = _replacePane(split.first, paneId, replacement);
    final second = _replacePane(split.second, paneId, replacement);
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return EditorSplitNode(
      axis: split.axis,
      ratio: split.ratio,
      first: first,
      second: second,
    );
  }

  static EditorLayoutNode? _removeLeaf(EditorLayoutNode node, String paneId) {
    if (node is EditorPaneNode) {
      return node.paneId == paneId ? null : node;
    }
    final split = node as EditorSplitNode;
    final first = _removeLeaf(split.first, paneId);
    final second = _removeLeaf(split.second, paneId);
    if (first == null) return second;
    if (second == null) return first;
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return EditorSplitNode(
      axis: split.axis,
      ratio: split.ratio,
      first: first,
      second: second,
    );
  }

  static EditorLayoutNode? _pruneNode(
    EditorLayoutNode node,
    Map<String, EditorPaneState> prunedPanes,
  ) {
    if (node is EditorPaneNode) {
      final state = prunedPanes[node.paneId];
      if (state == null || state.tabIds.isEmpty) return null;
      return node;
    }
    final split = node as EditorSplitNode;
    final first = _pruneNode(split.first, prunedPanes);
    final second = _pruneNode(split.second, prunedPanes);
    if (first == null) return second;
    if (second == null) return first;
    if (identical(first, split.first) && identical(second, split.second)) {
      return split;
    }
    return EditorSplitNode(
      axis: split.axis,
      ratio: split.ratio,
      first: first,
      second: second,
    );
  }

  String _uniquePaneId(String? preferred) {
    final used = _leafIds(root).toSet();
    if (preferred != null && preferred.isNotEmpty && !used.contains(preferred)) {
      return preferred;
    }
    var n = 1;
    while (used.contains('pane-$n')) {
      n++;
    }
    return 'pane-$n';
  }
}
