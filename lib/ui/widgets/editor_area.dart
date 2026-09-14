
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
import 'top_message.dart';

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

  /// 上一次渲染的章节 id，用于检测章节切换并复位滚动位置
  String? _lastChapterId;

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
    // 文字高亮主题映射：文档统一存亮色规范值，
    // 暗色主题下渲染为对应深色变体（亮色 i ↔ 暗色 i）。
    final bg = style?.backgroundColor;
    if (bg != null) {
      final mapped = _themeSwatchOf(bg, Theme.brightnessOf(context));
      if (mapped != bg) {
        style = (style ?? const TextStyle()).copyWith(backgroundColor: mapped);
      }
    }

    if (_searchQuery.isEmpty || _searchOffsets.isEmpty) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }

    final nodeStart = node.documentOffset;
    final nodeEnd = nodeStart + text.length;
    final queryLen = _searchQuery.length;

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
      // 匹配可能跨节点（起点在上一节点、终点在下一节点），
      // 必须钳制到当前节点文本边界内，否则 substring 抛 RangeError
      // 导致编辑器子树渲染出 RenderErrorBox 并连锁崩溃。
      final localStart = (ms - nodeStart).clamp(0, text.length);
      final localEnd = (me - nodeStart).clamp(0, text.length);

      if (localStart > pos) {
        children.add(TextSpan(
          text: text.substring(pos, localStart),
          style: style,
          recognizer: recognizer,
        ));
      }

      if (localEnd > pos) {
        children.add(TextSpan(
          text: text.substring(localStart, localEnd),
          style: (style ?? const TextStyle()).copyWith(
            background: Paint()..color = isCurrent ? currentColor : matchColor,
          ),
          recognizer: recognizer,
        ));
        pos = localEnd;
      }
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

    // 切换章节时将编辑器滚动位置复位到顶部（State 跨章节复用，滚动位置会残留）
    if (chapter.id != _lastChapterId) {
      _lastChapterId = chapter.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
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
                // Ctrl+U / Ctrl+Shift+X 同理在此拦截，切换下划线/删除线。
                // ignore: experimental_member_use
                onKeyPressed: (event, node) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyF &&
                      HardwareKeyboard.instance.isControlPressed) {
                    _openSearch(withReplace: true);
                    return KeyEventResult.handled;
                  }
                  final ctrl = HardwareKeyboard.instance.isControlPressed;
                  final shift = HardwareKeyboard.instance.isShiftPressed;
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyU &&
                      ctrl &&
                      !shift) {
                    _toggleInlineAttr(
                        state.editorController, Attribute.underline);
                    return KeyEventResult.handled;
                  }
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.keyX &&
                      ctrl &&
                      shift) {
                    _toggleInlineAttr(
                        state.editorController, Attribute.strikeThrough);
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
            showTopMessage(ctx, '自动保存失败，请检查磁盘空间；正文仍在内存中，请勿关闭应用。');
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
      // 历史按钮在 initState 时订阅 document.changes 流；replaceDocument
      // 整体替换 Document 实例后旧流不再发事件，按钮会永久置灰。
      // 用 Document 实例作 key，替换文档时重建按钮以重新订阅新流。
      QuillToolbarHistoryButton(
        // Document 未重写 toString/==，直接插值得到的 key 恒定不变，
        // 必须用 identityHashCode 区分实例（替换文档时 key 才会变化）。
        key: ValueKey('undo-${identityHashCode(state.editorController.document)}'),
        controller: state.editorController,
        isUndo: true,
        baseOptions: base,
      ),
      QuillToolbarHistoryButton(
        key: ValueKey('redo-${identityHashCode(state.editorController.document)}'),
        controller: state.editorController,
        isUndo: false,
        baseOptions: base,
      ),
      // Quill 原生搜索按钮，通过 customOnPressedCallback 保持打开应用内搜索替换栏。
      QuillToolbarSearchButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarSearchButtonOptions(
          tooltip: '搜索与替换 (Ctrl+F)',
          customOnPressedCallback: (_) async => _openSearch(withReplace: false),
        ),
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.bold,
        controller: state.editorController,
        baseOptions: base,
        options: const QuillToolbarToggleStyleButtonOptions(tooltip: '加粗'),
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.italic,
        controller: state.editorController,
        baseOptions: base,
        options: const QuillToolbarToggleStyleButtonOptions(tooltip: '斜体'),
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.underline,
        controller: state.editorController,
        baseOptions: base,
        options: const QuillToolbarToggleStyleButtonOptions(tooltip: '下划线'),
      ),
      QuillToolbarToggleStyleButton(
        attribute: Attribute.strikeThrough,
        controller: state.editorController,
        baseOptions: base,
        options: const QuillToolbarToggleStyleButtonOptions(tooltip: '删除线'),
      ),
      _HighlightToolbarButton(controller: state.editorController),
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
              showTopMessage(context, '已创建手动快照');
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

  /// 切换内联样式属性（有则移除，无则应用），供快捷键使用。
  static void _toggleInlineAttr(QuillController controller, Attribute attr) {
    final enabled =
        controller.getSelectionStyle().attributes.containsKey(attr.key);
    controller.formatSelection(enabled ? Attribute.clone(attr, null) : attr);
  }

  Future<void> _runFormatter(BuildContext context, AppState state) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final before = state.editorController.document.toPlainText();
    final after = TextFormatter.format(before);
    if (after == before) {
      if (context.mounted) {
        showTopMessage(context, '排版完成：无需修改');
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
    state.replaceDocument(RichTextCodec.documentFromContent(after));
    await state.autosave.flush();
    if (context.mounted) {
      showTopMessage(context, '排版已应用；如需撤销请前往「历史快照」回滚');
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
        showTopMessage(context, '已导入 ${parts.length} 个章节');
      }
    } else {
      final raw = await FileIO.pickReadText(ext: ['docx']);
      if (raw == null) return;
      if (context.mounted) {
        showTopMessage(
            context, 'docx 导入请在导出对话框中使用 TXT 版本；MVP 暂不解析二进制 docx');
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
    showTopMessage(context, path == null ? '已取消导出' : '导出成功：$path');
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
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isSelected ? selectedColor : unselectedColor,
            ),
          ),
        );
      }).toList(),
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

