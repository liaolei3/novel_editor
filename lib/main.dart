import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/db.dart';
import 'data/repositories.dart';
import 'services/autosave_service.dart';
import 'services/durability_service.dart';
import 'services/session_stats.dart';
import 'services/sync/sync_engine.dart';
import 'state/app_config.dart';
import 'state/app_state.dart';
import 'state/settings_controller.dart';
import 'ui/app_root.dart';
import 'ui/widgets/window_controls.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final settings = SettingsController(config);

  final books = BookRepository();
  final volumes = VolumeRepository();
  final chapters = ChapterRepository();
  final snapshots = SnapshotRepository();
  final notes = NoteRepository();
  final stats = StatsRepository();
  final recycle = RecycleRepository();
  await Db.instance();

  final durability = DurabilityService(snapshots, chapters);
  final autosave = AutosaveService(chapters, durability);
  final session = SessionStats(stats);
  final sync = SyncEngine(chapters);
  final crash = CrashRecovery();

  autosave.startInterval();
  session.begin();
  await recycle.purgeExpired();

  final crashReport = await crash.detect();
  await crash.markAlive();

  final appState = AppState(
    settings: settings,
    books: books,
    volumes: volumes,
    chapters: chapters,
    snapshots: snapshots,
    notes: notes,
    stats: stats,
    recycle: recycle,
    autosave: autosave,
    durability: durability,
    crash: crash,
    session: session,
    sync: sync,
  );

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(titleBarStyle: TitleBarStyle.hidden);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(AppCloseHandler(appState));
  }

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<AppState>.value(value: appState),
    ],
    child: AppRoot(crashReport: crashReport),
  ));
}
