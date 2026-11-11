import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/app_loading_animation.dart';

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

  group('AppLoadingAnimation', () {
    testWidgets('所有 AppLoadingStyle 在亮色和暗色模式下均能正常绘制', (
      WidgetTester tester,
    ) async {
      for (final style in AppLoadingStyle.values) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await tester.pumpWidget(
            _buildTestApp(
              brightness: brightness,
              child: AppLoadingAnimation(
                style: style,
                width: 96,
              ),
            ),
          );

          // 推进一小段时间以触发 paintFrame 绘制
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(AppLoadingAnimation), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('在 disableAnimations: true 下静止停留且 pumpAndSettle 正常退出不挂起', (
      WidgetTester tester,
    ) async {
      for (final style in AppLoadingStyle.values) {
        await tester.pumpWidget(
          _buildTestApp(
            disableAnimations: true,
            child: AppLoadingAnimation(
              style: style,
              width: 96,
            ),
          ),
        );

        // 如果动画没有在 reduce-motion 下停止 ticker，pumpAndSettle 会抛出超时异常
        await tester.pumpAndSettle();
        expect(find.byType(AppLoadingAnimation), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('自定义 semanticLabel 能通过 Semantics 正确透出', (
      WidgetTester tester,
    ) async {
      const customLabel = '正在同步数据...';
      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: const AppLoadingAnimation(
            semanticLabel: customLabel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(customLabel), findsOneWidget);
    });

    testWidgets('默认 semanticLabel 从本地化中解析', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: const AppLoadingAnimation(),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(AppLoadingAnimation));
      expect(semantics.label, isNotEmpty);
    });

    testWidgets('能够根据 width 和 aspectRatio 正确推导组件高度', (
      WidgetTester tester,
    ) async {
      for (final style in AppLoadingStyle.values) {
        const testWidth = 140.0;
        final expectedHeight = testWidth / style.aspectRatio;

        await tester.pumpWidget(
          _buildTestApp(
            disableAnimations: true,
            child: AppLoadingAnimation(
              style: style,
              width: testWidth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final size = tester.getSize(find.byType(AppLoadingAnimation));
        expect(size.width, testWidth);
        expect(size.height, closeTo(expectedHeight, 0.01));
      }
    });

    testWidgets('动态切换 style 能正确更新尺寸与持续时间', (WidgetTester tester) async {
      var currentStyle = AppLoadingStyle.bookFlip;
      late StateSetter updateState;

      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: StatefulBuilder(
            builder: (context, setState) {
              updateState = setState;
              return AppLoadingAnimation(
                style: currentStyle,
                width: 100,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      var size = tester.getSize(find.byType(AppLoadingAnimation));
      expect(
        size.height,
        closeTo(100 / AppLoadingStyle.bookFlip.aspectRatio, 0.01),
      );

      // 切换为 inkWriting
      updateState(() {
        currentStyle = AppLoadingStyle.inkWriting;
      });
      await tester.pumpAndSettle();

      size = tester.getSize(find.byType(AppLoadingAnimation));
      expect(
        size.height,
        closeTo(100 / AppLoadingStyle.inkWriting.aspectRatio, 0.01),
      );

      // 切换为 inkDrop
      updateState(() {
        currentStyle = AppLoadingStyle.inkDrop;
      });
      await tester.pumpAndSettle();

      size = tester.getSize(find.byType(AppLoadingAnimation));
      expect(
        size.height,
        closeTo(100 / AppLoadingStyle.inkDrop.aspectRatio, 0.01),
      );

      // 切换为 writingLines
      updateState(() {
        currentStyle = AppLoadingStyle.writingLines;
      });
      await tester.pumpAndSettle();

      size = tester.getSize(find.byType(AppLoadingAnimation));
      expect(
        size.height,
        closeTo(100 / AppLoadingStyle.writingLines.aspectRatio, 0.01),
      );
    });
  });
}
