import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/repositories.dart' show newId;
import '../widgets/app_icon.dart';
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => setState(() => _offset += details.delta),
      child: Transform.translate(offset: _offset, child: widget.child),
    );
  }
}

/// 通用输入对话框。
Future<String?> inputDialog(BuildContext context,
    {required String title, String initial = '', String hint = '', int maxLines = 1}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          maxLength: maxLines > 1 ? 200 : null,
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确定')),
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
            title: const Text('新建作品'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl, autofocus: true,
                  decoration: const InputDecoration(labelText: '书名')),
              const SizedBox(height: 12),
              TextField(controller: penCtrl,
                  decoration: const InputDecoration(labelText: '作者笔名（可选）')),
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
            actions: [
              TextButton(
                onPressed: () async {
                  // 取消时清理本次已复制的封面文件。
                  final picked = pickedPath;
                  if (picked != null) await BookCover.deleteFile(picked);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  Navigator.pop(
                      ctx, (title, penCtrl.text.trim(), cleared ? null : pickedPath));
                },
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
                          AppIcon(Icons.upload_file, size: 28,
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
                      child: const AppIcon(Icons.close, size: 14,
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
            title: const Text('编辑作品'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '书名')),
              const SizedBox(height: 12),
              TextField(controller: penCtrl,
                  decoration: const InputDecoration(labelText: '作者笔名（可选）')),
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
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(ctx).textTheme.titleLarge)),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const AppIcon(Icons.close)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _pane(ctx, leftLabel, left)),
                const SizedBox(width: 12),
                Expanded(child: _pane(ctx, rightLabel, right)),
              ]),
            ),
          ]),
        ),
      ),
      ),
    ),
  );
}

Widget _pane(BuildContext ctx, String label, String text) {
  return Container(
    decoration: BoxDecoration(
      color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(80),
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(ctx).textTheme.titleSmall),
      const SizedBox(height: 8),
      Expanded(
        child: SingleChildScrollView(
          child: SelectableText(text, style: const TextStyle(height: 1.7)),
        ),
      ),
    ]),
  );
}