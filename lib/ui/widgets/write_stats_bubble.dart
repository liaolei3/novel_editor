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
/// 气泡经 [OverlayPortal] 挂到当前路由所在的 Overlay 层（不拦截正文交互），
/// 因此层级低于后弹出的弹窗；点外部不关闭，也没有关闭按钮——收起只能靠再点一次入口。
class WriteStatsEntry extends StatefulWidget {
  const WriteStatsEntry({super.key});

  @override
  State<WriteStatsEntry> createState() => _WriteStatsEntryState();
}

class _WriteStatsEntryState extends State<WriteStatsEntry> {
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  Rect? _anchor;
  bool _hovering = false;

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
      setState(() {});
      return;
    }
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _anchor = box.localToGlobal(Offset.zero) & box.size;
    _portal.show();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = _portal.isShowing;
    return OverlayPortal(
      controller: _portal,
      // 撑满整层的 Stack：气泡仍用 Positioned 定位，且空白处不拦截点击。
      overlayChildBuilder: (_) =>
          Stack(children: [_WriteStatsBubble(anchor: _anchor ?? Rect.zero)]),
      child: MouseRegion(
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
  /// 默认尺寸（收起重开即恢复）与拖拽缩放上下限。
  static const Size _defaultSize = Size(299, 192);
  static const Size _minSize = Size(280, 190);
  static const Size _maxSize = Size(480, 360);

  static const double _gap = 10;

  /// 面板与窗口边缘的最小间距。
  static const double _edge = 8;

  /// 四边拖拽缩放的命中带宽度。
  static const double _borderZone = 6;

  /// 数值右对齐后，这个间距就是「数值右端 → 萌宠左端」的实际视觉距离。
  static const double _columnGap = 12;

  /// 萌宠列宽度：资源为 1:1，列宽固定，图片按 BoxFit.contain 缩放并垂直居中。
  static const double _figureWidth = 130;

  /// 当前面板矩形（窗口坐标），拖动与缩放共用；null 表示未交互，用默认矩形。
  Rect? _rect;

  StreamSubscription<int>? _sub;
  Timer? _debounce;
  Timer? _poll;

  int _chars = 0;
  int _durationMs = 0;

  /// 指标口径：0 今日 / 1 本章 / 2 全书。
  int _scope = 0;

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

  Rect get _initialRect => Rect.fromLTWH(
    widget.anchor.right - _defaultSize.width,
    widget.anchor.top - _gap - _defaultSize.height,
    _defaultSize.width,
    _defaultSize.height,
  );

  Rect _clampRect(Rect r, Size window) => Rect.fromLTWH(
    r.left.clamp(_edge, math.max(_edge, window.width - r.width - _edge)),
    r.top.clamp(_edge, math.max(_edge, window.height - r.height - _edge)),
    r.width,
    r.height,
  );

  /// 以「当前钳制位置 + 位移」推进，避免拖到边界后反向拖动出现死区。
  void _onPanUpdate(DragUpdateDetails details, Size window) {
    final cur = _rect ?? _clampRect(_initialRect, window);
    setState(() => _rect = _clampRect(cur.shift(details.delta), window));
  }

  /// 对边固定、拖动边随位移推进；增量钳制在尺寸上下限与窗口边界内。
  void _onResizeUpdate(
    _ResizeEdge edge,
    DragUpdateDetails details,
    Size window,
  ) {
    final cur = _rect ?? _clampRect(_initialRect, window);
    final (left0, top0, right0, bottom0) = (
      cur.left,
      cur.top,
      cur.right,
      cur.bottom,
    );
    var left = left0, top = top0, right = right0, bottom = bottom0;
    if (edge.hitsLeft) {
      left = (left + details.delta.dx).clamp(
        math.max(_edge, right0 - _maxSize.width),
        right0 - _minSize.width,
      );
    }
    if (edge.hitsRight) {
      right = (right + details.delta.dx).clamp(
        left0 + _minSize.width,
        math.min(window.width - _edge, left0 + _maxSize.width),
      );
    }
    if (edge.hitsTop) {
      top = (top + details.delta.dy).clamp(
        math.max(_edge, bottom0 - _maxSize.height),
        bottom0 - _minSize.height,
      );
    }
    if (edge.hitsBottom) {
      bottom = (bottom + details.delta.dy).clamp(
        top0 + _minSize.height,
        math.min(window.height - _edge, top0 + _maxSize.height),
      );
    }
    setState(() => _rect = Rect.fromLTRB(left, top, right, bottom));
  }

  /// 边缘/角落的缩放命中区：边为 6px 条带，四角为 12px 方块并盖在条带之上。
  Widget _resizeHandle(_ResizeEdge edge, Size window) {
    final handle = MouseRegion(
      cursor: edge.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) => _onResizeUpdate(edge, d, window),
      ),
    );
    const c = 12.0;
    return switch (edge) {
      _ResizeEdge.left => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: _borderZone,
        child: handle,
      ),
      _ResizeEdge.right => Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: _borderZone,
        child: handle,
      ),
      _ResizeEdge.top => Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: _borderZone,
        child: handle,
      ),
      _ResizeEdge.bottom => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        height: _borderZone,
        child: handle,
      ),
      _ResizeEdge.topLeft => Positioned(
        left: 0,
        top: 0,
        width: c,
        height: c,
        child: handle,
      ),
      _ResizeEdge.topRight => Positioned(
        right: 0,
        top: 0,
        width: c,
        height: c,
        child: handle,
      ),
      _ResizeEdge.bottomLeft => Positioned(
        left: 0,
        bottom: 0,
        width: c,
        height: c,
        child: handle,
      ),
      _ResizeEdge.bottomRight => Positioned(
        right: 0,
        bottom: 0,
        width: c,
        height: c,
        child: handle,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final window = MediaQuery.sizeOf(context);
    final settings = context.watch<SettingsController>();
    final app = context.watch<AppState>();
    final standee = settings.standee;

    // 各口径的目标与当前字数；时长/时速恒为今日数据（无按章/按书记录）。
    final (goal, chars) = switch (_scope) {
      1 => (app.resolvedChapterGoal, app.currentChapter?.charCount ?? 0),
      2 => (app.currentBook?.goal ?? 0, app.bookCharTotal),
      _ => (settings.dailyGoal, _chars),
    };
    final progress = goal > 0 ? (chars / goal).clamp(0.0, 1.0) : 0.0;
    final reached = goal > 0 && chars >= goal;
    final pos = _clampRect(_rect ?? _initialRect, window);

    return Positioned.fromRect(
      rect: pos,
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (d) => _onPanUpdate(d, window),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
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
                child: Column(
                  children: [
                    _segmented(scheme),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _metrics(
                              scheme,
                              goal,
                              chars,
                              progress,
                              reached,
                            ),
                          ),
                          const SizedBox(width: _columnGap),
                          _figure(standee),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _resizeHandle(_ResizeEdge.left, window),
          _resizeHandle(_ResizeEdge.right, window),
          _resizeHandle(_ResizeEdge.top, window),
          _resizeHandle(_ResizeEdge.bottom, window),
          _resizeHandle(_ResizeEdge.topLeft, window),
          _resizeHandle(_ResizeEdge.topRight, window),
          _resizeHandle(_ResizeEdge.bottomLeft, window),
          _resizeHandle(_ResizeEdge.bottomRight, window),
        ],
      ),
    );
  }

  /// 口径分段控件：今日 / 本章 / 全书。
  Widget _segmented(ColorScheme scheme) {
    const labels = ['今日', '本章', '全书'];
    return Container(
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _scope = i),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _scope == i ? scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: _scope == i
                          ? [
                              BoxShadow(
                                color: scheme.shadow.withValues(alpha: 0.12),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: _scope == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _scope == i
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 萌宠列：列宽固定，萌宠按 BoxFit.contain 缩放并垂直居中。
  /// 注意不能用 AspectRatio(1)：那会撑成与列等高的正方形，把面板顶宽。
  Widget _figure(PetStandee standee) {
    return SizedBox(
      width: _figureWidth,
      child: Image.asset(standee.assetPath, fit: BoxFit.contain),
    );
  }

  Widget _metrics(
    ColorScheme scheme,
    int goal,
    int chars,
    double progress,
    bool reached,
  ) {
    // 时速口径见 TextStats.speedPerHour（不足 1 小时按 1 小时算）。
    final speed = TextStats.speedPerHour(_chars, _durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // 行距交给 spaceBetween 均分，不写死间距：行高总和小于内容高时不会溢出，
      // 面板改高度也只需改一个常量（当前 5 行 ×25，余下均分）。
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _metricRow(scheme, Icons.track_changes, '目标', '${_fmtInt(goal)} 字'),
        _metricRow(
          scheme,
          Icons.edit_outlined,
          '码字',
          '${_fmtInt(chars)} 字',
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

/// 缩放命中的边或角。
enum _ResizeEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get hitsLeft => this == left || this == topLeft || this == bottomLeft;
  bool get hitsRight =>
      this == right || this == topRight || this == bottomRight;
  bool get hitsTop => this == top || this == topLeft || this == topRight;
  bool get hitsBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;

  MouseCursor get cursor => switch (this) {
    left || right => SystemMouseCursors.resizeLeftRight,
    top || bottom => SystemMouseCursors.resizeUpDown,
    topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
  };
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
