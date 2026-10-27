/// 可停靠面板图标栏的布局数据。
///
/// 左右两侧各上下两段，共四个槽；每个槽维护图标顺序与当前展开的面板。
/// 布局整体存入 config.json 的 railLayout 键。
enum RailSlot {
  leftTop,
  leftBottom,
  rightTop,
  rightBottom;

  bool get isLeft => this == leftTop || this == leftBottom;

  bool get isTop => this == leftTop || this == rightTop;
}

class RailLayout {
  factory RailLayout({
    Map<RailSlot, List<String>>? panels,
    Map<RailSlot, String?>? active,
    double? leftWidth,
    double? rightWidth,
    double? leftSplit,
    double? rightSplit,
  }) {
    final normalized = _normalizePanels(panels);
    final normalizedActive = <RailSlot, String?>{};
    for (final slot in RailSlot.values) {
      final id = active?[slot];
      normalizedActive[slot] =
          id != null && normalized[slot]!.contains(id) ? id : null;
    }
    return RailLayout._(
      normalized,
      normalizedActive,
      _clampOr(leftWidth, defaultPanelWidth, minPanelWidth, maxPanelWidth),
      _clampOr(rightWidth, defaultPanelWidth, minPanelWidth, maxPanelWidth),
      _clampOr(leftSplit, defaultSplit, minSplit, maxSplit),
      _clampOr(rightSplit, defaultSplit, minSplit, maxSplit),
    );
  }

  RailLayout._(
    this.panels,
    this.active,
    this.leftWidth,
    this.rightWidth,
    this.leftSplit,
    this.rightSplit,
  );

  static const String tree = 'tree';
  static const String outline = 'outline';
  static const String ai = 'ai';
  static const String snapshot = 'snapshot';
  static const String character = 'character';
  static const String foreshadow = 'foreshadow';
  static const String sensitive = 'sensitive';
  static const String recycle = 'recycle';
  static const String preview = 'preview';

  /// 全部面板 id，按默认排列顺序。
  static const List<String> allPanels = [
    tree,
    outline,
    ai,
    snapshot,
    character,
    foreshadow,
    sensitive,
    recycle,
    preview,
  ];

  static const double minPanelWidth = 300;
  static const double maxPanelWidth = 520;
  static const double defaultPanelWidth = 360;
  static const double minSplit = 0.2;
  static const double maxSplit = 0.8;
  static const double defaultSplit = 0.5;

  /// 每段图标顺序，四个槽均有键，可为空列表。
  Map<RailSlot, List<String>> panels;

  /// 每段当前展开的面板 id，null 表示收起。
  Map<RailSlot, String?> active;

  double leftWidth;
  double rightWidth;

  /// 同侧上下高度比例。
  double leftSplit;
  double rightSplit;

  /// 默认布局：目录树在左上段展开，其余图标位于右上段。
  factory RailLayout.initial() => RailLayout(
        panels: {
          RailSlot.leftTop: [tree],
          RailSlot.rightTop: [
            for (final id in allPanels)
              if (id != tree) id,
          ],
        },
        active: {RailSlot.leftTop: tree},
      );

  /// 容错解析，永不抛异常。
  factory RailLayout.fromJson(Map<String, dynamic>? json) {
    try {
      if (json == null || json.isEmpty) return RailLayout.initial();
      final rawPanels = json['panels'];
      final parsed = <RailSlot, List<String>>{};
      final seen = <String>{};
      var total = 0;
      for (final slot in RailSlot.values) {
        final list = <String>[];
        final rawList = rawPanels is Map ? rawPanels[slot.name] : null;
        if (rawList is List) {
          for (final value in rawList) {
            if (value is String &&
                allPanels.contains(value) &&
                seen.add(value)) {
              list.add(value);
              total++;
            }
          }
        }
        parsed[slot] = list;
      }
      if (total == 0) return RailLayout.initial();
      // 旧版配置无目录树：插入左上段首位并默认展开。
      final hasTree = seen.contains(tree);
      if (!hasTree) {
        parsed[RailSlot.leftTop]!.insert(0, tree);
        seen.add(tree);
      }
      _fillMissing(parsed, seen);

      final rawActive = json['active'];
      final parsedActive = <RailSlot, String?>{};
      for (final slot in RailSlot.values) {
        final value = rawActive is Map ? rawActive[slot.name] : null;
        parsedActive[slot] = value is String && parsed[slot]!.contains(value)
            ? value
            : null;
      }
      if (!hasTree && parsedActive[RailSlot.leftTop] == null) {
        parsedActive[RailSlot.leftTop] = tree;
      }

      return RailLayout._(
        parsed,
        parsedActive,
        _clampJson(json['leftWidth'], defaultPanelWidth, minPanelWidth,
            maxPanelWidth),
        _clampJson(json['rightWidth'], defaultPanelWidth, minPanelWidth,
            maxPanelWidth),
        _clampJson(json['leftSplit'], defaultSplit, minSplit, maxSplit),
        _clampJson(json['rightSplit'], defaultSplit, minSplit, maxSplit),
      );
    } catch (_) {
      return RailLayout.initial();
    }
  }

