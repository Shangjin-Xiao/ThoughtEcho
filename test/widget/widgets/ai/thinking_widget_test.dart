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

  group('ThinkingWidget', () {
    testWidgets('initializes expanded when inProgress is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '正在分析问题...',
            inProgress: true,
          ),
        ),
      );

      expect(find.text('正在思考...'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('正在分析问题...'), findsOneWidget);
    });

    testWidgets('initializes collapsed when inProgress is false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '已经分析完成。',
            inProgress: false,
          ),
        ),
      );

      expect(find.text('思考'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets(
        'updates expansion state via didUpdateWidget when inProgress changes',
        (WidgetTester tester) async {
      // 初始进行中（展开）
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '思考中...',
            inProgress: true,
          ),
        ),
      );

      expect(find.byType(MarkdownBody), findsOneWidget);

      // 流式结束，inProgress 变为 false，保持当前展开状态（不自动折叠）
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '思考完成。',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('思考完成。'), findsOneWidget);
      expect(find.text('思考'), findsOneWidget);

      // 手动折叠
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsNothing);

      // 再次进入思考状态，inProgress 变为 true，由于此前已折叠，触发 didUpdateWidget 自动展开
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '第二轮思考中...',
            inProgress: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('第二轮思考中...'), findsOneWidget);
    });

    testWidgets(
        'preserves user intention when manually toggling during and after streaming',
        (WidgetTester tester) async {
      // 1. 开始流式思考，默认展开
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '第 1 轮思考中...',
            inProgress: true,
          ),
        ),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);

      // 2. 思考过程中用户手动折叠（inProgress 为 true 时有转圈动画，用 pump(300ms) 替代 pumpAndSettle）
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MarkdownBody), findsNothing);

      // 3. 流式结束 (inProgress -> false)，由于用户已手动折叠，组件保持折叠状态
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '第 1 轮思考完成',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsNothing);

      // 4. 发起第 2 轮思考 (inProgress -> true)，折叠状态自动展开
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '第 2 轮思考中...',
            inProgress: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MarkdownBody), findsOneWidget);

      // 5. 第 2 轮思考结束，用户未折叠，保留展开状态
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '第 2 轮思考完成',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('第 2 轮思考完成'), findsOneWidget);
    });

    testWidgets('toggles expanded state on tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '静态思考内容',
            inProgress: false,
          ),
        ),
      );

      expect(find.byType(MarkdownBody), findsNothing);

      // 点击展开
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('静态思考内容'), findsOneWidget);

      // 再次点击折叠
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets('debounces rapid streaming text updates to 100ms interval',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本',
            inProgress: true,
          ),
        ),
      );

      expect(find.text('初始文本'), findsOneWidget);

      // 20ms 后传入 Chunk 1
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本 + Chunk 1',
            inProgress: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      // 40ms 后传入 Chunk 2
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本 + Chunk 1 + Chunk 2',
            inProgress: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      // 此时未到 100ms 防抖间隔，文本仍保持初始文本
      expect(find.text('初始文本'), findsOneWidget);
      expect(find.text('初始文本 + Chunk 1 + Chunk 2'), findsNothing);

      // 前进 70ms（累计 110ms），防抖 Timer 触发更新
      await tester.pump(const Duration(milliseconds: 70));

      expect(find.text('初始文本 + Chunk 1 + Chunk 2'), findsOneWidget);
    });

    testWidgets(
        'flushes text immediately when stream completes (inProgress becomes false)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '流式思考中...',
            inProgress: true,
          ),
        ),
      );

      expect(find.text('流式思考中...'), findsOneWidget);

      // 流式输出结束，立即传入完整思考文本且 inProgress 设为 false
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '流式思考中...完整终极推导结论。',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 流式结束保持展开，直接可查看 MarkdownBody 中的完整文本
      expect(find.text('流式思考中...完整终极推导结论。'), findsOneWidget);
    });

    testWidgets(
        'flushes pending debounced text immediately when inProgress turns false without text change',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本',
            inProgress: true,
          ),
        ),
      );

      // 1. 传入最后一块文本，启动 100ms 防抖 Timer
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本 + 最后块',
            inProgress: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));

      // 文本尚未到达 100ms 防抖点
      expect(find.text('初始文本'), findsOneWidget);

      // 2. 随后单独更新翻转 inProgress 标志（文本未变）
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '初始文本 + 最后块',
            inProgress: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 流式结束保持展开，应立即刷入最后块文本，无需滞后等待 100ms 防抖 Timer
      expect(find.text('初始文本 + 最后块'), findsOneWidget);
    });

    testWidgets(
        'syncs text immediately when text becomes shorter or non-prefix growth',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '上一轮思考过程文本',
            inProgress: true,
          ),
        ),
      );

      expect(find.text('上一轮思考过程文本'), findsOneWidget);

      // 传入非前缀增长的新文本（如开启新一轮思考）
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '新一轮',
            inProgress: true,
          ),
        ),
      );
      await tester.pump();

      // 应该立即同步新文本，不闪现旧文
      expect(find.text('新一轮'), findsOneWidget);
    });

    testWidgets(
        'keeps content resident during collapse animation without instant vanishing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: '正在折叠的内容',
            inProgress: true,
          ),
        ),
      );

      expect(find.text('正在折叠的内容'), findsOneWidget);

      // 点击折叠触发动画
      await tester.tap(find.byType(InkWell));
      await tester.pump(); // 1st frame to start animation

      // 前进 100ms (动画播放过半，200ms 总时长)
      await tester.pump(const Duration(milliseconds: 100));

      // 动画过程中，内容保持常驻，不应在第一帧就替换为空盒
      expect(find.text('正在折叠的内容'), findsOneWidget);

      // 完成剩余 100ms 动画 (总时长 200ms)
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 50));

      // 动画完成后完全折叠 (Offstage)
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets('cancels debounce timer cleanly on dispose without throwing',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: 'Token 1',
            inProgress: true,
          ),
        ),
      );

      // 触发增量更新，启动 100ms 防抖 Timer
      await tester.pumpWidget(
        buildTestApp(
          const ThinkingWidget(
            thinkingText: 'Token 1 + Token 2',
            inProgress: true,
          ),
        ),
      );

      // 在 Timer 触发前直接销毁 Widget
      await tester.pumpWidget(const SizedBox());

      // 前进时间超过 100ms
      await tester.pump(const Duration(milliseconds: 200));

      // 验证无未处理异常/Timer 泄露
      expect(find.byType(ThinkingWidget), findsNothing);
    });
  });
}
