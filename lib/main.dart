import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'data/db.dart';
import 'data/repositories.dart';
import 'services/autosave_service.dart';
import 'services/durability_service.dart';
import 'services/logger.dart';
import 'services/session_stats.dart';
import 'services/sync/sync_engine.dart';
import 'state/app_config.dart';
import 'state/app_state.dart';
import 'state/settings_controller.dart';
import 'ui/app_root.dart';
import 'ui/widgets/window_controls.dart';

Future<void> main() async {
  await Logger.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger.error(
      'Flutter UI 异常: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      tag: 'Flutter',
    );
  };
  PlatformDispatcher.instance.onError = (e, stack) {
    Logger.error('平台派发未捕获异常',
        error: e, stackTrace: stack, tag: 'Platform');
    return true;
  };
  Isolate.current.addErrorListener(RawReceivePort((pair) async {
    final args = pair as List<Object>;
    Logger.error('Isolate 未捕获异常',
        error: args.first.toString(),
        stackTrace: StackTrace.fromString(args.last as String),
        tag: 'Isolate');
  }).sendPort);

  runZonedGuarded(() async {
    await _bootstrap();
  }, (e, stack) {
    Logger.error('未捕获异步异常', error: e, stackTrace: stack, tag: 'Zone');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final settings = SettingsController(config);

  final books = BookRepository();
  final volumes = VolumeRepository();
  final chapters = ChapterRepository(
      standardResolver: () => settings.countStandard);
  final snapshots = SnapshotRepository();
  final notes = NoteRepository();
  final characters = CharacterRepository();
  final foreshadows = ForeshadowRepository();
  final fsSegments = ForeshadowSegmentRepository();
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

  await crash.detect();
  await crash.markAlive();

  final appState = AppState(
    settings: settings,
    books: books,
    volumes: volumes,
    chapters: chapters,
    snapshots: snapshots,
    notes: notes,
    characters: characters,
    foreshadows: foreshadows,
    fsSegments: fsSegments,
    stats: stats,
    recycle: recycle,
    autosave: autosave,
    durability: durability,
    crash: crash,
    session: session,
    sync: sync,
  );

  await appState.purgeExpiredRecycle();

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
    child: AppRoot(),
  ));
}
