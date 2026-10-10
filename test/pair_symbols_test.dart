import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/core/utils/pair_symbols.dart';

QuillController _controllerWith(String text) =>
    QuillController.basic()..document.insert(0, text);

void main() {
  group('handlePairBackspace（成对空符号中间退格）', () {
    test('光标在“”中间：一并删除两个符号，光标前移一位', () {
      final c = _controllerWith('a“”b');
      c.updateSelection(
          const TextSelection.collapsed(offset: 2), ChangeSource.local);
      expect(handlePairBackspace(c), isTrue);
      expect(c.document.toPlainText(), 'ab\n');
      expect(c.selection.start, 1);
    });

    test('光标在《》中间：一并删除', () {
      final c = _controllerWith('x《》y');
      c.updateSelection(
          const TextSelection.collapsed(offset: 2), ChangeSource.local);
      expect(handlePairBackspace(c), isTrue);
      expect(c.document.toPlainText(), 'xy\n');
    });

    test('前开符与后闭符不匹配：不处理', () {
      final c = _controllerWith('a“】b');
      c.updateSelection(
          const TextSelection.collapsed(offset: 2), ChangeSource.local);
      expect(handlePairBackspace(c), isFalse);
      expect(c.document.toPlainText(), 'a“】b\n');
    });

    test('前一字符非开符：不处理', () {
      final c = _controllerWith('ab');
      c.updateSelection(
          const TextSelection.collapsed(offset: 1), ChangeSource.local);
      expect(handlePairBackspace(c), isFalse);
    });

    test('有选区：不处理', () {
      final c = _controllerWith('a“”b');
      c.updateSelection(
          const TextSelection(baseOffset: 1, extentOffset: 2),
          ChangeSource.local);
      expect(handlePairBackspace(c), isFalse);
    });

    test('文档开头：不处理', () {
      final c = _controllerWith('“”');
      c.updateSelection(
          const TextSelection.collapsed(offset: 0), ChangeSource.local);
      expect(handlePairBackspace(c), isFalse);
    });
  });

  group('updateEditingValue（IME 提交路径的成对补全）', () {
    Future<QuillRawEditorState> pumpEditor(
      WidgetTester tester,
      QuillController controller,
    ) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode,
              scrollController: ScrollController(),
              config: QuillEditorConfig(
                autoPairSymbols: fullWidthPairSymbols,
                autoFocus: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      return tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));
    }

    testWidgets('提交开符：补上闭符，光标落在二者中间', (tester) async {
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'ab“c\n',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab“”c\n');
      expect(controller.selection.start, 3);
    });

    testWidgets('光标前正是同款闭符时提交闭符：跳过，不重复插入', (tester) async {
      final controller = _controllerWith('ab“”c');
      controller.updateSelection(
          const TextSelection.collapsed(offset: 3), ChangeSource.local);
      final state = await pumpEditor(tester, controller);

      // IME 在光标处提交 ”：光标前（右侧紧邻）正是 ”。
      state.updateEditingValue(const TextEditingValue(
        text: 'ab“””c\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab“”c\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('有选区时提交开符：包裹选中文本，光标在闭符后', (tester) async {
      final controller = _controllerWith('abc');
      controller.updateSelection(
          const TextSelection(baseOffset: 1, extentOffset: 3),
          ChangeSource.local);
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'a“\n',
        selection: TextSelection.collapsed(offset: 2),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'a“bc”\n');
      expect(controller.selection.start, 5);
    });

    testWidgets('普通字符（不在符号表内）照常插入', (tester) async {
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'abXc\n',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'abXc\n');
      expect(controller.selection.start, 3);
    });

    testWidgets('连续三个半角句点：合并为中文省略号（……），光标随之后移', (tester) async {
      final controller = _controllerWith('ab..');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'ab...\n',
        selection: TextSelection.collapsed(offset: 5),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab……\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('仅两个半角句点：不合并', (tester) async {
      final controller = _controllerWith('ab.');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'ab..\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab..\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('未配置 autoPairSymbols 时不做补全', (tester) async {
      final controller = _controllerWith('abc');
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode,
              scrollController: ScrollController(),
              config: const QuillEditorConfig(autoFocus: false),
            ),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      final state =
          tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));

      state.updateEditingValue(const TextEditingValue(
        text: 'ab“c\n',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab“c\n');
    });
  });

  group('IME 组合路径（Windows 标点提交：组合更新 → 组合结束更新）', () {
    Future<QuillRawEditorState> pumpEditor(
      WidgetTester tester,
      QuillController controller,
    ) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              focusNode: focusNode,
              scrollController: ScrollController(),
              config: QuillEditorConfig(
                autoPairSymbols: fullWidthPairSymbols,
                autoFocus: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      return tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));
    }

    testWidgets('组合期间提交开符：组合结束后补闭符，光标居中', (tester) async {
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      // 组合更新：IME 提交 “，composing 覆盖该字符。
      state.updateEditingValue(const TextEditingValue(
        text: 'abc“\n',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      ));
      await tester.pump();
      // 组合期间不得改动文档（否则被 IME 回滚）。
      expect(controller.document.toPlainText(), 'abc“\n');

      // 组合结束更新：composing 清空，文本与选区不变。
      state.updateEditingValue(const TextEditingValue(
        text: 'abc“\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'abc“”\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('选区替换提交闭符（IME 开/闭交替）：组合结束后用完整对包裹',
        (tester) async {
      final controller = _controllerWith('a进门b');
      controller.updateSelection(
          const TextSelection(baseOffset: 1, extentOffset: 3),
          ChangeSource.local);
      final state = await pumpEditor(tester, controller);

      // 组合更新：IME 提交 ”（交替给出闭符）替换选区。
      state.updateEditingValue(const TextEditingValue(
        text: 'a”b\n',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ));
      await tester.pump();
      expect(controller.document.toPlainText(), 'a”b\n');

      // 组合结束：反查出开符 “，用 “进门” 包裹原选中文本。
      state.updateEditingValue(const TextEditingValue(
        text: 'a”b\n',
        selection: TextSelection.collapsed(offset: 2),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'a“进门”b\n');
      expect(controller.selection.start, 5);
    });

    testWidgets('组合期间提交闭符且右侧紧邻同款闭符：结束后跳过', (tester) async {
      final controller = _controllerWith('ab“”c');
      controller.updateSelection(
          const TextSelection.collapsed(offset: 3), ChangeSource.local);
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'ab“””c\n',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      ));
      await tester.pump();
      expect(controller.document.toPlainText(), 'ab“””c\n');

      state.updateEditingValue(const TextEditingValue(
        text: 'ab“””c\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'ab“”c\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('组合期间提交普通字符：不触发配对', (tester) async {
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'abc你\n',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      ));
      await tester.pump();
      state.updateEditingValue(const TextEditingValue(
        text: 'abc你\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'abc你\n');
    });

    testWidgets('输入法交替给出闭符且前方无未闭合开符：转为补全整对', (tester) async {
      // 用户实际场景：键入 “ 配对后删除，再次键入时 IME 交替给出 ”。
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'abc”\n',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 3, end: 4),
      ));
      await tester.pump();
      state.updateEditingValue(const TextEditingValue(
        text: 'abc”\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'abc“”\n');
      expect(controller.selection.start, 4);
    });

    testWidgets('输入法给出闭符且前方有未闭合开符：按闭符原样插入', (tester) async {
      final controller = _controllerWith('a“bc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'a“bc”\n',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 4, end: 5),
      ));
      await tester.pump();
      state.updateEditingValue(const TextEditingValue(
        text: 'a“bc”\n',
        selection: TextSelection.collapsed(offset: 5),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'a“bc”\n');
    });

    testWidgets('直接键入闭符（无组合）且前方无未闭合开符：转为补全整对',
        (tester) async {
      final controller = _controllerWith('abc');
      final state = await pumpEditor(tester, controller);

      state.updateEditingValue(const TextEditingValue(
        text: 'abc”\n',
        selection: TextSelection.collapsed(offset: 4),
      ));
      await tester.pump();

      expect(controller.document.toPlainText(), 'abc“”\n');
      expect(controller.selection.start, 4);
    });
  });

  group('findDialogueRanges（对话引号区间扫描）', () {
    test('全角双引号成对返回内文区间（不含引号本身）', () {
      expect(findDialogueRanges('他说：“你好。”'), [(4, 7)]);
    });

    test('半角双引号同字符开闭按开关式配对', () {
      expect(findDialogueRanges('"甲"和"乙"'), [(1, 2), (5, 6)]);
    });

    test('全角单引号成对识别', () {
      expect(findDialogueRanges('‘甲’乙'), [(1, 2)]);
    });

    test('直角引号成对识别', () {
      expect(findDialogueRanges('「甲」『乙』'), [(1, 2), (4, 5)]);
    });

    test('半角单引号/书名号/括号不算对话', () {
      expect(findDialogueRanges('《丁》【戊】（己）'), isEmpty);
      expect(findDialogueRanges("it's a 'b'"), isEmpty);
    });

    test('未闭合引号与孤立闭符都不产出区间', () {
      expect(findDialogueRanges('“甲'), isEmpty);
      expect(findDialogueRanges('甲”'), isEmpty);
      expect(findDialogueRanges('‘甲'), isEmpty);
      expect(findDialogueRanges('甲’'), isEmpty);
      expect(findDialogueRanges('"甲'), isEmpty);
      expect(findDialogueRanges('甲"'), isEmpty);
      expect(findDialogueRanges('「甲'), isEmpty);
      expect(findDialogueRanges('甲」'), isEmpty);
    });

    test('嵌套引号与父区间合并为同一段', () {
      expect(findDialogueRanges('「他说：“你好”」'), [(1, 8)]);
      expect(findDialogueRanges('“甲“乙”丙”'), [(1, 6)]);
    });

    test('一段文本里的多段对话各自成区间', () {
      expect(findDialogueRanges('“甲”和“乙”'), [(1, 2), (5, 6)]);
    });

    test('空引号对不产出区间', () {
      expect(findDialogueRanges('“”'), isEmpty);
      expect(findDialogueRanges('‘’'), isEmpty);
      expect(findDialogueRanges('""'), isEmpty);
      expect(findDialogueRanges('「」'), isEmpty);
    });

    test('全角/半角/直角/单引号混用互不干扰', () {
      expect(
        findDialogueRanges('“甲”‘乙’"丙"「丁」'),
        [(1, 2), (4, 5), (7, 8), (10, 11)],
      );
    });
  });
}
