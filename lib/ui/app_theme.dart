import 'package:flutter/material.dart';

/// 应用主题（三选一，顺序即设置里的展示顺序）。
enum AppTheme { nature, glass, chaos }

/// 主题中文名（设置展示、提示共用）。
String appThemeLabel(AppTheme theme) => switch (theme) {
      AppTheme.glass => '玻璃拟态',
      AppTheme.nature => '有机自然',
      AppTheme.chaos => '活力涂鸦',
    };

/// 特征卡片色板条目：各主题按其设计稿呈现不同形态（见 TintedCard）。
class TintedCardStyle {
  const TintedCardStyle({
    required this.background,
    this.backgroundEnd,
    this.blob,
    this.chip,
    this.onChip,
    required this.title,
    required this.body,
  });

  /// 卡片底色。
  final Color background;

  /// 底色渐变终点（仅活力涂鸦主题使用）。
  final Color? backgroundEnd;

  /// 角落装饰色块（null 不绘制）。
  final Color? blob;

  /// 图标章底色（null 显示无底图标）。
  final Color? chip;
  final Color? onChip;

  /// 卡片上的标题/正文文字色。
  final Color title;
  final Color body;
}

/// 主题视觉规格：主题构建与预览卡片共用同一份颜色/形态定义。
class AppThemeSpec {
  const AppThemeSpec({
    required this.brightness,
    required this.background,
    this.backgroundGradient,
    required this.panel,
    required this.panelAlt,
    required this.surfaceOpaque,
    required this.inputFill,
    required this.hairline,
    required this.border,
    required this.borderStrong,
    required this.borderWidth,
    required this.cardRadius,
    required this.buttonRadius,
    required this.text,
    required this.textDim,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.error,
    required this.onError,
    this.cardTints = const [],
    this.featureCardRadius = 24,
  });

  final Brightness brightness;

  /// scaffold 兜底纯色（有渐变时仅作窗口冷启动前的底色）。
  final Color background;

  /// 全屏底层渐变；null 表示纯色背景。
  final Gradient? backgroundGradient;

  /// 渐变上的半透明面板色。
  final Color panel;

  /// 半透明次级面板（输入底、悬停底）。
  final Color panelAlt;

  /// 不透明面板（对话框、菜单——浮在 barrier 上必须自持可读）。
  final Color surfaceOpaque;
  final Color inputFill;
  final Color hairline;
  final Color border;
  final Color borderStrong;
  final double borderWidth;
  final double cardRadius;
  final double buttonRadius;
  final Color text;
  final Color textDim;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;
  final Color error;
  final Color onError;

  /// 特征卡片色板（TintedCard 按 tintIndex 轮换取色）。
  final List<TintedCardStyle> cardTints;

  /// 特征卡片圆角（大于通用 cardRadius，呼应设计稿的大圆角卡片）。
  final double featureCardRadius;
}

