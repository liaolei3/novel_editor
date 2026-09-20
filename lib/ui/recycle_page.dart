import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../core/utils/rich_text_codec.dart';
import '../../core/utils/text_stats.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'app_root.dart';
import 'common/book_cover.dart';
import 'widgets/toast.dart';
import 'widgets/window_controls.dart';

/// 回收站作用域：书架页只看删除的书籍；工作区只看当前书的卷/章/素材。
enum RecycleScope { shelf, workspace }

/// 回收站（FR-6 / NFR-R5 / 9.1）：时间线展示，保留 30 天，可恢复/彻底删除。
class RecyclePage extends StatelessWidget {
  const RecyclePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: const Text('回收站')),
      body: const RecycleView(scope: RecycleScope.shelf),
    );
  }
}

/// 回收站内容（无页头），书架页与工作区侧边面板按作用域复用。
class RecycleView extends StatefulWidget {
  const RecycleView({super.key, required this.scope});

  final RecycleScope scope;

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

  List<RecycleItem> _visible() {
    final state = context.read<AppState>();
    if (widget.scope == RecycleScope.shelf) {
      return _items.where((i) => i.type == RecycleType.book).toList();
    }
    final bookId = state.currentBook?.id;
    if (bookId == null) return const [];
    return _items
        .where(
          (i) =>
              i.type != RecycleType.book &&
              _decode(i.payload)['book_id'] == bookId,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible();
    return widget.scope == RecycleScope.shelf
        ? _ShelfRecycleBody(
            items: items,
            onClearAll: () => _clearAll(items),
            onRestore: _restore,
            onPurge: _purge,
          )
        : _WorkspaceRecycleBody(
            items: items,
            onClearAll: () => _clearAll(items),
            onRestore: _restore,
            onPurge: _purge,
          );
  }

  Future<void> _restore(RecycleItem item) async {
    final state = context.read<AppState>();
    await state.restoreRecycleItem(item);
    await _refresh();
    if (mounted) {
      showToast(context, '「${_titleOf(item)}」恢复成功');
    }
  }

  Future<void> _purge(RecycleItem item) async {
    final ok = await confirmDangerous(
      context,
      '彻底删除「${_titleOf(item)}」？此操作不可撤销。',
    );
    if (!ok) return;
    await context.read<AppState>().purgeRecycleItem(item);
    await _refresh();
  }

  Future<void> _clearAll(List<RecycleItem> items) async {
    final ok = await confirmDangerous(
      context,
      '清空回收站？当前显示的 ${items.length} 项将被彻底删除，不可撤销。',
    );
    if (!ok) return;
    final state = context.read<AppState>();
    for (final item in List.of(items)) {
      await state.purgeRecycleItem(item);
    }
    await _refresh();
  }
}

/// 书架作用域布局：与书架一致的封面卡片网格，附加删除日期与剩余天数。
class _ShelfRecycleBody extends StatelessWidget {
  const _ShelfRecycleBody({
    required this.items,
    required this.onClearAll,
    required this.onRestore,
    required this.onPurge,
  });

