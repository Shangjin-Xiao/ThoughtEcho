import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/smart_result_card.dart';

Widget _buildTestWidget(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('SmartResultCard', () {
    testWidgets('displays metadata preview chips', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          SmartResultCard(
            title: 'AI 建议',
            content: '建议内容',
            author: '鲁迅',
            source: '《呐喊》',
            tagNames: const ['文学', '经典'],
            locationPreview: '北京市·东城区',
            weatherPreview: '晴朗 25°C',
            initialIncludeLocation: true,
            initialIncludeWeather: true,
            editorSource: 'new_note',
            onSaveDirectly: (_, __) {},
            onOpenInEditor: (_, __) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 建议'), findsOneWidget);
      expect(find.text('建议内容'), findsOneWidget);
      // 作者和出处
      expect(find.text('鲁迅'), findsOneWidget);
      expect(find.text('《呐喊》'), findsOneWidget);
      // 标签
      expect(find.text('文学'), findsOneWidget);
      expect(find.text('经典'), findsOneWidget);
      // 位置和天气预览
      expect(find.text('北京市·东城区'), findsOneWidget);
      expect(find.text('晴朗 25°C'), findsOneWidget);
    });

    testWidgets('does not display metadata when not provided', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          SmartResultCard(
            title: 'AI 建议',
            content: '建议内容',
            editorSource: 'new_note',
            onSaveDirectly: (_, __) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 建议'), findsOneWidget);
      expect(find.text('建议内容'), findsOneWidget);
      // 没有作者、出处、标签、位置天气
      expect(find.text('鲁迅'), findsNothing);
      expect(find.text('文学'), findsNothing);
      expect(find.text('北京市·东城区'), findsNothing);
    });

    testWidgets('toggles location and weather chips', (tester) async {
      var savedLocation = false;
      var savedWeather = false;

      await tester.pumpWidget(
        _buildTestWidget(
          SmartResultCard(
            title: 'AI 建议',
            content: '建议内容',
            editorSource: 'new_note',
            initialIncludeLocation: false,
            initialIncludeWeather: false,
            onSaveDirectly: (loc, weather) {
              savedLocation = loc;
              savedWeather = weather;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认未选中
      expect(find.byType(FilterChip), findsNWidgets(2));

      // 点击位置 chip
      await tester.tap(find.byType(FilterChip).first);
      await tester.pumpAndSettle();

      // 点击直接保存按钮（通过图标定位）
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(savedLocation, isTrue);
      expect(savedWeather, isFalse);
    });
  });
}
