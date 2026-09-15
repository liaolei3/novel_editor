import 'package:flutter/material.dart';

/// 应用主题（三选一）。
enum AppTheme { light, dark, pixel }

/// 统一的主题构建入口：主题 x 字号缩放。
ThemeData buildAppTheme(AppTheme theme, double fontScale) {
  final data = switch (theme) {
    AppTheme.light => _minimalTheme(Brightness.light),
    AppTheme.dark => _minimalTheme(Brightness.dark),
    AppTheme.pixel => _pixelTheme(),
  };
  return data.copyWith(textTheme: _scaleTextTheme(data.textTheme, fontScale));
}

TextTheme _scaleTextTheme(TextTheme t, double factor) {
  TextStyle? scale(TextStyle? s) {
    if (s == null || s.fontSize == null) return s;
    return s.copyWith(fontSize: s.fontSize! * factor);
  }

  return t.copyWith(
    displayLarge: scale(t.displayLarge),
    displayMedium: scale(t.displayMedium),
    displaySmall: scale(t.displaySmall),
    headlineLarge: scale(t.headlineLarge),
    headlineMedium: scale(t.headlineMedium),
    headlineSmall: scale(t.headlineSmall),
    titleLarge: scale(t.titleLarge),
    titleMedium: scale(t.titleMedium),
    titleSmall: scale(t.titleSmall),
    bodyLarge: scale(t.bodyLarge),
    bodyMedium: scale(t.bodyMedium),
    bodySmall: scale(t.bodySmall),
    labelLarge: scale(t.labelLarge),
    labelMedium: scale(t.labelMedium),
    labelSmall: scale(t.labelSmall),
  );
}

const _fontFallbacks = [
  'Inter',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
];

const _clickCursor = WidgetStatePropertyAll(SystemMouseCursors.click);

ThemeData _minimalTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: isLight ? const Color(0xFF0071E3) : const Color(0xFF0A84FF),
    brightness: brightness,
  ).copyWith(
    surface: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E),
    surfaceContainerHighest: isLight
        ? const Color(0xFFF5F5F7)
        : const Color(0xFF2C2C2E),
    onSurface: isLight ? const Color(0xFF1D1D1F) : const Color(0xFFF5F5F7),
    onSurfaceVariant: isLight ? const Color(0xFF86868B) : const Color(0xFFAEAEB2),
  );
  final hairline = isLight ? const Color(0x1A000000) : const Color(0x1AFFFFFF);

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamilyFallback: _fontFallbacks,
  );

  return base.copyWith(
    iconTheme: base.iconTheme.copyWith(size: 18),
    scaffoldBackgroundColor: scheme.surface,
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom().copyWith(mouseCursor: _clickCursor),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        // 更紧凑的悬停高亮：不用 M3 的 40x40 最小尺寸。
        minimumSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        padding: const EdgeInsets.all(5),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: hairline),
          ),
        ),
        visualDensity: VisualDensity.compact,
      ).copyWith(mouseCursor: _clickCursor),
    ),
    // 卡片：平面化，用柔和阴影/发丝边代替立体投影。
    cardTheme: CardThemeData(
      color: isLight ? Colors.white : const Color(0xFF1C1C1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: isLight
            ? BorderSide.none
            : const BorderSide(color: Color(0x1AFFFFFF)),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    // AppBar：无边框化，内容优先。
    appBarTheme: AppBarTheme(
      backgroundColor: isLight ? Colors.white : const Color(0xFF1C1C1E),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leadingWidth: 42,
      titleSpacing: 0,
      shape: Border(bottom: BorderSide(color: hairline, width: 0.5)),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      elevation: 1,
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 0.5),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight ? const Color(0xFFF5F5F7) : const Color(0xFF2C2C2E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xE61D1D1F) : const Color(0xE6F5F5F7),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        fontSize: 12,
        color: isLight ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(6),
      radius: Radius.circular(3),
      minThumbLength: 36,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: hairline,
    ),
  );
}

class _PixelPalette {
  const _PixelPalette({
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderDark,
    required this.text,
    required this.textDim,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.error,
  });

  final Color background;
  final Color panel;
  final Color panelAlt;
  final Color border;
  final Color borderDark;
  final Color text;
  final Color textDim;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color error;
}

