import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';

/// 主题特征卡片：无边框彩底，各主题按其设计稿呈现不同形态——
/// 有机自然：色底 + 角落有机圆块 + 叶形图标章；
/// 黏土拟态：四色渐变 + 白描边 + 厚偏移投影；
/// 玻璃拟态：半透明白玻璃 + 细白描边；
/// 活力涂鸦：霓虹纯色 + 轻旋转 + 硬贴纸投影（弱化时转幽灵卡）。
class TintedCard extends StatelessWidget {
  const TintedCard({
    super.key,
    this.tintIndex = 0,
    this.emphasized = true,
    this.icon,
    this.title,
    this.subtitle,
    this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  /// 色板轮换索引。
  final int tintIndex;

  /// false 时弱化装饰（nature 去角落色块、chaos 转幽灵卡），用于密集数据卡。
  final bool emphasized;

  final IconData? icon;
  final String? title;
  final String? subtitle;

  /// 自定义内容（替代 icon/title/subtitle 的特征布局）。
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// 当前主题下的卡片文字色（title, body），供自定义内容取色。
  static (Color, Color) textColorsOf(BuildContext context, {int tintIndex = 0}) {
    final spec = appThemeSpec(context.watch<SettingsController>().theme);
    final tint = spec.cardTints[tintIndex % spec.cardTints.length];
    return (tint.title, tint.body);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SettingsController>().theme;
    final spec = appThemeSpec(theme);
    final tint = spec.cardTints[tintIndex % spec.cardTints.length];

    final BorderRadius radius = BorderRadius.circular(
      emphasized ? spec.featureCardRadius : spec.cardRadius,
    );

    BoxDecoration decoration = switch (theme) {
      AppTheme.nature => BoxDecoration(
          color: tint.background,
          borderRadius: radius,
        ),
      AppTheme.clay => BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint.background, tint.backgroundEnd ?? tint.background],
          ),
          borderRadius: radius,
          border: Border.all(color: const Color(0x80FFFFFF), width: 3),
          boxShadow: [
            BoxShadow(
              offset: emphasized ? const Offset(8, 8) : const Offset(5, 5),
              color: tint.background.withValues(alpha: emphasized ? 0.5 : 0.35),
            ),
          ],
        ),
      AppTheme.glass => BoxDecoration(
          color: tint.background,
          borderRadius: radius,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
      AppTheme.chaos => emphasized
          ? BoxDecoration(
              color: tint.background,
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(
                  offset: Offset(3, 3),
                  color: Color(0x4D000000),
                ),
              ],
            )
          : BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: radius,
              border: Border.all(color: const Color(0x33FFFFFF), width: 1.5),
            ),
    };

    Widget card = Stack(
      children: [
        if (emphasized && theme == AppTheme.nature && tint.blob != null)
          Positioned(
            top: tintIndex.isEven ? -36 : null,
            left: tintIndex.isEven ? null : -36,
            right: tintIndex.isEven ? null : -36,
            bottom: tintIndex.isEven ? null : -36,
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                // 近似 organic-shape（30% 70% 70% 30% / 30% 30% 70% 70%）。
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(38),
                  topRight: Radius.circular(64),
                  bottomRight: Radius.circular(90),
                  bottomLeft: Radius.circular(64),
                ),
                color: tint.blob,
              ),
            ),
          ),
        Padding(
          padding: padding,
          child: child ?? _featureContent(theme, spec, tint),
        ),
      ],
    );

    card = ClipRRect(borderRadius: radius, child: card);
    card = DecoratedBox(decoration: decoration, child: card);

    // 涂鸦主题特征卡轻旋转（±0.9°），呼应贴纸感。
    if (emphasized && theme == AppTheme.chaos) {
      card = Transform.rotate(
        angle: tintIndex.isEven ? 0.016 : -0.016,
        child: card,
      );
    }

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: radius, onTap: onTap, child: card),
      ),
    );
  }

  /// 特征布局：图标章 + 标题 + 副文案（参考各设计稿的 Feature Cards）。
  Widget _featureContent(
    AppTheme theme,
    AppThemeSpec spec,
    TintedCardStyle tint,
  ) {
    final chipShape = switch (theme) {
      // 近似 leaf-shape（5% 95% 10% 90% / 85% 15% 85% 15%）。
      AppTheme.nature => BorderRadius.only(
          topLeft: const Radius.circular(4),
          topRight: Radius.circular(spec.featureCardRadius - 8),
          bottomRight: const Radius.circular(6),
          bottomLeft: Radius.circular(spec.featureCardRadius - 8),
        ),
      AppTheme.clay => BorderRadius.circular(16),
      AppTheme.glass => BorderRadius.circular(12),
      AppTheme.chaos => BorderRadius.circular(12),
    };
    final chipDecoration = switch (theme) {
      AppTheme.nature => BoxDecoration(color: tint.chip, borderRadius: chipShape),
      AppTheme.clay => BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFE6E6E6)],
          ),
          borderRadius: chipShape,
          border: Border.all(color: const Color(0xCCFFFFFF), width: 3),
          boxShadow: const [
            BoxShadow(offset: Offset(4, 4), color: Color(0x14000000)),
          ],
        ),
      AppTheme.glass => BoxDecoration(
          color: tint.chip,
          borderRadius: chipShape,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
      AppTheme.chaos => BoxDecoration(color: tint.chip, borderRadius: chipShape),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Container(
            width: 46,
            height: 46,
            decoration: chipDecoration,
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: tint.onChip),
          ),
        if (title != null) ...[
          SizedBox(height: icon != null ? 14 : 0),
          Text(
            title!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: tint.title,
            ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: tint.body,
            ),
          ),
        ],
      ],
    );
  }
}
