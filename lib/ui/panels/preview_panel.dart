import 'dart:async';
import 'dart:math' as math;

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/utils/foreshadow_delta.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../common/context_menu.dart';
import '../common/dialogs.dart';
import '../widgets/reading_styles.dart';

/// 手机机身与屏幕尺寸（逻辑像素，缩放前）。
const double _bezelWidth = 9;
const double _screenRadius = 22;
const double _statusBarHeight = 44;
const double _pageBarHeight = 26;
const double _homeBarHeight = 16;
const Color _bezelColor = Color(0xFF2A2C31);

/// 正文刷新防抖：输入过程中不重建预览，停笔后再刷，避免拖慢编辑器。
const Duration _refreshDebounce = Duration(milliseconds: 300);

/// 预览面板：把当前编辑中的章节渲染进手机画框，用于审阅手机端排版观感。
/// 机型/尺寸/排版参数均为预览专用（见 [showPreviewSettingsDialog]），
/// 不回写编辑器；正文为纯净只读渲染，不含角色高亮与伏笔标注。
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key});

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  late final AppState _state;
  final ScrollController _scroll = ScrollController();

  /// QuillEditor.basic 每次构建都会新建 FocusNode，必须复用同一个并自行释放。
  final FocusNode _focus = FocusNode();

  QuillController? _controller;
  bool _empty = true;

  /// 已订阅内容变化的文档对象：切章或整体替换文档时对象会变，需重新订阅。
  Document? _boundDoc;
  String? _chapterId;
  StreamSubscription<DocChange>? _docSub;
  Timer? _debounce;

  /// 一屏高度（正文可视区，已扣除状态栏与底部页码行）与分页结果。
  double _pageHeight = 0;
  int _pageCount = 1;
  int _pageIndex = 1;

  /// 重排后要恢复的滚动比例：改机型/排版后尽量停在原来的阅读位置。
  double? _pendingRatio;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _state.addListener(_onStateChanged);
    _scroll.addListener(_measurePages);
    _bindDocument();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _docSub?.cancel();
    _state.removeListener(_onStateChanged);
    _scroll.removeListener(_measurePages);
    _scroll.dispose();
    _focus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// 只在切章或文档对象被整体替换时重挂订阅；打字引起的变更交给文档流处理。
  void _onStateChanged() {
    final doc = _state.editorController.document;
    if (_state.currentChapter?.id != _chapterId || !identical(doc, _boundDoc)) {
      _bindDocument();
    }
  }

  void _bindDocument() {
    _docSub?.cancel();
    _debounce?.cancel();
    final doc = _state.editorController.document;
    _boundDoc = doc;
    _chapterId = _state.currentChapter?.id;
    _docSub = doc.changes.listen((_) => _scheduleRender());
    // 换章回到顶部，与编辑器切章行为一致。
    _pendingRatio = 0;
    _render();
  }

  void _scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(_refreshDebounce, _render);
  }

  /// 用当前正文重建预览文档（只读）。
  void _render() {
    if (!mounted) return;
    if (_state.currentChapter == null) {
      setState(() {
        _empty = true;
        _pageCount = 1;
        _pageIndex = 1;
      });
      return;
    }
    if (_pendingRatio == null) _captureScrollRatio();
    final doc =
        Document.fromDelta(_pureDelta(_state.editorController.document.toDelta()));
    if (_controller == null) {
      _controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } else {
      _controller!.document = doc;
    }
    setState(() => _empty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreScrollPosition();
    });
  }

  /// 剥离伏笔标注属性，得到纯净正文 Delta（内联样式与块属性全部保留）。
  Delta _pureDelta(Delta delta) {
    final ids = <String>{};
    for (final op in delta.operations) {
      final v = op.attributes?[kFsidKey];
      if (v is String) ids.add(v);
    }
    var out = delta;
    for (final id in ids) {
      out = removeFsidFromDelta(out, id);
    }
    return out;
  }

  void _captureScrollRatio() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _pendingRatio =
        pos.maxScrollExtent <= 0 ? 0 : pos.pixels / pos.maxScrollExtent;
  }

  void _restoreScrollPosition() {
    final ratio = _pendingRatio;
    _pendingRatio = null;
    if (ratio != null && _scroll.hasClients) {
      final pos = _scroll.position;
      pos.jumpTo((ratio * pos.maxScrollExtent).clamp(0.0, pos.maxScrollExtent));
    }
    _measurePages();
    // 文档替换后 Quill 内部可能再走一次布局，补测一次保证页数准确。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measurePages();
    });
  }

  /// 按一屏高度换算总页数与当前页（连续滚动下的位置指示）。
  void _measurePages() {
    if (!mounted || _pageHeight <= 0 || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final total =
        math.max(1, ((pos.maxScrollExtent + _pageHeight) / _pageHeight).ceil());
    final current = math.min(total, (pos.pixels / _pageHeight).floor() + 1);
    if (total == _pageCount && current == _pageIndex) return;
    setState(() {
      _pageCount = total;
      _pageIndex = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final screen = _previewScreenSize(settings);
    return Column(
      children: [
        _header(context, settings, screen),
        Expanded(
          child: ColoredBox(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
            child: _phoneArea(context, settings, screen),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, SettingsController settings, Size screen) {
    final scheme = Theme.of(context).colorScheme;
    final label = _activeDevice(settings)?.label ?? '自定义尺寸';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      child: Row(
        children: [
          Text(
            '预览',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label · ${screen.width.round()}×${screen.height.round()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: '预览设置',
            iconSize: 20,
            icon: const Icon(Icons.tune),
            onPressed: () => showPreviewSettingsDialog(context),
          ),
        ],
      ),
    );
  }

  /// 画框固定按机型逻辑分辨率绘制，仅在不合身时等比缩小（不放大以免失真）。
  Widget _phoneArea(
      BuildContext context, SettingsController settings, Size screen) {
    final frameW = screen.width + _bezelWidth * 2;
    final frameH = screen.height + _bezelWidth * 2;
    final body = Container(
      width: frameW,
      height: frameH,
      padding: const EdgeInsets.all(_bezelWidth),
      decoration: BoxDecoration(
        color: _bezelColor,
        borderRadius: BorderRadius.circular(_screenRadius + _bezelWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_screenRadius),
        child: _screen(context, settings, screen),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final sized = SizedBox(width: frameW, height: frameH, child: body);
          final fits = c.maxWidth >= frameW && c.maxHeight >= frameH;
          return Center(
            child: fits
                ? sized
                : FittedBox(fit: BoxFit.contain, child: sized),
          );
        },
      ),
    );
  }

  Widget _screen(
      BuildContext context, SettingsController settings, Size screen) {
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery(
      // 手机预览按机型自身度量渲染，不跟随「界面缩放」。
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: screen.width,
        height: screen.height,
        child: ColoredBox(
          color: scheme.surface,
          child: Column(
            children: [
              _statusBar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxHeight != _pageHeight) {
                      _pageHeight = c.maxHeight;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _measurePages();
                      });
                    }
                    return _content(context, settings);
                  },
                ),
              ),
              _pageBar(context),
              _homeBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SettingsController settings) {
    if (_empty) {
      return const Center(
        child: Text('先打开一个章节，再预览手机端效果',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
      );
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return QuillEditor.basic(
      controller: controller,
      focusNode: _focus,
      scrollController: _scroll,
      config: QuillEditorConfig(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
        scrollPhysics: const ClampingScrollPhysics(),
        // 只读预览：光标用普通箭头，避免看起来可编辑。
        readOnlyMouseCursor: SystemMouseCursors.basic,
        customStyles: buildReadingStyles(
          context,
          fontSize: settings.reviewFontSize,
          lineHeight: settings.reviewLineHeight,
          paragraphSpacing: settings.reviewParagraphSpacing,
          fontFamily: settings.editorFontFamily,
        ),
      ),
    );
  }

  /// 状态栏：时间 + 信号/电量，中央挖孔。
  Widget _statusBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final now = DateTime.now();
    final clock = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: _statusBarHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clock,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                  const Spacer(),
                  Icon(Icons.signal_cellular_alt, size: 13, color: fg),
                  const SizedBox(width: 3),
                  Icon(Icons.wifi, size: 13, color: fg),
                  const SizedBox(width: 3),
                  Icon(Icons.battery_full, size: 14, color: fg),
                ],
              ),
            ),
          ),
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 84,
                height: 22,
                decoration: BoxDecoration(
                  color: _bezelColor,
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 页码行：连续滚动下的「当前屏 / 总屏数」。
  Widget _pageBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _pageBarHeight,
      child: Center(
        child: Text(
          '$_pageIndex / $_pageCount',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _homeBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _homeBarHeight,
      child: Center(
        child: Container(
          width: 108,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// 预览设置弹窗：机型/尺寸与预览专用排版参数（只影响预览，不回写编辑器）。
Future<void> showPreviewSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DraggableDialog(child: _PreviewSettingsDialog()),
  );
}

class _PreviewSettingsDialog extends StatefulWidget {
  const _PreviewSettingsDialog();

  @override
  State<_PreviewSettingsDialog> createState() => _PreviewSettingsDialogState();
}

class _PreviewSettingsDialogState extends State<_PreviewSettingsDialog> {
  late final SettingsController _settings;
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final Set<String> _focusedLabels = <String>{};

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsController>();
    final size = _previewScreenSize(_settings);
    _widthCtrl.text = size.width.round().toString();
    _heightCtrl.text = size.height.round().toString();
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDevice(RenderBox target) async {
    final picked = await showAppAnchoredMenu<String>(
      context: context,
      target: target,
      initialValue: _settings.reviewDevice,
      entries: [
        for (final d in AppConstants.previewDevices) AppMenuItem(d.id, d.label),
        const AppMenuItem(AppConstants.previewCustomDeviceId, '自定义尺寸'),
      ],
    );
    if (picked == null) return;
    await _settings.setReviewDevice(picked);
    if (!mounted) return;
    final size = _previewScreenSize(_settings);
    setState(() {
      _widthCtrl.text = size.width.round().toString();
      _heightCtrl.text = size.height.round().toString();
    });
  }

  /// 尺寸输入：仅当宽高都合法时落库并切到「自定义」，
  /// 输入过程中越界不写配置，避免打断连续输入。
  void _applySize() {
    setState(() {});
    final w = double.tryParse(_widthCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    final okW = w != null &&
        w >= AppConstants.previewMinWidth &&
        w <= AppConstants.previewMaxWidth;
    final okH = h != null &&
        h >= AppConstants.previewMinHeight &&
        h <= AppConstants.previewMaxHeight;
    if (!okW || !okH) return;
    if (_settings.reviewDevice != AppConstants.previewCustomDeviceId) {
      _settings.setReviewDevice(AppConstants.previewCustomDeviceId);
    }
    _settings.setReviewCustomSize(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return AlertDialog(
      title: Row(children: [
        const Text('预览设置'),
        const Spacer(),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _deviceRow(context, settings),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _sizeField(
                    label: '宽',
                    controller: _widthCtrl,
                    min: AppConstants.previewMinWidth,
                    max: AppConstants.previewMaxWidth,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sizeField(
                    label: '高',
                    controller: _heightCtrl,
                    min: AppConstants.previewMinHeight,
                    max: AppConstants.previewMaxHeight,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              _sliderRow(
                context,
                title: '正文字号',
                value: '${settings.reviewFontSize.round()}',
                min: 13,
                max: 26,
                divisions: 13,
                current: settings.reviewFontSize,
                onChanged: settings.setReviewFontSize,
              ),
              _sliderRow(
                context,
                title: '行距',
                value: '${settings.reviewLineHeight.toStringAsFixed(1)} 倍',
                min: 1.2,
                max: 2.6,
                divisions: 14,
                current: settings.reviewLineHeight,
                onChanged: settings.setReviewLineHeight,
              ),
              _sliderRow(
                context,
                title: '段间距',
                value: '${settings.reviewParagraphSpacing.toStringAsFixed(1)} 倍',
                min: 0,
                max: 2.0,
                divisions: 20,
                current: settings.reviewParagraphSpacing,
                onChanged: settings.setReviewParagraphSpacing,
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _deviceRow(BuildContext context, SettingsController settings) {
    final scheme = Theme.of(context).colorScheme;
    final label = _activeDevice(settings)?.label ?? '自定义尺寸';
    final hairline = Theme.of(context).brightness == Brightness.light
        ? const Color(0x2E000000)
        : const Color(0x2EFFFFFF);
    return Row(children: [
      const Text('机型', style: TextStyle(fontSize: 13)),
      const Spacer(),
      Builder(
        builder: (ctx) => Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            // 用按钮自身的 RenderBox 定位锚点菜单。
            onTap: () => _pickDevice(ctx.findRenderObject()! as RenderBox),
            child: Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 104),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more,
                      size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _sizeField({
    required String label,
    required TextEditingController controller,
    required double min,
    required double max,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = Theme.of(context).brightness == Brightness.light
        ? const Color(0x2E000000)
        : const Color(0x2EFFFFFF);
    final v = double.tryParse(controller.text);
    final invalid = v == null || v < min || v > max;
    final focused = _focusedLabels.contains(label);
    final borderColor =
        invalid ? scheme.error : (focused ? scheme.primary : hairline);
    // 与「机型」下拉框同一套外壳，保证高度、圆角、描边一致。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onFocusChange: (has) => setState(() {
            has ? _focusedLabels.add(label) : _focusedLabels.remove(label);
          }),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: focused || invalid ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Transform.translate(
                  offset: const Offset(0, -1),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 13),
                    // 显式清空所有边框状态，否则会被主题 OutlineInputBorder 补出内层框
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    onChanged: (_) => _applySize(),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 错误提示占固定高度，出现/消失时不挤压输入框与下方滑块
        SizedBox(
          height: 16,
          child: invalid
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${min.round()}–${max.round()}',
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _sliderRow(
    BuildContext context, {
    required String title,
    required String value,
    required double min,
    required double max,
    required int divisions,
    required double current,
    required ValueChanged<double> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(value,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 6),
          Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: current.clamp(min, max),
            onChanged: onChanged,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// 预览用机型：返回 null 表示「自定义尺寸」档位。
PreviewDevice? _activeDevice(SettingsController s) {
  final id = s.reviewDevice;
  if (id == AppConstants.previewCustomDeviceId) return null;
  return AppConstants.previewDevices.firstWhere(
    (d) => d.id == id,
    orElse: () => AppConstants.defaultPreviewDevice,
  );
}

/// 预览画框使用的屏幕逻辑尺寸。
Size _previewScreenSize(SettingsController s) {
  final device = _activeDevice(s);
  return device == null
      ? Size(s.reviewCustomWidth, s.reviewCustomHeight)
      : Size(device.width, device.height);
}