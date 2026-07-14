import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/home/home_note_editor_actions.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

void main() {
  testWidgets('add reloads missing tags and reports that none are available', (
    tester,
  ) async {
    var tagLoadCount = 0;
    late String expectedFeedback;
    late ScaffoldMessengerState messenger;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              expectedFeedback = AppLocalizations.of(context).noTagsAvailable;
              messenger = ScaffoldMessenger.of(context);
              final actions = HomeNoteEditorActions(
                context: context,
                isMounted: () => true,
                readTags: () => const [],
                isLoadingTags: () => false,
                loadTags: () async => tagLoadCount++,
                releaseNoteSearchFocus: () {},
                noteListKey: GlobalKey<NoteListViewState>(),
              );
              return ElevatedButton(
                onPressed: () => unawaited(actions.add()),
                child: const Text('add'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tagLoadCount, 2);
    messenger.hideCurrentSnackBar();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(expectedFeedback), findsOneWidget);
  });
}
