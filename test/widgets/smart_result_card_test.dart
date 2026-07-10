import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/smart_result_card.dart';

void main() {
  Widget harness(Widget child) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('new note smart result card shows editor and direct save actions',
      (tester) async {
    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '这是新的笔记内容',
          editorSource: 'new_note',
          onOpenInEditor: (_, __) {},
          onSaveDirectly: (_, __) {},
        ),
      ),
    );

    expect(find.text('新笔记草稿'), findsOneWidget);
    expect(find.text('这是新的笔记内容'), findsOneWidget);
    expect(find.text('打开编辑器'), findsOneWidget);
    expect(find.text('直接保存'), findsOneWidget);
    expect(find.text('应用更改'), findsNothing);
    expect(find.text('追加到笔记'), findsNothing);
  });

  testWidgets('passes preview draft to direct save and disables after success',
      (tester) async {
    SmartResultDraft? savedDraft;
    String? savedNoteId;

    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '原内容',
          author: '原作者',
          source: '原出处',
          tagNames: const ['旧标签'],
          editorSource: 'new_note',
          onOpenDraftInEditor: (_) async {},
          onSaveDraftDirectly: (draft) async {
            savedDraft = draft;
            return 'note_saved';
          },
          onSavedNoteId: (noteId) {
            savedNoteId = noteId;
          },
        ),
      ),
    );

    await tester.tap(find.text('直接保存'));
    await tester.pumpAndSettle();

    expect(savedDraft?.content, '原内容');
    expect(savedDraft?.author, '原作者');
    expect(savedDraft?.source, '原出处');
    expect(savedDraft?.tagNames, ['旧标签']);
    expect(savedNoteId, 'note_saved');
    expect(find.text('笔记已保存'), findsAtLeastNWidgets(1));
    final savedButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '笔记已保存'),
    );
    expect(savedButton.onPressed, isNull);
  });

  testWidgets('keeps direct save retryable after failure', (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '内容',
          editorSource: 'new_note',
          onOpenDraftInEditor: (_) async {},
          onSaveDraftDirectly: (_) async {
            attempts++;
            throw Exception('db locked');
          },
        ),
      ),
    );

    await tester.tap(find.text('直接保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直接保存'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.textContaining('db locked'), findsOneWidget);
    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '直接保存'),
    );
    expect(retryButton.onPressed, isNotNull);
  });
}
