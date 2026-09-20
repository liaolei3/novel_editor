import 'package:dart_quill_delta/dart_quill_delta.dart' show Delta;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/foreshadow_delta.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart' show DraggableDialog;
import '../common/foreshadow_dialogs.dart';
import '../widgets/foreshadow_tip.dart' show foreshadowMarkColor;
import '../widgets/tinted_card.dart';
import '../widgets/toast.dart';
import '../widgets/view_toggle.dart';

/// 伏笔面板：列表态（状态筛选 + 卡片）↔ 详情态（编辑 + 片段列表）。
class ForeshadowPanel extends StatefulWidget {
  const ForeshadowPanel({super.key, required this.book, this.openForeshadowId});

  final Book book;

  /// 外部请求打开的伏笔 id（编辑器悬浮 tip「编辑」跳转）。
  final String? openForeshadowId;

  @override
  State<ForeshadowPanel> createState() => _ForeshadowPanelState();
}

class _ForeshadowPanelState extends State<ForeshadowPanel> {
  List<Foreshadow> _list = [];
  Map<String, int> _segCounts = const {};
  Foreshadow? _selected;
  bool _editingName = false;

  /// 详情页中已收起的卷分组名（默认全部展开）。
  final Set<String> _collapsedVolumes = {};
  List<ForeshadowSegment> _segments = [];
  ForeshadowStatus? _filter;
  String _keyword = '';
  bool _searching = false;
  bool _loading = true;
  bool _gridView = false;

  final _nameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _contentFocus = FocusNode();
  final _searchCtrl = TextEditingController();

  late final AppState _appState;

  static const _filterLabels = ['全部', '未完成', '已完成'];

  @override
  void initState() {
    super.initState();
    _gridView = context.read<SettingsController>().foreshadowGridView;
    _appState = context.read<AppState>();
    _appState.foreshadowVersion.addListener(_reload);
    _load();
    final openId = widget.openForeshadowId;
    if (openId != null) _openById(openId);
  }

  @override
  void didUpdateWidget(ForeshadowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final openId = widget.openForeshadowId;
    if (openId != null && openId != oldWidget.openForeshadowId) {
      _openById(openId);
    }
  }

  @override
  void dispose() {
    _appState.foreshadowVersion.removeListener(_reload);
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    _contentFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await _load();
    final sel = _selected;
    if (sel != null) {
      final fresh = _list.where((f) => f.id == sel.id).firstOrNull;
      if (fresh != null) {
        _selected = fresh;
        _fillDraft(fresh);
        await _loadSegments();
        if (mounted) setState(() {});
      } else {
        if (mounted) setState(() => _selected = null);
      }
    }
  }

  Future<void> _load() async {
    final state = _appState;
    final list = await state.foreshadows.listByBook(widget.book.id);
    final counts = <String, int>{};
    final segs = await state.fsSegments.listByBook(widget.book.id);
    for (final s in segs) {
      counts[s.fsId] = (counts[s.fsId] ?? 0) + 1;
    }
    if (mounted) {
      setState(() {
        _list = list;
        _segCounts = counts;
        _loading = false;
      });
    }
  }

  Future<void> _openById(String id) async {
    if (_list.isEmpty) await _load();
    final fs = _list.where((f) => f.id == id).firstOrNull;
    if (fs != null && mounted) _openDetail(fs);
  }

  void _openDetail(Foreshadow fs) {
    _fillDraft(fs);
    _collapseSearch();
    setState(() => _selected = fs);
    _loadSegments();
  }

  /// 离开列表态（进详情 / 切面板）时收起搜索框并清空关键词。
  void _collapseSearch() {
    _searching = false;
    _searchCtrl.clear();
    _keyword = '';
  }

  void _fillDraft(Foreshadow fs) {
    _nameCtrl.text = fs.name;
    _contentCtrl.text = fs.content;
    _editingName = false;
  }

  /// 伏笔描述失焦提交：变化才保存，未变静默。
  Future<void> _commitContent() async {
    final sel = _selected;
    if (sel == null) return;
    final content = _contentCtrl.text.trim();
    if (content.isEmpty || content == sel.content) return;
    sel.content = content;
    await _appState.saveForeshadow(sel);
    if (mounted) showToast(context, '描述保存成功');
  }

