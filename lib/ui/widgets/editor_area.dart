
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/docx_exporter.dart';
import '../../core/utils/docx_importer.dart';
import '../../core/utils/foreshadow_delta.dart';
import '../../core/utils/pair_symbols.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_formatter.dart';
import '../../core/utils/text_stats.dart';
import '../../data/models.dart';
import '../../services/autosave_service.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';

import '../common/character_marks.dart';
import '../common/context_menu.dart';
import '../common/dialogs.dart';
import '../common/file_io.dart';
import '../common/foreshadow_dialogs.dart';
import 'busy_overlay.dart';
import 'character_tip.dart';
import 'foreshadow_tip.dart';
import 'highlight_swatches.dart';
import 'reading_styles.dart';
import 'search_replace_bar.dart';
import 'toast.dart';
import 'write_stats_bubble.dart';

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

  /// 打字机模式（光标固定打字）：需要 RenderEditor 换算光标在正文中的
  /// 垂直位置，因此把 GlobalKey 交给 QuillEditorConfig.editorKey。
  final GlobalKey<EditorState> _editorKey = GlobalKey<EditorState>();

  /// 内容变化订阅。document.changes 只反映内容变化，不含纯选区变化，
  /// 正好对应「仅输入与换行时居中」。
  StreamSubscription<DocChange>? _docSubscription;
  Document? _boundDoc;

  /// 每次 build 同步的开关值，供帧末的居中回调读取。
  bool _typewriterMode = false;

  /// 对话高亮规范色（null = 关闭），每次 build 从设置同步。
  Color? _dialogueColor;

  /// 最近一次右键按下的全局坐标与时间：编辑器右键菜单跟随鼠标位置
  /// 而非选区位置（选区可能在远离点击处）。
  Offset? _secondaryTapPosition;
  DateTime? _secondaryTapAt;

  /// 搜索栏重挂载计数：全局搜索跳转等场景需要重置栏内状态并重新定位。
  int _searchNonce = 0;

  /// 角色名高亮词典：name/alias → 角色；按长度降序正则实现最长匹配。
  Map<String, Character> _nameToChar = const {};
  RegExp? _nameRegExp;

  /// 伏笔标注词典：片段 id → (伏笔, 片段)，渲染时按节点 fsid 属性查表。
  Map<String, (Foreshadow, ForeshadowSegment)> _fsDict = const {};

  /// 缓存 AppState：dispose 期间禁止通过 context 查找祖先节点。
  late final AppState _appState;

  /// 目标达成播报订阅。
  StreamSubscription<String>? _goalToastSub;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _goalToastSub = _appState.goalToasts.listen((msg) {
      if (mounted) showToast(context, msg);
    });
    _refreshCharacterDict();
    _appState.characterDictVersion.addListener(_refreshCharacterDict);
    _refreshForeshadowDict();
    _appState.foreshadowVersion.addListener(_refreshForeshadowDict);
    _appState.segmentJumpNonce.addListener(_onSegmentJump);
    _appState.editorController.addListener(_syncDocSubscription);
    _syncDocSubscription();
    _scrollController.typewriterTarget = _typewriterCenterOffset;
  }

  /// 章节切换会替换 QuillController.document，需跟随重新订阅内容变化流。
  void _syncDocSubscription() {
    final doc = _appState.editorController.document;
    if (identical(doc, _boundDoc)) return;
    _docSubscription?.cancel();
    _boundDoc = doc;
    _docSubscription = doc.changes.listen((_) => _onContentChanged());
  }

  /// 打字机模式：内容变化后于本帧末把光标行拉回视口中线。
  /// 放在帧末是为了晚于 flutter_quill 自身的 _showCaretOnScreen，
  /// 由随后的 jumpTo 取消它的动画滚动。
  void _onContentChanged() {
    if (!_typewriterMode) return;
    _scrollController.typewriterPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.typewriterPending = false;
      if (!mounted) return;
      _centerCaretOnScreen();
    });
  }

  void _centerCaretOnScreen() {
    final target = _typewriterCenterOffset();
    if (target == null) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  /// 光标行垂直中心对应的滚动偏移；非折叠选区或坐标不可用时返回 null。
  double? _typewriterCenterOffset() {
    if (!_typewriterMode || !_scrollController.hasClients) return null;
    final render = _editorKey.currentState?.renderEditor;
    if (render == null) return null;
    final controller = _appState.editorController;
    final sel = controller.selection;
    // 拖选/整段选中时不干预视口。
    if (!sel.isValid || !sel.isCollapsed) return null;
    final offset = sel.extentOffset;
    if (offset < 0 || offset > controller.document.length) return null;
    try {
      final rect = render.getLocalRectForCaret(
        TextPosition(offset: offset, affinity: sel.affinity),
      );
      return rect.center.dy - _scrollController.position.viewportDimension / 2;
    } catch (_) {
      // 布局未就绪等边界情况：跳过本次居中。
      return null;
    }
  }

  /// 面板"跳转正文"：聚焦编辑器触发滚动到选区。
  void _onSegmentJump() {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  Future<void> _onCreateForeshadowFromSelection() async {
    final state = context.read<AppState>();
    if (state.selectionHasFsidMark()) {
      showToast(context, '选区内已存在伏笔标注，请先取消原标注');
      return;
    }
    final result = await showCreateForeshadowDialog(context,
        excerpt: state.selectedPlainText());
    if (result == null || !mounted) return;
    if (state.selectionHasFsidMark()) {
      showToast(context, '选区内已存在伏笔标注，请先取消原标注');
      return;
    }
    await state.createForeshadowFromSelection(result.$1, result.$2, result.$3);
    showToast(context, '伏笔创建成功，选区标注完成');
  }

  Future<void> _onLinkForeshadow() async {
    final state = context.read<AppState>();
    if (state.selectionHasFsidMark()) {
      showToast(context, '选区内已存在伏笔标注，请先取消原标注');
      return;
    }
    final result = await showLinkForeshadowDialog(context, widget.book.id,
        excerpt: state.selectedPlainText());
    if (result == null || !mounted) return;
    if (state.selectionHasFsidMark()) {
      showToast(context, '选区内已存在伏笔标注，请先取消原标注');
      return;
    }
    await state.linkSegmentToForeshadow(result.$1, result.$2);
    showToast(context, '关联成功：「${result.$1.name}」');
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

  Future<void> _refreshForeshadowDict() async {
    final state = context.read<AppState>();
    final fss = await state.foreshadows.listByBook(widget.book.id);
    final segs = await state.fsSegments.listByBook(widget.book.id);
    if (!mounted) return;
    final fsById = {for (final f in fss) f.id: f};
    final dict = <String, (Foreshadow, ForeshadowSegment)>{};
    for (final s in segs) {
      final f = fsById[s.fsId];
      if (f != null) dict[s.id] = (f, s);
    }
    setState(() => _fsDict = dict);
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
    _appState.foreshadowVersion.removeListener(_refreshForeshadowDict);
    _appState.segmentJumpNonce.removeListener(_onSegmentJump);
    _appState.editorController.removeListener(_syncDocSubscription);
    _docSubscription?.cancel();
    _goalToastSub?.cancel();
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

  /// 对话高亮：台词引号内的文字套用高亮底色。
  /// 优先级低于手工高亮（节点已带 background 属性时不叠加）与搜索命中（搜索
  /// 命中在 [_richSpanCore] 内以 Paint 覆盖底色）；引号本身不变色。
  InlineSpan _richSpan(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    final dialogue = _dialogueColor;
    final ranges = dialogue == null || style?.backgroundColor != null
        ? const <(int, int)>[]
        : findDialogueRanges(text);
    if (ranges.isEmpty) {
      return _richSpanCore(context, node, nodeOffset, text, style, recognizer);
    }
    // 传入当前主题显示色；_searchHighlightSpanBuilder 的映射对其为无操作。
    final dialogueStyle = (style ?? const TextStyle()).copyWith(
        backgroundColor: themeSwatchOf(dialogue!, Theme.brightnessOf(context)));
    final children = <InlineSpan>[];
    var pos = 0;
    for (final (start, end) in ranges) {
      if (start > pos) {
        children.add(_richSpanCore(context, node, nodeOffset + pos,
            text.substring(pos, start), style, recognizer));
      }
      children.add(_richSpanCore(context, node, nodeOffset + start,
          text.substring(start, end), dialogueStyle, recognizer));
      pos = end;
    }
    if (pos < text.length) {
      children.add(_richSpanCore(context, node, nodeOffset + pos,
          text.substring(pos), style, recognizer));
    }
    return TextSpan(children: children, style: style);
  }

  InlineSpan _richSpanCore(
    BuildContext context,
    Node node,
    int nodeOffset,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    // 伏笔标注优先于角色名匹配：节点带 fsid 属性且词典可查时整体标注。
    final fsAttr = node.style.attributes[kFsidKey];
    if (fsAttr?.value is String) {
      final entry = _fsDict[fsAttr!.value as String];
      if (entry != null) {
        return _foreshadowSpan(
            context, entry.$1, entry.$2, text, style, recognizer);
      }
    }

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
        final color = characterMarkColor(char);
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

  /// 伏笔标注渲染：状态色文字 + 波浪下划线，悬浮展示信息卡。
  /// 不使用行内 WidgetSpan 图标——占位符会占据一个文字位置，
  /// 导致该行后续字符的光标/选区偏移错位。
  InlineSpan _foreshadowSpan(
    BuildContext context,
    Foreshadow foreshadow,
    ForeshadowSegment segment,
    String text,
    TextStyle? style,
    GestureRecognizer? recognizer,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final color = foreshadowMarkColor(foreshadow.status, scheme.brightness);
    return TextSpan(
      text: text,
      style: (style ?? const TextStyle()).copyWith(
        color: color,
        decoration: TextDecoration.underline,
        decorationColor: color,
        decorationStyle: TextDecorationStyle.wavy,
        decorationThickness: 2,
      ),
      onEnter: (e) => scheduleForeshadowTip(
          context, e.position, foreshadow, segment, () {
        context.read<AppState>().requestOpenForeshadow(foreshadow.id);
      }),
      onExit: (_) => cancelForeshadowTip(),
    );
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
      final mapped = themeSwatchOf(bg, Theme.brightnessOf(context));
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
    // 缓存开关值：帧末居中回调与滚动控制器无法访问 build 局部量。
    _typewriterMode = settings.typewriterMode;
    _dialogueColor = settings.dialogueHighlightColor;
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

    final savingHint = _saveIndicator(context);

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
        if (chapter.charCount > AppConstants.longChapterThreshold)
          MaterialBanner(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: const Text('本章超过 5 万字，建议拆分为多章以保证编辑流畅度。'),
            actions: [TextButton(onPressed: () {}, child: const Text('知道了'))],
          ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              // 打字机模式需按编辑器视口高度留半屏底部空白，故在此测量高度。
              child: LayoutBuilder(
                builder: (context, constraints) => Listener(
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
                      editorKey: _editorKey,
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 8 + (_typewriterMode ? constraints.maxHeight / 2 : 0),
                      ),
                      textSpanBuilder: _textSpanBuilder,
                      autoPairSymbols: fullWidthPairSymbols,
                      customStyles: _editorStyles(context, settings),
                      contextMenuBuilder: (context, rawState) {
                        var extras = <AppMenuAction>[];
                        // 「一键分章」：光标后有实际内容才显示；有选区时以选区起点拆分。
                        final sel = rawState.textEditingValue.selection;
                        final splitOffset =
                            sel.isValid && !sel.isCollapsed ? sel.start : sel.baseOffset;
                        if (!rawState.widget.config.readOnly &&
                            splitOffset >= 0 &&
                            splitOffset < rawState.controller.document.length &&
                            RichTextCodec.hasContentAfter(
                                rawState.controller.document.toDelta(), splitOffset)) {
                          extras.add(AppMenuAction(
                            '一键分章',
                            icon: Icons.call_split,
                            onTap: () => state.splitChapterAt(splitOffset),
                          ));
                        }
                        // 伏笔标注：非空选区时提供新建 / 关联入口。
                        if (!rawState.widget.config.readOnly &&
                            sel.isValid &&
                            !sel.isCollapsed) {
                          extras.add(AppMenuAction(
                            '新建伏笔',
                            icon: Icons.flag,
                            onTap: _onCreateForeshadowFromSelection,
                          ));
                          extras.add(AppMenuAction(
                            '关联伏笔',
                            icon: Icons.link,
                            onTap: _onLinkForeshadow,
                          ));
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
            ),
            // 正文右下角浮动按钮组：与正文同层，仅覆盖自身命中区域。
            Positioned(
              right: 24,
              bottom: 16,
              child: _ScrollJumpButtons(controller: _scrollController),
            ),
          ]),
        ),
        _statusBar(context, chapter),
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
    return buildReadingStyles(
      context,
      fontSize: settings.fontSize,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      fontFamily: settings.editorFontFamily,
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
              showToast(context, '手动快照创建成功');
            }
          },
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.file_download_outlined, size: 20),
          tooltip: '导入 TXT / docx（整份作为一个章节）',
          onPressed: () => _import(context, state),
        ),
      ),
      QuillToolbarCustomButton(
        controller: state.editorController,
        baseOptions: base,
        options: QuillToolbarCustomButtonOptions(
          icon: const Icon(Icons.file_upload_outlined, size: 20),
          tooltip: '导出本章 TXT / Word',
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

  Widget _statusBar(BuildContext context, Chapter chapter) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsController>();
    final std = settings.countStandard;
    final scheme = Theme.of(context).colorScheme;
    final chGoal = state.resolvedChapterGoal;
    final bookGoal = state.currentBook?.goal ?? 0;
    final dailyGoal = settings.dailyGoal;

    Widget stat(String text, bool reached) => Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: reached ? scheme.primary : null,
              fontWeight: reached ? FontWeight.w600 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        );

    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                stat(
                  chGoal > 0
                      ? '本章 ${chapter.charCount}/$chGoal'
                      : '本章 ${chapter.charCount} 字',
                  chGoal > 0 && chapter.charCount >= chGoal,
                ),
                const SizedBox(width: 16),
                stat(
                  bookGoal > 0
                      ? '全书 ${state.bookCharTotal}/$bookGoal'
                      : '全书 ${state.bookCharTotal} 字',
                  bookGoal > 0 && state.bookCharTotal >= bookGoal,
                ),
                const SizedBox(width: 16),
                stat(
                  '今日 ${state.todayChars}/$dailyGoal',
                  state.todayChars >= dailyGoal,
                ),
              ],
            ),
          ),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('字数统计口径：${std.label}',
                      style: TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 10),
                const WriteStatsEntry(),
              ],
            ),
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
                  padding: const EdgeInsets.all(24),
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
                                  style: textTheme.titleLarge?.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
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
      showToast(context, '排版应用成功；如需撤销请前往「历史快照」回滚');
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

  /// 导入外部文件为单个章节：扩展名由所选文件推断，不再让用户选格式。
  Future<void> _import(BuildContext context, AppState state) async {
    final picked = await FileIO.pickImportNamed();
    if (picked == null || !context.mounted) return;
    final (name, ext, bytes) = picked;

    final result = await runWithBusy(
        '正在解析《$name》', (_) => _readImportInBackground(ext, bytes));
    if (!context.mounted) return;
    if (result.error != null) {
      showToast(context, result.error!);
      return;
    }

    final volumeId = state.volumeTree.isNotEmpty
        ? state.volumeTree.first.id
        : (await state.addVolume('导入卷')).id;
    final ch = await state.addChapter(volumeId,
        title: name,
        content: RichTextCodec.deltaJsonFromPlainText(result.raw!));
    await state.openChapter(ch);
    if (context.mounted) showToast(context, '导入成功');
  }

  /// 导出当前章节：TXT 与 Word 均以章节名为首行。
  Future<void> _export(BuildContext context, AppState state) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final choice = await choiceDialog(
      context,
      icon: Icons.file_upload_outlined,
      title: '导出本章',
      choices: const [
        ChoiceSpec(
          value: 'txt',
          icon: Icons.description_outlined,
          title: 'TXT',
          subtitle: '纯文本',
        ),
        ChoiceSpec(
          value: 'docx',
          icon: Icons.article_outlined,
          title: 'Word',
          subtitle: '.docx 文档',
        ),
      ],
    );
    if (choice == null || !context.mounted) return;

    final body = RichTextCodec.plainTextFromDeltaJson(chapter.content);
    final path = choice == 'txt'
        ? await FileIO.saveText(
            fileName: '${chapter.title}.txt',
            content: '${chapter.title}\n\n$body')
        : await FileIO.saveBytes(
            fileName: '${chapter.title}.docx',
            bytes: DocxExporter.build(
              bookTitle: chapter.title,
              penName: state.currentBook?.penName ?? '',
              chapters: [MapEntry(chapter.title, body)],
              // 单章文件不写书名与作者，章节名即文件标题。
              includeBookHeader: false,
            ),
          );
    if (!context.mounted) return;
    showToast(context, path == null ? '已取消导出' : '导出成功：$path');
  }
}

