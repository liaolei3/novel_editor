import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/chapter_title_suggest.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../app_root.dart';
import '../common/dialogs.dart';
import '../common/context_menu.dart';
import '../common/long_press_drag_listener.dart';
import 'toast.dart';

/// 书树各行固定高度。偏移量定位依赖该不变量，故同时用于布局与计算，
/// 避免两处各写一个 48 后悄悄漂移。
const double _rowHeight = 48;

/// 卷内「新建章节」块的额外下边距。
const double _addChapterGap = 8;

/// 分隔线高度（卷头之间、卷头与章节列表之间）。
const double _dividerHeight = 1;

/// 作品树（9.2 左栏）：卷 → 章，支持新建/重命名/删除/拖拽排序/置顶（FR-6/7）。
/// 卷/章操作入口为右键菜单；章节排序通过行尾拖动手柄长按拖动完成。
///
/// 卷头与章节行同处一个 [CustomScrollView]，每卷的章节列表是一个独立的
/// [SliverReorderableList]，因此只按视口构建可见行。此前卷内用
/// ListView + shrinkWrap 时，为了让外层算出该项高度，整卷章节（含收起态）
/// 都会被构建与布局，上千章的书下代价与章节总数成正比。
class BookTree extends StatefulWidget {
  const BookTree({super.key, required this.book});

  final Book book;

  @override
  State<BookTree> createState() => _BookTreeState();
}

class _BookTreeState extends State<BookTree> {
  /// 展开的卷 id 集合；进入书籍时只展开当前章所属卷，其余卷收起。
  final Set<String> _expanded = <String>{};

  final ScrollController _controller = ScrollController();

  /// 上一次见到的当前章 id，用于识别切章并安排一次定位。
  String? _lastChapterId;

  /// 是否有待执行的定位。目标卷未展开时先展开，留到下一帧才真正滚动。
  bool _pendingReveal = false;

