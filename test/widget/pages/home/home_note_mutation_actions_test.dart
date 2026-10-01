import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/home/home_note_mutation_actions.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

class _Database extends ChangeNotifier implements DatabaseService {
  String? favoritedId;
  String? deletedId;

  @override
  Future<void> incrementFavoriteCount(String quoteId) async {
    favoritedId = quoteId;
  }

  @override
  Future<void> deleteQuote(String quoteId) async {
    deletedId = quoteId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('favorite persists the increment and reports the new count', (
    tester,
  ) async {
    final database = _Database();
    late String expectedFeedback;

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: database,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                expectedFeedback =
                    AppLocalizations.of(context).favoriteCountWithNum(3);
                final actions = HomeNoteMutationActions(
                  context: context,
                  isMounted: () => true,
                  noteListKey: GlobalKey<NoteListViewState>(),
                  onTrashGuideRequested: () {},
                );
                return ElevatedButton(
                  onPressed: () => unawaited(
                    actions.favorite(
                      Quote(
                        id: 'note-1',
                        content: 'note',
                        date: DateTime(2026).toIso8601String(),
                        favoriteCount: 2,
                      ),
                    ),
                  ),
                  child: const Text('favorite'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('favorite'));
    await tester.pump();

    expect(database.favoritedId, 'note-1');
    expect(find.text(expectedFeedback), findsOneWidget);
  });

  testWidgets('delete deletes the note and shows trash feedback',
      (tester) async {
    final database = _Database();
    late String expectedFeedback;

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: database,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                expectedFeedback =
                    AppLocalizations.of(context).noteMovedToTrash;
                final actions = HomeNoteMutationActions(
                  context: context,
                  isMounted: () => true,
                  noteListKey: GlobalKey<NoteListViewState>(),
                  onTrashGuideRequested: () {},
                );
                return ElevatedButton(
                  onPressed: () => unawaited(
                    actions.delete(
                      Quote(
                        id: 'note-2',
                        content: 'note to delete',
                        date: DateTime(2026).toIso8601String(),
                      ),
                    ),
                  ),
                  child: const Text('delete'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pump();

    expect(database.deletedId, 'note-2');
    expect(find.text(expectedFeedback), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
  });
}
