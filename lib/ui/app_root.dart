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
    final theme = buildAppTheme(
      settings.theme,
      fontFamily: settings.uiFontFamily,
    );
    return MaterialApp(
      title: 'NovelEditor 小说编辑器',
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.light,
      // 界面字体缩放：作用于全部文本（含写死字号的控件）；
      // 编辑器正文单独用 noScaling 覆盖，由正文字号独立控制。
      // 渐变主题在全局底层垫渐变，各页透明 scaffold 直接透出。
      builder: (context, child) {
        final gradient =
            appThemeSpec(settings.theme).backgroundGradient;
        final decorated = gradient == null
            ? child!
            : DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
                child: child!,
              );
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(settings.uiScale)),
          child: decorated,
        );
      },
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
        // Dialog 内部 Align 会架空外层 SizedBox 宽度，须用 constraints 指定。
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
        title: const Text('请确认'),
        content: Text(message),
        actionsAlignment: MainAxisAlignment.end,
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