AppThemeSpec appThemeSpec(AppTheme theme) => switch (theme) {
      AppTheme.glass => const AppThemeSpec(
          brightness: Brightness.dark,
          // #03 玻璃拟态：紫粉渐变上的白玻璃。
          background: Color(0xFF764BA2),
          backgroundGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2), Color(0xFFF093FB)],
          ),
          panel: Color(0x2EFFFFFF),
          panelAlt: Color(0x1FFFFFFF),
          surfaceOpaque: Color(0xFF3E2D63),
          inputFill: Color(0x26FFFFFF),
          hairline: Color(0x2EFFFFFF),
          border: Color(0x33FFFFFF),
          borderStrong: Color(0x59FFFFFF),
          borderWidth: 1,
          cardRadius: 16,
          buttonRadius: 12,
          text: Colors.white,
          textDim: Color(0xB8FFFFFF),
          primary: Colors.white,
          onPrimary: Color(0xFF6B3FA0),
          accent: Color(0xFFF093FB),
          onAccent: Color(0xFF4A2560),
          error: Color(0xFFFF8A80),
          onError: Color(0xFF3B0A0A),
          // #03 卡片：白玻璃，靠渐变背景透色。
          cardTints: [
            TintedCardStyle(
              background: Color(0x26FFFFFF),
              chip: Color(0x2EFFFFFF),
              onChip: Colors.white,
              title: Colors.white,
              body: Color(0x99FFFFFF),
            ),
          ],
          featureCardRadius: 16,
        ),
      AppTheme.nature => const AppThemeSpec(
          brightness: Brightness.light,
          // #42 有机自然：米色大地底 + 苔绿主色。
          background: Color(0xFFF5F1E8),
          panel: Color(0xFFEDE7DA),
          panelAlt: Color(0xFFE8E0D0),
          surfaceOpaque: Color(0xFFF5F1E8),
          inputFill: Color(0xFFEFE9DC),
          hairline: Color(0xFFE0D8C8),
          border: Color(0xFFE0D8C8),
          borderStrong: Color(0xFFCFC4AC),
          borderWidth: 1,
          cardRadius: 24,
          buttonRadius: 22,
          text: Color(0xFF3E4A32),
          textDim: Color(0xFF8A9A7B),
          primary: Color(0xFF5D6B4D),
          onPrimary: Color(0xFFF5F1E8),
          accent: Color(0xFF8FBC8F),
          onAccent: Color(0xFF24301E),
          error: Color(0xFFB0533C),
          onError: Colors.white,
          // #42 卡片：莫奈花园浅色系 ×10，色相均匀分布，角落有机色块 + 叶形图标章。
          cardTints: [
            TintedCardStyle(
              // 暖沙色
              background: Color(0xFFEDE2D0),
              blob: Color(0x4DDCC8A0),
              chip: Color(0xFFB89A6E),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 蔷薇粉
              background: Color(0xFFEED4D8),
              blob: Color(0x4DDCB0B8),
              chip: Color(0xFFC07B84),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 金盏橘
              background: Color(0xFFF0D8C0),
              blob: Color(0x4DE0B88A),
              chip: Color(0xFFC49660),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 含羞草黄
              background: Color(0xFFF1EBC4),
              blob: Color(0x4DE4D68C),
              chip: Color(0xFFC4B458),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 睡莲绿
              background: Color(0xFFD1E6D4),
              blob: Color(0x4DA3D4A8),
              chip: Color(0xFF6BA878),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 薄荷蓝
              background: Color(0xFFCDE2E8),
              blob: Color(0x4D9ECCD8),
              chip: Color(0xFF689CB0),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 晴空蓝
              background: Color(0xFFD2DAEF),
              blob: Color(0x4DA8B4E0),
              chip: Color(0xFF6E80B8),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 鸢尾紫
              background: Color(0xFFDDD2EF),
              blob: Color(0x4DB8A8E0),
              chip: Color(0xFF8E78C0),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 薰衣草粉
              background: Color(0xFFEDD6F0),
              blob: Color(0x4DD8B0E4),
              chip: Color(0xFFB878C0),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
            TintedCardStyle(
              // 月白
              background: Color(0xFFE8E6DA),
              blob: Color(0x4DD8D4C0),
              chip: Color(0xFFB0AC8C),
              onChip: Colors.white,
              title: Color(0xFF3E4A32),
              body: Color(0xFF5D6B4D),
            ),
          ],
          featureCardRadius: 28,
        ),
      AppTheme.chaos => const AppThemeSpec(
          brightness: Brightness.dark,
          // #57 活力涂鸦：深蓝底 + 霓虹贴纸。
          background: Color(0xFF1A1A2E),
          backgroundGradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF24234A)],
          ),
          panel: Color(0xFF24243E),
          panelAlt: Color(0xFF2C2C4A),
          surfaceOpaque: Color(0xFF24243E),
          inputFill: Color(0xFF2C2C4A),
          hairline: Color(0x33FFFFFF),
          border: Color(0x33FFFFFF),
          borderStrong: Color(0x59FFFFFF),
          borderWidth: 2,
          cardRadius: 20,
          buttonRadius: 22,
          text: Colors.white,
          textDim: Color(0xB3FFFFFF),
          primary: Color(0xFFFF6B6B),
          onPrimary: Colors.white,
          accent: Color(0xFF4ECDC4),
          onAccent: Color(0xFF10221F),
          error: Color(0xFFFF4D6D),
          onError: Colors.white,
          // #57 卡片：霓虹纯色 + 轻旋转 + 硬贴纸投影（TintedCard 绘制）。
          cardTints: [
            TintedCardStyle(
              background: Color(0xFFFF6B6B),
              chip: Color(0x40FFFFFF),
              onChip: Colors.white,
              title: Colors.white,
              body: Color(0xCCFFFFFF),
            ),
            TintedCardStyle(
              background: Color(0xFF4ECDC4),
              backgroundEnd: Color(0xFF95E1D3),
              chip: Color(0x59FFFFFF),
              onChip: Color(0xFF0E2A26),
              title: Color(0xFF0E2A26),
              body: Color(0xB30E2A26),
            ),
            TintedCardStyle(
              background: Color(0xFFFFE66D),
              chip: Color(0x59FFFFFF),
              onChip: Color(0xFF1F2430),
              title: Color(0xFF1F2430),
              body: Color(0xCC1F2430),
            ),
            TintedCardStyle(
              background: Color(0xFFA388EE),
              chip: Color(0x40FFFFFF),
              onChip: Colors.white,
              title: Colors.white,
              body: Color(0xCCFFFFFF),
            ),
          ],
          featureCardRadius: 24,
        ),
      };

