import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 章节拖拽负载：目录树内排序与拖入编辑区共用。
class ChapterDragData {
  const ChapterDragData({
    required this.bookId,
    required this.volumeId,
    required this.chapterId,
    required this.title,
  });

  final String bookId;
  final String volumeId;
  final String chapterId;
  final String title;
}

/// 章节拖出用的 Draggable：即时拖动识别器带鼠标位移容差。
class ChapterDraggable extends Draggable<ChapterDragData> {
  const ChapterDraggable({
    super.key,
    required super.data,
    required super.feedback,
    super.childWhenDragging,
    required super.child,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.onDraggableCanceled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _ChapterDragRecognizer()..onStart = onStart;
}

/// 位移超过阈值才启动拖出，避免长按排序期间的手抖被识别为拖出。
class _ChapterDragRecognizer extends MultiDragGestureRecognizer {
  _ChapterDragRecognizer() : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _ChapterDragPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'chapter drag';
}

class _ChapterDragPointerState extends MultiDragPointerState {
  _ChapterDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  /// 鼠标 / 触控板的启动阈值，给长按排序留出容差。
  static const double _mouseSlop = 8;

  @override
  void checkForResolutionAfterMove() {
    final mouse = kind == PointerDeviceKind.mouse ||
        kind == PointerDeviceKind.trackpad;
    final slop = mouse ? _mouseSlop : computeHitSlop(kind, gestureSettings);
    if (pendingDelta!.distance > slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

/// 章节拖动时跟随指针的浮层。
Widget chapterDragFeedback(BuildContext context, ChapterDragData data) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(8),
    color: Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.12),
      scheme.surface,
    ),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
