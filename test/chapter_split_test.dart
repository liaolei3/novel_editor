import 'dart:convert';

import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/chapter_title_suggest.dart';
import 'package:novel_editor/core/utils/rich_text_codec.dart';
import 'package:novel_editor/ui/common/context_menu.dart';

Delta _doc(String plain) => Delta()..insert(plain);

/// 空 Delta 的 JSON（"[]"）会被容错解码原样返回，测试里统一按空串处理。
String _plain(Delta d) => d.operations.isEmpty
    ? ''
    : RichTextCodec.plainTextFromDeltaJson(jsonEncode(d.toJson()));

void main() {
  group('RichTextCodec.splitDelta', () {
    test('段中间拆分：前段补换行、后段从切点字符开始', () {
      final (head, tail) = RichTextCodec.splitDelta(_doc('AB\nCD\n'), 1);
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(head.toJson())),
          'A\n');
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(tail.toJson())),
          'B\nCD\n');
    });

    test('段尾拆分：去掉紧随切点的一个换行，新章节无空行', () {
      final (head, tail) = RichTextCodec.splitDelta(_doc('AB\nCD\n'), 2);
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(head.toJson())),
          'AB\n');
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(tail.toJson())),
          'CD\n');
    });

    test('段首拆分：前段原样以换行结尾，后段为后续段落', () {
      final (head, tail) = RichTextCodec.splitDelta(_doc('AB\nCD\n'), 3);
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(head.toJson())),
          'AB\n');
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(tail.toJson())),
          'CD\n');
    });

    test('文档开头拆分：前段只剩一个换行，后段为全文', () {
      final (head, tail) = RichTextCodec.splitDelta(_doc('AB\nCD\n'), 0);
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(head.toJson())),
          '\n');
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(tail.toJson())),
          'AB\nCD\n');
    });

    test('切点所在段落的块属性保留在前段末尾换行上', () {
      final delta = Delta()
        ..insert('标题')
        ..insert('\n', {'header': 1})
        ..insert('正文\n');
      final (head, tail) = RichTextCodec.splitDelta(delta, 1);
      final headOps = head.operations;
      expect((headOps.last.data as String), '\n');
      expect(headOps.last.attributes, {'header': 1});
      expect(RichTextCodec.plainTextFromDeltaJson(jsonEncode(tail.toJson())),
          '题\n正文\n');
    });

    test('任意位置拆分：前段以换行结尾、内容守恒（至多补一个换行）', () {
      const plain = '第一段\n第二段正文内容\n第三段\n';
      for (var i = 0; i <= plain.length; i++) {
        final (head, tail) = RichTextCodec.splitDelta(_doc(plain), i);
        final h = _plain(head);
        final t = _plain(tail);
        expect(h.endsWith('\n'), isTrue, reason: 'offset=$i 前段应以换行结尾');
        // 切点停在段中间时前段补一个换行（原换行仍留在后段），其余位置守恒。
        expect(
          h.length + t.length,
          inInclusiveRange(plain.length, plain.length + 1),
          reason: 'offset=$i 内容应守恒（至多补一个换行）',
        );
        expect(
          (h + t).replaceAll('\n', '').length,
          plain.replaceAll('\n', '').length,
          reason: 'offset=$i 非换行字符应无增减',
        );
      }
    });
  });

  group('RichTextCodec.hasContentAfter', () {
    final delta = _doc('AB\nCD\n');

    test('末尾换行之前无实际内容 → false', () {
      expect(RichTextCodec.hasContentAfter(delta, 5), isFalse);
      expect(RichTextCodec.hasContentAfter(delta, 6), isFalse);
    });

    test('中间位置有内容 → true', () {
      expect(RichTextCodec.hasContentAfter(delta, 0), isTrue);
      expect(RichTextCodec.hasContentAfter(delta, 3), isTrue);
      expect(RichTextCodec.hasContentAfter(delta, 4), isTrue);
    });

    test('空行后仍有正文 → true', () {
      expect(
        RichTextCodec.hasContentAfter(_doc('AB\n\nCD\n'), 2),
        isTrue,
      );
    });
  });

  group('suggestChapterTitle', () {
    test('取最大编号 + 1', () {
      expect(suggestChapterTitle(['第一章', '第三章']), '第四章');
      expect(suggestChapterTitle(['第十二章']), '第十三章');
      expect(suggestChapterTitle([]), '第一章');
      expect(suggestChapterTitle(['楔子']), '第一章');
      expect(suggestChapterTitle(['第2章', '第10章']), '第十一章');
    });

    test('suggestVolumeTitle 取最大卷号 + 1', () {
      expect(suggestVolumeTitle(['第一卷', '第二卷']), '第三卷');
      expect(suggestVolumeTitle([]), '第一卷');
    });
  });

  testWidgets('右键菜单显示并触发「一键分章」额外条目', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var tapped = 0;
    final focusNode = FocusNode();
    final controller = QuillController.basic()
      ..document.insert(0, 'hello world')
      ..document.insert(11, '\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            focusNode: focusNode,
            scrollController: ScrollController(),
            config: QuillEditorConfig(
              contextMenuBuilder: (context, rawState) =>
                  appEditorContextMenuBuilder(
                context,
                rawState,
                extraEntries: [
                  AppMenuAction('一键分章', onTap: () => tapped++),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();
    // 右键菜单需要有效选区/光标才会弹出。
    controller.updateSelection(
      const TextSelection.collapsed(offset: 5),
      ChangeSource.local,
    );
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.byType(QuillEditor)),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('一键分章'), findsOneWidget);
    await tester.tap(find.text('一键分章'));
    await tester.pump();
    expect(tapped, 1);
  });
}
