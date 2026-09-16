import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// 右键菜单条目。
class AppMenuItem<T> {
  const AppMenuItem(
    this.value,
    this.label, {
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// 危险操作，以错误色（红）显示。
  final bool destructive;
}

/// 在 [globalPosition]（全局坐标）处弹出应用统一风格的右键菜单：
/// 高度 44 的条目、通栏圆角悬停高亮、圆角 8 的悬浮容器
/// （配色/描边由各主题的 popupMenuTheme 决定）。
Future<T?> showAppContextMenu<T>(
  BuildContext context,
  Offset globalPosition,
  List<AppMenuItem<T>> entries,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final items = <PopupMenuEntry<T>>[for (final e in entries) _ItemEntry(e)];
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    constraints: const BoxConstraints(minWidth: 176, maxWidth: 224),
    items: items,
  );
}

/// 编辑器文字菜单的动作条目：视觉字段与 [AppMenuItem] 一致，动作由回调提供。
class AppMenuAction {
  const AppMenuAction(
    this.label, {
    this.icon,
    this.destructive = false,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onTap;
}

/// 编辑器（文字选择）右键菜单构建器：供 QuillEditorConfig.contextMenuBuilder 使用，
/// 与 showAppContextMenu 同一视觉规格。由 flutter_quill 挂载到 root Overlay，
/// Overlay 对非 Positioned 条目施加全屏紧约束，布局代理必须改写为
/// 无界子约束，否则面板会被拉伸铺满屏幕。
/// [secondaryTapPosition] 为最近一次右键按下的全局坐标，非空时菜单
/// 跟随鼠标位置；为空时（拖选/双击等触发）跟随选区锚点。
Widget appEditorContextMenuBuilder(
  BuildContext context,
  QuillRawEditorState state, {
  Offset? secondaryTapPosition,
}) {
  final value = state.textEditingValue;
  final hasSelection = value.selection.isValid && !value.selection.isCollapsed;
  final readOnly = state.widget.config.readOnly;
  final anchors = state.contextMenuAnchors;
  return AppEditorContextMenuPanel(
    primaryAnchor: secondaryTapPosition ?? anchors.primaryAnchor,
    secondaryAnchor: secondaryTapPosition ?? anchors.secondaryAnchor,
    entries: [
      if (hasSelection)
        AppMenuAction(
          '复制',
          icon: Icons.content_copy,
          onTap: () => state.copySelection(SelectionChangedCause.toolbar),
        ),
      if (hasSelection && !readOnly)
        AppMenuAction(
          '剪切',
          icon: Icons.content_cut,
          onTap: () => state.cutSelection(SelectionChangedCause.toolbar),
        ),
      if (!readOnly)
        AppMenuAction(
          '粘贴',
          icon: Icons.content_paste,
          onTap: () => state.pasteText(SelectionChangedCause.toolbar),
        ),
      if (value.text.isNotEmpty)
        AppMenuAction(
          '全选',
          icon: Icons.select_all,
          onTap: () => state.selectAll(SelectionChangedCause.toolbar),
        ),
    ],
    onDismiss: () => state.hideToolbar(),
  );
}

/// 编辑器（文字选择）右键菜单面板：与 showAppContextMenu 同一视觉规格，
/// 由 flutter_quill 的 contextMenuBuilder 挂载到 root Overlay。
/// 外部点击通过 [onDismiss] 关闭（一般调用 raw editor 的 hideToolbar）。
class AppEditorContextMenuPanel extends StatelessWidget {
  const AppEditorContextMenuPanel({
    super.key,
    required this.primaryAnchor,
    required this.entries,
    required this.onDismiss,
    this.secondaryAnchor,
  });

  /// 菜单锚点：优先从 [secondaryAnchor]（选区底部/右键位置）向下展开，
  /// 底部放不下时翻转到 [primaryAnchor]（选区顶部/右键位置）上方。
  final Offset primaryAnchor;
  final Offset? secondaryAnchor;
  final List<AppMenuAction> entries;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final popup = PopupMenuTheme.of(context);
    return CustomSingleChildLayout(
      delegate: _OverlayMenuLayoutDelegate(primaryAnchor, secondaryAnchor),
      // 必须用 TextFieldTapRegion（与编辑器同组），否则鼠标按下菜单项时
      // 编辑器判定“点击在输入区域外”而失焦，postFrame 销毁选区覆盖层
      // （连同本菜单），松开时 InkWell 已不在树上，onTap 永远不触发。
      child: TextFieldTapRegion(
        onTapOutside: (_) => onDismiss(),
        child: Material(
          color: popup.color ?? Theme.of(context).colorScheme.surface,
          elevation: popup.elevation ?? 6,
          shadowColor: popup.shadowColor,
          shape: popup.shape,
          // 与 showAppContextMenu 的 minWidth 一致，保证两处菜单同宽。
          child: SizedBox(
            width: 176,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in entries)
                  _AppMenuRow(
                    label: e.label,
                    icon: e.icon,
                    destructive: e.destructive,
                    onTap: () {
                      e.onTap();
                      onDismiss();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _OverlayMenuLayoutDelegate(this.primaryAnchor, this.secondaryAnchor);

  final Offset primaryAnchor;
  final Offset? secondaryAnchor;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = (size.width - childSize.width - _margin).clamp(
      _margin,
      double.infinity,
    );
    final x = primaryAnchor.dx.clamp(_margin, maxX).toDouble();
    var y = (secondaryAnchor ?? primaryAnchor).dy;
    if (y + childSize.height > size.height - _margin) {
      y = primaryAnchor.dy - childSize.height - _margin;
    }
    return Offset(x, y.clamp(_margin, double.infinity).toDouble());
  }

  @override
  bool shouldRelayout(_OverlayMenuLayoutDelegate oldDelegate) =>
      oldDelegate.primaryAnchor != primaryAnchor ||
      oldDelegate.secondaryAnchor != secondaryAnchor;
}

/// 统一风格的菜单行：高度 44、图标 16 + 9 间距、圆角 5 通栏悬停高亮。
class _AppMenuRow extends StatefulWidget {
  const _AppMenuRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final IconData? icon;
  final bool destructive;
  final VoidCallback onTap;

  @override
  State<_AppMenuRow> createState() => _AppMenuRowState();
}

class _AppMenuRowState extends State<_AppMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destructive = widget.destructive;
    final fg = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    final iconColor = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final hoverColor = destructive
        ? theme.colorScheme.error.withValues(alpha: 0.10)
        : theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return InkWell(
      onTap: widget.onTap,
      onHover: (v) {
        if (v != _hover) setState(() => _hover = v);
      },
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 16, color: iconColor),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEntry<T> extends PopupMenuEntry<T> {
  const _ItemEntry(this.item);

  final AppMenuItem<T> item;

  @override
  double get height => 44;

  @override
  bool represents(T? value) => value == item.value;

  @override
  State<_ItemEntry<T>> createState() => _ItemEntryState<T>();
}

class _ItemEntryState<T> extends State<_ItemEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return _AppMenuRow(
      label: widget.item.label,
      icon: widget.item.icon,
      destructive: widget.item.destructive,
      onTap: () => Navigator.of(context).pop(widget.item.value),
    );
  }
}
