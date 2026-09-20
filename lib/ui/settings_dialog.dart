import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/utils/sensitive_words.dart';
import '../../core/utils/text_stats.dart';
import '../../data/db.dart';
import '../../services/font_service.dart';
import '../../services/logger.dart';
import '../../state/app_config.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'app_theme.dart';
import 'common/context_menu.dart';
import 'common/dialogs.dart';
import 'common/file_io.dart';
import 'conflict_page.dart';
import 'widgets/toast.dart';

/// 设置弹窗（9.8）：左分类导航 + 右内容区，参考系统设置布局。
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DraggableDialog(child: SettingsDialog()),
  );
}

class _Category {
  const _Category(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// 全宽滑块轨道：去掉默认 track 两侧为 thumb/overlay 预留的水平内缩，
/// 使轨道端点与行文字对齐。
class _FullWidthTrackShape extends RoundedRectSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isDiscrete = false,
    bool isEnabled = true,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4.0;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }
}

const _categories = [
  _Category(Icons.palette_outlined, '外观'),
  _Category(Icons.edit_note, '写作'),
  _Category(Icons.sync, '同步与账号'),
  _Category(Icons.message_outlined, 'AI 配置'),
  _Category(Icons.folder_open, '数据'),
];

const _pageDescriptions = [
  '主题、界面字体与缩放',
  '正文排版、统计与保存',
  '本地优先的云端增量同步',
  '连接 OpenAI 兼容网关（可选）',
  '存储、词库与日志',
];

