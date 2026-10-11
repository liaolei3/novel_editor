import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 目标达成庆祝：窗口中央播放烟花特效 + 居中祝贺文字，非交互，到时自动消失。
/// [messages] 为本次达成的目标文案，多项时逐行展示。
void showFireworks(
  BuildContext context,
  List<String> messages, {
  FireworksStyle style = FireworksStyle.starShower,
}) {
  if (messages.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _FireworksCoordinator.show(overlay, List<String>.of(messages), style);
}

/// 烟花特效风格。
enum FireworksStyle {
  classicBloom('经典礼花'),
  chrysanthemum('重瓣菊花'),
  willow('金色垂柳'),
  starShower('星闪'),
  ringBurst('双环'),
  palmTree('棕榈'),
  doubleBloom('子母弹');

  const FireworksStyle(this.label);

  final String label;
}

/// 可复用的烟花播放组件；[loop] 用于预览页循环播放。
class FireworksShow extends StatefulWidget {
  const FireworksShow({
    super.key,
    required this.style,
    this.messages = const <String>[],
    this.loop = false,
    this.onFinished,
  });

  final FireworksStyle style;
  final List<String> messages;
  final bool loop;
  final VoidCallback? onFinished;

  @override
  State<FireworksShow> createState() => _FireworksShowState();
}

class _FireworksShowState extends State<FireworksShow>
    with SingleTickerProviderStateMixin {
  late final _Effect _effect;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _effect = _buildEffect(widget.style, math.Random());
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _effect.totalMs.round()),
    );
    if (widget.loop) {
      _controller.repeat();
    } else {
      _controller.forward().whenComplete(() {
        if (mounted) widget.onFinished?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final hasText = widget.messages.isNotEmpty;
              final textOpacity = !hasText
                  ? 0.0
                  : t < 0.12
                      ? (t / 0.12)
                      : (t > 0.82
                          ? ((1 - t) / 0.18).clamp(0.0, 1.0)
                          : 1.0);
              final textScale = 0.9 + 0.1 * math.min(t / 0.18, 1.0);
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FireworksPainter(
                        t: t,
                        effect: _effect,
                        durationMs: _effect.totalMs,
                      ),
                    ),
                  ),
                  if (hasText)
                    Center(
                      child: Opacity(
                        opacity: textOpacity,
                        child: Transform.scale(
                          scale: textScale,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final m in widget.messages)
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: _CelebrationText(m),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 祝贺文字：烟花同款渐变配色，底部叠一层柔和暗影保证浅色背景可读。
class _CelebrationText extends StatelessWidget {
  const _CelebrationText(this.text);

  final String text;

  static const LinearGradient _gradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFFFB021),
      Color(0xFFFF6FA5),
      Color(0xFF35C8E0),
      Color(0xFF9B6BFF),
    ],
  );

  static const TextStyle _base = TextStyle(
    fontSize: 30,
    height: 1.4,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.0,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 暗影层：浅色背景下压出轮廓
        Text(
          text,
          textAlign: TextAlign.center,
          style: _base.copyWith(
            color: Colors.transparent,
            shadows: const [Shadow(color: Color(0x40000000), blurRadius: 4)],
          ),
        ),
        // 渐变彩色层
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => _gradient.createShader(rect),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _base.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _FireworksCoordinator {
  static OverlayEntry? _entry;
  static final List<_Queued> _queue = [];

  static void show(OverlayState overlay, List<String> messages, FireworksStyle style) {
    if (_entry != null) {
      _queue.add(_Queued(messages, style));
      return;
    }
    _present(overlay, messages, style);
  }

  static void _present(OverlayState overlay, List<String> messages, FireworksStyle style) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => FireworksShow(
        style: style,
        messages: messages,
        onFinished: () {
          entry.remove();
          if (_entry == entry) _entry = null;
          if (_queue.isEmpty) return;
          final next = _queue.removeAt(0);
          if (overlay.mounted) {
            _present(overlay, next.messages, next.style);
          } else {
            _queue.clear();
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _Queued {
  _Queued(this.messages, this.style);
  final List<String> messages;
  final FireworksStyle style;
}

// ─────────────────────────── 粒子模型 ───────────────────────────

/// 单颗粒子，位置由时间闭式解出（原点 + 空气阻力位移 + 重力）。
class _Particle {
  _Particle({
    required this.ox,
    required this.oy,
    required this.angle,
    required this.speed,
    required this.drag,
    required this.gravity,
    required this.startMs,
    required this.lifeMs,
    required this.sizeFactor,
    required this.color,
    required this.trailSec,
    this.twinkleAmp = 0,
    this.twinkleFreq = 0,
    this.twinklePhase = 0,
    this.hot = false,
  });

  final double ox;
  final double oy;
  final double angle;
  final double speed;
  final double drag;
  final double gravity;
  final double startMs;
  final double lifeMs;
  final double sizeFactor;
  final Color color;
  final double trailSec;
  final double twinkleAmp;
  final double twinkleFreq;
  final double twinklePhase;
  final bool hot;

  double get endMs => startMs + lifeMs;
}

/// 升空火箭（轨迹 + 亮点），抵达顶点后由其位置爆发。
class _Rocket {
  _Rocket({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.startMs,
    required this.riseMs,
    required this.color,
  });

  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double startMs;
  final double riseMs;
  final Color color;
}

class _Effect {
  _Effect(this.rockets, this.particles, this.totalMs, {this.darkHalo = false});

  final List<_Rocket> rockets;
  final List<_Particle> particles;
  final double totalMs;

  /// 浅色背景下为每颗火花补一层柔和暗晕，提升对比度。
  final bool darkHalo;
}

// ─────────────────────────── 配色 ───────────────────────────

const Color _gold = Color(0xFFFFD24A);
const Color _warmWhite = Color(0xFFFFF3D0);
const Color _red = Color(0xFFFF6A5C);
const Color _cyan = Color(0xFF59E1F0);
const Color _purple = Color(0xFFA879FF);
const Color _pink = Color(0xFFFF8FC7);
const Color _green = Color(0xFF7CF07C);
const Color _blueWhite = Color(0xFFDCEBFF);

// ─────────────────────────── 特效构建 ───────────────────────────

double _easeOutQuad(double u) => 1 - (1 - u) * (1 - u);

_Effect _buildEffect(FireworksStyle style, math.Random rnd) {
  switch (style) {
    case FireworksStyle.classicBloom:
      return _classicBloom(rnd);
    case FireworksStyle.chrysanthemum:
      return _chrysanthemum(rnd);
    case FireworksStyle.willow:
      return _willow(rnd);
    case FireworksStyle.starShower:
      return _starShower(rnd);
    case FireworksStyle.ringBurst:
      return _ringBurst(rnd);
    case FireworksStyle.palmTree:
      return _palmTree(rnd);
    case FireworksStyle.doubleBloom:
      return _doubleBloom(rnd);
  }
}

/// 向四周均匀撒粒子。
List<_Particle> _disc({
  required double ox,
  required double oy,
  required double startMs,
  required int count,
  required double speedMin,
  required double speedMax,
  required double lifeMs,
  required double drag,
  required double gravity,
  required List<Color> colors,
  required math.Random rnd,
  double jitter = 0.06,
  double sizeFactor = 0.0022,
  double trailSec = 0.06,
  double twinkleAmp = 0,
  double twinkleFreq = 0,
  bool hot = false,
}) {
  final base = rnd.nextDouble() * 2 * math.pi;
  final list = <_Particle>[];
  for (var i = 0; i < count; i++) {
    final angle = base + (i / count) * 2 * math.pi + (rnd.nextDouble() - 0.5) * jitter;
    list.add(_Particle(
      ox: ox,
      oy: oy,
      angle: angle,
      speed: speedMin + rnd.nextDouble() * (speedMax - speedMin),
      drag: drag,
      gravity: gravity,
      startMs: startMs,
      lifeMs: lifeMs * (0.85 + rnd.nextDouble() * 0.3),
      sizeFactor: sizeFactor,
      color: colors[rnd.nextInt(colors.length)],
      trailSec: trailSec,
      twinkleAmp: twinkleAmp,
      twinkleFreq: twinkleFreq,
      twinklePhase: rnd.nextDouble() * 2 * math.pi,
      hot: hot,
    ));
  }
  return list;
}

_Effect _classicBloom(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const palette = [_gold, _cyan, _pink, _purple, _green];
  const shots = 4;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.28 + rnd.nextDouble() * 0.44;
    final y0 = 1.04;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.1;
    final y1 = 0.26 + rnd.nextDouble() * 0.22;
    final start = s * 620.0 + rnd.nextDouble() * 120;
    final rise = 520.0 + rnd.nextDouble() * 260;
    final color = palette[s % palette.length];
    rockets.add(_Rocket(
      x0: x0, y0: y0, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: color,
    ));
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: start + rise, count: 130,
      speedMin: 0.30, speedMax: 0.46, lifeMs: 1250,
      drag: 1.7, gravity: 0.20, colors: [color], rnd: rnd,
      hot: true, trailSec: 0.07,
    ));
  }
  return _finalize(rockets, particles, fallbackMs: 3600);
}

_Effect _chrysanthemum(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const pairs = [
    [_gold, _red],
    [_cyan, _blueWhite],
    [_pink, _purple],
  ];
  const shots = 3;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.32 + rnd.nextDouble() * 0.36;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.08;
    final y1 = 0.24 + rnd.nextDouble() * 0.18;
    final start = s * 720.0 + rnd.nextDouble() * 120;
    final rise = 560.0 + rnd.nextDouble() * 260;
    final pair = pairs[s % pairs.length];
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: pair[0],
    ));
    final burst = start + rise;
    // 外层大瓣
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 100,
      speedMin: 0.34, speedMax: 0.42, lifeMs: 1400,
      drag: 1.5, gravity: 0.22, colors: [pair[0]], rnd: rnd,
      hot: true,
    ));
    // 内层小瓣
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 70,
      speedMin: 0.16, speedMax: 0.24, lifeMs: 1100,
      drag: 1.8, gravity: 0.18, colors: [pair[1]], rnd: rnd,
    ));
  }
  return _finalize(rockets, particles, fallbackMs: 3800);
}

