import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/txt_importer.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'app_root.dart';
import 'app_theme.dart';
import 'common/book_cover.dart';
import 'common/dialogs.dart';
import 'common/file_io.dart';
import 'login_page.dart';
import 'recycle_page.dart';
import 'stats_page.dart';
import 'widgets/app_bar_nav_actions.dart';
import 'widgets/toast.dart';
import 'widgets/window_controls.dart';
import 'workspace_page.dart';

/// 首页（9.1）：左侧导航（书架/码字统计/回收站）+ 右侧内容区。
/// 点击书本进入工作区为全屏 push，侧栏随之消失，返回后恢复。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

enum _HomeTab { shelf, stats, recycle }

class _ShelfPageState extends State<ShelfPage> {
  _HomeTab _tab = _HomeTab.shelf;

  static const _tabs = [
    (Icons.menu_book, '书架', _HomeTab.shelf),
    (Icons.insights, '码字统计', _HomeTab.stats),
    (Icons.delete_outline, '回收站', _HomeTab.recycle),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = scheme.outlineVariant.withValues(alpha: 0.5);
    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: '主页',
          icon: const Icon(Icons.home_outlined, size: 26),
          onPressed: () => setState(() => _tab = _HomeTab.shelf),
        ),
        title: const Text('主页'),
        titleSpacing: 4,
        actions: const [AppBarNavActions()],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 侧栏：与设置弹窗左导航同一视觉语言（品牌色浅底选中态）。
          Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: hairline)),
            ),
            child: Column(
              children: [
                for (final (icon, label, tab) in _tabs)
                  _SideNavItem(
                    icon: icon,
                    label: label,
                    selected: _tab == tab,
                    onTap: () => setState(() => _tab = tab),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _LoginEntry(),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _HomeTab.shelf => const _ShelfBody(),
              _HomeTab.stats => const StatsView(),
              _HomeTab.recycle => const RecycleView(scope: RecycleScope.shelf),
            },
          ),
        ],
      ),
    );
  }
}

/// 左侧导航项：悬停浅高亮；选中用品牌色浅底。
class _SideNavItem extends StatefulWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final selected = widget.selected;
    final selectedColor =
        scheme.primary.withValues(alpha: isLight ? 0.10 : 0.18);
    final hoverColor = isLight
        ? const Color(0x08000000)
        : const Color(0x08FFFFFF);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? selectedColor
                  : (_hover ? hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 19,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

/// 侧栏底部登录入口：Codex 风格账号卡片（头像 + 标题/副标题），点击打开登录弹窗。
class _LoginEntry extends StatefulWidget {
  @override
  State<_LoginEntry> createState() => _LoginEntryState();
}

class _LoginEntryState extends State<_LoginEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final synced = context.watch<SettingsController>().syncEnabled;
    final hoverColor = isLight
        ? const Color(0x0A000000)
        : const Color(0x0AFFFFFF);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => showLoginDialog(context),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hover ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primary.withValues(
                  alpha: isLight ? 0.14 : 0.24,
                ),
                foregroundImage: null,
                child: Icon(Icons.person, size: 17, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      synced ? '本地账号' : '未登录',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      synced ? '云同步已开启' : '点击登录账号',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 书架内容区：顶部工具栏（搜索 / 导入 / 新建）+ 作品网格 + 空态。
class _ShelfBody extends StatefulWidget {
  const _ShelfBody();

  @override
  State<_ShelfBody> createState() => _ShelfBodyState();
}

class _ShelfBodyState extends State<_ShelfBody> {
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await appState(context).loadShelf();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<SettingsController>().theme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(context),
                Expanded(
                  child: state.bookList.isEmpty
                      ? _empty(context)
                      : _grid(context, state, theme),
                ),
              ],
            ),
    );
  }

  List<Book> _visibleBooks(AppState state) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return state.bookList;
    return state.bookList
        .where((b) =>
            b.title.toLowerCase().contains(q) ||
            b.penName.toLowerCase().contains(q))
        .toList();
  }

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = context.watch<SettingsController>().uiScale;
    final btnHeight = 38 * scale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 280 * scale),
            child: SizedBox(
              height: btnHeight,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索书名或作者',
                  prefixIcon: Icon(Icons.search,
                      size: 18 * scale, color: scheme.onSurfaceVariant),
                  prefixIconConstraints: BoxConstraints(
                      minWidth: 38 * scale, minHeight: btnHeight),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12 * scale, vertical: 10 * scale),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10 * scale),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: () => _importBook(context),
            icon: Icon(Icons.file_download_outlined, size: 18 * scale),
            label: const Text('导入书籍', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              fixedSize: Size.fromHeight(btnHeight),
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () => _createBook(context),
            icon: Icon(Icons.add, size: 18 * scale),
            label: const Text('新增书籍', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              fixedSize: Size.fromHeight(btnHeight),
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, AppState state, AppTheme theme) {
    final books = _visibleBooks(state);
    if (books.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配的作品',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 20,
        crossAxisSpacing: 18,
        childAspectRatio: 0.72,
      ),
      itemCount: books.length,
      itemBuilder: (ctx, i) => _BookCard(book: books[i], theme: theme),
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
              _miniBook(
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                -0.12,
              ),
              const SizedBox(width: 14),
              _miniBook(
                scheme.secondaryContainer,
                scheme.onSecondaryContainer,
                0,
              ),
              const SizedBox(width: 14),
              _miniBook(
                scheme.tertiaryContainer,
                scheme.onTertiaryContainer,
                0.12,
              ),
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
            '点击右上角「新增书籍」或「导入书籍」，开始你的第一部小说',
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

  /// 导入 TXT 为新书：文件名作书名，按"第X章"自动切分章节。
  Future<void> _importBook(BuildContext ctx) async {
    final file = await FileIO.pickReadTextNamed();
    if (file == null || ctx.mounted == false) return;
    final (name, raw) = file;
    final state = appState(ctx);
    final book = await state.importBookFromText(name, raw);
    final count = TxtImporter.splitChapters(raw).length;
    if (ctx.mounted) {
      showToast(ctx, '《${book.title}》导入成功，共 $count 个章节');
    }
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
      '确定删除《${widget.book.title}》？作品将进入回收站保留 30 天，恢复后内容完整复原。',
    );
    if (ok && mounted) {
      await state.deleteBook(widget.book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final scheme = Theme.of(context).colorScheme;
    final radius = 8.0;
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
