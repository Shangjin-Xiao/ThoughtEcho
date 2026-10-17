import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/streaming_text_dialog.dart';

void main() {
  group('StreamingTextDialog', () {
    testWidgets(
      'uses display transformer for preview but applies raw text',
      (tester) async {
        final controller = StreamController<String>();
        String? appliedText;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Polish',
                textStream: controller.stream,
                applyButtonText: '应用',
                displayTextTransformer: (rawText) =>
                    rawText.replaceAll('[[TE_MEDIA_1]]', ''),
                onApply: (text) {
                  appliedText = text;
                },
                onCancel: () {},
              ),
            ),
          ),
        );

        controller.add('Hello [[TE_MEDIA_1]] world');
        await controller.close();

        await tester.pumpAndSettle();

        expect(find.textContaining('[[TE_MEDIA_1]]'), findsNothing);
        expect(find.textContaining('Hello  world'), findsOneWidget);

        await tester.tap(find.text('应用'));
        await tester.pump();

        expect(appliedText, 'Hello [[TE_MEDIA_1]] world');
      },
    );

    testWidgets(
      'throttles stream updates (leading edge immediate + 50ms window buffering)',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Streaming Test',
                textStream: controller.stream,
                applyButtonText: '应用',
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );

        // 首个 Token 到达：前沿立即渲染
        controller.add('Chunk 1');
        await tester.pump();
        expect(find.textContaining('Chunk 1'), findsOneWidget);

        // 在 50ms 窗口内连续发送多个 Token
        controller.add(' Chunk 2');
        controller.add(' Chunk 3');
        await tester.pump(const Duration(milliseconds: 10));

        // 窗口未到期，界面尚未刷新 Chunk 2 和 Chunk 3
        expect(find.textContaining('Chunk 2'), findsNothing);

        // 推进时间越过 50ms 窗口
        await tester.pump(const Duration(milliseconds: 45));
        expect(find.textContaining('Chunk 1 Chunk 2 Chunk 3'), findsOneWidget);

        await controller.close();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'renders Markdown correctly when isMarkdown is true',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Markdown Test',
                textStream: controller.stream,
                applyButtonText: '应用',
                isMarkdown: true,
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );

        controller.add('# Title\n\n**Bold Text**\n\n- List Item');
        await controller.close();
        await tester.pumpAndSettle();

        expect(find.text('Title'), findsOneWidget);
        expect(find.text('Bold Text'), findsOneWidget);
        expect(find.text('List Item'), findsOneWidget);
      },
    );

    testWidgets(
      'flushes pending buffer immediately on completion',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Completion Flush Test',
                textStream: controller.stream,
                applyButtonText: '应用',
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );

        controller.add('First');
        await tester.pump();

        // 发送第二个 chunk 并立即关闭流
        controller.add(' Second');
        await controller.close();
        await tester.pump();

        // 完成时无须等待 50ms 节流窗口，缓冲区内容立即刷新屏上
        expect(find.textContaining('First Second'), findsOneWidget);
      },
    );

    testWidgets(
      'flushes error and displays error message immediately on stream error',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Error Test',
                textStream: controller.stream,
                applyButtonText: '应用',
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );

        controller.add('Part 1');
        await tester.pump();

        controller.addError('Connection Lost');
        await tester.pumpAndSettle();

        expect(find.textContaining('Part 1'), findsOneWidget);
        expect(find.textContaining('Connection Lost'), findsOneWidget);
      },
    );

    testWidgets(
      'auto-scrolls to bottom when content overflows and expands by >60px',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 300,
                  width: 600,
                  child: StreamingTextDialog(
                    title: 'Scroll Test',
                    textStream: controller.stream,
                    applyButtonText: '应用',
                    onApply: (_) {},
                    onCancel: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Fill content to exceed the height of the scroll container
        final lines1 = List.generate(30, (i) => 'Line $i').join('\n');
        controller.add(lines1);
        await tester.pump();
        final scrollableFinder = find.byType(SingleChildScrollView);
        expect(scrollableFinder, findsOneWidget);
        final SingleChildScrollView scrollView = tester.widget(scrollableFinder);
        final scrollController = scrollView.controller!;

        expect(scrollController.position.maxScrollExtent, greaterThan(0));
        expect(
          scrollController.position.pixels,
          equals(scrollController.position.maxScrollExtent),
        );

        // Push a large chunk that expands content height by > 60px
        final lines2 = List.generate(30, (i) => ' Extra Line $i').join('\n');
        controller.add('\n$lines2');
        await tester.pump(const Duration(milliseconds: 100));

        // Scroll position should auto-scroll to the new maxScrollExtent
        expect(
          scrollController.position.pixels,
          equals(scrollController.position.maxScrollExtent),
        );

        await controller.close();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'suppresses auto-scroll when user scrolls up, and resumes when scrolled back down',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 300,
                  width: 600,
                  child: StreamingTextDialog(
                    title: 'Scroll Guard Test',
                    textStream: controller.stream,
                    applyButtonText: '应用',
                    onApply: (_) {},
                    onCancel: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Fill content to overflow
        final initialLines = List.generate(30, (i) => 'Line $i').join('\n');
        controller.add(initialLines);
        await tester.pump(const Duration(milliseconds: 100));

        final scrollableFinder = find.byType(SingleChildScrollView);
        final SingleChildScrollView scrollView = tester.widget(scrollableFinder);
        final scrollController = scrollView.controller!;

        final maxScroll1 = scrollController.position.maxScrollExtent;
        expect(scrollController.position.pixels, equals(maxScroll1));

        // User manually scrolls up away from bottom
        await tester.drag(scrollableFinder, const Offset(0, 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(scrollController.position.pixels, lessThan(maxScroll1 - 60.0));
        final userScrolledPixels = scrollController.position.pixels;

        // Next chunk arrives while user is scrolled up
        controller.add('\nMore lines 1\nMore lines 2\nMore lines 3');
        await tester.pump(const Duration(milliseconds: 100));

        // Scroll position should remain near where user scrolled, NOT jump to maxScrollExtent
        expect(scrollController.position.pixels, equals(userScrolledPixels));

        // Now user scrolls back to bottom
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 100));

        // Next chunk arrives when user is back at bottom
        controller.add('\nFinal line 1\nFinal line 2');
        await tester.pump(const Duration(milliseconds: 100));

        // Auto-scroll should have resumed and jumped to the new maxScrollExtent
        expect(
          scrollController.position.pixels,
          equals(scrollController.position.maxScrollExtent),
        );

        await controller.close();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'releases throttle timer after window flush and immediately renders subsequent chunk',
      (tester) async {
        final controller = StreamController<String>();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Timer Release Test',
                textStream: controller.stream,
                applyButtonText: '应用',
                onApply: (_) {},
                onCancel: () {},
              ),
            ),
          ),
        );

        // First chunk -> leading edge renders immediately
        controller.add('Chunk 1');
        await tester.pump();
        expect(find.textContaining('Chunk 1'), findsOneWidget);

        // Wait 60ms so throttle window finishes and clears timer
        await tester.pump(const Duration(milliseconds: 60));

        // Second chunk arriving after timer cleared should render leading edge immediately
        controller.add(' Chunk 2');
        await tester.pump();

        expect(find.textContaining('Chunk 1 Chunk 2'), findsOneWidget);

        await controller.close();
        await tester.pumpAndSettle();
      },
    );
  });
}
