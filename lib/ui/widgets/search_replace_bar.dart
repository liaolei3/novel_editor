import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'toast.dart';

/// 编辑区内嵌搜索替换栏：匹配偏移随正文变化自动刷新
/// （订阅 document.changes，仅重算不挪光标），查询词/选项变化时才主动定位。
/// 通过 [onSearchChanged] 通知父组件更新全量高亮。
class SearchReplaceBar extends StatefulWidget {
  const SearchReplaceBar({
    super.key,
    required this.controller,
    required this.editorFocusNode,
    this.initialText = '',
    this.showReplaceInitially = false,
    required this.onClose,
    this.onSearchChanged,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;
  final String initialText;
  final bool showReplaceInitially;
  final VoidCallback onClose;

  /// 搜索结变化时回调，用于通知编辑器更新全量高亮。
  final void Function(List<int> offsets, int currentIndex, String query)?
      onSearchChanged;

  @override
  State<SearchReplaceBar> createState() => _SearchReplaceBarState();
}

class _SearchReplaceBarState extends State<SearchReplaceBar> {
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _replaceFocus = FocusNode();

  List<int> _offsets = const [];
  int _index = 0;
  bool _caseSensitive = false;
  late bool _replaceVisible = widget.showReplaceInitially;

  Timer? _debounce;
  StreamSubscription<void>? _docSub;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialText;
    _docSub = widget.controller.document.changes
        .listen((_) => _scheduleSearch(relocate: false));
    _searchCtrl.addListener(_scheduleSearchRelocate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      if (_searchCtrl.text.isNotEmpty) _recompute(relocate: true);
    });
  }

