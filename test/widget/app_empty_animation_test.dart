import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/app_empty_animation.dart';

Widget _buildTestApp({
  required Widget child,
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      ),
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppEmptyAnimation', () {
    testWidgets('所有 AppEmptyStyle 在亮色和暗色下走完一整圈均无绘制异常', (tester) async {
      for (final style in AppEmptyStyle.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            _buildTestApp(
              brightness: brightness,
              child: AppEmptyAnimation(style: style, width: 96),
            ),
          );
          // 分段推进覆盖扫行、摇头、首尾淡入淡出各阶段。
          for (var i = 0; i < 12; i++) {
            await tester.pump(style.period ~/ 12);
            expect(tester.takeException(), isNull);
          }
        }
      }
    });

    testWidgets('减少动态效果时停在静止帧，pumpAndSettle 能正常结束', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: const AppEmptyAnimation(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('高度按 width 与内容框宽高比推导', (tester) async {
      for (final style in AppEmptyStyle.values) {
        await tester.pumpWidget(
          _buildTestApp(
            disableAnimations: true,
            child: AppEmptyAnimation(style: style, width: 140),
          ),
        );
        final size = tester.getSize(find.byType(AppEmptyAnimation));
        expect(size.width, 140);
        expect(size.height, closeTo(140 / style.aspectRatio, 0.01));
      }
    });

    testWidgets('未传 semanticLabel 时作为装饰排除在语义树外', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: const AppEmptyAnimation(),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AppEmptyAnimation),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('传入 semanticLabel 时可被读屏找到', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildTestApp(
          disableAnimations: true,
          child: const AppEmptyAnimation(semanticLabel: '没有找到相关内容'),
        ),
      );
      expect(find.bySemanticsLabel('没有找到相关内容'), findsOneWidget);
      handle.dispose();
    });
  });
}
