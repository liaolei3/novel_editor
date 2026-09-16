import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';
import '../login_page.dart';
import '../settings_dialog.dart';

/// 顶栏导航按钮组：账号登录 / 主题切换 / 设置（书架页与工作区共用）。
class AppBarNavActions extends StatelessWidget {
  const AppBarNavActions({super.key});

  /// 蛋黄派主题用 Icons.pie_chart（实心圆盘，光学重量与浅/暗色图标一致）。
  Widget _themeIcon(AppTheme theme) => Icon(theme == AppTheme.eggPie
      ? Icons.pie_chart
      : theme == AppTheme.light
          ? Icons.light_mode
          : Icons.dark_mode);

  String _themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.light => '浅色',
        AppTheme.dark => '暗色',
        AppTheme.eggPie => '蛋黄派',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SettingsController>().theme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: '账号登录',
        icon: const Icon(Icons.person_outline, size: 24),
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
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => showSettingsDialog(context),
      ),
    ]);
  }
}
