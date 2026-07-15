import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/ai/smart_result_card.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';

class _Settings extends ChangeNotifier implements SettingsService {
  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(Widget child) => ChangeNotifierProvider<SettingsService>.value(
      value: _Settings(),
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('shows final plain document and opens change history',
      (tester) async {
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.edit,
      proposalTitle: 'Polish',
      reason: 'Clearer wording',
      noteId: 'note',
      originalKind: NoteDocumentKind.plain,
      resultKind: NoteDocumentKind.rich,
      modeTransition: NoteModeTransition.plainToRich,
      content: 'Final document',
      documentOps: const [
        {'insert': 'Final document\n'}
      ],
      metadata: const {},
      changes: [
        NoteProposalChange(type: 'replace', before: 'Old', after: 'Final'),
      ],
      baseRevision: 'revision',
    );

    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => true,
    )));

    expect(find.byType(QuoteContent), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    expect(find.textContaining('全屏富文本编辑器'), findsOneWidget);

    await tester.tap(find.text('查看修改记录'));
    await tester.pump();
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
  });

  testWidgets('limits long document height and disables after save',
      (tester) async {
    final artifact = NoteProposalArtifact(
      action: NoteProposalAction.create,
      proposalTitle: 'Draft',
      reason: '',
      resultKind: NoteDocumentKind.plain,
      content: List.filled(100, 'long text').join('\n'),
      documentOps: null,
      metadata: const {},
      changes: const [],
    );
    await tester.pumpWidget(_app(NoteProposalCard(
      artifact: artifact,
      onOpenInEditor: () async {},
      onApply: () async => true,
    )));

    final constrained = tester.widgetList<ConstrainedBox>(
      find.byType(ConstrainedBox),
    );
    expect(
      constrained.any((widget) => widget.constraints.maxHeight == 220),
      isTrue,
    );
    await tester.tap(find.text('保存笔记'));
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);
  });
}
