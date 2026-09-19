import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../common/long_press_drag_listener.dart';
import '../widgets/view_toggle.dart';

/// 大纲条目：卷分组头或章节卡片。
class _Entry {
  const _Entry.header(this.volume) : chapter = null;
  const _Entry.chapter(this.chapter) : volume = null;

  final Volume? volume;
  final Chapter? chapter;
  bool get isHeader => volume != null;
}

/// 大纲视图（FR-8 / 9.2）：按卷分组的章节大纲卡片，卷可收起，
/// 支持列表 / 网格两种视图切换；列表视图长按拖动调整卷内顺序。
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({super.key, required this.book});

  final Book book;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  /// 已收起的卷 id（默认全部展开）。
  final Set<String> _collapsedVolumes = {};

  /// 当前 hover 的卷头 id。
  final Set<String> _hoveredHeaders = {};

  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _gridView = context.read<SettingsController>().outlineGridView;
  }

  /// 按卷在书树中的顺序分组，保持章节在卷内的排列；
  /// 卷树中找不到的章节兜底归入"未分卷"。
  List<MapEntry<Volume?, List<Chapter>>> _groupedChapters(
      List<Volume> volumes, List<Chapter> chapters) {
    final byVolume = <String, List<Chapter>>{};
    for (final c in chapters) {
      byVolume.putIfAbsent(c.volumeId, () => []).add(c);
    }
    final groupedIds = <String>{};
    final groups = <MapEntry<Volume?, List<Chapter>>>[];
    for (final v in volumes) {
      final list = byVolume[v.id];
      if (list == null || list.isEmpty) continue;
      groupedIds.add(v.id);
      groups.add(MapEntry(v, list));
    }
    final orphans = [
      for (final c in chapters) if (!groupedIds.contains(c.volumeId)) c,
    ];
    if (orphans.isNotEmpty) {
      groups.add(MapEntry(null, orphans));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapters = state.chapterList;
    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: chapters.isEmpty
              ? const Center(child: Text('暂无章节'))
              : _gridView
                  ? _buildGridBody(state, chapters)
                  : _buildListBody(state, chapters),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(children: [
        Text('大纲',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const Spacer(),
        ViewToggleGroup(
          gridView: _gridView,
          onChanged: (grid) {
            setState(() => _gridView = grid);
            context.read<SettingsController>().setOutlineGridView(grid);
          },
        ),
      ]),
    );
  }

  // ---------- 列表视图 ----------

  Widget _buildListBody(AppState state, List<Chapter> chapters) {
    final groups = _groupedChapters(state.volumeTree, chapters);
    final counts = <String, int>{};
    for (final c in chapters) {
      counts[c.volumeId] = (counts[c.volumeId] ?? 0) + 1;
    }
    final entries = <_Entry>[];
    for (final g in groups) {
      entries.add(_Entry.header(g.key));
      for (final c in g.value) {
        entries.add(_Entry.chapter(c));
      }
    }
    // 收起的卷只保留标题行，隐藏其下章节卡片。
    var currentCollapsed = false;
    final visibleEntries = <_Entry>[];
    for (final e in entries) {
      if (e.isHeader) {
        currentCollapsed = _collapsedVolumes.contains(e.volume?.id ?? '_orphan');
        visibleEntries.add(e);
      } else if (!currentCollapsed) {
        visibleEntries.add(e);
      }
    }
    // 章节条目在可见条目中的下标，用于拖拽索引换算。
    final chapterItemIndices = [
      for (var i = 0; i < visibleEntries.length; i++)
        if (!visibleEntries[i].isHeader) i,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: ReorderableListView.builder(
        itemCount: visibleEntries.length,
        buildDefaultDragHandles: false,
        onReorder: (oldIndex, newIndex) => _onReorder(
            state, visibleEntries, chapterItemIndices, oldIndex, newIndex),
        itemBuilder: (ctx, i) {
          final entry = visibleEntries[i];
          if (entry.isHeader) {
            return _volumeHeader(
              entry.volume,
              counts[entry.volume?.id] ?? 0,
              key: ValueKey('v:${entry.volume?.id ?? '_orphan'}'),
            );
          }
          return LongPressDragStartListener(
            key: ValueKey(entry.chapter!.id),
            index: i,
            child: _OutlineCard(
              chapter: entry.chapter!,
              onTap: () => _editOutline(context, entry.chapter!),
            ),
          );
        },
      ),
    );
  }

  /// 拖拽换算：全局条目索引 → 章节在其所属卷内的顺序，仅支持卷内排序。
  Future<void> _onReorder(
    AppState state,
    List<_Entry> entries,
    List<int> chapterItemIndices,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final oldPos = chapterItemIndices.indexOf(oldIndex);
    if (oldPos < 0) return; // 卷头不可拖动
    final dragged = state.chapterList[oldPos];
    final volumeId = dragged.volumeId;
    final volumeChapters =
        state.chapterList.where((c) => c.volumeId == volumeId).toList();
    // 目标落点在全书章节序列中的位置。
    var dropPos = chapterItemIndices.where((i) => i < newIndex).length;
    // 夹取到被拖章节所在卷的范围内，禁止跨卷移动。
    final volStart = state.chapterList.indexOf(volumeChapters.first);
    final volEnd = volStart + volumeChapters.length;
    dropPos = dropPos.clamp(volStart, volEnd);
    final localPos = dropPos - volStart;
    final ids = volumeChapters.map((c) => c.id).toList();
    final localOld = ids.indexOf(dragged.id);
    if (localPos == localOld || localPos == localOld + 1) return;
    ids.removeAt(localOld);
    ids.insert(localPos.clamp(0, ids.length), dragged.id);
    await state.reorderChapters(volumeId, ids);
  }

  // ---------- 网格视图 ----------

  Widget _buildGridBody(AppState state, List<Chapter> chapters) {
    final groups = _groupedChapters(state.volumeTree, chapters);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in groups) ...[
            _volumeHeader(g.key, g.value.length),
            if (!_collapsedVolumes.contains(g.key?.id ?? '_orphan'))
              _volumeGrid(g.value),
          ],
        ],
      ),
    );
  }

  Widget _volumeGrid(List<Chapter> list) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      final columns = (width ~/ 190).clamp(1, 4);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: list.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 180,
        ),
        itemBuilder: (ctx, i) => _OutlineCard(
          chapter: list[i],
          outlineMaxLines: 5,
          tightMargin: true,
          onTap: () => _editOutline(context, list[i]),
        ),
      );
    });
  }

  // ---------- 卷头与卡片 ----------

  Widget _volumeHeader(Volume? volume, int chapterCount, {Key? key}) {
    final volumeId = volume?.id ?? '_orphan';
    final collapsed = _collapsedVolumes.contains(volumeId);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      onTap: () => setState(() {
        if (collapsed) {
          _collapsedVolumes.remove(volumeId);
        } else {
          _collapsedVolumes.add(volumeId);
        }
      }),
      borderRadius: BorderRadius.circular(6),
      mouseCursor: SystemMouseCursors.click,
      onHover: (hovering) => setState(() {
        if (hovering) {
          _hoveredHeaders.add(volumeId);
        } else {
          _hoveredHeaders.remove(volumeId);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hoveredHeaders.contains(volumeId)
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.menu_book, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                volume?.name ?? '未分卷',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$chapterCount 章',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 点击卡片直接编辑大纲；超过 200 字自动截断。
  Future<void> _editOutline(BuildContext context, Chapter chapter) async {
    final state = context.read<AppState>();
    final text = await inputDialog(
      context,
      title: '本章大纲',
      initial: chapter.outline,
      hint: '写一两句本章要点',
      maxLines: 8,
      width: 400,
    );
    if (text != null) {
      final trimmed = text.length > AppConstants.outlineMaxLength
          ? text.substring(0, AppConstants.outlineMaxLength)
          : text;
      await state.chapters.updateOutline(chapter, trimmed);
      await state.reloadTreePublic();
    }
  }
}

/// 章节大纲卡片，样式与伏笔面板列表卡片一致：细边框 + hover 加深。
class _OutlineCard extends StatefulWidget {
  const _OutlineCard({
    required this.chapter,
    required this.onTap,
    this.outlineMaxLines = 3,
    this.tightMargin = false,
  });

  final Chapter chapter;
  final VoidCallback onTap;
  final int outlineMaxLines;

  /// 网格模式下去掉底部外边距（由网格 spacing 控制）。
  final bool tightMargin;

  @override
  State<_OutlineCard> createState() => _OutlineCardState();
}

class _OutlineCardState extends State<_OutlineCard> {
  bool _hover = false;

  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return t.year == DateTime.now().year
        ? '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}'
        : '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.tightMargin ? 0 : 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: _hover
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hover
                      ? scheme.outlineVariant
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (widget.chapter.outlineEditedAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(widget.chapter.outlineEditedAt!),
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.chapter.outline.isEmpty
                        ? '（未填写大纲）'
                        : widget.chapter.outline,
                    maxLines: widget.outlineMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(height: 1.5),
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
