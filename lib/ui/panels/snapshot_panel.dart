import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_stats.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../widgets/toast.dart';

/// 历史快照面板（FR-9 / 9.5）：快照时间线、两版本对比、一键回滚（回滚前自动建快照）。
class SnapshotPanel extends StatefulWidget {
  const SnapshotPanel({super.key});

  @override
  State<SnapshotPanel> createState() => _SnapshotPanelState();
}

class _SnapshotPanelState extends State<SnapshotPanel> {
  List<Snapshot> _snaps = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final chapter = context.read<AppState>().currentChapter;
    if (chapter == null) return;
    final list = await context.read<AppState>().snapshots.listByChapter(
      chapter.id,
    );
    if (mounted) setState(() => _snaps = list);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapter = state.currentChapter;
    if (chapter == null) {
      return const Center(child: Text('先打开一个章节，再查看历史快照'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('「${chapter.title}」历史快照',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '保留最近 30 个',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '创建手动快照',
                icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                onPressed: () async {
                  await state.durability.manualSnapshot(chapter);
                  await _refresh();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _snaps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history,
                          size: 36,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text('暂无快照',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                  children: _buildTimeline(context, chapter),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildTimeline(BuildContext context, Chapter chapter) {
    final widgets = <Widget>[];
    widgets.add(_dateHeader(context, '今天'));
    widgets.add(_CurrentVersionTile(chapter: chapter));
    String? lastDay = '今天';
    for (var i = 0; i < _snaps.length; i++) {
      final snap = _snaps[i];
      final day = _dayLabel(snap.createdAt);
      final newGroup = day != lastDay;
      if (newGroup) {
        lastDay = day;
        widgets.add(_dateHeader(context, day));
      }
      final isOverallLast = i == _snaps.length - 1;
      final isLastOfDay =
          isOverallLast || _dayLabel(_snaps[i + 1].createdAt) != day;
      widgets.add(_TimelineTile(
        snap: snap,
        showTopLine: !newGroup,
        showBottomLine: !isOverallLast && !isLastOfDay,
        onCompare: () => showCompareDialog(
          context,
          title: '快照对比',
          leftLabel: '快照：${snap.title}',
          rightLabel: '当前版本',
          left: RichTextCodec.plainTextFromDeltaJson(snap.content),
          right: RichTextCodec.plainTextFromDeltaJson(chapter.content),
        ),
        onRollback: () => _rollback(context, snap),
      ));
    }
    return widgets;
  }

  Widget _dateHeader(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天';
    }
    final y = now.subtract(const Duration(days: 1));
    if (t.year == y.year && t.month == y.month && t.day == y.day) {
      return '昨天';
    }
    if (t.year == now.year) return '${t.month}月${t.day}日';
    return '${t.year}年${t.month}月${t.day}日';
  }

  Future<void> _rollback(BuildContext context, Snapshot snap) async {
    final state = context.read<AppState>();
    final chapter = state.currentChapter!;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          constraints: const BoxConstraints(maxWidth: 320),
          title: const Text('回滚确认'),
          content: const Text('将回滚到所选快照版本。当前版本会先自动保存为「回滚前」快照，操作本身可逆。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('回滚'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await state.durability.rollbackTo(chapter, snap);
    state.replaceDocument(
      RichTextCodec.documentFromContent(chapter.content),
    );
    await state.autosave.flush();
    await _refresh();
    if (context.mounted) {
      showToast(context, '回滚成功；当前版本已存为「回滚前」快照');
    }
  }
}

IconData _iconFor(SnapshotType type) => switch (type) {
  SnapshotType.manual => Icons.back_hand_outlined,
  SnapshotType.auto => Icons.schedule,
  SnapshotType.rollback => Icons.undo,
};

Color _typeColor(SnapshotType type, ColorScheme scheme) => switch (type) {
  SnapshotType.manual => scheme.primary,
  SnapshotType.auto => scheme.tertiary,
  SnapshotType.rollback => scheme.secondary,
};

String _typeLabel(SnapshotType type) => switch (type) {
  SnapshotType.manual => '手动',
  SnapshotType.auto => '自动',
  SnapshotType.rollback => '回滚前',
};

class _TimelineTile extends StatefulWidget {
  const _TimelineTile({
    required this.snap,
    required this.showTopLine,
    required this.showBottomLine,
    required this.onCompare,
    required this.onRollback,
  });

  final Snapshot snap;
  final bool showTopLine;
  final bool showBottomLine;
  final VoidCallback onCompare;
  final VoidCallback onRollback;

  @override
  State<_TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends State<_TimelineTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snap = widget.snap;
    final color = _typeColor(snap.type, scheme);
    final chars = TextStats.count(
      RichTextCodec.plainTextFromDeltaJson(snap.content),
      context.watch<SettingsController>().countStandard,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onCompare,
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _line(scheme, widget.showTopLine),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_iconFor(snap.type), size: 14, color: color),
                    ),
                    Expanded(
                      child: Center(
                        child: _line(scheme, widget.showBottomLine),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _timeText(snap.createdAt),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${_typeLabel(snap.type)} · $chars 字',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _hovering ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IgnorePointer(
                          ignoring: !_hovering,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _actionButton('对比', widget.onCompare),
                              _actionButton('回滚', widget.onRollback),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(ColorScheme scheme, bool visible) {
    return Container(
      width: 2,
      color: visible
          ? scheme.outlineVariant.withValues(alpha: 0.6)
          : Colors.transparent,
    );
  }

  String _timeText(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _actionButton(String text, VoidCallback onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        foregroundColor: scheme.primary,
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _CurrentVersionTile extends StatelessWidget {
  const _CurrentVersionTile({required this.chapter});

  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chars = TextStats.count(
      RichTextCodec.plainTextFromDeltaJson(chapter.content),
      context.watch<SettingsController>().countStandard,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前版本',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                  const SizedBox(height: 1),
                  Text(
                    '$chars 字 · 进行中',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