  @override
  void didUpdateWidget(covariant SearchReplaceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showReplaceInitially && !_replaceVisible) {
      _replaceVisible = true;
    }
    if (oldWidget.controller != widget.controller) {
      _docSub?.cancel();
      _docSub = widget.controller.document.changes
          .listen((_) => _scheduleSearch(relocate: false));
      _recompute(relocate: true);
    }
  }

  @override
  void dispose() {
    _docSub?.cancel();
    _debounce?.cancel();
    _searchCtrl.removeListener(_scheduleSearchRelocate);
    _searchCtrl.dispose();
    _replaceCtrl.dispose();
    _searchFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  String get _query => _searchCtrl.text;

  void _scheduleSearchRelocate() => _scheduleSearch(relocate: true);

  void _scheduleSearch({required bool relocate}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _recompute(relocate: relocate);
    });
  }

  /// 重算匹配。[relocate] 为 true 时把选区定位到当前匹配（滚动跟随）；
  /// 正文变化触发的重算只刷新计数，不干扰正在输入的光标。
  void _recompute({required bool relocate}) {
    if (!mounted) return;
    final query = _query;
    if (query.isEmpty) {
      setState(() {
        _offsets = const [];
        _index = 0;
      });
      _notifySearchChanged();
      if (relocate) _clearHighlight();
      return;
    }
    final anchor = relocate
        ? (_offsets.isNotEmpty ? _offsets[_index] : 0)
        : widget.controller.selection.baseOffset;
    final matches = widget.controller.document
        .search(query, caseSensitive: _caseSensitive);
    var idx = 0;
    for (var i = 0; i < matches.length; i++) {
      if (matches[i] >= anchor) {
        idx = i;
        break;
      }
    }
    setState(() {
      _offsets = matches;
      _index = matches.isEmpty ? 0 : idx;
    });
    _notifySearchChanged();
    if (relocate && matches.isNotEmpty) _locate(_index);
  }

  void _locate(int i) {
    setState(() => _index = i);
    _notifySearchChanged();
    final off = _offsets[i];
    widget.controller.updateSelection(
      TextSelection(baseOffset: off, extentOffset: off + _query.length),
      ChangeSource.local,
    );
  }

  void _clearHighlight() {
    final base =
        widget.controller.selection.baseOffset.clamp(0, widget.controller.plainTextEditingValue.text.length);
    widget.controller.updateSelection(
      TextSelection.collapsed(offset: base),
      ChangeSource.local,
    );
  }

  void _moveNext() {
    if (_offsets.isEmpty) return;
    _locate(_index == _offsets.length - 1 ? 0 : _index + 1);
  }

  void _movePrev() {
    if (_offsets.isEmpty) return;
    _locate(_index == 0 ? _offsets.length - 1 : _index - 1);
  }

  void _replaceCurrent() {
    if (_offsets.isEmpty) return;
    final off = _offsets[_index];
    widget.controller.replaceText(
      off,
      _query.length,
      _replaceCtrl.text,
      TextSelection.collapsed(offset: off),
    );
    _recompute(relocate: true);
  }

  void _replaceAll() {
    if (_offsets.isEmpty) return;
    final count = _offsets.length;
    for (final off in _offsets.reversed) {
      widget.controller.replaceText(off, _query.length, _replaceCtrl.text, null);
    }
    _recompute(relocate: false);
    showToast(context, '替换成功，共 $count 处');
  }

  void _notifySearchChanged() {
    widget.onSearchChanged?.call(_offsets, _index, _query);
  }

  void _close() {
    widget.onSearchChanged?.call(const [], 0, '');
    widget.onClose();
    widget.editorFocusNode.requestFocus();
  }

  KeyEventResult _searchKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      HardwareKeyboard.instance.isShiftPressed ? _movePrev() : _moveNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _replaceKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      HardwareKeyboard.instance.isShiftPressed ? _replaceAll() : _replaceCurrent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _iconBtn({
    required String tooltip,
    required Widget icon,
    Widget? selectedIcon,
    bool isSelected = false,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      selectedIcon: selectedIcon,
      isSelected: isSelected,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
    );
  }

  OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide:
            color == Colors.transparent ? BorderSide.none : BorderSide(color: color),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(60),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            _iconBtn(
              tooltip: _replaceVisible ? '收起替换' : '展开替换',
              isSelected: _replaceVisible,
              icon: Icon(
                _replaceVisible
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _replaceVisible = !_replaceVisible),
            ),
            const SizedBox(width: 4),
            Expanded(child: _searchField(context)),
            _iconBtn(
              tooltip: '上一个 (Shift+Enter)',
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: _offsets.isEmpty ? null : _movePrev,
            ),
            _iconBtn(
              tooltip: '下一个 (Enter)',
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: _offsets.isEmpty ? null : _moveNext,
            ),
            _iconBtn(
              tooltip: '区分大小写',
              isSelected: _caseSensitive,
              icon: Text('Aa',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              selectedIcon: Text('Aa',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
              onPressed: () {
                setState(() => _caseSensitive = !_caseSensitive);
                _recompute(relocate: true);
              },
            ),
            _iconBtn(
              tooltip: '关闭 (Esc)',
              icon: const Icon(Icons.close, size: 20),
              onPressed: _close,
            ),
          ]),
        ),
        if (_replaceVisible)
          SizedBox(
            height: 44,
            child: Row(children: [
              const SizedBox(width: 44),
              Expanded(child: _replaceField(context)),
              SizedBox(
                width: 160,
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _offsets.isEmpty ? null : _replaceCurrent,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('替换', maxLines: 1),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _offsets.isEmpty ? null : _replaceAll,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text('全部替换', maxLines: 1),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _searchField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final counter = _query.isEmpty
        ? null
        : '${_offsets.isEmpty ? 0 : _index + 1}/${_offsets.length}';
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _searchKeys,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _moveNext(),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '查找',
          filled: true,
          fillColor: cs.surfaceContainerHighest.withAlpha(120),
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixText: counter,
          suffixStyle: TextStyle(fontSize: 12, color: cs.outline),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          enabledBorder: _fieldBorder(Colors.transparent),
          focusedBorder: _fieldBorder(cs.primary),
        ),
      ),
    );
  }

  Widget _replaceField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _replaceKeys,
      child: TextField(
        controller: _replaceCtrl,
        focusNode: _replaceFocus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _replaceCurrent(),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          hintText: '替换为',
          filled: true,
          fillColor: cs.surfaceContainerHighest.withAlpha(120),
          prefixIcon: const Icon(Icons.loop, size: 18),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          enabledBorder: _fieldBorder(Colors.transparent),
          focusedBorder: _fieldBorder(cs.primary),
        ),
      ),
    );
  }
}
