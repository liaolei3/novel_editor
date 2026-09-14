
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/docx_exporter.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_formatter.dart';
import '../../core/utils/text_stats.dart';
import '../../core/utils/txt_importer.dart';
import '../../data/models.dart';
import '../../services/autosave_service.dart';
import '../../state/app_state.dart';

import '../common/file_io.dart';
import 'app_icon.dart';
import 'search_replace_bar.dart';

/// 编辑器区域：富文本工具栏 + 正文输入；沉浸/夜间/字体行距由全局设置控制。
/// Stateful：持有稳定的 FocusNode/ScrollController——QuillEditor.basic 每次
/// 构建会新建 FocusNode，重建过频（如输入触发 notifyListeners）会导致焦点
/// 丢失、光标消失，必须显式复用同一节点。
class EditorArea extends StatefulWidget {
  const EditorArea({super.key, required this.book});

  final Book book;

  @override
  State<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<EditorArea> {
  final FocusNode _focusNode = FocusNode();
  final _EditorScrollController _scrollController = _EditorScrollController();
  bool _showSearch = false;
  bool _showReplace = false;
  String _searchSeed = '';

  /// 搜索全量高亮状态
  List<int> _searchOffsets = const [];
  int _searchIndex = 0;
  String _searchQuery = '';

  void _onSearchChanged(List<int> offsets, int index, String query) {
    setState(() {
      _searchOffsets = offsets;
      _searchIndex = index;
      _searchQuery = query;
    });
  }

  /// 打开搜索栏并展开替换行（Ctrl+F / 工具栏按钮）；
  /// 首次打开时若编辑器有选区，则用选中文本预填查找词。
  void _openSearch({required bool withReplace}) {
    if (!_showSearch) {
      final ctrl = context.read<AppState>().editorController;
      final sel = ctrl.selection;
      final docLen = ctrl.document.length;
      if (!sel.isCollapsed && sel.start >= 0 && sel.end <= docLen) {
        _searchSeed =
            ctrl.document.toPlainText().substring(sel.start, sel.end);
      } else {
        _searchSeed = '';
      }
    }
    setState(() {
      _showSearch = true;
      _showReplace = withReplace;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 自定义 textSpanBuilder：搜索时对匹配文本做背景高亮。
  /// 非当前匹配与普通选中文本背景一致；
  /// 当前匹配用同色但更高不透明度（更浓），保持色相一致且更突出。
  InlineSpan _searchHighlightSpanBuilder(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    if (_searchQuery.isEmpty || _searchOffsets.isEmpty) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }

    final nodeStart = node.documentOffset;
    final nodeEnd = nodeStart + text.length;
    final queryLen = _searchQuery.length;

    // 收集与该文本节点重叠的匹配范围
    final ranges = <(int start, int end, bool isCurrent)>[];
    for (var i = 0; i < _searchOffsets.length; i++) {
      final ms = _searchOffsets[i];
      final me = ms + queryLen;
      if (ms < nodeEnd && me > nodeStart) {
        ranges.add((ms, me, i == _searchIndex));
      }
    }
    if (ranges.isEmpty) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }

    final matchColor = TextSelectionTheme.of(context).selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.4);
    final currentColor =
        matchColor.withValues(alpha: (matchColor.a * 2.5).clamp(0.0, 1.0));

    final children = <InlineSpan>[];
    int pos = 0;
    for (final (ms, me, isCurrent) in ranges) {
      final localStart = ms - nodeStart;
      final localEnd = me - nodeStart;

      if (localStart > pos) {
        children.add(TextSpan(
          text: text.substring(pos, localStart),
          style: style,
          recognizer: recognizer,
        ));
      }

      children.add(TextSpan(
        text: text.substring(localStart,
            localEnd > text.length ? text.length : localEnd),
        style: (style ?? const TextStyle()).copyWith(
          background: Paint()..color = isCurrent ? currentColor : matchColor,
        ),
        recognizer: recognizer,
      ));

      pos = localEnd;
    }

    if (pos < text.length) {
      children.add(TextSpan(
        text: text.substring(pos),
        style: style,
        recognizer: recognizer,
      ));
    }

    return TextSpan(children: children, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapter = state.currentChapter;

    if (chapter == null) {
      return const Center(child: Text('从左侧目录选择或新建一个章节开始写作'));
    }

    final sessionChars = state.session.sessionChars;
    final savingHint = _saveIndicator(context);
    final plain = state.editorController.document.toPlainText();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _openSearch(withReplace: true),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() {
              _showSearch = false;
              _showReplace = false;
              _searchOffsets = const [];
              _searchIndex = 0;
              _searchQuery = '';
            }),
      },
      child: Column(children: [
        _topBar(context, savingHint),
        _richToolbar(context, state),
        const Divider(height: 1),
        if (_showSearch)
          SearchReplaceBar(
            controller: state.editorController,
            editorFocusNode: _focusNode,
            initialText: _searchSeed,
            showReplaceInitially: _showReplace,
            onSearchChanged: _onSearchChanged,
            onClose: () => setState(() {
              _showSearch = false;
              _showReplace = false;
              _searchOffsets = const [];
              _searchIndex = 0;
              _searchQuery = '';
            }),
          ),
        if (TextStats.charCount(plain) > AppConstants.longChapterThreshold)
          MaterialBanner(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: const Text('本章超过 5 万字，建议拆分为多章以保证编辑流畅度。'),
            actions: [TextButton(onPressed: () {}, child: const Text('知道了'))],
          ),
        Expanded(
          child: Listener(
            // 鼠标拖选期间抑制 flutter_quill 内部 _showCaretOnScreen 触发的
            // animateTo（它会把视口拉回选区起点，与 bringIntoView 的向下
            // jumpTo 互相冲突，导致滚动条反复向上反弹）。
            onPointerDown: (event) => _scrollController.suppressAnimateTo =
                event.kind == PointerDeviceKind.mouse,
            onPointerUp: (_) => _scrollController.suppressAnimateTo = false,
            onPointerCancel: (_) => _scrollController.suppressAnimateTo = false,
            child: QuillEditor.basic(
              controller: state.editorController,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textSpanBuilder: _searchHighlightSpanBuilder,
                autoFocus: false,
                expands: true,
                // Quill 自带 Ctrl+F 会打开其内置查找弹窗，这里在其按键处理链
                // 最前端拦截，改为打开应用内搜索替换栏（与工具栏按钮一致）。
                // ignore: experimental_member_use
                onKeyPressed: (event, node) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyF &&
                      HardwareKeyboard.instance.isControlPressed) {
                    _openSearch(withReplace: true);
                    return KeyEventResult.handled;
                  }
                  return null;
                },
              ),
            ),
          ),
        ),
        _statusBar(context, chapter, sessionChars, plain),
      ]),
    );
  }

  Widget _saveIndicator(BuildContext context) {
    final autosave = context.read<AppState>().autosave;
    return ValueListenableBuilder<SaveState>(
      valueListenable: autosave.state,
      builder: (ctx, s, _) {
        final (icon, label, color) = switch (s) {
          SaveState.saved => (Icons.cloud_done_outlined, '已保存', Theme.of(ctx).colorScheme.primary),
          SaveState.unsaved => (Icons.schedule, '待保存', Theme.of(ctx).colorScheme.outline),
          SaveState.saving => (Icons.sync, '保存中…', Theme.of(ctx).colorScheme.outline),
          SaveState.failed => (Icons.error_outline, '保存失败', Theme.of(ctx).colorScheme.error),
        };
        if (s == SaveState.failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('自动保存失败，请检查磁盘空间；正文仍在内存中，请勿关闭应用。')));
          });
        }
        return Tooltip(
          message: '输入停顿 2 秒自动保存；每 30 秒兜底落盘',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ]),
        );
      },
    );
  }

  /// 顶部条：保存状态。
  Widget _topBar(BuildContext context, Widget savingHint) {
    return SizedBox(
      height: 44,
      child: Row(children: [
        const SizedBox(width: 8),
        savingHint,
      ]),
    );
  }

  /// 富文本工具栏：显式左对齐排布；H1/H2/H3 自建以支持独立 tooltip（一级/二级/三级标题）。
  Widget _richToolbar(BuildContext context, AppState state) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final base = QuillToolbarBaseButtonOptions(
      iconSize: 20,
      iconButtonFactor: 1.0,
      iconTheme: QuillIconTheme(
        iconButtonUnselectedData: IconButtonData(
          color: onSurface,
          padding: const EdgeInsets.all(5),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        ),
        iconButtonSelectedData: IconButtonData(color: onPrimary),
      ),
    );
    final headerTheme = QuillIconTheme(
      iconButtonUnselectedData: IconButtonData(
        color: onSurface,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      ),
      iconButtonSelectedData: IconButtonData(color: onPrimary),
    );

    final children = <Widget>[
      QuillToolbarHistoryButton(
        controller: state.editorController,
        isUndo: true,
        baseOptions: base,
      ),
      QuillToolbarHistoryButton(
        controller: state.editorController,
        isUndo: false,
        baseOptions: base,
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const AppIcon(Icons.search, size: 18),
          tooltip: '搜索与替换 (Ctrl+F)',
          onPressed: () => _openSearch(withReplace: false),
        ),
      ),
      _InlineStyleButtons(
        controller: state.editorController,
        iconTheme: base.iconTheme!,
      ),
      _HeaderStyleButtons(
        controller: state.editorController,
        iconTheme: headerTheme,
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.ol,
        controller: state.editorController,
        baseOptions: base,
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.ul,
        controller: state.editorController,
        baseOptions: base,
      ),
      QuillToolbarToggleCheckListButton(
        controller: state.editorController,
        baseOptions: base,
      ),
      QuillToolbarIndentButton(
        controller: state.editorController,
        isIncrease: false,
        baseOptions: base,
      ),
      QuillToolbarIndentButton(
        controller: state.editorController,
        isIncrease: true,
        baseOptions: base,
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const AppIcon(Icons.auto_fix_high, size: 20),
          tooltip: '一键排版',
          onPressed: () => _runFormatter(context, state),
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const AppIcon(Icons.camera_alt_outlined, size: 20),
          tooltip: '手动快照',
          onPressed: () async {
            await state.durability.manualSnapshot(state.currentChapter!);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已创建手动快照')));
            }
          },
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const AppIcon(Icons.file_download_outlined, size: 20),
          tooltip: '导入 TXT / docx',
          onPressed: () => _import(context, state),
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const AppIcon(Icons.file_upload_outlined, size: 20),
          tooltip: '导出 TXT / Word',
          onPressed: () => _export(context, state),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      // 强制占满整行并从左侧排布，避免被外层 Column 的居中对齐影响。
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
  }

  Widget _statusBar(BuildContext context, Chapter chapter, int sessionChars, String plain) {
    final state = context.watch<AppState>();
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 窄栏时隐藏口径说明，并允许统计文本省略，避免溢出分割线。
          final showNote = constraints.maxWidth >= 520;
          const style = TextStyle(fontSize: 11);
          return Row(children: [
            Flexible(
              child: Text('本章 ${TextStats.charCount(plain)} 字',
                  style: style, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text('全书 ${state.bookCharTotal} 字',
                  style: style, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text('本次会话 +$sessionChars 字',
                  style: style, overflow: TextOverflow.ellipsis),
            ),
            const Spacer(),
            if (showNote)
              const Text('口径：字符数（含标点，不含空白）',
                  style: TextStyle(fontSize: 10)),
          ]);
        },
      ),
    );
  }

  // ---- 一键排版（预览 → 应用，应用前自动快照可撤销） ----

  Future<void> _runFormatter(BuildContext context, AppState state) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final before = state.editorController.document.toPlainText();
    final after = TextFormatter.format(before);
    if (after == before) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('排版完成：无需修改')));
      }
      return;
    }
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键排版预览'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: Column(children: [
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Column(children: [
                    const Text('排版前'),
                    Expanded(child: SingleChildScrollView(child: SelectableText(before,
                        style: const TextStyle(fontSize: 12, height: 1.5)))),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(children: [
                    const Text('排版后'),
                    Expanded(child: SingleChildScrollView(child: SelectableText(after,
                        style: const TextStyle(fontSize: 12, height: 1.5)))),
                  ]),
                ),
              ]),
            ),
            const Text('提示：排版作用于纯文本，应用后富文本格式将被重置。',
                style: TextStyle(fontSize: 11, color: Colors.orange)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('应用（应用前自动快照）')),
        ],
      ),
    );
    if (apply != true) return;
    await state.durability.manualSnapshot(chapter);
    state.editorController.document = RichTextCodec.documentFromContent(after);
    state.onEditorChanged();
    await state.autosave.flush();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('排版已应用；如需撤销请前往「历史快照」回滚')));
    }
  }

  // ---- 导入导出 ----

  Future<void> _import(BuildContext context, AppState state) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('导入'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'txt'), child: const Text('批量导入 TXT（按“第X章”自动切分）')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'docx'), child: const Text('导入 docx（单文件 = 单章节）')),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'txt') {
      final raw = await FileIO.pickReadText();
      if (raw == null) return;
      final parts = TxtImporter.splitChapters(raw);
      final volumeId = state.volumeTree.isNotEmpty
          ? state.volumeTree.first.id
          : (await state.addVolume('导入卷')).id;
      for (final part in parts) {
        final ch = await state.addChapter(volumeId, title: part.key, outline: '');
        ch.content = RichTextCodec.deltaJsonFromPlainText(part.value);
        await state.chapters.updateContent(ch);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入 ${parts.length} 个章节')));
      }
    } else {
      final raw = await FileIO.pickReadText(ext: ['docx']);
      if (raw == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('docx 导入请在导出对话框中使用 TXT 版本；MVP 暂不解析二进制 docx')));
      }
    }
  }

  Future<void> _export(BuildContext context, AppState state) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('导出'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'chapter'), child: const Text('导出本章 TXT')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'book_txt'), child: const Text('导出全书 TXT')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'book_docx'), child: const Text('导出全书 Word (.docx)')),
        ],
      ),
    );
    if (choice == null || state.currentBook == null) return;
    final bookTitle = state.currentBook!.title;
    final penName = state.currentBook!.penName;

    if (choice == 'chapter') {
      final chapter = state.currentChapter;
      if (chapter == null) return;
      final body = RichTextCodec.plainTextFromDeltaJson(chapter.content);
      final path = await FileIO.saveText(
          fileName: '${chapter.title}.txt',
          content: '${chapter.title}\n\n$body');
      _toast(context, path);
    } else if (choice == 'book_txt') {
      final withTitle = await _askIncludeTitle(context);
      if (withTitle == null) return;
      final sb = StringBuffer();
      for (final ch in state.chapterList) {
        if (withTitle) sb.writeln(ch.title);
        sb.writeln(RichTextCodec.plainTextFromDeltaJson(ch.content));
        sb.writeln();
      }
      final path = await FileIO.saveText(fileName: '$bookTitle.txt', content: sb.toString());
      _toast(context, path);
    } else {
      final bytes = DocxExporter.build(
        bookTitle: bookTitle,
        penName: penName,
        chapters: state.chapterList
            .map((c) => MapEntry(c.title, RichTextCodec.plainTextFromDeltaJson(c.content)))
            .toList(),
      );
      final path = await FileIO.saveBytes(fileName: '$bookTitle.docx', bytes: bytes);
      _toast(context, path);
    }
  }

  Future<bool?> _askIncludeTitle(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否包含章节名？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('不含')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('包含')),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String? path) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null ? '已取消导出' : '导出成功：$path')));
  }
}

