import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/sensitive_words.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../common/dialogs.dart';
import '../common/file_io.dart';
import '../common/sensitive_word_dialog.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/toast.dart';
import '../widgets/underline_tab.dart';

/// 敏感词面板（FR-26）：检测（本章 / 全书，含替换）+ 词库管理（可视化 / 文件导入）。
class SensitivePanel extends StatefulWidget {
  const SensitivePanel({super.key});

  @override
  State<SensitivePanel> createState() => _SensitivePanelState();
}

enum _View { detect, dict }

enum _Scope { none, chapter, book }

class _SensitivePanelState extends State<SensitivePanel> {
  _View _view = _View.detect;
  _Scope _scope = _Scope.none;

  List<SensitiveMatch> _chapterMatches = const [];
  List<SensitiveChapterScan> _bookScans = const [];

  /// 检测时的当前章正文长度，用于判断结果是否已过期。
  int _scannedLen = -1;
  bool _stale = false;

  List<SensitiveWord> _words = const [];
  bool _wordsLoading = true;

  AppState? _state;
  String? _lastChapterId;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _lastChapterId = _state!.currentChapter?.id;
    _state!.addListener(_onStateChanged);
    _loadWords();
  }

  @override
  void dispose() {
    _state?.removeListener(_onStateChanged);
    super.dispose();
  }

  // ---------- 词条 / 结果来源 ----------

  List<SensitiveEntry> get _entries => [
        for (final w in _words)
          if (w.enabled && w.word.isNotEmpty)
            SensitiveEntry(word: w.word, suggestion: w.suggestion),
      ];

  int get _enabledCount => _entries.length;

  int get _currentChapterLen => _state?.currentChapter?.content.length ?? 0;

  void _onStateChanged() {
    final s = _state;
    if (s == null || !mounted) return;
    final id = s.currentChapter?.id;
    if (id != _lastChapterId) {
      // 切换章节：结果不再对应当前章，立即清空。
      _lastChapterId = id;
      setState(() {
        _scope = _Scope.none;
        _chapterMatches = const [];
        _bookScans = const [];
        _stale = false;
      });
      return;
    }
    if (_scope != _Scope.none && !_stale && _currentChapterLen != _scannedLen) {
      setState(() => _stale = true);
    }
  }

  Future<void> _loadWords() async {
    final list = await _state!.sensitiveWords.listAll();
    if (!mounted) return;
    setState(() {
      _words = list;
      _wordsLoading = false;
    });
  }

  // ---------- 检测 ----------

  Future<void> _detectChapter() async {
    final entries = _entries;
    if (entries.isEmpty) {
      showToast(context, '词库为空，请先在「词库」中添加敏感词');
      return;
    }
    setState(() {
      _scope = _Scope.chapter;
      _chapterMatches = _state!.scanSensitiveChapter(entries);
      _scannedLen = _currentChapterLen;
      _stale = false;
    });
  }

  Future<void> _detectBook() async {
    final entries = _entries;
    if (entries.isEmpty) {
      showToast(context, '词库为空，请先在「词库」中添加敏感词');
      return;
    }
    final scans = await runWithBusy('检测敏感词',
        (report) => _state!.scanSensitiveBook(entries, onProgress: report));
    if (!mounted) return;
    setState(() {
      _scope = _Scope.book;
      _bookScans = scans;
      _scannedLen = _currentChapterLen;
      _stale = false;
    });
  }

  // ---------- 替换 ----------

  Future<void> _replaceChapter(Chapter ch, {int? hits}) async {
    final entries = _entries;
    if (entries.isEmpty) return;
    final count =
        hits ?? _chapterMatches.fold<int>(0, (sum, m) => sum + m.count);
    final ok = await _confirm('替换本章',
        '将在《${ch.title}》中替换 $count 处命中词，并创建回滚快照。是否继续？', '替换');
    if (ok != true || !mounted) return;
    final (n, skipped) = await runWithBusy(
        '替换敏感词', (_) => _state!.replaceSensitiveChapter(ch, entries));
    if (!mounted) return;
    _afterReplace(n, skipped);
  }

  Future<void> _replaceBook() async {
    final entries = _entries;
    if (entries.isEmpty) return;
    final hits = _bookScans.fold(0, (sum, s) => sum + s.count);
    final ok = await _confirm('全书替换',
        '将在全书范围内替换 $hits 处命中词，并为每个被修改的章节创建回滚快照。是否继续？', '替换');
    if (ok != true || !mounted) return;
    final (n, skipped) = await runWithBusy(
        '替换敏感词', (report) => _state!.replaceSensitiveBook(entries, onProgress: report));
    if (!mounted) return;
    _afterReplace(n, skipped);
  }

  void _afterReplace(int n, Set<String> skipped) {
    setState(() {
      _scope = _Scope.none;
      _chapterMatches = const [];
      _bookScans = const [];
      _stale = false;
    });
    if (n == 0) {
      showToast(
          context,
          skipped.isNotEmpty
              ? '未替换：命中的词均未设置建议替换词'
              : '没有可替换的命中词');
      return;
    }
    final extra = skipped.isEmpty ? '' : '，跳过 ${skipped.length} 词（未设建议词）';
    showToast(context, '替换成功，共 $n 处$extra');
  }

  Future<void> _jump(Chapter ch, SensitiveOccurrence occ) async {
    final ok =
        await _state!.jumpToTextRange(ch.id, occ.start, occ.end);
    if (!mounted) return;
    if (!ok) showToast(context, '跳转失败：章节已不存在');
  }

  // ---------- 词库管理 ----------

  Future<void> _addWord() async {
    final result = await showSensitiveWordDialog(context);
    if (result == null || !mounted) return;
    final (word, suggestion) = result;
    if (_words.any((w) => w.word.toLowerCase() == word.toLowerCase())) {
      showToast(context, '新增失败：「$word」已存在');
      return;
    }
    await _state!.sensitiveWords.create(word: word, suggestion: suggestion);
    await _loadWords();
    if (mounted) showToast(context, '新增成功');
  }

  Future<void> _editWord(SensitiveWord w) async {
    final result = await showSensitiveWordDialog(context,
        word: w.word, suggestion: w.suggestion);
    if (result == null || !mounted) return;
    final (word, suggestion) = result;
    if (_words.any(
        (o) => o.id != w.id && o.word.toLowerCase() == word.toLowerCase())) {
      showToast(context, '保存失败：「$word」已存在');
      return;
    }
    w
      ..word = word
      ..suggestion = suggestion;
    await _state!.sensitiveWords.update(w);
    await _loadWords();
    if (mounted) showToast(context, '保存成功');
  }

  Future<void> _toggleWord(SensitiveWord w, bool enabled) async {
    await _state!.sensitiveWords.setEnabled(w.id, enabled);
    await _loadWords();
  }

  Future<void> _deleteWord(SensitiveWord w) async {
    final ok = await _confirm('删除敏感词', '确定删除「${w.word}」吗？', '删除');
    if (ok != true || !mounted) return;
    await _state!.sensitiveWords.delete(w.id);
    await _loadWords();
    if (mounted) showToast(context, '删除成功');
  }

  Future<void> _clearWords() async {
    final ok = await _confirm('清空词库', '确定清空全部敏感词吗？此操作不可撤销。', '清空');
    if (ok != true || !mounted) return;
    await _state!.sensitiveWords.clear();
    await _loadWords();
    if (mounted) showToast(context, '清空成功');
  }

  Future<void> _importWords() async {
    final raw = await FileIO.pickReadText();
    if (raw == null || !mounted) return;
    final parsed = SensitiveWordScanner.parseImport(raw);
    if (parsed.isEmpty) {
      showToast(context, '导入失败：未解析到有效词条');
      return;
    }
    final (added, updated) = await _state!.sensitiveWords.mergeImport(parsed);
    await _loadWords();
    if (mounted) showToast(context, '导入成功：新增 $added / 更新 $updated');
  }

  Future<bool?> _confirm(String title, String content, String okLabel) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
          title: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Text(content, style: const TextStyle(fontSize: 13, height: 1.5)),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(okLabel)),
          ],
        ),
      ),
    );
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 4),
            UnderlineTab(
              label: '检测',
              selected: _view == _View.detect,
              onTap: () => setState(() => _view = _View.detect),
            ),
            UnderlineTab(
              label: '词库',
              selected: _view == _View.dict,
              onTap: () => setState(() => _view = _View.dict),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
          child: _view == _View.detect
              ? _buildDetect(scheme)
              : _buildDict(scheme)),
    ]);
  }

  Widget _buildDetect(ColorScheme scheme) {
    final chapter = context.watch<AppState>().currentChapter;
    final hasResult = _scope != _Scope.none;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FilledButton.icon(
              onPressed: chapter == null ? null : _detectChapter,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('检测本章'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: chapter == null ? null : _detectBook,
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: const Text('检测全书'),
            ),
          ]),
          const SizedBox(height: 8),
          _summaryLine(scheme),
        ]),
      ),
      if (hasResult) _resultToolbar(scheme, chapter),
      if (hasResult) const Divider(height: 1),
      Expanded(child: _resultBody(scheme, chapter)),
    ]);
  }

  Widget _summaryLine(ColorScheme scheme) {
    final text = switch (_scope) {
      _Scope.none => '词库已启用 $_enabledCount 词；选择「检测本章」或「检测全书」。',
      _Scope.chapter => _chapterMatches.isEmpty
          ? '本章未检测到命中词'
          : '本章命中 ${_chapterMatches.length} 词 / ${_chapterMatches.fold(0, (n, m) => n + m.count)} 处',
      _Scope.book => _bookScans.isEmpty
          ? '全书未检测到命中词'
          : '全书命中 ${_bookScans.length} 章 / ${_bookScans.fold(0, (n, s) => n + s.count)} 处',
    };
    return Row(children: [
      Expanded(
        child: Text(text,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ),
      if (_stale)
        Text('内容已变更，建议重新检测',
            style: TextStyle(fontSize: 12, color: scheme.error)),
    ]);
  }

  Widget _resultToolbar(ColorScheme scheme, Chapter? chapter) {
    final canReplaceChapter =
        _scope == _Scope.chapter && _chapterMatches.isNotEmpty && chapter != null;
    final canReplaceBook = _scope == _Scope.book && _bookScans.isNotEmpty;
    if (!canReplaceChapter && !canReplaceBook) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        if (canReplaceChapter)
          FilledButton.icon(
            onPressed: () => _replaceChapter(chapter),
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('替换本章'),
          ),
        if (canReplaceBook)
          FilledButton.icon(
            onPressed: _replaceBook,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('全书替换'),
          ),
        const Spacer(),
        Text('已启用 $_enabledCount 词',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ]),
    );
  }

  Widget _resultBody(ColorScheme scheme, Chapter? chapter) {
    if (_scope == _Scope.none) {
      return _emptyHint(scheme, Icons.search, '尚未检测');
    }
    if (_scope == _Scope.chapter) {
      if (_chapterMatches.isEmpty) {
        return _emptyHint(scheme, Icons.check_circle_outline, '未检测到命中词');
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
        itemCount: _chapterMatches.length,
        itemBuilder: (ctx, i) => _MatchCard(
          match: _chapterMatches[i],
          onTapOccurrence: (occ) =>
              chapter == null ? null : _jump(chapter, occ),
        ),
      );
    }
    if (_bookScans.isEmpty) {
      return _emptyHint(scheme, Icons.check_circle_outline, '未检测到命中词');
    }
    return _buildBookResult(scheme);
  }

  Widget _buildBookResult(ColorScheme scheme) {
    final s = _state!;
    final volName = {for (final v in s.volumeTree) v.id: v.name};
    final groups = <String, List<SensitiveChapterScan>>{};
    for (final scan in _bookScans) {
      groups.putIfAbsent(scan.chapter.volumeId, () => []).add(scan);
    }
    final orderedIds = [
      ...s.volumeTree.map((v) => v.id),
      ...groups.keys.where((k) => !volName.containsKey(k)),
    ];
    final children = <Widget>[];
    for (final vid in orderedIds) {
      final items = groups[vid];
      if (items == null || items.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(volName[vid] ?? '未命名卷',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
      ));
      for (final scan in items) {
        children.add(_ChapterResultCard(
          scan: scan,
          onReplace: () => _replaceChapter(scan.chapter, hits: scan.count),
          onTapOccurrence: (occ) => _jump(scan.chapter, occ),
        ));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 80), children: children);
  }

  Widget _buildDict(ColorScheme scheme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(children: [
          FilledButton.icon(
            onPressed: _addWord,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新增'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _importWords,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.upload_file, size: 16),
              const SizedBox(width: 5),
              const Text('导入文件'),
              const SizedBox(width: 4),
              _hintIcon(
                  '导入格式：每行一个词，或「词|建议词」；分隔符支持 | 、逗号、Tab；# 开头为注释行。'),
            ]),
          ),
          const Spacer(),
          TextButton(
            onPressed: _words.isEmpty ? null : _clearWords,
            child: const Text('清空'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _wordsLoading
            ? const SizedBox.shrink()
            : _words.isEmpty
                ? _emptyHint(scheme, Icons.shield_outlined, '暂无敏感词，点击「新增」或「导入文件」添加')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 80),
                    itemCount: _words.length,
                    itemBuilder: (ctx, i) => _WordCard(
                      word: _words[i],
                      onToggle: (v) => _toggleWord(_words[i], v),
                      onEdit: () => _editWord(_words[i]),
                      onDelete: () => _deleteWord(_words[i]),
                    ),
                  ),
      ),
    ]);
  }

  /// 提示图标：视觉与设置弹窗的问号一致，悬浮（鼠标）时展示提示。
  Widget _hintIcon(String message) {
    return Tooltip(
      message: message,
      constraints: const BoxConstraints(maxWidth: 220),
      mouseCursor: SystemMouseCursors.click,
      child: SizedBox(
        width: 16,
        height: 16,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Center(
            child: Icon(
              Icons.help_outline,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(ColorScheme scheme, IconData icon, String text) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

/// 单章命中卡片（本章视图）。
class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onTapOccurrence});

  final SensitiveMatch match;
  final void Function(SensitiveOccurrence) onTapOccurrence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(match.word,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.error)),
            const SizedBox(width: 8),
            _suggestionChip(scheme, match.suggestion),
            const Spacer(),
            Text('命中 ${match.count} 处',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 6),
          for (final occ in match.occurrences)
            _OccurrenceLine(occ: occ, onTap: () => onTapOccurrence(occ)),
        ]),
      ),
    );
  }
}