  Future<void> _loadSegments() async {
    final sel = _selected;
    if (sel == null) return;
    final segs = await _appState.fsSegments.listByForeshadow(sel.id);
    if (!mounted) return;
    // 摘要以正文当前内容为准：正文修改后进详情页同步显示最新片段文本。
    for (final seg in segs) {
      seg.excerpt = await _liveExcerpt(seg) ?? seg.excerpt;
    }
    if (mounted) setState(() => _segments = segs);
  }

  /// 从章节当前 Delta 提取片段标注文本；正文已无该标注（失锚）时返回 null。
  Future<String?> _liveExcerpt(ForeshadowSegment seg) async {
    Delta delta;
    if (_appState.currentChapter?.id == seg.chapterId) {
      delta = _appState.editorController.document.toDelta();
    } else {
      var ch = _appState.chapterList
          .where((c) => c.id == seg.chapterId)
          .firstOrNull;
      ch ??= await _appState.chapters.get(seg.chapterId);
      if (ch == null || ch.content.isEmpty) return null;
      try {
        delta = RichTextCodec.documentFromContent(ch.content).toDelta();
      } catch (_) {
        return null;
      }
    }
    final ranges = deltaFsidRanges(delta, seg.id);
    if (ranges.isEmpty) return null;
    return ranges
        .map((r) => deltaPlainTextInRange(delta, r.$1, r.$2))
        .join();
  }