/// H1/H2/H3 按钮组：复刻 Quill 原生选中逻辑，但每个按钮独立 tooltip（一级/二级/三级标题）。
class _HeaderStyleButtons extends StatefulWidget {
  const _HeaderStyleButtons({required this.controller, required this.iconTheme});

  final QuillController controller;
  final QuillIconTheme iconTheme;

  @override
  State<_HeaderStyleButtons> createState() => _HeaderStyleButtonsState();
}

class _HeaderStyleButtonsState extends State<_HeaderStyleButtons> {
  Attribute? _selected;

  static const _items = [
    (Attribute.h1, 'H1', '一级标题'),
    (Attribute.h2, 'H2', '二级标题'),
    (Attribute.h3, 'H3', '三级标题'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = _current();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _HeaderStyleButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _selected = _current();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Attribute _current() {
    final toggler = widget.controller.toolbarButtonToggler;
    final attr = toggler[Attribute.header.key];
    if (attr != null) {
      toggler.remove(Attribute.header.key);
      return attr;
    }
    return widget.controller.getSelectionStyle().attributes[Attribute.header.key] ??
        Attribute.header;
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _selected = _current());
  }

  @override
  Widget build(BuildContext context) {
    final unselectedColor = widget.iconTheme.iconButtonUnselectedData?.color;
    final selectedColor = widget.iconTheme.iconButtonSelectedData?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _items.map((item) {
        final (attr, label, tip) = item;
        final isSelected = _selected == attr;
        return QuillToolbarIconButton(
          tooltip: tip,
          iconTheme: widget.iconTheme,
          isSelected: isSelected,
          onPressed: () {
            widget.controller
                .formatSelection(_selected == attr ? Attribute.header : attr);
          },
          icon: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
                color: isSelected ? selectedColor : unselectedColor,
              ),
            ),
          );
      }).toList(),
    );
  }
}

