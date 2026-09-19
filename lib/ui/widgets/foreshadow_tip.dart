import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../common/dialogs.dart' show DraggableDialog;
import 'toast.dart';

/// 伏笔标注色：未完成红 / 已完成绿，暗色主题用亮色变体。
Color foreshadowMarkColor(ForeshadowStatus status, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (status) {
    ForeshadowStatus.undone => dark ? const Color(0xFFFF6B6B) : const Color(0xFFD32F2F),
    ForeshadowStatus.done => dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32),
  };
}

/// 编辑器伏笔标注悬浮 tip：延迟 300ms 弹出，单例 OverlayEntry，
/// 鼠标进入 tip 有 100ms grace period；数据变化后自动刷新内容。
void scheduleForeshadowTip(
    BuildContext context,
    Offset globalPosition,
    Foreshadow foreshadow,
    ForeshadowSegment segment,
    VoidCallback onEdit) {
  _ForeshadowTipCoordinator.schedule(
      context, globalPosition, foreshadow, segment, onEdit);
}

void cancelForeshadowTip() => _ForeshadowTipCoordinator.scheduleDismiss();

class _ForeshadowTipCoordinator {
  static Timer? _showTimer;
  static Timer? _dismissTimer;
  static OverlayEntry? _entry;

  /// 弹出时的锚点 context（编辑器侧），tip 移除后弹确认框仍需使用。
  static BuildContext? _anchorContext;

  static void schedule(BuildContext context, Offset globalPosition,
      Foreshadow foreshadow, ForeshadowSegment segment, VoidCallback onEdit) {
    cancel();
    _showTimer = Timer(const Duration(milliseconds: 300), () {
      _show(context, globalPosition, foreshadow, segment, onEdit);
    });
  }

  static void _show(BuildContext context, Offset globalPosition,
      Foreshadow foreshadow, ForeshadowSegment segment, VoidCallback onEdit) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _anchorContext = context;
    _entry = OverlayEntry(
      builder: (_) => _ForeshadowTipView(
        foreshadowId: foreshadow.id,
        segmentId: segment.id,
        position: globalPosition,
        onEdit: () {
          dismissNow();
          onEdit();
        },
        onDismiss: dismissNow,
      ),
    );
    overlay.insert(_entry!);
  }

  static void scheduleDismiss() {
    _showTimer?.cancel();
    _showTimer = null;
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 100), () {
      dismissNow();
    });
  }

  static void dismissNow() {
    cancel();
  }

  /// 保持存活：取消正在进行的延迟消失。
  static void keepAlive() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  static void cancel() {
    _showTimer?.cancel();
    _showTimer = null;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _entry?.remove();
    _entry = null;
    _anchorContext = null;
  }
}

class _ForeshadowTipView extends StatefulWidget {
  const _ForeshadowTipView({
    required this.foreshadowId,
    required this.segmentId,
    required this.position,
    required this.onEdit,
    required this.onDismiss,
  });

  final String foreshadowId;
  final String segmentId;
  final Offset position;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  State<_ForeshadowTipView> createState() => _ForeshadowTipViewState();
}

class _ForeshadowTipViewState extends State<_ForeshadowTipView> {
  Foreshadow? _foreshadow;
  ForeshadowSegment? _segment;

  /// 同一伏笔下除当前片段外的其他关联片段（缩略展示）。
  List<ForeshadowSegment> _otherSegments = [];
  AppState? _appState;

