import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'app_theme.dart';
import 'common/dialogs.dart';
import 'shelf_page.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final theme = buildAppTheme(settings.theme, settings.fontSize / 17);
    return MaterialApp(
      title: 'NovelEditor 小说编辑器',
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const ShelfPage(),
    );
  }
}

AppState appState(BuildContext context) => context.read<AppState>();

Future<bool> confirmDangerous(
  BuildContext context,
  String message, {
  String confirmLabel = '删除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialog(
      child: AlertDialog(
        title: const Text('请确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return result == true;
}
