import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/text_stats.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'widgets/window_controls.dart';

/// 码字统计页（FR-14 / FR-15 / 9.6）：周/月/年指标、时速、摸鱼、码字日历。
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

/// 统计周期：本年、自然周（周一起）、自然月。
enum StatsRange { year, week, month }

/// 趋势折线的指标。
enum _TrendMetric { chars, minutes, speed }

/// 日历维度：日（当月日历）/ 月（全年月卡片）/ 年（多年卡片）。
enum _CalMode { day, month, year }

/// 码字统计内容（无页头），供统计页与主页侧栏复用。
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  StatsRange _range = StatsRange.week;
  DateTime _calendarMonth = DateTime.now();
  _CalMode _calMode = _CalMode.day;
  // 年视图的窗口末年（展示窗口末年往前 4 年，共 5 张年卡片）。
  int _yearWindowEnd = DateTime.now().year;
  Future<_StatsBundle>? _future;
  Future<List<WriteRecord>>? _monthFuture;
  // 月视图：整个日历年的记录。
  Future<List<WriteRecord>>? _calYearFuture;
  // 年视图：多年窗口的记录。
  Future<List<WriteRecord>>? _yearFuture;
  Future<List<WriteRecord>>? _trendFuture;
  _TrendMetric _trendMetric = _TrendMetric.chars;

  static const _yearWindowSize = 5;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _monthFuture = _loadMonth();
    _yearFuture = _loadYear();
    _trendFuture = _loadTrend();
  }

  static const _rangeLabels = {
    StatsRange.year: '本年',
    StatsRange.week: '本周',
    StatsRange.month: '本月',
  };

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_range) {
      case StatsRange.year:
        return DateTime(now.year, 1, 1);
      case StatsRange.week:
        final weekday = now.weekday; // Monday = 1
        return DateTime(now.year, now.month, now.day - (weekday - 1));
      case StatsRange.month:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<_StatsBundle> _load() async {
    final state = context.read<AppState>();
    final start = _periodStart;
    final records = await state.stats.range(start, DateTime.now());
    return _StatsBundle(records);
  }

  Future<List<WriteRecord>> _loadMonth() async {
    final state = context.read<AppState>();
    final first = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final last = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
    return state.stats.range(first, last);
  }

  Future<List<WriteRecord>> _loadCalYear() async {
    final state = context.read<AppState>();
    final first = DateTime(_calendarMonth.year, 1, 1);
    final last = DateTime(_calendarMonth.year + 1, 1, 0);
    return state.stats.range(first, last);
  }

  Future<List<WriteRecord>> _loadYear() async {
    final state = context.read<AppState>();
    final first = DateTime(_yearWindowEnd - _yearWindowSize + 1, 1, 1);
    final last = DateTime(_yearWindowEnd + 1, 1, 0);
    return state.stats.range(first, last);
  }

  /// 近 30 天（含今天）的日记录，供趋势折线使用。
  Future<List<WriteRecord>> _loadTrend() async {
    final state = context.read<AppState>();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 29);
    return state.stats.range(start, now);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return FutureBuilder<_StatsBundle>(
      future: _future,
      builder: (ctx, snap) {
        final bundle = snap.data ?? _StatsBundle(const []);
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final wide = constraints.maxWidth >= 960;
            return Align(
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: wide
                        ? SingleChildScrollView(
                            child: _wideLayout(context, bundle, settings),
                          )
                        : _narrowLayout(context, bundle, settings),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 布局骨架
  // ---------------------------------------------------------------------------

  /// 宽窗口：上行左今日目标、右区间汇总；下行左趋势图、右日历。
  /// 上下两栏左右等宽；下栏图表与日历固定高度 560，口径文字位于图表下方。
  Widget _wideLayout(
    BuildContext context,
    _StatsBundle bundle,
    SettingsController settings,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _todayCard(context, settings)),
                const SizedBox(width: 16),
                Expanded(child: _summaryCard(context, bundle)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 700, child: _chartCard(context, bundle)),
                    const SizedBox(height: 8),
                    _footnote(context, settings),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(height: 700, child: _calendarCard(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 窄窗口：单栏堆叠。
  Widget _narrowLayout(
    BuildContext context,
    _StatsBundle bundle,
    SettingsController settings,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(context, bundle),
        const SizedBox(height: 16),
        _todayCard(context, settings),
        const SizedBox(height: 16),
        _calendarCard(context),
        const SizedBox(height: 16),
        _chartCard(context, bundle, height: 260),
        const SizedBox(height: 8),
        _footnote(context, settings),
      ],
    );
  }

  Widget _footnote(BuildContext context, SettingsController settings) {
    return Text(
      '字数统计口径：${settings.countStandard.label}',
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 卡片
  // ---------------------------------------------------------------------------

  /// 区间汇总：标题行含周期切换（只影响本卡），五项指标（总字数 + 时长/时速/摸鱼）同一行横向排布。
  Widget _summaryCard(BuildContext context, _StatsBundle bundle) {
    final scheme = Theme.of(context).colorScheme;
    final durationMin = bundle.totalDurationMs ~/ 60000;
    final idleMin = bundle.totalIdleMs ~/ 60000;

    final rangeSwitch = SegmentedButton<StatsRange>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: StatsRange.week, label: Text('本周')),
        ButtonSegment(value: StatsRange.month, label: Text('本月')),
        ButtonSegment(value: StatsRange.year, label: Text('本年')),
      ],
      selected: {_range},
      onSelectionChanged: (s) => setState(() {
        _range = s.first;
        _future = _load();
      }),
    );

    final bigNumber = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_rangeLabels[_range]}码字字数',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          _fmtInt(bundle.totalChars),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface,
          ),
        ),
      ],
    );

    // 平均时速 = 区间总字数 / 区间总时长（小时），不足 1 字/时显示占位。
    final hours = bundle.totalDurationMs / 3600000.0;
    final avgSpeed = hours >= 1 / 60 ? bundle.totalChars / hours : 0.0;
    final stats = [
      _smallStat(context, '码字时长', '$durationMin 分钟'),
      _smallStat(
        context,
        '平均时速',
        '${avgSpeed >= 1 ? _fmtInt(avgSpeed.round()) : '—'} 字/时',
      ),
      _smallStat(
        context,
        '摸鱼时长',
        '$idleMin 分钟',
        info: '距最后一次键入超过 3 分钟记为摸鱼，\n恢复键入后该段计入摸鱼时长；\n应用失焦期间不计入。',
      ),
      _smallStat(context, '摸鱼次数', '${bundle.totalIdleCount} 次'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // 与左侧今日目标卡片同为两端对齐，保证底部指标行水平对齐。
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '区间汇总',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                rangeSwitch,
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 10,
              children: [bigNumber, ...stats],
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallStat(
    BuildContext context,
    String label,
    String value, {
    String? info,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            if (info != null) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: info,
                triggerMode: TooltipTriggerMode.tap,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.help_outline,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 今日目标：进度条 + 大号今日字数 + 时速，纵向填满卡片高度。
  Widget _todayCard(BuildContext context, SettingsController settings) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: FutureBuilder<WriteRecord>(
          future: context.read<AppState>().stats.today(),
          builder: (ctx, snap) {
            final today = snap.data;
            final todayChars = today?.chars ?? 0;
            final todayMin = (today?.durationMs ?? 0) / 60000.0;
            final speed = todayMin >= 1 ? todayChars / (todayMin / 60) : 0.0;
            final progress = (todayChars / settings.dailyGoal).clamp(0.0, 1.0);
            final reached = progress >= 1.0;

            final header = Text(
              '今日目标',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            );
            final bar = TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            );
            final bigNumber = Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtInt(todayChars),
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: reached ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '/ ${_fmtInt(settings.dailyGoal)} 字',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final footer = reached
                ? const _CelebrateRow()
                : Row(
                    children: [
                      Text(
                        '还差 ${((1 - progress) * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        '今日时速 ${speed >= 1 ? '${_fmtInt(speed.round())} 字/时' : '—'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );

            // 纵向布局：目标标签、大字进度、进度条、补充信息，各数据仅出现一次。
            // 固定间距排布，与右侧区间汇总底部指标行保持水平对齐。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 10),
                bigNumber,
                const SizedBox(height: 16),
                bar,
                const SizedBox(height: 16),
                footer,
              ],
            );
          },
        ),
      ),
    );
  }

  /// 码字日历：收益日历风格，日 / 月 / 年三档维度，切换按钮位于日历上方。
  Widget _calendarCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modeSwitch = SegmentedButton<_CalMode>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: _CalMode.day, label: Text('日')),
        ButtonSegment(value: _CalMode.month, label: Text('月')),
        ButtonSegment(value: _CalMode.year, label: Text('年')),
      ],
      selected: {_calMode},
      onSelectionChanged: (s) => setState(() {
        _calMode = s.first;
        // 进入月视图需要该整年数据，进入年视图需要窗口数据。
        if (_calMode == _CalMode.month) _calYearFuture = _loadCalYear();
        if (_calMode == _CalMode.year) _yearFuture = _loadYear();
      }),
    );

    final title = switch (_calMode) {
      _CalMode.day => '${_calendarMonth.year}年${_calendarMonth.month}月',
      _CalMode.month => '${_calendarMonth.year}年',
      _CalMode.year =>
        '${_yearWindowEnd - _yearWindowSize + 1}-$_yearWindowEnd年',
    };

    // 禁止翻到未来：各模式分别计算右箭头可用性。
    final now = DateTime.now();
    final canGoNext = switch (_calMode) {
      _CalMode.day => _calendarMonth.isBefore(DateTime(now.year, now.month, 1)),
      _CalMode.month => _calendarMonth.year < now.year,
      _CalMode.year => _yearWindowEnd < now.year,
    };

    return Card(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: box.maxHeight.isFinite ? box.maxHeight : 0,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部：卡片标题居左、维度切换靠右；下方为翻页行（居中年月）。
                      Row(
                        children: [
                          Text(
                            '码字日历',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          modeSwitch,
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: switch (_calMode) {
                                _CalMode.day => '上一月',
                                _CalMode.month => '上一年',
                                _CalMode.year => '往前五年',
                              },
                              icon: const Icon(Icons.chevron_left, size: 20),
                              onPressed: () => setState(() {
                                switch (_calMode) {
                                  case _CalMode.day:
                                    _calendarMonth = DateTime(
                                      _calendarMonth.year,
                                      _calendarMonth.month - 1,
                                      1,
                                    );
                                    _monthFuture = _loadMonth();
                                  case _CalMode.month:
                                    _calendarMonth = DateTime(
                                      _calendarMonth.year - 1,
                                      1,
                                      1,
                                    );
                                    _calYearFuture = _loadCalYear();
                                  case _CalMode.year:
                                    _yearWindowEnd -= _yearWindowSize;
                                    _yearFuture = _loadYear();
                                }
                              }),
                            ),
                            Expanded(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              tooltip: switch (_calMode) {
                                _CalMode.day => '下一月',
                                _CalMode.month => '下一年',
                                _CalMode.year => '往后五年',
                              },
                              icon: const Icon(Icons.chevron_right, size: 20),
                              onPressed: canGoNext
                                  ? () => setState(() {
                                      switch (_calMode) {
                                        case _CalMode.day:
                                          _calendarMonth = DateTime(
                                            _calendarMonth.year,
                                            _calendarMonth.month + 1,
                                            1,
                                          );
                                          _monthFuture = _loadMonth();
                                        case _CalMode.month:
                                          _calendarMonth = DateTime(
                                            _calendarMonth.year + 1,
                                            1,
                                            1,
                                          );
                                          _calYearFuture = _loadCalYear();
                                        case _CalMode.year:
                                          _yearWindowEnd += _yearWindowSize;
                                          _yearFuture = _loadYear();
                                      }
                                    })
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<List<WriteRecord>>(
                        // 热重载不重跑 initState，旧 State 中该字段为 null，构建时就地补载。
                        future: switch (_calMode) {
                          _CalMode.day => _monthFuture ??= _loadMonth(),
                          _CalMode.month => _calYearFuture ??= _loadCalYear(),
                          _CalMode.year => _yearFuture ??= _loadYear(),
                        },
                        builder: (ctx, snap) {
                          final records = snap.data ?? const <WriteRecord>[];

                          final Widget body;
                          switch (_calMode) {
                            case _CalMode.day:
                              body = _MonthGrid(
                                month: _calendarMonth,
                                recordsByDay: {
                                  for (final r in records) r.date.day: r,
                                },
                              );
                            case _CalMode.month:
                              // 按月聚合：总字数、码字天数。
                              final byMonth = List.generate(
                                12,
                                (_) => (chars: 0, days: 0),
                              );
                              for (final r in records.where(
                                (r) => r.date.year == _calendarMonth.year,
                              )) {
                                final m = byMonth[r.date.month - 1];
                                byMonth[r.date.month - 1] = (
                                  chars: m.chars + r.chars,
                                  days: m.days + (r.chars > 0 ? 1 : 0),
                                );
                              }
                              body = _MonthsGrid(
                                year: _calendarMonth.year,
                                months: byMonth,
                                onPickMonth: (m) => setState(() {
                                  _calendarMonth = DateTime(
                                    _calendarMonth.year,
                                    m,
                                    1,
                                  );
                                  _calMode = _CalMode.day;
                                  _monthFuture = _loadMonth();
                                }),
                              );
                            case _CalMode.year:
                              // 按年聚合窗口内各年：总字数、码字天数。
                              final byYear = <int, ({int chars, int days})>{};
                              for (final r in records) {
                                final y =
                                    byYear[r.date.year] ?? (chars: 0, days: 0);
                                byYear[r.date.year] = (
                                  chars: y.chars + r.chars,
                                  days: y.days + (r.chars > 0 ? 1 : 0),
                                );
                              }
                              final years = [
                                for (
                                  var y = _yearWindowEnd - _yearWindowSize + 1;
                                  y <= _yearWindowEnd;
                                  y++
                                )
                                  (
                                    year: y,
                                    data: byYear[y] ?? (chars: 0, days: 0),
                                  ),
                              ];
                              body = _YearsGrid(
                                years: years,
                                onPickYear: (y) => setState(() {
                                  _calendarMonth = DateTime(y, 1, 1);
                                  _calMode = _CalMode.month;
                                  _calYearFuture = _loadCalYear();
                                }),
                              );
                          }

                          return body;
                        },
                      ),
                    ],
                  ),
                  // 图例行贴底：与正文一起撑满卡片高度，正文变矮时仍固定在底部。
                  FutureBuilder<List<WriteRecord>>(
                    future: switch (_calMode) {
                      _CalMode.day => _monthFuture ??= _loadMonth(),
                      _CalMode.month => _calYearFuture ??= _loadCalYear(),
                      _CalMode.year => _yearFuture ??= _loadYear(),
                    },
                    builder: (ctx, snap) {
                      final records = snap.data ?? const <WriteRecord>[];
                      final totalChars = records.fold<int>(
                        0,
                        (sum, r) => sum + r.chars,
                      );
                      final writeDays = records
                          .where((r) => r.chars > 0)
                          .length;
                      final scopeLabel = switch (_calMode) {
                        _CalMode.day => '本月',
                        _CalMode.month => '${_calendarMonth.year}年',
                        _CalMode.year =>
                          '${_yearWindowEnd - _yearWindowSize + 1}-$_yearWindowEnd年',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                totalChars > 0
                                    ? '$scopeLabel合计 ${_fmtInt(totalChars)} 字 · 码字 $writeDays 天'
                                    : '$scopeLabel还没有码字记录，从今天开始吧',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '少',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                            ),
                            const SizedBox(width: 5),
                            for (var level = 1; level <= 4; level++) ...[
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withAlpha(
                                    _MonthGrid._heatAlphas[level],
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '多',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 趋势卡：近 30 天按日折线，tab 切换字数 / 时长 / 时速。
  /// [height] 为 null 时图表区域以 Expanded 填满父级剩余高度。
  Widget _chartCard(
    BuildContext context,
    _StatsBundle bundle, {
    double? height,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - 29);
    const daysInRange = 30;
    final chart = FutureBuilder<List<WriteRecord>>(
      // 热重载不重跑 initState，旧 State 中该字段为 null，构建时就地补载。
      future: _trendFuture ??= _loadTrend(),
      builder: (ctx, snap) {
        final records = snap.data ?? const <WriteRecord>[];
        // 补零成连续 30 天序列。
        final chars = List.filled(daysInRange, 0);
        final minutes = List.filled(daysInRange, 0.0);
        for (final r in records) {
          final idx = DateTime(
            r.date.year,
            r.date.month,
            r.date.day,
          ).difference(start).inDays;
          if (idx >= 0 && idx < daysInRange) {
            chars[idx] += r.chars;
            minutes[idx] += r.durationMs / 60000.0;
          }
        }
        final List<double> values;
        switch (_trendMetric) {
          case _TrendMetric.chars:
            values = chars.map((v) => v.toDouble()).toList();
          case _TrendMetric.minutes:
            values = minutes;
          case _TrendMetric.speed:
            values = [
              for (var i = 0; i < daysInRange; i++)
                minutes[i] >= 1 ? chars[i] / (minutes[i] / 60) : 0.0,
            ];
        }
        final unit = switch (_trendMetric) {
          _TrendMetric.chars => '字',
          _TrendMetric.minutes => '分钟',
          _TrendMetric.speed => '字/时',
        };
        final maxV = values.reduce(math.max);
        final yInterval = _niceInterval(maxV / 3);
        final body = snap.connectionState == ConnectionState.waiting
            ? const SizedBox.shrink()
            : values.every((v) => v == 0)
            ? Center(
                child: Text(
                  '暂无数据',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxV * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: scheme.outlineVariant.withAlpha(90),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: yInterval,
                        getTitlesWidget: (v, meta) {
                          // 跳过 fl_chart 在轴末端额外生成的边界标签，避免与前一刻度重叠。
                          final rem = v % yInterval;
                          if (rem > 0.001 && rem < yInterval - 0.001) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _fmtAxis(v, yInterval),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 7,
                        getTitlesWidget: (v, meta) {
                          // 首尾标签固定展示，中间按 7 天间隔展示。
                          final isStart = v <= 0.001;
                          final isEnd = (meta.max - v).abs() <= 0.001;
                          if (!isStart && !isEnd) {
                            final rem = v % 7;
                            final isMultiple = rem <= 0.001 || rem >= 6.999;
                            final tooCloseToEnd = (meta.max - v) < 3.5;
                            if (!isMultiple || tooCloseToEnd) {
                              return const SizedBox.shrink();
                            }
                          }
                          final d = start.add(Duration(days: v.toInt()));
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${d.month}/${d.day}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < values.length; i++)
                          FlSpot(i.toDouble(), values[i]),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.25,
                      preventCurveOverShooting: true,
                      barWidth: 2.5,
                      color: scheme.primary,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.primary.withAlpha(60),
                            scheme.primary.withAlpha(0),
                          ],
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => scheme.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(8),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      getTooltipItems: (spots) => spots
                          .map(
                            (s) => LineTooltipItem(
                              '${start.add(Duration(days: s.x.toInt())).month}/${start.add(Duration(days: s.x.toInt())).day}  ${_fmtAxis(s.y, 1)} $unit',
                              TextStyle(
                                color: scheme.onInverseSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
        return body;
      },
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '近 30 天趋势',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SegmentedButton<_TrendMetric>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: _TrendMetric.chars, label: Text('字数')),
                    ButtonSegment(
                      value: _TrendMetric.minutes,
                      label: Text('时长'),
                    ),
                    ButtonSegment(value: _TrendMetric.speed, label: Text('时速')),
                  ],
                  selected: {_trendMetric},
                  onSelectionChanged: (s) =>
                      setState(() => _trendMetric = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (height != null)
              SizedBox(height: height, width: double.infinity, child: chart)
            else
              Expanded(child: chart),
          ],
        ),
      ),
    );
  }

  /// 取 1/2/5×10^n 的整洁刻度间隔。
  static double _niceInterval(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final nice = f <= 1
        ? 1
        : f <= 2
        ? 2
        : f <= 5
        ? 5
        : 10;
    return nice * mag;
  }

  /// 轴刻度文本：整数直接显示，大数 k/万 缩写。
  static String _fmtAxis(double v, double interval) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    if (v >= 1000) {
      return interval >= 1000
          ? '${(v / 1000).toStringAsFixed(0)}k'
          : v.toStringAsFixed(0);
    }
    return interval < 1 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
  }
}

/// 一次周期加载的聚合结果。
class _StatsBundle {
  _StatsBundle(this.records) {
    for (final r in records) {
      totalChars += r.chars;
      totalDurationMs += r.durationMs;
      totalIdleMs += r.idleMs;
      totalIdleCount += r.idleCount;
    }
    if (records.isNotEmpty) {
      final first = records.first.date;
      final last = records.last.date;
      final days =
          last.difference(DateTime(first.year, first.month, first.day)).inDays +
          1;
      charsByDayOfRange = List.filled(days, 0);
      for (final r in records) {
        final idx = DateTime(
          r.date.year,
          r.date.month,
          r.date.day,
        ).difference(DateTime(first.year, first.month, first.day)).inDays;
        if (idx >= 0 && idx < days) charsByDayOfRange[idx] += r.chars;
      }
    }
  }

  final List<WriteRecord> records;
  int totalChars = 0;
  int totalDurationMs = 0;
  int totalIdleMs = 0;
  int totalIdleCount = 0;
  List<int> charsByDayOfRange = const [];
}

/// 星期短标签（周一起）。
const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 千分位整数格式。
String _fmtInt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final rest = s.length - 1 - i;
    if (rest > 0 && rest % 3 == 0) buf.write(',');
  }
  return buf.toString();
}

/// 月历（收益日历式）：格子为"日期 + 数字"上下居中两行，数字按字数档位着色，
/// 底色极淡分档，今日主色描边，悬浮展示当日详情。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.recordsByDay});

  final DateTime month;
  final Map<int, WriteRecord> recordsByDay;

  static const _cellHeight = 80.0;

  // 数字着色与底色分档：底色极淡，信息靠数字颜色深浅。
  static const _heatAlphas = [0, 20, 40, 65, 95];
  static const _numAlphas = [0, 150, 190, 225, 255];

  static int _heatLevel(int chars) {
    if (chars >= 5000) return 4;
    if (chars >= 2000) return 3;
    if (chars >= 500) return 2;
    if (chars > 0) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final today = DateTime.now();

    final rows = <TableRow>[
      TableRow(
        children: [
          for (var i = 0; i < 7; i++)
            SizedBox(
              height: 26,
              child: Center(
                child: Text(
                  _weekLabels[i],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: scheme.onSurfaceVariant.withAlpha(
                      i >= 5 ? 110 : 255,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      for (
        var row = 0;
        row < ((firstWeekday - 1 + daysInMonth) / 7).ceil();
        row++
      )
        TableRow(
          children: [
            for (var col = 0; col < 7; col++)
              Builder(
                builder: (ctx) {
                  final index = row * 7 + col;
                  final day = index - (firstWeekday - 1) + 1;
                  if (day < 1 || day > daysInMonth) {
                    return const SizedBox(height: _cellHeight);
                  }
                  return _dayCell(context, day, today, weekend: col >= 5);
                },
              ),
          ],
        ),
    ];

    return Table(children: rows);
  }

  Widget _dayCell(
    BuildContext context,
    int day,
    DateTime today, {
    required bool weekend,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final record = recordsByDay[day];
    final chars = record?.chars ?? 0;
    final isToday =
        today.year == month.year &&
        today.month == month.month &&
        today.day == day;
    final level = _heatLevel(chars);
    final isFuture =
        isToday || DateTime(month.year, month.month, day).isAfter(today);

    final Widget content = Container(
      height: _cellHeight,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      // 统一透明描边占位，避免今日格边框导致内容尺寸跳动。
      decoration: BoxDecoration(
        color: level > 0
            ? scheme.primary.withAlpha(_heatAlphas[level])
            : scheme.surfaceContainerHighest.withAlpha(isFuture ? 25 : 55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? scheme.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: textTheme.bodySmall?.copyWith(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
              color: isToday
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withAlpha(weekend ? 110 : 170),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            chars > 0 ? _fmtInt(chars) : '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: scheme.primary.withAlpha(_numAlphas[level]),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    if (record == null || chars <= 0) return content;
    return Tooltip(
      decoration: const BoxDecoration(color: Colors.transparent),
      margin: const EdgeInsets.all(4),
      richMessage: WidgetSpan(
        child: _DayTip(
          date: DateTime(month.year, month.month, day),
          record: record,
        ),
      ),
      waitDuration: const Duration(milliseconds: 250),
      child: content,
    );
  }

  static String _fmtChars(int chars) {
    if (chars >= 10000) return '${(chars / 10000).toStringAsFixed(1)}万';
    return _fmtInt(chars);
  }
}

/// 年历：4×3 月份宫格，每格展示当月总字数与码字天数，
/// 底色按月产量相对全年峰值分档；点击进入对应月份。
class _MonthsGrid extends StatelessWidget {
  const _MonthsGrid({
    required this.year,
    required this.months,
    required this.onPickMonth,
  });

  final int year;
  final List<({int chars, int days})> months;
  final ValueChanged<int> onPickMonth;

  static const _cellHeight = 92.0;

  static int _levelFor(int chars, int maxChars) {
    if (chars <= 0 || maxChars <= 0) return 0;
    final ratio = chars / maxChars;
    if (ratio > 0.75) return 4;
    if (ratio > 0.5) return 3;
    if (ratio > 0.25) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final maxChars = months.fold<int>(0, (m, e) => math.max(m, e.chars));
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Row(
            children: [
              for (var col = 0; col < 4; col++)
                Expanded(
                  child: _MonthCard(
                    year: year,
                    month: row * 4 + col + 1,
                    data: months[row * 4 + col],
                    level: _levelFor(months[row * 4 + col].chars, maxChars),
                    onTap: () => onPickMonth(row * 4 + col + 1),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _MonthCard extends StatefulWidget {
  const _MonthCard({
    required this.year,
    required this.month,
    required this.data,
    required this.level,
    required this.onTap,
  });

  final int year;
  final int month;
  final ({int chars, int days}) data;
  final int level;
  final VoidCallback onTap;

  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final isCurrentYear = now.year == widget.year;
    final isCurrentMonth = isCurrentYear && now.month == widget.month;
    final hasChars = widget.data.chars > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: _MonthsGrid._cellHeight,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hasChars
                ? scheme.primary.withAlpha(_MonthGrid._heatAlphas[widget.level])
                : scheme.surfaceContainerHighest.withAlpha(55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover
                  ? scheme.primary
                  : isCurrentMonth
                  ? scheme.primary.withAlpha(120)
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${widget.month}月',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  fontWeight: isCurrentMonth
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: isCurrentMonth
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withAlpha(170),
                ),
              ),
              const SizedBox(height: 4),
              if (hasChars)
                Text(
                  _MonthGrid._fmtChars(widget.data.chars),
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary.withAlpha(
                      _MonthGrid._numAlphas[widget.level],
                    ),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else
                Text(
                  '暂无记录',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withAlpha(110),
                  ),
                ),
              if (hasChars) ...[
                const SizedBox(height: 2),
                Text(
                  '码字 ${widget.data.days} 天',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withAlpha(190),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 年视图：多年卡片网格（每行 3 张），卡片展示年度总字数与码字天数，
/// 底色按年产量相对窗口峰值分档；点击进入该年的月视图。
class _YearsGrid extends StatelessWidget {
  const _YearsGrid({required this.years, required this.onPickYear});

  final List<({int year, ({int chars, int days}) data})> years;
  final ValueChanged<int> onPickYear;

  @override
  Widget build(BuildContext context) {
    final maxChars = years.fold<int>(0, (m, e) => math.max(m, e.data.chars));
    return Column(
      children: [
        for (var row = 0; row < (years.length / 3).ceil(); row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                if (row * 3 + col < years.length)
                  Expanded(
                    child: _YearCard(
                      item: years[row * 3 + col],
                      level: _MonthsGrid._levelFor(
                        years[row * 3 + col].data.chars,
                        maxChars,
                      ),
                      onTap: () => onPickYear(years[row * 3 + col].year),
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}

class _YearCard extends StatefulWidget {
  const _YearCard({
    required this.item,
    required this.level,
    required this.onTap,
  });

  final ({int year, ({int chars, int days}) data}) item;
  final int level;
  final VoidCallback onTap;

  @override
  State<_YearCard> createState() => _YearCardState();
}

class _YearCardState extends State<_YearCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCurrentYear = DateTime.now().year == widget.item.year;
    final hasChars = widget.item.data.chars > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: _MonthsGrid._cellHeight,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hasChars
                ? scheme.primary.withAlpha(_MonthGrid._heatAlphas[widget.level])
                : scheme.surfaceContainerHighest.withAlpha(55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover
                  ? scheme.primary
                  : isCurrentYear
                  ? scheme.primary.withAlpha(120)
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${widget.item.year}年',
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  fontWeight: isCurrentYear ? FontWeight.w800 : FontWeight.w500,
                  color: isCurrentYear
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withAlpha(170),
                ),
              ),
              const SizedBox(height: 4),
              if (hasChars)
                Text(
                  _MonthGrid._fmtChars(widget.item.data.chars),
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary.withAlpha(
                      _MonthGrid._numAlphas[widget.level],
                    ),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else
                Text(
                  '暂无记录',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withAlpha(110),
                  ),
                ),
              if (hasChars) ...[
                const SizedBox(height: 2),
                Text(
                  '码字 ${widget.item.data.days} 天',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant.withAlpha(190),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 日历格悬浮详情：深色圆角卡，日期标题 + 字数/时长/时速对齐数据行。
/// 字体显式取自 textTheme，保证跟随全局字体设置。
class _DayTip extends StatelessWidget {
  const _DayTip({required this.date, required this.record});

  final DateTime date;
  final WriteRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final labelColor = scheme.onInverseSurface.withAlpha(150);
    final minutes = record.durationMs ~/ 60000;
    final speed = minutes >= 1 ? record.chars / (minutes / 60) : 0.0;
    final rows = [
      ('字数', '${_fmtInt(record.chars)} 字'),
      ('时长', '$minutes 分钟'),
      ('时速', speed >= 1 ? '${_fmtInt(speed.round())} 字/时' : '—'),
    ];

    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.month}月${date.day}日 · 周${_weekLabels[date.weekday - 1]}',
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onInverseSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 3),
            Row(
              children: [
                Text(
                  rows[i].$1,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: labelColor,
                  ),
                ),
                const Spacer(),
                Text(
                  rows[i].$2,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onInverseSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
          Icon(
            Icons.emoji_events,
            color: Theme.of(context).colorScheme.primary,
            size: 16,
          ),
          const SizedBox(width: 6),
          const Text('恭喜！今日码字目标已达成 🎉'),
        ],
      ),
    );
  }
}
