import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';

/// 最近打开的书籍标签栏：主页与工作区顶栏共用。
/// 点击标签打开 / 切换书籍；悬浮显示关闭按钮；「＋」紧跟末尾标签，
/// 点击弹出锚定浮层，可从最近关闭或书架其他书籍中加入并打开。
class RecentBookTabs extends StatefulWidget {
  const RecentBookTabs({
    super.key,
    this.selectedBookId,
    required this.onSelect,
    required this.onClose,
  });

  /// 当前打开的书籍 id（工作区中高亮选中态；主页不传）。
  final String? selectedBookId;
  final ValueChanged<Book> onSelect;
  final ValueChanged<Book> onClose;

  @override
  State<RecentBookTabs> createState() => _RecentBookTabsState();
}

class _RecentBookTabsState extends State<RecentBookTabs> {
  /// 「＋」与浮层同组：点「＋」不触发浮层的点外关闭，由按钮自身 toggle。
  static const _kPickerGroup = ValueKey('recent-book-picker');
  static const _panelWidth = 300.0;

  final _layerLink = LayerLink();
  final _portalController = OverlayPortalController();
  final _plusKey = GlobalKey();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _togglePicker() {
    if (_portalController.isShowing) {
      _portalController.hide();
    } else {
      _searchController.clear();
      _query = '';
      _portalController.show();
    }
  }

  /// 从浮层选中书籍：加入标签栏（同时清除其隐藏记录）并打开。
  void _pick(Book book) {
    _portalController.hide();
    context.read<SettingsController>().touchRecentBook(book.id);
    widget.onSelect(book);
  }

  List<Book> _matchBooks(List<Book> source) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where(
          (b) =>
              b.title.toLowerCase().contains(q) ||
              b.penName.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsController>();
    final bookList = context.watch<AppState>().bookList;
    final byId = {for (final b in bookList) b.id: b};
    final books = [
      for (final id in settings.recentBookIds)
        if (byId[id] != null) byId[id]!,
    ];
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (_) =>
          _buildPickerOverlay(settings, bookList, byId),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final book in books)
              _BookTab(
                book: book,
                selected: book.id == widget.selectedBookId,
                onSelect: () => widget.onSelect(book),
                onClose: () => widget.onClose(book),
              ),
            CompositedTransformTarget(
              link: _layerLink,
              child: TapRegion(
                groupId: _kPickerGroup,
                child: IconButton(
                  key: _plusKey,
                  tooltip: '打开书籍',
                  icon:
                      Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
                  onPressed: _togglePicker,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「＋」下方的书籍选择浮层：最近关闭区 + 可搜索的书架其他书籍。
  Widget _buildPickerOverlay(
    SettingsController settings,
    List<Book> bookList,
    Map<String, Book> byId,
  ) {
    final scheme = Theme.of(context).colorScheme;

    // 依据「＋」在 overlay 中的位置定位：靠右时改为右对齐，高度钳制在窗内。
    var left = 0.0;
    var top = 48.0;
    var maxH = 440.0;
    var rightAlign = false;
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (box != null && overlay != null && box.attached && overlay.attached) {
      final size = overlay.size;
      final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
      top = pos.dy + box.size.height + 4;
      maxH = (size.height - top - 8).clamp(0.0, 440.0);
      if (pos.dx + _panelWidth > size.width - 8) rightAlign = true;
      left = pos.dx;
    }

    final hiddenBooks = _matchBooks([
      for (final id in settings.hiddenRecentBookIds)
        if (byId[id] != null) byId[id]!,
    ]);
    final hiddenIds = hiddenBooks.map((b) => b.id).toSet();
    final shelfBooks = _matchBooks(
      bookList
          .where(
            (b) =>
                !settings.recentBookIds.contains(b.id) &&
                !hiddenIds.contains(b.id),
          )
          .toList(),
    );

    final entries = <_PickerEntry>[
      if (hiddenBooks.isNotEmpty) const _PickerEntry.header('最近关闭'),
      for (final b in hiddenBooks) _PickerEntry.book(b),
      if (shelfBooks.isNotEmpty) const _PickerEntry.header('书架'),
      for (final b in shelfBooks) _PickerEntry.book(b),
    ];

    return Positioned(
      left: rightAlign ? null : left,
      right: rightAlign ? 8.0 : null,
      top: top,
      child: Material(
        color: scheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: TapRegion(
          groupId: _kPickerGroup,
          onTapOutside: (_) => _portalController.hide(),
          child: Container(
            width: _panelWidth,
            constraints: BoxConstraints(maxHeight: maxH <= 0 ? 1 : maxH),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索书名或作者',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 36,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            '没有找到匹配的书籍',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: entries.length,
                          itemBuilder: (ctx, i) {
                            final e = entries[i];
                            if (e.isHeader) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                                child: Text(
                                  e.title!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            final b = e.book!;
                            return _PickerItem(
                              book: b,
                              onTap: () => _pick(b),
                            );
                          },
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

/// 浮层列表项：分区标题或书籍条目。
class _PickerEntry {
  const _PickerEntry.header(this.title)
      : book = null,
        isHeader = true;

  const _PickerEntry.book(this.book)
      : title = null,
        isHeader = false;

  final String? title;
  final Book? book;
  final bool isHeader;
}

/// 浮层书籍条目：书本图标 + 书名，悬浮高亮。
class _PickerItem extends StatefulWidget {
  const _PickerItem({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  State<_PickerItem> createState() => _PickerItemState();
}

class _PickerItemState extends State<_PickerItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个书籍标签：书本图标 + 书名，选中底色更深，悬浮显示关闭按钮。
class _BookTab extends StatefulWidget {
  const _BookTab({
    required this.book,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final Book book;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<_BookTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 界面字号放大后中文字形的视觉中心偏移更大，图标随之下移。
    final iconDy =
        MediaQuery.textScalerOf(context).scale(1.0) > 1.0 ? 2.0 : 1.0;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(
                alpha: widget.selected ? 0.22 : (_hover ? 0.16 : 0.10),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, iconDy),
                  child: Icon(Icons.auto_stories_outlined,
                      size: 16, color: scheme.primary),
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                // 关闭按钮位置常驻，仅切换显隐，避免悬浮时标签宽度变化。
                const SizedBox(width: 2),
                IgnorePointer(
                  ignoring: !_hover && !widget.selected,
                  child: AnimatedOpacity(
                    opacity: _hover || widget.selected ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Transform.translate(
                        offset: Offset(0, iconDy),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
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
}
