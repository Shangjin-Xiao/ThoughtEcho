import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/home/home_card_actions.dart';

void main() {
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
}
