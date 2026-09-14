import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 鼠标友好的"长按后拖动"排序监听器。
///
/// 官方 [ReorderableDelayedDragStartListener] 对鼠标指针仅允许约 2px 的
/// 位移容差（kPrecisePointerPanSlop），按住时轻微抖动即被 reject，
/// 桌面端几乎无法触发；这里自定义 recognizer，长按 [kLongPressTimeout]
/// 后即开始拖动，不因微小位移失败。
class LongPressDragStartListener extends ReorderableDragStartListener {
  const LongPressDragStartListener({
    super.key,
    required super.child,
    required super.index,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _LongPressMultiDragRecognizer();
}

class _LongPressMultiDragRecognizer extends MultiDragGestureRecognizer {
  _LongPressMultiDragRecognizer() : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _LongPressPointerState(event.position, event.kind);
  }

  @override
  String get debugDescription => 'long press drag (mouse friendly)';
}

class _LongPressPointerState extends MultiDragPointerState {
  _LongPressPointerState(Offset initialPosition, PointerDeviceKind kind)
    : super(initialPosition, kind, null) {
    _timer = Timer(kLongPressTimeout, _delayPassed);
  }

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _delayPassed() {
    _timer = null;
    if (_starter != null) {
      _starter!(initialPosition);
      _starter = null;
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
