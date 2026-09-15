import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pixelarticons/pixelarticons.dart';
import 'package:provider/provider.dart';


import '../../core/utils/sensitive_words.dart';
import '../../data/db.dart';
import '../../state/app_config.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'app_theme.dart';
import 'common/dialogs.dart';
import 'common/file_io.dart';
import 'conflict_page.dart';
import 'recycle_page.dart';
import 'widgets/app_icon.dart';
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
    final trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
        offset.dx, trackTop, parentBox.size.width, trackHeight);
  }
}

const _categories = [
  _Category(Icons.palette_outlined, '外观'),
  _Category(Icons.edit_note, '写作'),
  _Category(Icons.sync, '同步与账号'),
  _Category(Icons.message_outlined, 'AI 配置'),
  _Category(Icons.folder_open, '数据'),
];

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final state = context.watch<AppState>();
    final isPixel =
        context.watch<SettingsController>().theme == AppTheme.pixel;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hairline = isLight
        ? const Color(0x1A000000)
        : const Color(0x1AFFFFFF);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        const Text('设置'),
        const Spacer(),
        IconButton(
          icon: const AppIcon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 680,
          height: 500,
          child: Column(
            children: [
              Divider(
                height: 1,
                thickness: isPixel ? 2 : 0.5,
                color: isPixel
                    ? const Color(0xFF5B2E0E)
                    : hairline,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 168,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                        child: Column(
                          children: [
                            for (var i = 0; i < _categories.length; i++)
                              _navItem(
                                category: _categories[i],
                                selected: i == _current,
                                isPixel: isPixel,
                                onTap: () =>
                                    setState(() => _current = i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(
                        width: 1,
                        thickness: isPixel ? 1 : 0.5,
                        color: isPixel
                            ? const Color(0x668A5A2A)
                            : hairline),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        children: switch (_current) {
                          0 => _appearance(settings, hairline),
                          1 => _writing(settings, hairline),
                          2 => _sync(settings, state, hairline),
                          3 => _ai(settings, hairline),
                          _ => _data(settings, hairline),
                        },
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

  List<Widget> _appearance(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const Expanded(child: Text('主题')),
              SegmentedButton<AppTheme>(
                segments: const [
                  ButtonSegment(
                      value: AppTheme.light,
                      icon: Tooltip(
                          message: '浅色',
                          child: Icon(Icons.light_mode, size: 16))),
                  ButtonSegment(
                      value: AppTheme.dark,
                      icon: Tooltip(
                          message: '暗色',
                          child: Icon(Icons.dark_mode, size: 16))),
                  ButtonSegment(
                      value: AppTheme.pixel,
                      icon: Tooltip(
                          message: '像素',
                          child: Icon(Pixel.gamepad, size: 20))),
                ],
                selected: {s.theme},
                onSelectionChanged: (v) => s.setTheme(v.first),
                showSelectedIcon: false,
              ),
            ],
          ),
        ),
        _divider(hairline),
        _sliderRow(
          title: '字体大小',
          value: '${s.fontSize.round()}',
          slider: Slider(
            min: 13, max: 26, divisions: 13,
            value: s.fontSize,
            onChanged: s.setFontSize,
          ),
        ),
        _divider(hairline),
        _sliderRow(
          title: '行距',
          value: '${s.lineHeight.toStringAsFixed(1)} 倍',
          slider: Slider(
            min: 1.2, max: 2.6, divisions: 14,
            value: s.lineHeight,
            onChanged: s.setLineHeight,
          ),
        ),
        _divider(hairline),
        _sliderRow(
          title: '段间距',
          value: '${s.paragraphSpacing.toStringAsFixed(1)} 倍',
          slider: Slider(
            min: 0, max: 2.0, divisions: 20,
            value: s.paragraphSpacing,
            onChanged: s.setParagraphSpacing,
          ),
        ),
      ]),
    ];
  }

  List<Widget> _writing(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text('自动保存停顿')),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1s')),
                  ButtonSegment(value: 2, label: Text('2s')),
                  ButtonSegment(value: 5, label: Text('5s')),
                ],
                selected: {s.autosaveSeconds},
                onSelectionChanged: (v) => s.setAutosaveSeconds(v.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('输入停顿后落盘；另有 30 秒兜底保存（FR-2）',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        _sliderRow(
          title: '每日码字目标',
          value: '${s.dailyGoal} 字',
          slider: Slider(
            min: 500, max: 10000, divisions: 19,
            label: '${s.dailyGoal}',
            value: s.dailyGoal.toDouble(),
            onChanged: (v) => s.setDailyGoal(v.round()),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _sync(SettingsController s, AppState state, Color hairline) {
    return [
      _group(hairline, [
        SwitchListTile(
          title: const Text('云同步'),
          subtitle: const Text('本地优先；联网时自动增量同步。\n关闭不影响本地写作。'),
          value: s.syncEnabled,
          onChanged: (v) => s.setSyncEnabled(v),
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        ListTile(
          title: const Text('立即同步'),
          subtitle: const Text('检测并推送/拉取增量；若同章双端修改将进入冲突解决'),
          trailing: const AppIcon(Icons.sync),
          onTap: () => _syncNow(state),
        ),
      ]),
    ];
  }

  List<Widget> _ai(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        ListTile(
          title: const Text('AI 网关'),
          subtitle: Text(s.aiBaseUrl.isEmpty
              ? '未配置（自动降级为纯写作模式）'
              : '${s.aiModel} @ ${s.aiBaseUrl}'),
          trailing: const AppIcon(Icons.chevron_right),
          onTap: _editAi,
        ),
      ]),
    ];
  }

  List<Widget> _data(SettingsController s, Color hairline) {
    return [
      _group(hairline, [
        ListTile(
          title: const Text('敏感词词库'),
          subtitle: Text(
              '当前词库：${s.sensitiveDictVersion}\n从 TXT 导入更新（一行一词，# 开头为注释）'),
          trailing: const AppIcon(Icons.upload_file),
          onTap: _importDict,
        ),
        _divider(hairline),
        FutureBuilder<String>(
          future: s.dataDir.isNotEmpty
              ? Future.value(s.dataDir)
              : Db.defaultDir(),
          builder: (context, snap) => ListTile(
            title: const Text('数据存储目录'),
            subtitle: Text(snap.data ?? '读取中…', maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: const AppIcon(Icons.folder_open),
            onTap:
                snap.hasData ? () => _changeDataDir(snap.data!) : null,
          ),
        ),
        _divider(hairline),
        ListTile(
          title: const Text('回收站'),
          subtitle: const Text('删除的卷/章/素材保留 30 天'),
          trailing: const AppIcon(Icons.chevron_right),
          onTap: _openRecycle,
        ),
      ]),
      const SizedBox(height: 12),
      _group(hairline, [
        const ListTile(
          title: Text('关于'),
          subtitle: Text('NovelEditor MVP 0.1.0 · 本地数据双副本 + 快照 + 崩溃恢复'),
        ),
      ]),
    ];
  }

  /// 卡片与导航选中项的共享底色：选中即「提亮」——
  /// 像素风：羊皮纸底 #FFE9C6 上的亮奶油面板；极简风：surfaceContainerHighest，
  /// 暗色下换更亮的灰色保证与弹窗底的对比。
  Color _panelColor(bool isPixel) {
    if (isPixel) return const Color(0xFFFFF6E0);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return isLight
        ? const Color(0xFFF5F5F7)
        : const Color(0xFF34343A);
  }

  /// 分组卡片：底色与导航选中项一致 + 组内行间分割线。
  /// 组内行统一包透明 Material：ListTile 的背景与墨水效果绘制在
  /// 最近的 Material 上，避免被卡片的 DecoratedBox 背景遮住。
  Widget _group(Color hairline, List<Widget> children) {
    final isPixel =
        context.read<SettingsController>().theme == AppTheme.pixel;
    return Container(
      decoration: BoxDecoration(
        color: _panelColor(isPixel),
        borderRadius: BorderRadius.circular(12),
        border: isPixel
            ? Border.all(color: const Color(0xFF5B2E0E), width: 2)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final child in children)
            Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }

  /// 组内分割线：像素风用棕色，极简风用发丝线。
  Widget _divider(Color hairline) {
    final isPixel =
        context.read<SettingsController>().theme == AppTheme.pixel;
    return Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: isPixel
            ? const Color(0x668A5A2A)
            : hairline);
  }

  /// 滑块行：标题行（左标题 + 右当前值）+ 下方滑块。
  /// 滑块轨道覆盖为全宽 shape，使轨道左右端点与上方文字对齐。
  Widget _sliderRow({
    required String title,
    required String value,
    required Widget slider,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(children: [
        Row(children: [
          Text(title),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        SizedBox(
          height: 28,
          child: SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(trackShape: const _FullWidthTrackShape()),
            child: slider,
          ),
        ),
      ]),
    );
  }

  Widget _navItem({
    required _Category category,
    required bool selected,
    required bool isPixel,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中项：像素风用次级面板色 + 木框；极简风用卡片同色。
    final color = selected ? _panelColor(isPixel) : Colors.transparent;
    final border = selected && isPixel
        ? Border.all(color: const Color(0xFF5B2E0E), width: 2)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: Row(children: [
              AppIcon(category.icon,
                  size: 16,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(category.label,
                  style: TextStyle(
                      fontSize: 13,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        ),
      ),
    );
  }

  /// 切换数据存储目录：选目录 → 确认 → 迁移数据 → 保存设置（重启后生效）。
  Future<void> _changeDataDir(String currentDir) async {
    final target = await FileIO.pickDirectory();
    if (target == null || target == currentDir) return;
    final hasExisting =
        File(p.join(target, 'novel_editor.db')).existsSync();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: const Text('切换数据存储目录'),
          content: Text(hasExisting
              ? '目标目录已包含数据文件，切换后将直接使用该目录中的数据（当前数据保留不动）：\n\n$target'
              : '将把当前全部数据（数据库与备份）迁移到：\n\n$target\n\n迁移后需重启应用生效，当前目录数据不会被删除。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认切换')),
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
                  child: const Text('知道了')),
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
      showToast(context, '冲突已解决并完成同步');
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Base URL（如 https://api.xxx.com/v1）')),
            TextField(controller: keyCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'API Key')),
            TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: '模型名')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await settings.setAiConfig(urlCtrl.text.trim(), keyCtrl.text.trim(), modelCtrl.text.trim());
    }
  }

  Future<void> _importDict() async {
    final raw = await FileIO.pickReadText();
    if (raw == null) return;
    final scanner = SensitiveWordScanner.parse(raw);
    await context.read<SettingsController>()
        .setSensitiveDictVersion('导入词库 ${scanner.words.length} 词');
    if (mounted) {
      showToast(context, '词库已更新（${scanner.words.length} 词）');
    }
  }

  void _openRecycle() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
        MaterialPageRoute(builder: (_) => const RecyclePage()));
  }
}
