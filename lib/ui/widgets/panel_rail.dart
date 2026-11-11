import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/rail_layout.dart';

/// rail 图标列宽度。
const double panelRailWidth = 48;

/// rail 图标按钮高度。
const double panelRailButtonHeight = 44;

/// 面板 id 对应的中文标题。
String panelRailTitle(String panelId) {
  switch (panelId) {
    case RailLayout.tree:
      return '目录';
    case RailLayout.outline:
      return '章纲';
    case RailLayout.snapshot:
      return '历史快照';
    case RailLayout.character:
      return '角色';
    case RailLayout.foreshadow:
      return '伏笔';
    case RailLayout.sensitive:
      return '敏感词';
    case RailLayout.recycle:
      return '回收站';
    case RailLayout.preview:
      return '预览';
  }
  return panelId;
}

/// 面板 id 对应的图标。
IconData panelRailIcon(String panelId) {
  switch (panelId) {
    case RailLayout.tree:
      return Icons.menu_book_outlined;
    case RailLayout.outline:
      return Icons.account_tree_outlined;
    case RailLayout.snapshot:
      return Icons.history;
    case RailLayout.character:
      return Icons.people_outlined;
    case RailLayout.foreshadow:
      return Icons.flag_outlined;
    case RailLayout.sensitive:
      return Icons.shield_outlined;
    case RailLayout.recycle:
      return Icons.delete_outline;
    case RailLayout.preview:
      return Icons.visibility_outlined;
  }
  return Icons.widgets_outlined;
}

/// 拖动中的面板图标数据：面板 id 与来源段。
@immutable
class PanelRailDragData {
  const PanelRailDragData({required this.panelId, required this.from});

  final String panelId;
  final RailSlot from;
}

/// 图标列底色与内外侧描边。
BoxDecoration panelRailDecoration(ColorScheme scheme, bool borderOnRight) {
  final side = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6));
  return BoxDecoration(
    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
    border: Border(
      left: borderOnRight ? BorderSide.none : side,
      right: borderOnRight ? side : BorderSide.none,
    ),
  );
}

/// 单段图标列：点击切换面板，拖动可段内排序或拖到其他段。
class PanelRailColumn extends StatefulWidget {
  const PanelRailColumn({
    super.key,
    required this.slot,
    required this.panelIds,
    required this.activeId,
    required this.borderOnRight,
    required this.onTap,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onDrop,
    this.dragging = false,
    this.decorated = true,
  });

  final RailSlot slot;
  final List<String> panelIds;
  final String? activeId;

  /// true 时描边在右侧（左侧停靠区），false 时在左侧（右侧停靠区）。
  final bool borderOnRight;
  final ValueChanged<String> onTap;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final void Function(PanelRailDragData data, int index) onDrop;

  /// 是否处于全局拖动中（按钮显示抓取指针）。
  final bool dragging;

  /// 是否自带底色与描边；由外层统一绘制时置 false。
  final bool decorated;

  @override
  State<PanelRailColumn> createState() => _PanelRailColumnState();
}

