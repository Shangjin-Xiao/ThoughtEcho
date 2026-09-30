import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
