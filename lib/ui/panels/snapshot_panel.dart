import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_stats.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../common/dialogs.dart';
import '../widgets/app_icon.dart';
import '../widgets/toast.dart';

/// 历史快照面板（FR-9 / 9.5）：快照列表、两版本对比、一键回滚（回滚前自动建快照）。
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
        ListTile(
          dense: true,
          title: Text('「${chapter.title}」历史快照'),
          subtitle: Text(
            '保留最近 50 个（手动 / 每日自动 / 回滚前）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: IconButton(
            tooltip: '创建手动快照',
            icon: const AppIcon(Icons.add_a_photo_outlined),
            onPressed: () async {
              await state.durability.manualSnapshot(chapter);
              await _refresh();
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _snaps.isEmpty
              ? const Center(child: Text('暂无快照'))
              : ListView.builder(
                  itemCount: _snaps.length,
                  itemBuilder: (ctx, i) {
                    final snap = _snaps[i];
                    final label = switch (snap.type) {
                      SnapshotType.manual => '手动',
                      SnapshotType.auto => '自动',
                      SnapshotType.rollback => '回滚前',
                    };
                    return ListTile(
                      dense: true,
                      leading: AppIcon(_iconFor(snap.type), size: 18),
                      title: Text(
                        snap.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '$label · ${TextStats.charCount(RichTextCodec.plainTextFromDeltaJson(snap.content))} 字',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            child: const Text('对比'),
                            onPressed: () => showCompareDialog(
                              context,
                              title: '快照对比',
                              leftLabel: '快照：${snap.title}',
                              rightLabel: '当前版本',
                              left: RichTextCodec.plainTextFromDeltaJson(
                                snap.content,
                              ),
                              right: RichTextCodec.plainTextFromDeltaJson(
                                chapter.content,
                              ),
                            ),
                          ),
                          TextButton(
                            child: const Text('回滚'),
                            onPressed: () => _rollback(context, snap),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _rollback(BuildContext context, Snapshot snap) async {
    final state = context.read<AppState>();
    final chapter = state.currentChapter!;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
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
      showToast(context, '已回滚；当前版本已存为「回滚前」快照');
    }
  }

  IconData _iconFor(SnapshotType type) => switch (type) {
    SnapshotType.manual => Icons.back_hand_outlined,
    SnapshotType.auto => Icons.schedule,
    SnapshotType.rollback => Icons.undo,
  };
}