  RailSlot? slotOf(String panelId) {
    for (final slot in RailSlot.values) {
      if (panels[slot]!.contains(panelId)) return slot;
    }
    return null;
  }

  /// 移动图标到目标段指定索引；同段时按移除后的索引插入。
  void move(String panelId, RailSlot to, int index) {
    final from = slotOf(panelId);
    if (from == null) return;
    final source = panels[from]!;
    final target = panels[to]!;
    source.remove(panelId);
    final at = index < 0
        ? 0
        : index > target.length
            ? target.length
            : index;
    target.insert(at, panelId);
    if (from != to && active[from] == panelId) active[from] = null;
  }

  /// 同段内点击：已展开则收起，否则展开或切换。
  void toggle(String panelId) {
    final slot = slotOf(panelId);
    if (slot == null) return;
    active[slot] = active[slot] == panelId ? null : panelId;
  }

  /// 在图标所在段展开该面板。
  void expandInSlot(String panelId) {
    final slot = slotOf(panelId);
    if (slot != null) active[slot] = panelId;
  }

  bool get hasAnyOpenPanel => active.values.any((id) => id != null);

  bool isOpen(String panelId) {
    final slot = slotOf(panelId);
    return slot != null && active[slot] == panelId;
  }

  /// 按左上、左下、右上、右下顺序合并，供窄屏使用。
  List<String> get mergedPanels => [
        for (final slot in RailSlot.values) ...panels[slot]!,
      ];

  Map<String, dynamic> toJson() => {
        'panels': {
          for (final slot in RailSlot.values)
            slot.name: List<String>.from(panels[slot]!),
        },
        'active': {
          for (final slot in RailSlot.values) slot.name: active[slot],
        },
        'leftWidth': leftWidth,
        'rightWidth': rightWidth,
        'leftSplit': leftSplit,
        'rightSplit': rightSplit,
      };

  static Map<RailSlot, List<String>> _normalizePanels(
      Map<RailSlot, List<String>>? input) {
    final seen = <String>{};
    final result = <RailSlot, List<String>>{};
    for (final slot in RailSlot.values) {
      final list = <String>[];
      for (final id in input?[slot] ?? const <String>[]) {
        if (allPanels.contains(id) && seen.add(id)) list.add(id);
      }
      result[slot] = list;
    }
    // 目录树缺失时补到左上段首位。
    if (seen.add(tree)) {
      result[RailSlot.leftTop]!.insert(0, tree);
    }
    _fillMissing(result, seen);
    return result;
  }

  /// 缺失的已知 id 追加到右上段末尾。
  static void _fillMissing(
      Map<RailSlot, List<String>> panels, Set<String> seen) {
    panels[RailSlot.rightTop]!.addAll([
      for (final id in allPanels)
        if (!seen.contains(id)) id,
    ]);
  }

  static double _clampOr(
      double? value, double fallback, double min, double max) {
    final d = value ?? fallback;
    if (d.isNaN || d.isInfinite) return fallback;
    return d.clamp(min, max).toDouble();
  }

  static double _clampJson(
      Object? value, double fallback, double min, double max) {
    if (value is! num) return fallback;
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return fallback;
    return d.clamp(min, max).toDouble();
  }
}
