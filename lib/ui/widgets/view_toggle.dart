import 'package:flutter/material.dart';

/// 面板顶部的视图切换按钮组：网格 / 列表。
class ViewToggleGroup extends StatelessWidget {
  const ViewToggleGroup({super.key, required this.gridView, required this.onChanged});

  final bool gridView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button({
      required IconData icon,
      required String tooltip,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(
                icon,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(
        icon: Icons.grid_view_outlined,
        tooltip: '网格视图',
        selected: gridView,
        onTap: () => onChanged(true),
      ),
      const SizedBox(width: 4),
      button(
        icon: Icons.view_list_outlined,
        tooltip: '列表视图',
        selected: !gridView,
        onTap: () => onChanged(false),
      ),
    ]);
  }
}