_Effect _willow(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const shots = 3;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.3 + rnd.nextDouble() * 0.4;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.08;
    final y1 = 0.2 + rnd.nextDouble() * 0.14;
    final start = s * 780.0;
    final rise = 560.0 + rnd.nextDouble() * 220;
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: _gold,
    ));
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: start + rise, count: 120,
      speedMin: 0.24, speedMax: 0.34, lifeMs: 2000,
      drag: 2.4, gravity: 0.55, colors: [_gold, _warmWhite], rnd: rnd,
      trailSec: 0.16, sizeFactor: 0.0019, hot: true,
    ));
  }
  return _finalize(rockets, particles, fallbackMs: 5200);
}

_Effect _starShower(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const shots = 6;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.24 + rnd.nextDouble() * 0.52;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.14;
    final y1 = 0.22 + rnd.nextDouble() * 0.26;
    final start = s * 520.0 + rnd.nextDouble() * 120;
    final rise = 480.0 + rnd.nextDouble() * 200;
    final rocketColor = [_cyan, _gold, _pink, _purple][s % 4];
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: rocketColor,
    ));
    final burst = start + rise;
    // 主瓣：饱和色，数量加密
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 150,
      speedMin: 0.24, speedMax: 0.46, lifeMs: 1600,
      drag: 1.9, gravity: 0.18,
      colors: [_cyan, _gold, _pink, _purple], rnd: rnd,
      twinkleAmp: 0.8, twinkleFreq: 6.0, trailSec: 0.05,
      sizeFactor: 0.0026, hot: true,
    ));
    // 内层缓速星点，更长闪烁
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst + 40, count: 90,
      speedMin: 0.1, speedMax: 0.24, lifeMs: 1400,
      drag: 2.2, gravity: 0.12,
      colors: [_gold, _cyan], rnd: rnd,
      twinkleAmp: 1.0, twinkleFreq: 9.0, sizeFactor: 0.0021,
    ));
    // 外层飞溅，快速远抛
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 70,
      speedMin: 0.44, speedMax: 0.62, lifeMs: 1100,
      drag: 1.6, gravity: 0.24,
      colors: [_gold, _pink, _cyan], rnd: rnd,
      twinkleAmp: 1.0, twinkleFreq: 12.0, sizeFactor: 0.0017,
      trailSec: 0.08,
    ));
  }
  return _finalize(rockets, particles, fallbackMs: 5600, darkHalo: true);
}

