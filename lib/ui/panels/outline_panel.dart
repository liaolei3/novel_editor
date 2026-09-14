import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../common/dialogs.dart';
import '../common/long_press_drag_listener.dart';

/// 大纲卡片视图（FR-8 / 9.2）：章节大纲卡片 + 拖拽调整顺序（软木板风格）。
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapters = state.chapterList;
    if (chapters.isEmpty) {
      return const Center(child: Text('暂无章节'));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: ReorderableListView.builder(
        itemCount: chapters.length,
        buildDefaultDragHandles: false,
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > oldIndex) newIndex--;
          final ids = chapters.map((c) => c.id).toList();
          final volumeId = chapters[newIndex.clamp(0, ids.length - 1)].volumeId;
          ids.insert(newIndex.clamp(0, ids.length), ids.removeAt(oldIndex));
          await state.reorderChapters(volumeId, ids);
        },
        itemBuilder: (ctx, i) => LongPressDragStartListener(
          key: ValueKey(chapters[i].id),
          index: i,
          child: _outlineCard(context, chapters[i]),
        ),
      ),
    );
  }

  Widget _outlineCard(BuildContext context, Chapter chapter) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editOutline(context, chapter),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                chapter.outline.isEmpty ? '（未填写大纲）' : chapter.outline,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(height: 1.5),
              ),
            ],
          ),
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
      maxLines: 5,
    );
    if (text != null) {
      final trimmed = text.length > AppConstants.outlineMaxLength
          ? text.substring(0, AppConstants.outlineMaxLength)
          : text;
      await state.chapters.updateOutline(chapter.id, trimmed);
      await state.reloadTreePublic();
    }
  }
}
