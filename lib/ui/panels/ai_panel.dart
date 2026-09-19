import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../services/ai/ai_gateway.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../widgets/toast.dart';

/// AI 面板（FR-16 ~ FR-20 / 9.4）：
/// 三类能力；候选卡片、加载态、失败重试；结果不自动写入正文，需用户确认。
class AiPanel extends StatefulWidget {
  const AiPanel({super.key});

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  AiTask _tab = AiTask.continueWriting;
  bool _loading = false;
  List<String> _results = const [];
  String? _error;
  String _polishMode = '润色';
  String _inspirationType = '剧情转折';

  AiGateway? _gateway(SettingsController s) {
    if (s.aiBaseUrl.isEmpty || s.aiApiKey.isEmpty) return null;
    return OpenAiCompatibleGateway(
      baseUrl: s.aiBaseUrl,
      apiKey: s.aiApiKey,
      model: s.aiModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final gateway = _gateway(settings);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (task, label) in const [
                (AiTask.continueWriting, '续写'),
                (AiTask.polish, '润色'),
                (AiTask.inspiration, '灵感'),
              ])
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _tab == task,
                    onSelected: (_) => setState(() {
                      _tab = task;
                      _results = const [];
                      _error = null;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _actionArea(context, gateway),
              if (_loading) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                const Center(child: Text('AI 正在生成…（30s 超时）')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _run(context, gateway),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              for (final (i, r) in _results.indexed)
                _candidateCard(context, i, r),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionArea(BuildContext context, AiGateway? gateway) {
    final state = context.watch<AppState>();
    if (gateway == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('尚未配置 AI 网关。'),
              const SizedBox(height: 4),
              const Text(
                '应用已降级为纯写作模式，全部本地功能不受影响（NFR-U4）。配置路径：设置 → AI 配置。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    switch (_tab) {
      case AiTask.continueWriting:
        final chapter = state.currentChapter;
        final ctxLen = chapter == null ? 0 : _contextBefore(state).length;
        return Text(
          chapter == null
              ? '先打开章节，将光标置于需要续写的位置。'
              : '将基于光标前 $ctxLen 字（上限 3000 字）生成 1~3 个候选片段，插入需确认。',
          style: const TextStyle(fontSize: 12),
        );
      case AiTask.polish:
        final selected = state.editorController.selection;
        final hasSel = selected.isValid && selected.start != selected.end;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final m in const ['润色', '精简', '扩写', '对白优化'])
                  ChoiceChip(
                    label: Text(m),
                    selected: _polishMode == m,
                    onSelected: (_) => setState(() => _polishMode = m),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasSel ? '已选中文本，点击下方按钮生成。' : '请先在正文中选中要处理的文本。',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      case AiTask.inspiration:
        return Wrap(
          spacing: 8,
          children: [
            for (final t in const ['剧情转折', '人物冲突', '开脑洞'])
              ChoiceChip(
                label: Text(t),
                selected: _inspirationType == t,
                onSelected: (_) => setState(() => _inspirationType = t),
              ),
          ],
        );
    }
  }

  String _contextBefore(AppState state) {
    final controller = state.editorController;
    final text = controller.document.toPlainText();
    final offset = controller.selection.baseOffset.clamp(0, text.length);
    final start = (offset - AppConstants.aiContextLimit).clamp(0, offset);
    return text.substring(start, offset);
  }

  Future<void> _run(BuildContext context, AiGateway? gateway) async {
    if (gateway == null || _loading) return;
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    final AiRequest request;
    switch (_tab) {
      case AiTask.continueWriting:
        request = AiRequest(
          kind: AiTask.continueWriting,
          prompt: AiPrompts.continueWriting(_contextBefore(state)),
          count: 3,
        );
        break;
      case AiTask.polish:
        final sel = state.editorController.selection;
        final text = state.editorController.document.toPlainText();
        final selectedText = text.substring(
          sel.start.clamp(0, text.length),
          sel.end.clamp(0, text.length),
        );
        request = AiRequest(
          kind: AiTask.polish,
          prompt: AiPrompts.polish(selectedText, _polishMode),
          count: 1,
        );
        break;
      case AiTask.inspiration:
        request = AiRequest(
          kind: AiTask.inspiration,
          prompt: AiPrompts.inspiration(_inspirationType),
          count: 1,
        );
        break;
    }
    final result = await gateway.complete(request);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _results = _splitCandidates(result.candidates);
      } else {
        _error = result.error ?? '生成失败，可重试。';
      }
    });
  }

  List<String> _splitCandidates(List<String> raw) {
    if (_tab == AiTask.continueWriting) return raw;
    final joined = raw.join('\n');
    if (_tab == AiTask.inspiration) {
      final lines = joined
          .split(RegExp(r'\n(?=\d+[.、）)])'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return lines.length > 1 ? lines : [joined];
    }
    return [joined];
  }

  Widget _candidateCard(BuildContext context, int index, String text) {
    final state = context.read<AppState>();
    final run = () =>
        _run(context, _gateway(context.read<SettingsController>()));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '候选 ${index + 1}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: const TextStyle(height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ..._actionsFor(context, state, text),
                IconButton(
                  tooltip: '换一批 / 重试',
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: run,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionsFor(BuildContext context, AppState state, String text) {
    switch (_tab) {
      case AiTask.continueWriting:
        return [
          FilledButton.tonal(
            child: const Text('确认插入正文（可撤销）'),
            onPressed: () async {
              final controller = state.editorController;
              final docLen = controller.document.length;
              final offset = controller.selection.baseOffset.clamp(0, docLen);
              await state.durability.manualSnapshot(state.currentChapter!);
              controller.replaceText(
                offset,
                0,
                '\n$text',
                TextSelection.collapsed(offset: offset + text.length + 1),
              );
              state.onEditorChanged();
              await state.autosave.flush();
              if (context.mounted) {
                showToast(context, '插入成功；插入前已自动创建快照，可从「历史快照」撤销');
              }
            },
          ),
        ];
      case AiTask.polish:
        return [
          FilledButton.tonal(
            child: const Text('采纳（替换选中文本）'),
            onPressed: () async {
              final controller = state.editorController;
              final sel = controller.selection;
              final docLen = controller.document.length;
              final start = sel.start.clamp(0, docLen);
              final end = sel.end.clamp(0, docLen);
              await state.durability.manualSnapshot(state.currentChapter!);
              controller.replaceText(
                start,
                end - start,
                text,
                TextSelection.collapsed(offset: start + text.length),
              );
              state.onEditorChanged();
              await state.autosave.flush();
              if (context.mounted) {
                showToast(context, '采纳成功，已写入正文');
              }
            },
          ),
        ];
      case AiTask.inspiration:
        return [
          FilledButton.tonal(
            child: const Text('存入灵感便签'),
            onPressed: () async {
              final book = state.currentBook;
              if (book == null) return;
              await state.notes.create(
                bookId: book.id,
                type: NoteType.idea,
                title: '灵感 ${DateTime.now().month}/${DateTime.now().day}',
                content: text,
              );
              if (context.mounted) {
                showToast(context, '保存成功，已存入灵感便签（素材库）');
              }
            },
          ),
        ];
    }
  }
}
