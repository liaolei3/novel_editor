import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

/// 通用输入对话框。
Future<String?> inputDialog(BuildContext context,
    {required String title, String initial = '', String hint = '', int maxLines = 1}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
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
  );
}

/// 新建作品对话框 → (书名, 笔名)。
Future<(String, String)?> createBookDialog(BuildContext context) async {
  final titleCtrl = TextEditingController();
  final penCtrl = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('新建作品'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, autofocus: true,
            decoration: const InputDecoration(labelText: '书名')),
        const SizedBox(height: 12),
        TextField(controller: penCtrl, decoration: const InputDecoration(labelText: '作者笔名（可选）')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final title = titleCtrl.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(ctx, (title, penCtrl.text.trim()));
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

/// 编辑作品对话框 → (书名, 笔名)，预填现有值。
Future<(String, String)?> editBookDialog(BuildContext context,
    {required String initialTitle, required String initialPenName}) async {
  final titleCtrl = TextEditingController(text: initialTitle);
  final penCtrl = TextEditingController(text: initialPenName);
  return showDialog<(String, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('编辑作品'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, autofocus: true,
            decoration: const InputDecoration(labelText: '书名')),
        const SizedBox(height: 12),
        TextField(controller: penCtrl,
            decoration: const InputDecoration(labelText: '作者笔名（可选）')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final title = titleCtrl.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(ctx, (title, penCtrl.text.trim()));
          },
          child: const Text('保存'),
        ),
      ],
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
    builder: (ctx) => Dialog(
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