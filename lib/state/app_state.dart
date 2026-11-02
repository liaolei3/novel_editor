import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;


import '../core/utils/chapter_title_suggest.dart';
import '../core/utils/foreshadow_delta.dart';
import '../core/utils/global_search.dart';
import '../core/utils/rich_text_codec.dart';
import '../core/utils/sensitive_words.dart';
import '../core/utils/text_stats.dart';
import '../core/utils/txt_importer.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../services/autosave_service.dart';
import '../services/durability_service.dart';
import '../services/session_stats.dart';
import '../services/sync/sync_engine.dart';
import 'editor_layout.dart';
import 'editor_panes.dart';
import 'settings_controller.dart';

/// 全局应用状态：书架、作品树、多窗格编辑、保存状态、同步入口。
class AppState extends ChangeNotifier {
  AppState({
    required this.settings,
    required this.books,
    required this.volumes,
    required this.chapters,
    required this.snapshots,
    required this.characters,
    required this.foreshadows,
    required this.fsSegments,
    required this.sensitiveWords,
    required this.stats,
    required this.recycle,
    required this.autosave,
    required this.durability,
    required this.crash,
    required this.session,
    required this.sync,
  }) {
    _ensureSession(_activePaneId);
  }

  final SettingsController settings;
  final BookRepository books;
  final VolumeRepository volumes;
  final ChapterRepository chapters;
  final SnapshotRepository snapshots;
  final CharacterRepository characters;
  final ForeshadowRepository foreshadows;
  final ForeshadowSegmentRepository fsSegments;
  final SensitiveWordRepository sensitiveWords;
  final StatsRepository stats;
  final RecycleRepository recycle;
  final AutosaveService autosave;
  final DurabilityService durability;
  final CrashRecovery crash;
  final SessionStats session;
  final SyncEngine sync;

  List<Book> bookList = [];
  Book? currentBook;
  List<Volume> volumeTree = [];
  List<Chapter> chapterList = [];

  /// 编辑区分屏布局（结构 + 各窗格标签状态）。
  EditorLayout _layout = EditorLayout.singlePane();

  /// 窗格运行时集合，键为窗格 id。
  final Map<String, PaneSession> _sessions = <String, PaneSession>{};

  String _activePaneId = 'pane-1';

  /// 布局落盘防抖。
  Timer? _layoutDebounce;

  EditorLayout get editorLayout => _layout;

  String get activePaneId => _activePaneId;

  /// 按布局顺序返回窗格 id。
  List<String> get editorPaneIds => _layout.paneIdsInOrder;

  PaneSession? paneSession(String paneId) => _sessions[paneId];

  /// 活动窗格当前章节。
  Chapter? get currentChapter => _sessions[_activePaneId]?.activeChapter;

  /// 活动窗格编辑器控制器；窗格尚未建立时的兜底控制器。
  QuillController get editorController =>
      _sessions[_activePaneId]?.controller ??
      (_scratchController ??= QuillController.basic());

  QuillController? _scratchController;

  Chapter? paneChapter(String paneId) => _sessions[paneId]?.activeChapter;

