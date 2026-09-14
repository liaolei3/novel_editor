import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_editor/ui/common/long_press_drag_listener.dart';

void main() {
  testWidgets('row long press drags item to reorder', (tester) async {
    List<String> items = ['A', 'B', 'C'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    items.insert(newIndex, items.removeAt(oldIndex));
                  });
                },
                itemBuilder: (context, i) => LongPressDragStartListener(
                  key: ValueKey(items[i]),
                  index: i,
                  child: ListTile(dense: true, title: Text(items[i])),
                ),
              );
            },
          ),
        ),
      ),
    );

    // 长按第一行（带轻微抖动，模拟真实鼠标/RDP 环境），随后向下拖过第二项。
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(4, 1));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(items, ['B', 'A', 'C']);
  });
}
