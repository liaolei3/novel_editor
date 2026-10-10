import 'package:flutter/material.dart';

import 'dialogs.dart';

/// 新增 / 编辑敏感词词条弹窗：返回 (词, 建议词)，取消返回 null。
Future<(String, String)?> showSensitiveWordDialog(
  BuildContext context, {
  String word = '',
  String suggestion = '',
}) {
  return showDialog<(String, String)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SensitiveWordDialog(word: word, suggestion: suggestion),
  );
}

class _SensitiveWordDialog extends StatefulWidget {
  const _SensitiveWordDialog({required this.word, required this.suggestion});

  final String word;
  final String suggestion;

  @override
  State<_SensitiveWordDialog> createState() => _SensitiveWordDialogState();
}

class _SensitiveWordDialogState extends State<_SensitiveWordDialog> {
  late final TextEditingController _word =
      TextEditingController(text: widget.word);
  late final TextEditingController _sug =
      TextEditingController(text: widget.suggestion);

  bool get _editing => widget.word.isNotEmpty;

  @override
  void dispose() {
    _word.dispose();
    _sug.dispose();
    super.dispose();
  }

  void _submit() {
    final w = _word.text.trim();
    if (w.isEmpty) return;
    Navigator.pop(context, (w, _sug.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialog(
      child: AlertDialog(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        title: Text(_editing ? '编辑敏感词' : '新增敏感词',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 272,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _word,
                autofocus: true,
                decoration: dialogFieldDecoration(
                    Theme.of(context).colorScheme,
                    label: '敏感词'),
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sug,
                decoration: dialogFieldDecoration(
                    Theme.of(context).colorScheme,
                    label: '建议替换词',
                    hint: '留空则仅提示'),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: _word.text.trim().isEmpty ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(72, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}