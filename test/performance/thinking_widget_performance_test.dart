import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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

  group('ThinkingWidget 流式思考组件渲染与防抖测试', () {
    testWidgets('高频 Token 流式思考卡片渲染与防抖冒烟测试', (WidgetTester tester) async {
      String currentText = 'AI 正在推导中：\n';
      bool inProgress = true;

      // 使用同一 App 结构与 StatefulBuilder 模拟生产路径的同状态更新
      await tester.pumpWidget(
        buildTestApp(
          StatefulBuilder(
            builder: (context, setState) {
              return ThinkingWidget(
                thinkingText: currentText,
                inProgress: inProgress,
              );
            },
          ),
        ),
      );

      // 模拟高频推送 100 个 Token 节点 (每 10ms 推送 1 个 Token，总计 1000ms 模拟时间)
      for (int i = 1; i <= 100; i++) {
        currentText += '- 步骤 $i: 深入分析复杂逻辑问题并处理 Markdown 内容节点\n';
        await tester.pumpWidget(
          buildTestApp(
            StatefulBuilder(
              builder: (context, setState) {
                return ThinkingWidget(
                  thinkingText: currentText,
                  inProgress: inProgress,
                );
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }

      // 结束流式输出并刷入最终结果（自动触发折叠）
      currentText += '\n推导完成！';
      inProgress = false;
      await tester.pumpWidget(
        buildTestApp(
          StatefulBuilder(
            builder: (context, setState) {
              return ThinkingWidget(
                thinkingText: currentText,
                inProgress: inProgress,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击展开以查验最终全量 MarkdownBody 节点
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // 验证最终完整 Markdown 节点成功渲染
      expect(find.textContaining('步骤 100:'), findsWidgets);
      expect(find.textContaining('推导完成！'), findsWidgets);
      expect(find.byType(MarkdownBody), findsOneWidget);
    });
  });
}
