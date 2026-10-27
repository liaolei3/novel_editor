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
import 'settings_controller.dart';

/// 全局应用状态：书架、作品树、当前章节编辑、保存状态、同步入口。
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
    // 仅文档内容变化时通知（document.changes 流不发纯选区事件），
    // 光标移动不再触发保存；未绑定则手动输入不会落盘。
    _docSub = editorController.document.changes.listen((_) => onEditorChanged());
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
  Chapter? currentChapter;

  QuillController editorController = QuillController.basic();
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

  /// 离开当前书时落盘 UI 快照：当前章光标（内存 + DB）、书级位置与滚动（DB）、
  /// 树展开与面板状态（config.json）。
  Future<void> _persistBookUi() async {
    final book = currentBook;
    if (book == null) return;
    final chapter = currentChapter;
    final snap = _uiSnaps[book.id];
    final sel = editorController.selection;
    final cursor =
        (sel.baseOffset >= 0 && sel.baseOffset <= editorController.document.length)
            ? sel.baseOffset
            : null;
    if (chapter != null) {
      if (cursor != null) chapter.cursorOffset = cursor;
      await chapters.updateCursor(chapter.id, cursor ?? chapter.cursorOffset);
    }
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
      await settings.saveBookUi(
        book.id,
        tree: snap.expandedVolumes.toList(),
        chapterTabs: snap.chapterTabIds.toList(),
      );
    }
  }

  StreamSubscription<SyncEvent>? _syncSub;

  /// document.changes 内容变化订阅；document 实例被替换时需重绑。
  StreamSubscription? _docSub;

  /// 程序化加载文档期间为 true，抑制 onEditorChanged 误触发。
  bool _loadingDoc = false;

  /// 上次编辑器文档序列化结果，用于忽略纯光标/选区变化。
  String? _lastDocJson;


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

  /// 打开作品：加载卷章树并恢复上次编辑位置（12.1）。
  /// 打开前先将上一本书的 UI 快照落盘（切书还原）。
  Future<void> openBook(Book book, {String? startChapterId}) async {
    await autosave.flush();
    await _persistBookUi();
    currentBook = book;
    _resetEditor();
    currentChapter = null;
    await _reloadTree();
    bookCharTotal =
        chapterList.fold(0, (sum, c) => sum + c.charCount);
    await _loadTodayStats();
    await settings.setLastBookId(book.id);
    await settings.touchRecentBook(book.id);
    final targetId = startChapterId ??
        book.lastChapterId ??
        (chapterList.isNotEmpty ? chapterList.first.id : null);
    final snap = uiSnapshot(book.id);
    if (!snap.treeLoaded) {
      // 首次进入快照：从 config.json 还原该书的目录树展开卷（跨会话）。
      snap.expandedVolumes.addAll(settings.bookUiOf(book.id).tree);
      snap.treeLoaded = true;
    }
    if (!snap.tabsLoaded) {
      // 首次进入快照：还原章节标签，剔除已删除章节并去重。
      final validIds = chapterList.map((c) => c.id).toSet();
      for (final id in settings.bookUiOf(book.id).chapterTabs) {
        if (validIds.contains(id) && !snap.chapterTabIds.contains(id)) {
          snap.chapterTabIds.add(id);
        }
      }
      snap.tabsLoaded = true;
    }
    if (targetId != null) {
      final ch = await chapters.get(targetId);
      if (ch != null) {
        _pendingRestoreScroll = snap.scrollOffset;
        await openChapter(ch);
      }
    }
    notifyListeners();
  }

  Future<void> _reloadTree() async {
    if (currentBook == null) return;
    volumeTree = await volumes.listByBook(currentBook!.id);
    chapterList = await chapters.listByBook(currentBook!.id);
    // 章节被删除 / 同步移除后，标签里不再存在的 id 一并剔除。
    final snap = uiSnapshot(currentBook!.id);
    final validIds = chapterList.map((c) => c.id).toSet();
    final before = snap.chapterTabIds.length;
    snap.chapterTabIds.removeWhere((id) => !validIds.contains(id));
    if (snap.chapterTabIds.length != before) await _saveChapterTabs();
  }

  /// 章节标签顺序落盘（config.json bookUi）。
  Future<void> _saveChapterTabs() async {
    final book = currentBook;
    if (book == null) return;
    final snap = uiSnapshot(book.id);
    await settings.saveBookUi(
      book.id,
      tree: snap.expandedVolumes.toList(),
      chapterTabs: snap.chapterTabIds.toList(),
    );
  }

  /// 当前书的章节标签（按标签顺序解析为章对象）。
  List<Chapter> get chapterTabs {
    final book = currentBook;
    if (book == null) return const [];
    final byId = {for (final c in chapterList) c.id: c};
    return [
      for (final id in uiSnapshot(book.id).chapterTabIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

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

  /// 关闭章节标签：移除标签；关的是当前章时切到邻位，无标签则进入空态。
  Future<void> closeChapterTab(String id) async {
    final book = currentBook;
    if (book == null) return;
    final snap = uiSnapshot(book.id);
    final pos = snap.chapterTabIds.indexOf(id);
    if (pos < 0) return;
    final wasCurrent = currentChapter?.id == id;
    final nextId = wasCurrent
        ? _neighborTabId(snap.chapterTabIds, pos, {id})
        : null;
    snap.chapterTabIds.removeAt(pos);
    await _saveChapterTabs();
    if (!wasCurrent) {
      notifyListeners();
      return;
    }
    final next =
        chapterList.where((c) => c.id == nextId).firstOrNull;
    if (next != null) {
      await openChapter(next);
      return;
    }
    await autosave.flush();
    final ch = currentChapter;
    if (ch != null) await _saveCursorTo(ch);
    currentChapter = null;
    _resetEditor();
    notifyListeners();
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
    var contentChanged = false;

    for (final ch in List<Chapter>.of(chapterList)) {
      if (ch.content.isNotEmpty) {
        final (newJson, n) =
            GlobalSearch.replaceInDeltaJson(ch.content, query, replacement);
        if (n > 0) {
          await durability.manualSnapshot(ch);
          ch.content = newJson;
          await chapters.updateContent(ch);
          total += n;
          if (currentChapter?.id == ch.id) contentChanged = true;
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
      if (contentChanged && currentChapter != null) {
        final fresh = chapterList
            .where((c) => c.id == currentChapter!.id)
            .firstOrNull;
        if (fresh != null) {
          currentChapter = fresh;
          _loadingDoc = true;
          try {
            replaceDocument(
                RichTextCodec.documentFromContent(fresh.content),
                fireChange: false);
          } finally {
            _loadingDoc = false;
            _lastDocJson =
                jsonEncode(editorController.document.toDelta().toJson());
          }
        }
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
    var contentChanged = false;
    for (final ch in list) {
      final (n, sk) = await _replaceSensitiveChapter(ch, scanner);
      total += n;
      skipped.addAll(sk);
      if (n > 0 && currentChapter?.id == ch.id) contentChanged = true;
      onProgress?.call(++done, list.length);
    }
    if (total > 0) {
      await _reloadTree();
      bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
      if (contentChanged && currentChapter != null) {
        _reloadCurrentDocIfNeeded(currentChapter!.id);
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

  /// 替换后重载指定章（仅当它正是当前章）的编辑器文档。
  void _reloadCurrentDocIfNeeded(String chapterId) {
    if (currentChapter?.id != chapterId) return;
    final fresh = chapterList.where((c) => c.id == chapterId).firstOrNull;
    if (fresh == null) return;
    currentChapter = fresh;
    _loadingDoc = true;
    try {
      replaceDocument(RichTextCodec.documentFromContent(fresh.content),
          fireChange: false);
    } finally {
      _loadingDoc = false;
      _lastDocJson = jsonEncode(editorController.document.toDelta().toJson());
    }
  }

  /// 把编辑器当前光标写回指定章节（内存 + DB）。
  Future<void> _saveCursorTo(Chapter chapter) async {
    final off = editorController.selection.baseOffset;
    if (off < 0 || off > editorController.document.length) return;
    chapter.cursorOffset = off;
    await chapters.updateCursor(chapter.id, off);
  }

  /// 打开章节（≤300ms 预算：单次查询 + 控制器赋值）。
  /// 离开旧章前把光标偏移写入内存章对象，供同会话切回时还原。
  Future<void> openChapter(Chapter chapter) async {
    if (currentChapter?.id == chapter.id) return;
    final book = currentBook;
    if (book != null && chapter.bookId == book.id) {
      final snap = uiSnapshot(book.id);
      if (!snap.chapterTabIds.contains(chapter.id)) {
        snap.chapterTabIds.add(chapter.id);
        await _saveChapterTabs();
      }
    }
    await autosave.flush();
    final prev = currentChapter;
    if (prev != null) await _saveCursorTo(prev);
    currentChapter = chapter;
    _loadingDoc = true;
    try {
      replaceDocument(RichTextCodec.documentFromContent(chapter.content),
          fireChange: false);
      final docLen = editorController.document.length;
      editorController.updateSelection(
          TextSelection.collapsed(offset: chapter.cursorOffset.clamp(0, docLen)),
          ChangeSource.local);
    } finally {
      _loadingDoc = false;
      _lastDocJson = jsonEncode(editorController.document.toDelta().toJson());
    }

    await durability.autoSnapshotIfNeeded(chapter);
    await autosave.flush();
    notifyListeners();
  }

  /// 替换编辑器文档并重绑内容变化监听。
  /// [fireChange] 为 true 时按一次内容变化处理（回滚/替换等主动修改场景）。
  void replaceDocument(Document doc, {bool fireChange = true}) {
    editorController.document = doc;
    _docSub?.cancel();
    _docSub = editorController.document.changes.listen((_) => onEditorChanged());
    if (fireChange) onEditorChanged();
  }

  /// 编辑器内容变化：防抖自动保存 + 实时字数。
  void onEditorChanged() {
    if (_loadingDoc) return;
    final chapter = currentChapter;
    if (chapter == null) return;
    final content = jsonEncode(editorController.document.toDelta().toJson());
    if (content == _lastDocJson) return;
    _lastDocJson = content;
    final plainText = editorController.document.toPlainText();
    final nowChars = TextStats.count(plainText, settings.countStandard);
    final delta = nowChars - chapter.charCount;
    autosave.onContentChanged(chapter, content);
    if (delta != 0) {
      session.addChars(delta);
      _onCharsDelta(delta);
      bookCharTotal += delta;
      chapter.charCount = nowChars;
      // 作品树直接读 chapterList 的 char_count，需同步同 id 项，
      // 以免 currentChapter 与 chapterList 为不同实例时字数显示滞后。
      final idx = chapterList.indexWhere((c) => c.id == chapter.id);
      if (idx >= 0) chapterList[idx].charCount = nowChars;
      _checkGoals();
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
  void _checkGoals() {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null) return;

    final done = <String>[];

    final chGoal = resolvedChapterGoal;
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

  /// 删除章节 → 回收站（FR-6 / NFR-R5）。
  Future<void> deleteChapter(String id) async {
    final ch = await chapters.get(id);
    if (ch == null) return;
    await recycle.add(RecycleType.chapter, id, {
      'book_id': ch.bookId,
      'volume_id': ch.volumeId,
      'title': ch.title,
      'content': ch.content,
      'outline': ch.outline,
      'sort': ch.sort,
    });
    final wasCurrent = currentChapter?.id == id;
    final snap = currentBook == null ? null : uiSnapshot(currentBook!.id);
    final tabsBefore =
        snap == null ? const <String>[] : [...snap.chapterTabIds];
    final pos = tabsBefore.indexOf(id);
    if (wasCurrent) {
      currentChapter = null;
      _resetEditor();
    }
    await chapters.hardDelete(id);
    await _reloadTree();
    if (wasCurrent && snap != null) {
      final nextId = _neighborTabId(
        tabsBefore,
        pos < 0 ? tabsBefore.length : pos,
        {id},
      );
      final next = nextId == null
          ? null
          : chapterList.where((c) => c.id == nextId).firstOrNull;
      if (next != null) {
        await openChapter(next);
      }
    }
    notifyListeners();
  }

  /// 删除卷 → 回收站（卷内章节一并打包）。
  Future<void> deleteVolume(String id) async {
    final vol = volumeTree.firstWhere((v) => v.id == id);
    final list = chapterList.where((c) => c.volumeId == id).toList();
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
    final currentId = currentChapter?.id;
    final removed = list.map((c) => c.id).toSet();
    final wasCurrent = currentId != null && removed.contains(currentId);
    final snap = currentBook == null ? null : uiSnapshot(currentBook!.id);
    final tabsBefore =
        snap == null ? const <String>[] : [...snap.chapterTabIds];
    final pos = currentId == null ? -1 : tabsBefore.indexOf(currentId);
    if (wasCurrent) {
      currentChapter = null;
      _resetEditor();
    }
    for (final c in list) {
      await chapters.hardDelete(c.id);
    }
    await _reloadTree();
    if (wasCurrent && snap != null) {
      final nextId = _neighborTabId(
        tabsBefore,
        pos < 0 ? tabsBefore.length : pos,
        removed,
      );
      final next = nextId == null
          ? null
          : chapterList.where((c) => c.id == nextId).firstOrNull;
      if (next != null) {
        await openChapter(next);
      }
    }
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

  /// 应用退出前：保存 UI 快照 + 冲刷保存 + 记录写作时长 + 清除崩溃标记。
  Future<void> shutdown() async {
    await _persistBookUi();
    await autosave.flush(withBackup: false);
    session.end();
    await crash.clear();
    autosave.dispose();
  }

  /// 重置编辑器为空文档。
  void _resetEditor() {
    replaceDocument(RichTextCodec.documentFromContent(''), fireChange: false);
    editorController.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _docSub?.cancel();
    _goalToasts.close();
    editorController.dispose();
    autosave.dispose();
    super.dispose();
  }

  /// 切换字数口径后：全库重算 char_count，并刷新当前书的内存数据。
  Future<void> recountAll() async {
    await autosave.flush();
    await chapters.recountAll(settings.countStandard);
    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    final id = currentChapter?.id;
    if (id != null) {
      currentChapter =
          chapterList.where((c) => c.id == id).firstOrNull ?? currentChapter;
    }
    notifyListeners();
  }
}

/// 单本书的会话内 UI 状态（内存，跨书切换保留；落盘由 [_persistBookUi] 负责）。
class BookUiSnapshot {
  BookUiSnapshot();

  /// 左侧目录树中展开的卷 id 集合。
  final Set<String> expandedVolumes = <String>{};

  /// 章节标签顺序（章节 id）。
  final List<String> chapterTabIds = <String>[];

  /// 是否已从 config.json 载入过持久化的展开集合（跨会话还原一次）。
  bool treeLoaded = false;

  /// 是否已从 config.json 载入过章节标签（跨会话还原一次）。
  bool tabsLoaded = false;

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
