import 'package:flutter/material.dart';

/// 下划线式文字 Tab（角色 / 伏笔面板与全局搜索弹窗共用）。
/// [count] 非空时在标签右侧显示数量（如「正文 12」）。
class UnderlineTab extends StatelessWidget {
  const UnderlineTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: count == null
            ? Text(label, style: _labelStyle(scheme))
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(label, style: _labelStyle(scheme)),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  TextStyle _labelStyle(ColorScheme scheme) => TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
      );
}