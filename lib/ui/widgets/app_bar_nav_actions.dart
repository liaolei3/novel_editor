import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';
import '../login_page.dart';
import '../settings_page.dart';
import 'app_icon.dart';

/// 顶栏导航按钮组：账号登录 / 主题切换 / 设置（书架页与工作区共用）。
class AppBarNavActions extends StatelessWidget {
  const AppBarNavActions({super.key});

  IconData _themeIcon(AppTheme theme) => switch (theme) {
        AppTheme.light => Icons.light_mode,
        AppTheme.dark => Icons.dark_mode,
        AppTheme.pixel => Icons.sports_esports,
      };

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
        icon: AppIcon(
          _themeIcon(theme),
          size: theme == AppTheme.pixel ? 26 : null,
        ),
        onPressed: () {
          final next = AppTheme
              .values[(theme.index + 1) % AppTheme.values.length];
          context.read<SettingsController>().setTheme(next);
        },
      ),
      IconButton(
        tooltip: '设置',
        icon: const AppIcon(Icons.settings_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        ),
      ),
    ]);
  }
}