/// 编辑区导入的解析入口（isolate 顶层函数，避免闭包捕获 [AppState] 等不可
/// 发送对象）。
Future<({String? raw, String? error})> _readImportInBackground(
        String ext, List<int> bytes) =>
    Isolate.run(() => _readImport(ext, bytes));

/// 解析导入文件为纯文本：docx 解压抽文本 / txt 解码。与书架导入不同，编辑区
/// 导入不做卷章切分——整份文件作为一个章节，故这里只返回文本。
({String? raw, String? error}) _readImport(String ext, List<int> bytes) {
  final String raw;
  if (ext == 'docx') {
    try {
      raw = DocxImporter.extractText(bytes);
    } on FormatException {
      return (raw: null, error: '导入失败：无法解析该 docx 文件');
    }
  } else {
    // 未知扩展名按 txt 兜底；非 UTF-8 文本会解出替换字符，但至少能导入。
    raw = utf8.decode(bytes, allowMalformed: true);
  }
  if (raw.trim().isEmpty) return (raw: null, error: '导入失败：文件内容为空');
  return (raw: raw, error: null);
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
///
/// 另外把「滚动区尺寸变化」暴露成 [metricsTick]：这类变化不改变偏移，也就
/// 不经过控制器通知，只有位置层在帧末抛 ScrollMetricsNotification。
/// 右下角的置顶/置底按钮靠这个信号才能及时重算显隐（典型场景：在短章顶端
/// 一直打字把正文撑到超出一屏）。
class _EditorScrollController extends ScrollController {
  final ValueNotifier<int> metricsTick = ValueNotifier<int>(0);

  bool _suppressAnimateTo = false;

  set suppressAnimateTo(bool value) => _suppressAnimateTo = value;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _EditorScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      metricsTick: metricsTick,
    );
  }

  @override
  void dispose() {
    metricsTick.dispose();
    super.dispose();
  }

  /// 打字机模式：内容变化到帧末之间置位。flutter_quill 只在光标离开视口时
  /// 才请求滚动，而打字机模式要求每行都停在正中，故期间把它的动画请求改为
  /// 瞬时对齐到光标中线目标（否则折行时光标会掉出中线）。
  bool typewriterPending = false;

  /// 计算光标居中偏移的回调，由 State 注入。
  double? Function()? typewriterTarget;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    if (_suppressAnimateTo) return Future.value();
    if (typewriterPending && hasClients) {
      final target = typewriterTarget?.call();
      if (target != null) {
        jumpTo(
          target
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
        return Future.value();
      }
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }
}

