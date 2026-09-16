import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/sensitive_words.dart';
import '../../state/app_state.dart';
import '../widgets/toast.dart';

/// 敏感词检测面板（FR-26）：内置词库 + 命中列表 + 替换建议，不做强制屏蔽。
class SensitivePanel extends StatefulWidget {
  const SensitivePanel({super.key});

  @override
  State<SensitivePanel> createState() => _SensitivePanelState();
}

class _SensitivePanelState extends State<SensitivePanel> {
  Map<String, List<int>>? _hits;
  String _suggestion = '○○○';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chapter = state.currentChapter;
    final scanner = SensitiveWordScanner.defaultScanner;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('敏感词检测（内置词库 ${scanner.words.length} 词）',
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      const Text('命中仅做提示，不强制屏蔽；支持一键替换为建议字符。'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('检测本章'),
            onPressed: chapter == null
                ? null
                : () => setState(() => _hits =
                    scanner.scan(RichTextCodec.plainTextFromDeltaJson(chapter.content))),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.build),
            label: const Text('全部替换'),
            onPressed: (_hits == null || _hits!.isEmpty || chapter == null)
                ? null
                : () async {
                    final plain =
                        RichTextCodec.plainTextFromDeltaJson(chapter.content);
                    final replaced = scanner.replaceAll(plain, _suggestion);
                    state
                        .replaceDocument(RichTextCodec.documentFromContent(replaced));
                    await state.autosave.flush();
                    if (context.mounted) {
                      showToast(context, '已替换全部命中词');
                    }
                    setState(() => _hits = scanner.scan(replaced));
                  },
          ),
          SizedBox(
            width: 100,
            child: TextField(
              decoration: const InputDecoration(labelText: '建议替换', isDense: true),
              onChanged: (v) => _suggestion = v,
              controller: TextEditingController(text: _suggestion),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (_hits == null)
        const Text('尚未检测。')
      else if (_hits!.isEmpty)
        const Text('未检测到命中词 ✓')
      else
        ..._hits!.entries.map((e) => Card(
              child: ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: Text(e.key),
                subtitle: Text('命中 ${e.value.length} 处'),
              ),
            )),
    ]);
  }
}