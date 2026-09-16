import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'app_root.dart';
import 'global_search_dialog.dart';
import 'panels/ai_panel.dart';
import 'panels/character_panel.dart';
import 'panels/notes_panel.dart';
import 'panels/outline_panel.dart';
import 'panels/sensitive_panel.dart';
import 'panels/snapshot_panel.dart';
import 'panels/stats_panel.dart';
import 'recycle_page.dart';
import 'widgets/app_bar_nav_actions.dart';
import 'widgets/book_tree.dart';
import 'widgets/editor_area.dart';
import 'widgets/window_controls.dart';

/// 作品工作区（9.2）：左=作品树，中=编辑器，右=竖向活动图标列 + 弹出工具面板；
/// 窄屏以底部导航切换；沉浸模式隐藏左右栏（FR-4）。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.book});

  final Book book;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  int _mobileTab = 1;
  int _panelIndex = 0;
  bool _panelOpen = false;
  bool _immersive = false;
  String? _openCharacterId;

  /// 缓存 AppState：dispose 期间禁止通过 context 查找祖先节点。
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _appState.openCharacterNonce.addListener(_onOpenCharacter);
  }

  @override
  void dispose() {
    _appState.openCharacterNonce.removeListener(_onOpenCharacter);
    super.dispose();
  }

  /// 编辑器悬浮 tip 的「编辑」请求：切到角色面板并打开对应角色详情。
  void _onOpenCharacter() {
    final state = context.read<AppState>();
    final id = state.pendingOpenCharacterId;
    if (id == null) return;
    state.pendingOpenCharacterId = null;
    setState(() {
      _openCharacterId = id;
      _panelIndex = 3;
      _panelOpen = true;
      _immersive = false;
      _mobileTab = 2;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _openCharacterId = null);
    });
  }

  static const _panels = ['大纲视图', 'AI 助手', '历史快照', '角色', '素材库', '敏感词', '码字统计', '回收站'];
  static const _panelIcons = [
    Icons.account_tree_outlined,
    Icons.auto_awesome,
    Icons.history,
    Icons.people_outlined,
    Icons.sticky_note_2_outlined,
    Icons.shield_outlined,
    Icons.query_stats_outlined,
    Icons.delete_outline,
  ];
  static const double _minLeftWidth = 220;
  static const double _minMidWidth = 320;
  static const double _minRightWidth = 360;
  static const double _dividerWidth = 6;
  static const double _railWidth = 48;

  double _leftWidth = 280;
  double _rightWidth = 408;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 1000;
    final body = wide ? _wideBody(state) : _narrowBody(state);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final s = appState(context);
        await s.shutdown();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: _immersive
            ? null
            : AppTopBar(
                title: Text(widget.book.title),
                actions: [
                  IconButton(
                    tooltip: '全局搜索替换',
                    icon: const Icon(Icons.search, size: 26),
                    onPressed: () => showGlobalSearchDialog(context),
                  ),
                  IconButton(
                    tooltip: _immersive ? '退出沉浸' : '沉浸模式',
                    icon: Icon(
                      _immersive ? Icons.fullscreen_exit : Icons.fullscreen,
                      size: 26,
                    ),
                    onPressed: () => setState(() => _immersive = !_immersive),
                  ),
                  const AppBarNavActions(),
                ],
              ),
        body: _immersive && !wide ? EditorArea(book: widget.book) : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _immersive ? 1 : _mobileTab,
                onDestinationSelected: (i) => setState(() {
                  _mobileTab = i;
                  _immersive = false;
                }),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    label: '目录',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.edit_note),
                    label: '写作',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.widgets_outlined),
                    label: '工具',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _wideBody(AppState state) {
    if (_immersive) {
      return Stack(
        children: [
          EditorArea(book: widget.book),
          Positioned(
            right: 16,
            top: 16,
            child: IconButton.filledTonal(
              tooltip: '退出App沉浸模式',
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: () => setState(() => _immersive = false),
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final chrome = _dividerWidth * 2;
        // 联合约束：左 + 右 <= 窗口宽 − 分隔条 − 中栏保底，保证中栏不被挤压。
        final midBudget = math.max(
          0.0,
          total - chrome - _minMidWidth,
        );
        var left = math.max(_minLeftWidth, _leftWidth);
        var right = math.max(_minRightWidth, _rightWidth);
        if (_panelOpen && left + right > midBudget) {
          final overflow = left + right - midBudget;
          // 超限时收缩较大的一侧。
          if (left >= right) {
            left = math.max(_minLeftWidth, left - overflow);
          } else {
            right = math.max(_minRightWidth, right - overflow);
          }
        }
        return Row(
          children: [
            SizedBox(
              width: left,
              child: BookTree(book: widget.book),
            ),
            _DragDivider(
              width: _dividerWidth,
              onDrag: (delta) => setState(() {
                _leftWidth = (_leftWidth + delta).clamp(
                  _minLeftWidth,
                  math.max(_minLeftWidth, midBudget - right),
                );
              }),
            ),
            Expanded(child: EditorArea(book: widget.book)),
            if (_panelOpen)
              _DragDivider(
                width: _dividerWidth,
                onDrag: (delta) => setState(() {
                  _rightWidth = (_rightWidth - delta).clamp(
                    _minRightWidth,
                    math.max(_minRightWidth, midBudget - left),
                  );
                }),
              ),
            SizedBox(
              width: _panelOpen ? right : _railWidth,
              child: _panelArea(),
            ),
          ],
        );
      },
    );
  }

  Widget _narrowBody(AppState state) {
    switch (_immersive ? 1 : _mobileTab) {
      case 0:
        return BookTree(book: widget.book);
      case 1:
        return EditorArea(book: widget.book);
      default:
        return _panelArea(forceOpen: true);
    }
  }

  /// 右缘活动图标列：点击图标在其左侧弹出对应面板，再次点击收起。
  Widget _panelArea({bool forceOpen = false}) {
    final scheme = Theme.of(context).colorScheme;
    final open = forceOpen || _panelOpen;
    return Row(
      children: [
        if (open)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey(_panelIndex),
                child: _panelBody(),
              ),
            ),
          ),
        Container(
          width: _railWidth,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border(
              left: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _panels.length; i++)
                _RailButton(
                  tooltip: _panels[i],
                  icon: _panelIcons[i],
                  selected: open && _panelIndex == i,
                  onTap: () => setState(() {
                    if (_panelIndex == i) {
                      _panelOpen = !_panelOpen;
                    } else {
                      _panelIndex = i;
                      _panelOpen = true;
                    }
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panelBody() {
    final book = widget.book;
    switch (_panelIndex) {
      case 0:
        return OutlinePanel(book: book);
      case 1:
        return const AiPanel();
      case 2:
        return const SnapshotPanel();
      case 3:
        return CharacterPanel(book: book, openCharacterId: _openCharacterId);
      case 4:
        return NotesPanel(book: book);
      case 5:
        return const SensitivePanel();
      case 6:
        return const StatsPanel();
      default:
        return const RecycleView();
    }
  }
}

/// 可拖动的垂直分隔条：拖动调整左右栏宽度，hover 时高亮。
class _DragDivider extends StatefulWidget {
  const _DragDivider({required this.width, required this.onDrag});

  final double width;
  final ValueChanged<double> onDrag;

  @override
  State<_DragDivider> createState() => _DragDividerState();
}

class _DragDividerState extends State<_DragDivider> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          child: Center(
            child: Container(
              width: _hovered ? 2 : 1,
              height: double.infinity,
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// 活动列按钮：类似 IDE 工具窗按钮，选中时左缘显示指示条。
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Stack(
        children: [
          SizedBox(
            width: 48,
            height: 44,
            child: Material(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: onTap,
                child: Center(
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