  List<Foreshadow> get _filtered {
    var list = _list;
    if (_filter != null) list = list.where((f) => f.status == _filter).toList();
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(kw)).toList();
    }
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String _chapterTitle(String chapterId) {
    final ch = _appState.chapterList
        .where((c) => c.id == chapterId)
        .firstOrNull;
    return ch?.title ?? '章节已删除';
  }

  String _volumeTitle(String chapterId) {
    final ch = _appState.chapterList
        .where((c) => c.id == chapterId)
        .firstOrNull;
    if (ch == null) return '章节已删除';
    final vol = _appState.volumeTree
        .where((v) => v.id == ch.volumeId)
        .firstOrNull;
    return vol?.name ?? '未分卷';
  }

  /// 片段按所属卷分组，保持卷在书树中的顺序。
  Map<String, List<ForeshadowSegment>> get _groupedSegments {
    final groups = <String, List<ForeshadowSegment>>{};
    for (final seg in _segments) {
      groups.putIfAbsent(_volumeTitle(seg.chapterId), () => []).add(seg);
    }
    return groups;
  }

  Future<void> _createEmpty() async {
    final result = await showCreateForeshadowDialog(context, showRemark: false);
    if (result == null || !mounted) return;
    final fs = await _appState.foreshadows.create(
        bookId: widget.book.id, name: result.$1, content: result.$2);
    _appState.foreshadowVersion.value++;
    _openDetail(fs);
  }

  /// 重命名（标题行编辑图标触发，回车或失焦提交）。
  Future<void> _commitName() async {
    final sel = _selected;
    if (sel == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() => _editingName = false);
      showToast(context, '伏笔名称不能为空');
      return;
    }
    // 内容未变时静默退出编辑态，不提示。
    if (name == sel.name) {
      if (mounted) setState(() => _editingName = false);
      return;
    }
    sel.name = name;
    await _appState.saveForeshadow(sel);
    if (mounted) {
      setState(() => _editingName = false);
      showToast(context, '名称修改成功');
    }
  }

  /// 切换状态立即生效。
  Future<void> _setStatus(ForeshadowStatus status) async {
    final sel = _selected;
    if (sel == null || sel.status == status) return;
    sel.status = status;
    await _appState.saveForeshadow(sel);
    if (mounted) {
      showToast(context,
          status == ForeshadowStatus.done ? '已标记为已完成' : '已标记为未完成');
    }
  }

  /// 删除伏笔（二次确认）；[target] 为空时删除当前详情态伏笔。
  Future<void> _deleteForeshadow([Foreshadow? target]) async {
    final sel = target ?? _selected;
    if (sel == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
          title: const Text('删除伏笔',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Text('确定删除「${sel.name}」吗？删除后将移入回收站，正文中该伏笔的标注会暂时取消高亮，恢复后自动复原。',
              style: const TextStyle(fontSize: 13, height: 1.5)),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.errorContainer,
                    foregroundColor:
                        Theme.of(ctx).colorScheme.onErrorContainer),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _appState.deleteForeshadow(sel);
    if (!mounted) return;
    if (target == null || _selected?.id == target.id) {
      setState(() => _selected = null);
    }
    showToast(context, '删除成功，可从回收站恢复');
  }

  Future<void> _jumpToSegment(ForeshadowSegment seg) async {
    final ok = await _appState.jumpToSegment(seg);
    if (!mounted) return;
    if (!ok) showToast(context, '该片段已不在正文中');
  }

  Future<void> _editSegmentRemark(ForeshadowSegment seg) async {
    final result = await showEditSegmentRemarkDialog(context, seg.remark);
    if (result == null || !mounted) return;
    seg.remark = result;
    await _appState.fsSegments.update(seg);
    if (!mounted) return;
    await _loadSegments();
    _appState.foreshadowVersion.value++;
    if (mounted) showToast(context, '片段备注保存成功');
  }

  Future<void> _removeSegment(ForeshadowSegment seg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
          title: const Text('解除关联',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Text('确定解除该片段与伏笔的关联吗？正文中的标注将同时清除。',
              style: const TextStyle(fontSize: 13, height: 1.5)),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.errorContainer,
                    foregroundColor:
                        Theme.of(ctx).colorScheme.onErrorContainer),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('解除')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _appState.removeSegment(seg);
    await _loadSegments();
    if (mounted) showToast(context, '解除关联成功');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_selected != null) return _buildDetail(scheme);
    return _buildList(scheme);
  }

  // ---------- 列表态 ----------

  Widget _buildList(ColorScheme scheme) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Text('伏笔',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
          const Spacer(),
          if (_searching)
            SizedBox(
              width: 180,
              height: 28,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '名称',
                  hintStyle:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  prefixIcon: const Icon(Icons.search, size: 14),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 26, minHeight: 28),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                ),
                onChanged: (v) {
                  setState(() => _keyword = v.trim());
                },
              ),
            )
          else
            SizedBox(
              height: 28,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    _searchCtrl.text = _keyword;
                    setState(() => _searching = true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _keyword.isEmpty ? Icons.search : Icons.filter_alt,
                      size: 18,
                      color: _keyword.isEmpty ? null : scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          SizedBox(
            height: 28,
            child: Material(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(6),
                onTap: _createEmpty,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Icon(Icons.add, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text('新建',
                        style: TextStyle(
                            fontSize: 12, color: scheme.primary)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          ViewToggleGroup(
            gridView: _gridView,
            onChanged: (grid) {
              setState(() => _gridView = grid);
              context.read<SettingsController>().setForeshadowGridView(grid);
            },
          ),
        ]),
      ),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (var i = 0; i < _filterLabels.length; i++)
              _UnderlineTab(
                label: _filterLabels[i],
                selected: _filter ==
                    (i == 0
                        ? null
                        : i == 1
                            ? ForeshadowStatus.undone
                            : ForeshadowStatus.done),
                onTap: () => setState(() {
                  _filter = i == 0
                      ? null
                      : i == 1
                          ? ForeshadowStatus.undone
                          : ForeshadowStatus.done;
                }),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_outlined,
                            size: 48,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        Text(_list.isEmpty ? '暂无伏笔' : '无匹配结果',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : _gridView
                    ? _buildGrid(scheme)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => _ForeshadowCard(
                          foreshadow: _filtered[i],
                          segmentCount: _segCounts[_filtered[i].id] ?? 0,
                          tintIndex: i,
                          onTap: () => _openDetail(_filtered[i]),
                          onDelete: () => _deleteForeshadow(_filtered[i]),
                        ),
                      ),
      ),
    ]);
  }

  /// 伏笔网格视图：竖向卡片，高度与大纲网格一致（180px）。
  Widget _buildGrid(ColorScheme scheme) {
    return LayoutBuilder(builder: (ctx, constraints) {
      // 每列最小 220px，面板过窄时自动减少列数。
      final columns = (constraints.maxWidth ~/ 220).clamp(1, 4);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
        itemCount: _filtered.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 280,
        ),
        itemBuilder: (ctx, i) => _ForeshadowGridCell(
          foreshadow: _filtered[i],
          segmentCount: _segCounts[_filtered[i].id] ?? 0,
          tintIndex: i,
          onTap: () => _openDetail(_filtered[i]),
          onDelete: () => _deleteForeshadow(_filtered[i]),
        ),
      );
    });
  }

  // ---------- 详情态 ----------

  Widget _buildDetail(ColorScheme scheme) {
    final sel = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Row(children: [
            IconButton(
              tooltip: '返回列表',
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => setState(() => _selected = null),
            ),
            Expanded(
              child: _editingName
                  ? TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface),
                      decoration: const InputDecoration(
                          isDense: true, border: InputBorder.none),
                      onSubmitted: (_) => _commitName(),
                      onTapOutside: (_) => _commitName(),
                    )
                  : Text(sel.name.isEmpty ? '未命名伏笔' : sel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
            ),
            IconButton(
              tooltip: '重命名',
              icon: Icon(Icons.edit_outlined,
                  size: 17, color: scheme.onSurfaceVariant),
              onPressed: () =>
                  setState(() => _editingName = true),
            ),
            IconButton(
              tooltip: '删除伏笔',
              icon: Icon(Icons.delete_outline,
                  size: 19, color: scheme.error),
              onPressed: _deleteForeshadow,
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              Row(children: [
                Text('状态',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(width: 10),
                _StatusSegment(
                  label: '未完成',
                  selected: sel.status == ForeshadowStatus.undone,
                  color: foreshadowMarkColor(
                      ForeshadowStatus.undone, scheme.brightness),
                  onTap: () => _setStatus(ForeshadowStatus.undone),
                ),
                const SizedBox(width: 8),
                _StatusSegment(
                  label: '已完成',
                  selected: sel.status == ForeshadowStatus.done,
                  color: foreshadowMarkColor(
                      ForeshadowStatus.done, scheme.brightness),
                  onTap: () => _setStatus(ForeshadowStatus.done),
                ),
              ]),
              const SizedBox(height: 16),
              Text('描述',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
              const SizedBox(height: 8),
              TextField(
                controller: _contentCtrl,
                focusNode: _contentFocus,
                minLines: 4,
                maxLines: 12,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: '这个伏笔埋了什么、打算怎么回收…',
                  hintStyle: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                ),
                onTapOutside: (_) {
                  _contentFocus.unfocus();
                  _commitContent();
                },
              ),
              const SizedBox(height: 16),
              Text('关联片段（${_segments.length}）',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
              const SizedBox(height: 8),
              if (_segments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('尚无关联片段，选中正文后右键可关联',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                )
              else
                for (final entry in _groupedSegments.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Row(children: [
                      // 可点击收起/展开，需按 UI 红线给手型光标。
                      InkWell(
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () => setState(() {
                          if (_collapsedVolumes.contains(entry.key)) {
                            _collapsedVolumes.remove(entry.key);
                          } else {
                            _collapsedVolumes.add(entry.key);
                          }
                        }),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 2),
                          child: Row(children: [
                            Icon(
                              _collapsedVolumes.contains(entry.key)
                                  ? Icons.keyboard_arrow_right
                                  : Icons.keyboard_arrow_down,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.menu_book,
                                size: 13, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(entry.key,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(width: 6),
                            Text('${entry.value.length}段',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.7))),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  if (!_collapsedVolumes.contains(entry.key))
                    for (final seg in entry.value)
                      _SegmentTile(
                        segment: seg,
                        chapterTitle: _chapterTitle(seg.chapterId),
                        onJump: () => _jumpToSegment(seg),
                        onEditRemark: () => _editSegmentRemark(seg),
                        onRemove: () => _removeSegment(seg),
                      ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color:
                    selected ? scheme.onSurface : scheme.onSurfaceVariant)),
      ),
    );
  }
}

/// 伏笔网格卡片：主题色板彩底（无边框），图标 + 状态徽章 + 名称 + 描述 + 片段数/时间。
class _ForeshadowGridCell extends StatefulWidget {
  const _ForeshadowGridCell({
    required this.foreshadow,
    required this.segmentCount,
    required this.onTap,
    required this.onDelete,
    this.tintIndex = 0,
  });

  final Foreshadow foreshadow;
  final int segmentCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final int tintIndex;

  @override
  State<_ForeshadowGridCell> createState() => _ForeshadowGridCellState();
}

class _ForeshadowGridCellState extends State<_ForeshadowGridCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreshadow = widget.foreshadow;
    final color = foreshadowMarkColor(foreshadow.status, scheme.brightness);
    String two(int n) => n.toString().padLeft(2, '0');
    final t = foreshadow.updatedAt;
    final timeText = t.year == DateTime.now().year
        ? '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}'
        : '${t.year}-${two(t.month)}-${two(t.day)}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TintedCard(
        emphasized: false,
        tintIndex: widget.tintIndex,
        padding: const EdgeInsets.all(16),
        onTap: widget.onTap,
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(Icons.flag_outlined, size: 15, color: color),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                        foreshadow.status == ForeshadowStatus.done
                            ? '已完成'
                            : '未完成',
                        style: TextStyle(fontSize: 10, color: color)),
                  ),
                  if (_hover) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          onTap: widget.onDelete,
                          child: Center(
                            child: Icon(Icons.delete_outline,
                                size: 15, color: scheme.error),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(foreshadow.name.isEmpty ? '未命名伏笔' : foreshadow.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                      foreshadow.content.isEmpty
                          ? '暂无描述'
                          : foreshadow.content,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: foreshadow.content.isEmpty
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface.withValues(alpha: 0.85))),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${widget.segmentCount} 个片段',
                      style: TextStyle(
                          fontSize: 10,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  Text(timeText,
                      style: TextStyle(
                          fontSize: 10,
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                ]),
              ],
      ),
      ),
    );
  }
}

