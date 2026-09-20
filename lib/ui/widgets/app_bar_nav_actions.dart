import 'package:flutter/material.dart';

import '../settings_dialog.dart';

/// 顶栏导航按钮组：设置（书架页与工作区共用）。
class AppBarNavActions extends StatelessWidget {
  const AppBarNavActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => showSettingsDialog(context),
        ),
      ],
    );
  }
}
