import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
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

AskUserQuestion _question(
  String question, {
  String? header,
  required List<String> options,
  Map<String, String> descriptions = const {},
  bool multiSelect = false,
}) {
  return AskUserQuestion(
    question: question,
    header: header,
    options: [
      for (final label in options)
        AskUserOption(label: label, description: descriptions[label] ?? ''),
    ],
    multiSelect: multiSelect,
  );
}

void main() {
  group('AskUserCard Widget 测试', () {
    testWidgets('正常展示 Thoughter 标题、问题与纵向选项', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question(
              '你想创建哪种类型的笔记？',
              header: '分类确认',
              options: ['工作复盘', '生活随笔', '读书随笔'],
              descriptions: {'工作复盘': '记录项目得失'},
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Thoughter 有一个问题'), findsOneWidget);
      expect(find.text('分类确认'), findsOneWidget);
      expect(find.text('你想创建哪种类型的笔记？'), findsOneWidget);
      expect(find.text('工作复盘'), findsOneWidget);
      expect(find.text('记录项目得失'), findsOneWidget);
      expect(find.text('生活随笔'), findsOneWidget);
      expect(find.text('单选'), findsOneWidget);
      // 纵向整宽行：不再使用横向 FilterChip
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(Radio<String?>), findsNWidgets(4));
    });

    testWidgets('多问题向导只展示第一题与进度', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一问？', options: ['A', 'B']),
            _question('第二问？', options: ['C', 'D'], multiSelect: true),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Thoughter 有 2 个问题'), findsOneWidget);
      expect(find.text('问题 1/2'), findsOneWidget);
      // 一次只展示一题，第二题尚未出现
      expect(find.text('第一问？'), findsOneWidget);
      expect(find.text('第二问？'), findsNothing);
      expect(find.byType(Radio<String?>), findsNWidgets(3));
      expect(find.byType(Checkbox), findsNothing);
      // 未作答时继续按钮禁用
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '继续')),
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '继续'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('单选模式下切换选项并提交', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('请选择分类', options: ['A', 'B'])
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
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

      expect(submitted?.length, 1);
      expect(submitted?.first.selectedOptions, ['B']);
      expect(submitted?.first.customText, isNull);
    });

    testWidgets('多选模式下选择多个选项并提交', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('可多选标签',
                options: ['标签1', '标签2', '标签3'], multiSelect: true),
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
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

      expect(submitted?.first.selectedOptions, containsAll(['标签1', '标签3']));
      expect(submitted?.first.selectedOptions.length, 2);
    });

    testWidgets('输入自定义文本自动切换为手输选项，切换回预设选项不抹除手输文本', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('请选择或输入', options: ['A', 'B'])
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 先选 A
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        'A',
      );

      // 输入自定义文本：单选自动选中手输选项
      await tester.enterText(find.byType(TextField), '自定义笔记主题');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        '__custom_option__',
      );

      // 切换到预设选项 B：单选切换为 B，但手输文本不被清空
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        'B',
      );
      expect(find.text('自定义笔记主题'), findsOneWidget);

      // 提交时由于当前选的是 B，只提交选项 B，不提交手输文本
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(submitted?.first.selectedOptions, ['B']);
      expect(submitted?.first.customText, isNull);
    });

    testWidgets('切换回手输选项保留已输文本并可正常提交', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('请选择或输入', options: ['A', 'B'])
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '手输内容');
      await tester.pumpAndSettle();
      expect(find.text('手输内容'), findsOneWidget);

      // 切换到选项 B
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.text('手输内容'), findsOneWidget);

      // 再次点击手输选项所在的输入框，切回手输选项
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        '__custom_option__',
      );

      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(submitted?.first.selectedOptions, isEmpty);
      expect(submitted?.first.customText, '手输内容');
    });

    testWidgets('手输选项未输入文字时确定按钮禁用，输入文字后启用', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('请选择或输入', options: ['A', 'B'])
          ],
        ),
      ));
      await tester.pumpAndSettle();

      final confirmBtn = find.widgetWithText(FilledButton, '确定');
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

      // 点击手输选项行对应的 Radio
      await tester.tap(find.byType(Radio<String?>).last);
      await tester.pumpAndSettle();
      // 虽已选中手输选项，但输入框文字为空，确定按钮仍应禁用
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

      // 输入文字后启用
      await tester.enterText(find.byType(TextField), '有效回复');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);

      // 清空文字后重新禁用
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
    });

    testWidgets('向导单选点选后不自动前进，需手动点击继续', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一问？', options: ['A', 'B']),
            _question('第二问？', options: ['C', 'D']),
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 点选 A 后停留在第一题，不自动进入第二题
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(find.text('第一问？'), findsOneWidget);
      expect(find.text('第二问？'), findsNothing);
      expect(find.text('问题 1/2'), findsOneWidget);

      // 手动点击「继续」进入第二题
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('第一问？'), findsNothing);
      expect(find.text('第二问？'), findsOneWidget);
      expect(find.text('问题 2/2'), findsOneWidget);

      // 上一步返回，第一题的 A 仍然选中
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('第一问？'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        'A',
      );

      // 继续回到第二题，点选 D，停留在第二题
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('D'));
      await tester.pumpAndSettle();
      expect(find.text('第二问？'), findsOneWidget);

      // 手动点击「继续」进入总览页
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('确认你的回答'), findsOneWidget);
      expect(find.text('第一问？'), findsOneWidget);
      expect(find.text('第二问？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '提交全部'));
      await tester.pumpAndSettle();

      expect(submitted?.length, 2);
      expect(submitted?[0].selectedOptions, ['A']);
      expect(submitted?[1].selectedOptions, ['D']);
    });

    testWidgets('向导多选与自定义输入走继续按钮前进', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('多选题？', options: ['M1', 'M2', 'M3'], multiSelect: true),
            _question('问答题？', options: ['X', 'Y']),
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 多选点选不自动前进，手动继续
      await tester.tap(find.text('M1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3'));
      await tester.pumpAndSettle();
      expect(find.text('多选题？'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      // 第二题手输自定义后继续，进入总览并提交
      expect(find.text('问答题？'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '手写答案');
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('确认你的回答'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '提交全部'));
      await tester.pumpAndSettle();

      expect(submitted?.length, 2);
      expect(submitted?[0].selectedOptions, containsAll(['M1', 'M3']));
      expect(submitted?[1].selectedOptions, isEmpty);
      expect(submitted?[1].customText, '手写答案');
    });

    testWidgets('多选模式下手输选项可与预设选项同时勾选并一并提交', (tester) async {
      List<AskUserAnswer>? submitted;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('可多选标签', options: ['标签1', '标签2'], multiSelect: true),
          ],
          onSubmit: ({required answers}) {
            submitted = answers;
          },
        ),
      ));
      await tester.pumpAndSettle();

      // 勾选标签1
      await tester.tap(find.text('标签1'));
      await tester.pumpAndSettle();

      // 勾选手输选项并输入内容
      await tester.enterText(find.byType(TextField), '补充标签');
      await tester.pumpAndSettle();

      // 此时既勾选了标签1，又勾选了手输选项
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();

      expect(submitted?.first.selectedOptions, ['标签1']);
      expect(submitted?.first.customText, '补充标签');
    });

    testWidgets('向导总览页可回跳修改答案', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一问？', options: ['A', 'B']),
            _question('第二问？', options: ['C', 'D']),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('确认你的回答'), findsOneWidget);

      // 点第一行的修改回到第一题，改选 B 后手动点击继续回到第二题，再继续回总览
      await tester.tap(find.text('修改').first);
      await tester.pumpAndSettle();
      expect(find.text('第一问？'), findsOneWidget);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('第二问？'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('确认你的回答'), findsOneWidget);
    });

    testWidgets('向导跳题留下未作答时总览禁用提交并提示', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一问？', options: ['A', 'B']),
            _question('第二问？', options: ['C', 'D']),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      // 通过进度段直接跳到第二题，第一题留空
      await tester.tap(find.byType(InkWell).at(1));
      await tester.pumpAndSettle();
      expect(find.text('第二问？'), findsOneWidget);
      await tester.tap(find.text('D'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('确认你的回答'), findsOneWidget);
      expect(find.text('未作答'), findsOneWidget);
      expect(find.text('还有问题没回答'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交全部'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('点击取消按钮调用 onCancel 回调', (tester) async {
      var cancelled = false;

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('是否确认？', options: ['是', '否'])
          ],
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

    testWidgets('已完成状态正确展示已选选项，隐藏交互控件', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('风格选择', options: ['纸墨', '素笺'])
          ],
          isCompleted: true,
          completedAnswers: const [
            AskUserAnswer(selectedOptions: ['纸墨']),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Thoughter 有一个问题'), findsOneWidget);
      expect(find.text('已选择：'), findsOneWidget);
      expect(find.text('纸墨'), findsOneWidget);
      // 输入框与确定按钮不应在已完成状态出现
      expect(find.byType(TextField), findsNothing);
      expect(find.text('确定'), findsNothing);
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('已取消状态正确展示已取消标识', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('风格选择', options: ['纸墨', '素笺'])
          ],
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
        AskUserCard(
          questions: [
            _question('风格选择', options: ['纸墨', '素笺'])
          ],
          isCompleted: true,
          completedAnswers: const [
            AskUserAnswer(customText: '我想用深色素笺'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('自定义回复：我想用深色素笺'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('已完成多问题中未作答的问题展示未作答', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一问？', options: ['A', 'B']),
            _question('第二问？', options: ['C', 'D']),
          ],
          isCompleted: true,
          completedAnswers: const [
            AskUserAnswer(selectedOptions: ['A']),
            AskUserAnswer(),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Thoughter 有 2 个问题'), findsOneWidget);
      expect(find.text('未作答'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('已完成但无任何答案时作为取消状态展示', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('风格选择', options: ['纸墨', '素笺'])
          ],
          isCompleted: true,
          completedAnswers: const [],
        ),
      ));
      await tester.pumpAndSettle();

      // 应当展示取消态，而不是错误地展示绿勾与“确定”
      expect(find.text('已取消选择'), findsOneWidget);
      expect(find.text('确定'), findsNothing);
    });

    testWidgets('didUpdateWidget 正常同步外部初始答案变更', (tester) async {
      AskUserQuestion question() => _question('测试变更', options: ['A', 'B']);

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [question()],
          initialAnswers: const [
            AskUserAnswer(selectedOptions: ['A'], customText: '旧备注'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('旧备注'), findsOneWidget);

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [question()],
          initialAnswers: const [
            AskUserAnswer(selectedOptions: ['B'], customText: '新备注'),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('新备注'), findsOneWidget);
      // 外部初始答案被同步：B 选中（历史数据里选项与自定义可共存，原样呈现）
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        'B',
      );
    });

    testWidgets('外部初始答案不变时保留用户自己的选择', (tester) async {
      const initial = [
        AskUserAnswer(selectedOptions: ['A']),
      ];
      AskUserQuestion question() => _question('保持选择', options: ['A', 'B']);

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [question()],
          initialAnswers: initial,
        ),
      ));
      await tester.pumpAndSettle();

      // 用户在界面上改选 B
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      // 外部因滚动重建传入内容相同的全新实例
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [question()],
          initialAnswers: List<AskUserAnswer>.from(initial),
        ),
      ));
      await tester.pumpAndSettle();

      // 用户的选择 B 不应被回滚
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        'B',
      );
    });

    testWidgets('问题列表变化时重建草稿', (tester) async {
      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第一组？', options: ['A', 'B'])
          ],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_buildTestApp(
        AskUserCard(
          questions: [
            _question('第二组？', options: ['C', 'D'])
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('第二组？'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        isNull,
      );
    });
  });
}
