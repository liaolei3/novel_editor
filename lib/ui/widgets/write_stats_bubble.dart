import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/text_stats.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';

/// 编辑器底部状态栏右侧的码字面板入口：一个文字按钮，
/// 点击在状态栏上方弹出非模态气泡，再点一次收起。
///
/// 气泡挂在根 Overlay 上（不拦截正文交互），点外部不关闭，也没有关闭按钮——
/// 收起只能靠再点一次入口。
class WriteStatsEntry extends StatefulWidget {
  const WriteStatsEntry({super.key});

  @override
  State<WriteStatsEntry> createState() => _WriteStatsEntryState();
}

class _WriteStatsEntryState extends State<WriteStatsEntry> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  bool _hovering = false;

  @override
  void dispose() {
    _removeBubble();
    super.dispose();
  }

  void _removeBubble() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      setState(_removeBubble);
      return;
    }
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box == null || !box.hasSize || overlay == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _WriteStatsBubble(anchor: anchor));
    _entry = entry;
    overlay.insert(entry);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _entry != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: open ? '收起码字面板' : '展开码字面板',
        child: GestureDetector(
          onTap: _toggle,
          child: Container(
            key: _anchorKey,
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 展开与 hover 共用同一底色，展开时图标转主题色。
              color: _hovering || open
                  ? scheme.primaryContainer.withValues(alpha: 0.45)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            // 与书架主页「码字统计」导航用同一图标；只剩图标后含义不自明，靠 tooltip 说明用途。
            child: Icon(
              Icons.insights,
              size: 15,
              color: open ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 非模态悬浮气泡：萌宠 + 今日码字指标。
class _WriteStatsBubble extends StatefulWidget {
  const _WriteStatsBubble({required this.anchor});

  /// 头像按钮在窗口坐标系中的矩形，气泡锚定其上方并右对齐。
  final Rect anchor;

  @override
  State<_WriteStatsBubble> createState() => _WriteStatsBubbleState();
}

class _WriteStatsBubbleState extends State<_WriteStatsBubble> {
  /// 宽度按最长数值反算：数值可用宽 = 299 - 12*2 - 1 - _columnGap - _figureWidth
  /// = 132px，足够「12,345 字/时」「10 小时 30 分」不被省略号截断。
  static const double _width = 299;

  /// 高度按内容反算：描边 Border.all(0.5) 会额外吃掉 0.5px/边，
  /// 故内容高 = 178 - 12*2 - 1 = 153。
  static const double _height = 178;
  static const double _gap = 10;
  static const double _edge = 8;

  /// 数值右对齐后，这个间距就是「数值右端 → 萌宠左端」的实际视觉距离。
  static const double _columnGap = 12;

  /// 萌宠列宽度：资源为 1:1，列高 153，取 130 让萌宠比列高略窄并垂直居中，
  /// 左右更紧凑且不过度留白。
  static const double _figureWidth = 130;

  /// 相对基准位置的拖动量（写入前已按窗口边界钳制）。
  Offset _drag = Offset.zero;

  StreamSubscription<int>? _sub;
  Timer? _debounce;
  Timer? _poll;

  int _chars = 0;
  int _durationMs = 0;

  /// 缓存 AppState：dispose 期间禁止通过 context 查找祖先节点。
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _sub = _app.session.changes.listen((_) => _scheduleRefresh());
    // 时长每分钟由 SessionStats 落库但不发 changes 流，30 秒兜底刷新一次。
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _refresh);
  }

  Future<void> _refresh() async {
    final rec = await _app.stats.today();
    if (!mounted) return;
    setState(() {
      _chars = rec.chars;
      _durationMs = rec.durationMs;
    });
  }

  Offset get _base => Offset(
        widget.anchor.right - _width,
        widget.anchor.top - _height - _gap,
      );

  Offset _clampToWindow(Offset raw, Size window) => Offset(
        raw.dx.clamp(_edge, math.max(_edge, window.width - _width - _edge)),
        raw.dy.clamp(_edge, math.max(_edge, window.height - _height - _edge)),
      );

  /// 以「当前钳制位置 + 位移」推进，避免拖到边界后反向拖动出现死区。
  void _onPanUpdate(DragUpdateDetails details, Size window) {
    final next = _clampToWindow(_base + _drag + details.delta, window);
    setState(() => _drag = next - _base);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final window = MediaQuery.sizeOf(context);
    final goal = context.watch<SettingsController>().dailyGoal;
    final standee = context.watch<SettingsController>().standee;
    final progress = goal > 0 ? (_chars / goal).clamp(0.0, 1.0) : 0.0;
    final reached = progress >= 1;
    final pos = _clampToWindow(_base + _drag, window);

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => _onPanUpdate(d, window),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _metrics(scheme, goal, progress, reached),
                ),
                const SizedBox(width: _columnGap),
                _figure(standee),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 萌宠列：列宽固定，萌宠按 BoxFit.contain 缩放并垂直居中。
  /// 注意不能用 AspectRatio(1)：那会撑成与列等高的正方形，把面板顶宽。
  Widget _figure(PetStandee standee) {
    return SizedBox(
      width: _figureWidth,
      child: Image.asset(
        standee.assetPath,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _metrics(
    ColorScheme scheme,
    int goal,
    double progress,
    bool reached,
  ) {
    // 时速口径见 TextStats.speedPerHour（不足 1 小时按 1 小时算）。
    final speed = TextStats.speedPerHour(_chars, _durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // 行距交给 spaceBetween 均分，不写死间距：行高总和小于内容高时不会溢出，
      // 面板改高度也只需改一个常量（当前 5 行 ×25，余下 28px 均分成 4 个 7px）。
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _metricRow(
          scheme,
          Icons.track_changes,
          '目标',
          '${_fmtInt(goal)} 字',
        ),
        _metricRow(
          scheme,
          Icons.edit_outlined,
          '码字',
          '${_fmtInt(_chars)} 字',
          highlight: reached,
        ),
        _metricRow(
          scheme,
          Icons.trending_up,
          '进度',
          '${(progress * 100).round()}%',
          highlight: reached,
        ),
        _metricRow(scheme, Icons.schedule, '时长', _fmtDuration(_durationMs)),
        _metricRow(
          scheme,
          Icons.speed,
          '时速',
          speed >= 1 ? '${_fmtInt(speed.round())} 字/时' : '—',
        ),
      ],
    );
  }

  /// 紧凑指标行：图标 + 标签靠左、数值右对齐贴住立绘列，
  /// 中间空白集中在标签与数值之间，两列看起来更近。
  Widget _metricRow(
    ColorScheme scheme,
    IconData icon,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return SizedBox(
      height: 25,
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: _labelStyle(scheme)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: highlight ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _labelStyle(ColorScheme scheme) =>
      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
}

/// 千分位整数格式（与统计页口径一致）。
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

String _fmtDuration(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 1) return '不足 1 分钟';
  if (minutes < 60) return '$minutes 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h 小时' : '$h 小时 $m 分';
}