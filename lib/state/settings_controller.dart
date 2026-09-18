import 'package:flutter/material.dart';

import 'app_config.dart';
import '../core/utils/text_stats.dart';
import '../ui/app_theme.dart';

/// 设置控制器（9.8 设置页）：
/// 主题（浅色/暗色/蛋黄派）、字体大小、行距、自动保存频率、每日目标、AI 配置、同步开关。
/// 配置持久化在数据目录的 config.json 中，随数据目录一起迁移。
class SettingsController extends ChangeNotifier {
  SettingsController(this._cfg);

  final AppConfig _cfg;

  AppTheme get theme {
    switch (_cfg.getString('appTheme')) {
      case 'dark':
        return AppTheme.dark;
      case 'eggPie':
        return AppTheme.eggPie;
      default:
        return AppTheme.light;
    }
  }

  double get fontSize => _cfg.getDouble('fontSize') ?? 17;
  double get lineHeight => _cfg.getDouble('lineHeight') ?? 1.8;
  double get uiScale => _cfg.getDouble('uiScale') ?? 1.0;
  String get uiFontFamily => _cfg.getString('uiFontFamily') ?? '';
  String get editorFontFamily => _cfg.getString('editorFontFamily') ?? '';
  double get paragraphSpacing => _cfg.getDouble('paragraphSpacing') ?? 0.5;
  int get autosaveSeconds => _cfg.getInt('autosaveSeconds') ?? 2;
  int get dailyGoal => _cfg.getInt('dailyGoal') ?? 2000;
  CountStandard get countStandard => CountStandard.values.firstWhere(
        (s) => s.name == _cfg.getString('countStandard'),
        orElse: () => CountStandard.withPunctuation,
      );
  bool get syncEnabled => _cfg.getBool('syncEnabled') ?? false;
  String get aiBaseUrl => _cfg.getString('aiBaseUrl') ?? '';
  String get aiApiKey => _cfg.getString('aiApiKey') ?? '';
  String get aiModel => _cfg.getString('aiModel') ?? '';
  String get sensitiveDictVersion => _cfg.getString('sensitiveDictVersion') ?? '内置 v1';
  String get lastBookId => _cfg.getString('lastBookId') ?? '';
  String get dataDir => _cfg.getString('dataDir') ?? '';

  Future<void> setTheme(AppTheme theme) =>
      _set('appTheme', theme.name, () => notifyListeners());

  Future<void> setFontSize(double v) =>
      _set('fontSize', v, () => notifyListeners());

  Future<void> setUiScale(double v) =>
      _set('uiScale', v, () => notifyListeners());

  Future<void> setUiFontFamily(String v) =>
      _set('uiFontFamily', v, () => notifyListeners());

  Future<void> setEditorFontFamily(String v) =>
      _set('editorFontFamily', v, () => notifyListeners());

  Future<void> setLineHeight(double v) =>
      _set('lineHeight', v, () => notifyListeners());

  Future<void> setParagraphSpacing(double v) =>
      _set('paragraphSpacing', v, () => notifyListeners());

  Future<void> setAutosaveSeconds(int v) =>
      _set('autosaveSeconds', v, () => notifyListeners());

  Future<void> setDailyGoal(int v) =>
      _set('dailyGoal', v, () => notifyListeners());

  Future<void> setCountStandard(CountStandard v) =>
      _set('countStandard', v.name, () => notifyListeners());

  Future<void> setSyncEnabled(bool v) => _set('syncEnabled', v, null);

  Future<void> setAiConfig(String baseUrl, String apiKey, String model) async {
    await _cfg.setString('aiBaseUrl', baseUrl);
    await _cfg.setString('aiApiKey', apiKey);
    await _cfg.setString('aiModel', model);
    notifyListeners();
  }

  Future<void> setSensitiveDictVersion(String v) =>
      _set('sensitiveDictVersion', v, null);

  Future<void> setLastBookId(String v) => _set('lastBookId', v, null);

  /// 切换数据存储目录（空 = 应用默认目录）；重启应用后生效。
  Future<void> setDataDir(String v) =>
      _set('dataDir', v, () => notifyListeners());

  Future<void> _set<T>(String key, T value, VoidCallback? after) async {
    if (value is int) {
      await _cfg.setInt(key, value);
    } else if (value is double) {
      await _cfg.setDouble(key, value);
    } else if (value is bool) {
      await _cfg.setBool(key, value);
    } else {
      await _cfg.setString(key, value as String);
    }
    after?.call();
  }
}
