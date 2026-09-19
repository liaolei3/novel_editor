import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';


import '../core/utils/chapter_title_suggest.dart';
import '../core/utils/foreshadow_delta.dart';
import '../core/utils/global_search.dart';
import '../core/utils/rich_text_codec.dart';
import '../core/utils/text_stats.dart';
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
    required this.notes,
    required this.characters,
    required this.foreshadows,
    required this.fsSegments,
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
  final NoteRepository notes;
  final CharacterRepository characters;
  final ForeshadowRepository foreshadows;
  final ForeshadowSegmentRepository fsSegments;
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

  /// 打开作品：加载卷章树并恢复上次编辑位置（12.1）。
  Future<void> openBook(Book book, {String? startChapterId}) async {
    await autosave.flush();
    currentBook = book;
    _resetEditor();
    currentChapter = null;
    await _reloadTree();
    bookCharTotal =
        chapterList.fold(0, (sum, c) => sum + c.charCount);
    await settings.setLastBookId(book.id);
    final targetId = startChapterId ??
        book.lastChapterId ??
        (chapterList.isNotEmpty ? chapterList.first.id : null);
    if (targetId != null) {
      final ch = await chapters.get(targetId);
      if (ch != null) await openChapter(ch);
    }
    notifyListeners();
  }

  Future<void> _reloadTree() async {
    if (currentBook == null) return;
    volumeTree = await volumes.listByBook(currentBook!.id);
    chapterList = await chapters.listByBook(currentBook!.id);
  }

  /// 对外暴露的树刷新（大纲编辑等场景）。
  Future<void> reloadTreePublic() async {
    await _reloadTree();
    bookCharTotal = chapterList.fold(0, (sum, c) => sum + c.charCount);
    notifyListeners();
  }

  /// 全书搜索（正文 / 章纲 / 角色 / 标题）。
  Future<List<GlobalSearchHit>> globalSearch(
      String query, Set<SearchScope> scopes) async {
    if (currentBook == null || query.isEmpty) return const [];
    final chars = scopes.contains(SearchScope.character)
        ? await characters.listByBook(currentBook!.id)
        : const <Character>[];
    return GlobalSearch.search(
      query: query,
      scopes: scopes,
      chapters: chapterList,
      volumes: volumeTree,
      characters: chars,
    );
  }

  /// 全书替换：命中处统一直接写回（不做撤销），
  /// 正文替换保留富文本格式；执行前为每个被修改的章节自动创建快照。
  Future<int> globalReplace({
    required String query,
    required String replacement,
    required Set<SearchScope> scopes,
  }) async {
    if (currentBook == null || query.isEmpty) return 0;
    await autosave.flush();
    var total = 0;
    var contentChanged = false;

    for (final ch in List<Chapter>.of(chapterList)) {
      if (scopes.contains(SearchScope.content) && ch.content.isNotEmpty) {
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
      if (scopes.contains(SearchScope.outline) && ch.outline.contains(query)) {
        final n = GlobalSearch.matchStarts(ch.outline, query).length;
        ch.outline = ch.outline.replaceAll(query, replacement);
        await chapters.updateOutline(ch.id, ch.outline);
        total += n;
      }
      if (scopes.contains(SearchScope.title) && ch.title.contains(query)) {
        final n = GlobalSearch.matchStarts(ch.title, query).length;
        ch.title = ch.title.replaceAll(query, replacement);
        await chapters.updateTitle(ch.id, ch.title);
        total += n;
      }
    }

    if (scopes.contains(SearchScope.title)) {
      for (final v in volumeTree) {
        if (v.name.contains(query)) {
          final n = GlobalSearch.matchStarts(v.name, query).length;
          v.name = v.name.replaceAll(query, replacement);
          await volumes.rename(v.id, v.name);
          total += n;
        }
      }
    }

    var characterChanged = false;
    if (scopes.contains(SearchScope.character)) {
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

  /// 打开章节（≤300ms 预算：单次查询 + 控制器赋值）。
  Future<void> openChapter(Chapter chapter) async {
    if (currentChapter?.id == chapter.id) return;
    await autosave.flush();
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
      bookCharTotal += delta;
      chapter.charCount = nowChars;
    }
    notifyListeners();
  }

  Future<void> saveCursor() async {
    final chapter = currentChapter;
    if (chapter == null) return;
    await chapters.updateCursor(chapter.id, editorController.selection.baseOffset);
    if (currentBook != null) {
      await books.saveLocation(currentBook!.id, chapter.id,
          editorController.selection.baseOffset);
    }
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

  Future<Chapter> addChapter(String volumeId, {String? title, String? outline}) async {
    final ch = await chapters.create(
      bookId: currentBook!.id,
      volumeId: volumeId,
      title: title ?? '新章节',
      outline: outline ?? '',
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
    if (currentChapter?.id == id) {
      currentChapter = null;
      _resetEditor();

    }
    await chapters.hardDelete(id);
    await _reloadTree();
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
    for (final c in list) {
      if (currentChapter?.id == c.id) {
        currentChapter = null;
        _resetEditor();

      }
      await chapters.hardDelete(c.id);
    }
    await _reloadTree();
    notifyListeners();
  }

  /// 从回收站恢复章节。
  Future<void> restoreRecycleItem(RecycleItem item) async {
    if (item.type == RecycleType.chapter) {
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

  /// 应用退出前：冲刷保存 + 记录写作时长 + 清除崩溃标记。
  Future<void> shutdown() async {
    await saveCursor();
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