  final List<RecycleItem> items;
  final VoidCallback onClearAll;
  final ValueChanged<RecycleItem> onRestore;
  final ValueChanged<RecycleItem> onPurge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              Text(
                '已删书籍保留 30 天，过期自动彻底删除',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: items.isEmpty ? null : onClearAll,
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('清空回收站', style: TextStyle(fontSize: 13)),
                style:
                    TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ).copyWith(
                      mouseCursor: const WidgetStatePropertyAll(
                        SystemMouseCursors.click,
                      ),
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 40,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '回收站为空',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 18,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) => _ShelfRecycleCard(
                    item: items[i],
                    onRestore: () => onRestore(items[i]),
                    onPurge: () => onPurge(items[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 回收站书籍卡片：复刻书架封面样式，底部加删除信息条，hover 浮现恢复/彻底删除。
class _ShelfRecycleCard extends StatefulWidget {
  const _ShelfRecycleCard({
    required this.item,
    required this.onRestore,
    required this.onPurge,
  });

  final RecycleItem item;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  State<_ShelfRecycleCard> createState() => _ShelfRecycleCardState();
}

class _ShelfRecycleCardState extends State<_ShelfRecycleCard> {
  bool _hovered = false;
  ImageProvider? _coverImage;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  Future<void> _loadCover() async {
    final path = _decode(widget.item.payload)['cover_path'] as String? ?? '';
    if (path.isEmpty) return;
    final provider = await BookCover.providerFor(path);
    if (!mounted) return;
    setState(() => _coverImage = provider);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final radius = 8.0;
    final hasCustom = _coverImage != null;
    final daysLeft = item.expireAt
        .difference(DateTime.now())
        .inDays
        .clamp(0, 30);
    final info =
        '${item.deletedAt.month}月${item.deletedAt.day}日删除 · 剩余 $daysLeft 天';
    final fg = hasCustom ? Colors.white : scheme.onSurface.withAlpha(230);
    final subFg = hasCustom ? Colors.white70 : scheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.04 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_hovered ? 72 : 40),
                blurRadius: _hovered ? 16 : 6,
                offset: Offset(0, _hovered ? 8 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCustom)
                  Image(image: _coverImage!, fit: BoxFit.cover)
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.surfaceContainerHighest,
                          scheme.surfaceContainer,
                        ],
                      ),
                    ),
                  ),
                // 装饰双线框（仅默认封面，经典书封样式）。
                if (!hasCustom) ...[
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: scheme.onSurface.withAlpha(70),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: scheme.onSurface.withAlpha(38),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // 左侧书脊阴影。
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 12,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0x52000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
                // 居中书名 + 作者。
                Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      hasCustom ? 22 : 30,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _titleOf(item),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: fg,
                            shadows: hasCustom
                                ? const [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black54,
                                    ),
                                    Shadow(
                                      blurRadius: 14,
                                      color: Colors.black26,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!hasCustom) ...[
                          _ornament(scheme.onSurface.withAlpha(90)),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          _penOf(item),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: subFg,
                            shadows: hasCustom
                                ? const [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black54,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 底部删除信息条。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    color: Colors.black.withAlpha(hasCustom ? 110 : 28),
                    alignment: Alignment.center,
                    child: Text(
                      info,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.3,
                        color: hasCustom
                            ? Colors.white.withAlpha(230)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                // hover 浮现操作按钮（右下角，信息条上方）。
                Positioned(
                  bottom: 30,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _circleAction(
                          Icons.restore_outlined,
                          '恢复',
                          widget.onRestore,
                        ),
                        const SizedBox(width: 4),
                        _circleAction(
                          Icons.delete_forever,
                          '彻底删除',
                          widget.onPurge,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ornament(Color color) {
    return SizedBox(
      width: 76,
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: color)),
          Transform.rotate(
            angle: 3.14159 / 4,
            child: Container(width: 5, height: 5, color: color),
          ),
          Expanded(child: Container(height: 1, color: color)),
        ],
      ),
    );
  }

  Widget _circleAction(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: Color(0x96000000),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

/// 工作区作用域布局：紧凑时间线（面板空间有限，保持原样式）。
class _WorkspaceRecycleBody extends StatelessWidget {
  const _WorkspaceRecycleBody({
    required this.items,
    required this.onClearAll,
    required this.onRestore,
    required this.onPurge,
  });

  final List<RecycleItem> items;
  final VoidCallback onClearAll;
  final ValueChanged<RecycleItem> onRestore;
  final ValueChanged<RecycleItem> onPurge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '回收站',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '已删卷/章/角色/伏笔/素材保留 30 天',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '清空回收站',
                iconSize: 26,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_forever,
                  color: items.isEmpty ? null : scheme.error,
                ),
                onPressed: items.isEmpty ? null : onClearAll,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 36,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      const Text('回收站为空', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                  children: _buildTimeline(context, items),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildTimeline(BuildContext context, List<RecycleItem> items) {
    final widgets = <Widget>[];
    String? lastDay;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final day = _wsDayLabel(item.deletedAt);
      final newGroup = day != lastDay;
      if (newGroup) {
        lastDay = day;
        widgets.add(_dateHeader(context, day));
      }
      final isOverallLast = i == items.length - 1;
      final isLastOfDay =
          isOverallLast || _wsDayLabel(items[i + 1].deletedAt) != day;
      widgets.add(
        _TimelineTile(
          item: item,
          showTopLine: !newGroup,
          showBottomLine: !isOverallLast && !isLastOfDay,
          onRestore: () => onRestore(item),
          onPurge: () => onPurge(item),
        ),
      );
    }
    return widgets;
  }

  String _wsDayLabel(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天';
    }
    final y = now.subtract(const Duration(days: 1));
    if (t.year == y.year && t.month == y.month && t.day == y.day) {
      return '昨天';
    }
    if (t.year == now.year) return '${t.month}月${t.day}日';
    return '${t.year}年${t.month}月${t.day}日';
  }
}

Widget _dateHeader(BuildContext context, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

String _titleOf(RecycleItem item) {
  final payload = _decode(item.payload);
  return payload['title'] as String? ?? payload['name'] as String? ?? '（未命名）';
}

String _penOf(RecycleItem item) {
  final pen = _decode(item.payload)['pen_name'] as String? ?? '';
  return pen.isEmpty ? '未署名' : pen;
}

Map<String, Object?> _decode(String payload) {
  try {
    return Map<String, Object?>.from(jsonDecode(payload) as Map);
  } catch (_) {
    return const {};
  }
}

IconData _iconFor(RecycleType t) => switch (t) {
  RecycleType.book => Icons.menu_book_outlined,
  RecycleType.volume => Icons.folder_off_outlined,
  RecycleType.chapter => Icons.description_outlined,
  RecycleType.note => Icons.sticky_note_2_outlined,
  RecycleType.character => Icons.person_outline,
  RecycleType.foreshadow => Icons.flag_outlined,
};

Color _colorFor(RecycleType t, ColorScheme scheme) => switch (t) {
  RecycleType.book => scheme.primary,
  RecycleType.volume => scheme.secondary,
  RecycleType.chapter => scheme.tertiary,
  RecycleType.character => const Color(0xFF4A90D9),
  RecycleType.foreshadow => const Color(0xFF7B61C9),
  RecycleType.note => const Color(0xFF4CAF7D),
};

String _typeLabel(RecycleType t) => switch (t) {
  RecycleType.book => '书籍',
  RecycleType.volume => '卷',
  RecycleType.chapter => '章节',
  RecycleType.note => '素材',
  RecycleType.character => '角色',
  RecycleType.foreshadow => '伏笔',
};

const _characterLabels = {
  'protagonist': '主角',
  'supporting': '配角',
  'antagonist': '反派',
  'minor': '龙套',
};

const _noteLabels = {'role': '角色卡', 'world': '世界观', 'idea': '灵感便签'};

/// 按类型生成附加信息：书籍显示笔名、卷显示含章数、章节显示字数等。
String _extraInfo(RecycleItem item, BuildContext context) {
  final payload = _decode(item.payload);
  switch (item.type) {
    case RecycleType.book:
      final pen = payload['pen_name'] as String? ?? '';
      return pen.isEmpty ? '未署名' : pen;
    case RecycleType.volume:
      final chs = (payload['chapters'] as List<Object?>?) ?? const [];
      return '含 ${chs.length} 章';
    case RecycleType.chapter:
      final std = context.read<SettingsController>().countStandard;
      final chars = TextStats.count(
        RichTextCodec.plainTextFromDeltaJson(
          payload['content'] as String? ?? '',
        ),
        std,
      );
      return '$chars 字';
    case RecycleType.character:
      final t = payload['type'] as String?;
      return _characterLabels[t] ?? '';
    case RecycleType.foreshadow:
      return payload['status'] == 'done' ? '已完成' : '未完成';
    case RecycleType.note:
      final t = payload['type'] as String?;
      return _noteLabels[t] ?? '';
  }
}

class _TimelineTile extends StatefulWidget {
  const _TimelineTile({
    required this.item,
    required this.showTopLine,
    required this.showBottomLine,
    required this.onRestore,
    required this.onPurge,
  });

  final RecycleItem item;
  final bool showTopLine;
  final bool showBottomLine;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  State<_TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends State<_TimelineTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final color = _colorFor(item.type, scheme);
    final daysLeft = item.expireAt
        .difference(DateTime.now())
        .inDays
        .clamp(0, 30);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: _hovering
              ? scheme.onSurface.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(child: _line(scheme, widget.showTopLine)),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_iconFor(item.type), size: 17, color: color),
                    ),
                    Expanded(
                      child: Center(
                        child: _line(scheme, widget.showBottomLine),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titleOf(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_typeLabel(item.type)} · ${_extraInfo(item, context)} · 剩余 $daysLeft 天',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _hovering ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: IgnorePointer(
                          ignoring: !_hovering,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _actionButton('恢复', widget.onRestore),
                              _actionButton(
                                '彻底删除',
                                widget.onPurge,
                                danger: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(ColorScheme scheme, bool visible) {
    return Container(
      width: 2,
      color: visible
          ? scheme.outlineVariant.withValues(alpha: 0.6)
          : Colors.transparent,
    );
  }

  Widget _actionButton(
    String text,
    VoidCallback onPressed, {
    bool danger = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        foregroundColor: danger ? scheme.error : scheme.primary,
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