const _pixelLight = _PixelPalette(
  background: Color(0xFFF6E5B8), // 羊皮纸
  panel: Color(0xFFFFE9C6), // 面板奶油
  panelAlt: Color(0xFFF0D79E), // 次级面板
  border: Color(0xFF8A5A2A), // 木框
  borderDark: Color(0xFF5B2E0E), // 深棕描边
  text: Color(0xFF3F2200),
  textDim: Color(0xFF7A5A33),
  primary: Color(0xFF2C8A43), // 农场绿
  onPrimary: Color(0xFFFFF6DC),
  accent: Color(0xFFFFB03B), // 麦穗黄
  error: Color(0xFFC0392B),
);

ThemeData _pixelTheme() {
  const p = _pixelLight;
  const brightness = Brightness.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.accent,
    onPrimaryContainer: p.borderDark,
    secondary: p.accent,
    onSecondary: p.borderDark,
    secondaryContainer: p.panelAlt,
    onSecondaryContainer: p.text,
    tertiary: p.primary,
    onTertiary: p.onPrimary,
    error: p.error,
    onError: Colors.white,
    surface: p.panel,
    onSurface: p.text,
    surfaceContainerHighest: p.panelAlt,
    onSurfaceVariant: p.textDim,
    outline: p.border,
    outlineVariant: p.border,
  );

  final frameBorder = BorderSide(color: p.borderDark, width: 2);
  OutlineInputBorder pixelField(BorderSide side) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: side,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamilyFallback: _fontFallbacks,
  );

  ButtonStyle pixelButton({
    required Color fill,
    required Color fg,
  }) =>
      ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(fill),
        foregroundColor: WidgetStatePropertyAll(fg),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: frameBorder,
          ),
        ),
        side: WidgetStatePropertyAll(frameBorder),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        overlayColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.25)),
      ).copyWith(mouseCursor: _clickCursor);

  return base.copyWith(
    iconTheme: base.iconTheme.copyWith(size: 18, color: p.text),
    scaffoldBackgroundColor: p.background,
    splashFactory: NoSplash.splashFactory,
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))
          .copyWith(side: frameBorder),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: pixelButton(fill: p.primary, fg: p.onPrimary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: frameBorder,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: pixelButton(fill: p.panelAlt, fg: p.text),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        iconSize: 18,
        minimumSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        highlightColor: p.accent.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
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
        side: WidgetStatePropertyAll(frameBorder),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
        visualDensity: VisualDensity.compact,
        elevation: const WidgetStatePropertyAll(0),
      ).copyWith(mouseCursor: _clickCursor),
    ),
    cardTheme: CardThemeData(
      color: p.panel,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))
          .copyWith(side: frameBorder),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))
          .copyWith(side: BorderSide(color: p.border.withValues(alpha: 0.4))),
      iconColor: p.textDim,
      selectedColor: p.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.panel,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leadingWidth: 42,
      titleSpacing: 0,
      shape: Border(bottom: BorderSide(color: p.borderDark, width: 3)),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: p.text,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))
          .copyWith(side: frameBorder),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: p.border.withValues(alpha: 0.6),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.borderDark,
      contentTextStyle: const TextStyle(color: Color(0xFFFFE9C6)),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))
          .copyWith(side: BorderSide(color: p.accent, width: 2)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.panelAlt,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.3),
      trackHeight: 6,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.panelAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: pixelField(BorderSide(color: p.borderDark, width: 2)),
      enabledBorder: pixelField(BorderSide(color: p.borderDark, width: 2)),
      focusedBorder: pixelField(BorderSide(color: p.primary, width: 2)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      color: p.panel,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))
          .copyWith(side: frameBorder),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.borderDark,
        border: Border.all(color: p.accent, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Color(0xFFFFE9C6)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(3),
      minThumbLength: 36,
      thumbColor: WidgetStatePropertyAll(p.border),
      trackBorderColor: WidgetStatePropertyAll(p.borderDark),
      trackColor: WidgetStatePropertyAll(p.panelAlt),
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
      trackOutlineColor: WidgetStatePropertyAll(p.borderDark),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.primary;
        return p.panelAlt;
      }),
      side: BorderSide(color: p.borderDark, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
  );
}
