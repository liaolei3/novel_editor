import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/rich_text_codec.dart';
import '../../services/sync/sync_engine.dart';
import '../../state/app_state.dart';


/// 冲突解决界面（FR-13 / 12.2）：
/// 保留我的 / 使用云端 / 两者都保留（生成副本），绝不静默覆盖。
class ConflictDialog extends StatefulWidget {
  const ConflictDialog({super.key, required this.conflicts});

  final List<SyncConflict> conflicts;

  @override
  State<ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<ConflictDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.conflicts.length) {
      return const AlertDialog(title: Text('冲突已全部解决'));
    }
    final conflict = widget.conflicts[_index];
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('检测到同步冲突（${_index + 1}/${widget.conflicts.length}）',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('章节「${conflict.chapterTitle}」在本机与云端均被修改，请选择保留方式：',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Expanded(
              child: Row(children: [
                Expanded(child: _pane(context, '本机版本（v${conflict.localVersion}）',
                    RichTextCodec.plainTextFromDeltaJson(conflict.localContent))),
                const SizedBox(width: 12),
                Expanded(child: _pane(context, '云端版本（v${conflict.cloudVersion}）',
                    RichTextCodec.plainTextFromDeltaJson(conflict.cloudContent))),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
              OutlinedButton(
                onPressed: () => _resolve(ConflictChoice.keepLocal),
                child: const Text('保留我的'),
              ),
              OutlinedButton(
                onPressed: () => _resolve(ConflictChoice.useCloud),
                child: const Text('使用云端'),
              ),
              FilledButton(
                onPressed: () => _resolve(ConflictChoice.keepBoth),
                child: const Text('两者都保留（云端生成副本）'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _pane(BuildContext context, String label, String text) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(height: 1.7)),
          ),
        ),
      ]),
    );
  }

  Future<void> _resolve(ConflictChoice choice) async {
    final state = context.read<AppState>();
    final conflict = widget.conflicts[_index];
    if (choice == ConflictChoice.keepLocal) {
      // 本机内容已在内存中：确保章节对象为本地内容后再走统一流程。
      final chapter = await state.chapters.get(conflict.chapterId);
      if (chapter != null) {
        chapter.content = conflict.localContent;
        await state.sync.resolveConflict(chapter, choice);
      }
    } else {
      final chapter = await state.chapters.get(conflict.chapterId);
      if (chapter != null) {
        await state.sync.resolveConflict(chapter, choice);
      }
    }
    setState(() => _index++);
    if (_index >= widget.conflicts.length && context.mounted) {
      Navigator.pop(context, true);
    }
  }
}