/// 滑块行/下拉行共享的标题列宽，保证各滑块左侧起点一致；
/// 150% 界面缩放下 4 字标题约需 84px，取 104 留余量防换行。
const _rowLabelWidth = 104.0;

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _current = 0;

  final _themeScroll = ScrollController();

  @override
  void dispose() {
    _themeScroll.dispose();
    super.dispose();
  }

  /// 鼠标滚轮在主题预览行上转为横向滚动。
  void _themeWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final position = _themeScroll.position;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    final next = (position.pixels + delta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    position.jumpTo(next);
  }

  /// 按住左右拖动预览行（拖动距离超过阈值时不会误触卡片点击）。
  void _themeDragUpdate(DragUpdateDetails d) {
    final position = _themeScroll.position;
    position.jumpTo(
      (position.pixels - d.delta.dx)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final state = context.watch<AppState>();
    final fontService = context.watch<FontService>();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hairline = isLight
        ? const Color(0x1A000000)
        : const Color(0x1AFFFFFF);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Text('设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 960,
          height: 700,
          child: Column(
            children: [
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < _categories.length; i++)
                              _navItem(
                                category: _categories[i],
                                selected: i == _current,
                                onTap: () => setState(() => _current = i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        children: [
                          _pageHeader(
                            _categories[_current].label,
                            _pageDescriptions[_current],
                          ),
                          ...switch (_current) {
                            0 => _appearance(settings, fontService, hairline),
                            1 => _writing(settings, state, fontService, hairline),
                            2 => _sync(settings, state, hairline),
                            3 => _ai(settings, hairline),
                            _ => _data(settings, hairline),
                          },
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 内置字体 + 已导入字体（family 即显示名）。
  List<FontOption> _fontOptions(FontService fontService) {
    return [
      ...appFontOptions,
      for (final f in fontService.fonts) FontOption(f.family, f.family),
    ];
  }

  List<Widget> _appearance(
    SettingsController s,
    FontService fontService,
    Color hairline,
  ) {
    final fontOptions = _fontOptions(fontService);
    return [
      _group(
        hairline,
        [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '主题',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // 主题预览：一行横向排列；滚轮上下滚动与按住拖动均转为左右滑动。
          Align(
            alignment: Alignment.centerLeft,
            child: Listener(
              onPointerSignal: _themeWheel,
              child: GestureDetector(
                onHorizontalDragUpdate: _themeDragUpdate,
                child: SingleChildScrollView(
                  controller: _themeScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      for (final theme in AppTheme.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _ThemePreviewCard(
                            theme: theme,
                            selected: s.theme == theme,
                            onTap: () => s.setTheme(theme),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _group(hairline, [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('导入字体', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            '导入 ttf / otf 字体文件，界面与正文均可选用',
            style: TextStyle(fontSize: 12),
          ),
          trailing: _actionIcon(Icons.upload_file),
          onTap: _importFont,
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        _dropdownRow(
          title: '界面字体',
          value: s.uiFontFamily,
          options: fontOptions,
          onChanged: (v) => s.setUiFontFamily(v),
        ),
        _divider(hairline),
        _sliderRow(
          title: '界面缩放',
          value: '${(s.uiScale * 100).round()}%',
          slider: Slider(
            min: 0.8,
            max: 1.5,
            divisions: 14,
            value: s.uiScale.clamp(0.8, 1.5),
            onChanged: s.setUiScale,
            padding: EdgeInsets.zero,
          ),
        ),
      ]),
    ];
  }

  List<Widget> _writing(
    SettingsController s,
    AppState state,
    FontService fontService,
    Color hairline,
  ) {
    return [
      _group(hairline, [
        _dropdownRow(
          title: '正文字体',
          value: s.editorFontFamily,
          options: _fontOptions(fontService),
          onChanged: (v) => s.setEditorFontFamily(v),
        ),
        _divider(hairline),
        _sliderRow(
          title: '正文字号',
          value: '${s.fontSize.round()}',
          slider: Slider(
            min: 13,
            max: 26,
            divisions: 13,
            value: s.fontSize,
            onChanged: s.setFontSize,
            padding: EdgeInsets.zero,
          ),
        ),
        _divider(hairline),
        _sliderRow(
          title: '行距',
          value: '${s.lineHeight.toStringAsFixed(1)} 倍',
          slider: Slider(
            min: 1.2,
            max: 2.6,
            divisions: 14,
            value: s.lineHeight,
            onChanged: s.setLineHeight,
            padding: EdgeInsets.zero,
          ),
        ),
        _divider(hairline),
        _sliderRow(
          title: '段间距',
          value: '${s.paragraphSpacing.toStringAsFixed(1)} 倍',
          slider: Slider(
            min: 0,
            max: 2.0,
            divisions: 20,
            value: s.paragraphSpacing,
            onChanged: s.setParagraphSpacing,
            padding: EdgeInsets.zero,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const Expanded(child: Text('字数统计口径')),
              SizedBox(
                width: 240,
                child: SegmentedButton<CountStandard>(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(120, 36)),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: CountStandard.withPunctuation,
                      label: Text('含标点'),
                    ),
                    ButtonSegment(
                      value: CountStandard.withoutPunctuation,
                      label: Text('不含标点'),
                    ),
                  ],
                  selected: {s.countStandard},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) async {
                    final std = v.first;
                    if (std == s.countStandard) return;
                    await s.setCountStandard(std);
                    await state.recountAll();
                  },
                ),
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('自动保存停顿'),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '输入停顿后保存，另有 30 秒兜底自动保存',
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 3),
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Center(
                          child: Icon(
                            Icons.help_outline,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 240,
                child: SegmentedButton<int>(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(80, 36)),
                  ),
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1s')),
                    ButtonSegment(value: 2, label: Text('2s')),
                    ButtonSegment(value: 5, label: Text('5s')),
                  ],
                  selected: {s.autosaveSeconds},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => s.setAutosaveSeconds(v.first),
                ),
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        _sliderRow(
          title: '码字目标',
          value: '${s.dailyGoal} 字',
          slider: Slider(
            min: 500,
            max: 10000,
            divisions: 19,
            label: '${s.dailyGoal}',
            value: s.dailyGoal.toDouble(),
            onChanged: (v) => s.setDailyGoal(v.round()),
            padding: EdgeInsets.zero,
          ),
        ),
      ]),
    ];
  }

  List<Widget> _sync(SettingsController s, AppState state, Color hairline) {
    return [
      _group(hairline, [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('云同步'),
          subtitle: const Text('本地优先；联网时自动增量同步。\n关闭不影响本地写作。'),
          value: s.syncEnabled,
          onChanged: (v) => s.setSyncEnabled(v),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('立即同步'),
          subtitle: const Text('检测并推送/拉取增量；若同章双端修改将进入冲突解决'),
          trailing: _actionIcon(Icons.sync),
          onTap: () => _syncNow(state),
        ),
      ]),
    ];
  }

  List<Widget> _ai(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('AI 网关'),
          subtitle: Text(
            s.aiBaseUrl.isEmpty
                ? '未配置（自动降级为纯写作模式）'
                : '${s.aiModel} @ ${s.aiBaseUrl}',
          ),
          trailing: _chevron(),
          onTap: _editAi,
        ),
      ]),
    ];
  }

  List<Widget> _data(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('敏感词词库'),
          subtitle: Text('当前词库：${s.sensitiveDictVersion}'),
          trailing: _actionIcon(Icons.upload_file),
          onTap: _importDict,
        ),
        _divider(hairline),
        FutureBuilder<String>(
          future: s.dataDir.isNotEmpty
              ? Future.value(s.dataDir)
              : Db.defaultDir(),
          builder: (context, snap) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('数据存储目录'),
            subtitle: Text(
              snap.data ?? '读取中…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _actionIcon(Icons.folder_open),
            onTap: snap.hasData ? () => _changeDataDir(snap.data!) : null,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('运行日志'),
          subtitle: const Text('程序出错会自动记录在此'),
          trailing: _actionIcon(Icons.description),
          onTap: _openLogs,
        ),
        _divider(hairline),
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
          title: Text('关于'),
          subtitle: Text('NovelEditor 0.1.0'),
        ),
      ]),
    ];
  }

  /// 动作行 trailing：小描边容器图标，与下拉按钮/值胶囊同一视觉语言。
  Widget _actionIcon(IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isLight
              ? const Color(0x2E000000)
              : const Color(0x2EFFFFFF),
        ),
      ),
      child: Icon(icon, size: 15, color: scheme.onSurfaceVariant),
    );
  }

  /// 跳转行 trailing：弱色 chevron。
  Widget _chevron() {
    return Icon(
      Icons.chevron_right,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  /// 页头：当前分类大标题 + 一句话说明。
  Widget _pageHeader(String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片与导航选中项的共享底色：选中即「提亮」
  Color _panelColor() {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return isLight
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : scheme.surfaceContainerHighest;
  }

  /// 分组卡片：底色与导航选中项一致 + 组内行间分割线。
  /// 组内行统一包透明 Material：ListTile 的背景与墨水效果绘制在
  /// 最近的 Material 上，避免被卡片的 DecoratedBox 背景遮住。
  Widget _group(Color hairline, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _panelColor(),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme.merge(
        shape: const RoundedRectangleBorder(),
        child: Column(
          children: [
            for (final child in children)
              Material(type: MaterialType.transparency, child: child),
          ],
        ),
      ),
    );
  }

  /// 组内分割线：粗细与颜色由主题 dividerTheme 决定。
  Widget _divider(Color hairline) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }

  /// 滑块行：标题（固定宽，与下拉行对齐）+ 滑块 + 描边胶囊值同一行。
  Widget _sliderRow({
    required String title,
    required String value,
    required Widget slider,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hairlineStrong = isLight
        ? const Color(0x2E000000)
        : const Color(0x2EFFFFFF);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: _rowLabelWidth,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SizedBox(
                height: 28,
                child: SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(trackShape: const _FullWidthTrackShape()),
                  child: slider,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 88,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: hairlineStrong),
            ),
            alignment: Alignment.center,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下拉行：与滑块行同构（左标题 + 右控件）。右侧为描边选择器按钮，
  /// 点击弹出与右键菜单同规格（popupMenuTheme、44px 行高）的字体菜单，
  /// 当前项初始高亮。
  Widget _dropdownRow({
    required String title,
    required String value,
    required List<FontOption> options,
    required ValueChanged<String> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final current = options.firstWhere(
      (f) => f.family == value,
      orElse: () => options.first,
    );
    final hairlineStrong = isLight
        ? const Color(0x2E000000)
        : const Color(0x2EFFFFFF);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: _rowLabelWidth,
            child: Text(title),
          ),
          const Spacer(),
          Builder(
            builder: (ctx) => Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () async {
                  final box = ctx.findRenderObject() as RenderBox;
                  final picked = await showAppAnchoredMenu<String>(
                    context: ctx,
                    target: box,
                    initialValue: value,
                    entries: [
                      for (final f in options) AppMenuItem(f.family, f.label),
                    ],
                  );
                  if (picked != null) onChanged(picked);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  constraints: const BoxConstraints(minWidth: 88),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hairlineStrong),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current.label,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_more,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required _Category category,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _NavItem(
      category: category,
      selected: selected,
      onTap: onTap,
    );
  }
  /// 切换数据存储目录：选目录 → 确认 → 迁移数据 → 保存设置（重启后生效）。
  Future<void> _changeDataDir(String currentDir) async {
    final target = await FileIO.pickDirectory();
    if (target == null || target == currentDir) return;
    final hasExisting = File(p.join(target, 'novel_editor.db')).existsSync();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: const Text('切换数据存储目录'),
          content: Text(
            hasExisting
                ? '目标目录已包含数据文件，切换后将直接使用该目录中的数据（当前数据保留不动）：\n\n$target'
                : '将把当前全部数据（数据库与备份）迁移到：\n\n$target\n\n迁移后需重启应用生效，当前目录数据不会被删除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认切换'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      if (!hasExisting) await Db.migrateDataTo(target);
      await Db.anchorDataDir(target);
      await context.read<SettingsController>().setDataDir(target);
      // 当前配置写入新目录，重启后新目录内配置即完整。
      await AppConfig.instance.saveTo(target);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => DraggableDialog(
          child: AlertDialog(
            title: const Text('已切换'),
            content: const Text('数据存储目录已更新，重启应用后生效。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showToast(context, '切换失败：$e');
      }
    }
  }

  Future<void> _syncNow(AppState state) async {
    if (state.currentBook == null) {
      if (mounted) showToast(context, '请先打开一部作品');
      return;
    }
    final conflicts = await state.syncNow();
    if (!mounted) return;
    if (conflicts.isEmpty) {
      showToast(context, '同步完成，无冲突');
      return;
    }
    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConflictDialog(conflicts: conflicts),
    );
    if (resolved == true && mounted) {
      showToast(context, '冲突解决成功，同步完成');
      await state.reloadTreePublic();
    }
  }

  Future<void> _editAi() async {
    final settings = context.read<SettingsController>();
    final urlCtrl = TextEditingController(text: settings.aiBaseUrl);
    final keyCtrl = TextEditingController(text: settings.aiApiKey);
    final modelCtrl = TextEditingController(text: settings.aiModel);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: const Text('AI 网关（OpenAI 兼容）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL（如 https://api.xxx.com/v1）',
                ),
              ),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: '模型名'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await settings.setAiConfig(
        urlCtrl.text.trim(),
        keyCtrl.text.trim(),
        modelCtrl.text.trim(),
      );
    }
  }

  Future<void> _importDict() async {
    final raw = await FileIO.pickReadText();
    if (raw == null) return;
    final scanner = SensitiveWordScanner.parse(raw);
    await context.read<SettingsController>().setSensitiveDictVersion(
      '导入词库 ${scanner.words.length} 词',
    );
    if (mounted) {
      showToast(context, '词库更新成功（共 ${scanner.words.length} 词）');
    }
  }

  /// 导入字体：选文件 → 复制到数据目录并注册，导入后即可在字体下拉中选用。
  Future<void> _importFont() async {
    final path = await FileIO.pickFilePath(ext: ['ttf', 'otf']);
    if (path == null) return;
    try {
      await FontService.instance.importFont(path);
      if (mounted) showToast(context, '字体导入成功');
    } catch (e) {
      Logger.error('字体导入失败', error: e, tag: 'Settings');
      if (mounted) showToast(context, '字体导入失败：$e');
    }
  }

  /// 用系统资源管理器打开日志文件夹（Windows），便于用户打包日志发回排查。
  Future<void> _openLogs() async {
    final dirPath = await Logger.logsDir();
    try {
      if (!Directory(dirPath).existsSync()) {
        await Directory(dirPath).create(recursive: true);
      }
      await Process.run('explorer.exe', [dirPath]);
    } catch (e) {
      if (mounted) showToast(context, '打开失败：$e\n目录：$dirPath');
    }
  }
}

/// 左侧导航项：悬停浅高亮，选中用主题色浅底。
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final selected = widget.selected;
    final selectedColor = scheme.primary.withValues(alpha: isLight ? 0.10 : 0.18);
    final hoverColor = isLight
        ? const Color(0x08000000)
        : const Color(0x08FFFFFF);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor
                  : (_hover ? hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.category.icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.category.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主题预览卡：用主题规格画一张迷你界面示意（面板 + 标题行 + 按钮），
/// 颜色/圆角/渐变与实际主题同源，选中态用主题色描边。
class _ThemePreviewCard extends StatefulWidget {
  const _ThemePreviewCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ThemePreviewCard> createState() => _ThemePreviewCardState();
}

class _ThemePreviewCardState extends State<_ThemePreviewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final spec = appThemeSpec(widget.theme);
    final scheme = Theme.of(context).colorScheme;
    final border = widget.selected
        ? Border.all(color: scheme.primary, width: 2)
        : Border.all(
            color: scheme.onSurfaceVariant.withValues(alpha: _hover ? 0.45 : 0.2),
            width: 1,
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 168,
              height: 116,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(spec.cardRadius),
                border: border,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(spec.cardRadius - 2),
                child: Container(
                  decoration: BoxDecoration(
                    color: spec.background,
                    gradient: spec.backgroundGradient,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: spec.panel,
                      borderRadius: BorderRadius.circular(spec.cardRadius - 8),
                      border: Border.all(
                        color: spec.borderStrong,
                        width: spec.borderWidth,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题行 + 强调色圆点
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 6,
                              decoration: BoxDecoration(
                                color: spec.text,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 10,
                              height: 10,
                              decoration:
                                  BoxDecoration(color: spec.accent, shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 正文行
                        Container(
                          width: 84,
                          height: 4,
                          decoration: BoxDecoration(
                            color: spec.textDim.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 64,
                          height: 4,
                          decoration: BoxDecoration(
                            color: spec.textDim.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Spacer(),
                        // 主按钮
                        Container(
                          width: 48,
                          height: 14,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: spec.primary,
                            borderRadius: BorderRadius.circular(spec.buttonRadius),
                            border: spec.borderWidth > 1
                                ? Border.all(
                                    color: spec.borderStrong,
                                    width: spec.borderWidth,
                                  )
                                : null,
                          ),
                          child: Container(
                            width: 24,
                            height: 3,
                            decoration: BoxDecoration(
                              color: spec.onPrimary,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              appThemeLabel(widget.theme),
              style: TextStyle(
                fontSize: 12,
                color: widget.selected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                fontWeight:
                    widget.selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
