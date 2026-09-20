import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';
import '../state/app_config.dart';
import 'logger.dart';

/// 已导入字体的清单项。family 即注册到字体引擎的名字（取自文件名）。
class ImportedFont {
  const ImportedFont({required this.family, required this.fileName});

  final String family;
  final String fileName;

  Map<String, Object?> toJson() => {'family': family, 'fileName': fileName};

  static ImportedFont? fromJson(Object? item) {
    if (item is! Map) return null;
    final family = item['family']?.toString() ?? '';
    final fileName = item['fileName']?.toString() ?? '';
    if (family.isEmpty || fileName.isEmpty) return null;
    return ImportedFont(family: family, fileName: fileName);
  }
}

/// 动态导入字体：字体文件复制到数据目录 fonts/ 下，用 FontLoader 注册为
/// 运行时字体；清单持久化在 config.json 的 importedFonts，启动时统一注册。
class FontService extends ChangeNotifier {
  FontService._();
  static final FontService instance = FontService._();

  static const _manifestKey = 'importedFonts';

  final List<ImportedFont> _fonts = [];
  List<ImportedFont> get fonts => List.unmodifiable(_fonts);

  /// 启动时注册全部已导入字体；文件缺失则跳过。
  Future<void> registerAll() async {
    _fonts.clear();
    final raw = AppConfig.instance.getString(_manifestKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final item in list) {
        final font = ImportedFont.fromJson(item);
        if (font == null) continue;
        _fonts.add(font);
        await _register(font);
      }
    } catch (_) {
      // 清单损坏时忽略，不影响启动。
    }
  }

  Future<void> _register(ImportedFont font) async {
    try {
      final file = File(p.join(await _fontsDir(), font.fileName));
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      await ui.loadFontFromList(bytes, fontFamily: font.family);
    } catch (e) {
      Logger.error('注册字体失败: ${font.family}',
          error: e, tag: 'FontService');
    }
  }

  Future<String> _fontsDir() async {
    final dir = Directory(p.join(await Db.supportDir(), 'fonts'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
  }

  /// 导入字体文件：复制到 fonts/、注册到引擎并更新清单，返回字体族名。
  Future<String> importFont(String sourcePath) async {
    final family = p.basenameWithoutExtension(sourcePath);
    final fileName = p.basename(sourcePath);
    final target = File(p.join(await _fontsDir(), fileName));
    await File(sourcePath).copy(target.path);
    final font = ImportedFont(family: family, fileName: fileName);
    await _register(font);
    _fonts.removeWhere((f) => f.family == family);
    _fonts.add(font);
    await AppConfig.instance.setString(
      _manifestKey,
      jsonEncode([for (final f in _fonts) f.toJson()]),
    );
    notifyListeners();
    return family;
  }
}
