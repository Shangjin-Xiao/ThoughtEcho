import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/widgets/svg_card_widget.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  const sampleSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="blue"/></svg>';

  final sampleCard = GeneratedCard(
    id: 'test_card_1',
    noteId: 'test_note_1',
    originalContent: 'Sample note content for test',
    svgContent: sampleSvg,
    type: CardType.minimalist,
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('SVGCardWidget renders valid SVG content properly',
      (WidgetTester tester) async {
    const validSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="blue"/></svg>';

    await tester.pumpWidget(
      buildTestableWidget(
        const SVGCardWidget(
          svgContent: validSvg,
          width: 200,
          height: 200,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(SVGCardWidget), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
  });

  testWidgets('SVGCardWidget shows error UI when svgContent is empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const SVGCardWidget(
          svgContent: '',
          width: 200,
          height: 200,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets('SVGCardWidget shows error UI when svgContent is invalid format',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        const SVGCardWidget(
          svgContent: 'invalid svg text',
          width: 200,
          height: 200,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets(
      'CardPreviewDialog entrance animation plays smoothly and reuses static child',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestableWidget(
        CardPreviewDialog(
          card: sampleCard,
        ),
      ),
    );

    // Initial frame of entrance animation (t=0)
    await tester.pump(Duration.zero);

    final opacityFinder = find.descendant(
      of: find.byType(CardPreviewDialog),
      matching: find.byType(Opacity),
    );
    expect(opacityFinder, findsOneWidget);

    final initialOpacity = tester.widget<Opacity>(opacityFinder);
    expect(initialOpacity.opacity, equals(0.0));

    final cardFinder = find.byType(GeneratedCardWidget);
    expect(cardFinder, findsOneWidget);
    final initialCardElement = tester.element(cardFinder);
    final initialCardWidget = tester.widget<GeneratedCardWidget>(cardFinder);

    // Mid-animation frame (t = 150ms)
    await tester.pump(const Duration(milliseconds: 150));

    final midOpacity = tester.widget<Opacity>(opacityFinder);
    expect(midOpacity.opacity, greaterThan(0.0));
    expect(midOpacity.opacity, lessThan(1.0));

    // Static child subtree is preserved and reused across animation frames
    final midCardElement = tester.element(cardFinder);
    final midCardWidget = tester.widget<GeneratedCardWidget>(cardFinder);
    expect(midCardElement, same(initialCardElement));
    expect(midCardWidget, same(initialCardWidget));

    // Settle animation to completion (300ms)
    await tester.pumpAndSettle();

    final finalOpacity = tester.widget<Opacity>(opacityFinder);
    expect(finalOpacity.opacity, equals(1.0));
    final finalCardWidget = tester.widget<GeneratedCardWidget>(cardFinder);
    expect(finalCardWidget, same(initialCardWidget));
    expect(find.byType(GeneratedCardWidget), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('CardPreviewDialog re-renders correctly on regeneration',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const updatedSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="red"/></svg>';
    final updatedCard = GeneratedCard(
      id: 'test_card_2',
      noteId: 'test_note_1',
      originalContent: 'Regenerated note content',
      svgContent: updatedSvg,
      type: CardType.quote,
      createdAt: DateTime(2026, 1, 2),
    );

    final completer = Completer<GeneratedCard>();

    await tester.pumpWidget(
      buildTestableWidget(
        CardPreviewDialog(
          card: sampleCard,
          onRegenerate: () => completer.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialCardWidget =
        tester.widget<GeneratedCardWidget>(find.byType(GeneratedCardWidget));
    expect(initialCardWidget.card, equals(sampleCard));

    // Tap regenerate button
    final regenerateButton = find.byIcon(Icons.refresh);
    expect(regenerateButton, findsOneWidget);
    await tester.ensureVisible(regenerateButton);
    await tester.tap(regenerateButton);
    await tester.pump();

    // Loading indicator appears while regenerating
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Complete the regeneration
    completer.complete(updatedCard);
    await tester.pumpAndSettle();

    // Loading indicator disappears and card is updated
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GeneratedCardWidget), findsOneWidget);
    final updatedCardWidget =
        tester.widget<GeneratedCardWidget>(find.byType(GeneratedCardWidget));
    expect(updatedCardWidget.card, equals(updatedCard));
    expect(updatedCardWidget, isNot(same(initialCardWidget)));
  });

  testWidgets('CardPreviewDialog dismisses when close button is tapped',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (context) => CardPreviewDialog(card: sampleCard),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreviewDialog), findsOneWidget);

    // Tap close button
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(CardPreviewDialog), findsNothing);
  });
}
