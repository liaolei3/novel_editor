import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import 'app_root.dart';
import 'widgets/app_icon.dart';
import 'widgets/toast.dart';
import 'widgets/window_controls.dart';

/// 回收站（FR-6 / NFR-R5 / 9.1）：已删卷/章/素材，保留 30 天，可恢复/彻底删除。
class RecyclePage extends StatelessWidget {
  const RecyclePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: const Text('回收站')),
      body: const RecycleView(),
    );
  }
}

/// 回收站内容（无页头），供回收站页与工作区侧边面板复用。
class RecycleView extends StatefulWidget {
  const RecycleView({super.key});

  @override
  State<RecycleView> createState() => _RecycleViewState();
}

class _RecycleViewState extends State<RecycleView> {
  List<RecycleItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final items = await context.read<AppState>().recycle.list();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          dense: true,
          title: const Text('回收站'),
          subtitle: Text(
            '已删卷/章/素材保留 30 天',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: IconButton(
            tooltip: '清空回收站',
            icon: const AppIcon(Icons.delete_forever),
            onPressed: _items.isEmpty ? null : _clearAll,
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: Text('回收站为空'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final title = _titleOf(item);
                    final daysLeft = item.expireAt
                        .difference(DateTime.now())
                        .inDays
                        .clamp(0, 30);
                    return ListTile(
                      leading: AppIcon(_iconOf(item.type)),
                      title: Text(title),
                      subtitle: Text('$daysLeft 天后自动清除（保留 30 天）'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                            onPressed: () => _restore(item),
                            child: const Text('恢复')),
                        TextButton(
                            onPressed: () => _purge(item),
                            child: Text('彻底删除',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _titleOf(RecycleItem item) {
    final payload = _decode(item.payload);
    return payload['title'] as String? ??
        payload['name'] as String? ??
        '（未命名）';
  }

  IconData _iconOf(RecycleType t) => switch (t) {
        RecycleType.volume => Icons.folder_off_outlined,
        RecycleType.chapter => Icons.description,
        RecycleType.note => Icons.sticky_note_2_outlined,
        RecycleType.character => Icons.person_outline,
      };

  Future<void> _restore(RecycleItem item) async {
    final state = context.read<AppState>();
    await state.restoreRecycleItem(item);
    await _refresh();
    if (mounted) {
      showToast(context, '已恢复「${_titleOf(item)}」');
    }
  }

  Future<void> _purge(RecycleItem item) async {
    final ok = await confirmDangerous(context, '彻底删除「${_titleOf(item)}」？此操作不可撤销。');
    if (!ok) return;
    await context.read<AppState>().recycle.remove(item.id);
    await _refresh();
  }

  Future<void> _clearAll() async {
    final ok = await confirmDangerous(context, '清空回收站？全部内容将被彻底删除，不可撤销。');
    if (!ok) return;
    final state = context.read<AppState>();
    for (final item in List.of(_items)) {
      await state.recycle.remove(item.id);
    }
    await _refresh();
  }

  static Map<String, Object?> _decode(String payload) {
    try {
      return Map<String, Object?>.from(jsonDecode(payload) as Map);
    } catch (_) {
      return const {};
    }
  }
}
