import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/feature_guide.dart';
import 'package:thoughtecho/widgets/feature_guide_popover.dart';

void main() {
  Widget buildTestableWidget({required Widget child}) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox.expand(
          child: Stack(
            children: [child],
          ),
        ),
      ),
    );
  }

  testWidgets('当目标 Widget 被从树中移除时，Popover 在 PostFrame 回调中自动关闭',
      (WidgetTester tester) async {
    final targetKey = GlobalKey();
    bool dismissed = false;

    const guide = FeatureGuide(
      id: 'homepage_daily_quote',
      title: '每日一言',
      description: '点击切换不同语言及来源',
    );

    late StateSetter parentSetState;

    bool showTarget = true;

    await tester.pumpWidget(
      buildTestableWidget(
        child: StatefulBuilder(
          builder: (context, setState) {
            parentSetState = setState;
            return Stack(
              children: [
                if (showTarget)
                  Positioned(
                    top: 100,
                    left: 100,
                    child: Container(
                      key: targetKey,
                      width: 100,
                      height: 50,
                      color: Colors.blue,
                    ),
                  ),
                Positioned.fill(
                  child: FeatureGuidePopover(
                    guide: FeatureGuide(
                      id: guide.id,
                      title: guide.title,
                      description: guide.description,
                      targetKey: targetKey,
                    ),
                    autoDismissDuration: const Duration(seconds: 10),
                    onDismiss: () {
                      dismissed = true;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FeatureGuidePopover), findsOneWidget);
    expect(dismissed, isFalse);

    // 移除目标 Widget 并触发重绘
    parentSetState(() {
      showTarget = false;
    });

    // 绘制移除 target 的这一帧
    await tester.pump();
    // 渲染完成后，PostFrameCallback 在下一帧检查 RenderBox 并自动触发 _handleDismiss 动画
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('当 visibilityPredicate 返回 false 时，Popover 在 PostFrame 回调中自动关闭',
      (WidgetTester tester) async {
    bool isVisible = true;
    bool dismissed = false;

    const guide = FeatureGuide(
      id: 'homepage_daily_quote',
      title: '每日一言',
      description: '点击切换',
    );

    late StateSetter parentSetState;

    await tester.pumpWidget(
      buildTestableWidget(
        child: StatefulBuilder(
          builder: (context, setState) {
            parentSetState = setState;
            return Positioned.fill(
              child: FeatureGuidePopover(
                guide: guide,
                visibilityPredicate: () => isVisible,
                autoDismissDuration: const Duration(seconds: 10),
                onDismiss: () {
                  dismissed = true;
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FeatureGuidePopover), findsOneWidget);
    expect(dismissed, isFalse);

    // 改变可见性谓词条件并触发重绘
    parentSetState(() {
      isVisible = false;
    });

    await tester.pump();
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('界面静止且目标有效时 Popover 正常保持显示', (WidgetTester tester) async {
    final targetKey = GlobalKey();
    bool dismissed = false;

    const guide = FeatureGuide(
      id: 'homepage_daily_quote',
      title: '每日一言',
      description: '点击切换',
    );

    await tester.pumpWidget(
      buildTestableWidget(
        child: Stack(
          children: [
            Positioned(
              top: 50,
              left: 50,
              child: SizedBox(
                key: targetKey,
                width: 100,
                height: 50,
              ),
            ),
            Positioned.fill(
              child: FeatureGuidePopover(
                guide: FeatureGuide(
                  id: guide.id,
                  title: guide.title,
                  description: guide.description,
                  targetKey: targetKey,
                ),
                autoDismissDuration: const Duration(seconds: 5),
                onDismiss: () {
                  dismissed = true;
                },
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FeatureGuidePopover), findsOneWidget);
    expect(dismissed, isFalse);
  });

  testWidgets('静止闲置时通过 500ms 兜底定时器检测 visibilityPredicate 改变并自动关闭',
      (WidgetTester tester) async {
    bool isVisible = true;
    bool dismissed = false;

    const guide = FeatureGuide(
      id: 'homepage_daily_quote',
      title: '每日一言',
      description: '点击切换',
    );

    await tester.pumpWidget(
      buildTestableWidget(
        child: FeatureGuidePopover(
          guide: guide,
          visibilityPredicate: () => isVisible,
          autoDismissDuration: const Duration(seconds: 10),
          onDismiss: () {
            dismissed = true;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(FeatureGuidePopover), findsOneWidget);
    expect(dismissed, isFalse);

    // 在静止无重绘的情况下修改 predicate
    isVisible = false;

    // 推进 500ms 触发 fallback 定时器（不依赖 setState/pump 重绘新帧）
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets(
      '当 targetKey.currentContext 在 findRenderObject 抛出异常时在 _findTargetRenderBox 中捕获日志并降级居中显示',
      (WidgetTester tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      buildTestableWidget(
        child: Stack(
          children: [
            _ThrowingWidget(key: key),
            FeatureGuidePopover(
              guide: FeatureGuide(
                id: 'test_guide',
                title: '测试标题',
                description: '测试描述',
                targetKey: key,
              ),
              autoDismissDuration: const Duration(seconds: 10),
              onDismiss: () {},
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 应当安全捕获异常，降级显示 Popover，页面不崩溃
    expect(find.byType(FeatureGuidePopover), findsOneWidget);
  });
}

class _ThrowingWidget extends Widget {
  const _ThrowingWidget({super.key});

  @override
  Element createElement() => _ThrowingElement(this);
}

class _ThrowingElement extends ComponentElement {
  _ThrowingElement(super.widget);

  @override
  Widget build() => const SizedBox.shrink();

  @override
  RenderObject? findRenderObject() {
    throw StateError('Simulated findRenderObject failure');
  }
}
