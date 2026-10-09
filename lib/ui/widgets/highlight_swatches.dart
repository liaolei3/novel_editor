import 'package:flutter/material.dart';

/// 文字/对话高亮色板（亮色主题）：文档统一存亮色规范值。
const List<Color> highlightLightSwatches = [
  Color(0xFFFFEB3B), // 亮黄
  Color(0xFFFFB74D), // 橙
  Color(0xFFE57373), // 红
  Color(0xFFF48FB1), // 粉
  Color(0xFFBA68C8), // 紫
  Color(0xFF64B5F6), // 蓝
  Color(0xFF4DB6AC), // 青
  Color(0xFF81C784), // 绿
  Color(0xFFAED581), // 黄绿
];

/// 高亮色板（暗色主题）：同色相的深色变体，浅色文字下均可读。
const List<Color> highlightDarkSwatches = [
  Color(0xFFF9A825), // 亮黄
  Color(0xFFB26A00), // 橙
  Color(0xFFC62828), // 红
  Color(0xFFAD1457), // 粉
  Color(0xFF6A1B9A), // 紫
  Color(0xFF1565C0), // 蓝
  Color(0xFF00695C), // 青
  Color(0xFF2E7D32), // 绿
  Color(0xFF558B2F), // 黄绿
];

/// 暗色主题下换用深色变体色板，保证主题文字颜色在底色上可读。
List<Color> highlightPaletteFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? highlightDarkSwatches
        : highlightLightSwatches;

/// 规范存储色 → 当前主题显示色（亮色 i ↔ 暗色 i 双向对应）。
Color themeSwatchOf(Color canonical, Brightness brightness) {
  final i = highlightLightSwatches.indexOf(canonical);
  if (i < 0) return canonical;
  return brightness == Brightness.dark
      ? highlightDarkSwatches[i]
      : highlightLightSwatches[i];
}

/// 显示色 → 亮色规范存储值（暗色色板色转对应亮色；非色板色原样返回）。
Color canonicalSwatchOf(Color display) {
  if (highlightLightSwatches.contains(display)) return display;
  final i = highlightDarkSwatches.indexOf(display);
  if (i >= 0) return highlightLightSwatches[i];
  return display;
}

/// 把颜色编码为 Quill 背景属性使用的 #rrggbb 十六进制字符串。
String highlightHex(Color c) {
  String channel(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}

/// 解析 #rrggbb 十六进制为颜色；格式不符返回 null。
Color? colorFromHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// 高亮色块：紧凑小方块，选中态为主题色描边加对号。
class HighlightSwatchCell extends StatelessWidget {
  const HighlightSwatchCell({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 24,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.black26, width: 0.5),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: size / 2,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

/// 清除高亮格（色板末位）：与色块同尺寸的空心格，无高亮时置灰。
class HighlightClearCell extends StatelessWidget {
  const HighlightClearCell({
    super.key,
    required this.enabled,
    required this.onTap,
    this.size = 24,
  });

  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: onSurface.withValues(alpha: enabled ? 0.6 : 0.15),
          ),
        ),
        child: Icon(
          Icons.format_color_reset,
          size: size * 2 / 3,
          color: onSurface.withValues(alpha: enabled ? 0.8 : 0.2),
        ),
      ),
    );
  }
}