  /// 指定窗格的标签章节（按 id 从最新章列表解析）。
  List<Chapter> paneTabs(String paneId) {
    final pane = _sessions[paneId];
    if (pane == null) return const [];
    final byId = {for (final c in chapterList) c.id: c};
    return [
      for (final id in pane.tabIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  int bookCharTotal = 0;

  /// 今日累计新增字数（内存维护，供状态栏与达成检测实时读取）。
  int todayChars = 0;
  String? _todayDateKey;
  bool _todayGoalNotified = false;

  /// 目标达成播报流：UI 层订阅后以烟花庆祝呈现。
  /// 载荷为本次达成项文案列表，同帧内多项合并为一次播报。
  final StreamController<List<String>> _goalToasts =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get goalToasts => _goalToasts.stream;

  /// 当前章节生效的单章目标（三态解析）；0 = 未设置/关闭。
  int get resolvedChapterGoal {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null) return 0;
    return chapter.goal ?? book.chapterGoal;
  }

  /// 角色词典版本号：角色增删改后自增，编辑器据此重建名字高亮词典。
  final ValueNotifier<int> characterDictVersion = ValueNotifier(0);

  /// 角色编辑跳转请求：编辑器悬浮 tip 的「编辑」按钮触发。
  String? pendingOpenCharacterId;
  final ValueNotifier<int> openCharacterNonce = ValueNotifier(0);

  void requestOpenCharacter(String id) {
    pendingOpenCharacterId = id;
    openCharacterNonce.value++;
  }

  /// 伏笔数据版本号：增删改后自增，编辑器据此重建标注词典。
  final ValueNotifier<int> foreshadowVersion = ValueNotifier(0);

  /// 伏笔面板跳转请求：悬浮 tip「编辑」按钮触发。
  String? pendingOpenForeshadowId;
  final ValueNotifier<int> openForeshadowNonce = ValueNotifier(0);

  void requestOpenForeshadow(String id) {
    pendingOpenForeshadowId = id;
    openForeshadowNonce.value++;
  }

  /// 片段跳转请求（面板 → 编辑器定位）：编辑器收到后聚焦滚动到选区。
  final ValueNotifier<int> segmentJumpNonce = ValueNotifier(0);

  /// 目录树章节拖出计数，>0 时工作区显示抓取光标。
  final ValueNotifier<int> chapterDragCount = ValueNotifier<int>(0);

  /// 每书 UI 会话快照（内存缓存，跨书保留）：目录树展开卷、离开时的滚动偏移。
  /// 写盘统一延后到切书离开 / 退出（_persistBookUi）。
  final Map<String, BookUiSnapshot> _uiSnaps = {};

  BookUiSnapshot uiSnapshot(String bookId) =>
      _uiSnaps.putIfAbsent(bookId, BookUiSnapshot.new);

  /// 切书/重启后待恢复的编辑器滚动偏移（EditorArea 消费后清空）。
  double? _pendingRestoreScroll;

  /// 每章滚动偏移（仅内存）：切回标签时还原。
  final Map<String, double> _chapterScrolls = {};

  double? chapterScrollOf(String chapterId) => _chapterScrolls[chapterId];

  void setChapterScroll(String chapterId, double offset) {
    _chapterScrolls[chapterId] = offset;
  }

  double? consumePendingRestoreScroll() {
    final v = _pendingRestoreScroll;
    _pendingRestoreScroll = null;
    return v;
  }

  /// 离开当前书时落盘 UI 快照：所有窗格光标（内存 + DB）、书级位置与滚动（DB）、
  /// 目录树（config.json）与分屏布局。
  Future<void> _persistBookUi() async {
    final book = currentBook;
    if (book == null) return;
    await autosave.flush();
    for (final pane in _sessions.values) {
      final chapter = pane.activeChapter;
      if (chapter != null) await _saveCursorTo(chapter);
    }
    final chapter = currentChapter;
    final snap = _uiSnaps[book.id];
    final sel = editorController.selection;
    final cursor =
        (sel.baseOffset >= 0 && sel.baseOffset <= editorController.document.length)
            ? sel.baseOffset
            : null;
    if (chapter != null && cursor != null) chapter.cursorOffset = cursor;
    final scroll = snap?.scrollOffset.round() ?? 0;
    await books.saveLocation(book.id, chapter?.id, cursor, scrollOffset: scroll);
    // 同步内存实例：切回该书时 openBook 依赖 book.lastChapterId 定位上次章节，
    // 只写 DB 不更新内存会打开陈旧章节并连带树定位错卷。
    book
      ..lastChapterId = chapter?.id
      ..lastCursor = cursor
      ..lastScrollOffset = scroll;
    final idx = bookList.indexWhere((b) => b.id == book.id);
    if (idx >= 0 && !identical(bookList[idx], book)) {
      bookList[idx]
        ..lastChapterId = chapter?.id
        ..lastCursor = cursor
        ..lastScrollOffset = scroll;
    }
    if (snap != null) {
      await settings.saveBookTree(book.id, snap.expandedVolumes.toList());
    }
    await saveLayoutNow();
  }

  StreamSubscription<SyncEvent>? _syncSub;

  Future<void> loadShelf() async {
    bookList = await books.listAll();
    notifyListeners();
  }

  Future<Book> createBook(String title, String penName,
      {String? coverPath}) async {
    final book = await books.create(title, penName: penName);
    if (coverPath != null && coverPath.isNotEmpty) {
      await books.updateCover(book.id, coverPath);
    }
    final vol = await volumes.create(book.id, '第一卷');
    await chapters.create(bookId: book.id, volumeId: vol.id, title: '第一章');
    await loadShelf();
    return book;
  }

  /// 按导入预览的卷/章结构创建新书，正文转 Delta JSON 存储；
  /// [onProgress] 回报已写入章节数 / 总章节数。
  Future<Book> importBookFromPreview(
    String title,
    ImportPreview preview, {
    String penName = '',
    void Function(int done, int total)? onProgress,
  }) async {
    final total = preview.chapterCount;
    var done = 0;
    onProgress?.call(done, total);
    final book = await books.create(title, penName: penName);
    for (final volume in preview.volumes) {
      final vol = await volumes.create(book.id, volume.name);
      for (var i = 0; i < volume.chapters.length; i++) {
        final chapter = volume.chapters[i];
        await chapters.create(
          bookId: book.id,
          volumeId: vol.id,
          title: chapter.title,
          // 导入顺序即章序号，避免每章再查一次库里已有章数。
          sort: i,
          content: RichTextCodec.deltaJsonFromPlainText(chapter.body),
        );
        onProgress?.call(++done, total);
      }
    }
    await loadShelf();
    return book;
  }

  /// 删除书籍 → 回收站（一条 book 条目；子数据原地不动，恢复即全部复原）。
  Future<void> deleteBook(Book book) async {
    await books.softDelete(book.id);
    await recycle.add(RecycleType.book, book.id, {
      'book_id': book.id,
      'title': book.title,
      'pen_name': book.penName,
      'cover_path': book.coverPath,
      'summary': book.summary,
    });
    await loadShelf();
  }

  /// 启动时过期清理：book 条目级联彻底删除，其余沿用既有行为。
  Future<void> purgeExpiredRecycle() async {
    final now = DateTime.now();
    for (final item in await recycle.list()) {
      if (item.expireAt.isAfter(now)) continue;
      if (item.type == RecycleType.book) {
        await _purgeBookCompletely(item);
      } else {
        if (item.type == RecycleType.chapter) {
          // 章节行已不存在，hardDelete 仅清理其残留快照。
          await chapters.hardDelete(item.originId);
        }
        await recycle.remove(item.id);
      }
    }
  }

  /// 彻底删除回收站条目；书籍类型执行级联清理。
  Future<void> purgeRecycleItem(RecycleItem item) async {
    if (item.type == RecycleType.book) {
      await _purgeBookCompletely(item);
      return;
    }
    if (item.type == RecycleType.chapter) {
      await chapters.hardDelete(item.originId);
    }
    await recycle.remove(item.id);
  }

  /// 书籍级联彻底删除：子数据、快照、封面文件、章节备份、回收站遗留子条目。
  Future<void> _purgeBookCompletely(RecycleItem item) async {
    final bookId = item.originId;
    // 先清回收站里该书遗留的子条目，避免恢复时父书已不存在。
    for (final r in await recycle.list()) {
      if (r.type == RecycleType.book) continue;
      if (_decode(r.payload)['book_id'] == bookId) {
        await recycle.remove(r.id);
      }
    }
    await volumes.hardDeleteByBook(bookId);
    await chapters.hardDeleteByBook(bookId);
    await fsSegments.hardDeleteByBook(bookId);
    await foreshadows.hardDeleteByBook(bookId);
    await characters.hardDeleteByBook(bookId);
    final coverPath = _decode(item.payload)['cover_path'] as String? ?? '';
    if (coverPath.isNotEmpty) {
      try {
        final f = File(p.join(await Db.supportDir(), coverPath));
        if (f.existsSync()) await f.delete();
      } catch (_) {
        // 文件被占用或缺失时忽略，不影响 DB 状态。
      }
    }
    await durability.deleteBookBackups(bookId);
    await books.hardDelete(bookId);
    await recycle.remove(item.id);
    await loadShelf();
  }

  /// 打开作品：加载卷章树、还原分屏布局并恢复活动窗格。
  /// 打开前先将上一本书的 UI 快照与布局落盘（切书还原）。
  Future<void> openBook(Book book, {String? startChapterId}) async {
    await autosave.flush();
    await _persistBookUi();
    currentBook = book;
    await _reloadTree(prunePanes: false);
    bookCharTotal =
        chapterList.fold(0, (sum, c) => sum + c.charCount);
    await _loadTodayStats();
    await settings.setLastBookId(book.id);
    await settings.touchRecentBook(book.id);
    final snap = uiSnapshot(book.id);
    if (!snap.treeLoaded) {
      // 首次进入快照：从 config.json 还原该书的目录树展开卷（跨会话）。
      snap.expandedVolumes.addAll(settings.bookUiOf(book.id).tree);
      snap.treeLoaded = true;
    }
    final validIds = chapterList.map((c) => c.id).toSet();
    final fallbackId =
        (book.lastChapterId != null && validIds.contains(book.lastChapterId))
            ? book.lastChapterId
            : chapterList.firstOrNull?.id;
    var layout = settings.editorLayoutOf(book.id);
    if (layout == null) {
      // 旧数据迁移：bookUi.chapterTabs 转为单窗格标签。
      final oldTabs = settings
          .bookUiOf(book.id)
          .chapterTabs
          .where(validIds.contains)
          .toList();
      layout = EditorLayout.singlePane(
        tabIds: oldTabs,
        activeChapterId: fallbackId,
      );
    }
    final pruned = layout.prune(
      validChapterIds: validIds,
      fallbackChapterId: fallbackId,
      fallbackPaneId: layout.paneIdsInOrder.firstOrNull ?? 'pane-1',
    );
    await _applyLayoutAndLoad(pruned, persist: false);
    _pendingRestoreScroll = snap.scrollOffset;
    if (startChapterId != null) {
      final ch = _chapterById(startChapterId);
      if (ch != null) await openChapter(ch);
    }
    await saveLayoutNow();
    notifyListeners();
  }

  Future<void> _reloadTree({
    bool prunePanes = true,
    String? fallbackChapterId,
    Map<String, String?> preferredActive = const {},
  }) async {
    if (currentBook == null) return;
    volumeTree = await volumes.listByBook(currentBook!.id);
    chapterList = await chapters.listByBook(currentBook!.id);
    if (!prunePanes) return;
    await _prunePanes(
      fallbackChapterId: fallbackChapterId,
      preferredActive: preferredActive,
    );
  }

  /// 剔除所有窗格中失效的章节与空窗格，并同步布局。
  Future<void> _prunePanes({
    String? fallbackChapterId,
    Map<String, String?> preferredActive = const {},
  }) async {
    if (_sessions.isEmpty) return;
    _commitLayout();
    final validIds = chapterList.map((c) => c.id).toSet();
    final pruned = _layout.prune(
      validChapterIds: validIds,
      fallbackChapterId: fallbackChapterId,
      fallbackPaneId: _layout.paneIdsInOrder.firstOrNull ?? 'pane-1',
    );
    await _applyLayoutAndLoad(pruned, preferredActive: preferredActive);
  }

  /// 当前书的章节标签（活动窗格）。
  List<Chapter> get chapterTabs => paneTabs(_activePaneId);

  /// 当前章在标签中的邻位：先右后左，跳过 [removed]；无则返回 null。
  String? _neighborTabId(
    List<String> tabs,
    int fromPos,
    Set<String> removed,
  ) {
    for (var i = fromPos; i < tabs.length; i++) {
      if (!removed.contains(tabs[i])) return tabs[i];
    }
    for (var i = fromPos - 1; i >= 0; i--) {
      if (!removed.contains(tabs[i])) return tabs[i];
    }
    return null;
  }

  // ---------- 窗格运行时 ----------

  Chapter? _chapterById(String? id) {
    if (id == null) return null;
    return chapterList.where((c) => c.id == id).firstOrNull;
  }

  PaneSession _ensureSession(String paneId) {
    final existing = _sessions[paneId];
    if (existing != null) return existing;
    final pane = PaneSession(paneId);
    final state = _layout.panes[paneId];
    if (state != null) pane.tabIds = List<String>.of(state.tabIds);
    pane.bindDocumentListener(() => onPaneChanged(paneId));
    _sessions[paneId] = pane;
    return pane;
  }

  /// 查找包含指定章节的窗格 id（标签或当前文档）。
  String? _paneOwningChapter(String chapterId) {
    for (final entry in _sessions.entries) {
      if (entry.value.tabIds.contains(chapterId) ||
          entry.value.activeChapter?.id == chapterId) {
        return entry.key;
      }
    }
    return null;
  }

  /// 正在显示指定章节的窗格。
  PaneSession? _paneDisplaying(String chapterId) {
    for (final pane in _sessions.values) {
      if (pane.activeChapter?.id == chapterId) return pane;
    }
    return null;
  }

  /// 把窗格会话的标签与当前章节写回布局。
  void _commitLayout() {
    final states = <String, EditorPaneState>{};
    for (final id in _layout.paneIdsInOrder) {
      final pane = _sessions[id];
      if (pane == null) continue;
      states[id] = EditorPaneState(
        tabIds: List<String>.of(pane.tabIds),
        activeChapterId: pane.activeChapter?.id,
      );
    }
    _layout = _layout.withPaneStates(states, activePaneId: _activePaneId);
  }

  /// 立即写入当前书分屏布局。
  Future<void> saveLayoutNow() async {
    _layoutDebounce?.cancel();
    _layoutDebounce = null;
    _commitLayout();
    final book = currentBook;
    if (book == null) return;
    await settings.saveEditorLayout(book.id, _layout);
  }

  /// 300ms 防抖写入分屏布局。
  void saveLayoutSoon() {
    _layoutDebounce?.cancel();
    _layoutDebounce = Timer(const Duration(milliseconds: 300), () {
      _layoutDebounce = null;
      unawaited(saveLayoutNow());
    });
  }

  /// 按布局重建会话：销毁多余窗格，解析各窗格当前章节并加载文档。
  Future<void> _applyLayoutAndLoad(
    EditorLayout layout, {
    Map<String, String?> preferredActive = const {},
    bool persist = true,
  }) async {
    final before = jsonEncode(_layout.toJson());
    _layout = layout;
    _activePaneId = layout.activePaneId;
    final ids = layout.paneIdsInOrder.toSet();
    for (final id in _sessions.keys.toList()) {
      if (!ids.contains(id)) _sessions.remove(id)!.dispose();
    }
    for (final id in layout.paneIdsInOrder) {
      final pane = _ensureSession(id);
      pane.tabIds = List<String>.of(layout.panes[id]?.tabIds ?? const []);
    }
    for (final id in layout.paneIdsInOrder) {
      final pane = _sessions[id]!;
      final prefer = preferredActive[id];
      final activeId = (prefer != null && pane.tabIds.contains(prefer))
          ? prefer
          : layout.panes[id]?.activeChapterId;
      final chapter = _chapterById(activeId);
      if (chapter == null) {
        if (pane.activeChapter != null) {
          pane.activeChapter = null;
          _loadEmptyDocument(pane);
        }
      } else if (pane.activeChapter?.id == chapter.id) {
        pane.activeChapter = chapter;
      } else {
        await _loadChapterIntoPane(id, chapter, persist: false);
      }
    }
    _commitLayout();
    if (persist && jsonEncode(_layout.toJson()) != before) {
      await saveLayoutNow();
    }
  }

  /// 把章节加载进指定窗格，并处理原章节光标与快照。
  Future<void> _loadChapterIntoPane(
    String paneId,
    Chapter chapter, {
    bool persist = true,
  }) async {
    final pane = _sessions[paneId];
    if (pane == null) return;
    final fresh = _chapterById(chapter.id) ?? chapter;
    await autosave.flush();
    final prev = pane.activeChapter;
    if (prev != null && prev.id != fresh.id) await _saveCursorTo(prev);
    pane.activeChapter = fresh;
    pane.loadingDoc = true;
    try {
      pane.replaceDocument(
        RichTextCodec.documentFromContent(fresh.content),
        fireChange: false,
      );
      final docLen = pane.controller.document.length;
      pane.controller.updateSelection(
        TextSelection.collapsed(
            offset: fresh.cursorOffset.clamp(0, docLen)),
        ChangeSource.local,
      );
    } finally {
      pane.loadingDoc = false;
      pane.lastDocJson = jsonEncode(pane.controller.document.toDelta().toJson());
    }
    await durability.autoSnapshotIfNeeded(fresh);
    if (persist) {
      _commitLayout();
      await saveLayoutNow();
    }
  }

  /// 窗格切换为空文档。
  void _loadEmptyDocument(PaneSession pane) {
    pane.loadingDoc = true;
    try {
      pane.replaceDocument(
        RichTextCodec.documentFromContent(''),
        fireChange: false,
      );
      pane.controller.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
    } finally {
      pane.loadingDoc = false;
      pane.lastDocJson = jsonEncode(pane.controller.document.toDelta().toJson());
    }
  }

  /// 激活窗格并选中章节；章节已在其他窗格时不重复打开。
  Future<void> _activateChapterInPane(String paneId, Chapter chapter) async {
    final pane = _sessions[paneId];
    if (pane == null) return;
    final fresh = _chapterById(chapter.id) ?? chapter;
    _activePaneId = paneId;
    _layout = _layout.withActivePane(paneId);
    if (!pane.tabIds.contains(fresh.id)) pane.tabIds.add(fresh.id);
    if (pane.activeChapter?.id == fresh.id) {
      pane.activeChapter = fresh;
      _commitLayout();
      await saveLayoutNow();
      notifyListeners();
      return;
    }
    await _loadChapterIntoPane(paneId, fresh);
    notifyListeners();
  }

  void activatePane(String paneId) {
    if (!_sessions.containsKey(paneId) || paneId == _activePaneId) return;
    final prev = currentChapter;
    if (prev != null) unawaited(_saveCursorTo(prev));
    _activePaneId = paneId;
    _layout = _layout.withActivePane(paneId);
    _commitLayout();
    saveLayoutSoon();
    notifyListeners();
  }

  /// 在指定窗格打开章节；章节已在其他窗格时只激活并选中。
  Future<void> openChapterInPane(String paneId, Chapter chapter) async {
    if (!_sessions.containsKey(paneId)) return;
    final owner = _paneOwningChapter(chapter.id);
    await _activateChapterInPane(owner ?? paneId, chapter);
  }

  /// 按方向分割目标窗格并在新窗格打开章节，成功返回新窗格 id。
  Future<String?> splitPaneWithChapter(
    String targetPaneId,
    EditorSplitDirection direction,
    Chapter chapter,
  ) async {
    if (!_sessions.containsKey(targetPaneId)) return null;
    final owner = _paneOwningChapter(chapter.id);
    if (owner != null) {
      await _activateChapterInPane(owner, chapter);
      return null;
    }
    await autosave.flush();
    final prev = currentChapter;
    if (prev != null) await _saveCursorTo(prev);
    _commitLayout();
    final next = _layout.splitPane(
      targetPaneId,
      direction,
      newActiveChapterId: chapter.id,
    );
    if (identical(next, _layout)) return null;
    final newPaneId = next.activePaneId;
    _layout = next;
    _activePaneId = newPaneId;
    final pane = _ensureSession(newPaneId);
    pane.tabIds = List<String>.of(next.panes[newPaneId]?.tabIds ?? [chapter.id]);
    await _loadChapterIntoPane(newPaneId, chapter, persist: false);
    _commitLayout();
    await saveLayoutNow();
    notifyListeners();
    return newPaneId;
  }

  /// 关闭窗格：销毁会话并由兄弟节点顶替（至少保留一个窗格）。
  Future<void> closePane(String paneId) async {
    if (_sessions.length <= 1 || !_sessions.containsKey(paneId)) return;
    await autosave.flush();
    final pane = _sessions[paneId]!;
    final chapter = pane.activeChapter;
    if (chapter != null) await _saveCursorTo(chapter);
    _commitLayout();
    _layout = _layout.removePane(paneId);
    _sessions.remove(paneId)?.dispose();
    _activePaneId = _layout.activePaneId;
    for (final id in _layout.paneIdsInOrder) {
      _ensureSession(id);
    }
    _commitLayout();
    await saveLayoutNow();
    notifyListeners();
  }

  /// 在指定窗格关闭章节标签；窗格为空且存在其他窗格时移除该窗格。
  Future<void> closeChapterTabInPane(String paneId, String chapterId) async {
    final pane = _sessions[paneId];
    if (pane == null) return;
    final pos = pane.tabIds.indexOf(chapterId);
    if (pos < 0) return;
    final wasCurrent = pane.activeChapter?.id == chapterId;
    final nextId =
        wasCurrent ? _neighborTabId(pane.tabIds, pos, {chapterId}) : null;
    pane.tabIds.removeAt(pos);
    if (!wasCurrent) {
      _commitLayout();
      await saveLayoutNow();
      notifyListeners();
      return;
    }
    await autosave.flush();
    final cur = pane.activeChapter;
    if (cur != null) await _saveCursorTo(cur);
    pane.activeChapter = null;
    final next = _chapterById(nextId);
    if (next != null) {
      await _loadChapterIntoPane(paneId, next, persist: false);
    } else {
      _loadEmptyDocument(pane);
    }
    if (pane.tabIds.isEmpty && _sessions.length > 1) {
      await closePane(paneId);
      return;
    }
    _commitLayout();
    await saveLayoutNow();
    notifyListeners();
  }

  /// 关闭活动窗格的章节标签。
  Future<void> closeChapterTab(String id) =>
      closeChapterTabInPane(_activePaneId, id);

  /// 调整分割比例；[path] 为从根出发的 0/1 索引路径。
  Future<void> updateSplitRatio(List<int> path, double ratio) async {
    _layout = _layout.withSplitRatioAt(path, ratio);
    notifyListeners();
    saveLayoutSoon();
  }

  /// 对外暴露的树刷新（大纲编辑等场景）。
  Future<void> reloadTreePublic() async {
    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    notifyListeners();
  }

  /// 全书搜索（正文 / 章纲 / 角色 / 伏笔）。
  Future<List<GlobalSearchHit>> globalSearch(String query) async {
    if (currentBook == null || query.isEmpty) return const [];
    final chars = await characters.listByBook(currentBook!.id);
    final fsList = await foreshadows.listByBook(currentBook!.id);
    return GlobalSearch.search(
      query: query,
      chapters: chapterList,
      volumes: volumeTree,
      characters: chars,
      foreshadows: fsList,
    );
  }

  /// 全书替换：命中处统一直接写回（不做撤销），覆盖正文 / 章纲 / 角色 / 伏笔；
  /// 正文替换保留富文本格式；执行前为每个被修改的章节自动创建快照。
  Future<int> globalReplace({
    required String query,
    required String replacement,
  }) async {
    if (currentBook == null || query.isEmpty) return 0;
    await autosave.flush();
    var total = 0;
    final changedChapterIds = <String>{};

    for (final ch in List<Chapter>.of(chapterList)) {
      if (ch.content.isNotEmpty) {
        final (newJson, n) =
            GlobalSearch.replaceInDeltaJson(ch.content, query, replacement);
        if (n > 0) {
          await durability.manualSnapshot(ch);
          ch.content = newJson;
          await chapters.updateContent(ch);
          total += n;
          if (_paneOwningChapter(ch.id) != null) changedChapterIds.add(ch.id);
        }
      }
      if (ch.outline.contains(query)) {
        final n = GlobalSearch.matchStarts(ch.outline, query).length;
        ch.outline = ch.outline.replaceAll(query, replacement);
        await chapters.updateOutline(ch, ch.outline);
        total += n;
      }
    }

    var characterChanged = false;
    {
      final list = await characters.listByBook(currentBook!.id);
      for (final c in list) {
        var changed = false;
        // 固定字段替换（属性名不参与替换）。
        final fixed = <(String Function(), void Function(String))>[
          (() => c.name, (v) => c.name = v),
          (() => c.aliases, (v) => c.aliases = v),
          (() => c.tags, (v) => c.tags = v),
        ];
        for (final (getter, setter) in fixed) {
          final text = getter();
          if (!text.contains(query)) continue;
          total += GlobalSearch.matchStarts(text, query).length;
          setter(text.replaceAll(query, replacement));
          changed = true;
        }
        // 自定义属性：只替换属性值。
        final attrs = c.attrList;
        for (final a in attrs) {
          if (!a.value.contains(query)) continue;
          total += GlobalSearch.matchStarts(a.value, query).length;
          a.value = a.value.replaceAll(query, replacement);
          changed = true;
        }
        if (changed) {
          c.attrList = attrs;
          await characters.update(c);
          characterChanged = true;
        }
      }
      if (characterChanged) characterDictVersion.value++;
    }

    var foreshadowChanged = false;
    {
      final list = await foreshadows.listByBook(currentBook!.id);
      for (final f in list) {
        var changed = false;
        if (f.name.contains(query)) {
          total += GlobalSearch.matchStarts(f.name, query).length;
          f.name = f.name.replaceAll(query, replacement);
          changed = true;
        }
        if (f.content.contains(query)) {
          total += GlobalSearch.matchStarts(f.content, query).length;
          f.content = f.content.replaceAll(query, replacement);
          changed = true;
        }
        if (changed) {
          await foreshadows.update(f);
          foreshadowChanged = true;
        }
      }
      if (foreshadowChanged) foreshadowVersion.value++;
    }

    if (total > 0) {
      await _reloadTree();
      bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
      for (final id in changedChapterIds) {
        _reloadCurrentDocIfNeeded(id);
      }
      notifyListeners();
    }
    return total;
  }

  /// 供敏感词检测：取章节正文纯文本（embed 记 1，与编辑器坐标一致）。
  String sensitiveTextOf(Chapter ch) =>
      RichTextCodec.plainTextFromDeltaJson(ch.content);

  /// 全书敏感词检测：逐章扫描正文，只返回有命中的章节（按章节顺序）。
  Future<List<SensitiveChapterScan>> scanSensitiveBook(
    List<SensitiveEntry> entries, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (currentBook == null || entries.isEmpty) return const [];
    await autosave.flush();
    final scanner = SensitiveWordScanner(entries);
    final out = <SensitiveChapterScan>[];
    final list = List<Chapter>.of(chapterList);
    var done = 0;
    for (final ch in list) {
      final matches = scanner.scan(sensitiveTextOf(ch));
      if (matches.isNotEmpty) {
        out.add(SensitiveChapterScan(chapter: ch, matches: matches));
      }
      onProgress?.call(++done, list.length);
    }
    return out;
  }

  /// 检测当前章节正文，返回命中（无词条或无命中返回空列表）。
  List<SensitiveMatch> scanSensitiveChapter(List<SensitiveEntry> entries) {
    final ch = currentChapter;
    if (ch == null || entries.isEmpty) return const [];
    return SensitiveWordScanner(entries).scan(sensitiveTextOf(ch));
  }

  /// 替换指定章节命中：建议词为空的词跳过。返回 (替换处数, 跳过词)。
  Future<(int, Set<String>)> replaceSensitiveChapter(
      Chapter ch, List<SensitiveEntry> entries) async {
    if (entries.isEmpty) return (0, const <String>{});
    await autosave.flush();
    final (n, skipped) =
        await _replaceSensitiveChapter(ch, SensitiveWordScanner(entries));
    if (n > 0) {
      await _reloadTree();
      bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
      _reloadCurrentDocIfNeeded(ch.id);
      notifyListeners();
    }
    return (n, skipped);
  }

  /// 全书敏感词替换：逐章先建快照再替换（保留富文本）。返回 (替换处数, 跳过词)。
  Future<(int, Set<String>)> replaceSensitiveBook(
    List<SensitiveEntry> entries, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (currentBook == null || entries.isEmpty) return (0, const <String>{});
    await autosave.flush();
    final scanner = SensitiveWordScanner(entries);
    final skipped = <String>{};
    final list = List<Chapter>.of(chapterList);
    var total = 0;
    var done = 0;
    final changedChapterIds = <String>{};
    for (final ch in list) {
      final (n, sk) = await _replaceSensitiveChapter(ch, scanner);
      total += n;
      skipped.addAll(sk);
      if (n > 0 && _paneOwningChapter(ch.id) != null) {
        changedChapterIds.add(ch.id);
      }
      onProgress?.call(++done, list.length);
    }
    if (total > 0) {
      await _reloadTree();
      bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
      for (final id in changedChapterIds) {
        _reloadCurrentDocIfNeeded(id);
      }
      notifyListeners();
    }
    return (total, skipped);
  }

  /// 单章替换实现（不负责刷新/通知）：建议词为空的词只统计、不替换。
  Future<(int, Set<String>)> _replaceSensitiveChapter(
      Chapter ch, SensitiveWordScanner scanner) async {
    final skipped = <String>{};
    if (ch.content.isEmpty) return (0, skipped);
    for (final m in scanner.scan(sensitiveTextOf(ch))) {
      if (m.suggestion.isEmpty) skipped.add(m.word);
    }
    final (newJson, n) = scanner.replaceInDeltaJson(ch.content);
    if (n > 0) {
      await durability.manualSnapshot(ch);
      ch.content = newJson;
      await chapters.updateContent(ch);
    }
    return (n, skipped);
  }

  /// 替换后重载所有正在显示该章节的窗格文档，并夹取原光标。
  void _reloadCurrentDocIfNeeded(String chapterId) {
    final fresh = _chapterById(chapterId);
    if (fresh == null) return;
    for (final pane in _sessions.values) {
      if (pane.activeChapter?.id != chapterId) continue;
      final sel = pane.controller.selection;
      final base = sel.baseOffset;
      final extent = sel.extentOffset;
      pane.activeChapter = fresh;
      pane.loadingDoc = true;
      try {
        pane.replaceDocument(
          RichTextCodec.documentFromContent(fresh.content),
          fireChange: false,
        );
        final docLen = pane.controller.document.length;
        final b = base < 0 ? 0 : base.clamp(0, docLen);
        final e = extent < 0 ? 0 : extent.clamp(0, docLen);
        pane.controller.updateSelection(
            TextSelection(baseOffset: b, extentOffset: e),
            ChangeSource.local);
      } finally {
        pane.loadingDoc = false;
        pane.lastDocJson =
            jsonEncode(pane.controller.document.toDelta().toJson());
      }
    }
  }

  /// 把章节当前光标写回（内存 + DB）；优先取正在显示该章的窗格。
  Future<void> _saveCursorTo(Chapter chapter) async {
    final pane = _paneDisplaying(chapter.id) ?? _sessions[_activePaneId];
    if (pane == null) return;
    final off = pane.controller.selection.baseOffset;
    if (off < 0 || off > pane.controller.document.length) return;
    chapter.cursorOffset = off;
    await chapters.updateCursor(chapter.id, off);
  }

  /// 打开章节：已在某窗格时激活该窗格，否则在活动窗格打开。
  Future<void> openChapter(Chapter chapter) async {
    final owner = _paneOwningChapter(chapter.id);
    if (owner != null) {
      await _activateChapterInPane(owner, chapter);
      return;
    }
    await _activateChapterInPane(_activePaneId, chapter);
  }

  /// 替换活动窗格文档并重绑内容变化监听。
  /// [fireChange] 为 true 时按一次内容变化处理（回滚/替换等主动修改场景）。
  void replaceDocument(Document doc, {bool fireChange = true}) {
    final pane = _sessions[_activePaneId];
    if (pane == null) return;
    pane.replaceDocument(doc, fireChange: false);
    if (fireChange) onPaneChanged(_activePaneId);
  }

  /// 兼容旧入口：处理活动窗格的内容变化。
  void onEditorChanged() => onPaneChanged(_activePaneId);

  /// 单个窗格内容变化：防抖自动保存 + 字数与目标统计。
  void onPaneChanged(String paneId) {
    final pane = _sessions[paneId];
    if (pane == null || pane.loadingDoc) return;
    final chapter = pane.activeChapter;
    if (chapter == null) return;
    final content = jsonEncode(pane.controller.document.toDelta().toJson());
    if (content == pane.lastDocJson) return;
    pane.lastDocJson = content;
    final plainText = pane.controller.document.toPlainText();
    final nowChars = TextStats.count(plainText, settings.countStandard);
    final delta = nowChars - chapter.charCount;
    autosave.onContentChanged(chapter, content);
    if (delta != 0) {
      session.addChars(delta);
      _onCharsDelta(delta);
      bookCharTotal += delta;
      chapter.charCount = nowChars;
      // 作品树直接读 chapterList 的 char_count，需同步同 id 项，
      // 以免窗格章节与 chapterList 为不同实例时字数显示滞后。
      final idx = chapterList.indexWhere((c) => c.id == chapter.id);
      if (idx >= 0) chapterList[idx].charCount = nowChars;
      _checkGoals(chapter);
    }
    notifyListeners();
  }

  /// 读取当日写作记录，初始化今日字数与「已提示」标记。
  Future<void> _loadTodayStats() async {
    final rec = await stats.today();
    todayChars = rec.chars;
    _todayDateKey = WriteRecord.dateKeyOf(DateTime.now());
    _todayGoalNotified = rec.goalNotified;
  }

  /// 维护今日字数内存累计：仅新增推进；跨天自动归零。
  void _onCharsDelta(int delta) {
    if (delta <= 0) return;
    final key = WriteRecord.dateKeyOf(DateTime.now());
    if (key != _todayDateKey) {
      _todayDateKey = key;
      todayChars = 0;
      _todayGoalNotified = false;
    }
    todayChars += delta;
  }

  /// 编辑跨越目标时播报达成：每种目标只提示一次（标记落库）。
  /// 同帧内多个目标同时达成时，只播报首个达成项。
  void _checkGoals([Chapter? chapterOverride]) {
    final book = currentBook;
    final chapter = chapterOverride ?? currentChapter;
    if (book == null || chapter == null) return;

    final done = <String>[];

    final chGoal = chapter.goal ?? book.chapterGoal;
    if (chGoal > 0 && chapter.charCount >= chGoal && !chapter.goalNotified) {
      chapter.goalNotified = true;
      final idx = chapterList.indexWhere((c) => c.id == chapter.id);
      if (idx >= 0) chapterList[idx].goalNotified = true;
      chapters.setGoalNotified(chapter.id, true);
      done.add('本章目标已达成，太棒了！');
    }

    if (book.goal > 0 && bookCharTotal >= book.goal && !book.goalNotified) {
      book.goalNotified = true;
      final idx = bookList.indexWhere((b) => b.id == book.id);
      if (idx >= 0) bookList[idx].goalNotified = true;
      books.setGoalNotified(book.id, true);
      done.add('全书目标已达成，太棒了！');
    }

    final dailyGoal = settings.dailyGoal;
    if (dailyGoal > 0 && todayChars >= dailyGoal && !_todayGoalNotified) {
      _todayGoalNotified = true;
      stats.setGoalNotified(true);
      done.add('今日目标已达成，太棒了！');
    }

    if (done.isNotEmpty) _goalToasts.add([done.first]);
  }

  /// 设置整书目标与全书单章默认目标；目标值变化时重置「已提示」以便重新播报。
  Future<void> setBookGoals({int? goal, int? chapterGoal}) async {
    final book = currentBook;
    if (book == null) return;
    var resetNotified = false;
    if (goal != null && goal != book.goal) {
      book.goal = goal;
      resetNotified = true;
    }
    if (chapterGoal != null) book.chapterGoal = chapterGoal;
    await books.updateGoals(book.id,
        goal: book.goal, chapterGoal: book.chapterGoal);
    if (resetNotified) {
      book.goalNotified = false;
      await books.setGoalNotified(book.id, false);
    }
    final idx = bookList.indexWhere((b) => b.id == book.id);
    if (idx >= 0) {
      bookList[idx]
        ..goal = book.goal
        ..chapterGoal = book.chapterGoal
        ..goalNotified = book.goalNotified;
    }
    notifyListeners();
  }

  /// 设置单章目标三态：null = 跟随全书默认、0 = 关闭、>0 = 自定义。
  Future<void> setChapterGoal(String chapterId, int? goal) async {
    final chapter = chapterList.where((c) => c.id == chapterId).firstOrNull ??
        (currentChapter?.id == chapterId ? currentChapter : null);
    if (chapter == null) return;
    final changed = goal != chapter.goal;
    chapter.goal = goal;
    if (changed) chapter.goalNotified = false;
    if (currentChapter?.id == chapterId && !identical(currentChapter, chapter)) {
      currentChapter!
        ..goal = goal
        ..goalNotified = chapter.goalNotified;
    }
    await chapters.updateGoal(chapterId, goal);
    if (changed) await chapters.setGoalNotified(chapterId, false);
    notifyListeners();
  }

  Future<void> renameChapter(String id, String title) async {
    await chapters.updateTitle(id, title);
    await _reloadTree();
    notifyListeners();
  }

  Future<void> renameVolume(String id, String name) async {
    await volumes.rename(id, name);
    await _reloadTree();
    notifyListeners();
  }

  Future<Volume> addVolume(String name) async {
    final vol = await volumes.create(currentBook!.id, name);
    await _reloadTree();
    notifyListeners();
    return vol;
  }

  /// 新建章节。[content] 为初始正文（Delta JSON）。带上初值建章，可让随后
  /// 的 [_reloadTree] 直接读到完整数据，避免树里留下空 content 的旧实例。
  Future<Chapter> addChapter(String volumeId,
      {String? title, String? outline, String? content}) async {
    final ch = await chapters.create(
      bookId: currentBook!.id,
      volumeId: volumeId,
      title: title ?? '新章节',
      outline: outline ?? '',
      content: content ?? '',
    );
    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    notifyListeners();
    return ch;
  }

  /// 一键分章：把当前章节从 [offset]（选区起点或光标位置，编辑器纯文本坐标）
  /// 拆为两章——光标前内容留在原章节，其后内容剪切到新章节
  /// （插入当前章节之后、卷内后续章节顺延，章节名取该卷「第N章」最大编号 + 1）。
  /// 成功后自动打开新章节；无当前章节或光标后无实际内容时返回 null 且不做修改。
  Future<Chapter?> splitChapterAt(int offset) async {
    final chapter = currentChapter;
    if (chapter == null) return null;
    final delta = editorController.document.toDelta();
    final docLen = editorController.document.length;
    if (offset < 0 || offset >= docLen) return null;
    if (!RichTextCodec.hasContentAfter(delta, offset)) return null;

    // 先落盘未保存的编辑，避免拆分结果被随后的自动保存覆盖。
    await autosave.flush();

    final (head, tail) = RichTextCodec.splitDelta(delta, offset);
    final headJson = jsonEncode(head.toJson());
    final tailJson = jsonEncode(tail.toJson());
    if (tail.operations.isEmpty ||
        RichTextCodec.plainTextFromDeltaJson(tailJson).trim().isEmpty) {
      return null;
    }

    // 原章节保留前半部分。
    chapter.content = headJson;
    chapter.cursorOffset = offset;
    await chapters.updateContent(chapter);

    // 卷内后续章节 sort 顺延，新章节插到当前章节之后。
    final newSort = chapter.sort + 1;
    await chapters.shiftSortFrom(chapter.volumeId, newSort);
    final created = await chapters.create(
      bookId: chapter.bookId,
      volumeId: chapter.volumeId,
      title: suggestChapterTitle(
          chapterList.where((c) => c.volumeId == chapter.volumeId).map((c) => c.title)),
      content: tailJson,
      sort: newSort,
    );

    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    final fresh = chapterList.where((c) => c.id == created.id).firstOrNull ?? created;
    notifyListeners();
    await openChapter(fresh);
    return fresh;
  }

  Future<void> reorderChapters(String volumeId, List<String> orderedIds) async {
    await chapters.reorder(volumeId, orderedIds);
    await _reloadTree();
    notifyListeners();
  }

  Future<void> togglePin(String chapterId) async {
    final ch = chapterList.firstWhere((c) => c.id == chapterId);
    await chapters.setPinned(chapterId, !ch.pinned);
    await _reloadTree();
    notifyListeners();
  }

  // ---------- 伏笔 ----------

  /// 当前选区是否有效且可标注（非空、不越界）。
  bool selectionMarkable() {
    final sel = editorController.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    return sel.start >= 0 && sel.end <= editorController.document.length;
  }

  /// 选区内是否已含伏笔标注（叠加拦截）。
  bool selectionHasFsidMark() {
    if (!selectionMarkable()) return false;
    return deltaRangeHasFsid(
        editorController.document.toDelta(),
        editorController.selection.start,
        editorController.selection.end);
  }

  String _selectedPlainText() {
    final sel = editorController.selection;
    return editorController.document
        .toPlainText()
        .substring(sel.start, sel.end);
  }

  /// 当前选区纯文本（供新建/关联伏笔弹窗展示摘要）。
  String selectedPlainText() =>
      selectionMarkable() ? _selectedPlainText() : '';

  /// 从选区新建伏笔并以选区为首片段；备注归属片段，调用方需先通过 selectionHasFsidMark 拦截。
  Future<Foreshadow> createForeshadowFromSelection(
      String name, String content, String remark) async {
    final book = currentBook!;
    final chapter = currentChapter!;
    final excerpt = _selectedPlainText();
    final fs =
        await foreshadows.create(bookId: book.id, name: name, content: content);
    final seg = await fsSegments.create(
        fsId: fs.id, chapterId: chapter.id, excerpt: excerpt, remark: remark);
    editorController.formatSelection(fsidAttribute(seg.id));
    foreshadowVersion.value++;
    return fs;
  }

  /// 将选区作为新片段关联到已有伏笔；调用方需先通过 selectionHasFsidMark 拦截。
  Future<void> linkSegmentToForeshadow(Foreshadow fs, String segRemark) async {
    final chapter = currentChapter!;
    final excerpt = _selectedPlainText();
    final seg = await fsSegments.create(
        fsId: fs.id, chapterId: chapter.id, excerpt: excerpt, remark: segRemark);
    editorController.formatSelection(fsidAttribute(seg.id));
    foreshadowVersion.value++;
  }

  /// 保存伏笔名称修改。
  Future<void> saveForeshadow(Foreshadow fs) async {
    await foreshadows.update(fs);
    foreshadowVersion.value++;
  }

  /// 删除伏笔：软删除进回收站（携带片段以支持原 id 恢复），
  /// 正文中的 fsid 属性不清洗——渲染时查无词典自动降级，恢复后自动复原。
  Future<void> deleteForeshadow(Foreshadow fs) async {
    final segs = await fsSegments.listByForeshadow(fs.id);
    await recycle.add(RecycleType.foreshadow, fs.id, {
      'book_id': fs.bookId,
      'name': fs.name,
      'status': fs.status.name,
      'sort': fs.sort,
      'segments': [for (final s in segs) s.toMap()],
    });
    await fsSegments.hardDeleteByForeshadow(fs.id);
    await foreshadows.hardDelete(fs.id);
    foreshadowVersion.value++;
  }

  /// 解除关联 / 删除片段：物理删除记录并清除正文标注属性。
  Future<void> removeSegment(ForeshadowSegment seg) async {
    await fsSegments.hardDelete(seg.id);
    foreshadowVersion.value++;
    await _clearSegmentMark(seg);
  }

  /// 清除片段在正文中的 fsid 属性。
  /// 当前章节走 formatSelection（保留撤销栈）；其他章节直接改写章节 JSON。
  Future<void> _clearSegmentMark(ForeshadowSegment seg) async {
    if (currentChapter?.id == seg.chapterId) {
      final ranges = deltaFsidRanges(editorController.document.toDelta(), seg.id);
      if (ranges.isEmpty) return;
      final restore = editorController.selection;
      for (final (start, end) in ranges) {
        editorController.updateSelection(
            TextSelection(baseOffset: start, extentOffset: end),
            ChangeSource.local);
        editorController.formatSelection(unsetFsidAttribute());
      }
      if (restore.isValid) {
        editorController.updateSelection(restore, ChangeSource.local);
      }
      return;
    }
    final ch = await chapters.get(seg.chapterId);
    if (ch == null || ch.content.isEmpty) return;
    final delta = RichTextCodec.documentFromContent(ch.content).toDelta();
    final cleaned = removeFsidFromDelta(delta, seg.id);
    final newJson = jsonEncode(cleaned.toJson());
    if (newJson == ch.content) return;
    await durability.manualSnapshot(ch);
    ch.content = newJson;
    await chapters.updateContent(ch);
    final inList = chapterList.where((c) => c.id == ch.id).firstOrNull;
    if (inList != null) inList.content = newJson;
  }

  /// 面板 → 编辑器：打开片段所在章节并选中标注文字。
  /// 返回 false 表示章节不存在或片段已失锚（正文无该标注）。
  Future<bool> jumpToSegment(ForeshadowSegment seg) async {
    if (currentChapter?.id != seg.chapterId) {
      final target =
          chapterList.where((c) => c.id == seg.chapterId).firstOrNull;
      if (target == null) return false;
      await openChapter(target);
    }
    final ranges = deltaFsidRanges(editorController.document.toDelta(), seg.id);
    if (ranges.isEmpty) return false;
    final r = ranges.first;
    editorController.updateSelection(
        TextSelection(baseOffset: r.$1, extentOffset: r.$2),
        ChangeSource.local);
    segmentJumpNonce.value++;
    return true;
  }

  /// 跳转并选中指定章节的正文区间（敏感词结果点击定位）。
  Future<bool> jumpToTextRange(String chapterId, int start, int end) async {
    if (currentChapter?.id != chapterId) {
      final target = chapterList.where((c) => c.id == chapterId).firstOrNull;
      if (target == null) return false;
      await openChapter(target);
    }
    final docLen = editorController.document.length;
    final s = start.clamp(0, docLen);
    final e = end.clamp(s, docLen);
    editorController.updateSelection(
        TextSelection(baseOffset: s, extentOffset: e), ChangeSource.local);
    segmentJumpNonce.value++;
    return true;
  }

  /// 即将被删除的章节所对应的窗格邻位章节。
  Map<String, String?> _neighborAfterRemoval(Set<String> removed) {
    final result = <String, String?>{};
    for (final entry in _sessions.entries) {
      final pane = entry.value;
      final activeId = pane.activeChapter?.id;
      if (activeId == null || !removed.contains(activeId)) continue;
      final pos = pane.tabIds.indexOf(activeId);
      result[entry.key] = _neighborTabId(
        pane.tabIds,
        pos < 0 ? pane.tabIds.length : pos,
        removed,
      );
    }
    return result;
  }

  /// 删除章节 → 回收站（FR-6 / NFR-R5）。
  Future<void> deleteChapter(String id) async {
    final ch = await chapters.get(id);
    if (ch == null) return;
    await autosave.flush();
    final neighbors = _neighborAfterRemoval({id});
    await recycle.add(RecycleType.chapter, id, {
      'book_id': ch.bookId,
      'volume_id': ch.volumeId,
      'title': ch.title,
      'content': ch.content,
      'outline': ch.outline,
      'sort': ch.sort,
    });
    await chapters.hardDelete(id);
    await _reloadTree(preferredActive: neighbors);
    notifyListeners();
  }

  /// 删除卷 → 回收站（卷内章节一并打包）。
  Future<void> deleteVolume(String id) async {
    final vol = volumeTree.firstWhere((v) => v.id == id);
    await autosave.flush();
    final list = chapterList.where((c) => c.volumeId == id).toList();
    final removed = list.map((c) => c.id).toSet();
    final neighbors = _neighborAfterRemoval(removed);
    await recycle.add(RecycleType.volume, id, {
      'book_id': vol.bookId,
      'name': vol.name,
      'sort': vol.sort,
      'chapters': list.map((c) => {
            'id': c.id,
            'title': c.title,
            'content': c.content,
            'outline': c.outline,
            'sort': c.sort,
          }).toList(),
    });
    for (final c in list) {
      await chapters.hardDelete(c.id);
    }
    await _reloadTree(preferredActive: neighbors);
    notifyListeners();
  }

  /// 从回收站恢复章节。
  Future<void> restoreRecycleItem(RecycleItem item) async {
    if (item.type == RecycleType.book) {
      // 子数据删除书籍时未清理，恢复软删标记即全部复原。
      await books.restore(item.originId);
      await loadShelf();
    } else if (item.type == RecycleType.chapter) {
      final payload = Map<String, Object?>.from(_decode(item.payload));
      await chapters.create(
        bookId: payload['book_id'] as String,
        volumeId: payload['volume_id'] as String,
        title: payload['title'] as String? ?? '恢复章节',
        content: payload['content'] as String? ?? '',
        outline: payload['outline'] as String? ?? '',
      );
    } else if (item.type == RecycleType.volume) {
      final payload = Map<String, Object?>.from(_decode(item.payload));
      final vol = await volumes.create(
          payload['book_id'] as String, payload['name'] as String? ?? '恢复卷');
      final chs = (payload['chapters'] as List<Object?>?) ?? const [];
      for (final raw in chs) {
        final c = Map<String, Object?>.from(raw! as Map<String, Object?>);
        await chapters.create(
          bookId: vol.bookId,
          volumeId: vol.id,
          title: c['title'] as String? ?? '',
          content: c['content'] as String? ?? '',
          outline: c['outline'] as String? ?? '',
        );
      }
    } else if (item.type == RecycleType.character) {
      final payload = Map<String, Object?>.from(_decode(item.payload));
      final char = await characters.create(
        bookId: payload['book_id'] as String,
        name: payload['name'] as String? ?? '恢复角色',
      );
      char.aliases = payload['aliases'] as String? ?? '';
      char.type = CharacterType.values.firstWhere(
        (t) => t.name == payload['type'], orElse: () => CharacterType.protagonist);
      char.gender = Gender.values.firstWhere(
        (g) => g.name == payload['gender'], orElse: () => Gender.male);
      char.attributes = payload['attributes'] as String? ?? '';
      char.color = payload['color'] as String? ?? '';
      char.tags = payload['tags'] as String? ?? '';
      await characters.update(char);
      characterDictVersion.value++;
    } else if (item.type == RecycleType.foreshadow) {
      final payload = Map<String, Object?>.from(_decode(item.payload));
      // 以原 id 重建伏笔与片段，正文中的 fsid 标注才能恢复关联。
      final fs = await foreshadows.create(
        bookId: payload['book_id'] as String,
        name: payload['name'] as String? ?? '恢复伏笔',
        id: item.originId,
      );
      fs.status = ForeshadowStatus.values.firstWhere(
        (s) => s.name == payload['status'],
        orElse: () => ForeshadowStatus.undone);
      fs.sort = (payload['sort'] as int?) ?? 0;
      await foreshadows.update(fs);
      final segs = (payload['segments'] as List<Object?>?) ?? const [];
      for (final raw in segs) {
        final m = Map<String, Object?>.from(raw! as Map);
        await fsSegments.create(
          fsId: fs.id,
          chapterId: m['chapter_id'] as String? ?? '',
          excerpt: m['excerpt'] as String? ?? '',
          remark: m['remark'] as String? ?? '',
          id: m['id'] as String?,
        );
      }
      foreshadowVersion.value++;
    }
    await recycle.remove(item.id);
    if (currentBook != null) await _reloadTree();
    notifyListeners();
  }

  static Map<String, Object?> _decode(String payload) =>
      Map<String, Object?>.from(jsonDecode(payload) as Map);

  void startSyncWatch() {
    _syncSub ??= sync.events.listen((_) {});
  }

  /// 联网自动增量同步入口（FR-12）。
  Future<List<SyncConflict>> syncNow() async {
    if (!settings.syncEnabled || currentBook == null) return const [];
    await autosave.flush();
    return sync.syncAll(currentBook!.id);
  }

  /// 应用退出前：保存 UI 快照与布局 + 冲刷保存 + 记录写作时长 + 清除崩溃标记。
  Future<void> shutdown() async {
    await _persistBookUi();
    await autosave.flush(withBackup: false);
    session.end();
    await crash.clear();
    autosave.dispose();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _layoutDebounce?.cancel();
    _goalToasts.close();
    chapterDragCount.dispose();
    for (final pane in _sessions.values) {
      pane.dispose();
    }
    _sessions.clear();
    _scratchController?.dispose();
    autosave.dispose();
    super.dispose();
  }

  /// 切换字数口径后：全库重算 char_count，并刷新所有窗格的章节实例。
  Future<void> recountAll() async {
    await autosave.flush();
    await chapters.recountAll(settings.countStandard);
    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    for (final pane in _sessions.values) {
      final id = pane.activeChapter?.id;
      if (id == null) continue;
      final fresh = _chapterById(id);
      if (fresh != null) pane.activeChapter = fresh;
    }
    _commitLayout();
    notifyListeners();
  }
}

/// 单本书的会话内 UI 状态（内存，跨书切换保留；落盘由 [_persistBookUi] 负责）。
class BookUiSnapshot {
  BookUiSnapshot();

  /// 左侧目录树中展开的卷 id 集合。
  final Set<String> expandedVolumes = <String>{};

  /// 是否已从 config.json 载入过持久化的展开集合（跨会话还原一次）。
  bool treeLoaded = false;

  /// 离开该书时编辑器的滚动偏移（EditorArea 滚动时实时同步）。
  double scrollOffset = 0;
}

/// 全书敏感词检测的单章结果。
class SensitiveChapterScan {
  SensitiveChapterScan({required this.chapter, required this.matches});

  final Chapter chapter;
  final List<SensitiveMatch> matches;

  int get count => matches.fold(0, (sum, m) => sum + m.count);
}
