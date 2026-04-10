import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/tool_progress_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget _buildTestApp(Widget child) {
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
          toolName: 'test_tool',
          status: ToolProgressStatus.running,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      // 应该显示标题
      expect(find.text('测试标题'), findsOneWidget);

      // 应该显示进度指示器
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('displays completed state with done icon',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: false,
          ),
        ),
      );

      // 应该显示"已执行 N 个操作"
      expect(find.text('已执行 1 个操作'), findsOneWidget);

      // 应该显示完成图标
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('can toggle expansion', (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          description: '测试描述',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: false,
          ),
        ),
      );

      // 初始状态应该是折叠的（完成状态默认折叠）
      expect(find.text('test_tool'), findsNothing);

      // 点击标题栏展开
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // 现在应该能看到工具名称
      expect(find.text('test_tool'), findsOneWidget);
      expect(find.text('测试描述'), findsOneWidget);

      // 再次点击折叠
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // 应该又看不到了
      expect(find.text('test_tool'), findsNothing);
    });

    testWidgets('displays tool items with correct status icons',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'pending_tool',
          status: ToolProgressStatus.pending,
        ),
        const ToolProgressItem(
          toolName: 'completed_tool',
          status: ToolProgressStatus.completed,
        ),
        const ToolProgressItem(
          toolName: 'failed_tool',
          status: ToolProgressStatus.failed,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      // 进行中状态默认展开
      await tester.pump();

      // 应该显示所有工具名称
      expect(find.text('pending_tool'), findsOneWidget);
      expect(find.text('completed_tool'), findsOneWidget);
      expect(find.text('failed_tool'), findsOneWidget);

      // 应该显示对应的状态图标
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
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
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      await tester.pump();

      // 应该显示描述和结果
      expect(find.text('参数: query="test"'), findsOneWidget);
      expect(find.text('找到 5 条结果'), findsOneWidget);
    });

    testWidgets('uses custom done icon when provided',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
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

    testWidgets('collapses when changing from in progress to completed',
        (WidgetTester tester) async {
      final items = [
        const ToolProgressItem(
          toolName: 'test_tool',
          status: ToolProgressStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: items,
            inProgress: true,
          ),
        ),
      );

      await tester.pump();

      // 进行中时默认展开，应该能看到工具名称
      expect(find.text('test_tool'), findsOneWidget);

      // 更新状态为完成
      await tester.pumpWidget(
        _buildTestApp(
          ToolProgressPanel(
            title: '测试标题',
            items: [
              const ToolProgressItem(
                toolName: 'test_tool',
                status: ToolProgressStatus.completed,
              ),
            ],
            inProgress: false,
          ),
        ),
      );

      // 等待动画完成
      await tester.pump(const Duration(milliseconds: 500));

      // 完成后应该自动折叠，看不到工具名称
      expect(find.text('test_tool'), findsNothing);
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
