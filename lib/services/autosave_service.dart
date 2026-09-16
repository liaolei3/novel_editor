import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import 'durability_service.dart';
import 'logger.dart';

/// 自动保存（FR-2 / NFR-R2）：
/// - 输入停顿 ≤2 秒防抖落盘；
/// - 每 30 秒兜底保存一次；
/// - 保存失败回调（角标 + 弹窗由状态层处理）。
class AutosaveService {
  AutosaveService(this._chapters, this._durability);

  final ChapterRepository _chapters;
  final DurabilityService _durability;

  Timer? _debounce;
  Timer? _interval;
  Chapter? _pending;

  bool _saving = false;

  ValueNotifier<SaveState> state =
      ValueNotifier<SaveState>(SaveState.saved);

  void startInterval() {
    _interval?.cancel();
    _interval = Timer.periodic(AppConstants.autosaveInterval, (_) {
      if (_pending != null) flush();
    });
  }

  void stopInterval() {
    _interval?.cancel();
    _interval = null;
  }

  /// 编辑器内容变化时调用。
  void onContentChanged(Chapter chapter, String content) {
    chapter.content = content;
    _pending = chapter;
    state.value = SaveState.unsaved;
    _debounce?.cancel();
    _debounce = Timer(AppConstants.autosaveDebounce, flush);
  }

  /// 立即落盘（切换章节 / 退出前调用）。
  /// [withBackup] 为 false 时跳过备份副本文件写入：关闭路径只保证主库落盘，
  /// 避免冗余备份被文件系统/杀毒扫描阻塞导致窗口迟迟无法关闭。
  Future<bool> flush({bool withBackup = true}) async {
    _debounce?.cancel();
    final chapter = _pending;
    if (chapter == null || _saving) return true;
    _saving = true;
    state.value = SaveState.saving;
    try {
      await _chapters.updateContent(chapter);
      if (withBackup) {
        await _durability.backupChapter(chapter);
      }

      _pending = null;
      state.value = SaveState.saved;
      return true;
    } catch (e, s) {
      Logger.error('自动保存失败: ${chapter.id}',
          error: e, stackTrace: s, tag: 'Autosave');
      state.value = SaveState.failed;
      return false;
    } finally {
      _saving = false;
    }
  }

  void dispose() {
    _debounce?.cancel();
    stopInterval();
  }
}

enum SaveState { saved, unsaved, saving, failed }