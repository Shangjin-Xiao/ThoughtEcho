import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/app_loading_view.dart';

Widget _buildTestApp({
  required Widget child,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      ),
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppInlineLoadingIndicator', () {
    testWidgets('内建 RepaintBoundary 图层隔离并正确包裹 CircularProgressIndicator', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const AppInlineLoadingIndicator(),
        ),
      );

      final indicatorFinder = find.byType(AppInlineLoadingIndicator);
      expect(indicatorFinder, findsOneWidget);

      final boundaryFinder = find.descendant(
        of: indicatorFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaryFinder, findsOneWidget);

      final progressFinder = find.descendant(
        of: boundaryFinder,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(progressFinder, findsOneWidget);

      final renderObject = tester.renderObject(boundaryFinder);
      expect(renderObject, isA<RenderRepaintBoundary>());
      expect((renderObject as RenderRepaintBoundary).isRepaintBoundary, isTrue);

      // 推进若干帧，验证旋转动画在独立图层内正常运转无异常
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('支持自定义尺寸、线宽与颜色并保持 RepaintBoundary 边界约束', (
      WidgetTester tester,
    ) async {
      const customSize = 24.0;
      const customStrokeWidth = 2.4;
      const customColor = Color(0xFF556677);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppInlineLoadingIndicator(
            size: customSize,
            strokeWidth: customStrokeWidth,
            color: customColor,
          ),
        ),
      );

      final sizedBoxFinder = find.descendant(
        of: find.byType(AppInlineLoadingIndicator),
        matching: find.byType(SizedBox),
      );
      expect(sizedBoxFinder, findsOneWidget);

      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.width, customSize);
      expect(sizedBox.height, customSize);

      final progress = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byType(AppInlineLoadingIndicator),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(progress.strokeWidth, customStrokeWidth);
      expect(
        progress.valueColor,
        isA<AlwaysStoppedAnimation<Color>>().having(
          (anim) => anim.value,
          'color',
          customColor,
        ),
      );
    });

    testWidgets('快速挂载与卸载时无图层残留且正常销毁', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const AppInlineLoadingIndicator(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AppInlineLoadingIndicator), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);

      // 快速卸载组件
      await tester.pumpWidget(
        _buildTestApp(
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(find.byType(AppInlineLoadingIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppLoadingView', () {
    testWidgets('根节点内建 RepaintBoundary 图层隔离', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const AppLoadingView(),
        ),
      );

      final loadingViewFinder = find.byType(AppLoadingView);
      expect(loadingViewFinder, findsOneWidget);

      final rootBoundaryFinder = find.descendant(
        of: loadingViewFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(rootBoundaryFinder, findsWidgets);

      final rootBoundaryWidget = tester.widget<RepaintBoundary>(
        rootBoundaryFinder.first,
      );
      expect(rootBoundaryWidget.child, isA<Center>());

      final renderObject = tester.renderObject(rootBoundaryFinder.first);
      expect(renderObject, isA<RenderRepaintBoundary>());
      expect((renderObject as RenderRepaintBoundary).isRepaintBoundary, isTrue);

      expect(find.byType(AppLoadingAnimation), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('附加文字说明时文字与动画均收敛在根 RepaintBoundary 防御图层内', (
      WidgetTester tester,
    ) async {
      const testMessage = '正在载入笔记...';

      await tester.pumpWidget(
        _buildTestApp(
          child: const AppLoadingView(
            message: testMessage,
          ),
        ),
      );

      final loadingViewFinder = find.byType(AppLoadingView);
      final rootBoundaryFinder = find
          .descendant(
            of: loadingViewFinder,
            matching: find.byType(RepaintBoundary),
          )
          .first;

      final textInsideBoundary = find.descendant(
        of: rootBoundaryFinder,
        matching: find.text(testMessage),
      );
      expect(textInsideBoundary, findsOneWidget);

      final textWidget = tester.widget<Text>(textInsideBoundary);
      expect(textWidget.data, testMessage);
    });

    testWidgets('在 disableAnimations: true 下静止停留且 pumpAndSettle 正常退出', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const AppLoadingView(),
          disableAnimations: true,
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(AppLoadingView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('快速挂载与卸载时正常清理无图层残留', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const AppLoadingView(message: '瞬时加载'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(AppLoadingView), findsOneWidget);

      // 瞬时完成并卸载
      await tester.pumpWidget(
        _buildTestApp(
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(find.byType(AppLoadingView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
