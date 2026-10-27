import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';

/// 章节标签栏：点击切换章节，悬浮显示关闭按钮；溢出时滚轮横向滚动，
/// 当前标签自动滚入可视区。视觉样式与书籍标签一致。
class ChapterTabs extends StatefulWidget {
  const ChapterTabs({super.key});

  @override
  State<ChapterTabs> createState() => _ChapterTabsState();
}

class _ChapterTabsState extends State<ChapterTabs> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _tabKeys = {};
  String? _lastSelectedId;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 新打开 / 切到的标签自动滚入可视区。
  void _ensureVisible(String? id) {
    if (id == null || id == _lastSelectedId) return;
    _lastSelectedId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[id]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  /// 鼠标滚轮横向滚动。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    final pos = _scroll.position;
    final target = (pos.pixels + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    if (target == pos.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_scroll.hasClients) _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tabs = state.chapterTabs;
    final selectedId = state.currentChapter?.id;
    final volumeNames = {
      for (final v in state.volumeTree) v.id: v.name,
    };
    _ensureVisible(selectedId);
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final chapter in tabs)
              _ChapterTab(
                key: _tabKeys.putIfAbsent(chapter.id, () => GlobalKey()),
                chapter: chapter,
                volumeName: volumeNames[chapter.volumeId],
                selected: chapter.id == selectedId,
                onSelect: () => state.openChapter(chapter),
                onClose: () => state.closeChapterTab(chapter.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单个章节标签：章节图标 + 章名，选中底色更深，悬浮显示关闭按钮。
class _ChapterTab extends StatefulWidget {
  const _ChapterTab({
    super.key,
    required this.chapter,
    required this.volumeName,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final Chapter chapter;
  final String? volumeName;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_ChapterTab> createState() => _ChapterTabState();
}

class _ChapterTabState extends State<_ChapterTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 界面字号放大后中文字形的视觉中心偏移更大，图标随之下移。
    final iconDy =
        MediaQuery.textScalerOf(context).scale(1.0) > 1.0 ? 2.0 : 1.0;
    final volume = widget.volumeName;
    final tooltip = volume == null || volume.isEmpty
        ? widget.chapter.title
        : '$volume · ${widget.chapter.title}';
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onSelect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(
                  alpha: widget.selected ? 0.22 : (_hover ? 0.16 : 0.10),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: Offset(0, iconDy),
                    child: Icon(Icons.article_outlined,
                        size: 16, color: scheme.primary),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      widget.chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  // 关闭按钮位置常驻，仅切换显隐，避免悬浮时标签宽度变化。
                  const SizedBox(width: 2),
                  IgnorePointer(
                    ignoring: !_hover && !widget.selected,
                    child: AnimatedOpacity(
                      opacity: _hover || widget.selected ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Tooltip(
                        message: '关闭标签',
                        child: GestureDetector(
                          onTap: widget.onClose,
                          child: Transform.translate(
                            offset: Offset(0, iconDy),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