  /// 本次切章来自「点击树上已可见的行」，跳过定位：行本就看得见，
  /// 硬滚到中间只会让列表无谓地跳。
  bool _suppressRevealOnce = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final volumeId = state.currentChapter?.volumeId;
    if (volumeId != null) _expanded.add(volumeId);
    _lastChapterId = state.currentChapter?.id;
    // 进入书籍时把当前章滚进视野：它可能在一卷上千章的很下面。
    _pendingReveal = true;
  }

  @override
  void didUpdateWidget(BookTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换书时按新书的当前章重置，避免展开态错挂到别的卷。
    if (oldWidget.book.id != widget.book.id) {
      _expanded.clear();
      final state = context.read<AppState>();
      final volumeId = state.currentChapter?.volumeId;
      if (volumeId != null) _expanded.add(volumeId);
      _lastChapterId = state.currentChapter?.id;
      _pendingReveal = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // 按卷分组一次；字数直接取已维护的 char_count。
    // 若在此解析每章 Delta，大书下会退化为 O(卷数 × 全书字数) 的 build 级开销。
    final byVolume = _groupByVolume(state.chapterList);
    final volumeChars = <String, int>{};
    for (final entry in byVolume.entries) {
      var sum = 0;
      for (final c in entry.value) {
        sum += c.charCount;
      }
      volumeChars[entry.key] = sum;
    }
    final volumes = state.volumeTree;

    // 切章（含全局搜索跳章、伏笔/片段跳转、回收站恢复）后安排一次定位。
    final chapterId = state.currentChapter?.id;
    if (chapterId != _lastChapterId) {
      _lastChapterId = chapterId;
      _pendingReveal = true;
    }
    if (_pendingReveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingReveal());
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'tree-add',
        tooltip: '新建卷',
        mouseCursor: SystemMouseCursors.click,
        child: const Icon(Icons.post_add),
        onPressed: () => _addVolume(context, state),
      ),
      body: volumes.isEmpty
          ? Center(
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新建卷'),
                onPressed: () => _addVolume(context, state),
              ),
            )
          : CustomScrollView(
              controller: _controller,
              slivers: [
                for (var i = 0; i < volumes.length; i++)
                  ..._volumeSlivers(
                    context,
                    state,
                    i,
                    volumes[i],
                    byVolume[volumes[i].id] ?? const <Chapter>[],
                    volumeChars[volumes[i].id] ?? 0,
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
    );
  }

  /// 一个卷对应的 slivers：卷头 +（展开时）分隔线、章节列表、新建章节按钮。
  List<Widget> _volumeSlivers(
    BuildContext context,
    AppState state,
    int index,
    Volume volume,
    List<Chapter> chapters,
    int charCount,
  ) {
    final expanded = _expanded.contains(volume.id);
    return [
      SliverToBoxAdapter(
        key: ValueKey('volume-${volume.id}'),
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showVolumeMenu(context, volume, details.globalPosition),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0) const Divider(height: _dividerHeight),
              _VolumeHeader(
                volume: volume,
                charCount: charCount,
                expanded: expanded,
                // 当前打开章节所在的卷，标题染主色以标示归属。
                containsCurrent: state.currentChapter?.volumeId == volume.id,
                onToggle: () => setState(() {
                  if (!_expanded.remove(volume.id)) _expanded.add(volume.id);
                }),
              ),
            ],
          ),
        ),
      ),
      if (expanded) ...[
        // 卷与第一章之间的分隔线，随展开/收起一起显隐。
        SliverToBoxAdapter(
          key: ValueKey('divider-${volume.id}'),
          child: const Divider(height: _dividerHeight),
        ),
        SliverReorderableList(
          key: ValueKey('chapters-${volume.id}'),
          itemCount: chapters.length,
          itemExtent: _rowHeight,
          proxyDecorator: _dragProxyDecorator,
          onReorderItem: (oldIndex, newIndex) async {
            // onReorderItem 已修正过向下移动的 newIndex，不需要再自减。
            final ids = chapters.map((c) => c.id).toList();
            ids.insert(newIndex, ids.removeAt(oldIndex));
            await state.reorderChapters(volume.id, ids);
          },
          itemBuilder: (ctx, j) => LongPressDragStartListener(
            key: ValueKey(chapters[j].id),
            index: j,
            child: _ChapterTile(
              chapter: chapters[j],
              onTap: () => _openChapter(chapters[j]),
            ),
          ),
        ),
        SliverToBoxAdapter(
          key: ValueKey('add-${volume.id}'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: _addChapterGap),
            child: SizedBox(
              height: _rowHeight,
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建章节'),
                  onPressed: () => _createChapter(context, state, volume.id),
                ),
              ),
            ),
          ),
        ),
      ],
    ];
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
          label: '卷名',
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
      const AppMenuItem('goal', '章节目标', icon: Icons.flag_outlined),
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
          label: '章节名',
          initial: chapter.title,
        );
        if (name != null && name.trim().isNotEmpty) {
          await state.renameChapter(chapter.id, name.trim());
        }
        break;
      case 'goal':
        final result = await chapterGoalDialog(
          context,
          chapterTitle: chapter.title,
          goal: chapter.goal,
          defaultGoal: state.currentBook?.chapterGoal ?? 0,
        );
        if (result != null) {
          await state.setChapterGoal(chapter.id, result.$1);
          if (context.mounted) showToast(context, '章节目标保存成功');
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
      label: '卷名',
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
      label: '章节名',
      initial: suggestChapterTitle(inVolume.map((c) => c.title)),
    );
    if (name == null || name.trim().isEmpty) return;
    final ch = await state.addChapter(volumeId, title: name.trim());
    await state.openChapter(ch);
  }

  /// 点击树上的章节行。行必然可见，故标记跳过随后的定位；
  /// 点到当前章时不会切章，也就不会安排定位，不能留下这个标记。
  void _openChapter(Chapter chapter) {
    final state = context.read<AppState>();
    if (state.currentChapter?.id == chapter.id) return;
    _suppressRevealOnce = true;
    state.openChapter(chapter);
  }

  /// 按卷分组章节。chapterList 本身已按 sortNumber 排序，分组后顺序自然保持。
  static Map<String, List<Chapter>> _groupByVolume(List<Chapter> chapters) {
    final byVolume = <String, List<Chapter>>{};
    for (final c in chapters) {
      (byVolume[c.volumeId] ??= <Chapter>[]).add(c);
    }
    return byVolume;
  }

  /// 目标章行在全树中的顶部偏移。依赖所有行等高 + 卷头固定高度，
  /// 只有「已展开的卷」才计入其章节行与新建章节块。
  double _chapterOffset(
    List<Volume> volumes,
    Map<String, List<Chapter>> byVolume,
    int volumeIndex,
    int chapterIndex,
  ) {
    var offset = 0.0;
    for (var i = 0; i < volumeIndex; i++) {
      offset += _rowHeight; // 卷头
      if (i > 0) offset += _dividerHeight; // 卷头内分隔线
      if (_expanded.contains(volumes[i].id)) {
        offset += _dividerHeight; // 章节列表前的分隔线
        offset += (byVolume[volumes[i].id]?.length ?? 0) * _rowHeight;
        offset += _rowHeight + _addChapterGap; // 新建章节块
      }
    }
    offset += _rowHeight; // 当前卷卷头
    if (volumeIndex > 0) offset += _dividerHeight;
    offset += _dividerHeight; // 当前卷章节列表前的分隔线
    offset += chapterIndex * _rowHeight;
    return offset;
  }

  /// 当前章在树中的顶部偏移；找不到返回 null。
  double? _currentChapterOffset(AppState state) {
    final ch = state.currentChapter;
    if (ch == null) return null;
    final volumes = state.volumeTree;
    final volumeIndex = volumes.indexWhere((v) => v.id == ch.volumeId);
    if (volumeIndex < 0) return null;
    final byVolume = _groupByVolume(state.chapterList);
    final chapterIndex =
        byVolume[ch.volumeId]?.indexWhere((c) => c.id == ch.id) ?? -1;
    if (chapterIndex < 0) return null;
    return _chapterOffset(volumes, byVolume, volumeIndex, chapterIndex);
  }

  /// 把当前章滚到视口中间。非点击路径（进入书籍、搜索跳章、伏笔/片段、
  /// 回收站恢复）都走这里，让目标行尽量落在正中而非贴着上边；点击路径
  /// 由 _suppressRevealOnce 拦在门外。
  void _revealCurrentChapter() {
    if (!mounted || !_controller.hasClients) return;
    final top = _currentChapterOffset(context.read<AppState>());
    if (top == null) return;
    final position = _controller.position;
    // 目标行中心对准视口中心；接近列表两端时被 clamp 拉回。
    final target = (top - (position.viewportDimension - _rowHeight) / 2)
        .clamp(0.0, position.maxScrollExtent);
    _controller.jumpTo(target);
  }

  /// 帧末把当前章定位进视野。目标卷未展开时先展开，再等一帧定位。
  void _applyPendingReveal() {
    if (!mounted || !_pendingReveal) return;
    final ch = context.read<AppState>().currentChapter;
    if (ch == null) {
      _pendingReveal = false;
      return;
    }
    if (!_expanded.contains(ch.volumeId)) {
      // 章节行随卷展开才存在：先展开，下一帧再定位。
      setState(() => _expanded.add(ch.volumeId));
      return; // _pendingReveal 保持 true，build 会再排一次帧末回调
    }
    _pendingReveal = false;
    // 点击树上行触发的切章：行本就可见，不滚。
    if (_suppressRevealOnce) {
      _suppressRevealOnce = false;
      return;
    }
    _revealCurrentChapter();
  }
}

