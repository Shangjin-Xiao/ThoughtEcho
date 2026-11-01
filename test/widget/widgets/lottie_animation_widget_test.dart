import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/lottie_config.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/common/lottie_animation_widget.dart';

Widget _buildLocalizedWidget({
  required Widget child,
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LottieAnimationWithText 国际化文案渲染', () {
    testWidgets('在中文环境下正确渲染各预设场景的中文描述', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('zh'),
          child: const LottieAnimationWithText(
            scene: LottieScene.searchLoading,
          ),
        ),
      );
      expect(find.text('搜索中...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('zh'),
          child: const LottieAnimationWithText(
            scene: LottieScene.weatherSearchLoading,
          ),
        ),
      );
      expect(find.text('天气搜索中...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('zh'),
          child: const LottieAnimationWithText(
            scene: LottieScene.customLoading,
          ),
        ),
      );
      expect(find.text('加载中...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('zh'),
          child: const LottieAnimationWithText(
            scene: LottieScene.notFound,
          ),
        ),
      );
      expect(find.text('未找到相关内容'), findsOneWidget);
    });

    testWidgets('在英文环境下正确渲染各预设场景的英文描述', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('en'),
          child: const LottieAnimationWithText(
            scene: LottieScene.searchLoading,
          ),
        ),
      );
      expect(find.text('Searching...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('en'),
          child: const LottieAnimationWithText(
            scene: LottieScene.weatherSearchLoading,
          ),
        ),
      );
      expect(find.text('Searching weather...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('en'),
          child: const LottieAnimationWithText(
            scene: LottieScene.customLoading,
          ),
        ),
      );
      expect(find.text('Loading...'), findsOneWidget);

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('en'),
          child: const LottieAnimationWithText(
            scene: LottieScene.notFound,
          ),
        ),
      );
      expect(find.text('No content found'), findsOneWidget);
    });

    testWidgets('显式指定 text 参数时优先使用自定义文本而不覆盖', (WidgetTester tester) async {
      const customText = 'Custom In-Flight Operation';

      await tester.pumpWidget(
        _buildLocalizedWidget(
          locale: const Locale('en'),
          child: const LottieAnimationWithText(
            scene: LottieScene.searchLoading,
            text: customText,
          ),
        ),
      );

      expect(find.text(customText), findsOneWidget);
      expect(find.text('Searching...'), findsNothing);
      expect(find.text('搜索中...'), findsNothing);
    });

    testWidgets('缺失 AppLocalizations 时优雅回退至默认描述且不抛异常',
        (WidgetTester tester) async {
      // 在没有配置 AppLocalizations.localizationsDelegates 的裸 MaterialApp 中渲染
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: LottieAnimationWithText(
                scene: LottieScene.searchLoading,
              ),
            ),
          ),
        ),
      );

      // 应安全回退到默认预设描述 "搜索中..."
      expect(find.text('搜索中...'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('自定义 textStyle 与间距正确生效', (WidgetTester tester) async {
      const customStyle = TextStyle(fontSize: 18.0, color: Color(0xFF123456));

      await tester.pumpWidget(
        _buildLocalizedWidget(
          child: const LottieAnimationWithText(
            scene: LottieScene.customLoading,
            textStyle: customStyle,
            spacing: 24.0,
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('加载中...'));
      expect(textWidget.style?.fontSize, equals(18.0));
      expect(textWidget.style?.color, equals(const Color(0xFF123456)));

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final spacingBox = sizedBoxes.firstWhere((box) => box.height == 24.0);
      expect(spacingBox.height, equals(24.0));
    });
  });
}