class _ForeshadowCard extends StatefulWidget {
  const _ForeshadowCard({
    required this.foreshadow,
    required this.segmentCount,
    required this.onTap,
    required this.onDelete,
    this.tintIndex = 0,
  });

  final Foreshadow foreshadow;
  final int segmentCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final int tintIndex;

  @override
  State<_ForeshadowCard> createState() => _ForeshadowCardState();
}

class _ForeshadowCardState extends State<_ForeshadowCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreshadow = widget.foreshadow;
    final color = foreshadowMarkColor(foreshadow.status, scheme.brightness);
    String two(int n) => n.toString().padLeft(2, '0');
    final t = foreshadow.updatedAt;
    final timeText = t.year == DateTime.now().year
        ? '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}'
        : '${t.year}-${two(t.month)}-${two(t.day)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TintedCard(
          emphasized: false,
          tintIndex: widget.tintIndex,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          onTap: widget.onTap,
          child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.flag_outlined, size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(foreshadow.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                              foreshadow.status == ForeshadowStatus.done
                                  ? '已完成'
                                  : '未完成',
                              style:
                                  TextStyle(fontSize: 10, color: color)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                          foreshadow.content.isEmpty
                              ? '暂无描述'
                              : foreshadow.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: foreshadow.content.isEmpty
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface.withValues(alpha: 0.85))),
                      const SizedBox(height: 3),
                      Text(
                          '${widget.segmentCount} 个片段 · $timeText',
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: _hover
                      ? Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(6),
                            onTap: widget.onDelete,
                            child: Center(
                              child: Icon(Icons.delete_outline,
                                  size: 16, color: scheme.error),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
        ),
      ),
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.6)
                  : Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.segment,
    required this.chapterTitle,
    required this.onJump,
    required this.onEditRemark,
    required this.onRemove,
  });

  final ForeshadowSegment segment;
  final String chapterTitle;
  final VoidCallback onJump;
  final VoidCallback onEditRemark;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('「${segment.excerpt}」',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurface)),
          const SizedBox(height: 3),
          Text(chapterTitle,
              style: TextStyle(
                  fontSize: 10, color: scheme.onSurfaceVariant)),
          if (segment.remark.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('备注：${segment.remark}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            _MiniAction(icon: Icons.my_location, label: '跳转正文', onTap: onJump),
            const SizedBox(width: 10),
            _MiniAction(icon: Icons.edit_note, label: '备注', onTap: onEditRemark),
            const Spacer(),
            _MiniAction(
                icon: Icons.link_off,
                label: '解除关联',
                onTap: onRemove,
                color: scheme.error),
          ]),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction(
      {required this.icon, required this.label, required this.onTap,
      this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color ?? scheme.primary),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color ?? scheme.primary)),
        ]),
      ),
    );
  }
}
