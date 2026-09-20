import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/material.dart';

import '../../data/repositories.dart' show newId;
import 'book_cover.dart';

/// 可拖动对话框包装：按住弹窗任意空白区域（未被内部控件接管的区域，
/// 如标题、留白、按钮周围）拖动即可移动弹窗；内部滚动区、文本框、
/// 按钮等手势不受影响。
class DraggableDialog extends StatefulWidget {
  const DraggableDialog({super.key, required this.child});

  final Widget child;

  @override
  State<DraggableDialog> createState() => _DraggableDialogState();
}

class _DraggableDialogState extends State<DraggableDialog> {
  Offset _offset = Offset.zero;
  Rect? _baseRect; // 弹窗未偏移时的初始位置（基准）。
  final _childKey = GlobalKey();

  // 子树会被对话框路由的紧约束拉成全窗尺寸，且 Dialog 自带 insetPadding
  // 等包裹层，只有最内层 Material 才是弹窗本体；找到它再做边界钳制。
  RenderBox? _contentBox(Size window) {
    final ctx = _childKey.currentContext;
    if (ctx == null) return null;
    RenderBox? found;
    void visit(Element el) {
      if (found != null) return;
      if (el.widget is Material) {
        final ro = el.findRenderObject();
        if (ro is RenderBox &&
            ro.hasSize &&
            ro.size.width < window.width &&
            ro.size.height < window.height) {
          found = ro;
        }
        return;
      }
      el.visitChildElements(visit);
    }

    visit(ctx as Element);
    if (found != null) return found;
    final root = ctx.findRenderObject();
    return root is RenderBox && root.hasSize ? root : null;
  }

  // 边缘位置钳制：盒子不小于窗口时锁定居中，否则限制在 [0, 窗口-盒子]。
  double _limit(double edge, double size, double boundary) {
    if (size >= boundary) return (boundary - size) / 2;
    return edge.clamp(0.0, boundary - size);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final window = MediaQuery.sizeOf(context);
    if (_baseRect == null) {
      final box = _contentBox(window);
      if (box == null) return;
      // 全局坐标含当前 transform 偏移，换算回未偏移基准。
      _baseRect = (box.localToGlobal(Offset.zero) - _offset) & box.size;
    }
    final rect = _baseRect!.shift(_offset);
    final dx =
        _limit(rect.left + details.delta.dx, rect.width, window.width) -
            rect.left;
    final dy =
        _limit(rect.top + details.delta.dy, rect.height, window.height) -
            rect.top;
    if (dx == 0 && dy == 0) return;
    setState(() => _offset += Offset(dx, dy));
  }

  @override
  Widget build(BuildContext context) {
    Widget child = KeyedSubtree(key: _childKey, child: widget.child);
    // 弹窗底色半透明（玻璃拟态）时叠加背景模糊，圆角跟随弹窗 shape。
    final dialogBg = Theme.of(context).dialogTheme.backgroundColor;
    if (dialogBg != null && dialogBg.a < 1) {
      final shape = Theme.of(context).dialogTheme.shape;
      final radius = shape is RoundedRectangleBorder
          ? shape.borderRadius
              .resolve(Directionality.of(context))
              .topLeft
              .x
          : 16.0;
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: child,
        ),
      );
    }
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      child: Transform.translate(offset: _offset, child: child),
    );
  }
}

