import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/tool_progress_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: const Locale('zh', 'CN'),
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('ToolProgressPanel', () {
    testWidgets('displays title and progress indicator when in progress',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: '正在搜索笔记...',
          status: ToolProgressStatus.running,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
            thinkingText: '让我先看看最近的记录。',
          ),
        ),
      );

      // 执行中时标题仍显示当前动作，但详情默认折叠。
      expect(find.text('正在搜索笔记...'), findsAtLeastNWidgets(1));
      expect(find.text('让我先看看最近的记录。'), findsNothing);

      // 应该显示进度指示器
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('displays completed state with done icon',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          description: 'test_description',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: false,
          ),
        ),
      );

      // 应该显示本地化的完成摘要
      expect(find.text('执行了 1 个操作'), findsOneWidget);

      // 应该显示完成图标
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('opens the detail sheet on tap', (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          description: '测试描述',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: false,
          ),
        ),
      );

      // 折叠行只有摘要，细节不在对话流里
      expect(find.text('test_tool'), findsNothing);

      await tester.tap(find.byType(ToolProgressPanel));
      await tester.pumpAndSettle();

      // 细节在抽屉里
      expect(find.text('test_tool'), findsOneWidget);
      expect(find.text('测试描述'), findsOneWidget);

      // 关掉抽屉后回到只有摘要的状态
      Navigator.of(tester.element(find.text('test_tool'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('test_tool'), findsNothing);
    });

    testWidgets('detail sheet follows live progress while it stays open',
        (WidgetTester tester) async {
      Widget panelWith(List<ToolProgressItem> items, {required bool running}) {
        return buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: running,
          ),
        );
      }

      await tester.pumpWidget(
        panelWith(
          const [
            ToolProgressItem(
              toolName: 'search_notes',
              status: ToolProgressStatus.running,
            ),
          ],
          running: true,
        ),
      );

      await tester.tap(find.byType(ToolProgressPanel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 执行中折叠行的标题就是当前工具名，工具名会同时出现在行和抽屉里；
      // 用只存在于抽屉的结果文本做判据。
      expect(find.text('search_notes'), findsAtLeastNWidgets(1));
      expect(find.text('get_weather'), findsNothing);
      expect(find.text('找到 5 条结果'), findsNothing);

      // Agent 在抽屉开着的时候继续跑：抽屉是独立路由，父组件重建不会
      // 带着它刷新，必须靠快照通知。
      await tester.pumpWidget(
        panelWith(
          const [
            ToolProgressItem(
              toolName: 'search_notes',
              status: ToolProgressStatus.completed,
              result: '找到 5 条结果',
            ),
            ToolProgressItem(
              toolName: 'get_weather',
              status: ToolProgressStatus.running,
            ),
          ],
          running: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('get_weather'), findsAtLeastNWidgets(1));
      expect(find.text('找到 5 条结果'), findsOneWidget);
    });

    testWidgets('detail sheet distinguishes failed calls from completed ones',
        (WidgetTester tester) async {
      // 每项曾经都是一个恒定 secondaryContainer 的圆点，四个状态在界面上
      // 完全无法区分——工具调用失败看起来和成功一样。
      await tester.pumpWidget(
        buildTestApp(
          const ToolProgressPanel(
            title: '测试标题',
            items: [
              ToolProgressItem(
                toolName: 'ok_tool',
                status: ToolProgressStatus.completed,
              ),
              ToolProgressItem(
                toolName: 'broken_tool',
                status: ToolProgressStatus.failed,
              ),
            ],
            inProgress: false,
          ),
        ),
      );

      await tester.tap(find.byType(ToolProgressPanel));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      final theme = Theme.of(tester.element(find.text('broken_tool')));
      final failedLabel = tester.widget<Text>(find.text('broken_tool'));
      expect(failedLabel.style?.color, theme.colorScheme.error);
    });

    testWidgets('keeps tool items collapsed when in progress',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'pending_tool',
          description: 'pending_description',
          status: ToolProgressStatus.pending,
        ),
        const ToolProgressItem(
          toolName: 'completed_tool',
          description: 'completed_description',
          status: ToolProgressStatus.completed,
        ),
        const ToolProgressItem(
          toolName: 'failed_tool',
          description: 'failed_description',
          status: ToolProgressStatus.failed,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      expect(find.text('pending_description'), findsNothing);
      expect(find.text('completed_description'), findsNothing);
      expect(find.text('failed_description'), findsNothing);
    });

    testWidgets('displays description and result when provided',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          description: '参数: query="test"',
          status: ToolProgressStatus.completed,
          result: '找到 5 条结果',
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      await tester.tap(find.byType(ToolProgressPanel));
      // inProgress 的转圈是无限动画，pumpAndSettle 永远等不到静止
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 应该显示描述和结果
      expect(find.text('参数: query="test"'), findsOneWidget);
      expect(find.text('找到 5 条结果'), findsOneWidget);
    });

    testWidgets('uses custom done icon when provided',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          description: 'test_description',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: false,
            doneIcon: Icons.done_all,
          ),
        ),
      );

      // 应该显示自定义图标
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('keeps the sheet open when progress state changes',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ToolProgressPanel(
            title: '测试标题',
            items: [
              ToolProgressItem(
                toolName: 'test_tool',
                description: 'test_description',
                status: ToolProgressStatus.completed,
              ),
            ],
            inProgress: true,
          ),
        ),
      );

      expect(find.text('test_description'), findsNothing);

      await tester.tap(find.byType(ToolProgressPanel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('test_description'), findsOneWidget);

      // 更新状态为完成
      await tester.pumpWidget(
        buildTestApp(
          const ToolProgressPanel(
            title: '测试标题',
            items: [
              ToolProgressItem(
                toolName: 'test_tool',
                description: 'test_description',
                status: ToolProgressStatus.completed,
              ),
            ],
            inProgress: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 运行结束不该把用户正在看的抽屉关掉。
      expect(find.text('test_description'), findsOneWidget);
    });
  });

  group('ToolProgressItem', () {
    test('creates item with required fields', () {
      const item = ToolProgressItem(
        toolName: 'test',
        status: ToolProgressStatus.pending,
      );

      expect(item.toolName, 'test');
      expect(item.status, ToolProgressStatus.pending);
      expect(item.description, null);
      expect(item.result, null);
    });

    test('copyWith updates fields correctly', () {
      const item = ToolProgressItem(
        toolName: 'test',
        status: ToolProgressStatus.pending,
      );

      final updated = item.copyWith(
        status: ToolProgressStatus.completed,
        result: '完成',
      );

      expect(updated.toolName, 'test');
      expect(updated.status, ToolProgressStatus.completed);
      expect(updated.result, '完成');
      expect(updated.description, null);
    });
  });
}
