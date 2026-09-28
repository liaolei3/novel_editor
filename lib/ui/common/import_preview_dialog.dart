import 'package:flutter/material.dart';

import '../../core/utils/txt_importer.dart';
import 'dialogs.dart' show DraggableDialog;

/// 导入预览弹窗：展示切分出的卷/章结构，确认后返回书名（取消 / 关闭返回 null）。
Future<String?> importPreviewDialog(
  BuildContext context, {
  required String initialTitle,
  required ImportPreview preview,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: _ImportPreviewBody(initialTitle: initialTitle, preview: preview),
    ),
  );
}

class _ImportPreviewBody extends StatefulWidget {
  const _ImportPreviewBody({required this.initialTitle, required this.preview});

  final String initialTitle;
  final ImportPreview preview;

  @override
  State<_ImportPreviewBody> createState() => _ImportPreviewBodyState();
}

class _ImportPreviewBodyState extends State<_ImportPreviewBody> {
  late final TextEditingController _titleCtrl =
      TextEditingController(text: widget.initialTitle);
  final ScrollController _scrollCtrl = ScrollController();

  /// 默认全部展开，仅记录被收起的卷下标。
  final Set<int> _collapsed = {};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preview = widget.preview;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: 720, height: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_stories_outlined,
                      size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导入预览',
                          style: textTheme.titleLarge?.copyWith(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        '共 ${preview.volumeCount} 卷 · ${preview.chapterCount} 章 · ${_formatCount(preview.charCount)}字',
                        style: textTheme.bodySmall?.copyWith(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '书名',
                  labelStyle: TextStyle(fontSize: 13),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: preview.volumes.length,
                        itemBuilder: (_, i) =>
                            _volumeSection(context, preview.volumes[i], i),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _titleCtrl.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _titleCtrl.text.trim()),
                    child: const Text('确认导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _volumeSection(BuildContext context, ImportVolume volume, int index) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = scheme.outlineVariant.withValues(alpha: 0.45);
    final collapsed = _collapsed.contains(index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (index > 0)
          Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: hairline),
        _HoverRow(
          onTap: () => setState(() {
            collapsed ? _collapsed.remove(index) : _collapsed.add(index);
          }),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(children: [
            Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                volume.name,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${volume.chapters.length} 章 · ${_formatCount(volume.charCount)}字',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more,
                  size: 18, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.only(left: 17, bottom: 6),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final chapter in volume.chapters)
                    _HoverRow(
                      padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            chapter.title,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_formatCount(chapter.charCount)}字',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 字数缩写：万字以上按「45.2万」显示，避免长数字撑破行。
  static String _formatCount(int count) {
    if (count < 10000) return '$count';
    final wan = (count / 10000).toStringAsFixed(1);
    return '${wan.endsWith('.0') ? wan.substring(0, wan.length - 2) : wan}万';
  }
}

/// 行悬停底色；传 [onTap] 时同时表现为可点击（手型指针）。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, required this.padding, this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      color: _hovered
          ? scheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      padding: widget.padding,
      child: widget.child,
    );
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? row
          : GestureDetector(onTap: widget.onTap, child: row),
    );
  }
}