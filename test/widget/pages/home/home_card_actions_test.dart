import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/home/home_card_actions.dart';
import 'package:thoughtecho/widgets/svg_card_widget.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: child,
      ),
    );
  }

  final testCard = GeneratedCard(
    id: 'card1',
    noteId: 'note1',
    originalContent: 'A note content',
    svgContent:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="blue"/></svg>',
    type: CardType.minimalist,
    createdAt: DateTime.now(),
  );

  testWidgets('generateCard reports an unavailable card generator', (
    tester,
  ) async {
    late String expectedMessage;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              expectedMessage =
                  AppLocalizations.of(context).aiCardServiceNotInitialized;
              final actions = HomeCardActions(
                context: context,
                isMounted: () => true,
                cardService: null,
              );
              return ElevatedButton(
                onPressed: () => actions.generateCard(
                  Quote(
                    content: 'A note',
                    date: DateTime(2026).toIso8601String(),
                  ),
                ),
                child: const Text('generate'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('generate'));
    await tester.pump();

    expect(find.text(expectedMessage), findsOneWidget);
  });

  testWidgets(
    'CardPreviewDialog locks UI and presents progress during share export',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final shareCompleter = Completer<void>();
      late String shareProgressText;
      late String shareSuccessText;

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              shareProgressText = l10n.generatingShareImage;
              shareSuccessText = l10n.cardSharedSuccessfully;
              return CardPreviewDialog(
                card: testCard,
                onShare: (card) => shareCompleter.future,
                onSave: (card) async {},
                onRegenerate: () async => testCard,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find share button by icon
      final shareButtonFinder = find.widgetWithIcon(FilledButton, Icons.share);
      expect(shareButtonFinder, findsOneWidget);

      final FilledButton shareButtonBefore = tester.widget(shareButtonFinder);
      expect(shareButtonBefore.onPressed, isNotNull);

      // Tap share
      await tester.tap(shareButtonFinder);
      await tester.pump();

      // Progress UI should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(shareProgressText), findsOneWidget);

      // Buttons should be disabled during export
      final FilledButton shareButtonDuring = tester.widget(shareButtonFinder);
      expect(shareButtonDuring.onPressed, isNull);

      final FilledButton saveButtonDuring = tester.widget(
        find.widgetWithIcon(FilledButton, Icons.save_alt),
      );
      expect(saveButtonDuring.onPressed, isNull);

      final FilledButton regenButtonDuring = tester.widget(
        find.widgetWithIcon(FilledButton, Icons.refresh),
      );
      expect(regenButtonDuring.onPressed, isNull);

      // Complete share
      shareCompleter.complete();
      await tester.pump();

      // Feedback should be displayed and buttons unlocked
      expect(find.text(shareSuccessText), findsOneWidget);
      final FilledButton shareButtonAfter = tester.widget(shareButtonFinder);
      expect(shareButtonAfter.onPressed, isNotNull);
    },
  );

  testWidgets(
    'CardPreviewDialog locks UI and presents progress during save export',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final saveCompleter = Completer<String>();
      late String saveProgressText;
      late String saveSuccessText;

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              saveProgressText = l10n.savingCardToGallery;
              saveSuccessText = l10n.cardSavedToGallery('/saved/path/card.png');
              return CardPreviewDialog(
                card: testCard,
                onShare: (card) async {},
                onSave: (card) => saveCompleter.future,
                onRegenerate: () async => testCard,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      final saveButtonFinder =
          find.widgetWithIcon(FilledButton, Icons.save_alt);
      expect(saveButtonFinder, findsOneWidget);

      await tester.tap(saveButtonFinder);
      await tester.pump();

      // Progress UI visible and buttons disabled
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(saveProgressText), findsOneWidget);

      final FilledButton saveButtonDuring = tester.widget(saveButtonFinder);
      expect(saveButtonDuring.onPressed, isNull);

      // Complete save with path
      saveCompleter.complete('/saved/path/card.png');
      await tester.pump();

      // Success feedback displayed and buttons restored
      expect(find.text(saveSuccessText), findsOneWidget);
      final FilledButton saveButtonAfter = tester.widget(saveButtonFinder);
      expect(saveButtonAfter.onPressed, isNotNull);
    },
  );

  testWidgets(
    'CardPreviewDialog handles export error and restores UI interaction',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late String errorText;

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              errorText = l10n.saveFailed('Disk full');
              return CardPreviewDialog(
                card: testCard,
                onShare: (card) async {},
                onSave: (card) async => throw 'Disk full',
                onRegenerate: () async => testCard,
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      final saveButtonFinder =
          find.widgetWithIcon(FilledButton, Icons.save_alt);
      await tester.tap(saveButtonFinder);
      await tester.pump();

      // Error feedback visible and buttons re-enabled
      expect(find.text(errorText), findsOneWidget);
      final FilledButton saveButtonAfter = tester.widget(saveButtonFinder);
      expect(saveButtonAfter.onPressed, isNotNull);
    },
  );
}