  double? _measuredHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appState = context.read<AppState>();
      _appState!.foreshadowVersion.addListener(_refresh);
      _refresh();
    });
  }

  @override
  void dispose() {
    _appState?.foreshadowVersion.removeListener(_refresh);
    super.dispose();
  }

  void _measure() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (box.size.height != _measuredHeight) {
      setState(() => _measuredHeight = box.size.height);
    }
  }

  Future<void> _refresh() async {
    final s = _appState;
    if (s == null) return;
    final fs = await s.foreshadows.get(widget.foreshadowId);
    final seg = await s.fsSegments.get(widget.segmentId);
    if (fs == null) {
      // 伏笔已被删除：关闭 tip。
      _ForeshadowTipCoordinator.dismissNow();
      return;
    }
    final all = await s.fsSegments.listByForeshadow(widget.foreshadowId);
    if (mounted) {
      setState(() {
        _foreshadow = fs;
        _segment = seg;
        _otherSegments =
            all.where((e) => e.id != widget.segmentId).toList();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure();
      });
    }
  }

  /// tip 内直接切换完成状态；foreshadowVersion 自增同步刷新编辑器标注色。
  Future<void> _toggleStatus() async {
    final s = _appState;
    final fs = _foreshadow;
    if (s == null || fs == null) return;
    fs.status = fs.status == ForeshadowStatus.done
        ? ForeshadowStatus.undone
        : ForeshadowStatus.done;
    await s.saveForeshadow(fs);
    s.foreshadowVersion.value++;
    if (mounted) showToast(context, '状态修改成功');
  }

  /// 点击其他片段卡片：关闭 tip 并跳转至该片段在正文中的位置。
  Future<void> _jumpToSegment(ForeshadowSegment seg) async {
    final s = _appState;
    if (s == null) return;
    _ForeshadowTipCoordinator.dismissNow();
    await s.jumpToSegment(seg);
  }

  /// 解除当前片段关联：点击后 tip 立即消失，再二次确认（正文标注同时清除）。
  Future<void> _unlinkSegment() async {
    final s = _appState;
    final seg = _segment;
    if (s == null || seg == null) return;
    final dialogCtx = _ForeshadowTipCoordinator._anchorContext;
    if (dialogCtx == null || !dialogCtx.mounted) return;
    _ForeshadowTipCoordinator.dismissNow();
    final confirmed = await showDialog<bool>(
      context: dialogCtx,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
          title: const Text('解除关联',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Text('确定解除该片段与伏笔的关联吗？正文中的标注将同时清除。',
              style: const TextStyle(fontSize: 13, height: 1.5)),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.errorContainer,
                    foregroundColor:
                        Theme.of(ctx).colorScheme.onErrorContainer),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('解除')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await s.removeSegment(seg);
    if (dialogCtx.mounted) showToast(dialogCtx, '解除关联成功');
  }

  String _chapterTitle(String chapterId) {
    final ch = _appState?.chapterList
        .where((c) => c.id == chapterId)
        .firstOrNull;
    return ch?.title ?? '章节已删除';
  }

  String _volumeTitle(String chapterId) {
    final ch = _appState?.chapterList
        .where((c) => c.id == chapterId)
        .firstOrNull;
    if (ch == null) return '';
    final vol = _appState?.volumeTree
        .where((v) => v.id == ch.volumeId)
        .firstOrNull;
    return vol?.name ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final fs = _foreshadow;
    if (fs == null) return const SizedBox.shrink();
    final seg = _segment;
    final color = foreshadowMarkColor(fs.status, scheme.brightness);

    const tipWidth = 300.0;
    final tipHeight = _measuredHeight ?? 200.0;
    final measured = _measuredHeight != null;
    var left = widget.position.dx;
    if (left + tipWidth > size.width - 8) left = widget.position.dx - tipWidth;
    left = left.clamp(8.0, size.width - tipWidth - 8);
    var top = widget.position.dy;
    if (top + tipHeight > size.height - 8) top = widget.position.dy - tipHeight;
    top = top.clamp(8.0, size.height - tipHeight - 8);

    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: measured ? 1.0 : 0.0,
        child: MouseRegion(
          onEnter: (_) => _ForeshadowTipCoordinator.keepAlive(),
          onExit: (_) => widget.onDismiss(),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: tipWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.edit, size: 15, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(fs.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                    ),
                    const SizedBox(width: 4),
                    _statusBadge(fs.status, color),
                  ]),
                  const SizedBox(height: 6),
                  Text(fs.content.isEmpty ? '暂无描述' : '伏笔描述：${fs.content}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: fs.content.isEmpty
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface.withValues(alpha: 0.85))),
                  const SizedBox(height: 6),
                  Text(seg?.remark.isNotEmpty ?? false
                          ? '片段备注：${seg!.remark}'
                          : '片段备注：暂无',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: seg?.remark.isNotEmpty ?? false
                              ? scheme.onSurface.withValues(alpha: 0.85)
                              : scheme.onSurfaceVariant)),
                  if (_otherSegments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('其他片段（${_otherSegments.length}）',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    ..._otherSegments.map(
                      (s) => _SegmentJumpCard(
                        segment: s,
                        location:
                            '${_volumeTitle(s.chapterId)} · ${_chapterTitle(s.chapterId)}',
                        onTap: () => _jumpToSegment(s),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: OutlinedButton(
                          onPressed: _unlinkSegment,
                          style: OutlinedButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 11),
                            padding: EdgeInsets.zero,
                            foregroundColor: scheme.error,
                            side: BorderSide(
                                color: scheme.error.withValues(alpha: 0.4)),
                          ),
                          child: const Text('解除关联'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: FilledButton.tonal(
                          onPressed: widget.onEdit,
                          style: FilledButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 11),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('编辑'),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 状态徽章可点击：直接切换完成状态。
  Widget _statusBadge(ForeshadowStatus status, Color color) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(3),
      onTap: _toggleStatus,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(status == ForeshadowStatus.done ? '已完成' : '未完成',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w500, color: color)),
      ),
    );
  }
}

/// tip 内可点击跳转的其他片段卡片：hover 高亮 + 行尾右三角，提示可点击。
class _SegmentJumpCard extends StatefulWidget {
  const _SegmentJumpCard({
    required this.segment,
    required this.location,
    required this.onTap,
  });

  final ForeshadowSegment segment;
  final String location;
  final VoidCallback onTap;

  @override
  State<_SegmentJumpCard> createState() => _SegmentJumpCardState();
}

class _SegmentJumpCardState extends State<_SegmentJumpCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hover
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: _hover
                    ? scheme.primary.withValues(alpha: 0.4)
                    : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(widget.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary.withValues(alpha: 0.8))),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 13,
                    color: _hover
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ]),
              const SizedBox(height: 2),
              Text(
                widget.segment.excerpt.isEmpty
                    ? '（无内容）'
                    : widget.segment.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: scheme.onSurface.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
