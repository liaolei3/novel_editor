import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../services/durability_service.dart';
import '../state/app_state.dart';
import 'app_root.dart';
import 'common/dialogs.dart';

import 'widgets/app_bar_nav_actions.dart';
import 'widgets/app_icon.dart';
import 'widgets/window_controls.dart';
import 'workspace_page.dart';

/// 书架页（9.1 首页）：作品列表、新建作品、回收站、设置、账号。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key, this.crashReport});

  final CrashReport? crashReport;

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await appState(context).loadShelf();
      if (mounted) setState(() => _loading = false);
      if (widget.crashReport != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '检测到上次异常退出，已自动恢复至最后一次保存点。如需更早版本，请进入章节的「历史快照」找回。',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: '知道了', onPressed: () {}),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppTopBar(
        title: const Text('书架'),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: const [AppBarNavActions()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : state.bookList.isEmpty
          ? _empty(context)
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.86,
              ),
              itemCount: state.bookList.length,
              itemBuilder: (ctx, i) =>
                  _bookCard(ctx, state.bookList[i], scheme),
            ),
      floatingActionButton: FloatingActionButton.extended(
        mouseCursor: SystemMouseCursors.click,
        icon: const AppIcon(Icons.add),
        label: const Text('新建作品'),
        onPressed: () => _createBook(context),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 56,
            color: scheme.primary.withAlpha(100),
          ),
          const SizedBox(height: 20),
          Text(
            '还没有作品',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点击右下角开始创作',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _bookCard(BuildContext ctx, Book book, ColorScheme scheme) {
    return _BookCard(book: book, scheme: scheme);
  }

  Future<void> _createBook(BuildContext ctx) async {
    final values = await createBookDialog(ctx);
    if (values == null || ctx.mounted == false) return;
    final state = appState(ctx);
    await state.createBook(values.$1, values.$2);
  }
}

/// 书籍卡片：hover 时右上角浮现编辑/删除图标，悬停图标显示文字 tooltip。
class _BookCard extends StatefulWidget {
  const _BookCard({required this.book, required this.scheme});

  final Book book;
  final ColorScheme scheme;

  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  bool _hovered = false;

  Future<void> _open() async {
    final state = appState(context);
    await state.openBook(widget.book);
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WorkspacePage(book: widget.book)),
      );
      await state.loadShelf();
    }
  }

  Future<void> _edit() async {
    final state = appState(context);
    final result = await editBookDialog(
      context,
      initialTitle: widget.book.title,
      initialPenName: widget.book.penName,
    );
    if (result != null && mounted) {
      await state.books.rename(widget.book.id, result.$1);
      await state.books.updateMeta(
        widget.book.id,
        result.$2,
        widget.book.summary,
      );
      await state.loadShelf();
    }
  }

  Future<void> _delete() async {
    final state = appState(context);
    final ok = await confirmDangerous(
      context,
      '确定删除《${widget.book.title}》？作品将进入回收站保留 30 天。',
    );
    if (ok && mounted) {
      await state.books.softDelete(widget.book.id);
      await state.loadShelf();
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final scheme = widget.scheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: isLight ? (_hovered ? 8 : 2) : 0,
        surfaceTintColor: Colors.transparent,
        child: Stack(
          children: [
            InkWell(
              onTap: _open,
              mouseCursor: SystemMouseCursors.click,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 96,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        book.title.characters.first,
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w300,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.penName.isEmpty ? '未署名' : book.penName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '编辑信息',
                      color: scheme.onSurface,
                      mouseCursor: SystemMouseCursors.click,
                      icon: const AppIcon(Icons.edit_outlined),
                      onPressed: _edit,
                    ),
                    IconButton(
                      tooltip: '删除作品',
                      color: scheme.onSurface,
                      mouseCursor: SystemMouseCursors.click,
                      icon: const AppIcon(Icons.delete_outline),
                      onPressed: _delete,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
