import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/pages/home/home_guide_coordinator.dart';
import 'package:thoughtecho/pages/settings_page.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

class _ShownFeatureGuides extends ChangeNotifier
    implements FeatureGuideService {
  @override
  bool hasShown(String guideId) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('note targets ready resumes note navigation through the seam', (
    tester,
  ) async {
    var consumeCalls = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: _ShownFeatureGuides(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final coordinator = HomeGuideCoordinator(
                  context: context,
                  isMounted: () => true,
                  currentPage: () => 1,
                  dailyQuoteKey: GlobalKey(),
                  noteListKey: GlobalKey<NoteListViewState>(),
                  noteFilterKey: GlobalKey(),
                  noteFavoriteKey: GlobalKey(),
                  noteMoreKey: GlobalKey(),
                  noteFoldKey: GlobalKey(),
                  settingsTabKey: GlobalKey(),
                  settingsPageKey: GlobalKey<SettingsPageState>(),
                );
                return ElevatedButton(
                  onPressed: () => coordinator.onNoteTargetsReady(
                    onConsumeTarget: () => consumeCalls++,
                  ),
                  child: const Text('ready'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ready'));

    expect(consumeCalls, 1);
  });
}