/// 全书视图：单章结果卡片。
class _ChapterResultCard extends StatelessWidget {
  const _ChapterResultCard({
    required this.scan,
    required this.onReplace,
    required this.onTapOccurrence,
  });

  final SensitiveChapterScan scan;
  final VoidCallback onReplace;
  final void Function(SensitiveOccurrence) onTapOccurrence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(scan.chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
            ),
            Text('${scan.count} 处',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onReplace,
              child: const Text('替换本章', style: TextStyle(fontSize: 12)),
            ),
          ]),
          for (final m in scan.matches) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(children: [
                Text(m.word,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.error)),
                const SizedBox(width: 6),
                _suggestionChip(scheme, m.suggestion),
              ]),
            ),
            for (final occ in m.occurrences)
              _OccurrenceLine(occ: occ, onTap: () => onTapOccurrence(occ)),
          ],
        ]),
      ),
    );
  }
}

Widget _suggestionChip(ColorScheme scheme, String suggestion) {
  if (suggestion.isEmpty) {
    return Text('未设建议词',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('→ $suggestion',
        style: TextStyle(fontSize: 12, color: scheme.primary)),
  );
}

/// 命中处上下文行：命中词红底加粗，点击跳转定位。
class _OccurrenceLine extends StatelessWidget {
  const _OccurrenceLine({required this.occ, required this.onTap});

  final SensitiveOccurrence occ;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: scheme.onSurfaceVariant),
            children: [
              TextSpan(text: occ.before),
              TextSpan(
                text: occ.match,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                  backgroundColor: scheme.error.withValues(alpha: 0.14),
                ),
              ),
              TextSpan(text: occ.after),
            ],
          ),
        ),
      ),
    );
  }
}

