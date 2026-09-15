import 'package:flutter/material.dart';
import 'package:pixelarticons/pixelarticons.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';
import '../login_page.dart';
import '../settings_dialog.dart';
import 'app_icon.dart';

/// 顶栏导航按钮组：账号登录 / 主题切换 / 设置（书架页与工作区共用）。
class AppBarNavActions extends StatelessWidget {
  const AppBarNavActions({super.key});

  /// 像素主题固定用 Pixel.gamepad，其余走 AppIcon 主题映射。
  Widget _themeIcon(AppTheme theme) => theme == AppTheme.pixel
      ? const Icon(Pixel.gamepad, size: 26)
      : AppIcon(theme == AppTheme.light
          ? Icons.light_mode
          : Icons.dark_mode);

  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '浅色',
        AppTheme.dark => '暗色',
        AppTheme.pixel => '像素',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SettingsController>().theme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: '账号登录',
        icon: const AppIcon(Icons.person_outline),
        onPressed: () => showLoginDialog(context),
      ),
      IconButton(
        tooltip: _themeLabel(theme),
        icon: _themeIcon(theme),
        onPressed: () {
          final next = AppTheme
              .values[(theme.index + 1) % AppTheme.values.length];
          context.read<SettingsController>().setTheme(next);
        },
      ),
      IconButton(
        tooltip: '设置',
        icon: const AppIcon(Icons.settings_outlined),
        onPressed: () => showSettingsDialog(context),
      ),
    ]);
  }
}
