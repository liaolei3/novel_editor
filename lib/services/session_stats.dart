import 'dart:async';

import '../core/constants.dart';
import '../data/repositories.dart';

/// 会话码字统计（FR-5 / FR-14）：
/// 记录本次会话新增字数、纯码字时长与摸鱼时长，并按日累计落库。
///
/// 摸鱼判定：距最后一次键入超过 [idleThreshold] 即进入摸鱼状态，
/// 恢复键入则摸鱼段结束并计 1 次摸鱼；应用失焦不算摸鱼。
class SessionStats {
  SessionStats(this._stats);

  final StatsRepository _stats;
  static const idleThreshold = Duration(minutes: 3);

  Timer? _timer;
  Timer? _idleTimer;
  DateTime? _lastInputAt;
  DateTime? _idleStart;
  int _pendingIdleMs = 0;

  int sessionChars = 0;
  final DateTime sessionStart = DateTime.now();
  final _changes = StreamController<int>.broadcast();

  Stream<int> get changes => _changes.stream;

  int get sessionMinutes => DateTime.now().difference(sessionStart).inMinutes;

  /// 码字速度（字/分钟），FR-14。
  double get speed {
    final m = sessionMinutes < 1 ? 1 : sessionMinutes;
    return sessionChars / m;
  }

  void begin() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void end() {
    _timer?.cancel();
    _stopIdle();
    _tick();
  }

  /// 编辑内容变化时由状态层调用：[delta] 为相对上次保存的新增字符数。
  Future<void> addChars(int delta) async {
    if (delta == 0) return;
    _onUserInput();
    sessionChars += delta > 0 ? delta : 0;
    _changes.add(sessionChars);
    await _stats.addChars(delta);
  }

  void _onUserInput() {
    final now = DateTime.now();
    _lastInputAt = now;
    // 结束当前摸鱼段：累计摸鱼时长，一段计 1 次。
    if (_idleStart != null) {
      _pendingIdleMs += now.difference(_idleStart!).inMilliseconds;
      final flush = _pendingIdleMs;
      _pendingIdleMs = 0;
      _idleStart = null;
      _stats.addIdle(durationMs: flush, count: 1);
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleThreshold, () {
      // 超时未键入，进入摸鱼状态。
      _idleStart = DateTime.now();
    });
  }

  void _stopIdle() {
    _idleTimer?.cancel();
    // 应用退出时若处于摸鱼中，把未结算的摸鱼段落库（不计次数，避免半段凑数）。
    if (_idleStart != null) {
      final ms = DateTime.now().difference(_idleStart!).inMilliseconds;
      if (ms > 0) _stats.addIdle(durationMs: ms);
      _idleStart = null;
    } else if (_pendingIdleMs > 0) {
      final ms = _pendingIdleMs;
      _pendingIdleMs = 0;
      _stats.addIdle(durationMs: ms);
    }
  }

  void _tick() {
    // 每分钟累计纯码字时长（有键入活动才计，区分挂机）。
    if (_lastInputAt != null &&
        DateTime.now().difference(_lastInputAt!) < const Duration(minutes: 1)) {
      _stats.addChars(0, durationMs: 60000);
    }
  }

  /// 每日目标进度（0~1），FR-15。
  Future<double> dailyGoalProgress(int goal) async {
    if (goal <= 0) return 0;
    final rec = await _stats.today();
    return (rec.chars / goal).clamp(0.0, 1.0);
  }

  static bool get goalEnabled => AppConstants.defaultDailyGoal > 0;
}
