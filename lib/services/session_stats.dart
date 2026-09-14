import 'dart:async';

import '../core/constants.dart';
import '../data/repositories.dart';

/// 会话码字统计（FR-5 / FR-14）：
/// 记录本次会话新增字数、写作时长，并按日累计落库。
class SessionStats {
  SessionStats(this._stats);

  final StatsRepository _stats;
  Timer? _timer;

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
    _tick();
  }

  /// 编辑内容变化时由状态层调用：[delta] 为相对上次保存的新增字符数。
  Future<void> addChars(int delta) async {
    if (delta == 0) return;
    sessionChars += delta > 0 ? delta : 0;
    _changes.add(sessionChars);
    await _stats.addChars(delta);
  }

  void _tick() {
    // 每分钟累计写作时长。
    _stats.addChars(0, durationMs: 60000);
  }

  /// 每日目标进度（0~1），FR-15。
  Future<double> dailyGoalProgress(int goal) async {
    if (goal <= 0) return 0;
    final rec = await _stats.today();
    return (rec.chars / goal).clamp(0.0, 1.0);
  }

  static bool get goalEnabled => AppConstants.defaultDailyGoal > 0;
}