class _PanelRailColumnState extends State<PanelRailColumn> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _boxKey = GlobalKey();
  int? _insertIndex;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 滚动时刷新插入线位置。
  void _onScroll() {
    if (_insertIndex != null && mounted) setState(() {});
  }

  /// 由全局落点换算段内插入索引。
  int _indexAt(double globalY) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    final top = box?.localToGlobal(Offset.zero).dy ?? 0;
    final local = globalY - top + _scroll.offset;
    return (local / panelRailButtonHeight)
        .round()
        .clamp(0, widget.panelIds.length)
        .toInt();
  }

  void _clearInsert() {
    if (_insertIndex != null) setState(() => _insertIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = DragTarget<PanelRailDragData>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final index = _indexAt(details.offset.dy);
        if (index != _insertIndex) setState(() => _insertIndex = index);
      },
      onLeave: (_) => _clearInsert(),
      onAcceptWithDetails: (details) {
        final index = _indexAt(details.offset.dy);
        _clearInsert();
        widget.onDrop(details.data, index);
      },
      builder: (context, candidate, _) {
        final hovered = candidate.isNotEmpty;
        return Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    children: [
                      for (final id in widget.panelIds) _draggableButton(id),
                    ],
                  ),
                ),
              ),
            ),
            if (hovered)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DashedRectPainter(
                      color: hovered
                          ? scheme.primary.withValues(alpha: 0.55)
                          : scheme.primary.withValues(alpha: 0.2),
                      fill: hovered
                          ? scheme.primary.withValues(alpha: 0.06)
                          : null,
                    ),
                  ),
                ),
              ),
            if (hovered && _insertIndex != null)
              Positioned(
                left: 1,
                right: 1,
                top: _insertIndex! * panelRailButtonHeight - _scroll.offset - 2,
                child: IgnorePointer(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    return SizedBox(
      key: _boxKey,
      width: panelRailWidth,
      child: widget.decorated
          ? DecoratedBox(
              decoration: panelRailDecoration(scheme, widget.borderOnRight),
              child: content,
            )
          : content,
    );
  }

  /// 图标按钮包装为可拖拽项，原位置保留半透明占位。
  Widget _draggableButton(String id) {
    final data = PanelRailDragData(panelId: id, from: widget.slot);
    return Draggable<PanelRailDragData>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // 残影跟随指针居中，半透明以便透出下方的插入位置提示。
      feedback: Transform.translate(
        offset: const Offset(
          -panelRailButtonHeight / 2,
          -panelRailButtonHeight / 2,
        ),
        child: Opacity(
          opacity: 0.55,
          child: _RailDragFeedback(panelId: id),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _RailIconButton(
          panelId: id,
          selected: widget.activeId == id,
          onTap: null,
          dragging: widget.dragging,
        ),
      ),
      onDragStarted: widget.onDragStarted,
      onDragEnd: (_) => widget.onDragEnd(),
      onDragCompleted: widget.onDragEnd,
      onDraggableCanceled: (_, _) => widget.onDragEnd(),
      child: _RailIconButton(
        panelId: id,
        selected: widget.activeId == id,
        onTap: () => widget.onTap(id),
        dragging: widget.dragging,
      ),
    );
  }
}

/// 单段整段投放区：图标列与同段面板区/空白区均可高亮并接受投放。
class PanelRailDropArea extends StatefulWidget {
  const PanelRailDropArea({
    super.key,
    required this.slot,
    required this.railOnLeft,
    required this.enabled,
    required this.dropIndex,
    required this.onDrop,
    this.includeRail = true,
    required this.child,
  });

  final RailSlot slot;

  /// true 时图标列位于左端，false 时位于右端。
  final bool railOnLeft;

  /// 投放区是否包含图标列；仅包裹面板区时置 false。
  final bool includeRail;

  /// 是否处于拖动中。
  final bool enabled;

  /// 外层投放时追加到的索引。
  final int dropIndex;
  final void Function(PanelRailDragData data, int index) onDrop;
  final Widget child;

  @override
  State<PanelRailDropArea> createState() => _PanelRailDropAreaState();
}

class _PanelRailDropAreaState extends State<PanelRailDropArea> {
  bool _hovered = false;

  @override
  void didUpdateWidget(PanelRailDropArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hovered = false;
  }

  void _setHover(bool value) {
    if (mounted && _hovered != value) setState(() => _hovered = value);
  }

  /// 指针落在图标列内时清除外层高亮，交给内层精确计算索引。
  void _onMove(DragTargetDetails<PanelRailDragData> details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final localX = box.globalToLocal(details.offset).dx;
    final inRail =
        widget.includeRail &&
        (widget.railOnLeft
            ? localX < panelRailWidth
            : localX > box.size.width - panelRailWidth);
    _setHover(!inRail);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<PanelRailDragData>(
      onWillAcceptWithDetails: (_) => widget.enabled,
      onMove: _onMove,
      onLeave: (_) => _setHover(false),
      onAcceptWithDetails: (details) {
        _setHover(false);
        widget.onDrop(details.data, widget.dropIndex);
      },
      builder: (context, _, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !widget.enabled,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            widget.child,
            if (widget.enabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DashedRectPainter(
                      color: scheme.primary.withValues(
                        alpha: _hovered ? 0.55 : 0.2,
                      ),
                      fill: _hovered
                          ? scheme.primary.withValues(alpha: 0.06)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 空段在拖动期间显示的虚线投放条。
class PanelRailDropStub extends StatefulWidget {
  const PanelRailDropStub({
    super.key,
    required this.slot,
    required this.borderOnRight,
    required this.onDrop,
    this.decorated = true,
  });

  final RailSlot slot;
  final bool borderOnRight;
  final void Function(PanelRailDragData data, int index) onDrop;

  /// 是否自带底色与描边；由外层统一绘制时置 false。
  final bool decorated;

  @override
  State<PanelRailDropStub> createState() => _PanelRailDropStubState();
}

class _PanelRailDropStubState extends State<PanelRailDropStub> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = DragTarget<PanelRailDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => widget.onDrop(details.data, 0),
      builder: (context, candidate, _) {
        final hovered = candidate.isNotEmpty;
        final color = hovered
            ? scheme.primary
            : scheme.outlineVariant.withValues(alpha: 0.9);
        return Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DashedRectPainter(
                  color: color,
                  fill: hovered ? scheme.primary.withValues(alpha: 0.08) : null,
                ),
              ),
              Center(
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: color.withValues(alpha: hovered ? 1 : 0.6),
                ),
              ),
            ],
          ),
        );
      },
    );
    return SizedBox(
      width: panelRailWidth,
      child: widget.decorated
          ? DecoratedBox(
              decoration: panelRailDecoration(scheme, widget.borderOnRight),
              child: content,
            )
          : content,
    );
  }
}

