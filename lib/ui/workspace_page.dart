import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../state/rail_layout.dart';
import '../state/settings_controller.dart';
import 'app_root.dart';
import 'global_search_dialog.dart';
import 'panels/character_panel.dart';
import 'panels/foreshadow_panel.dart';
import 'panels/outline_panel.dart';
import 'panels/preview_panel.dart';
import 'panels/sensitive_panel.dart';
import 'panels/snapshot_panel.dart';

import 'recycle_page.dart';
import 'common/dialogs.dart';
import 'widgets/app_bar_nav_actions.dart';
import 'widgets/book_tree.dart';
import 'widgets/editor_area.dart';
import 'widgets/panel_rail.dart';
import 'widgets/recent_book_tabs.dart';
import 'widgets/toast.dart';
import 'widgets/window_controls.dart';

/// 作品工作区（9.2）：左右停靠栏 + 中间编辑器；
/// 停靠栏左右各分上下两段，图标可拖动换段换侧，每段独立展开一个面板。
/// 窄屏以底部导航切换；沉浸模式隐藏左右栏（FR-4）。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.book});

  final Book book;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  int _mobileTab = 1;
  bool _immersive = false;
  String? _openCharacterId;
  String? _openForeshadowId;

  /// 当前书籍：顶栏标签可切换，切换后整体重建。
  late Book _book;

  /// 缓存 AppState：dispose 期间禁止通过 context 查找祖先节点。
  late final AppState _appState;
  late final SettingsController _settings;

  /// 停靠栏布局（全局配置，不随书切换）。
  late RailLayout _rail;

  /// 窄屏当前工具面板。
  String _narrowPanelId = RailLayout.outline;

  /// 是否正在拖动 rail 图标（拖动期间两侧显示投放轮廓）。
  bool _dragging = false;

  static const double _minMidWidth = 320;
  static const double _dividerWidth = 6;

  /// 拖动分隔条时仅递增此值，驱动布局层重建（不重建编辑器 / 目录 / 面板）。
  final _layoutTick = ValueNotifier<int>(0);

  /// 宽屏布局的子区域 widget，仅在常规 build 时刷新；拖动时复用同一实例跳过重建。
  Widget? _editorWidget;
  final Map<String, Widget> _panelWidgets = {};

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _appState = context.read<AppState>();
    _settings = context.read<SettingsController>();
    _rail = _settings.railLayout;
    _narrowPanelId = _rail.mergedPanels.first;
    _appState.openCharacterNonce.addListener(_onOpenCharacter);
    _appState.openForeshadowNonce.addListener(_onOpenForeshadow);
  }

  @override
  void dispose() {
    _layoutTick.dispose();
    _appState.openCharacterNonce.removeListener(_onOpenCharacter);
    _appState.openForeshadowNonce.removeListener(_onOpenForeshadow);
    super.dispose();
  }

  /// 保存停靠栏布局到配置文件。
  void _saveRail() => _settings.saveRailLayout(_rail);

  /// 顶栏标签切换书籍：切书后整体重建（布局为全局配置，不还原面板）。
  Future<void> _switchBook(Book book) async {
    if (book.id == _book.id) return;
    await _appState.openBook(book);
    if (!mounted) return;
    setState(() {
      _book = book;
      _openCharacterId = null;
      _openForeshadowId = null;
    });
  }

  /// 关闭标签：仅从标签栏移除；关的是当前书时优先跳到相邻标签的书
  /// （右侧优先，其次左侧/最近一本），无标签可跳才退回主页。
  Future<void> _closeTab(Book book) async {
    final pos = _settings.recentBookIds.indexOf(book.id);
    await _settings.removeRecentBook(book.id);
    if (book.id != _book.id || !mounted) return;
    final remaining = _settings.recentBookIds;
    Book? next;
    if (remaining.isNotEmpty) {
      final nextId = pos >= 0 && pos < remaining.length
          ? remaining[pos]
          : remaining.last;
      for (final b in _appState.bookList) {
        if (b.id == nextId) {
          next = b;
          break;
        }
      }
    }
    if (next == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await _switchBook(next);
  }

  /// 打开写作目标对话框：设置整书目标与全书单章默认目标。
  Future<void> _openGoals() async {
    final book = _appState.currentBook ?? _book;
    final result = await bookGoalDialog(
      context,
      goal: book.goal,
      chapterGoal: book.chapterGoal,
    );
    if (result == null) return;
    await _appState.setBookGoals(goal: result.$1, chapterGoal: result.$2);
    if (mounted) showToast(context, '目标保存成功');
  }

  /// 编辑器悬浮 tip 的「编辑」请求：在图标所在段展开角色面板。
  void _onOpenCharacter() {
    final state = context.read<AppState>();
    final id = state.pendingOpenCharacterId;
    if (id == null) return;
    state.pendingOpenCharacterId = null;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    setState(() {
      _openCharacterId = id;
      _immersive = false;
      _mobileTab = 2;
      if (wide) {
        _rail.expandInSlot(RailLayout.character);
        _saveRail();
      } else {
        _narrowPanelId = RailLayout.character;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _openCharacterId = null);
    });
  }

  /// 编辑器悬浮 tip 的「编辑」请求：在图标所在段展开伏笔面板。
  void _onOpenForeshadow() {
    final state = context.read<AppState>();
    final id = state.pendingOpenForeshadowId;
    if (id == null) return;
    state.pendingOpenForeshadowId = null;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    setState(() {
      _openForeshadowId = id;
      _immersive = false;
      _mobileTab = 2;
      if (wide) {
        _rail.expandInSlot(RailLayout.foreshadow);
        _saveRail();
      } else {
        _narrowPanelId = RailLayout.foreshadow;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _openForeshadowId = null);
    });
  }

  /// 点击 rail 图标：展开 / 收起该段面板。
  void _onTogglePanel(String panelId) {
    setState(() {
      _rail.toggle(panelId);
      _saveRail();
    });
  }

  void _onRailDragStarted() {
    if (mounted && !_dragging) setState(() => _dragging = true);
  }

  void _onRailDragEnd() {
    if (mounted && _dragging) setState(() => _dragging = false);
  }

  /// 指针抬起后于下一帧兜底清除拖动状态：rail 被卸载时 onDragEnd 不会回调。
  void _scheduleEndDrag() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragging) setState(() => _dragging = false);
    });
  }

  /// 图标落到目标段：同段移动按移除后的索引插入。
  void _onRailDrop(RailSlot slot, PanelRailDragData data, int index) {
    final from = _rail.slotOf(data.panelId);
    if (from == null) return;
    var at = index;
    if (from == slot) {
      final sourceIndex = _rail.panels[from]!.indexOf(data.panelId);
      if (sourceIndex >= 0 && sourceIndex < at) at -= 1;
    }
    setState(() {
      _rail.move(data.panelId, slot, at);
      _saveRail();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    if (wide && !_immersive) {
      _editorWidget = RepaintBoundary(child: EditorArea(book: _book));
      for (final id in RailLayout.allPanels) {
        _panelWidgets[id] = _buildPanel(id);
      }
    }
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
                leading: IconButton(
                  tooltip: '返回主页',
                  icon: const Icon(Icons.home_outlined, size: 22),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                title: RecentBookTabs(
                  selectedBookId: _book.id,
                  onSelect: _switchBook,
                  onClose: _closeTab,
                ),
                actions: [
                  IconButton(
                    tooltip: '写作目标',
                    icon: const Icon(Icons.flag_outlined, size: 26),
                    onPressed: _openGoals,
                  ),
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
        body: Listener(
          onPointerUp: (_) => _scheduleEndDrag(),
          onPointerCancel: (_) => _scheduleEndDrag(),
          child: ValueListenableBuilder<int>(
            valueListenable: _appState.chapterDragCount,
            builder: (context, count, child) => Stack(
              fit: StackFit.expand,
              children: [
                child!,
                if (count > 0)
                  Positioned.fill(
                    // 只注册抓取光标注解，不参与命中，下层投放目标仍可接收拖拽。
                    child: MouseRegion(
                      opaque: false,
                      cursor: SystemMouseCursors.grabbing,
                      child: IgnorePointer(child: SizedBox.expand()),
                    ),
                  ),
              ],
            ),
            child: MouseRegion(
              cursor: _dragging
                  ? SystemMouseCursors.grabbing
                  : MouseCursor.defer,
              child: _immersive && !wide
                  ? EditorArea(book: _book, singlePaneOnly: true)
                  : body,
            ),
          ),
        ),
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
          EditorArea(book: _book),
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
        return ValueListenableBuilder<int>(
          valueListenable: _layoutTick,
          builder: (context, _, _) {
            final budget = _computeBudget(total);
            return Row(
              children: [
                if (budget.showLeftRail)
                  KeyedSubtree(
                    key: const ValueKey('dockLeft'),
                    child: _dockSide(isLeft: true, budget: budget),
                  ),
                if (budget.leftPanelWidth > 0)
                  KeyedSubtree(
                    key: const ValueKey('leftPanelDivider'),
                    child: PanelRailVerticalDivider(
                      onDrag: (delta) {
                        _rail.leftWidth = (_rail.leftWidth + delta)
                            .clamp(
                              RailLayout.minPanelWidth,
                              RailLayout.maxPanelWidth,
                            )
                            .toDouble();
                        _layoutTick.value++;
                      },
                      onDragEnd: _saveRail,
                    ),
                  ),
                Expanded(
                  key: const ValueKey('editor'),
                  child: _editorWidget ?? EditorArea(book: _book),
                ),
                if (budget.rightPanelWidth > 0)
                  KeyedSubtree(
                    key: const ValueKey('rightPanelDivider'),
                    child: PanelRailVerticalDivider(
                      onDrag: (delta) {
                        _rail.rightWidth = (_rail.rightWidth - delta)
                            .clamp(
                              RailLayout.minPanelWidth,
                              RailLayout.maxPanelWidth,
                            )
                            .toDouble();
                        _layoutTick.value++;
                      },
                      onDragEnd: _saveRail,
                    ),
                  ),
                if (budget.showRightRail)
                  KeyedSubtree(
                    key: const ValueKey('dockRight'),
                    child: _dockSide(isLeft: false, budget: budget),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 计算宽度预算：优先压缩面板宽度，仍不足时先隐藏右侧面板、再隐藏左侧面板。
  _WideBudget _computeBudget(double total) {
    final showLeftRail =
        _rail.panels[RailSlot.leftTop]!.isNotEmpty ||
        _rail.panels[RailSlot.leftBottom]!.isNotEmpty ||
        _dragging;
    final showRightRail =
        _rail.panels[RailSlot.rightTop]!.isNotEmpty ||
        _rail.panels[RailSlot.rightBottom]!.isNotEmpty ||
        _dragging;

    var leftOpen =
        _rail.active[RailSlot.leftTop] != null ||
        _rail.active[RailSlot.leftBottom] != null;
    var rightOpen =
        _rail.active[RailSlot.rightTop] != null ||
        _rail.active[RailSlot.rightBottom] != null;
    var leftPanel = leftOpen ? _rail.leftWidth : 0.0;
    var rightPanel = rightOpen ? _rail.rightWidth : 0.0;

    final rails =
        (showLeftRail ? panelRailWidth : 0.0) +
        (showRightRail ? panelRailWidth : 0.0);

    // 编辑器可用宽度 = 总宽 - 图标列 - 面板 - 分隔条。
    double over() =>
        leftPanel +
        rightPanel +
        (leftOpen ? _dividerWidth : 0.0) +
        (rightOpen ? _dividerWidth : 0.0) -
        (total - rails - _minMidWidth);

    var exceeded = over();
    if (exceeded > 0) {
      final leftCap = leftOpen
          ? math.max(0.0, leftPanel - RailLayout.minPanelWidth)
          : 0.0;
      final rightCap = rightOpen
          ? math.max(0.0, rightPanel - RailLayout.minPanelWidth)
          : 0.0;
      final capacity = leftCap + rightCap;
      if (capacity > 0) {
        final shrink = math.min(exceeded, capacity);
        leftPanel -= shrink * leftCap / capacity;
        rightPanel -= shrink * rightCap / capacity;
        exceeded = over();
      }
      if (exceeded > 0 && rightOpen) {
        rightOpen = false;
        rightPanel = 0;
        exceeded = over();
      }
      if (exceeded > 0 && leftOpen) {
        leftOpen = false;
        leftPanel = 0;
      }
    }

    return _WideBudget(
      leftPanelWidth: leftOpen
          ? math.max(leftPanel, RailLayout.minPanelWidth)
          : 0.0,
      rightPanelWidth: rightOpen
          ? math.max(rightPanel, RailLayout.minPanelWidth)
          : 0.0,
      showLeftRail: showLeftRail,
      showRightRail: showRightRail,
      active: {
        RailSlot.leftTop: leftOpen ? _rail.active[RailSlot.leftTop] : null,
        RailSlot.leftBottom: leftOpen
            ? _rail.active[RailSlot.leftBottom]
            : null,
        RailSlot.rightTop: rightOpen ? _rail.active[RailSlot.rightTop] : null,
        RailSlot.rightBottom: rightOpen
            ? _rail.active[RailSlot.rightBottom]
            : null,
      },
    );
  }

  /// 一侧停靠区：图标列在窗口边缘，面板朝编辑器一侧展开。
  Widget _dockSide({required bool isLeft, required _WideBudget budget}) {
    final topSlot = isLeft ? RailSlot.leftTop : RailSlot.rightTop;
    final bottomSlot = isLeft ? RailSlot.leftBottom : RailSlot.rightBottom;
    final topIds = _rail.panels[topSlot]!;
    final bottomIds = _rail.panels[bottomSlot]!;
    if (topIds.isEmpty && bottomIds.isEmpty && !_dragging) {
      return const SizedBox.shrink();
    }

    final activeTop = budget.active[topSlot];
    final activeBottom = budget.active[bottomSlot];
    final anyOpen = activeTop != null || activeBottom != null;
    final panelWidth = isLeft ? budget.leftPanelWidth : budget.rightPanelWidth;
    final sideWidth = panelRailWidth + (anyOpen ? panelWidth : 0.0);
    final split = isLeft ? _rail.leftSplit : _rail.rightSplit;
    final scheme = Theme.of(context).colorScheme;
    // 无激活面板的分块不占高度；拖动中临时占位以提供投放区域。
    final topShown = topIds.isNotEmpty && (activeTop != null || _dragging);
    final bottomShown =
        bottomIds.isNotEmpty && (activeBottom != null || _dragging);
    final both = topShown && bottomShown;

    Widget railGroup(RailSlot slot, List<String> ids) {
      final rail = ids.isEmpty
          ? PanelRailDropStub(
              slot: slot,
              borderOnRight: isLeft,
              decorated: false,
              onDrop: (data, index) => _onRailDrop(slot, data, index),
            )
          : PanelRailColumn(
              slot: slot,
              panelIds: ids,
              activeId: _rail.active[slot],
              borderOnRight: isLeft,
              decorated: false,
              onTap: _onTogglePanel,
              onDragStarted: _onRailDragStarted,
              onDragEnd: _onRailDragEnd,
              onDrop: (data, index) => _onRailDrop(slot, data, index),
              dragging: _dragging,
            );
      return KeyedSubtree(key: ValueKey('${slot.name}-rail'), child: rail);
    }

    Widget railSection(RailSlot slot, List<String> ids, Alignment alignment) {
      final rail = railGroup(slot, ids);
      final content = ids.isEmpty
          ? rail
          : Align(
              alignment: alignment,
              child: SizedBox(
                height: ids.length * panelRailButtonHeight,
                child: rail,
              ),
            );
      // 整段作为投放区：面板收起后仍可把图标拖到该段的空白处。
      return Expanded(
        child: PanelRailDropArea(
          slot: slot,
          railOnLeft: isLeft,
          includeRail: false,
          enabled: _dragging,
          dropIndex: ids.length,
          onDrop: (data, index) => _onRailDrop(slot, data, index),
          child: content,
        ),
      );
    }

    Widget panelBlock(RailSlot slot, List<String> ids, String? active) {
      return PanelRailDropArea(
        slot: slot,
        railOnLeft: isLeft,
        includeRail: false,
        enabled: _dragging,
        dropIndex: ids.length,
        onDrop: (data, index) => _onRailDrop(slot, data, index),
        child: active == null
            ? ColoredBox(
                color: scheme.surfaceContainerLowest.withValues(alpha: 0.6),
                child: const SizedBox.expand(),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey('${slot.name}:$active'),
                  child: _panelWidgets[active] ?? _buildPanel(active),
                ),
              ),
      );
    }

    final rail = SizedBox(
      width: panelRailWidth,
      child: DecoratedBox(
        decoration: panelRailDecoration(scheme, isLeft),
        child: Column(
          children: [
            if (topIds.isNotEmpty || _dragging)
              railSection(topSlot, topIds, Alignment.topCenter),
            if (bottomIds.isNotEmpty || _dragging)
              railSection(bottomSlot, bottomIds, Alignment.bottomCenter),
          ],
        ),
      ),
    );

    final panelColumn = anyOpen
        ? Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final topFlex = both
                    ? (split * 1000).round().clamp(1, 999).toInt()
                    : 1;
                final bottomFlex = both
                    ? (1000 - (split * 1000).round()).clamp(1, 999).toInt()
                    : 1;
                return Column(
                  children: [
                    if (topShown)
                      Expanded(
                        key: ValueKey('${isLeft ? 'L' : 'R'}-top'),
                        flex: topFlex,
                        child: panelBlock(topSlot, topIds, activeTop),
                      ),
                    if (both)
                      PanelRailHorizontalDivider(
                        key: ValueKey('${isLeft ? 'L' : 'R'}-split'),
                        onDrag: (delta) {
                          final usable = math.max(1.0, height - _dividerWidth);
                          final next = split + delta / usable;
                          final value = next
                              .clamp(RailLayout.minSplit, RailLayout.maxSplit)
                              .toDouble();
                          if (isLeft) {
                            _rail.leftSplit = value;
                          } else {
                            _rail.rightSplit = value;
                          }
                          _layoutTick.value++;
                        },
                        onDragEnd: _saveRail,
                      ),
                    if (bottomShown)
                      Expanded(
                        key: ValueKey('${isLeft ? 'L' : 'R'}-bottom'),
                        flex: bottomFlex,
                        child: panelBlock(bottomSlot, bottomIds, activeBottom),
                      ),
                  ],
                );
              },
            ),
          )
        : null;

    return SizedBox(
      width: sideWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: isLeft ? [rail, ?panelColumn] : [?panelColumn, rail],
      ),
    );
  }

  Widget _narrowBody(AppState state) {
    switch (_immersive ? 1 : _mobileTab) {
      case 0:
        return BookTree(book: _book);
      case 1:
        // 窄屏仅渲染活动窗格，分屏布局保留不丢失。
        return EditorArea(book: _book, singlePaneOnly: true);
      default:
        // 窄屏底部导航已有「目录」页，工具列表不再重复给出目录图标。
        final ids = [
          for (final id in _rail.mergedPanels)
            if (id != RailLayout.tree) id,
        ];
        final available = ids.isEmpty ? [RailLayout.outline] : ids;
        final current = available.contains(_narrowPanelId)
            ? _narrowPanelId
            : available.first;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(current),
                  child: _buildPanel(current),
                ),
              ),
            ),
            PanelRailPlainList(
              panelIds: available,
              activeId: current,
              onTap: (id) => setState(() => _narrowPanelId = id),
            ),
          ],
        );
    }
  }

  /// 按面板 id 构建面板内容。
  Widget _buildPanel(String panelId) {
    switch (panelId) {
      case RailLayout.tree:
        return BookTree(book: _book);
      case RailLayout.outline:
        return OutlinePanel(book: _book);
      case RailLayout.snapshot:
        return const SnapshotPanel();
      case RailLayout.character:
        return CharacterPanel(book: _book, openCharacterId: _openCharacterId);
      case RailLayout.foreshadow:
        return ForeshadowPanel(
          book: _book,
          openForeshadowId: _openForeshadowId,
        );
      case RailLayout.sensitive:
        return const SensitivePanel();
      case RailLayout.recycle:
        return const RecycleView(scope: RecycleScope.workspace);
      default:
        return const PreviewPanel();
    }
  }
}

/// 宽屏布局的宽度预算结果。
class _WideBudget {
  const _WideBudget({
    required this.leftPanelWidth,
    required this.rightPanelWidth,
    required this.showLeftRail,
    required this.showRightRail,
    required this.active,
  });

  final double leftPanelWidth;
  final double rightPanelWidth;
  final bool showLeftRail;
  final bool showRightRail;

  /// 实际生效的展开状态（临时隐藏的面板为 null）。
  final Map<RailSlot, String?> active;
}
