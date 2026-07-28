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
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
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
          onOpenDraftInEditor: (_) async => null,
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
    // 保存后变为「已保存 · 查看笔记」出口，编辑/保存按钮消失，防止重复采纳
    expect(find.text('已保存 · 查看笔记'), findsOneWidget);
    expect(find.text('直接保存'), findsNothing);
    expect(find.text('打开编辑器'), findsNothing);
  });

  testWidgets('writes back the note id saved inside the editor',
      (tester) async {
    String? savedNoteId;

    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '内容',
          onOpenDraftInEditor: (_) async => 'note_from_editor',
          onSaveDraftDirectly: (_) async => null,
          onSavedNoteId: (noteId) {
            savedNoteId = noteId;
          },
        ),
      ),
    );

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    expect(savedNoteId, 'note_from_editor');
    // 采纳后编辑/保存入口消失，只留「已保存 · 查看笔记」，避免重复采纳产生重复笔记
    expect(find.text('打开编辑器'), findsNothing);
    expect(find.text('直接保存'), findsNothing);
    expect(find.text('已保存 · 查看笔记'), findsOneWidget);
  });

  testWidgets('disables the editor action for an already saved result',
      (tester) async {
    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '内容',
          initialSavedNoteId: 'existing_note',
          onOpenDraftInEditor: (_) async => null,
          onSaveDraftDirectly: (_) async => null,
        ),
      ),
    );

    // 历史已保存卡片只显示「已保存 · 查看笔记」出口
    expect(find.text('打开编辑器'), findsNothing);
    expect(find.text('直接保存'), findsNothing);
    expect(find.text('已保存 · 查看笔记'), findsOneWidget);
  });

  testWidgets('keeps direct save retryable after failure', (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      harness(
        SmartResultCard(
          title: '新笔记草稿',
          content: '内容',
          onOpenDraftInEditor: (_) async => null,
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
    // 不再向用户裸露异常原文，只显示可重试的通用文案
    expect(find.textContaining('db locked'), findsNothing);
    expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '直接保存'),
    );
    expect(retryButton.onPressed, isNotNull);
  });
}
