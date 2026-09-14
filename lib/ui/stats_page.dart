import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'widgets/app_icon.dart';
import 'widgets/window_controls.dart';

/// 码字统计页（FR-14 / FR-15 / 9.6）：日/周/月曲线、时长、速度、每日目标。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(title: Text('码字统计')),
      body: const StatsView(),
    );
  }
}

/// 码字统计内容（无页头），供统计页与工作区侧边统计面板复用。
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  int _range = 7;
  Future<List<WriteRecord>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<WriteRecord>> _load() =>
      context.read<AppState>().stats.recent(_range);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return FutureBuilder<List<WriteRecord>>(
      future: _future,
      builder: (ctx, snap) {
          final records = snap.data ?? const <WriteRecord>[];
          final total = records.fold(0, (s, r) => s + r.chars);
          final durationMin =
              records.fold(0, (s, r) => s + r.durationMs) ~/ 60000;
          final todayChars = records.isEmpty ? 0 : records.last.chars;
          final progress = (todayChars / settings.dailyGoal).clamp(0.0, 1.0);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('近 7 天')),
                  ButtonSegment(value: 30, label: Text('近 30 天')),
                  ButtonSegment(value: 90, label: Text('近 90 天')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() {
                  _range = s.first;
                  _future = _load();
                }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _metric(context, '区间总字数', '$total'),
                  _metric(context, '写作时长', '$durationMin 分钟'),
                  _metric(
                    context,
                    '码字速度',
                    '${durationMin > 0 ? (total / durationMin).toStringAsFixed(1) : '0'} 字/分',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _dailyGoalCard(context, todayChars, progress),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '码字字数曲线',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 180,
                        child: records.isEmpty
                            ? const Center(child: Text('暂无数据'))
                            : CustomPaint(
                                painter: _LineChartPainter(
                                  records
                                      .map((r) => r.chars.toDouble())
                                      .toList(),
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '口径：字符数（含标点，不含空白）',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('写作历史', style: Theme.of(context).textTheme.titleSmall),
              for (final r in records.reversed.take(15))
                ListTile(
                  dense: true,
                  leading: const AppIcon(Icons.history_edu, size: 16),
                  title: Text(_dateLabel(r.date)),
                  trailing: Text(
                    '${r.chars} 字 · ${r.durationMs ~/ 60000} 分钟',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      );
  }

  Widget _dailyGoalCard(BuildContext context, int todayChars, double progress) {
    final reached = progress >= 1.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('今日目标', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$todayChars 字',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 8),
            if (reached)
              const _CelebrateRow()
            else
              Text(
                '距离目标还差 ${(1 - progress) * 100 == 0 ? 0 : ((1 - progress) * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天';
    }
    return '${d.month}/${d.day}';
  }
}

class _CelebrateRow extends StatefulWidget {
  const _CelebrateRow();

  @override
  State<_CelebrateRow> createState() => _CelebrateRowState();
}

class _CelebrateRowState extends State<_CelebrateRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
      child: Row(
        children: [
          AppIcon(
            Icons.emoji_events,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text('恭喜！今日码字目标已达成 🎉'),
        ],
      ),
    );
  }
}

/// 简易折线 + 柱状图（自绘，避免重依赖）。
class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.values, {required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = max(values.reduce(max), 1.0);
    final barWidth = size.width / values.length;

    // 柱状背景。
    final barPaint = Paint()..color = color.withAlpha(40);
    for (var i = 0; i < values.length; i++) {
      final h = size.height * (values[i] / maxV);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth + barWidth * 0.15,
            size.height - h,
            barWidth * 0.7,
            h,
          ),
          const Radius.circular(3),
        ),
        barPaint,
      );
    }

    // 折线。
    if (values.length >= 2) {
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = i * barWidth + barWidth / 2;
        final y = size.height - size.height * (values[i] / maxV) * 0.92 - 4;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