_Effect _ringBurst(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const pairs = [
    [_gold, _purple],
    [_cyan, _pink],
  ];
  const shots = 3;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.34 + rnd.nextDouble() * 0.32;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.06;
    final y1 = 0.28 + rnd.nextDouble() * 0.16;
    final start = s * 760.0;
    final rise = 560.0 + rnd.nextDouble() * 220;
    final pair = pairs[s % pairs.length];
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: pair[0],
    ));
    final burst = start + rise;
    // 速度几乎一致 → 清晰圆环
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 96,
      speedMin: 0.40, speedMax: 0.425, lifeMs: 1300,
      drag: 1.4, gravity: 0.12, colors: [pair[0]], rnd: rnd,
      jitter: 0.0, hot: true,
    ));
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 96,
      speedMin: 0.26, speedMax: 0.275, lifeMs: 1300,
      drag: 1.4, gravity: 0.12, colors: [pair[1]], rnd: rnd,
      jitter: 0.0,
    ));
  }
  return _finalize(rockets, particles, fallbackMs: 4400);
}

_Effect _palmTree(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const shots = 3;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.3 + rnd.nextDouble() * 0.4;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.08;
    final y1 = 0.22 + rnd.nextDouble() * 0.16;
    final start = s * 700.0;
    final rise = 540.0 + rnd.nextDouble() * 220;
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: _gold,
    ));
    final burst = start + rise;
    // 8 束粗壮枝干
    const arms = 8;
    final base = rnd.nextDouble() * 2 * math.pi;
    for (var a = 0; a < arms; a++) {
      final armAngle = base + (a / arms) * 2 * math.pi;
      particles.addAll(List<_Particle>.generate(16, (i) {
        return _Particle(
          ox: x1,
          oy: y1,
          angle: armAngle + (rnd.nextDouble() - 0.5) * 0.12,
          speed: 0.30 + rnd.nextDouble() * 0.08,
          drag: 1.8,
          gravity: 0.34,
          startMs: burst,
          lifeMs: 1500 * (0.85 + rnd.nextDouble() * 0.3),
          sizeFactor: 0.0026,
          color: rnd.nextBool() ? _gold : _warmWhite,
          trailSec: 0.12,
          hot: true,
        );
      }));
    }
  }
  return _finalize(rockets, particles, fallbackMs: 4600);
}

