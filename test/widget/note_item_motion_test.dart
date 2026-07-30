library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/note_list/note_item_motion.dart';

/// 记录页列表项动效层的回归测试。
///
/// 这三条不变量是「增删动画反复出问题」的根因，任何改动都必须继续满足：
/// 1. 卡片宽度在动画全程不变（旧实现用 Align/SizeTransition，宽度约束被放松成
///    loose，短笔记在动画期间横向缩水、结束时又弹回整宽）。
/// 2. 动画开始和结束都不重挂载卡片子树（旧实现按需插入/移除包装层，卡片在动画
///    首帧和末帧各重建一次，Quill/图片重来一遍，体感就是动画加速或丢掉）。
/// 3. 动画播完由动效层自己回调通知，外层不靠挂钟定时器猜。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 模拟笔记卡片：宽度撑满约束、内容宽度远小于整宽，
  /// 一旦上层放松宽度约束就会明显缩水。
  Widget buildCard() {
    return Container(
      key: const ValueKey('card'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF112233),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('短'), SizedBox(height: 40)],
        ),
      ),
    );
  }

  Widget host({
    int? insertVersion,
    String insertAnimationType = 'slide',
    bool animateInsertLayout = false,
    bool isDeleting = false,
    void Function(int version)? onInsertCompleted,
    VoidCallback? onDeleteCompleted,
  }) {
    return MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            child: NoteItemMotion(
              key: const ValueKey('motion'),
              insertVersion: insertVersion,
              insertAnimationType: insertAnimationType,
              animateInsertLayout: animateInsertLayout,
              isDeleting: isDeleting,
              onInsertCompleted: onInsertCompleted ?? (_) {},
              onDeleteCompleted: onDeleteCompleted ?? () {},
              child: buildCard(),
            ),
          ),
        ),
      ),
    );
  }

  double cardWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(const ValueKey('card'))).width;

  testWidgets('结构性入场动画全程保持卡片宽度不变', (tester) async {
    await tester.pumpWidget(
      host(insertVersion: 1, animateInsertLayout: true),
    );

    // 宽度约束原样透传给子树：卡片始终撑满 400
    const expectedWidth = 400.0;
    expect(cardWidth(tester), expectedWidth);

    for (var elapsed = 0; elapsed < 250; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        cardWidth(tester),
        expectedWidth,
        reason: '入场动画第 ${elapsed + 50}ms 时卡片宽度变了',
      );
    }

    await tester.pump(const Duration(milliseconds: 50));
    expect(cardWidth(tester), expectedWidth);
  });

  testWidgets('删除折叠动画全程保持卡片宽度不变，并逐帧收缩占位高度', (tester) async {
    await tester.pumpWidget(host());
    final expectedWidth = cardWidth(tester);
    expect(expectedWidth, 400.0);
    final fullHeight = tester.getSize(find.byKey(const ValueKey('motion'))).height;
    expect(fullHeight, greaterThan(0));

    await tester.pumpWidget(host(isDeleting: true));

    var previousHeight = fullHeight;
    for (var elapsed = 0; elapsed < 280; elapsed += 40) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        cardWidth(tester),
        expectedWidth,
        reason: '删除动画第 ${elapsed + 40}ms 时卡片宽度变了',
      );
      final height =
          tester.getSize(find.byKey(const ValueKey('motion'))).height;
      expect(height, lessThanOrEqualTo(previousHeight));
      previousHeight = height;
    }

    expect(previousHeight, lessThan(fullHeight * 0.1));
  });

  testWidgets('动画开始和结束都不重挂载卡片子树', (tester) async {
    await tester.pumpWidget(host());
    final Element idleElement = tester.element(find.byKey(const ValueKey('card')));

    // 入场动画开始
    await tester.pumpWidget(host(insertVersion: 1, animateInsertLayout: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.element(find.byKey(const ValueKey('card'))),
      same(idleElement),
      reason: '入场动画开始时卡片子树被重挂载了',
    );

    // 入场动画播完，外层清理挂起状态
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(host());
    expect(
      tester.element(find.byKey(const ValueKey('card'))),
      same(idleElement),
      reason: '入场动画结束时卡片子树被重挂载了',
    );

    // 删除折叠开始
    await tester.pumpWidget(host(isDeleting: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.element(find.byKey(const ValueKey('card'))),
      same(idleElement),
      reason: '删除动画开始时卡片子树被重挂载了',
    );
  });

  testWidgets('入场与删除动画播完时回调各触发一次', (tester) async {
    final insertCompletions = <int>[];
    var deleteCompletions = 0;

    await tester.pumpWidget(
      host(
        insertVersion: 3,
        animateInsertLayout: true,
        onInsertCompleted: insertCompletions.add,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(insertCompletions, isEmpty, reason: '动画还没播完就回调了');

    await tester.pump(const Duration(milliseconds: 60));
    expect(insertCompletions, [3]);

    await tester.pumpWidget(
      host(isDeleting: true, onDeleteCompleted: () => deleteCompletions++),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(deleteCompletions, 0, reason: '折叠还没播完就回调了');

    await tester.pump(const Duration(milliseconds: 100));
    expect(deleteCompletions, 1);

    // 播完后继续 pump 不应重复回调
    await tester.pump(const Duration(milliseconds: 300));
    expect(deleteCompletions, 1);
  });

  testWidgets('撤销删除后动效层复位到静止态', (tester) async {
    await tester.pumpWidget(host(isDeleting: true));
    await tester.pump(const Duration(milliseconds: 140));

    final state = tester.state<NoteItemMotionState>(
      find.byKey(const ValueKey('motion')),
    );
    expect(state.debugHeightFactor, lessThan(1.0));
    expect(state.debugOpacity, lessThan(1.0));

    await tester.pumpWidget(host());
    await tester.pump();

    expect(state.debugHeightFactor, 1.0);
    expect(state.debugOpacity, 1.0);
  });

  testWidgets('animationType 为 none 时不播入场动画但动效层照常挂载', (tester) async {
    final insertCompletions = <int>[];
    await tester.pumpWidget(
      host(
        insertVersion: 1,
        insertAnimationType: 'none',
        animateInsertLayout: true,
        onInsertCompleted: insertCompletions.add,
      ),
    );

    final state = tester.state<NoteItemMotionState>(
      find.byKey(const ValueKey('motion')),
    );
    expect(state.debugOpacity, 1.0);
    expect(state.debugHeightFactor, 1.0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(insertCompletions, isEmpty);
  });
}