/// 高亮色板（亮色主题）：精选柔和底色，深色文字下均可读。
const List<Color> _highlightLightSwatches = [
  Color(0xFFFFEB3B), // 亮黄
  Color(0xFFFFB74D), // 橙
  Color(0xFFE57373), // 红
  Color(0xFFF48FB1), // 粉
  Color(0xFFBA68C8), // 紫
  Color(0xFF64B5F6), // 蓝
  Color(0xFF4DB6AC), // 青
  Color(0xFF81C784), // 绿
  Color(0xFFAED581), // 黄绿
];

/// 高亮色板（暗色主题）：同色相的深色变体，浅色文字下均可读。
const List<Color> _highlightDarkSwatches = [
  Color(0xFFF9A825), // 亮黄
  Color(0xFFB26A00), // 橙
  Color(0xFFC62828), // 红
  Color(0xFFAD1457), // 粉
  Color(0xFF6A1B9A), // 紫
  Color(0xFF1565C0), // 蓝
  Color(0xFF00695C), // 青
  Color(0xFF2E7D32), // 绿
  Color(0xFF558B2F), // 黄绿
];

/// 清除高亮占位格（色板末位）：与色块同尺寸的空心格，无高亮时置灰。
class _ClearCell extends StatelessWidget {
  const _ClearCell({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: onSurface.withValues(alpha: enabled ? 0.6 : 0.15),
          ),
        ),
        child: Icon(
          Icons.format_color_reset,
          size: 16,
          color: onSurface.withValues(alpha: enabled ? 0.8 : 0.2),
        ),
      ),
    );
  }
}

/// 高亮弹窗的色块：紧凑小方块，选中态为主题色描边加对号。
class _SwatchCell extends StatelessWidget {
  const _SwatchCell({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.black26, width: 0.5),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 12,
                color:
                    color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              )
            : null,
      ),
    );
  }
}