_Effect _doubleBloom(math.Random rnd) {
  final rockets = <_Rocket>[];
  final particles = <_Particle>[];
  const shots = 2;
  for (var s = 0; s < shots; s++) {
    final x0 = 0.32 + rnd.nextDouble() * 0.36;
    final x1 = x0 + (rnd.nextDouble() - 0.5) * 0.08;
    final y1 = 0.3 + rnd.nextDouble() * 0.16;
    final start = s * 900.0;
    final rise = 560.0 + rnd.nextDouble() * 220;
    final color = s == 0 ? _gold : _cyan;
    rockets.add(_Rocket(
      x0: x0, y0: 1.04, x1: x1, y1: y1,
      startMs: start, riseMs: rise, color: color,
    ));
    final burst = start + rise;
    particles.addAll(_disc(
      ox: x1, oy: y1, startMs: burst, count: 90,
      speedMin: 0.30, speedMax: 0.42, lifeMs: 1000,
      drag: 1.6, gravity: 0.2, colors: [color], rnd: rnd, hot: true,
    ));
    // 子母弹：主爆后延迟，在若干方位二次小爆
    const children = 6;
    final base = rnd.nextDouble() * 2 * math.pi;
    for (var c = 0; c < children; c++) {
      final a = base + (c / children) * 2 * math.pi;
      final r = 0.18 + rnd.nextDouble() * 0.06;
      final cx = x1 + math.cos(a) * r * 0.9;
      final cy = y1 + math.sin(a) * r * 0.6;
      particles.addAll(_disc(
        ox: cx, oy: cy, startMs: burst + 380 + rnd.nextDouble() * 140,
        count: 26, speedMin: 0.1, speedMax: 0.2, lifeMs: 900,
        drag: 2.0, gravity: 0.16,
        colors: [color, _warmWhite], rnd: rnd, sizeFactor: 0.0019,
        twinkleAmp: 0.5, twinkleFreq: 5.0,
      ));
    }
  }
  return _finalize(rockets, particles, fallbackMs: 4800);
}

