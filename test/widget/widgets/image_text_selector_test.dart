import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/app_empty_view.dart';
import 'package:thoughtecho/widgets/local_ai/image_text_selector.dart';

void main() {
  Widget buildTestApp({
    required List<Rect> detectedRegions,
    Function(Rect)? onRegionSelected,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImageTextSelector(
        imagePath: 'dummy/path.png',
        detectedRegions: detectedRegions,
        onRegionSelected: onRegionSelected,
      ),
    );
  }

  testWidgets('renders AppEmptyView and region selection works correctly',
      (WidgetTester tester) async {
    Rect? selectedRegion;
    final regions = [
      const Rect.fromLTWH(10, 10, 100, 50),
    ];

    await tester.pumpWidget(
      buildTestApp(
        detectedRegions: regions,
        onRegionSelected: (region) {
          selectedRegion = region;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyView), findsOneWidget);

    // Confirm button is initially not visible
    expect(find.byType(FilledButton), findsNothing);

    // Tap on region
    final regionFinder = find.byType(GestureDetector).first;
    await tester.tap(regionFinder);
    await tester.pumpAndSettle();

    expect(selectedRegion, equals(regions[0]));
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
