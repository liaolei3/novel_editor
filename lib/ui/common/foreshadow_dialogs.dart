import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/foreshadow_tip.dart' show foreshadowMarkColor;
import 'dialogs.dart';

/// 弹窗顶部的「选中文本」手稿引文块：左侧主色竖条 + 浅底，[text] 为空时不展示。
Widget? excerptBlock(String text, BuildContext ctx) {
  if (text.trim().isEmpty) return null;
  final scheme = Theme.of(ctx).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(8),
    ),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: scheme.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('选中文本',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(text.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: scheme.onSurface.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 新建伏笔对话框 → (名称, 伏笔描述, 首片段备注)。名称与伏笔描述均为必填。
/// [showRemark] 为 false 时仅输入名称与内容
///（面板新建场景：尚无片段，备注无处归属）。
/// [excerpt] 为选中文本摘要，非空时在顶部展示。
Future<(String, String, String)?> showCreateForeshadowDialog(
    BuildContext context,
    {bool showRemark = true, String excerpt = ''}) {
  final nameCtrl = TextEditingController();
  final contentCtrl = TextEditingController();
  final remarkCtrl = TextEditingController();
  return showDialog<(String, String, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return DraggableDialog(
      child: AlertDialog(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 480),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        title: const Text('新建伏笔',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (excerptBlock(excerpt, ctx) != null) ...[
              excerptBlock(excerpt, ctx)!,
              const SizedBox(height: 16),
            ],
            // 名称即伏笔的标题：无框大字输入，与下方正文区分层。
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '伏笔名称',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: contentCtrl,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: scheme.onSurface),
              decoration: InputDecoration(
                labelText: '伏笔描述（必填）',
                alignLabelWithHint: true,
                labelStyle: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
                hintStyle: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                hintText: '埋了什么、打算怎么回收…',
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              ),
            ),
            if (showRemark) ...[
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                minLines: 2,
                maxLines: 4,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: scheme.onSurface),
                decoration: InputDecoration(
                  labelText: '片段备注（可选）',
                  alignLabelWithHint: true,
                  labelStyle: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                  hintStyle: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  hintText: '这次标注需要记下的话…',
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameCtrl,
            builder: (ctx, _, _) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: contentCtrl,
              builder: (ctx, _, _) {
                final enabled = nameCtrl.text.trim().isNotEmpty &&
                    contentCtrl.text.trim().isNotEmpty;
                return FilledButton(
                  onPressed: enabled
                      ? () => Navigator.pop(
                          ctx,
                          (nameCtrl.text.trim(), contentCtrl.text.trim(),
                              remarkCtrl.text.trim()))
                      : null,
                  child: const Text('创建'),
                );
              },
            ),
          ),
        ],
      ),
      );
    },
  );
}