_Effect _finalize(
  List<_Rocket> rockets,
  List<_Particle> particles, {
  required double fallbackMs,
  bool darkHalo = false,
}) {
  var maxMs = fallbackMs;
  for (final p in particles) {
    if (p.endMs > maxMs) maxMs = p.endMs;
  }
  // 末尾留一段空白，循环播放时更有呼吸感。
  return _Effect(rockets, particles, maxMs + 500, darkHalo: darkHalo);
}

// ─────────────────────────── 绘制 ───────────────────────────

class _FireworksPainter extends CustomPainter {
  _FireworksPainter({
    required this.t,
    required this.effect,
    required this.durationMs,
  });

  final double t;
  final _Effect effect;
  final double durationMs;

  Offset _pos(_Particle p, double dt, Size size, double minDim) {
    final k = p.drag;
    final dist = k > 0 ? p.speed * (1 - math.exp(-k * dt)) / k : p.speed * dt;
    final dx = math.cos(p.angle) * dist;
    final dy = math.sin(p.angle) * dist + 0.5 * p.gravity * dt * dt;
    return Offset(
      p.ox * size.width + dx * minDim,
      p.oy * size.height + dy * minDim,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final minDim = math.min(size.width, size.height);
    final nowMs = t * durationMs;

    // 火箭升空
    for (final r in effect.rockets) {
      final u = (nowMs - r.startMs) / r.riseMs;
      if (u < 0 || u >= 1) continue;
      final e = _easeOutQuad(u);
      final x = (r.x0 + (r.x1 - r.x0) * u) * size.width;
      final y = (r.y0 + (r.y1 - r.y0) * e) * size.height;
      final head = Offset(x, y);
      // 尾迹
      final tailY = y + 26 * (0.4 + 0.6 * (1 - u));
      final trail = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, minDim * 0.004)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [r.color.withValues(alpha: 0.55), r.color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTRB(x - 2, y, x + 2, tailY));
      canvas.drawLine(head, Offset(x, tailY), trail);
      canvas.drawCircle(head, math.max(1.6, minDim * 0.0035), Paint()..color = Colors.white);
      canvas.drawCircle(
        head,
        math.max(3.0, minDim * 0.008),
        Paint()..color = r.color.withValues(alpha: 0.35),
      );
    }

    // 火花粒子
    for (final p in effect.particles) {
      final dt = (nowMs - p.startMs) / 1000;
      if (dt < 0) continue;
      final prog = (nowMs - p.startMs) / p.lifeMs;
      if (prog >= 1) continue;

      var alpha = math.pow(1 - prog, 0.7).toDouble();
      if (p.twinkleAmp > 0) {
        final tw = 0.5 + 0.5 * math.sin(p.twinklePhase + p.twinkleFreq * dt * 2 * math.pi);
        alpha *= (1 - p.twinkleAmp) + p.twinkleAmp * tw;
      }
      if (alpha <= 0.02) continue;

      final pos = _pos(p, dt, size, minDim);
      final tailDt = math.max(0.0, dt - p.trailSec);
      final tailPos = _pos(p, tailDt, size, minDim);
      final radius = p.sizeFactor * minDim;

      // 拖尾
      canvas.drawLine(
        tailPos,
        pos,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = radius * 1.15
          ..color = p.color.withValues(alpha: alpha * 0.75),
      );
      // 浅色背景对比：柔和暗晕
      if (effect.darkHalo) {
        canvas.drawCircle(
          pos,
          radius * 2.1,
          Paint()..color = Colors.black.withValues(alpha: alpha * 0.13),
        );
      }
      // 外发光（饱和彩色，浅底更显眼）
      canvas.drawCircle(
        pos,
        radius * 2.8,
        Paint()..color = p.color.withValues(alpha: alpha * 0.26),
      );
      // 本色
      canvas.drawCircle(
        pos,
        radius,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
      // 高亮核心（偏色，避免浅底糊成白点）
      if (p.hot) {
        final core = Color.lerp(p.color, Colors.white, 0.55)!;
        canvas.drawCircle(
          pos,
          radius * 0.55,
          Paint()..color = core.withValues(alpha: alpha * 0.95),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) => oldDelegate.t != t;
}