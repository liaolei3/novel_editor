import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/chapter_title_suggest.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_stats.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../app_root.dart';
import '../common/dialogs.dart';
import '../common/context_menu.dart';
import '../common/long_press_drag_listener.dart';

/// 作品树（9.2 左栏）：卷 → 章，支持新建/重命名/删除/拖拽排序/置顶（FR-6/7）。
/// 卷/章操作入口为右键菜单；章节排序通过行尾拖动手柄长按拖动完成。
class BookTree extends StatelessWidget {
  const BookTree({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapters = state.chapterList;
    final std = context.watch<SettingsController>().countStandard;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'tree-add',
        tooltip: '新建卷',
        mouseCursor: SystemMouseCursors.click,
        child: const Icon(Icons.post_add),
        onPressed: () => _addVolume(context, state),
      ),
      body: state.volumeTree.isEmpty
          ? Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建卷'),
                onPressed: () => _addVolume(context, state),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.volumeTree.length,
              itemBuilder: (ctx, i) {
                final volume = state.volumeTree[i];
                final inVolume = chapters
                    .where((c) => c.volumeId == volume.id)
                    .toList();
                final volumeChars = inVolume.fold<int>(
                  0,
                  (sum, c) => sum + TextStats.count(
                    RichTextCodec.plainTextFromDeltaJson(c.content),
                    std,
                  ),
                );
                return GestureDetector(
                  onSecondaryTapUp: (details) =>
                      _showVolumeMenu(context, volume, details.globalPosition),
                  child: Column(
                    children: [
                      if (i > 0) const Divider(height: 1),
                      _VolumeTile(
                        volume: volume,
                        chapters: inVolume,
                        charCount: volumeChars,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showVolumeMenu(
    BuildContext context,
    Volume volume,
    Offset position,
  ) async {
    final state = context.read<AppState>();
    final action = await showAppContextMenu<String>(context, position, const [
      AppMenuItem('add', '新建章节', icon: Icons.post_add_outlined),
      AppMenuItem('rename', '重命名', icon: Icons.edit_outlined),
      AppMenuItem('delete', '删除', icon: Icons.delete_outline, destructive: true),
    ]);
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'rename':
        final name = await inputDialog(
          context,
          title: '重命名卷',
          initial: volume.name,
        );
        if (name != null && name.trim().isNotEmpty) {
          await state.renameVolume(volume.id, name.trim());
        }
        break;
      case 'add':
        await _createChapter(context, state, volume.id);
        break;
      case 'delete':
        final ok = await confirmDangerous(
          context,
          '删除卷「${volume.name}」及其下所有章节？内容将进入回收站保留 30 天。',
        );
        if (ok) await state.deleteVolume(volume.id);
        break;
    }
  }

  static Future<void> _showChapterMenu(
    BuildContext context,
    Chapter chapter,
    Offset position,
  ) async {
    final state = context.read<AppState>();
    final action = await showAppContextMenu<String>(context, position, [
      const AppMenuItem('rename', '重命名', icon: Icons.edit_outlined),
      AppMenuItem(
        'pin',
        chapter.pinned ? '取消置顶' : '置顶',
        icon: Icons.push_pin_outlined,
      ),
      const AppMenuItem('delete', '删除', icon: Icons.delete_outline, destructive: true),
    ]);
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'rename':
        final name = await inputDialog(
          context,
          title: '重命名章节',
          initial: chapter.title,
        );
        if (name != null && name.trim().isNotEmpty) {
          await state.renameChapter(chapter.id, name.trim());
        }
        break;
      case 'pin':
        await state.togglePin(chapter.id);
        break;
      case 'delete':
        final ok = await confirmDangerous(
          context,
          '删除章节「${chapter.title}」？将进入回收站保留 30 天。',
        );
        if (ok) await state.deleteChapter(chapter.id);
        break;
    }
  }

  Future<void> _addVolume(BuildContext context, AppState state) async {
    final name = await inputDialog(
      context,
      title: '新建卷',
      initial: suggestVolumeTitle(state.volumeTree.map((v) => v.name)),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.addVolume(name.trim());
    }
  }

  /// 新建章节：预填该卷下一章标题（如已有 3 章则预填「第四章」），创建后自动打开该章。
  static Future<void> _createChapter(
    BuildContext context,
    AppState state,
    String volumeId,
  ) async {
    final inVolume =
        state.chapterList.where((c) => c.volumeId == volumeId).toList();
    final name = await inputDialog(
      context,
      title: '新建章节',
      initial: suggestChapterTitle(inVolume.map((c) => c.title)),
    );
    if (name == null || name.trim().isEmpty) return;
    final ch = await state.addChapter(volumeId, title: name.trim());
    await state.openChapter(ch);
  }
}

/// 卷标题行：左侧展开三角 + 卷名，行尾为卷字数；下方章节列表可展开/收起。
/// 自定义头部（非 ExpansionTile），左右内边距与章节行一致，保证字数右对齐。
class _VolumeTile extends StatefulWidget {
  const _VolumeTile({
    required this.volume,
    required this.chapters,
    required this.charCount,
  });

  final Volume volume;
  final List<Chapter> chapters;
  final int charCount;

  @override
  State<_VolumeTile> createState() => _VolumeTileState();
}

class _VolumeTileState extends State<_VolumeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapters = widget.chapters;
    final scheme = Theme.of(context).colorScheme;
    // 当前打开章节所在的卷，标题染主色以标示归属。
    final containsCurrent =
        state.currentChapter?.volumeId == widget.volume.id;
    final children = Column(
      key: ValueKey(widget.volume.id),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 卷与第一章之间的分隔线，随展开/收起一起显隐。
        const Divider(height: 1),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: chapters.length,
          onReorder: (oldIndex, newIndex) async {
            final ids = chapters.map((c) => c.id).toList();
            if (newIndex > oldIndex) newIndex--;
            ids.insert(newIndex, ids.removeAt(oldIndex));
            await state.reorderChapters(widget.volume.id, ids);
          },
          itemBuilder: (ctx, j) => LongPressDragStartListener(
            key: ValueKey(chapters[j].id),
            index: j,
            child: _ChapterTile(chapter: chapters[j]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 48,
            child: Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建章节'),
                onPressed: () =>
                    BookTree._createChapter(context, state, widget.volume.id),
              ),
            ),
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    // 展开状态三角：向右收起、向下展开。
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.arrow_right, size: 22),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.volume.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 14,
                          color: containsCurrent ? scheme.primary : null,
                          fontWeight: containsCurrent
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.charCount} 字',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: children,
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.fastOutSlowIn,
        ),
      ],
    );
  }
}

/// 章节行：无左侧图标，整行长按拖动排序，右键弹操作菜单。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter});

  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final std = context.watch<SettingsController>().countStandard;
    final scheme = Theme.of(context).colorScheme;
    final selected = state.currentChapter?.id == chapter.id;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          BookTree._showChapterMenu(context, chapter, details.globalPosition),
      child: Stack(
        children: [
          ListTile(
            minTileHeight: 48,
            titleTextStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 14,
              color: selected ? scheme.primary : null,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
            selected: selected,
            selectedTileColor: scheme.primary.withValues(alpha: 0.08),
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            contentPadding: const EdgeInsets.only(left: 42, right: 16),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chapter.pinned) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.push_pin,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  '${TextStats.count(RichTextCodec.plainTextFromDeltaJson(chapter.content), std)} 字',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            onTap: () => state.openChapter(chapter),
          ),
          // 选中态左侧主色竖条，与淡主色底、主色标题共同标示当前章节。
          if (selected)
            Positioned(
              left: 26,
              top: 12,
              bottom: 12,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