/// 统一的主题构建入口。全局文本缩放由 MaterialApp.textScaler 承担，
/// 此处只负责主题配色与界面字体。
ThemeData buildAppTheme(AppTheme theme, {String? fontFamily}) {
  return _buildTheme(appThemeSpec(theme), fontFamily);
}

/// 字体候选（界面与正文共用）：family 为空表示默认回退链。
class FontOption {
  const FontOption(this.label, this.family);
  final String label;
  final String family;
}

const appFontOptions = <FontOption>[
  FontOption('默认', ''),
  FontOption('微软雅黑', 'Microsoft YaHei'),
  FontOption('宋体', 'SimSun'),
  FontOption('楷体', 'KaiTi'),
  FontOption('仿宋', 'FangSong'),
  FontOption('黑体', 'SimHei'),
];

const _fontFallbacks = [
  'Inter',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
];

const _clickCursor = WidgetStatePropertyAll(SystemMouseCursors.click);

ThemeData _buildTheme(AppThemeSpec p, String? fontFamily) {
  final isDark = p.brightness == Brightness.dark;
  // 渐变主题的 scaffold 透明，由 MaterialApp.builder 统一垫渐变背景。
  final scaffoldColor =
      p.backgroundGradient == null ? p.background : Colors.transparent;

  // 依据面板透明度派生的 scheme：半透明面板主题以不透明底色近似，
  // 供仅有 ColorScheme 的下游（如编辑器取色）保持可读。
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.accent,
    onPrimaryContainer: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.panelAlt,
    onSecondaryContainer: p.text,
    tertiary: p.accent,
    onTertiary: p.onAccent,
    error: p.error,
    onError: p.onError,
    // 透明面板下取半透明混合的近似实色，避免下游拿到全透色。
    surface: isDark ? Color.alphaBlend(p.panel, p.background) : p.panel,
    onSurface: p.text,
    surfaceContainerHighest: p.panelAlt,
    onSurfaceVariant: p.textDim,
    outline: p.border,
    outlineVariant: p.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: p.brightness,
    fontFamily: (fontFamily == null || fontFamily.isEmpty)
        ? null
        : fontFamily,
    fontFamilyFallback: _fontFallbacks,
  );

  // 按钮文字统一 14px/w500，从主题派生以携带界面字体。
  final buttonTextStyle = base.textTheme.labelLarge
      ?.copyWith(fontSize: 14, fontWeight: FontWeight.w500);

  final strongSide = BorderSide(color: p.borderStrong, width: p.borderWidth);

  return base.copyWith(
    iconTheme: base.iconTheme.copyWith(size: 18, color: p.text),
    scaffoldBackgroundColor: scaffoldColor,
    splashFactory: NoSplash.splashFactory,
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceOpaque,
      elevation: 6,
      shadowColor: isDark ? const Color(0x66000000) : const Color(0x28000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius),
        side: p.borderWidth > 1 ? strongSide : BorderSide(color: p.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? p.panelAlt
                : p.primary),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? p.textDim : p.onPrimary),
        textStyle: WidgetStatePropertyAll(buttonTextStyle),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.buttonRadius),
            side: p.borderWidth > 1
                ? strongSide
                : BorderSide(color: p.border, width: 1),
          ),
        ),
        side: WidgetStatePropertyAll(
          p.borderWidth > 1
              ? strongSide
              : BorderSide(color: p.border, width: 1),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.25)),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: isDark ? p.text : p.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.buttonRadius),
        ),
        textStyle: buttonTextStyle,
      ).copyWith(mouseCursor: _clickCursor),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: p.borderWidth > 1 ? strongSide : BorderSide(color: p.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.buttonRadius),
        ),
        textStyle: buttonTextStyle,
      ).copyWith(mouseCursor: _clickCursor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? p.panelAlt
                : p.panel),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? p.textDim : p.text),
        textStyle: WidgetStatePropertyAll(buttonTextStyle),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.buttonRadius),
            side: p.borderWidth > 1
                ? strongSide
                : BorderSide(color: p.border, width: 1),
          ),
        ),
        side: WidgetStatePropertyAll(
          p.borderWidth > 1
              ? strongSide
              : BorderSide(color: p.border, width: 1),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.25)),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        // 更紧凑的悬停高亮：不用 M3 的 40x40 最小尺寸。
        minimumSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        highlightColor: p.accent.withValues(alpha: isDark ? 0.30 : 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.buttonRadius - 2),
        ),
        padding: const EdgeInsets.all(5),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.panelAlt;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onPrimary;
          return p.text;
        }),
        side: WidgetStatePropertyAll(
          p.borderWidth > 1 ? strongSide : BorderSide(color: p.border),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.buttonRadius),
          ),
        ),
        visualDensity: VisualDensity.compact,
        elevation: const WidgetStatePropertyAll(0),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    // 卡片：平面化，靠边框与圆角表达形态。
    cardTheme: CardThemeData(
      color: p.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius),
        side: p.borderWidth > 1 ? strongSide : BorderSide(color: p.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius - 4),
        side: BorderSide(color: p.hairline),
      ),
      iconColor: p.textDim,
      selectedColor: isDark ? p.accent : p.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leadingWidth: 42,
      titleSpacing: 0,
      shape: Border(
        bottom: BorderSide(
          color: p.borderWidth > 1 ? p.borderStrong : p.hairline,
          width: p.borderWidth > 1 ? p.borderWidth : 0.5,
        ),
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius - 4),
        side: p.borderWidth > 1 ? strongSide : BorderSide.none,
      ),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: p.borderWidth > 1 ? p.borderStrong : p.hairline,
      thickness: p.borderWidth > 1 ? p.borderWidth : 0.5,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? p.surfaceOpaque : p.primary,
      contentTextStyle: TextStyle(color: p.onPrimary),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.buttonRadius),
        side: p.borderWidth > 1 ? strongSide : BorderSide.none,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.panelAlt,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.3),
      trackHeight: p.borderWidth > 1 ? 6 : 3,
      thumbShape: RoundSliderThumbShape(
        enabledThumbRadius: p.borderWidth > 1 ? 8 : 7,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.inputFill,
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.buttonRadius - 2),
        borderSide: p.borderWidth > 1
            ? strongSide
            : BorderSide(color: p.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.buttonRadius - 2),
        borderSide: p.borderWidth > 1
            ? strongSide
            : BorderSide(color: p.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.buttonRadius - 2),
        borderSide: BorderSide(
          color: isDark ? p.accent : p.primary,
          width: p.borderWidth > 1 ? p.borderWidth : 1.5,
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      color: p.surfaceOpaque,
      elevation: 6,
      shadowColor: isDark ? const Color(0x66000000) : const Color(0x28000000),
      menuPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius - 4),
        side: p.borderWidth > 1 ? strongSide : BorderSide(color: p.hairline),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xE6F5F5F7) : const Color(0xE62C2438),
        border: p.borderWidth > 1 ? Border.all(color: p.accent, width: 1.5) : null,
        borderRadius: BorderRadius.circular(p.buttonRadius - 2),
      ),
      textStyle: TextStyle(
        fontSize: 12,
        color: isDark ? const Color(0xFF24243E) : Colors.white,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: Radius.circular(p.buttonRadius / 4),
      minThumbLength: 36,
      thumbColor: WidgetStatePropertyAll(p.textDim.withValues(alpha: 0.6)),
      trackColor: WidgetStatePropertyAll(p.panelAlt.withValues(alpha: 0.5)),
      trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.panelAlt,
      circularTrackColor: p.panelAlt,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.onPrimary;
        return p.textDim;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.primary;
        return p.panelAlt;
      }),
      trackOutlineColor: WidgetStatePropertyAll(p.borderStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.primary;
        return Colors.transparent;
      }),
      side: BorderSide(color: p.textDim, width: p.borderWidth > 1 ? 2 : 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.borderWidth > 1 ? 4 : 2),
      ),
    ),
  );
}
