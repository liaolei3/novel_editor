import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../common/extensions/view_id_ext.dart';
import '../../delta/delta_diff.dart';
import '../../document/document.dart';
import '../editor.dart';
import 'raw_editor.dart';

mixin RawEditorStateTextInputClientMixin on EditorState
    implements TextInputClient {
  TextInputConnection? _textInputConnection;
  TextEditingValue? __lastKnownRemoteTextEditingValue;

  set _lastKnownRemoteTextEditingValue(TextEditingValue? value) {
    __lastKnownRemoteTextEditingValue = value;
    if (composingRange.value != value?.composing) {
      composingRange.value = value?.composing ?? TextRange.empty;
    }
  }

  TextEditingValue? get _lastKnownRemoteTextEditingValue =>
      __lastKnownRemoteTextEditingValue;

  /// The range of text that is currently being composed.
  final ValueNotifier<TextRange> composingRange = ValueNotifier<TextRange>(
    TextRange.empty,
  );

  /// Whether to create an input connection with the platform for text editing
  /// or not.
  ///
  /// Read-only input fields do not need a connection with the platform since
  /// there's no need for text editing capabilities (e.g. virtual keyboard).
  ///
  /// On the web, we always need a connection because we want some browser
  /// functionalities to continue to work on read-only input fields like:
  ///
  /// - Relevant context menu.
  /// - cmd/ctrl+c shortcut to copy.
  /// - cmd/ctrl+a to select all.
  /// - Changing the selection using a physical keyboard.
  bool get shouldCreateInputConnection => kIsWeb || !widget.config.readOnly;

  /// Returns `true` if there is open input connection.
  bool get hasConnection =>
      _textInputConnection != null && _textInputConnection!.attached;

  /// Opens or closes input connection based on the current state of
  /// [focusNode] and [value].
  void openOrCloseConnection() {
    if (widget.config.focusNode.hasFocus &&
        widget.config.focusNode.consumeKeyboardToken()) {
      openConnectionIfNeeded();
    } else if (!widget.config.focusNode.hasFocus) {
      closeConnectionIfNeeded();
    }
  }

  /// This setting is only honored on iOS devices.
  @visibleForTesting
  @internal
  Brightness createKeyboardAppearance() =>
      widget.config.keyboardAppearance ??
      CupertinoTheme.maybeBrightnessOf(context) ??
      Theme.of(context).brightness;

  void openConnectionIfNeeded() {
    if (!shouldCreateInputConnection) {
      return;
    }

    if (!hasConnection) {
      _lastKnownRemoteTextEditingValue = textEditingValue;
      _textInputConnection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          readOnly: widget.config.readOnly,
          inputAction: widget.config.textInputAction,
          enableSuggestions: !widget.config.readOnly,
          keyboardAppearance: createKeyboardAppearance(),
          textCapitalization: widget.config.textCapitalization,
          allowedMimeTypes: widget.config.contentInsertionConfiguration == null
              ? const <String>[]
              : widget.config.contentInsertionConfiguration!.allowedMimeTypes,
          viewId: context.getViewId(),
        ),
      );

      _updateSizeAndTransform();
      //update IME position for Windows
      _updateComposingRectIfNeeded();
      //update IME position for Macos
      _updateCaretRectIfNeeded();

      /// Trap selection extends off end of document
      if (_lastKnownRemoteTextEditingValue != null) {
        if (_lastKnownRemoteTextEditingValue!.selection.end >
            _lastKnownRemoteTextEditingValue!.text.length) {
          _lastKnownRemoteTextEditingValue = _lastKnownRemoteTextEditingValue!
              .copyWith(
                  selection: _lastKnownRemoteTextEditingValue!.selection
                      .copyWith(
                          extentOffset:
                              _lastKnownRemoteTextEditingValue!.text.length));
        }
      }
      _textInputConnection!.setEditingState(_lastKnownRemoteTextEditingValue!);
    }
    _textInputConnection!.show();
  }

  void _updateComposingRectIfNeeded() {
    final composingRange = _lastKnownRemoteTextEditingValue?.composing ??
        textEditingValue.composing;
    if (hasConnection) {
      assert(mounted);
      try {
        final selection = renderEditor.selection;
        final offset = composingRange.isValid
            ? composingRange.end
            : (selection.isValid ? selection.extentOffset : 0);
        var composingRect =
            renderEditor.getLocalRectForCaret(TextPosition(offset: offset));
        // Windows: 引擎用 rect 顶部作输入法窗口锚点，下移到行底部，
        // 使候选框显示在光标行下方，避免遮住正在输入的文字。
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          composingRect = Rect.fromLTRB(
            composingRect.left,
            composingRect.bottom,
            composingRect.right,
            composingRect.bottom,
          );
        }
        _textInputConnection!.setComposingRect(composingRect);
      } catch (error) {
        // 计算失败时不能让 postFrameCallback 循环中断，否则后续帧不再上报
        // 坐标，输入法候选框会永久停留在旧位置。
      }
      SchedulerBinding.instance
          .addPostFrameCallback((_) => _updateComposingRectIfNeeded());
    }
  }

  void _updateCaretRectIfNeeded() {
    if (hasConnection) {
      if (!dirty &&
          renderEditor.selection.isValid &&
          renderEditor.selection.isCollapsed) {
        final currentTextPosition =
            TextPosition(offset: renderEditor.selection.baseOffset);
        final caretRect =
            renderEditor.getLocalRectForCaret(currentTextPosition);
        _textInputConnection!.setCaretRect(caretRect);
      }
      SchedulerBinding.instance
          .addPostFrameCallback((_) => _updateCaretRectIfNeeded());
    }
  }

  /// Closes input connection if it's currently open. Otherwise does nothing.
  void closeConnectionIfNeeded() {
    if (!hasConnection) {
      return;
    }
    _textInputConnection!.close();
    _textInputConnection = null;
    _lastKnownRemoteTextEditingValue = null;
  }

  /// Updates remote value based on current state of [document] and
  /// [selection].
  ///
  /// This method may not actually send an update to native side if it thinks
  /// remote value is up to date or identical.
  void updateRemoteValueIfNeeded() {
    if (!hasConnection) {
      return;
    }

    final value = textEditingValue;

    // Since we don't keep track of the composing range in value provided
    // by the Controller we need to add it here manually before comparing
    // with the last known remote value.
    // It is important to prevent excessive remote updates as it can cause
    // race conditions.
    final composingRange = _lastKnownRemoteTextEditingValue!.composing;
    final actualValue = value.copyWith(
      // Ignore last known composing range if it exceeds current text length.
      composing: composingRange.end > value.text.length ? null : composingRange,
    );

    if (actualValue == _lastKnownRemoteTextEditingValue) {
      return;
    }

    _lastKnownRemoteTextEditingValue = actualValue;
    _textInputConnection!.setEditingState(
      // Set composing to (-1, -1), otherwise an exception will be thrown if
      // the values are different.
      actualValue.copyWith(composing: const TextRange(start: -1, end: -1)),
    );
  }

  // Start TextInputClient implementation
  @override
  TextEditingValue? get currentTextEditingValue =>
      _lastKnownRemoteTextEditingValue;

  // autofill is not needed
  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!shouldCreateInputConnection) {
      return;
    }

    if (_lastKnownRemoteTextEditingValue == value) {
      // There is no difference between this value and the last known value.
      return;
    }

    // 成对符号自动补全（见 QuillEditorConfig.autoPairSymbols）：
    // IME 组合期间改动文档会被输入法回滚，因此组合期间只记录、
    // 组合结束后再补全；无组合的直接输入立即补全。
    final pairs = widget.config.autoPairSymbols;
    final composingActive =
        value.composing.isValid && !value.composing.isCollapsed;
    final wasComposing = _autoPairComposing;
    _autoPairComposing = composingActive;
    final compositionEnded = wasComposing && !composingActive;

    // Check if only composing range changed.
    if (_lastKnownRemoteTextEditingValue!.text == value.text &&
        _lastKnownRemoteTextEditingValue!.selection == value.selection) {
      // This update only modifies composing range. Since we don't keep track
      // of composing range we just need to update last known value here.
      // This check fixes an issue on Android when it sends
      // composing updates separately from regular changes for text and
      // selection.
      _lastKnownRemoteTextEditingValue = value;
      if (pairs != null && compositionEnded) {
        _executeDeferredAutoPair(pairs);
      }
      return;
    }

    final effectiveLastKnownValue = _lastKnownRemoteTextEditingValue!;
    _lastKnownRemoteTextEditingValue = value;
    final oldText = effectiveLastKnownValue.text;
    final text = value.text;
    final cursorPosition = value.selection.extentOffset;
    final diff = getDiff(oldText, text, cursorPosition);
    if (diff.deleted.isEmpty && diff.inserted.isEmpty) {
      widget.controller.updateSelection(value.selection, ChangeSource.local);
      if (pairs != null && compositionEnded) {
        _executeDeferredAutoPair(pairs);
      }
      return;
    }

    if (pairs != null && diff.inserted.length == 1) {
      final inserted = diff.inserted;
      final closer = pairs[inserted];
      final isOpen = closer != null;
      final isClose = pairs.containsValue(inserted);

      if (composingActive) {
        // IME 对引号类按键做开/闭交替，此处闭符也可能触发包裹。
        if (isOpen || isClose) {
          _autoPairSymbol = inserted;
          _autoPairPos = diff.start;
          _autoPairDeleted = diff.deleted;
        } else {
          _autoPairSymbol = null;
        }
      } else if (!wasComposing) {
        if (diff.deleted.isEmpty && isOpen) {
          widget.controller.replaceText(
            diff.start,
            0,
            inserted + closer,
            TextSelection.collapsed(offset: diff.start + 1),
          );
          return;
        }
        if (diff.deleted.isEmpty &&
            isClose &&
            diff.start < oldText.length &&
            oldText[diff.start] == inserted) {
          // 键入闭符且右侧紧邻同款闭符：跳过。
          widget.controller.updateSelection(
            TextSelection.collapsed(offset: diff.start + 1),
            ChangeSource.local,
          );
          return;
        }
        if (diff.deleted.isEmpty && isClose) {
          final open = _openSymbolFor(pairs, inserted)!;
          if (!_hasUnclosedOpenBefore(oldText, diff.start, open, inserted)) {
            // 输入法交替给出闭符、前方无未闭合开符：实意是开引号，补全整对。
            widget.controller.replaceText(
              diff.start,
              0,
              open + inserted,
              TextSelection.collapsed(offset: diff.start + 1),
            );
            return;
          }
          // 有未闭合开符：按闭符原样插入，落到默认逻辑。
        }
        if (diff.deleted.isNotEmpty && (isOpen || isClose)) {
          // 有选区：包裹选中文本。
          final open = isOpen ? inserted : _openSymbolFor(pairs, inserted)!;
          widget.controller.replaceText(
            diff.start,
            diff.deleted.length,
            open + diff.deleted + pairs[open]!,
            TextSelection.collapsed(
                offset: diff.start + diff.deleted.length + 2),
          );
          return;
        }
      }
    }

    widget.controller.replaceText(
      diff.start,
      diff.deleted.length,
      diff.inserted,
      value.selection,
    );

    if (pairs != null && compositionEnded) {
      _executeDeferredAutoPair(pairs);
    }
  }

  // ---- 成对符号自动补全（延后执行） ----

  bool _autoPairComposing = false;
  String? _autoPairSymbol;
  int _autoPairPos = -1;
  String _autoPairDeleted = '';

  String? _openSymbolFor(Map<String, String> pairs, String closer) {
    for (final e in pairs.entries) {
      if (e.value == closer) return e.key;
    }
    return null;
  }

  /// offset 之前同族开符多于闭符，视为有未闭合开符。
  bool _hasUnclosedOpenBefore(String text, int offset, String open, String close) {
    var opens = 0, closes = 0;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (text[i] == open) {
        opens++;
      } else if (text[i] == close) {
        closes++;
      }
    }
    return opens > closes;
  }

  /// 组合结束后执行延后的配对：开符补闭符 / 闭符跳过 / 选区包裹。
  /// 符号已不在原位（组合被取消或文档已变化）时放弃。
  void _executeDeferredAutoPair(Map<String, String> pairs) {
    final symbol = _autoPairSymbol;
    _autoPairSymbol = null;
    if (symbol == null) return;
    final pos = _autoPairPos;
    final deleted = _autoPairDeleted;
    final controller = widget.controller;
    final text = controller.document.toPlainText();
    if (pos < 0 || pos >= text.length || text[pos] != symbol) return;
    final open =
        pairs.containsKey(symbol) ? symbol : _openSymbolFor(pairs, symbol);
    if (open == null) return;
    final closer = pairs[open]!;
    if (deleted.isEmpty) {
      if (symbol == open) {
        controller.replaceText(
          pos + 1,
          0,
          closer,
          TextSelection.collapsed(offset: pos + 1),
        );
      } else if (pos + 1 < text.length && text[pos + 1] == symbol) {
        controller.replaceText(
          pos,
          1,
          '',
          TextSelection.collapsed(offset: pos + 1),
        );
      } else if (!_hasUnclosedOpenBefore(text, pos, open, symbol)) {
        // 前方无未闭合开符：实意是开引号，补全整对。
        controller.replaceText(
          pos,
          1,
          open + closer,
          TextSelection.collapsed(offset: pos + 1),
        );
      }
    } else {
      controller.replaceText(
        pos,
        1,
        open + deleted + closer,
        TextSelection.collapsed(offset: pos + deleted.length + 2),
      );
    }
  }

  @override
  void performAction(TextInputAction action) {
    widget.config.onPerformAction?.call(action);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // no-op
  }

  // The time it takes for the floating cursor to snap to the text aligned
  // cursor position after the user has finished placing it.
  static const Duration _floatingCursorResetTime = Duration(milliseconds: 125);

  // The original position of the caret on FloatingCursorDragState.start.
  Rect? _startCaretRect;

  // The most recent text position as determined by the location of the floating
  // cursor.
  TextPosition? _lastTextPosition;

  // The offset of the floating cursor as determined from the start call.
  Offset? _pointOffsetOrigin;

  // The most recent position of the floating cursor.
  Offset? _lastBoundedOffset;

  // Because the center of the cursor is preferredLineHeight / 2 below the touch
  // origin, but the touch origin is used to determine which line the cursor is
  // on, we need this offset to correctly render and move the cursor.
  Offset _floatingCursorOffset(TextPosition textPosition) =>
      Offset(0, renderEditor.preferredLineHeight(textPosition) / 2);

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    switch (point.state) {
      case FloatingCursorDragState.Start:
        if (floatingCursorResetController.isAnimating) {
          floatingCursorResetController.stop();
          onFloatingCursorResetTick();
        }
        // We want to send in points that are centered around a (0,0) origin, so
        // we cache the position.
        _pointOffsetOrigin = point.offset;

        final currentTextPosition =
            TextPosition(offset: renderEditor.selection.baseOffset);
        _startCaretRect =
            renderEditor.getLocalRectForCaret(currentTextPosition);

        _lastBoundedOffset = _startCaretRect!.center -
            _floatingCursorOffset(currentTextPosition);
        _lastTextPosition = currentTextPosition;
        renderEditor.setFloatingCursor(
            point.state, _lastBoundedOffset!, _lastTextPosition!);
        break;
      case FloatingCursorDragState.Update:
        assert(_lastTextPosition != null, 'Last text position was not set');
        final floatingCursorOffset = _floatingCursorOffset(_lastTextPosition!);
        final centeredPoint = point.offset! - _pointOffsetOrigin!;
        final rawCursorOffset =
            _startCaretRect!.center + centeredPoint - floatingCursorOffset;

        final preferredLineHeight =
            renderEditor.preferredLineHeight(_lastTextPosition!);
        _lastBoundedOffset = renderEditor.calculateBoundedFloatingCursorOffset(
          rawCursorOffset,
          preferredLineHeight,
        );
        _lastTextPosition = renderEditor.getPositionForOffset(renderEditor
            .localToGlobal(_lastBoundedOffset! + floatingCursorOffset));
        renderEditor.setFloatingCursor(
            point.state, _lastBoundedOffset!, _lastTextPosition!);
        final newSelection = TextSelection.collapsed(
            offset: _lastTextPosition!.offset,
            affinity: _lastTextPosition!.affinity);
        // Setting selection as floating cursor moves will have scroll view
        // bring background cursor into view
        renderEditor.onSelectionChanged(
            newSelection, SelectionChangedCause.forcePress);
        break;
      case FloatingCursorDragState.End:
        // We skip animation if no update has happened.
        if (_lastTextPosition != null && _lastBoundedOffset != null) {
          floatingCursorResetController
            ..value = 0.0
            ..animateTo(1,
                duration: _floatingCursorResetTime, curve: Curves.decelerate);
        }
        break;
    }
  }

  /// Specifies the floating cursor dimensions and position based
  /// the animation controller value.
  /// The floating cursor is resized
  /// (see [RenderAbstractEditor.setFloatingCursor])
  /// and repositioned (linear interpolation between position of floating cursor
  /// and current position of background cursor)
  void onFloatingCursorResetTick() {
    final finalPosition =
        renderEditor.getLocalRectForCaret(_lastTextPosition!).centerLeft -
            _floatingCursorOffset(_lastTextPosition!);
    if (floatingCursorResetController.isCompleted) {
      renderEditor.setFloatingCursor(
          FloatingCursorDragState.End, finalPosition, _lastTextPosition!);
      _startCaretRect = null;
      _lastTextPosition = null;
      _pointOffsetOrigin = null;
      _lastBoundedOffset = null;
    } else {
      final lerpValue = floatingCursorResetController.value;
      final lerpX =
          lerpDouble(_lastBoundedOffset!.dx, finalPosition.dx, lerpValue)!;
      final lerpY =
          lerpDouble(_lastBoundedOffset!.dy, finalPosition.dy, lerpValue)!;

      renderEditor.setFloatingCursor(FloatingCursorDragState.Update,
          Offset(lerpX, lerpY), _lastTextPosition!,
          resetLerpValue: lerpValue);
    }
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // this is called VERY OFTEN when editing a document, no longer throw
    // an exception
  }

  @override
  void connectionClosed() {
    if (!hasConnection) {
      return;
    }
    _textInputConnection!.connectionClosedReceived();
    _textInputConnection = null;
    _lastKnownRemoteTextEditingValue = null;
  }

  @override
  bool onFocusReceived() => false;

  void _updateSizeAndTransform() {
    if (hasConnection) {
      // Asking for renderEditor.size here can cause errors if layout hasn't
      // occurred yet. So we schedule a post frame callback instead.
      final size = renderEditor.size;
      final transform = renderEditor.getTransformTo(null);
      _textInputConnection?.setEditableSizeAndTransform(size, transform);
      SchedulerBinding.instance
          .addPostFrameCallback((_) => _updateSizeAndTransform());
    }
  }
}
