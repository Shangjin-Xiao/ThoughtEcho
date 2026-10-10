import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/widgets/quote_card.dart';
import 'package:thoughtecho/widgets/quote_card_helpers.dart';

void main() {
  Quote createTestQuote({
    String content = 'Test Quote Content',
    String? colorHex,
    String? sourceAuthor,
    String? sourceWork,
    String? source,
  }) {
    return Quote(
      id: '1',
      content: content,
      date: '2026-10-08T12:00:00.000',
      colorHex: colorHex,
      sourceAuthor: sourceAuthor,
      sourceWork: sourceWork,
      source: source,
    );
  }

  Widget buildTestApp({
    required Quote quote,
    Brightness brightness = Brightness.light,
    ThemeData? theme,
  }) {
    final effectiveTheme = theme ??
        ThemeData(
          brightness: brightness,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
          ),
        );

    return MaterialApp(
      theme: effectiveTheme,
      home: Scaffold(
        body: QuoteCard(quote: quote),
      ),
    );
  }

  group('QuoteCard Dynamic Contrast Tests', () {
    testWidgets(
        'renders light card color (#FFFFFF) with high contrast text in light mode',
        (WidgetTester tester) async {
      final quote = createTestQuote(
        colorHex: '#FFFFFF',
        sourceAuthor: 'Author A',
        sourceWork: 'Book A',
      );

      await tester
          .pumpWidget(buildTestApp(quote: quote, brightness: Brightness.light));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);
      final expectedColors =
          QuoteCardColors.fromHex('#FFFFFF', theme.colorScheme);

      final contentText = tester.widget<Text>(find.text('Test Quote Content'));
      expect(contentText.style?.color, expectedColors.primaryTextColor);

      final sourceText = tester.widget<Text>(find.text('——Author A 「Book A」'));
      expect(sourceText.style?.color, expectedColors.secondaryTextColor);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, expectedColors.cardColor);
    });

    testWidgets(
        'renders light card color (#FFFFFF) with dark text in dark mode',
        (WidgetTester tester) async {
      final quote = createTestQuote(
        colorHex: '#FFFFFF',
        sourceAuthor: 'Author B',
      );

      await tester
          .pumpWidget(buildTestApp(quote: quote, brightness: Brightness.dark));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);
      final expectedColors =
          QuoteCardColors.fromHex('#FFFFFF', theme.colorScheme);

      final contentText = tester.widget<Text>(find.text('Test Quote Content'));
      expect(contentText.style?.color, expectedColors.primaryTextColor);

      final sourceText = tester.widget<Text>(find.text('——Author B'));
      expect(sourceText.style?.color, expectedColors.secondaryTextColor);
    });

    testWidgets(
        'renders dark card color (#000000) with light text in light mode',
        (WidgetTester tester) async {
      final quote = createTestQuote(
        colorHex: '#000000',
        source: 'Legacy Source',
      );

      await tester
          .pumpWidget(buildTestApp(quote: quote, brightness: Brightness.light));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);
      final expectedColors =
          QuoteCardColors.fromHex('#000000', theme.colorScheme);

      final contentText = tester.widget<Text>(find.text('Test Quote Content'));
      expect(contentText.style?.color, expectedColors.primaryTextColor);

      final sourceText = tester.widget<Text>(find.text('Legacy Source'));
      expect(sourceText.style?.color, expectedColors.secondaryTextColor);
    });
  });

  group('QuoteCard Fallback Handling Tests', () {
    testWidgets('degrades gracefully when colorHex is null',
        (WidgetTester tester) async {
      final quote = createTestQuote(colorHex: null, source: 'Source Test');

      await tester.pumpWidget(buildTestApp(quote: quote));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);
      final expectedColors = QuoteCardColors.fromHex(null, theme.colorScheme);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
      expect(card.color, expectedColors.cardColor);
    });

    testWidgets('degrades gracefully when colorHex is empty string',
        (WidgetTester tester) async {
      final quote = createTestQuote(colorHex: '', source: 'Source Test');

      await tester.pumpWidget(buildTestApp(quote: quote));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
    });

    testWidgets('degrades gracefully when colorHex is invalid hex',
        (WidgetTester tester) async {
      final quote =
          createTestQuote(colorHex: 'invalid-hex', source: 'Source Test');

      await tester.pumpWidget(buildTestApp(quote: quote));

      final BuildContext context = tester.element(find.byType(QuoteCard));
      final theme = Theme.of(context);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, theme.colorScheme.surfaceContainerLowest);
    });
  });

  group('QuoteCard Theme Integration Tests', () {
    testWidgets('renders Card with specified quote color and uses CardTheme',
        (WidgetTester tester) async {
      const cardTheme = CardThemeData(
        margin: EdgeInsets.all(16),
        elevation: 2,
      );
      final themeWithCard = ThemeData(
        brightness: Brightness.light,
        cardTheme: cardTheme,
      );

      final quote = createTestQuote(colorHex: '#F0F0F0');

      await tester.pumpWidget(
        buildTestApp(
          quote: quote,
          theme: themeWithCard,
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, const Color(0xFFF0F0F0));
      expect(card.margin, const EdgeInsets.all(16));
    });
  });
}
