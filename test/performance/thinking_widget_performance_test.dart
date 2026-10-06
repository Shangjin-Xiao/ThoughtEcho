import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/thinking_widget.dart';

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
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  group('ThinkingWidget 流式输出渲染性能基准测试', () {
    testWidgets('高频 Token 流式思考卡片渲染性能 benchmark', (WidgetTester tester) async {
      final Stopwatch stopwatch = Stopwatch()..start();

      // 1. 初始化展开状态下的 ThinkingWidget
      String currentText = 'AI 正在推导中：\n';
      await tester.pumpWidget(
        buildTestApp(
          ThinkingWidget(
            thinkingText: currentText,
            inProgress: true,
          ),
        ),
      );

      // 2. 模拟高频推送 100 个 Token 节点 (每 10ms 推送 1 个 Token)
      for (int i = 1; i <= 100; i++) {
        currentText += '- 步骤 $i: 深入分析复杂逻辑问题并处理 Markdown 内容节点\n';
        await tester.pumpWidget(
          buildTestApp(
            ThinkingWidget(
              thinkingText: currentText,
              inProgress: true,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }

      // 3. 结束流式输出并刷入最终结果（此时自动折叠）
      await tester.pumpWidget(
        buildTestApp(
          ThinkingWidget(
            thinkingText: '$currentText\n推导完成！',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击展开以查验最终全量 MarkdownBody 节点
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      stopwatch.stop();

      // 验证最终完整 Markdown 节点成功渲染
      expect(find.textContaining('步骤 100:'), findsWidgets);
      expect(find.textContaining('推导完成！'), findsWidgets);

      // 确认 100 次 Token 流式高频刷新能在合理时延内完成 (小于 10 秒)
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });
}