/// 把颜色编码为 Quill 背景属性使用的 #rrggbb 十六进制字符串。
String _highlightHex(Color c) {
  String channel(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}

/// 解析选区上的背景色属性，无背景或格式不符时返回 null。
Color? _selectionBackground(QuillController controller) {
  final value =
      controller.getSelectionStyle().attributes[Attribute.background.key]?.value;
  if (value is String && value.length == 7 && value.startsWith('#')) {
    return Color(int.parse('0xFF${value.substring(1)}'));
  }
  return null;
}

/// 文字高亮按钮（参考 Word/WPS 交互，无模态弹窗）：
/// - 主体为油漆桶图标 + 当前颜色条；点击时选区有高亮则清除，否则应用当前颜色；
/// - 右侧下拉箭头展开色板浮层，点选即应用并记住为当前颜色。
class _HighlightToolbarButton extends StatefulWidget {
  const _HighlightToolbarButton({required this.controller});

  final QuillController controller;

  @override
  State<_HighlightToolbarButton> createState() =>
      _HighlightToolbarButtonState();
}

class _HighlightToolbarButtonState extends State<_HighlightToolbarButton> {
  /// 当前颜色（跨选区记忆，与 Word 行为一致）。
  Color _current = _highlightLightSwatches.first;

  final MenuController _menuController = MenuController();

  Color? _selectionBg;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromSelection);
    _syncFromSelection();
  }

  @override
  void didUpdateWidget(covariant _HighlightToolbarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromSelection);
      widget.controller.addListener(_syncFromSelection);
      _syncFromSelection();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromSelection);
    super.dispose();
  }

  void _syncFromSelection() {
    final bg = _selectionBackground(widget.controller);
    if (bg != _selectionBg) {
      setState(() => _selectionBg = bg);
    }
  }

  void _apply(Color? color) {
    widget.controller.formatSelection(
      Attribute.clone(
        Attribute.background,
        color == null
            ? null
            : _highlightHex(_canonicalSwatchOf(color)),
      ),
    );
  }

  /// 主体点击：与当前颜色相同的高亮再点即清除，否则应用当前颜色。
  void _toggleOnSelection() {
    if (_selectionBg != null) {
      _apply(null);
    } else {
      _apply(_current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    final active = _selectionBg != null;
    final activeDisplay = _selectionBg == null
        ? null
        : _themeSwatchOf(_selectionBg!, Theme.of(context).brightness);

    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 152,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final swatch in _paletteFor(context))
                  _SwatchCell(
                    color: swatch,
                    selected: activeDisplay == swatch,
                    onTap: () {
                      setState(() => _current = _canonicalSwatchOf(swatch));
                      _apply(swatch);
                      _menuController.close();
                    },
                  ),
                _ClearCell(
                  enabled: _selectionBg != null,
                  onTap: () {
                    _menuController.close();
                    _apply(null);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (menuContext, menuController, _) => Tooltip(
        message: '文字高亮',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
            onTap: _toggleOnSelection,
            child: Container(
              width: 34,
              height: 32,
              decoration: BoxDecoration(
                color: active ? primary.withValues(alpha: 0.15) : null,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(6)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.format_color_fill,
                    size: 17,
                    color: active ? primary : onSurface,
                  ),
                  const SizedBox(height: 1),
                  Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _themeSwatchOf(
                          _current, Theme.of(context).brightness),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(6)),
            onTap: () =>
                menuController.isOpen ? menuController.close() : menuController.open(),
            child: Container(
              width: 14,
              height: 32,
              decoration: BoxDecoration(
                color: active ? primary.withValues(alpha: 0.15) : null,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(6)),
              ),
              child: Icon(Icons.arrow_drop_down, size: 14, color: onSurface),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 暗色主题下换用深色变体色板，保证主题文字颜色在底色上可读。
List<Color> _paletteFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? _highlightDarkSwatches
        : _highlightLightSwatches;

/// 规范存储色 → 当前主题显示色（亮色 i ↔ 暗色 i 双向对应）。
/// 文档统一存亮色值，暗色主题下渲染与按钮状态映射为对应深色变体。
Color _themeSwatchOf(Color canonical, Brightness brightness) {
  final i = _highlightLightSwatches.indexOf(canonical);
  if (i < 0) return canonical;
  return brightness == Brightness.dark
      ? _highlightDarkSwatches[i]
      : _highlightLightSwatches[i];
}

/// 显示色 → 亮色规范存储值（暗色色板色转对应亮色；非色板色原样返回）。
Color _canonicalSwatchOf(Color display) {
  if (_highlightLightSwatches.contains(display)) return display;
  final i = _highlightDarkSwatches.indexOf(display);
  if (i >= 0) return _highlightLightSwatches[i];
  return display;
}
