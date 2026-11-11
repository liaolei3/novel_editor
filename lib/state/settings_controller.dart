import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'editor_layout.dart';
import 'rail_layout.dart';
import '../core/constants.dart';
import '../core/utils/text_stats.dart';
import '../ui/app_theme.dart';
import '../ui/widgets/highlight_swatches.dart';

/// 设置控制器（9.8 设置页）：
/// 主题（玻璃拟态/有机自然/活力涂鸦）、字体大小、行距、自动保存频率、每日目标、同步开关。
/// 配置持久化在数据目录的 config.json 中，随数据目录一起迁移。
class SettingsController extends ChangeNotifier {
  SettingsController(this._cfg);

  final AppConfig _cfg;

  /// 未知/历史遗留的主题值一律回退默认「有机自然」。
  AppTheme get theme {
    final name = _cfg.getString('appTheme');
    for (final t in AppTheme.values) {
      if (t.name == name) return t;
    }
    return AppTheme.nature;
  }

  /// 未知/历史遗留的立绘值一律回退默认「英短蓝猫」。
  PetStandee get standee {
    final id = _cfg.getString('standee');
    for (final s in PetStandee.values) {
      if (s.id == id) return s;
    }
    return PetStandee.blue;
  }

  double get fontSize => _cfg.getDouble('fontSize') ?? 17;
  double get lineHeight => _cfg.getDouble('lineHeight') ?? 1.8;
  double get uiScale => _cfg.getDouble('uiScale') ?? 1.0;
  String get uiFontFamily => _cfg.getString('uiFontFamily') ?? '';
  String get editorFontFamily => _cfg.getString('editorFontFamily') ?? '';
  double get paragraphSpacing => _cfg.getDouble('paragraphSpacing') ?? 0.5;

  /// 手机预览（审阅）专用排版：未单独设置过时回落到全局写作排版，
  /// 面板内调整只影响预览，不回写编辑器。
  double get reviewFontSize => _cfg.getDouble('reviewFontSize') ?? fontSize;
  double get reviewLineHeight => _cfg.getDouble('reviewLineHeight') ?? lineHeight;
  double get reviewParagraphSpacing =>
      _cfg.getDouble('reviewParagraphSpacing') ?? paragraphSpacing;

  /// 预览机型：预设 id 或 [AppConstants.previewCustomDeviceId]。
  String get reviewDevice =>
      _cfg.getString('reviewDevice') ?? AppConstants.previewDefaultDeviceId;
  double get reviewCustomWidth =>
      _cfg.getDouble('reviewCustomWidth') ?? AppConstants.defaultPreviewDevice.width;
  double get reviewCustomHeight =>
      _cfg.getDouble('reviewCustomHeight') ?? AppConstants.defaultPreviewDevice.height;
  bool get typewriterMode => _cfg.getBool('typewriterMode') ?? false;

  /// 对话（台词）高亮颜色（规范亮色值）；null 表示「无色」即关闭。
  /// 未配置过时默认亮黄（色板首色），因此默认开启。
  Color? get dialogueHighlightColor {
    final v = _cfg.getString('dialogueHighlight');
    if (v == null) return highlightLightSwatches.first;
    if (v == 'none') return null;
    return colorFromHex(v) ?? highlightLightSwatches.first;
  }

  int get autosaveSeconds => _cfg.getInt('autosaveSeconds') ?? 2;
  int get dailyGoal => _cfg.getInt('dailyGoal') ?? 2000;
  CountStandard get countStandard => CountStandard.values.firstWhere(
        (s) => s.name == _cfg.getString('countStandard'),
        orElse: () => CountStandard.withPunctuation,
      );
  bool get syncEnabled => _cfg.getBool('syncEnabled') ?? false;

  String get lastBookId => _cfg.getString('lastBookId') ?? '';
  String get dataDir => _cfg.getString('dataDir') ?? '';

  double get workspaceLeftWidth => _cfg.getDouble('workspaceLeftWidth') ?? 280;
  bool get outlineGridView => _cfg.getBool('outlineGridView') ?? true;
  bool get characterGridView => _cfg.getBool('characterGridView') ?? false;
  bool get foreshadowGridView => _cfg.getBool('foreshadowGridView') ?? false;

  /// 可停靠面板图标栏布局（全局保存）。
  RailLayout get railLayout =>
      RailLayout.fromJson(_cfg.getMap('railLayout'));

  Future<void> setTheme(AppTheme theme) =>
      _set('appTheme', theme.name, () => notifyListeners());

  Future<void> setStandee(PetStandee v) =>
      _set('standee', v.id, () => notifyListeners());

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

  Future<void> setTypewriterMode(bool v) =>
      _set('typewriterMode', v, () => notifyListeners());

  Future<void> setDialogueHighlightColor(Color? color) => _set(
        'dialogueHighlight',
        color == null ? 'none' : highlightHex(canonicalSwatchOf(color)),
        () => notifyListeners(),
      );

  Future<void> setReviewFontSize(double v) =>
      _set('reviewFontSize', v, () => notifyListeners());

  Future<void> setReviewLineHeight(double v) =>
      _set('reviewLineHeight', v, () => notifyListeners());

  Future<void> setReviewParagraphSpacing(double v) =>
      _set('reviewParagraphSpacing', v, () => notifyListeners());

  Future<void> setReviewDevice(String v) =>
      _set('reviewDevice', v, () => notifyListeners());

  Future<void> setReviewCustomSize(double width, double height) async {
    await _cfg.setDouble('reviewCustomWidth', width);
    await _cfg.setDouble('reviewCustomHeight', height);
    notifyListeners();
  }

