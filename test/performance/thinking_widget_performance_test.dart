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

  group('ThinkingWidget 流式思考渲染防抖性能基准测试', () {
    testWidgets('高频 Token 流式思考卡片 100ms 防抖重建抑制率基准测试',
        (WidgetTester tester) async {
      String currentText = 'AI 正在推导中：\n';
      bool inProgress = true;
      const int totalTokenTriggers = 100;

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

      int rebuildCount = 0;
      String? lastRenderedData;

      // 模拟高频推送 100 个 Token 节点 (每 10ms 推送 1 个 Token，总计 1000ms 模拟时间)
      for (int i = 1; i <= totalTokenTriggers; i++) {
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

        final markdownFinder = find.byType(MarkdownBody);
        if (markdownFinder.evaluate().isNotEmpty) {
          final markdown = tester.widget<MarkdownBody>(markdownFinder);
          if (markdown.data != lastRenderedData) {
            rebuildCount++;
            lastRenderedData = markdown.data;
          }
        }
      }

      final double suppressionRatio =
          (totalTokenTriggers - rebuildCount) / totalTokenTriggers;

      // ignore: avoid_print
      print(
          'ThinkingWidget Streaming Benchmark: $rebuildCount rebuilds for $totalTokenTriggers token triggers (${(suppressionRatio * 100).toStringAsFixed(1)}% rebuild suppression ratio)');

      // 验证定量基准指标：防抖后的 Markdown AST 重建次数远小于触发次数（<= 15 次 vs 100 次触发）
      expect(rebuildCount, lessThanOrEqualTo(15));
    });
  });
}
