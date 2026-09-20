import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';

/// 主题特征卡片：无边框彩底，各主题按其设计稿呈现不同形态——
/// 有机自然：磨砂色底（半透明 + 背景模糊）+ 角落有机圆块 + 叶形图标章；
/// 玻璃拟态：半透明白玻璃 + 细白描边；
/// 活力涂鸦：霓虹纯色 + 轻旋转 + 硬贴纸投影（弱化时转幽灵卡）。
class TintedCard extends StatefulWidget {
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
  State<TintedCard> createState() => _TintedCardState();
}

class _TintedCardState extends State<TintedCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final theme = context.watch<SettingsController>().theme;
    final spec = appThemeSpec(theme);
    final tint = spec.cardTints[widget.tintIndex % spec.cardTints.length];

    final BorderRadius radius = BorderRadius.circular(
      widget.emphasized ? spec.featureCardRadius : spec.cardRadius,
    );

    BoxDecoration decoration = switch (theme) {
      AppTheme.nature => BoxDecoration(
          color: tint.background.withValues(alpha: 0.72),
          borderRadius: radius,
        ),
      AppTheme.glass => BoxDecoration(
          color: tint.background,
          borderRadius: radius,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
      AppTheme.chaos => widget.emphasized
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
        if (widget.emphasized && theme == AppTheme.nature && tint.blob != null)
          Positioned(
            top: widget.tintIndex.isEven ? -36 : null,
            left: widget.tintIndex.isEven ? null : -36,
            right: widget.tintIndex.isEven ? null : -36,
            bottom: widget.tintIndex.isEven ? null : -36,
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
          padding: widget.padding,
          child: widget.child ?? _featureContent(theme, spec, tint),
        ),
      ],
    );

    // 有机自然磨砂：先模糊卡片下层内容，再叠半透明彩底。
    card = ClipRRect(
      borderRadius: radius,
      child: theme == AppTheme.nature
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: card,
            )
          : card,
    );
    card = DecoratedBox(decoration: decoration, child: card);

    // 悬浮时用前景外投影增强层次。
    // 有机自然卡片底色半透明且经 BackdropFilter 磨砂，BoxShadow 画在卡片
    // 后面会透出使整卡变暗，因此统一以前景自绘方式绘制，内部抠掉不渗色。
    if (_hovering) {
      card = CustomPaint(
        foregroundPainter: _EdgeShadowPainter(radius: radius),
        child: card,
      );
    }

    // 涂鸦主题特征卡轻旋转（±0.9°），呼应贴纸感。
    if (widget.emphasized && theme == AppTheme.chaos) {
      card = Transform.rotate(
        angle: widget.tintIndex.isEven ? 0.016 : -0.016,
        child: card,
      );
    }

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: card,
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
      AppTheme.glass => BorderRadius.circular(12),
      AppTheme.chaos => BorderRadius.circular(12),
    };
    final chipDecoration = switch (theme) {
      AppTheme.nature => BoxDecoration(color: tint.chip, borderRadius: chipShape),
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
        if (widget.icon != null)
          Container(
            width: 46,
            height: 46,
            decoration: chipDecoration,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 22, color: tint.onChip),
          ),
        if (widget.title != null) ...[
          SizedBox(height: widget.icon != null ? 14 : 0),
          Text(
            widget.title!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: tint.title,
            ),
          ),
        ],
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.subtitle!,
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

/// 悬浮外投影：先画模糊填充阴影，再抠掉卡片矩形内部，
/// 阴影只留在卡片外围——与常规 BoxShadow 视觉一致，但不渗入半透明卡底。
class _EdgeShadowPainter extends CustomPainter {
  _EdgeShadowPainter({required this.radius});

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).inflate(24);
    final cardRect = (Offset.zero & size).shift(const Offset(0, 2));
    final shadowRRect = radius.toRRect(cardRect).inflate(3);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRRect(
      shadowRRect,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..color = const Color(0x33000000),
    );
    // 抠掉卡片本体区域，避免阴影透过半透明底。
    canvas.drawRRect(
      radius.toRRect(Offset.zero & size),
      Paint()..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeShadowPainter oldDelegate) => oldDelegate.radius != radius;
}