/// 拖动中条目的代理装饰：与 [ReorderableListView] 的默认实现一致，
/// 抬起时叠一层 0→6 的阴影。[SliverReorderableList] 本身没有默认代理，
/// 不传的话拖起来的行会失去高度感。
Widget _dragProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final animValue = Curves.easeInOut.transform(animation.value);
      return Material(elevation: lerpDouble(0, 6, animValue)!, child: child);
    },
    child: child,
  );
}

/// 卷标题行：左侧展开三角 + 卷名，行尾为卷字数。
/// 左右内边距与章节行一致，保证字数右对齐。
class _VolumeHeader extends StatelessWidget {
  const _VolumeHeader({
    required this.volume,
    required this.charCount,
    required this.expanded,
    required this.containsCurrent,
    required this.onToggle,
  });

  final Volume volume;
  final int charCount;
  final bool expanded;
  final bool containsCurrent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                // 展开状态三角：向右收起、向下展开。
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.arrow_right, size: 22),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    volume.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 14,
                      color: containsCurrent ? scheme.primary : null,
                      fontWeight: containsCurrent ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$charCount 字',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 章节行：无左侧图标，整行长按拖动排序，右键弹操作菜单。
class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter, required this.onTap});

  final Chapter chapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 只订阅「本行是否为当前章」，避免整树广播时每个已构建行都重建。
    final selected = context.select<AppState, bool>(
      (s) => s.currentChapter?.id == chapter.id,
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => _BookTreeState._showChapterMenu(
        context,
        chapter,
        details.globalPosition,
      ),
      child: Stack(
        children: [
          ListTile(
            minTileHeight: _rowHeight,
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
                  '${chapter.charCount} 字',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            onTap: onTap,
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