/// 词库视图：词条卡片。
class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.word,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final SensitiveWord word;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(word.word,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: word.enabled
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant)),
                  ),
                  if (!word.enabled) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('已停用',
                          style: TextStyle(
                              fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  word.suggestion.isEmpty ? '未设建议词（仅提示）' : '→ ${word.suggestion}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: word.enabled ? '点击停用' : '点击启用',
            child: _CompactSwitch(value: word.enabled, onChanged: onToggle),
          ),
          const SizedBox(width: 6),
          _MiniIconButton(
              icon: Icons.edit_outlined, tooltip: '编辑', onTap: onEdit),
          _MiniIconButton(
              icon: Icons.delete_outline, tooltip: '删除', onTap: onDelete),
        ]),
      ),
    );
  }
}

/// 紧凑胶囊开关：与卡片内小图标按钮尺寸协调，颜色沿用主题 SwitchTheme。
class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const width = 46.0;
    const height = 26.0;
    const borderWidth = 1.5;
    final scheme = Theme.of(context).colorScheme;
    final switchTheme = SwitchTheme.of(context);
    final states = value ? const {WidgetState.selected} : const <WidgetState>{};
    final trackColor = switchTheme.trackColor?.resolve(states) ??
        (value ? scheme.primary : scheme.surfaceContainerHighest);
    final thumbColor = switchTheme.thumbColor?.resolve(states) ??
        (value ? scheme.onPrimary : scheme.outline);
    final outlineColor = switchTheme.trackOutlineColor?.resolve(states) ??
        scheme.outlineVariant;
    const inset = borderWidth + 1.5;
    final thumbSize = height - inset * 2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: outlineColor, width: borderWidth),
          ),
          padding: EdgeInsets.all(inset),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration:
                  BoxDecoration(color: thumbColor, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片内小图标按钮：统一 32×32 触区与 16px 图标。
class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        foregroundColor: scheme.onSurfaceVariant,
        highlightColor: scheme.primary.withValues(alpha: 0.08),
      ),
      icon: Icon(icon),
    );
  }
}