import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';


import '../../core/utils/sensitive_words.dart';
import '../../data/db.dart';
import '../../state/app_config.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'common/file_io.dart';
import 'conflict_page.dart';
import 'widgets/top_message.dart';
import 'recycle_page.dart';
import 'widgets/app_icon.dart';
import 'widgets/window_controls.dart';

/// 设置页（9.8）：同步开关、AI 配置、自动保存频率、夜间模式、字体行距、敏感词词库、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: const AppTopBar(title: Text('设置')),
      body: ListView(padding: const EdgeInsets.all(16), children: _spaced([
        _section(context, '外观'),
        ListTile(
          title: Text('字体大小：${settings.fontSize.round()}'),
          subtitle: Slider(
            min: 13, max: 26, divisions: 13,
            value: settings.fontSize,
            onChanged: settings.setFontSize,
          ),
        ),
        ListTile(
          title: Text('行距：${settings.lineHeight.toStringAsFixed(1)} 倍'),
          subtitle: Slider(
            min: 1.2, max: 2.6, divisions: 14,
            value: settings.lineHeight,
            onChanged: settings.setLineHeight,
          ),
        ),
        _section(context, '写作'),
        ListTile(
          title: Text('自动保存停顿：${settings.autosaveSeconds} 秒'),
          subtitle: const Text('输入停顿后落盘；另有 30 秒兜底保存（FR-2）'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1s')),
              ButtonSegment(value: 2, label: Text('2s')),
              ButtonSegment(value: 5, label: Text('5s')),
            ],
            selected: {settings.autosaveSeconds},
            onSelectionChanged: (s) => settings.setAutosaveSeconds(s.first),
          ),
        ),
        ListTile(
          title: Text('每日码字目标：${settings.dailyGoal} 字'),
          subtitle: Slider(
            min: 500, max: 10000, divisions: 19,
            label: '${settings.dailyGoal}',
            value: settings.dailyGoal.toDouble(),
            onChanged: (v) => settings.setDailyGoal(v.round()),
          ),
        ),
        _section(context, '同步与账号（FR-12/13）'),
        SwitchListTile(
          title: const Text('云同步'),
          subtitle: const Text('本地优先；联网时自动增量同步。关闭不影响本地写作。'),
          value: settings.syncEnabled,
          onChanged: (v) => settings.setSyncEnabled(v),
        ),
        ListTile(
          title: const Text('立即同步'),
          subtitle: const Text('检测并推送/拉取增量；若同章双端修改将进入冲突解决'),
          trailing: const AppIcon(Icons.sync),
          onTap: () => _syncNow(context, state),
        ),
        _section(context, 'AI 配置（FR-16~20）'),
        ListTile(
          title: const Text('AI 网关'),
          subtitle: Text(settings.aiBaseUrl.isEmpty
              ? '未配置（自动降级为纯写作模式）'
              : '${settings.aiModel} @ ${settings.aiBaseUrl}'),
          onTap: () => _editAi(context, settings),
        ),
        _section(context, '敏感词词库'),
        ListTile(
          title: Text('当前词库：${settings.sensitiveDictVersion}'),
          subtitle: const Text('从 TXT 导入更新（一行一词，# 开头为注释）'),
          trailing: const AppIcon(Icons.upload_file),
          onTap: () => _importDict(context, settings),
        ),
        _section(context, '数据'),
        FutureBuilder<String>(
          future: settings.dataDir.isNotEmpty
              ? Future.value(settings.dataDir)
              : Db.defaultDir(),
          builder: (context, snap) => ListTile(
            title: const Text('数据存储目录'),
            subtitle: Text(
              snap.data ?? '读取中…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const AppIcon(Icons.folder_open),
            onTap:
                snap.hasData ? () => _changeDataDir(context, snap.data!) : null,
          ),
        ),
        ListTile(
          title: const Text('回收站'),
          subtitle: const Text('删除的卷/章/素材保留 30 天'),
          trailing: const AppIcon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const RecyclePage())),
        ),
        ListTile(
          title: const Text('关于'),
          subtitle: const Text('NovelEditor MVP 0.1.0 · 本地数据双副本 + 快照 + 崩溃恢复'),
        ),
      ])),
    );
  }

  /// 切换数据存储目录：选目录 → 确认 → 迁移数据 → 保存设置（重启后生效）。
  Future<void> _changeDataDir(BuildContext context, String currentDir) async {
    final target = await FileIO.pickDirectory();
    if (target == null || target == currentDir) return;
    final hasExisting = File(p.join(target, 'novel_editor.db')).existsSync();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
    if (confirmed != true) return;
    try {
      if (!hasExisting) await Db.migrateDataTo(target);
      await Db.anchorDataDir(target);
      await context.read<SettingsController>().setDataDir(target);
      // 当前配置写入新目录，重启后新目录内配置即完整。
      await AppConfig.instance.saveTo(target);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已切换'),
          content: const Text('数据存储目录已更新，重启应用后生效。'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showTopMessage(context, '切换失败：$e');
      }
    }
  }

  Future<void> _syncNow(BuildContext context, AppState state) async {
    if (state.currentBook == null) {
      showTopMessage(context, '请先打开一部作品');
      return;
    }
    final conflicts = await state.syncNow();
    if (!context.mounted) return;
    if (conflicts.isEmpty) {
      showTopMessage(context, '同步完成，无冲突');
      return;
    }
    final resolved = await showDialog<bool>(
      context: context,
      builder: (_) => ConflictDialog(conflicts: conflicts),
    );
    if (resolved == true && context.mounted) {
      showTopMessage(context, '冲突已解决并完成同步');
      await state.reloadTreePublic();
    }
  }

  Future<void> _editAi(BuildContext context, SettingsController settings) async {
    final urlCtrl = TextEditingController(text: settings.aiBaseUrl);
    final keyCtrl = TextEditingController(text: settings.aiApiKey);
    final modelCtrl = TextEditingController(text: settings.aiModel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
    if (ok == true) {
      await settings.setAiConfig(urlCtrl.text.trim(), keyCtrl.text.trim(), modelCtrl.text.trim());
    }
  }

  Future<void> _importDict(BuildContext context, SettingsController settings) async {
    final raw = await FileIO.pickReadText();
    if (raw == null) return;
    final scanner = SensitiveWordScanner.parse(raw);
    await settings.setSensitiveDictVersion('导入词库 ${scanner.words.length} 词');
    if (context.mounted) {
      showTopMessage(context, '词库已更新（${scanner.words.length} 词）');
    }
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  /// 相邻设置项之间加入少量上下间隔。
  List<Widget> _spaced(Iterable<Widget> children) {
    final list = <Widget>[];
    for (final child in children) {
      list
        ..add(child)
        ..add(const SizedBox(height: 4));
    }
    return list;
  }
}