/// 加粗/斜体按钮组：文字样式与 H1/H2/H3 保持一致（14px）；I 用 Zpix 渲染以呈现上下衬线横线。
class _InlineStyleButtons extends StatefulWidget {
  const _InlineStyleButtons({required this.controller, required this.iconTheme});

  final QuillController controller;
  final QuillIconTheme iconTheme;

  @override
  State<_InlineStyleButtons> createState() => _InlineStyleButtonsState();
}

class _InlineStyleButtonsState extends State<_InlineStyleButtons> {
  bool _bold = false;
  bool _italic = false;

  @override
  void initState() {
    super.initState();
    _update();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _InlineStyleButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _update();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _update() {
    final attrs = widget.controller.getSelectionStyle().attributes;
    _bold = attrs.containsKey(Attribute.bold.key);
    _italic = attrs.containsKey(Attribute.italic.key);
  }

  void _changed() {
    if (!mounted) return;
    setState(_update);
  }

  void _toggle(Attribute attr, bool current) {
    widget.controller.formatSelection(
      current ? Attribute.clone(attr, null) : attr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final unselectedColor = widget.iconTheme.iconButtonUnselectedData?.color;
    final selectedColor = widget.iconTheme.iconButtonSelectedData?.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        QuillToolbarIconButton(
          tooltip: '加粗',
          iconTheme: widget.iconTheme,
          isSelected: _bold,
          onPressed: () => _toggle(Attribute.bold, _bold),
          icon: Text(
            'B',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: _bold ? selectedColor : unselectedColor,
            ),
          ),
        ),
        QuillToolbarIconButton(
          tooltip: '斜体',
          iconTheme: widget.iconTheme,
          isSelected: _italic,
          onPressed: () => _toggle(Attribute.italic, _italic),
          icon: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.25),
            child: Text(
              'I',
              style: TextStyle(
                fontFamily: 'Zpix',
                fontSize: 14,
                color: _italic ? selectedColor : unselectedColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 编辑器滚动控制器：可在鼠标拖选期间忽略外部 animateTo 请求
/// （jumpTo 不受影响，保证拖选时向下自动滚动仍然生效）。
class _EditorScrollController extends ScrollController {
  bool _suppressAnimateTo = false;

  set suppressAnimateTo(bool value) => _suppressAnimateTo = value;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    if (_suppressAnimateTo) return Future.value();
    return super.animateTo(offset, duration: duration, curve: curve);
  }
}
