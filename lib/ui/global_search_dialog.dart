import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/utils/global_search.dart';
import '../state/app_state.dart';
import 'common/dialogs.dart';
import 'widgets/toast.dart';
import 'widgets/underline_tab.dart';

/// 全局搜索替换弹窗：一次搜索全部类型（正文 / 章纲 / 角色 / 伏笔），
/// 结果按类型 tab 分区展示；正文与章纲进一步按卷分类、按章排序；
/// 正文命中可点击跳转章节；替换前自动为受影响章节创建快照。
Future<void> showGlobalSearchDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DraggableDialog(child: _GlobalSearchDialog()),
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  SearchScope _tab = SearchScope.content;
  List<GlobalSearchHit> _hits = const [];
  Map<String, String> _volumeNames = const {};

  /// 已收起的卷 id（默认全部展开）。
  final Set<String> _collapsedVolumes = {};
  bool _searched = false;
  bool _searching = false;
  bool _replacing = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _replaceCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _searchCtrl.text;
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    final state = context.read<AppState>();
    final hits = await state.globalSearch(query);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      // 卷名随搜索结果一并快照，供正文 / 章纲按卷分组使用。
      _volumeNames = {for (final v in state.volumeTree) v.id: v.name};
      // 新一轮结果回到全展开。
      _collapsedVolumes.clear();
      _searched = true;
      _searching = false;
    });
  }

  Future<void> _doReplace() async {
    final query = _searchCtrl.text;
    if (query.isEmpty || _hits.isEmpty || _replacing) return;
    final state = context.read<AppState>();
    final total = _hits.fold<int>(0, (sum, h) => sum + h.count);
    final replaceEmpty = _replaceCtrl.text.isEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: const Text('全部替换'),
          content: Text(
            '将在 ${_hits.length} 个位置替换共 $total 处'
            '（正文、章纲、角色、伏笔）。\n\n'
            '${replaceEmpty ? "替换词为空，命中的内容将被删除。\n\n" : ""}'
            '执行前会为受影响章节自动创建快照，'
            '如需撤销请前往「历史快照」回滚。确定执行？',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('替换')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _replacing = true);
    final n = await state.globalReplace(
      query: query,
      replacement: _replaceCtrl.text,
    );
    if (!mounted) return;
    setState(() => _replacing = false);
    showToast(context, '替换成功，共 $n 处');
    await _doSearch();
  }

  /// 点击正文 / 章纲命中：关闭弹窗并跳转到对应章节。
  Future<void> _jumpToChapter(GlobalSearchHit hit) async {
    final state = context.read<AppState>();
    final chapterId = hit.chapterId;
    if (chapterId == null) return;
    Navigator.of(context).pop();
    final chapter = await state.chapters.get(chapterId);
    if (chapter == null) return;
    await state.openChapter(chapter);
  }

  void _switchTab(SearchScope scope) {
    if (_tab == scope) return;
    setState(() => _tab = scope);
    // 不同 tab 内容长度差异大，切换后回到顶部避免落在无意义位置。
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 12),
              _searchRow(context),
              const SizedBox(height: 8),
              _replaceRow(context),
              const SizedBox(height: 10),
              if (_searched) ...[
                _typeTabs(context),
                const SizedBox(height: 8),
              ],
              const Divider(height: 1),
              Expanded(child: _resultList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      Text('全局搜索',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      const Spacer(),
      IconButton(
        tooltip: '关闭 (Esc)',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
      ),
    ]);
  }

  Widget _searchRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索全书…',
              hintStyle: const TextStyle(fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.primary),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 96,
        height: 36,
        child: FilledButton(
          onPressed: _searching ? null : _doSearch,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('搜索'),
        ),
      ),
    ]);
  }

  static const _scopeNames = {
    SearchScope.content: '正文',
    SearchScope.outline: '章纲',
    SearchScope.character: '角色',
    SearchScope.foreshadow: '伏笔',
  };

  /// 类型 tab：数量为该类型的命中处数（与行内「×N」相加口径一致）。
  Widget _typeTabs(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(children: [
        for (final scope in SearchScope.values)
          UnderlineTab(
            label: _scopeNames[scope]!,
            count: _countForScope(scope),
            selected: _tab == scope,
            onTap: () => _switchTab(scope),
          ),
      ]),
    );
  }

  int _countForScope(SearchScope scope) {
    var n = 0;
    for (final h in _hits) {
      if (h.scope == scope) n += h.count;
    }
    return n;
  }

  Widget _resultList(BuildContext context) {
    if (!_searched) {
      return Center(
        child: Text(
          '输入关键词后按回车或点击「搜索」',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    final hits = _hits.where((h) => h.scope == _tab).toList();
    if (hits.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配内容',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    final groupByVolume =
        _tab == SearchScope.content || _tab == SearchScope.outline;
    final children = <Widget>[];
    if (groupByVolume) {
      // hits 已按「卷序 → 章序」排列，按出现顺序分组即得卷分组顺序。
      final groups = <String, List<GlobalSearchHit>>{};
      for (final h in hits) {
        (groups[h.volumeId ?? ''] ??= <GlobalSearchHit>[]).add(h);
      }
      var first = true;
      for (final entry in groups.entries) {
        if (!first) children.add(const Divider(height: 1));
        final collapsed = _collapsedVolumes.contains(entry.key);
        children.add(_volumeHeader(context, entry.key, entry.value, collapsed));
        if (!collapsed) {
          for (final h in entry.value) {
            children.add(_HitTile(
              hit: h,
              query: _searchCtrl.text,
              showFieldName: false,
              onTap: h.chapterId != null ? () => _jumpToChapter(h) : null,
            ));
          }
        }
        first = false;
      }
    } else {
      for (final h in hits) {
        children.add(_HitTile(hit: h, query: _searchCtrl.text));
      }
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }

  /// 卷分组标题：卷名 + 该卷命中处数，点击可收起 / 展开（默认展开）。
  Widget _volumeHeader(BuildContext context, String volumeId,
      List<GlobalSearchHit> hits, bool collapsed) {
    final count = hits.fold<int>(0, (sum, h) => sum + h.count);
    final name = _volumeNames[volumeId] ?? '未分卷';
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => setState(() {
          if (!_collapsedVolumes.remove(volumeId)) {
            _collapsedVolumes.add(volumeId);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 4, 4),
          child: Row(children: [
            // 展开状态三角：向右收起、向下展开，与书树卷头一致。
            AnimatedRotation(
              turns: collapsed ? 0 : 0.25,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.arrow_right, size: 22, color: cs.primary),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$name · $count 处',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _replaceRow(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _replaceCtrl,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _doReplace(),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: '替换为',
            hintStyle: const TextStyle(fontSize: 14),
            prefixIcon: const Icon(Icons.loop, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 96,
        height: 36,
        child: FilledButton(
          onPressed: _hits.isEmpty || _replacing ? null : _doReplace,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('全部替换'),
        ),
      ),
    ]);
  }
}

/// 单条命中：名称 + 计数 + 上下文摘要（命中处高亮）。
/// [showFieldName] 为 false 时不显示字段名（正文/章纲的字段名已由 tab 表达）。
class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.query,
    this.showFieldName = true,
    this.onTap,
  });

  final GlobalSearchHit hit;
  final String query;
  final bool showFieldName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clickable = onTap != null;
    return InkWell(
      mouseCursor: clickable ? SystemMouseCursors.click : null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 基线对齐，保证右侧计数与左侧位置文字上下对齐。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        hit.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: clickable ? cs.primary : cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _metaText(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                _snippets(context),
              ],
            ),
          ),
          if (clickable)
            Icon(Icons.chevron_right, size: 16, color: cs.outline),
        ]),
      ),
    );
  }

  String _metaText() {
    if (hit.fields.length > 1) return '共 ${hit.count} 处';
    return showFieldName ? '${hit.fieldLabel} ×${hit.count}' : '×${hit.count}';
  }

  /// 单字段命中：一条摘要；多字段命中（角色/伏笔聚合）：逐字段展示摘要与数量。
  Widget _snippets(BuildContext context) {
    if (hit.fields.length == 1) {
      return _fieldSnippet(context, hit.fields.first, false);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < hit.fields.length; i++) ...[
          _fieldSnippet(context, hit.fields[i], true),
          if (i < hit.fields.length - 1) const SizedBox(height: 2),
        ],
      ],
    );
  }

  /// 上下文摘要（前后各约 20 字），命中部分标色加粗。
  /// 正文 / 章纲的纯文本含段落换行，统一按空格渲染并限制单行，
  /// 否则含换行的命中会折行导致行高参差。
  Widget _fieldSnippet(
      BuildContext context, GlobalSearchFieldHit field, bool withLabel) {
    final cs = Theme.of(context).colorScheme;
    final source = field.source;
    final first = field.starts.first;
    final contextLen = 20;
    final start = (first - contextLen).clamp(0, source.length);
    final end =
        (first + query.length + contextLen).clamp(0, source.length);
    final spans = <InlineSpan>[];
    if (withLabel) {
      spans.add(TextSpan(
        text: '${field.fieldLabel} ×${field.count}：',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurfaceVariant,
        ),
      ));
    }
    if (start > 0) spans.add(const TextSpan(text: '…'));
    var pos = start;
    for (final s in field.starts) {
      final e = s + query.length;
      if (e <= start || s >= end) continue;
      final ls = s.clamp(start, end);
      final le = e.clamp(start, end);
      if (ls > pos) {
        spans.add(TextSpan(text: _inline(source.substring(pos, ls))));
      }
      spans.add(TextSpan(
        text: _inline(source.substring(ls, le)),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: cs.primary.withValues(alpha: 0.12),
        ),
      ));
      pos = le;
    }
    if (pos < end) {
      spans.add(TextSpan(text: _inline(source.substring(pos, end))));
    }
    if (end < source.length) spans.add(const TextSpan(text: '…'));
    // RichText 不继承 DefaultTextStyle，根 span 必须显式指定颜色，
    // 否则浅色主题下默认按白色渲染导致不可读。
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base.copyWith(fontSize: 13, height: 1.4),
        children: spans,
      ),
    );
  }

  /// 摘要内的换行 / 制表符按空格渲染，保证每条摘要都只占一行。
  static String _inline(String text) => text
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      .replaceAll('\t', ' ');
}