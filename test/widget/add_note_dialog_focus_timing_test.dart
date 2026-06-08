import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

void main() {
  testWidgets('delays content focus until bottom sheet entrance settles',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>(
        create: (_) => _MockFeatureGuideService(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => AddNoteDialog(
                      tags: const [],
                      onSave: (_) {},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final contentField = tester.widget<TextField>(find.byType(TextField).first);
    expect(contentField.focusNode?.hasFocus, isFalse);

    await tester.pumpAndSettle();

    expect(contentField.focusNode?.hasFocus, isTrue);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('disables add info chip checkmarks to avoid keyboard jank flash',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>(
        create: (_) => _MockFeatureGuideService(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AddNoteDialog(
              tags: const [],
              onSave: (_) {},
            ),
          ),
        ),
      ),
    );

    for (final key in const [
      ValueKey('add_note_location_chip'),
      ValueKey('add_note_weather_chip'),
      ValueKey('add_note_color_chip'),
    ]) {
      final chip = tester.widget<FilterChip>(find.byKey(key));
      expect(chip.showCheckmark, isFalse);
    }

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('ignores repeated save taps while create is in progress',
      (tester) async {
    final databaseService = _SlowDatabaseService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FeatureGuideService>(
            create: (_) => _MockFeatureGuideService(),
          ),
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AddNoteDialog(
              tags: const [],
              onSave: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '重复保存测试');
    await tester.pump(const Duration(seconds: 2));

    final saveButton = find.widgetWithText(FilledButton, '保存');
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(saveButton);
    await tester.pump();

    expect(databaseService.addQuoteCallCount, 1);

    databaseService.completeSave();
    await tester.pumpAndSettle();
  });
}

class _MockFeatureGuideService extends FeatureGuideService {
  _MockFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

class _SlowDatabaseService extends DatabaseService {
  _SlowDatabaseService() : super.forTesting();

  final _saveCompleter = Completer<void>();
  int addQuoteCallCount = 0;

  void completeSave() {
    if (!_saveCompleter.isCompleted) {
      _saveCompleter.complete();
    }
  }

  @override
  Future<List<NoteCategory>> getCategories() async => const [];

  @override
  Future<void> addQuote(Quote quote) async {
    addQuoteCallCount += 1;
    await _saveCompleter.future;
  }

  @override
  Future<QuoteUpdateResult> updateQuote(Quote quote) async {
    await _saveCompleter.future;
    return QuoteUpdateResult.updated;
  }
}