/// 仅用于把尺寸变化转成 [metricsTick] 自增，其余行为与默认位置一致。
class _EditorScrollPosition extends ScrollPositionWithSingleContext {
  _EditorScrollPosition({
    required super.physics,
    required super.context,
    required this.metricsTick,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
  });

  final ValueNotifier<int> metricsTick;

  @override
  void didUpdateScrollMetrics() {
    metricsTick.value++;
    super.didUpdateScrollMetrics();
  }
}

/// 判「已在端头」的容差，只用于抵消浮点误差：滚 1px 就算离开了端头。
const double _endTolerance = 0.5;

/// 正文右下角的置顶 / 置底浮动按钮组（纵向叠放、锚定右下角）。
///
/// 显隐由当前滚动量决定：无法滚动时整组不出现；停在顶端只留「回到底部」，
/// 停在底端只留「回到顶部」，中间区域两个都在。因锚点在右下角，收起其中一个
/// 时另一个原地不动。
class _ScrollJumpButtons extends StatelessWidget {
  const _ScrollJumpButtons({required this.controller});

  final _EditorScrollController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // 滚动偏移变化由控制器通知；内容撑长、视口缩放不改变偏移，
      // 只会触发 metricsTick，两条信号都要接。
      animation: Listenable.merge([controller, controller.metricsTick]),
      builder: (context, _) {
        // 切章重建正文的窗口期内位置可能尚未挂载，此时不画。
        if (!controller.hasClients) return const SizedBox.shrink();
        final position = controller.position;
        final max = position.maxScrollExtent;
        if (max <= 0) return const SizedBox.shrink();
        final canUp = position.pixels > position.minScrollExtent + _endTolerance;
        final canDown = position.pixels < max - _endTolerance;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (canUp)
              _JumpButton(
                icon: Icons.vertical_align_top,
                tooltip: '回到顶部',
                onTap: () => _jumpToEdge(controller, toEnd: false),
              ),
            if (canUp && canDown) const SizedBox(height: 8),
            if (canDown)
              _JumpButton(
                icon: Icons.vertical_align_bottom,
                tooltip: '回到底部',
                onTap: () => _jumpToEdge(controller, toEnd: true),
              ),
          ],
        );
      },
    );
  }
}

