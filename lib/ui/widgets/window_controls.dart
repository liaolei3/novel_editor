import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../state/app_state.dart';
import 'app_icon.dart';

bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;

Future<void> _toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// 窗口关闭收尾：冲刷保存等 shutdown 后再销毁窗口；在 main 中全局注册一次。
class AppCloseHandler with WindowListener {
  AppCloseHandler(this._state);

  final AppState _state;

  @override
  void onWindowClose() {
    // 事件回调签名为 void，不能 await；此处自行异步处理。
    _handleClose();
  }

  Future<void> _handleClose() async {
    // 收尾有 3 秒上限：任何保存/数据库/文件操作异常或挂起都不能阻塞窗口关闭。
    try {
      await _state.shutdown().timeout(const Duration(seconds: 3));
    } catch (_) {
      // 忽略收尾失败，保证窗口一定能关闭。
    }
    // 数据已由 shutdown() 落盘，直接强制退出进程：
    exit(0);
  }
}

/// 窗口控制按钮（最小化/最大化还原/关闭），仅 Windows 桌面端渲染。
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } catch (_) {
      // 平台通道不可用（如测试环境）时保持默认。
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    if (!_isWindowsDesktop) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        icon: const AppIcon(Icons.horizontal_rule),
        onPressed: windowManager.minimize,
      ),
      IconButton(
        icon: AppIcon(_maximized ? Icons.filter_none : Icons.crop_square),
        onPressed: _toggleMaximize,
      ),
      IconButton(
        icon: const AppIcon(Icons.close),
        onPressed: windowManager.close,
      ),
    ]);
  }
}

/// 应用统一顶栏：AppBar 空白区可拖动窗口、双击最大化/还原，右侧自带窗口控制。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, this.title, this.actions, this.titleSpacing});

  /// 顶栏图标统一尺寸（返回、actions、窗口控制按钮）。
  static const double _iconSize = 20;

  final Widget? title;
  final List<Widget>? actions;
  final double? titleSpacing;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final bar = IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          iconSize: _iconSize,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          padding: const EdgeInsets.all(5),
        ).copyWith(
          mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        ),
      ),
      child: AppBar(
        title: title,
        titleSpacing: titleSpacing,
        actionsIconTheme: const IconThemeData(size: _iconSize),
        actions: [...?actions, if (_isWindowsDesktop) const WindowControls()],
      ),
    );
    if (!_isWindowsDesktop) return bar;
    return DragToMoveArea(child: bar);
  }
}