/// 通用输入对话框（macOS 风格：居中标题 + 紧凑输入框 + 右下角按钮）。
Future<String?> inputDialog(BuildContext context,
    {required String title,
    String initial = '',
    String hint = '',
    int maxLines = 1,
    double width = 320}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: AlertDialog(
        constraints: BoxConstraints(minWidth: width, maxWidth: width),
        backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor,
        shape: Theme.of(ctx).dialogTheme.shape,
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        actionsOverflowButtonSpacing: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          maxLength: maxLines > 1 ? 200 : null,
          style: const TextStyle(fontSize: 13),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(
              minimumSize: const Size(72, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}

/// 新建作品对话框 → (书名, 笔名, 封面相对路径?)。
/// 封面在创建前先落盘（以临时 ID 命名），取消时清理。
Future<(String, String, String?)?> createBookDialog(BuildContext context) async {
  final titleCtrl = TextEditingController();
  final penCtrl = TextEditingController();
  final tempId = newId(); // 封面文件命名前缀，书籍 ID 稍后由仓库生成。
  String? pickedPath; // 已复制的封面相对路径。
  var cleared = false;

  return showDialog<(String, String, String?)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pick() async {
          final picked = await BookCover.pickAndStore(tempId);
          if (picked != null) {
            setDialogState(() {
              pickedPath = picked;
              cleared = false;
            });
          }
        }

        return DraggableDialog(
          child: AlertDialog(
            // Dialog 内部 Align 会架空外层 SizedBox 的宽度，须用 constraints 指定。
            constraints: const BoxConstraints(minWidth: 320),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            title: const Text('新建作品',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '书名',
                    labelStyle: TextStyle(fontSize: 13),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  )),
              const SizedBox(height: 14),
              TextField(
                  controller: penCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '作者笔名（可选）',
                    labelStyle: TextStyle(fontSize: 13),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  )),
              const SizedBox(height: 16),
              _CoverUploadBox(
                previewPath: cleared ? '' : (pickedPath ?? ''),
                onPick: pick,
                onClear: pickedPath != null && !cleared
                    ? () => setDialogState(() {
                          cleared = true;
                          BookCover.deleteFile(pickedPath!);
                          pickedPath = null;
                        })
                    : null,
              ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () async {
                  // 取消时清理本次已复制的封面文件。
                  final picked = pickedPath;
                  if (picked != null) await BookCover.deleteFile(picked);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(
                      ctx, (title, penCtrl.text.trim(), cleared ? null : pickedPath));
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 封面上传框：等宽书本比例，无图时显示图标+提示，整框可点击。
/// 有图时铺满预览，右上角浮现清除按钮（[onClear] 为 null 时隐藏）。
class _CoverUploadBox extends StatelessWidget {
  const _CoverUploadBox({
    required this.previewPath,
    required this.onPick,
    this.onClear,
  });

  final String previewPath;
  final Future<void> Function() onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 输入框背景色，上传框与之一致。
    final fieldFill = Theme.of(context).inputDecorationTheme.fillColor ??
        scheme.surfaceContainerHighest;
    final previewFuture = previewPath.isEmpty
        ? Future<ImageProvider?>.value()
        : BookCover.resolve(previewPath)
            .then<FileImage>((abs) => FileImage(File(abs)));
    return FutureBuilder<ImageProvider?>(
      future: previewFuture,
      builder: (ctx, snap) {
        final hasImage = snap.hasData && snap.data != null;
        return Stack(
          children: [
            InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(8),
              mouseCursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: hasImage ? null : fieldFill,
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image(image: snap.data!, fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file, size: 32,
                              color: scheme.onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text(
                            '上传封面（可选）',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (hasImage && onClear != null)
              Positioned(
                top: 6,
                right: 6,
                child: Tooltip(
                  message: '清除封面',
                  child: GestureDetector(
                    onTap: onClear,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0x96000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 编辑作品对话框 → (书名, 笔名, 封面动作)。
/// 封面动作语义：null = 未改动；'' = 清除封面；其他 = 新封面的相对路径。
Future<(String, String, String?)?> editBookDialog(
  BuildContext context, {
  required String bookId,
  required String initialTitle,
  required String initialPenName,
  required String initialCoverPath,
}) async {
  final titleCtrl = TextEditingController(text: initialTitle);
  final penCtrl = TextEditingController(text: initialPenName);
  String? newPath; // 新选择的封面相对路径。
  var cleared = false; // 是否选择清除封面。

  return showDialog<(String, String, String?)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        // 当前预览图：新选文件 > 现有封面文件 > 空占位。
        final previewPath = cleared ? '' : (newPath ?? initialCoverPath);

        Future<void> pick() async {
          final picked = await BookCover.pickAndStore(bookId);
          if (picked != null) {
            setDialogState(() {
              newPath = picked;
              cleared = false;
            });
          }
        }

        return DraggableDialog(
          child: AlertDialog(
            constraints: const BoxConstraints(minWidth: 320),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            title: const Text('编辑作品',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '书名',
                    labelStyle: TextStyle(fontSize: 13),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  )),
              const SizedBox(height: 14),
              TextField(
                  controller: penCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '作者笔名（可选）',
                    labelStyle: TextStyle(fontSize: 13),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  )),
              const SizedBox(height: 16),
              _CoverUploadBox(
                previewPath: previewPath,
                onPick: pick,
                onClear: previewPath.isEmpty
                    ? null
                    : () => setDialogState(() => cleared = true),
              ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () async {
                  // 取消时清理本次已复制的新封面文件。
                  final picked = newPath;
                  if (picked != null && picked != initialCoverPath) {
                    await BookCover.deleteFile(picked);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  // 封面动作：'' = 清除；null = 保持不变；其他 = 新相对路径。
                  final action = cleared ? '' : newPath;
                  Navigator.pop(ctx, (title, penCtrl.text.trim(), action));
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 文本对照视图（快照对比 / 润色对照 / 冲突对比共用）。
Future<void> showCompareDialog(
  BuildContext context, {
  required String title,
  required String leftLabel,
  required String rightLabel,
  required String left,
  required String right,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 780),
          child: _CompareBody(
            title: title,
            leftLabel: leftLabel,
            rightLabel: rightLabel,
            left: left,
            right: right,
          ),
        ),
      ),
    ),
  );
}

class _CompareBody extends StatefulWidget {
  const _CompareBody({
    required this.title,
    required this.leftLabel,
    required this.rightLabel,
    required this.left,
    required this.right,
  });

  final String title;
  final String leftLabel;
  final String rightLabel;
  final String left;
  final String right;

  @override
  State<_CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends State<_CompareBody> {
  List<dmp.Diff>? _diffs;
  final ScrollController _leftCtrl = ScrollController();
  final ScrollController _rightCtrl = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftCtrl.addListener(() => _syncScroll(_leftCtrl, _rightCtrl));
    _rightCtrl.addListener(() => _syncScroll(_rightCtrl, _leftCtrl));
    Future.microtask(() async {
      final diffs = await Future(() {
        final d = dmp.diff(widget.left, widget.right);
        dmp.cleanupSemantic(d);
        return d;
      });
      if (mounted) setState(() => _diffs = diffs);
    });
  }

  @override
  void dispose() {
    _leftCtrl.dispose();
    _rightCtrl.dispose();
    super.dispose();
  }

  void _syncScroll(ScrollController src, ScrollController dst) {
    if (_syncing || !src.hasClients || !dst.hasClients) return;
    final srcMax = src.position.maxScrollExtent;
    final dstMax = dst.position.maxScrollExtent;
    if (srcMax <= 0) return;
    _syncing = true;
    dst.jumpTo((src.offset / srcMax * dstMax).clamp(0.0, dstMax));
    _syncing = false;
  }

  int get _changeCount {
    final diffs = _diffs;
    if (diffs == null) return 0;
    var n = 0;
    var inRegion = false;
    for (final d in diffs) {
      if (d.operation == dmp.DIFF_EQUAL) {
        inRegion = false;
      } else if (!inRegion) {
        n++;
        inRegion = true;
      }
    }
    return n;
  }

  int _opChars(int op) {
    var n = 0;
    final diffs = _diffs;
    if (diffs != null) {
      for (final d in diffs) {
        if (d.operation == op) n += d.text.length;
      }
    }
    return n;
  }

  List<TextSpan> _spans(Color delBg, Color delFg, Color insBg, Color insFg,
      bool isLeft) {
    final spans = <TextSpan>[];
    for (final d in _diffs!) {
      switch (d.operation) {
        case dmp.DIFF_EQUAL:
          spans.add(TextSpan(text: d.text));
        case dmp.DIFF_DELETE:
          if (isLeft) {
            spans.add(TextSpan(
              text: d.text,
              style: TextStyle(backgroundColor: delBg, color: delFg),
            ));
          }
        case dmp.DIFF_INSERT:
          if (!isLeft) {
            spans.add(TextSpan(
              text: d.text,
              style: TextStyle(backgroundColor: insBg, color: insFg),
            ));
          }
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dark = scheme.brightness == Brightness.dark;
    final delBg = dark
        ? const Color(0xFFF87171).withValues(alpha: 0.18)
        : const Color(0xFFFDE8E8);
    final delFg = dark ? const Color(0xFFFCA5A5) : const Color(0xFF9B1C1C);
    final insBg = dark
        ? const Color(0xFF4ADE80).withValues(alpha: 0.16)
        : const Color(0xFFE3F5E8);
    final insFg = dark ? const Color(0xFF86EFAC) : const Color(0xFF1E6B3A);

    return Padding(
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
              child:
                  Icon(Icons.difference_outlined, size: 24, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: textTheme.titleLarge
                          ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Flexible(
                      child: Text(
                        '${widget.leftLabel} ↔ ${widget.rightLabel}',
                        style: textTheme.bodySmall?.copyWith(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 14),
                    _legendDot(delBg, delFg),
                    const SizedBox(width: 4),
                    Text('删除',
                        style: textTheme.bodySmall?.copyWith(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 10),
                    _legendDot(insBg, insFg),
                    const SizedBox(width: 4),
                    Text('新增',
                        style: textTheme.bodySmall?.copyWith(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Expanded(
            child: _diffs == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text('正在计算差异…',
                            style: textTheme.bodySmall?.copyWith(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : Row(children: [
                    Expanded(
                        child: _diffPane(context, widget.leftLabel,
                            Icons.article_outlined, false, delBg, delFg, insBg, insFg)),
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
                        child: _diffPane(context, widget.rightLabel,
                            Icons.auto_awesome, true, delBg, delFg, insBg, insFg)),
                  ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(
                _diffs == null
                    ? ''
                    : _changeCount == 0
                        ? '两版内容一致'
                        : '共 $_changeCount 处差异（新增 ${_opChars(dmp.DIFF_INSERT)} 字 / 删除 ${_opChars(dmp.DIFF_DELETE)} 字）',
                style: textTheme.bodySmall
                    ?.copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _legendDot(Color bg, Color fg) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3.5),
        border: Border.all(color: fg.withValues(alpha: 0.6), width: 0.8),
      ),
    );
  }

  Widget _diffPane(
    BuildContext context,
    String label,
    IconData icon,
    bool isRight,
    Color delBg,
    Color delFg,
    Color insBg,
    Color insFg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest
            .withValues(alpha: isRight ? 0.55 : 0.31),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRight
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
                color:
                    isRight ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isRight ? scheme.primary : null,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              controller: isRight ? _rightCtrl : _leftCtrl,
              child: SelectionArea(
                child: Text.rich(
                  TextSpan(
                    children: _spans(delBg, delFg, insBg, insFg, !isRight),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.8,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}