import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';

/// 应用配置存储：单文件 JSON（config.json），保存在数据目录内，随数据目录一起迁移，
/// 不再依赖 C 盘默认目录的 shared_preferences。
class AppConfig {
  AppConfig._(File file, this._values) : _file = file;

  final Map<String, Object?> _values;
  File _file;

  static AppConfig? _instance;
  static AppConfig get instance => _instance!;

  static Future<AppConfig> load() async {
    final root = await Db.supportDir();
    final file = File(p.join(root, 'config.json'));
    Map<String, Object?> values = {};
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          values = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // 配置文件损坏时按空配置启动。
      }
    } else {
      values = await _importLegacy(root);
      try {
        await Directory(root).create(recursive: true);
        await file.writeAsString(jsonEncode(values), flush: true);
      } catch (_) {}
    }
    final cfg = AppConfig._(file, values);
    _instance = cfg;
    return cfg;
  }

  /// 首次运行：从旧版 shared_preferences.json 导入（数据目录备份优先，其次默认目录）。
  static Future<Map<String, Object?>> _importLegacy(String root) async {
    final defaultDir = (await getApplicationSupportDirectory()).path;
    for (final path in [
      p.join(root, 'shared_preferences.json'),
      p.join(defaultDir, 'shared_preferences.json'),
    ]) {
      final f = File(path);
      if (!f.existsSync()) continue;
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is! Map) continue;
        return decoded.map((k, v) => MapEntry(
            k.toString().replaceFirst(RegExp('^flutter\\.'), ''), v));
      } catch (_) {}
    }
    return {};
  }

  String? getString(String key) => _values[key] as String?;
  int? getInt(String key) => _values[key] as int?;
  double? getDouble(String key) {
    final v = _values[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return null;
  }

  bool? getBool(String key) => _values[key] as bool?;

  Future<void> setString(String key, String v) => _set(key, v);
  Future<void> setInt(String key, int v) => _set(key, v);
  Future<void> setDouble(String key, double v) => _set(key, v);
  Future<void> setBool(String key, bool v) => _set(key, v);

  Future<void> _set(String key, Object? v) async {
    _values[key] = v;
    try {
      await _file.writeAsString(jsonEncode(_values), flush: true);
    } catch (_) {
      // 落盘失败时保留内存值。
    }
  }

  /// 切换数据目录时，把当前配置写入新目录，后续修改也落盘到新位置。
  Future<void> saveTo(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      final f = File(p.join(dir, 'config.json'));
      await f.writeAsString(jsonEncode(_values), flush: true);
      _file = f;
    } catch (_) {
      // 写入失败时保持原位置。
    }
  }
}
