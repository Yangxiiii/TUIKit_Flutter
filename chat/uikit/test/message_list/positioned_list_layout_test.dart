import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('普通页面仍保存并恢复定位列表的阅读锚点', (tester) async {
    final bucket = PageStorageBucket();
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    Widget layout(bool show) => MaterialApp(
            home: PageStorage(
          bucket: bucket,
          child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 300,
                child: show
                    ? ScrollablePositionedList.builder(
                        key: const PageStorageKey('saved-records'),
                        itemCount: 30,
                        itemScrollController: controller,
                        itemPositionsListener: positions,
                        itemBuilder: (_, index) =>
                            SizedBox(height: 60, child: Text('$index')),
                      )
                    : const SizedBox.shrink(),
              )),
        ));
    await tester.pumpWidget(layout(true));
    await tester.pumpAndSettle();
    controller.jumpTo(index: 10);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ScrollablePositionedList));
    expect((bucket.readState(context) as ItemPosition).index, 10);
    // 销毁列表再挂载，验证可选存储没有破坏原页面的恢复行为。
    await tester.pumpWidget(layout(false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(layout(true));
    await tester.pumpAndSettle();
    expect(
        positions.itemPositions.value
            .any((p) => p.index == 10 && p.itemLeadingEdge.abs() < .01),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('视口随键盘缩小再恢复、消息数量增加时仍保持连续', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ItemScrollController();
    Widget layout(double height, int count) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: height,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ScrollablePositionedList.builder(
                    reverse: true,
                    shrinkWrap: true,
                    itemCount: count,
                    itemScrollController: controller,
                    initialScrollIndex: 1,
                    itemBuilder: (_, index) => SizedBox(
                      key: ValueKey('resize-$index'),
                      height: 56,
                      child: Text('$index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    for (final (height, count) in [
      (600.0, 3),
      (140.0, 3),
      (140.0, 4),
      (600.0, 4)
    ]) {
      await tester.pumpWidget(layout(height, count));
      await tester.pumpAndSettle();
      for (var index = 0; index < count - 1; index++) {
        final first = find.byKey(ValueKey('resize-$index'));
        final next = find.byKey(ValueKey('resize-${index + 1}'));
        if (first.evaluate().isEmpty || next.evaluate().isEmpty) continue;
        final a = tester.getRect(first);
        final b = tester.getRect(next);
        expect(a.top - b.bottom, closeTo(0, .01));
      }
      expect(tester.takeException(), isNull);
    }
    expect(find.byKey(const ValueKey('resize-3')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reverse in [true, false]) {
    for (final shrinkWrap in [true, false]) {
      testWidgets('恢复锚点和跳转不拆开相邻消息：reverse=$reverse，shrinkWrap=$shrinkWrap',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final count in [0, 3, 4, 12, 30]) {
          for (final anchor in count == 0 ? [0] : [0, 1, count - 1]) {
            for (final alignment in [0.0, 0.1, 0.5, 0.9]) {
              await tester.pumpWidget(const SizedBox.shrink());
              final controller = ItemScrollController();
              await tester.pumpWidget(MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 390,
                      height: 600,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ScrollablePositionedList.builder(
                          reverse: reverse,
                          shrinkWrap: shrinkWrap,
                          itemCount: count,
                          initialScrollIndex: anchor,
                          initialAlignment: alignment,
                          itemScrollController: controller,
                          itemBuilder: (_, index) => SizedBox(
                            key: ValueKey('item-$index'),
                            height: 56,
                            child: Text('$index'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ));
              await tester.pumpAndSettle();

              // 同时核对锚点两侧，防止把视口剩余高度误留在两个消息分段之间。
              void checkAdjacency() {
                for (var index = 0; index < count - 1; index++) {
                  final first = find.byKey(ValueKey('item-$index'));
                  final next = find.byKey(ValueKey('item-${index + 1}'));
                  if (first.evaluate().isEmpty || next.evaluate().isEmpty) {
                    continue;
                  }
                  final a = tester.getRect(first);
                  final b = tester.getRect(next);
                  expect(reverse ? a.top - b.bottom : b.top - a.bottom,
                      closeTo(0, .01),
                      reason:
                          'count=$count anchor=$anchor alignment=$alignment');
                }
              }

              checkAdjacency();
              if (count > 0) {
                controller.jumpTo(index: 0);
                await tester.pumpAndSettle();
                checkAdjacency();
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