/// 瞬时跳到当前滚动范围的端头；控制器未挂载（切章窗口期）时忽略。
void _jumpToEdge(ScrollController controller, {required bool toEnd}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  controller.jumpTo(toEnd ? position.maxScrollExtent : position.minScrollExtent);
}

/// 圆形浮动按钮：浮在正文之上，必须有实底 + 描边才压得住下方文字，
/// 故与码字气泡同套视觉（surface 底 + outlineVariant 描边 + 轻投影）。
///
/// 用 GestureDetector 而非 InkWell：Material 组件在桌面端可能抢走编辑器焦点，
/// 点完按钮就无法直接继续打字。
class _JumpButton extends StatefulWidget {
  const _JumpButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_JumpButton> createState() => _JumpButtonState();
}

class _JumpButtonState extends State<_JumpButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // hover 底色若直接用半透明主色，下方正文会透出来，
              // 故先与面板底色混合成不透明色。
              color: _hovering
                  ? Color.alphaBlend(
                      scheme.primaryContainer.withValues(alpha: 0.45),
                      scheme.surface,
                    )
                  : scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovering ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
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
  Color _current = highlightLightSwatches.first;

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
            : highlightHex(canonicalSwatchOf(color)),
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
        : themeSwatchOf(_selectionBg!, Theme.of(context).brightness);

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
                for (final swatch in highlightPaletteFor(context))
                  HighlightSwatchCell(
                    color: swatch,
                    selected: activeDisplay == swatch,
                    onTap: () {
                      setState(() => _current = canonicalSwatchOf(swatch));
                      _apply(swatch);
                      _menuController.close();
                    },
                  ),
                HighlightClearCell(
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
                      color: themeSwatchOf(
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
