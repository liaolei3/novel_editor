import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';


import '../core/utils/global_search.dart';
import '../core/utils/rich_text_codec.dart';
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

  Future<Book> createBook(String title, String penName) async {
    final book = await books.create(title, penName: penName);
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
      const fields = [
        ('name', '名字'),
        ('aliases', '别名'),
        ('appearance', '外貌'),
        ('personality', '性格'),
        ('background', '背景'),
        ('tags', '标签'),
      ];
      final list = await characters.listByBook(currentBook!.id);
      for (final c in list) {
        var changed = false;
        for (final (key, _) in fields) {
          final text = switch (key) {
            'name' => c.name,
            'aliases' => c.aliases,
            'appearance' => c.appearance,
            'personality' => c.personality,
            'background' => c.background,
            _ => c.tags,
          };
          if (!text.contains(query)) continue;
          final n = GlobalSearch.matchStarts(text, query).length;
          final replaced = text.replaceAll(query, replacement);
          switch (key) {
            case 'name':
              c.name = replaced;
            case 'aliases':
              c.aliases = replaced;
            case 'appearance':
              c.appearance = replaced;
            case 'personality':
              c.personality = replaced;
            case 'background':
              c.background = replaced;
            default:
              c.tags = replaced;
          }
          total += n;
          changed = true;
        }
        if (changed) {
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
    final nowChars = _countChars(plainText);
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
      char.appearance = payload['appearance'] as String? ?? '';
      char.personality = payload['personality'] as String? ?? '';
      char.background = payload['background'] as String? ?? '';
      char.color = payload['color'] as String? ?? '';
      char.tags = payload['tags'] as String? ?? '';
      await characters.update(char);
      characterDictVersion.value++;
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

  static int _countChars(String content) {
    var n = 0;
    for (final rune in content.runes) {
      final ch = String.fromCharCode(rune);
      if (ch.trim().isNotEmpty) n++;
    }
    return n;
  }
}