/// 关联伏笔对话框：左侧搜索选择伏笔，右侧展示所选详情并填写片段备注
/// → (伏笔, 片段备注)。[excerpt] 为选中文本摘要，非空时在顶部展示。
Future<(Foreshadow, String)?> showLinkForeshadowDialog(
    BuildContext context, String bookId,
    {String excerpt = ''}) {
  final searchCtrl = TextEditingController();
  final remarkCtrl = TextEditingController();
  List<Foreshadow> all = [];
  var loaded = false;
  Foreshadow? selected;

  return showDialog<(Foreshadow, String)>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> load() async {
          final list =
              await context.read<AppState>().foreshadows.listByBook(bookId);
          if (!ctx.mounted) return;
          setDialogState(() {
            // 已完成伏笔无需再关联新片段，列表仅展示未完成。
            all = list
                .where((f) => f.status == ForeshadowStatus.undone)
                .toList();
            loaded = true;
          });
        }

        if (!loaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) => load());
        }

        final scheme = Theme.of(ctx).colorScheme;
        final kw = searchCtrl.text.trim().toLowerCase();
        final filtered = kw.isEmpty
            ? all
            : all.where((f) => f.name.toLowerCase().contains(kw)).toList();

        return DraggableDialog(
          child: AlertDialog(
            constraints: const BoxConstraints(minWidth: 560, maxWidth: 560),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            title: const Text('关联伏笔',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (excerptBlock(excerpt, ctx) != null) ...[
                  excerptBlock(excerpt, ctx)!,
                  const SizedBox(height: 12),
                ],
                SizedBox(
              width: 512,
              height: 340,
              child: !loaded
                  ? Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 左列：搜索 + 伏笔列表（固定宽度，内部滚动）
                        SizedBox(
                          width: 224,
                          child: Column(
                            children: [
                              TextField(
                                controller: searchCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  hintText: '搜索伏笔名称',
                                  hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant),
                                  prefixIcon:
                                      const Icon(Icons.search, size: 16),
                                  prefixIconConstraints: const BoxConstraints(
                                      minWidth: 34, minHeight: 34),
                                  isDense: true,
                                  filled: true,
                                  fillColor: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: scheme.outlineVariant
                                            .withValues(alpha: 0.6)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                        color: scheme.outlineVariant
                                            .withValues(alpha: 0.6)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: filtered.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.flag_outlined,
                                                size: 32,
                                                color: scheme.onSurfaceVariant
                                                    .withValues(alpha: 0.4)),
                                            const SizedBox(height: 6),
                                            Text(
                                                all.isEmpty
                                                    ? '本书还没有伏笔\n先在正文中选中文字新建伏笔'
                                                    : '无匹配结果',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    height: 1.5,
                                                    color: scheme
                                                        .onSurfaceVariant)),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        itemCount: filtered.length,
                                        itemBuilder: (ctx2, i) {
                                          final f = filtered[i];
                                          final color = foreshadowMarkColor(
                                              f.status,
                                              Theme.of(ctx2).brightness);
                                          final isSelected =
                                              selected?.id == f.id;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Material(
                                              color: isSelected
                                                  ? scheme.primary
                                                      .withValues(alpha: 0.08)
                                                  : scheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.4),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                side: BorderSide(
                                                    width: isSelected
                                                        ? 1.4
                                                        : 1.0,
                                                    color: isSelected
                                                        ? scheme.primary
                                                        : scheme.outlineVariant
                                                            .withValues(
                                                                alpha: 0.5)),
                                              ),
                                              child: InkWell(
                                                mouseCursor:
                                                    SystemMouseCursors.click,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: () => setDialogState(
                                                    () => selected = f),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 9),
                                                  child: Row(children: [
                                                    Icon(Icons.flag_outlined,
                                                        size: 15,
                                                        color: color),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(f.name,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  isSelected
                                                                      ? FontWeight
                                                                          .w600
                                                                      : FontWeight
                                                                          .w400,
                                                              color: isSelected
                                                                  ? scheme
                                                                      .primary
                                                                  : scheme
                                                                      .onSurface)),
                                                    ),
                                                    if (isSelected) ...[
                                                      const SizedBox(width: 6),
                                                      Icon(Icons.check,
                                                          size: 14,
                                                          color:
                                                              scheme.primary),
                                                    ],
                                                  ]),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 右列：所选伏笔详情 + 片段备注（与选择联动，消除割裂）
                        Expanded(
                          child: Container(
                            padding:
                                const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.6)),
                            ),
                            child: selected == null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.flag_outlined,
                                            size: 32,
                                            color: scheme.onSurfaceVariant
                                                .withValues(alpha: 0.4)),
                                        const SizedBox(height: 8),
                                        Text('在左侧选择要关联的伏笔',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: scheme
                                                    .onSurfaceVariant)),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Icon(Icons.flag_outlined,
                                            size: 16,
                                            color: foreshadowMarkColor(
                                                selected!.status,
                                                scheme.brightness)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(selected!.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      scheme.onSurface)),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: foreshadowMarkColor(
                                                    selected!.status,
                                                    scheme.brightness)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                              selected!.status ==
                                                      ForeshadowStatus.done
                                                  ? '已完成'
                                                  : '未完成',
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  color: foreshadowMarkColor(
                                                      selected!.status,
                                                      scheme.brightness))),
                                        ),
                                      ]),
                                      const SizedBox(height: 10),
                                      // 伏笔描述只读展示，过长时区域内滚动。
                                      Flexible(
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: scheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.25),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: SingleChildScrollView(
                                            child: Text(
                                                selected!.content.isEmpty
                                                    ? '暂无描述'
                                                    : selected!.content,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    height: 1.5,
                                                    color: selected!.content
                                                            .isEmpty
                                                        ? scheme
                                                            .onSurfaceVariant
                                                        : scheme.onSurface
                                                            .withValues(
                                                                alpha: 0.85))),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text('片段备注（可选）',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  scheme.onSurfaceVariant)),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: TextField(
                                          controller: remarkCtrl,
                                          expands: true,
                                          maxLines: null,
                                          textAlignVertical:
                                              TextAlignVertical.top,
                                          style:
                                              const TextStyle(fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText:
                                                '记录该片段与伏笔的关联说明…',
                                            hintStyle: TextStyle(
                                                fontSize: 12,
                                                color: scheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.6)),
                                            filled: true,
                                            fillColor: scheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.25),
                                            contentPadding:
                                                const EdgeInsets.all(10),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                  color: scheme.outlineVariant
                                                      .withValues(
                                                          alpha: 0.6)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: BorderSide(
                                                  color: scheme.outlineVariant
                                                      .withValues(
                                                          alpha: 0.6)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () =>
                        Navigator.pop(ctx, (selected!, remarkCtrl.text.trim())),
                child: const Text('确认'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 编辑片段备注对话框 → 新备注文本。
Future<String?> showEditSegmentRemarkDialog(
    BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: AlertDialog(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
        title: const Text('编辑片段备注',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '该剧情片段的备注',
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
