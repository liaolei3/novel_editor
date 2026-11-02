import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/text_stats.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/editor_layout.dart';
import '../../state/settings_controller.dart';

import 'editor_pane.dart';
import 'fireworks.dart';
import 'write_stats_bubble.dart';

/// 编辑区容器：按布局树递归渲染水平 / 垂直分割的窗格。
/// 目标达成烟花在此订阅一次，避免每个窗格重复订阅。
class EditorArea extends StatefulWidget {
  const EditorArea({
    super.key,
    required this.book,
    this.singlePaneOnly = false,
  });

  final Book book;

  /// 窄屏与窄屏沉浸模式只渲染活动窗格，不显示分隔条与关闭按钮。
  final bool singlePaneOnly;

  @override
  State<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<EditorArea> {
  late final AppState _appState;

  StreamSubscription<List<String>>? _goalFireworksSub;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _goalFireworksSub = _appState.goalToasts.listen((msgs) {
      if (mounted) showFireworks(context, msgs);
    });
  }

  @override
  void dispose() {
    _goalFireworksSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final content = widget.singlePaneOnly
        ? EditorPane(
            key: ValueKey(state.activePaneId),
            book: widget.book,
            paneId: state.activePaneId,
            allowSplitDrop: false,
          )
        : _buildNode(
            state,
            state.editorLayout.root,
            const <int>[],
            state.editorPaneIds.length,
          );
    // 全局状态栏只渲染一次，汇总活动窗格本章与全书 / 今日等全局数据。
    return Column(
      children: [
        Expanded(child: content),
        const _GlobalStatusBar(),
      ],
    );
  }

  /// 递归渲染布局节点；[path] 为从根到当前分割节点的 0/1 索引路径。
  Widget _buildNode(
    AppState state,
    EditorLayoutNode node,
    List<int> path,
    int paneCount,
  ) {
    if (node is EditorPaneNode) {
      final pane = EditorPane(
        key: ValueKey(node.paneId),
        book: widget.book,
        paneId: node.paneId,
        showCloseButton: paneCount > 1,
        allowSplitDrop: !widget.singlePaneOnly,
        onClose: () => state.closePane(node.paneId),
      );
      // 焦点状态由各窗格的章节标签栏表达，窗格本体不加描边。
      return pane;
    }

    final split = node as EditorSplitNode;
    final horizontal = split.axis == EditorSplitAxis.horizontal;
    final firstFlex = (split.ratio * 1000).round().clamp(1, 999);
    final secondFlex = 1000 - firstFlex;
    final first = _buildNode(state, split.first, [...path, 0], paneCount);
    final second = _buildNode(state, split.second, [...path, 1], paneCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final extent =
            horizontal ? constraints.maxWidth : constraints.maxHeight;
        final divider = _SplitDivider(
          axis: split.axis,
          ratio: split.ratio,
          extent: extent,
          onRatioChanged: (ratio) =>
              unawaited(state.updateSplitRatio(path, ratio)),
        );
        if (horizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: firstFlex, child: first),
              divider,
              Expanded(flex: secondFlex, child: second),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: firstFlex, child: first),
            divider,
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }
}

/// 编辑区唯一全局状态栏：左侧是活动窗格的当前章节名前缀与目标进度，
/// 右侧是全书 / 今日、字数统计口径与码字面板入口，分屏时不再重复。
class _GlobalStatusBar extends StatelessWidget {
  const _GlobalStatusBar();

  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final std = settings.countStandard;
    final chapter = state.currentChapter;
    final chGoal = state.resolvedChapterGoal;
    final bookGoal = state.currentBook?.goal ?? 0;
    final dailyGoal = settings.dailyGoal;
    final chapterReached = chGoal > 0 && (chapter?.charCount ?? 0) >= chGoal;

    Widget stat(String text, bool reached) => Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: reached ? scheme.primary : null,
              fontWeight: reached ? FontWeight.w600 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );

    return Container(
      height: _height,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(90),
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chapter == null)
                  Text(
                    '未打开章节',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Icon(Icons.article_outlined, size: 14, color: scheme.primary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: chapterReached ? scheme.primary : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    chGoal > 0
                        ? '${chapter.charCount}/$chGoal'
                        : '${chapter.charCount} 字',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: chapterReached ? FontWeight.w600 : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: chapterReached ? scheme.primary : null,
                    ),
                  ),
                ],
                const SizedBox(width: 16),
                stat(
                  bookGoal > 0
                      ? '全书 ${state.bookCharTotal}/$bookGoal'
                      : '全书 ${state.bookCharTotal} 字',
                  bookGoal > 0 && state.bookCharTotal >= bookGoal,
                ),
                const SizedBox(width: 16),
                stat(
                  '今日 ${state.todayChars}/$dailyGoal',
                  state.todayChars >= dailyGoal,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('字数统计口径：${std.label}',
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 10),
                const WriteStatsEntry(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 6px 分隔条：悬停高亮，拖动按位移调整相邻窗格比例。
class _SplitDivider extends StatefulWidget {
  const _SplitDivider({
    required this.axis,
    required this.ratio,
    required this.extent,
    required this.onRatioChanged,
  });

  final EditorSplitAxis axis;
  final double ratio;

  /// 当前分割节点在分割方向上的总尺寸。
  final double extent;
  final ValueChanged<double> onRatioChanged;

  @override
  State<_SplitDivider> createState() => _SplitDividerState();
}

class _SplitDividerState extends State<_SplitDivider> {
  static const double _thickness = 6;

  bool _hover = false;
  bool _dragging = false;
  double _startRatio = 0.5;
  double _dragDelta = 0;

  bool get _horizontal => widget.axis == EditorSplitAxis.horizontal;

  void _onDragStart(DragStartDetails _) {
    _startRatio = widget.ratio;
    _dragDelta = 0;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragDelta += _horizontal ? details.delta.dx : details.delta.dy;
    final available = widget.extent - _thickness;
    if (!available.isFinite || available <= 1) return;
    final ratio = (_startRatio + _dragDelta / available)
        .clamp(EditorLayout.minSplitRatio, EditorLayout.maxSplitRatio)
        .toDouble();
    widget.onRatioChanged(ratio);
  }

  void _onDragEnd() {
    if (!_dragging) return;
    setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hover || _dragging;
    final fillColor = active
        ? scheme.primary.withValues(alpha: 0.12)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final lineColor = active
        ? scheme.primary.withValues(alpha: 0.7)
        : scheme.outlineVariant.withValues(alpha: 0.8);

    return MouseRegion(
      cursor: _horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _horizontal ? _onDragStart : null,
        onHorizontalDragUpdate: _horizontal ? _onDragUpdate : null,
        onHorizontalDragEnd: _horizontal ? (_) => _onDragEnd() : null,
        onHorizontalDragCancel: _horizontal ? _onDragEnd : null,
        onVerticalDragStart: _horizontal ? null : _onDragStart,
        onVerticalDragUpdate: _horizontal ? null : _onDragUpdate,
        onVerticalDragEnd: _horizontal ? null : (_) => _onDragEnd(),
        onVerticalDragCancel: _horizontal ? null : _onDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: _horizontal ? _thickness : null,
          height: _horizontal ? null : _thickness,
          color: fillColor,
          alignment: Alignment.center,
          child: Container(
            width: _horizontal ? 1 : double.infinity,
            height: _horizontal ? double.infinity : 1,
            color: lineColor,
          ),
        ),
      ),
    );
  }
}
