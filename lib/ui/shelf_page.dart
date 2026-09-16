import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'app_root.dart';
import 'app_theme.dart';
import 'common/book_cover.dart';
import 'common/dialogs.dart';
import 'widgets/app_bar_nav_actions.dart';
import 'widgets/window_controls.dart';
import 'workspace_page.dart';

/// 书架页（9.1 首页）：作品列表、新建作品、回收站、设置、账号。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<SettingsController>().theme;
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
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 20,
                crossAxisSpacing: 18,
                childAspectRatio: 0.72,
              ),
              itemCount: state.bookList.length,
              itemBuilder: (ctx, i) =>
                  _BookCard(book: state.bookList[i], theme: theme),
            ),
      floatingActionButton: FloatingActionButton.extended(
        mouseCursor: SystemMouseCursors.click,
        icon: const Icon(Icons.add),
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
          // 三本迷你书本装饰。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniBook(scheme.primaryContainer, scheme.onPrimaryContainer, -0.12),
              const SizedBox(width: 14),
              _miniBook(scheme.secondaryContainer, scheme.onSecondaryContainer, 0),
              const SizedBox(width: 14),
              _miniBook(scheme.tertiaryContainer, scheme.onTertiaryContainer, 0.12),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '书架还是空的',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点击右下角「新建作品」，开始你的第一部小说',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 空态迷你书本：带书脊的小书封。
  Widget _miniBook(Color bg, Color fg, double tilt) {
    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: 46,
        height: 68,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(width: 6, color: fg.withAlpha(60)),
            Expanded(
              child: Center(
                child: Container(width: 14, height: 2, color: fg.withAlpha(90)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBook(BuildContext ctx) async {
    final values = await createBookDialog(ctx);
    if (values == null || ctx.mounted == false) return;
    final state = appState(ctx);
    await state.createBook(values.$1, values.$2, coverPath: values.$3);
  }
}

/// 书籍卡片：立体书脊书封。
/// 未上传封面时显示主题默认背景图 + 书名首字；hover 上浮并浮现编辑/删除按钮。
class _BookCard extends StatefulWidget {
  const _BookCard({required this.book, required this.theme});

  final Book book;
  final AppTheme theme;

  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  bool _hovered = false;
  ImageProvider? _coverImage;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant _BookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.coverPath != widget.book.coverPath) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    final provider = await BookCover.providerFor(widget.book.coverPath);
    if (!mounted) return;
    setState(() => _coverImage = provider);
  }

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
    final book = widget.book;
    final result = await editBookDialog(
      context,
      bookId: book.id,
      initialTitle: book.title,
      initialPenName: book.penName,
      initialCoverPath: book.coverPath,
    );
    if (result == null || !mounted) return;
    final (title, penName, coverAction) = result;
    await state.books.rename(book.id, title);
    await state.books.updateMeta(book.id, penName, book.summary);
    if (coverAction != null) {
      if (coverAction.isEmpty) {
        await BookCover.deleteFile(book.coverPath);
        await state.books.updateCover(book.id, '');
      } else if (coverAction != book.coverPath) {
        if (book.coverPath.isNotEmpty) {
          await BookCover.deleteFile(book.coverPath);
        }
        await state.books.updateCover(book.id, coverAction);
      }
    }
    await state.loadShelf();
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
    final scheme = Theme.of(context).colorScheme;
    final isEggPie = widget.theme == AppTheme.eggPie;
    final radius = isEggPie ? 2.0 : 8.0;
    final hasCustom = _coverImage != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _open,
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
                  // 背景：自定义封面图，或主题色渐变（与页面协调）。
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
                        padding: EdgeInsets.all(isEggPie ? 6.0 : 10.0),
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
                        padding: EdgeInsets.all(isEggPie ? 9.0 : 14.0),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            book.title,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              color: hasCustom
                                  ? Colors.white
                                  : scheme.onSurface.withAlpha(230),
                              shadows: hasCustom
                                  ? const [
                                      Shadow(blurRadius: 6, color: Colors.black54),
                                      Shadow(blurRadius: 14, color: Colors.black26),
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
                            book.penName.isEmpty ? '未署名' : book.penName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1,
                              color: hasCustom
                                  ? Colors.white70
                                  : scheme.onSurfaceVariant,
                              shadows: hasCustom
                                  ? const [
                                      Shadow(blurRadius: 6, color: Colors.black54),
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // hover 浮现操作按钮（右下角）。
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _circleAction(Icons.edit_outlined, '编辑信息', _edit),
                          const SizedBox(width: 4),
                          _circleAction(Icons.delete_outline, '删除作品', _delete),
                        ],
                      ),
                    ),
                  ),
                  if (isEggPie)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: scheme.outline,
                              width: 2,
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
      ),
    );
  }

  /// 书名与作者之间的分隔装饰：线 - 菱形 - 线。
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
