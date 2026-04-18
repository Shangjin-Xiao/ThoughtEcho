import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/ai/smart_result_card.dart';

void main() {
  testWidgets('new note smart result card shows editor and direct save actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SmartResultCard(
            title: '新笔记草稿',
            content: '这是新的笔记内容',
            editorSource: 'new_note',
            onOpenInEditor: () {},
            onSaveDirectly: () {},
          ),
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
}
