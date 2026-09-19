import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/ui/common/dialogs.dart';

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => inputDialog(ctx, title: '标题'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // 用标题文本代表弹窗本体（外层包装盒被路由拉成全窗尺寸，不可测）。
  Rect titleRect(WidgetTester tester) => tester.getRect(find.text('标题'));

  testWidgets('拖动可移动弹窗且不越出窗口边界', (tester) async {
    await openDialog(tester);

    // 向右下拖动 2000px：应被钳制在窗口内（右下角不越界）。
    await tester.drag(find.text('标题'), const Offset(2000, 2000));
    await tester.pump();
    var rect = titleRect(tester);
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));

    // 向左上拖动 2000px：应被钳制在窗口内（左上角不越界）。
    await tester.drag(find.text('标题'), const Offset(-2000, -2000));
    await tester.pump();
    rect = titleRect(tester);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('普通幅度拖动可以移动弹窗', (tester) async {
    await openDialog(tester);
    final before = titleRect(tester);

    await tester.drag(find.text('标题'), const Offset(80, 60));
    await tester.pump();
    final after = titleRect(tester);

    expect(after.left - before.left, moreOrLessEquals(80, epsilon: 1));
    expect(after.top - before.top, moreOrLessEquals(60, epsilon: 1));
  });

  testWidgets('新建/编辑作品弹窗宽度为 320', (tester) async {
    for (final open in [
      (BuildContext ctx) => createBookDialog(ctx),
      (BuildContext ctx) => editBookDialog(ctx,
          bookId: 'b1',
          initialTitle: 't',
          initialPenName: '',
          initialCoverPath: ''),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => open(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // AlertDialog 内部的 Material 即弹窗本体，宽度应为 320。
      final material = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getRect(material).width, moreOrLessEquals(320, epsilon: 1));

      // 关闭弹窗，避免遮挡下一轮循环的 open 按钮。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
  });
}
