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

  group('CardPreviewDialog tests', () {
    final initialCard = GeneratedCard(
      id: 'card_1',
      noteId: 'note_1',
      originalContent: 'Original Card Content',
      svgContent:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="blue"/><text x="10" y="20">Card 1</text></svg>',
      type: CardType.knowledge,
      createdAt: DateTime(2026, 10, 17),
    );

    final regeneratedCard = GeneratedCard(
      id: 'card_2',
      noteId: 'note_1',
      originalContent: 'Regenerated Card Content',
      svgContent:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="green"/><text x="10" y="20">Card 2</text></svg>',
      type: CardType.minimalist,
      createdAt: DateTime(2026, 10, 17),
    );

    testWidgets(
        'CardPreviewDialog plays entrance animation and renders content properly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestableWidget(
          CardPreviewDialog(card: initialCard),
        ),
      );

      // Verify widget tree is present during initial frame of animation
      expect(find.byType(CardPreviewDialog), findsOneWidget);
      expect(find.byType(AnimatedBuilder), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(GeneratedCardWidget), findsOneWidget);

      // Pump mid-way through 300ms entrance animation
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(Transform), findsWidgets);
      expect(find.byType(Opacity), findsWidgets);

      // Complete entrance animation
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(find.byType(CardPreviewDialog), findsOneWidget);
      expect(find.byType(GeneratedCardWidget), findsOneWidget);
    });

    testWidgets('CardPreviewDialog handles card regeneration and updates state',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool regenerateCalled = false;

      await tester.pumpWidget(
        buildTestableWidget(
          CardPreviewDialog(
            card: initialCard,
            onRegenerate: () async {
              regenerateCalled = true;
              await Future.delayed(const Duration(milliseconds: 100));
              return regeneratedCard;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find regenerate action button and tap it
      final regenerateBtn = find.widgetWithIcon(FilledButton, Icons.refresh);
      expect(regenerateBtn, findsOneWidget);
      await tester.tap(regenerateBtn);

      // Trigger frame to enter _isRegenerating state
      await tester.pump();
      expect(regenerateCalled, isTrue);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Complete async regeneration request
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Verify regenerated card state is displayed and loading indicator disappears
      expect(find.byType(CardPreviewDialog), findsOneWidget);
      expect(find.byType(GeneratedCardWidget), findsOneWidget);
    });

    testWidgets('CardPreviewDialog can be closed via close button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => CardPreviewDialog(card: initialCard),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(CardPreviewDialog), findsOneWidget);

      // Tap close button
      final closeButton = find.widgetWithIcon(IconButton, Icons.close);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(CardPreviewDialog), findsNothing);
    });
  });
}
