import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/settings_controller.dart';
import '../app_theme.dart';

/// 加载遮罩的显示内容。
@immutable
class BusyInfo {
  const BusyInfo({required this.title, this.detail, this.progress});

  final String title;
  final String? detail;

  /// 0..1 的确定进度；null 表示进度未知（无限转圈）。
  final double? progress;

  BusyInfo copyWith({String? title, String? detail, double? progress}) =>
      BusyInfo(
        title: title ?? this.title,
        detail: detail ?? this.detail,
        progress: progress ?? this.progress,
      );
}

/// 全局加载态；null 表示不显示。
///
/// 遮罩需盖住整个应用（含顶栏与左侧菜单），所以由 [BusyOverlayHost] 在根布局
/// 消费，而不是挂在发起操作的那个页面里。
final ValueNotifier<BusyInfo?> busyState = ValueNotifier<BusyInfo?>(null);

/// 显示前的最小等待：更快的操作压根不闪提示。
const Duration _revealDelay = Duration(milliseconds: 120);

/// 一旦显示后的最短停留，避免「闪一下就没」。
const Duration _minShow = Duration(milliseconds: 400);

/// 执行 [task] 并显示全局加载遮罩；[task] 用它的回调参数回报进度。
Future<T> runWithBusy<T>(
  String title,
  Future<T> Function(void Function(int done, int total) report) task,
) async {
  final stopwatch = Stopwatch()..start();
  var latest = BusyInfo(title: title);
  final reveal = Timer(_revealDelay, () => busyState.value = latest);

  void report(int done, int total) {
    final percent = total == 0 ? 100 : done * 100 ~/ total;
    // 按整数百分比节流，避免逐章重建遮罩。
    if (latest.progress != null && (latest.progress! * 100).floor() == percent) {
      return;
    }
    latest = latest.copyWith(
      detail: '$done / $total 章',
      progress: total == 0 ? null : done / total,
    );
    if (busyState.value != null) busyState.value = latest;
  }

  try {
    return await task(report);
  } finally {
    reveal.cancel();
    if (busyState.value != null) {
      final rest = _minShow - stopwatch.elapsed;
      if (rest > Duration.zero) await Future<void>.delayed(rest);
      busyState.value = null;
    }
  }
}

/// 全局加载遮罩宿主：包住应用内容，遮罩即覆盖其全部区域。
class BusyOverlayHost extends StatelessWidget {
  const BusyOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: ValueListenableBuilder<BusyInfo?>(
            valueListenable: busyState,
            builder: (context, info, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: info == null
                  ? const SizedBox.expand(key: ValueKey('busyIdle'))
                  : _BusyOverlay(key: const ValueKey('busy'), info: info),
            ),
          ),
        ),
      ],
    );
  }
}

/// 半透明 scrim + 主题色进度卡片；吸收点击，加载期间不允许误操作。
class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({super.key, required this.info});

  final BusyInfo info;

  @override
  Widget build(BuildContext context) {
    final spec = appThemeSpec(context.watch<SettingsController>().theme);
    final textTheme = Theme.of(context).textTheme;
    final isDark = spec.brightness == Brightness.dark;

    return AbsorbPointer(
      child: ColoredBox(
        color: isDark ? const Color(0x73000000) : const Color(0x2E000000),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            decoration: BoxDecoration(
              // 浮在遮罩上必须自持可读，故取不透明面板色。
              color: spec.surfaceOpaque,
              borderRadius: BorderRadius.circular(spec.cardRadius),
              border: Border.fromBorderSide(
                spec.borderWidth > 1
                    ? BorderSide(
                        color: spec.borderStrong, width: spec.borderWidth)
                    : BorderSide(color: spec.hairline),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      isDark ? const Color(0x66000000) : const Color(0x28000000),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: info.progress,
                    strokeWidth: 3,
                    // 轨道用主色淡染，比中性灰更贴合各主题。
                    backgroundColor: spec.primary.withValues(alpha: 0.16),
                    valueColor: AlwaysStoppedAnimation<Color>(spec.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  info.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // 从 textTheme 派生以保留界面字体设置。
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: spec.text,
                  ),
                ),
                if (info.detail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    info.detail!,
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: spec.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}