  Future<void> setAutosaveSeconds(int v) =>
      _set('autosaveSeconds', v, () => notifyListeners());

  Future<void> setDailyGoal(int v) =>
      _set('dailyGoal', v, () => notifyListeners());

  Future<void> setCountStandard(CountStandard v) =>
      _set('countStandard', v.name, () => notifyListeners());

  Future<void> setSyncEnabled(bool v) => _set('syncEnabled', v, null);

  Future<void> setLastBookId(String v) => _set('lastBookId', v, null);

  static const int _recentBookLimit = 10;
  static const int _hiddenRecentLimit = 10;

  /// 最近打开的书籍 id（新打开的排最前），用于主页顶栏书籍标签。
  List<String> get recentBookIds =>
      _cfg.getStringList('recentBookIds') ?? const [];

  /// 最近关闭标签的书 id（按关闭时间倒序），供「＋」浮层快速恢复。
  List<String> get hiddenRecentBookIds =>
      _cfg.getStringList('hiddenRecentBookIds') ?? const [];

  /// 记录一次打开：已在标签栏的书保持原位不跳动；新书追加到末尾，
  /// 超出上限时淘汰最旧（列表头部）移入隐藏列表。
  Future<void> touchRecentBook(String id) async {
    final ids = [...recentBookIds];
    if (ids.contains(id)) return;
    final hidden = [...hiddenRecentBookIds]..remove(id);
    ids.add(id);
    if (ids.length > _recentBookLimit) {
      hidden.insertAll(0, ids.sublist(0, ids.length - _recentBookLimit));
      ids.removeRange(0, ids.length - _recentBookLimit);
    }
    if (hidden.length > _hiddenRecentLimit) {
      hidden.removeRange(_hiddenRecentLimit, hidden.length);
    }
    await _cfg.setStringList('recentBookIds', ids);
    await _cfg.setStringList('hiddenRecentBookIds', hidden);
  }

  /// 关闭标签：从标签栏移入隐藏列表（可经「＋」浮层恢复）。
  Future<void> removeRecentBook(String id) async {
    final ids = [...recentBookIds]..remove(id);
    await _cfg.setStringList('recentBookIds', ids);
    final hidden = [...hiddenRecentBookIds]..remove(id);
    hidden.insert(0, id);
    if (hidden.length > _hiddenRecentLimit) {
      hidden.removeRange(_hiddenRecentLimit, hidden.length);
    }
    await _cfg.setStringList('hiddenRecentBookIds', hidden);
    notifyListeners();
  }

  /// 工作区布局：仅落盘，不通知（布局是 WorkspacePage 的本地状态）。
  Future<void> setWorkspaceLeftWidth(double v) => _cfg.setDouble('workspaceLeftWidth', v);
  Future<void> setOutlineGridView(bool v) => _cfg.setBool('outlineGridView', v);
  Future<void> setCharacterGridView(bool v) => _cfg.setBool('characterGridView', v);
  Future<void> setForeshadowGridView(bool v) => _cfg.setBool('foreshadowGridView', v);

  /// 保存可停靠面板布局，仅落盘。
  Future<void> saveRailLayout(RailLayout layout) =>
      _cfg.setMap('railLayout', layout.toJson());

  /// 每书分屏布局（config.json 的 editorPanes 键），不存在或损坏返回 null。
  EditorLayout? editorLayoutOf(String bookId) {
    final raw = _cfg.getMap('editorPanes')?[bookId];
    if (raw is Map) return EditorLayout.fromJson(raw);
    if (raw is String) {
      try {
        return EditorLayout.fromJson(jsonDecode(raw));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 保存指定书的分屏布局，保留其他书条目。
  Future<void> saveEditorLayout(String bookId, EditorLayout layout) async {
    final map = _cfg.getMap('editorPanes') ?? <String, Object?>{};
    map[bookId] = layout.toJson();
    await _cfg.setMap('editorPanes', map);
  }

  /// 每书 UI 快照（config.json 的 bookUi 键）：目录树展开卷、章节标签。
  BookUiRecord bookUiOf(String bookId) {
    final m = _cfg.getMap('bookUi')?[bookId];
    if (m is! Map) return const BookUiRecord();
    return BookUiRecord(
      tree: (m['tree'] as List?)?.whereType<String>().toList() ?? const [],
      chapterTabs:
          (m['chapterTabs'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  Future<void> saveBookUi(
    String bookId, {
    required List<String> tree,
    required List<String> chapterTabs,
  }) async {
    final map = _cfg.getMap('bookUi') ?? <String, Object?>{};
    map[bookId] = {'tree': tree, 'chapterTabs': chapterTabs};
    await _cfg.setMap('bookUi', map);
  }

  /// 只更新目录树展开状态，保留该书记录里的旧 chapterTabs 字段。
  Future<void> saveBookTree(String bookId, List<String> tree) async {
    final map = _cfg.getMap('bookUi') ?? <String, Object?>{};
    final existing = map[bookId];
    final oldTabs = existing is Map ? existing['chapterTabs'] : null;
    map[bookId] = {
      'tree': tree,
      if (oldTabs is List) 'chapterTabs': oldTabs.whereType<String>().toList(),
    };
    await _cfg.setMap('bookUi', map);
  }

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

/// 单本书的持久化 UI 快照（config.json bookUi 键的条目）。
class BookUiRecord {
  const BookUiRecord({this.tree = const [], this.chapterTabs = const []});

  /// 展开的卷 id 集合。
  final List<String> tree;

  /// 章节标签顺序（章节 id）。
  final List<String> chapterTabs;
}