/// 窄屏普通图标列：仅展示与切换，不可拖动。
class PanelRailPlainList extends StatelessWidget {
  const PanelRailPlainList({
    super.key,
    required this.panelIds,
    required this.activeId,
    required this.onTap,
  });

  final List<String> panelIds;
  final String? activeId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: panelRailWidth,
      child: DecoratedBox(
        decoration: panelRailDecoration(scheme, false),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final id in panelIds)
                _RailIconButton(
                  panelId: id,
                  selected: activeId == id,
                  onTap: () => onTap(id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标按钮：选中时 primaryContainer 底色 + 左缘 3px 指示条。
class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.panelId,
    required this.selected,
    required this.onTap,
    this.dragging = false,
  });

  final String panelId;
  final bool selected;
  final VoidCallback? onTap;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: panelRailTitle(panelId),
      waitDuration: const Duration(milliseconds: 400),
      child: Stack(
        children: [
          SizedBox(
            width: panelRailWidth,
            height: panelRailButtonHeight,
            child: Material(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              child: InkWell(
                mouseCursor: dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.click,
                onTap: onTap,
                child: Center(
                  child: Icon(
                    panelRailIcon(panelId),
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: 3,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 拖动时跟随指针的图标。
class _RailDragFeedback extends StatelessWidget {
  const _RailDragFeedback({required this.panelId});

  final String panelId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: panelRailButtonHeight,
        height: panelRailButtonHeight,
        child: Center(
          child: Icon(panelRailIcon(panelId), size: 20, color: scheme.primary),
        ),
      ),
    );
  }
}

/// 可拖动的纵向分隔条：调整左右停靠区面板宽度。
class PanelRailVerticalDivider extends StatefulWidget {
  const PanelRailVerticalDivider({
    super.key,
    this.width = 6,
    required this.onDrag,
    this.onDragEnd,
  });

  final double width;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<PanelRailVerticalDivider> createState() =>
      _PanelRailVerticalDividerState();
}

class _PanelRailVerticalDividerState extends State<PanelRailVerticalDivider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => widget.onDragEnd?.call(),
          child: Center(
            child: Container(
              width: _hovered ? 2 : 1,
              height: double.infinity,
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// 可拖动的水平分隔条：调整同侧上下两段高度比例。
class PanelRailHorizontalDivider extends StatefulWidget {
  const PanelRailHorizontalDivider({
    super.key,
    this.height = 6,
    required this.onDrag,
    this.onDragEnd,
  });

  final double height;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<PanelRailHorizontalDivider> createState() =>
      _PanelRailHorizontalDividerState();
}

class _PanelRailHorizontalDividerState
    extends State<PanelRailHorizontalDivider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => widget.onDrag(details.delta.dy),
          onVerticalDragEnd: (_) => widget.onDragEnd?.call(),
          child: Center(
            child: Container(
              width: double.infinity,
              height: _hovered ? 2 : 1,
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制虚线圆角矩形边框。
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color, this.fill});

  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      const Radius.circular(6),
    );
    if (fill != null) {
      canvas.drawRRect(rrect, Paint()..color = fill!);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 4, metric.length)),
          paint,
        );
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}
