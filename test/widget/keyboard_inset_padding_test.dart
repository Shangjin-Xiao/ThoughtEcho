import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/add_note_dialog_parts.dart';

void main() {
  testWidgets('reports keyboard inset during build', (tester) async {
    final reportedInsets = <double>[];

    Widget buildWithInset(double bottomInset) {
      return MediaQuery(
        data: MediaQueryData(
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: KeyboardInsetPadding(
            onInsetBuild: reportedInsets.add,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildWithInset(0));
    await tester.pumpWidget(buildWithInset(240));

    expect(reportedInsets, containsAllInOrder(<double>[0, 240]));
  });

  testWidgets('holds the last inset while the route is leaving',
      (tester) async {
    final reportedInsets = <double>[];
    double bottomInset = 240;
    late StateSetter setInset;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => StatefulBuilder(
                  builder: (context, setState) {
                    setInset = setState;
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        viewInsets: EdgeInsets.only(bottom: bottomInset),
                      ),
                      child: KeyboardInsetPadding(
                        onInsetBuild: reportedInsets.add,
                        child: const SizedBox(width: 100, height: 100),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(reportedInsets.last, 240);

    // 退场和键盘收起同时发生：inset 塌到 0，但内边距必须停在 240，
    // 否则弹窗会先瞬移一个键盘的高度，下滑动画就没了。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    bottomInset = 0;
    setInset(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(reportedInsets.last, 240);

    await tester.pumpAndSettle();
  });

  testWidgets('does not resurrect a keyboard dismissed before the pop',
      (tester) async {
    final reportedInsets = <double>[];
    double bottomInset = 240;
    late StateSetter setInset;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => StatefulBuilder(
                  builder: (context, setState) {
                    setInset = setState;
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        viewInsets: EdgeInsets.only(bottom: bottomInset),
                      ),
                      child: KeyboardInsetPadding(
                        onInsetBuild: reportedInsets.add,
                        child: const SizedBox(width: 100, height: 100),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(reportedInsets.last, 240);

    // 用户先自己收了键盘：弹窗早就按 inset=0 重排完了。
    bottomInset = 0;
    setInset(() {});
    await tester.pumpAndSettle();
    expect(reportedInsets.last, 0);

    // 此时再关闭，冻结的必须是 0。若改成「冻结最后一次非零 inset」，
    // 退场一开始弹窗会凭空长高一个键盘，反而是更糟的跳变。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    setInset(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(reportedInsets.last, 0);

    await tester.pumpAndSettle();
  });
}
