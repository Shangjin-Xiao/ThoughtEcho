import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/ask_user_card.dart';

Widget _buildTestApp(Widget child) {
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('AskUserCard Widget 测试', () {
    testWidgets('正常展示标题、问题与选项', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        const AskUserCard(
          header: '分类确认',
          question: '你想创建哪种类型的笔记？',
          options: ['工作复盘', '生活随笔', '读书随笔'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('分类确认'), findsOneWidget);
      expect(find.text('你想创建哪种类型的笔记？'), findsOneWidget);
      expect(find.text('工作复盘'), findsOneWidget);
      expect(find.text('生活随笔'), findsOneWidget);
      expect(find.text('读书随笔'), findsOneWidget);
      expect(find.text('单选'), findsOneWidget);
    });

    testWidgets('单选模式下切换选项并提交', (tester) async {
      List<String>? submittedOptions;
      String? submittedCustom;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          question: '请选择分类',
          options: const ['A', 'B'],
          onSubmit: ({required selectedOptions, customText}) {
            submittedOptions = selectedOptions;
            submittedCustom = customText;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 初始未选时确定按钮禁用
      final confirmButtonFinder = find.widgetWithText(FilledButton, '确定');
      expect(
          tester.widget<FilledButton>(confirmButtonFinder).onPressed, isNull);

      // 点击选项 A
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirmButtonFinder).onPressed,
          isNotNull);

      // 切换到选项 B
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      // 点击确定
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(submittedOptions, ['B']);
      expect(submittedCustom, isNull);
    });

    testWidgets('多选模式下选择多个选项并提交', (tester) async {
      List<String>? submittedOptions;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          question: '可多选标签',
          options: const ['标签1', '标签2', '标签3'],
          multiSelect: true,
          onSubmit: ({required selectedOptions, customText}) {
            submittedOptions = selectedOptions;
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('可多选'), findsOneWidget);

      await tester.tap(find.text('标签1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标签3'));
      await tester.pumpAndSettle();

      final confirmButtonFinder = find.widgetWithText(FilledButton, '确定');
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(submittedOptions, containsAll(['标签1', '标签3']));
      expect(submittedOptions?.length, 2);
    });

    testWidgets('自定义文本输入与提交', (tester) async {
      String? submittedCustom;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          question: '请选择或输入',
          options: const ['A', 'B'],
          onSubmit: ({required selectedOptions, customText}) {
            submittedCustom = customText;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 输入自定义文本
      await tester.enterText(find.byType(TextField), '自定义笔记主题');
      await tester.pumpAndSettle();

      final confirmButtonFinder = find.widgetWithText(FilledButton, '确定');
      expect(tester.widget<FilledButton>(confirmButtonFinder).onPressed,
          isNotNull);

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(submittedCustom, '自定义笔记主题');
    });

    testWidgets('点击取消按钮调用 onCancel 回调', (tester) async {
      var cancelled = false;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          question: '是否确认？',
          options: const ['是', '否'],
          onCancel: () {
            cancelled = true;
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('已完成状态正确展示已选选项与摘要，隐藏交互控件', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        const AskUserCard(
          question: '风格选择',
          options: ['纸墨', '素笺'],
          isCompleted: true,
          selectedOptions: ['纸墨'],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已选择：'), findsOneWidget);
      expect(find.text('纸墨'), findsOneWidget);
      // 输入框与确定按钮不应在已完成状态出现
      expect(find.byType(TextField), findsNothing);
      expect(find.text('确定'), findsNothing);
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('已取消状态正确展示已取消标识', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        const AskUserCard(
          question: '风格选择',
          options: ['纸墨', '素笺'],
          isCompleted: true,
          isCancelled: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已取消选择'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('已完成状态正确展示自定义回复', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        const AskUserCard(
          question: '风格选择',
          options: ['纸墨', '素笺'],
          isCompleted: true,
          customText: '我想用深色素笺',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('自定义回复：我想用深色素笺'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
