
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/docx_exporter.dart';
import '../../core/utils/pair_symbols.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_formatter.dart';
import '../../core/utils/text_stats.dart';
import '../../core/utils/txt_importer.dart';
import '../../data/models.dart';
import '../../services/autosave_service.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';

import '../common/context_menu.dart';
import '../common/dialogs.dart';
import '../common/file_io.dart';
import 'character_tip.dart';
import 'search_replace_bar.dart';
import 'toast.dart';

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

  List<int> _searchOffsets = const [];
  int _searchIndex = 0;
  String _searchQuery = '';

  String? _lastChapterId;

  /// 最近一次右键按下的全局坐标与时间：编辑器右键菜单跟随鼠标位置
  /// 而非选区位置（选区可能在远离点击处）。
  Offset? _secondaryTapPosition;
  DateTime? _secondaryTapAt;

  /// 搜索栏重挂载计数：全局搜索跳转等场景需要重置栏内状态并重新定位。
  int _searchNonce = 0;

  /// 角色名高亮词典：name/alias → 角色；按长度降序正则实现最长匹配。
  Map<String, Character> _nameToChar = const {};
  RegExp? _nameRegExp;

  /// 缓存 AppState：dispose 期间禁止通过 context 查找祖先节点。
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _refreshCharacterDict();
    _appState.characterDictVersion.addListener(_refreshCharacterDict);
  }

  Future<void> _refreshCharacterDict() async {
    final state = context.read<AppState>();
    final list = await state.characters.listByBook(widget.book.id);
    if (!mounted) return;
    final map = <String, Character>{};
    void addName(String raw, Character c) {
      final n = raw.trim();
      if (n.isNotEmpty && !map.containsKey(n)) map[n] = c;
    }

    for (final c in list) {
      addName(c.name, c);
      for (final a in c.aliases.split(',')) {
        addName(a, c);
      }
    }
    final names = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    setState(() {
      _nameToChar = map;
      _nameRegExp = names.isEmpty ? null : RegExp(names.map(RegExp.escape).join('|'));
    });
  }

  void _onSearchChanged(List<int> offsets, int index, String query) {
    setState(() {
      _searchOffsets = offsets;
      _searchIndex = index;
      _searchQuery = query;
    });
  }

  /// 打开搜索栏并展开替换行（Ctrl+F / 工具栏按钮）。
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
      _searchNonce++;
    });
  }

  @override
  void dispose() {
    _appState.characterDictVersion.removeListener(_refreshCharacterDict);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 中文段落首行缩进：两个全角空格。
  static const String _cnIndent = '\u3000\u3000';

  /// 光标所在行是否为普通段落（无列表/引用/代码块/标题/对齐等块级属性）。
  bool _isPlainLine(QuillController controller, int offset) {
    final node = controller.document.queryChild(offset).node;
    if (node == null) return true;
    return node.style.attributes.values
        .every((attr) => attr.scope != AttributeScope.block);
  }

  /// 回车：自动插入一个空行 + 普通段落行首缩进两个全角空格。
  /// 单次 replaceText 同时写入空行与缩进，撤销时一并回退。
  /// 块级行（列表/引用/代码块/标题）保持 Quill 默认换行行为。
  void _handleEnterWithIndent(QuillController controller) {
    final sel = controller.selection;
    final start = sel.start;
    final insert =
        _isPlainLine(controller, start) ? '\n\n$_cnIndent' : '\n';
    controller.replaceText(
      start,
      sel.end - start,
      insert,
      TextSelection.collapsed(offset: start + insert.length),
    );
  }

  /// Tab：普通段落插入两个全角空格；
  /// 有选区或块级行（列表等需要缩进层级）交给 Quill 默认处理。
  KeyEventResult? _handleTabIndent(QuillController controller) {
    final sel = controller.selection;
    if (sel.baseOffset != sel.extentOffset) return null;
    if (!_isPlainLine(controller, sel.baseOffset)) return null;
    controller.replaceText(
      sel.baseOffset,
      0,
      _cnIndent,
      TextSelection.collapsed(offset: sel.baseOffset + _cnIndent.length),
    );
    return KeyEventResult.handled;
  }

  static bool _isWhitespace(String ch) =>
      ch == '\n' || ch == ' ' || ch == '\u3000' || ch == '\t';

  /// 段首退格：一次性删除光标前的所有缩进空格与空行，
  /// 使当前段落直接衔接上一段文字；单次 replaceText，撤销一并回退。
  /// 光标前（行内）存在非空白字符、有选区或已到文档开头时交给 Quill 默认处理。
  KeyEventResult? _handleBackspaceAtParagraphStart(
      QuillController controller) {
    final sel = controller.selection;
    if (!sel.isCollapsed) return null;
    final offset = sel.start;
    if (offset == 0) return null;
    final text = controller.document.toPlainText();
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    for (var i = lineStart; i < offset; i++) {
      if (!_isWhitespace(text[i])) return null;
    }
    var target = offset;
    while (target > 0 && _isWhitespace(text[target - 1])) {
      target--;
    }
    if (target == offset) return null;
    controller.replaceText(
      target,
      offset - target,
      '',
      TextSelection.collapsed(offset: target),
    );
    return KeyEventResult.handled;
  }

  /// 自定义 textSpanBuilder：角色名高亮 + 搜索背景高亮复合。
  InlineSpan _textSpanBuilder(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    // TextAlign.justify 下引擎会裁掉行首空白（段首全角空格缩进会消失），
    // 渲染层把行首 \u3000 替换为等宽 WidgetSpan 占位：每个占位符对应
    // 恰好一个字符位，文档文本与光标/选区映射均不受影响。
    var leading = 0;
    if (nodeOffset == 0 && node.isFirst) {
      while (leading < text.length && text.codeUnitAt(leading) == 0x3000) {
        leading++;
      }
    }
    if (leading > 0) {
      final fs =
          style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
      return TextSpan(
        style: style,
        children: [
          for (var i = 0; i < leading; i++)
            WidgetSpan(
              alignment: PlaceholderAlignment.bottom,
              child: SizedBox(width: fs),
            ),
          _richSpan(context, node, nodeOffset, text.substring(leading), style,
              recognizer),
        ],
      );
    }
    return _richSpan(context, node, nodeOffset, text, style, recognizer);
  }

  InlineSpan _richSpan(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    final regex = _nameRegExp;
    if (regex == null) {
      return _searchHighlightSpanBuilder(
          context, node, nodeOffset, text, style, recognizer);
    }
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) {
      return _searchHighlightSpanBuilder(
          context, node, nodeOffset, text, style, recognizer);
    }

    final scheme = Theme.of(context).colorScheme;
    InlineSpan plain(int from, int to) {
      return _searchHighlightSpanBuilder(context, node, nodeOffset + from,
          text.substring(from, to), style, recognizer);
    }

    final children = <InlineSpan>[];
    int pos = 0;
    for (final m in matches) {
      if (m.start > pos) children.add(plain(pos, m.start));
      final char = _nameToChar[text.substring(m.start, m.end)];
      if (char != null) {
        // 文字颜色与下划线用角色标记色；hover 展示信息卡。
        final color = parseCharacterColor(char.color) ?? scheme.primary;
        children.add(TextSpan(
          text: text.substring(m.start, m.end),
          style: (style ?? const TextStyle()).copyWith(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
          onEnter: (e) =>
              scheduleCharacterTip(context, e.position, char, () {
                context.read<AppState>().requestOpenCharacter(char.id);
              }),
          onExit: (_) => cancelCharacterTip(),
        ));
      } else {
        children.add(plain(m.start, m.end));
      }
      pos = m.end;
    }
    if (pos < text.length) children.add(plain(pos, text.length));
    return TextSpan(children: children, style: style);
  }

  /// 搜索匹配背景高亮分段。
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

    final nodeStart = nodeOffset;
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
    final settings = context.watch<SettingsController>();
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
    final std = settings.countStandard;

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
            key: ValueKey('search-$_searchNonce'),
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
        if (TextStats.count(plain, std) > AppConstants.longChapterThreshold)
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
            onPointerDown: (event) {
              _scrollController.suppressAnimateTo =
                  event.kind == PointerDeviceKind.mouse;
              if (event.buttons == kSecondaryButton) {
                _secondaryTapPosition = event.position;
                _secondaryTapAt = DateTime.now();
              }
            },
            onPointerUp: (_) => _scrollController.suppressAnimateTo = false,
            onPointerCancel: (_) => _scrollController.suppressAnimateTo = false,
            // 正文不受「界面字体缩放」影响，字号/行距由设置独立控制。
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
              ),
              child: QuillEditor.basic(
              controller: state.editorController,
              focusNode: _focusNode,
              scrollController: _scrollController,
              config: QuillEditorConfig(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textSpanBuilder: _textSpanBuilder,
                autoPairSymbols: fullWidthPairSymbols,
                customStyles: _editorStyles(context, settings),
                contextMenuBuilder: (context, rawState) {
                  // 「一键分章」：光标后有实际内容才显示；有选区时以选区起点拆分。
                  final sel = rawState.textEditingValue.selection;
                  final splitOffset =
                      sel.isValid && !sel.isCollapsed ? sel.start : sel.baseOffset;
                  var extras = const <AppMenuAction>[];
                  if (!rawState.widget.config.readOnly &&
                      splitOffset >= 0 &&
                      splitOffset < rawState.controller.document.length &&
                      RichTextCodec.hasContentAfter(
                          rawState.controller.document.toDelta(), splitOffset)) {
                    extras = [
                      AppMenuAction(
                        '一键分章',
                        icon: Icons.call_split,
                        onTap: () => state.splitChapterAt(splitOffset),
                      ),
                    ];
                  }
                  return appEditorContextMenuBuilder(
                    context,
                    rawState,
                    secondaryTapPosition: _recentSecondaryTap(),
                    extraEntries: extras,
                  );
                },
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
                  // 回车：换行 + 普通段落自动缩进两个全角空格。
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey ==
                              LogicalKeyboardKey.numpadEnter)) {
                    final mods = HardwareKeyboard.instance;
                    if (!mods.isControlPressed &&
                        !mods.isMetaPressed &&
                        !mods.isAltPressed) {
                      _handleEnterWithIndent(state.editorController);
                      return KeyEventResult.handled;
                    }
                    return null;
                  }
                  // 段首退格：一次性删除前面的所有缩进空格与空行。
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    final mods = HardwareKeyboard.instance;
                    if (!mods.isControlPressed &&
                        !mods.isMetaPressed &&
                        !mods.isAltPressed &&
                        !mods.isShiftPressed) {
                      // 成对空符号中间退格：一并删除开闭符。
                      if (handlePairBackspace(state.editorController)) {
                        return KeyEventResult.handled;
                      }
                      return _handleBackspaceAtParagraphStart(
                          state.editorController);
                    }
                    return null;
                  }
                  // Tab：普通段落插入两个全角空格。
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.tab) {
                    return _handleTabIndent(state.editorController);
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
        ),
        _statusBar(context, chapter, sessionChars, plain),
      ]),
    );
  }

  /// 返回 1 秒内的右键位置：右键菜单由 postFrame 弹出，时间窗保证
  /// 只影响右键触发的菜单；拖选/双击触发的菜单仍跟随选区。
  Offset? _recentSecondaryTap() {
    final at = _secondaryTapAt;
    if (at == null) return null;
    return DateTime.now().difference(at) <= const Duration(seconds: 1)
        ? _secondaryTapPosition
        : null;
  }

  /// 编辑器自定义样式：把全局设置的字体/字号/行距/段间距应用到正文相关块。
  DefaultStyles _editorStyles(BuildContext context, SettingsController settings) {
    final defaults = DefaultStyles.getInstance(context);
    final fs = settings.fontSize;
    // family 为空时保持主题字体（copyWith 传 null 不覆盖）。
    final base = DefaultTextStyle.of(context).style.copyWith(
          fontSize: fs,
          height: settings.lineHeight,
          fontFamily: settings.editorFontFamily.isEmpty
              ? null
              : settings.editorFontFamily,
          decoration: TextDecoration.none,
        );
    final vs =
        VerticalSpacing(0, (fs * settings.paragraphSpacing).toDouble());

    DefaultTextBlockStyle? bodyBlock(DefaultTextBlockStyle? d) =>
        d?.copyWith(style: base, verticalSpacing: vs);

    DefaultTextBlockStyle? scaledHeading(DefaultTextBlockStyle? d) {
      if (d == null) return null;
      final size = d.style.fontSize;
      return size == null
          ? d
          : d.copyWith(style: d.style.copyWith(fontSize: size * fs / 17));
    }

    return DefaultStyles(
      paragraph: bodyBlock(defaults.paragraph),
      indent: bodyBlock(defaults.indent),
      align: bodyBlock(defaults.align),
      // 列表序号/圆点样式与正文一致，否则序号字号偏小且垂直位置偏上。
      leading: defaults.leading?.copyWith(style: base),
      lists: defaults.lists?.copyWith(style: base, verticalSpacing: vs),
      quote: defaults.quote?.copyWith(
        style: base.copyWith(color: base.color?.withValues(alpha: 0.6)),
      ),
      h1: scaledHeading(defaults.h1),
      h2: scaledHeading(defaults.h2),
      h3: scaledHeading(defaults.h3),
      h4: scaledHeading(defaults.h4),
      h5: scaledHeading(defaults.h5),
      h6: scaledHeading(defaults.h6),
    );
  }

  /// 编辑器右键/文字选择菜单：复用应用统一右键菜单样式（与章节树一致），
  /// 构建逻辑见 context_menu.dart 的 appEditorContextMenuBuilder。
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
            showToast(ctx, '自动保存失败，请检查磁盘空间；正文仍在内存中，请勿关闭应用。');
          });
        }
        return Tooltip(
          message: '输入停顿 2 秒自动保存；每 30 秒兜底落盘',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ]),
        );
      },
    );
  }

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
      _ListStyleButton(
        controller: state.editorController,
        ordered: true,
      ),
      _ListStyleButton(
        controller: state.editorController,
        ordered: false,
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
          icon: const Icon(Icons.auto_fix_high, size: 20),
          tooltip: '一键排版',
          onPressed: () => _runFormatter(context, state),
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.camera_alt_outlined, size: 20),
          tooltip: '手动快照',
          onPressed: () async {
            await state.durability.manualSnapshot(state.currentChapter!);
            if (context.mounted) {
              showToast(context, '已创建手动快照');
            }
          },
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.file_download_outlined, size: 20),
          tooltip: '导入 TXT / docx',
          onPressed: () => _import(context, state),
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.file_upload_outlined, size: 20),
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
    final std = context.watch<SettingsController>().countStandard;
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('本章 ${TextStats.count(plain, std)} 字',
                  style: TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(width: 16),
              Text('全书 ${state.bookCharTotal} 字',
                  style: TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(width: 16),
              Text('本次会话 +$sessionChars 字',
                  style: TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('字数统计口径：${std.label}',
                style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    var collapseBlank = true;
    var normalizePunct = true;
    var indent = true;
    var joinBlank = true;
    String preview() => TextFormatter.format(before,
        collapseBlank: collapseBlank,
        normalizePunct: normalizePunct,
        indent: indent,
        joinBlank: joinBlank);
    final leftCtrl = ScrollController();
    final rightCtrl = ScrollController();
    var syncing = false;
    void syncScroll(ScrollController src, ScrollController dst) {
      if (syncing || !src.hasClients || !dst.hasClients) return;
      final srcMax = src.position.maxScrollExtent;
      final dstMax = dst.position.maxScrollExtent;
      if (srcMax <= 0) return;
      syncing = true;
      dst.jumpTo((src.offset / srcMax * dstMax).clamp(0.0, dstMax));
      syncing = false;
    }

    leftCtrl.addListener(() => syncScroll(leftCtrl, rightCtrl));
    rightCtrl.addListener(() => syncScroll(rightCtrl, leftCtrl));
    final apply = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final options = [
            ('清理空行与空格', collapseBlank, (v) => collapseBlank = v),
            ('统一中文标点', normalizePunct, (v) => normalizePunct = v),
            ('段首缩进', indent, (v) => indent = v),
            ('段间空行', joinBlank, (v) => joinBlank = v),
          ];
          return DraggableDialog(
            child: Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 780),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(Icons.auto_fix_high,
                              size: 24, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('一键排版预览',
                                  style: textTheme.titleLarge
                                      ?.copyWith(fontSize: 24)),
                              const SizedBox(height: 2),
                              Text(
                                '排版作用于纯文本，应用后富文本格式将被重置；如需撤销请前往「历史快照」。',
                                style: textTheme.bodySmall?.copyWith(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(ctx, false),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, value, onChanged) in options)
                            FilterChip(
                              label: Text(label),
                              selected: value,
                              onSelected: (v) =>
                                  setDialogState(() => onChanged(v)),
                              showCheckmark: true,
                              labelStyle: TextStyle(
                                fontSize: 13,
                                color: value
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              checkmarkColor: scheme.primary,
                              side: BorderSide(
                                color: value
                                    ? scheme.primary.withValues(alpha: 0.4)
                                    : scheme.outlineVariant,
                              ),
                              backgroundColor: Colors.transparent,
                              selectedColor:
                                  scheme.primary.withValues(alpha: 0.08),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: Row(children: [
                          Expanded(
                              child: _formatPane(
                                  ctx, '排版前', before, Icons.article_outlined,
                                  controller: leftCtrl)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: scheme.primary,
                              child: Icon(Icons.arrow_forward,
                                  size: 16, color: scheme.onPrimary),
                            ),
                          ),
                          Expanded(
                              child: _formatPane(ctx, '排版后', preview(),
                                  Icons.auto_awesome,
                                  highlight: true, controller: rightCtrl)),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('应用排版'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (apply != true) {
      leftCtrl.dispose();
      rightCtrl.dispose();
      return;
    }
    leftCtrl.dispose();
    rightCtrl.dispose();
    await state.durability.manualSnapshot(chapter);
    state.replaceDocument(RichTextCodec.documentFromContent(preview()));
    await state.autosave.flush();
    if (context.mounted) {
      showToast(context, '排版已应用；如需撤销请前往「历史快照」回滚');
    }
  }

  Widget _formatPane(
    BuildContext context,
    String label,
    String text,
    IconData icon, {
    bool highlight = false,
    ScrollController? controller,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainerHighest.withAlpha(highlight ? 140 : 80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon,
                size: 17,
                color: highlight ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: highlight ? scheme.primary : null,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              child: SelectableText(text,
                  style: const TextStyle(fontSize: 15, height: 1.8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, AppState state) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: SimpleDialog(
          title: const Text('导入'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'txt'), child: const Text('批量导入 TXT（按“第X章”自动切分）')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'docx'), child: const Text('导入 docx（单文件 = 单章节）')),
          ],
        ),
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
        showToast(context, '已导入 ${parts.length} 个章节');
      }
    } else {
      final raw = await FileIO.pickReadText(ext: ['docx']);
      if (raw == null) return;
      if (context.mounted) {
        showToast(
            context, 'docx 导入请在导出对话框中使用 TXT 版本；MVP 暂不解析二进制 docx');
      }
    }
  }

  Future<void> _export(BuildContext context, AppState state) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: SimpleDialog(
          title: const Text('导出'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'chapter'), child: const Text('导出本章 TXT')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'book_txt'), child: const Text('导出全书 TXT')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'book_docx'), child: const Text('导出全书 Word (.docx)')),
          ],
        ),
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
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: const Text('是否包含章节名？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('不含')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('包含')),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String? path) {
    if (!context.mounted) return;
    showToast(context, path == null ? '已取消导出' : '导出成功：$path');
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

/// 列表按钮：应用列表时自动清除段首缩进，取消时逐一还原。
class _ListStyleButton extends StatefulWidget {
  const _ListStyleButton({
    required this.controller,
    required this.ordered,
  });

  final QuillController controller;
  final bool ordered;

  @override
  State<_ListStyleButton> createState() => _ListStyleButtonState();
}

class _ListStyleButtonState extends State<_ListStyleButton> {
  /// 按选区段落顺序存储被移除的段首前缀，用于取消列表时还原。
  List<String> _prefixes = [];
  bool _isSelected = false;

  Attribute get _attr => widget.ordered ? Attribute.ol : Attribute.ul;

  @override
  void initState() {
    super.initState();
    _syncSelected();
    widget.controller.addListener(_syncSelected);
  }

  @override
  void didUpdateWidget(covariant _ListStyleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSelected);
      widget.controller.addListener(_syncSelected);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSelected);
    super.dispose();
  }

  void _syncSelected() {
    final attrs = widget.controller.getSelectionStyle().attributes;
    final listAttr = attrs[Attribute.list.key];
    final selected = listAttr != null && listAttr.value == _attr.value;
    if (selected != _isSelected) {
      setState(() => _isSelected = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final (icon, tip) = widget.ordered
        ? (Icons.format_list_numbered, '有序列表')
        : (Icons.format_list_bulleted, '无序列表');

    return QuillToolbarIconButton(
      tooltip: tip,
      iconTheme: QuillIconTheme(
        iconButtonUnselectedData: IconButtonData(
          color: onSurface,
          padding: const EdgeInsets.all(5),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        ),
      ),
      isSelected: _isSelected,
      onPressed: _toggle,
      icon: Icon(icon, size: 20),
    );
  }

  void _toggle() {
    final controller = widget.controller;
    final sel = controller.selection;
    if (!sel.isValid) return;

    if (_isSelected) {
      // 取消列表 → 先移除列表属性，再还原段首缩进
      controller.formatSelection(Attribute.clone(_attr, null));
      _restorePrefixes(sel);
    } else {
      // 应用列表 → 先清除段首缩进，再应用列表属性
      _prefixes.clear();
      _stripPrefixes(sel);
      controller.formatSelection(_attr);
    }
  }

  /// 清除选区内各段落的段首缩进，结果存入 [_prefixes]（文档顺序）。
  void _stripPrefixes(TextSelection sel) {
    final text = widget.controller.document.toPlainText();
    final ranges = <(int start, int end)>[];
    var pStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    while (pStart < sel.end) {
      final pEnd = text.indexOf('\n', pStart);
      if (pEnd < 0 || pEnd > sel.end) {
        ranges.add((pStart, sel.end));
        break;
      }
      ranges.add((pStart, pEnd));
      pStart = pEnd + 1;
    }
    if (ranges.isEmpty) return;

    // 逆序处理：后替换不影响前面的偏移
    for (final (start, end) in ranges.reversed) {
      var i = start;
      while (i < end && (text[i] == '\u3000' || text[i] == ' ')) {
        i++;
      }
      final prefix = text.substring(start, i);
      _prefixes.add(prefix);
      if (prefix.isNotEmpty) {
        widget.controller.replaceText(
          start,
          prefix.length,
          '',
          TextSelection.collapsed(offset: widget.controller.selection.start),
        );
      }
    }
    _prefixes = _prefixes.reversed.toList();
  }

  /// 将 [_prefixes] 逐一插回选区段落起始位置。
  void _restorePrefixes(TextSelection sel) {
    if (_prefixes.isEmpty) return;

    final text = widget.controller.document.toPlainText();
    final starts = <int>[];
    var pStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    while (pStart < sel.end && starts.length < _prefixes.length) {
      starts.add(pStart);
      final pEnd = text.indexOf('\n', pStart);
      if (pEnd < 0 || pEnd > sel.end) break;
      pStart = pEnd + 1;
    }

    // 逆序插入
    for (var i = starts.length - 1; i >= 0; i--) {
      final prefix = _prefixes[i];
      if (prefix.isNotEmpty) {
        widget.controller.replaceText(
          starts[i],
          0,
          prefix,
          TextSelection.collapsed(offset: widget.controller.selection.start),
        );
      }
    }
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

/// 文字高亮按钮（参考 Word/WPS 交互，无模态弹窗）。
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
