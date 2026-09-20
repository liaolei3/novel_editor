import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/utils/global_search.dart';
import '../state/app_state.dart';
import 'common/dialogs.dart';
import 'widgets/toast.dart';

/// 全局搜索替换弹窗：多选范围（正文 / 章纲 / 角色 / 标题），
/// 分组结果列表，正文命中可点击跳转章节；替换前自动为受影响章节创建快照。
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

  final Set<SearchScope> _scopes = SearchScope.values.toSet();
  List<GlobalSearchHit> _hits = const [];
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
    final hits =
        await context.read<AppState>().globalSearch(query, Set.of(_scopes));
    if (!mounted) return;
    setState(() {
      _hits = hits;
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
            '将在 ${_hits.length} 个位置替换共 $total 处。\n\n'
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
      scopes: Set.of(_scopes),
    );
    if (!mounted) return;
    setState(() => _replacing = false);
    showToast(context, '替换成功，共 $n 处');
    await _doSearch();
  }

  /// 点击正文命中：关闭弹窗并跳转到对应章节（不触发编辑区搜索）。
  Future<void> _jumpToChapter(GlobalSearchHit hit) async {
    final state = context.read<AppState>();
    final chapterId = hit.chapterId;
    if (chapterId == null) return;
    Navigator.of(context).pop();
    final chapter = await state.chapters.get(chapterId);
    if (chapter == null) return;
    await state.openChapter(chapter);
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
              _scopeChips(context),
              const SizedBox(height: 8),
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

  Widget _scopeChips(BuildContext context) {
    return Row(children: [
      Text('范围', style: _scopeLabelStyle(context)),
      const SizedBox(width: 8),
      for (final scope in SearchScope.values) ...[
        _scopeChip(context, scope),
        const SizedBox(width: 6),
      ],
    ]);
  }

  static const _scopeNames = {
    SearchScope.content: '正文',
    SearchScope.outline: '章纲',
    SearchScope.character: '角色',
    SearchScope.title: '标题',
  };

  TextStyle _scopeLabelStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Widget _scopeChip(BuildContext context, SearchScope scope) {
    final cs = Theme.of(context).colorScheme;
    final selected = _scopes.contains(scope);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        selected ? _scopes.remove(scope) : _scopes.add(scope);
      }),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.5)
                : cs.outlineVariant,
          ),
        ),
        child: Text(
          _scopeNames[scope]!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
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
    if (_hits.isEmpty) {
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
    final children = <Widget>[];
    var firstGroup = true;
    for (final scope in SearchScope.values) {
      final group = _hitsForScope(scope);
      if (group.isEmpty) continue;
      if (!firstGroup) children.add(const Divider(height: 1));
      children.addAll(group);
      firstGroup = false;
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }

  List<Widget> _hitsForScope(SearchScope scope) {
    final hits = _hits.where((h) => h.scope == scope).toList();
    if (hits.isEmpty) return const [];
    final count = hits.fold<int>(0, (sum, h) => sum + h.count);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          '${_scopeNames[scope]} · ${hits.length} 处位置 / $count 处命中',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      for (final hit in hits)
        _HitTile(
          hit: hit,
          query: _searchCtrl.text,
          onTap: hit.chapterId != null ? () => _jumpToChapter(hit) : null,
        ),
    ];
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

/// 单条命中：位置标签 + 上下文摘要（命中处高亮）。
class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.query,
    this.onTap,
  });

  final GlobalSearchHit hit;
  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clickable = onTap != null;
    return InkWell(
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
                      hit.fields.length == 1
                          ? '${hit.fieldLabel} ×${hit.count}'
                          : '共 ${hit.count} 处',
                      style: TextStyle(fontSize: 11, color: cs.outline),
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

  /// 单字段命中：一条摘要；多字段命中（角色聚合）：逐字段展示摘要与数量。
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
        style: TextStyle(fontSize: 11, color: cs.outline),
      ));
    }
    if (start > 0) spans.add(TextSpan(text: '…'));
    var pos = start;
    for (final s in field.starts) {
      final e = s + query.length;
      if (e <= start || s >= end) continue;
      final ls = s.clamp(start, end);
      final le = e.clamp(start, end);
      if (ls > pos) {
        spans.add(TextSpan(text: source.substring(pos, ls)));
      }
      spans.add(TextSpan(
        text: source.substring(ls, le),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: cs.primary.withValues(alpha: 0.12),
        ),
      ));
      pos = le;
    }
    if (pos < end) spans.add(TextSpan(text: source.substring(pos, end)));
    if (end < source.length) spans.add(const TextSpan(text: '…'));
    // RichText 不继承 DefaultTextStyle，根 span 必须显式指定颜色，
    // 否则浅色主题下默认按白色渲染导致不可读。
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base.copyWith(fontSize: 13, height: 1.4),
        children: spans,
      ),
    );
  }
}
