import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';

/// 角色卡颜色解析：'#RRGGBB' → Color，非法值返回 null。
Color? parseCharacterColor(String hex) {
  if (hex.isEmpty) return null;
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return null;
  }
}

/// 编辑器角色名悬浮 tip：延迟 300ms 弹出。
/// 单例 OverlayEntry，同一时刻只显示一个。
/// 鼠标离开文本后有 100ms grace period，期间进入 tip 可保持展示。
/// 角色数据变化后自动刷新内容。
void scheduleCharacterTip(
    BuildContext context, Offset globalPosition, Character character, VoidCallback onEdit) {
  _CharacterTipCoordinator.schedule(context, globalPosition, character, onEdit);
}

void cancelCharacterTip() => _CharacterTipCoordinator.scheduleDismiss();

void keepCharacterTipAlive() => _CharacterTipCoordinator.keepAlive();

void dismissCharacterTipNow() => _CharacterTipCoordinator.dismissNow();

class _CharacterTipCoordinator {
  static Timer? _showTimer;
  static Timer? _dismissTimer;
  static OverlayEntry? _entry;

  static void schedule(
      BuildContext context, Offset globalPosition, Character character, VoidCallback onEdit) {
    cancel();
    _showTimer = Timer(const Duration(milliseconds: 300), () {
      _show(context, globalPosition, character, onEdit);
    });
  }

  static void _show(
      BuildContext context, Offset globalPosition, Character character, VoidCallback onEdit) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => _CharacterTipView(
        character: character,
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

  /// 软取消：启动 100ms 延迟，期间进入 tip 可阻止消失。
  static void scheduleDismiss() {
    _showTimer?.cancel();
    _showTimer = null;
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 100), () {
      dismissNow();
    });
  }

  /// 保持存活：取消正在进行的延迟消失。
  static void keepAlive() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  /// 立即硬取消。
  static void dismissNow() {
    cancel();
  }

  static void cancel() {
    _showTimer?.cancel();
    _showTimer = null;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _CharacterTipView extends StatefulWidget {
  const _CharacterTipView({
    required this.character,
    required this.position,
    required this.onEdit,
    required this.onDismiss,
  });

  final Character character;
  final Offset position;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  State<_CharacterTipView> createState() => _CharacterTipViewState();
}

class _CharacterTipViewState extends State<_CharacterTipView> {
  Character? _character;
  AppState? _appState;

  /// 渲染后测得的 tip 实际高度；未测得前 tip 隐藏，避免用估算值定位闪现/跑飞。
  double? _measuredHeight;

  @override
  void initState() {
    super.initState();
    _character = widget.character;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appState = context.read<AppState>();
      _appState!.characterDictVersion.addListener(_refresh);
      // 首次展示强制刷新，避免传递的 Character 对象过时。
      _refresh();
      _measure();
    });
  }

  @override
  void dispose() {
    _appState?.characterDictVersion.removeListener(_refresh);
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
    final char = await s.characters.get(_character!.id);
    if (mounted && char != null) {
      setState(() => _character = char);
      // 内容变化后高度可能变化，下一帧重新测量。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure();
      });
    }
  }

  static const _typeLabels = <CharacterType, String>{
    CharacterType.protagonist: '主角',
    CharacterType.supporting: '配角',
    CharacterType.antagonist: '反派',
    CharacterType.minor: '龙套',
  };

  static const _typeColors = <CharacterType, Color>{
    CharacterType.protagonist: Color(0xFF4A90D9),
    CharacterType.supporting: Color(0xFF7CB342),
    CharacterType.antagonist: Color(0xFFE53935),
    CharacterType.minor: Color(0xFF9E9E9E),
  };

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (t.year == now.year) {
      return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    }
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final char = _character!;
    final color = parseCharacterColor(char.color) ?? scheme.primary;

    // 位置：与文字左对齐、正下方紧贴（无间隙）；
    // 下方空间不足时按实测高度上翻，屏幕边缘钳制。
    const tipWidth = 200.0;
    final tipHeight = _measuredHeight ?? 240.0;
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
        onEnter: (_) => keepCharacterTipAlive(),
        onExit: (_) => widget.onDismiss(),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: tipWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
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
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: AssetImage(
                        char.gender == Gender.female
                            ? 'assets/avatars/female.png'
                            : 'assets/avatars/male.png'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(char.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface)),
                          ),
                          const SizedBox(width: 4),
                          _badge(_typeLabels[char.type] ?? '',
                              _typeColors[char.type] ?? color),
                          const SizedBox(width: 4),
                          Text(char.gender == Gender.female ? '女' : '男',
                              style: TextStyle(
                                  fontSize: 10, color: scheme.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 2),
                        Text('修改于 ${_formatTime(char.updatedAt)}',
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                ]),
                if (char.aliases.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('别名：${char.aliases}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
                if (char.tags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('标签：${char.tags}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
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
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w500, color: color)),
    );
  }
}