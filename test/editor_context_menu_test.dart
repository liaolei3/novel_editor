import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/editor_toolbar_controller_shared/clipboard/clipboard_service.dart';
import 'package:flutter_quill/src/editor_toolbar_controller_shared/clipboard/clipboard_service_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/ui/common/context_menu.dart';

/// 测试用剪贴板服务：不支持富文本（HTML/Markdown/图片），走纯文本路径。
// ignore: experimental_member_use
class _PlainTextOnlyClipboardService extends ClipboardService {
  @override
  Future<String?> getHtmlText() async => null;
  @override
  Future<String?> getHtmlFile() async => null;
  @override
  Future<String?> getMarkdownFile() async => null;
  @override
  Future<Uint8List?> getImageFile() async => null;
  @override
  Future<Uint8List?> getGifFile() async => null;
  @override
  Future<void> copyImage(Uint8List imageBytes) async {}
}

/// 模拟 editor_area 的右键位置记录：记录最近一次右键按下的全局坐标。
class _TapTracker {
  Offset? position;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test 环境没有 Clipboard 通道处理器，mock 掉。
  String? clipboardContent;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        return clipboardContent == null
            ? null
            : {'text': clipboardContent};
      case 'Clipboard.setData':
        clipboardContent = call.arguments['text'] as String?;
        return null;
      case 'Clipboard.hasStrings':
        return clipboardContent != null && clipboardContent!.isNotEmpty;
    }
    return null;
  });

  setUp(() {
    // ignore: experimental_member_use
    ClipboardServiceProvider.setInstance(_PlainTextOnlyClipboardService());
  });

  Future<QuillController> pumpEditor(
    WidgetTester tester,
    FocusNode focusNode, {
    _TapTracker? tracker,
  }) async {
    final controller = QuillController.basic()
      ..document.insert(0, 'hello world')
      ..document.insert(11, '\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Listener(
            onPointerDown: (event) {
              if (tracker != null && event.buttons == kSecondaryButton) {
                tracker.position = event.position;
              }
            },
            child: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode,
              scrollController: ScrollController(),
              config: QuillEditorConfig(
                contextMenuBuilder: (context, state) =>
                    appEditorContextMenuBuilder(
                  context,
                  state,
                  secondaryTapPosition: tracker?.position,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();
    return controller;
  }

  Future<void> showMenu(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.byType(QuillEditor)),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('全选：点击菜单项后选区覆盖整篇文档', (tester) async {
    final focusNode = FocusNode();
    final controller = await pumpEditor(tester, focusNode);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      ChangeSource.local,
    );
    await tester.pump();

    await showMenu(tester);
    expect(find.text('全选'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(controller.selection.baseOffset, 0);
    // 全选后选区覆盖编辑器全部文本（文档末尾可能被补一个换行）。
    expect(controller.selection.extentOffset, greaterThanOrEqualTo(12));
    expect(
      controller.selection.extentOffset,
      controller.document.toPlainText().length - 1,
    );
  });

  testWidgets('菜单跟随右键点击位置而非选区位置', (tester) async {
    final focusNode = FocusNode();
    final tracker = _TapTracker();
    final controller = await pumpEditor(tester, focusNode, tracker: tracker);
    // 选区在文档顶部，右键点击在编辑器中心，菜单应出现在中心。
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      ChangeSource.local,
    );
    await tester.pump();

    await showMenu(tester);

    final center = tester.getCenter(find.byType(QuillEditor));
    expect(tracker.position, isNotNull);
    // 面板根是 CustomSingleChildLayout（位于 0,0），菜单内容定位在其
    // 内部 Material 上，取 Material 的全局坐标才是菜单位置。
    final menuTopLeft = tester
        .renderObject<RenderBox>(
          find
              .descendant(
                of: find.byType(AppEditorContextMenuPanel),
                matching: find.byType(Material),
              )
              .first,
        )
        .localToGlobal(Offset.zero);
    expect(menuTopLeft.dy, closeTo(tracker.position!.dy, 1));
    expect(menuTopLeft.dx, closeTo(tracker.position!.dx, 1));
    // 菜单不应出现在选区（文档顶部）附近。
    expect(menuTopLeft.dy, greaterThan(center.dy - 20));
  });

  testWidgets('复制：选区文本进入剪贴板且菜单关闭', (tester) async {
    final focusNode = FocusNode();
    final controller = await pumpEditor(tester, focusNode);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      ChangeSource.local,
    );
    await tester.pump();

    await showMenu(tester);
    await tester.tap(find.text('复制'));
    await tester.pump();

    expect(clipboardContent, 'hello');
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('剪切：选区文本进入剪贴板且从文档移除', (tester) async {
    final focusNode = FocusNode();
    final controller = await pumpEditor(tester, focusNode);
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 6),
      ChangeSource.local,
    );
    await tester.pump();

    await showMenu(tester);
    await tester.tap(find.text('剪切'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(clipboardContent, 'hello ');
    expect(controller.document.toPlainText(), startsWith('world'));
  });

  testWidgets('粘贴：剪贴板文本插入光标处', (tester) async {
    final focusNode = FocusNode();
    final controller = await pumpEditor(tester, focusNode);
    clipboardContent = 'XYZ';
    controller.updateSelection(
      const TextSelection.collapsed(offset: 11),
      ChangeSource.local,
    );
    await tester.pump();

    await showMenu(tester);
    await tester.tap(find.text('粘贴'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(controller.document.toPlainText(), contains('XYZ'));
  });
}
