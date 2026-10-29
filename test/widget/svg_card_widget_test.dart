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
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<!-- stroke-dasharray="0.1" -->'
        '<rect width="100" height="100" style="fill:blue"/>'
        '<text x="1" y="20">stroke-dasharray</text></svg>';

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

  final dashedContents = {
    'path attribute': '<path d="M0 0 L10 0" stroke="blue" '
        'stroke-dasharray="0.1 0.1"/>',
    'inherited group attribute': '<g stroke="blue" stroke-dasharray="0.1 0.1">'
        '<path d="M0 0 C1 1 9 1 10 0"/></g>',
    'inline style': '<path d="M0 0 L10 0" '
        'style="stroke:blue; stroke-dasharray : 0.1 0.1"/>',
    'XML-encoded inline style': '<path d="M0 0 L10 0" '
        'style="stroke:blue;stroke-dash&#97;rray&#58;0.1 0.1"/>',
    'namespaced attribute': '<path xmlns:s="urn:example" d="M0 0 L10 0" '
        'stroke="blue" s:stroke-dasharray="0.1 0.1"/>',
  };

  for (final entry in dashedContents.entries) {
    testWidgets('SVGCardWidget rejects dash arrays in ${entry.key}',
        (tester) async {
      await tester.pumpWidget(buildTestableWidget(SVGCardWidget(
        svgContent: '<svg xmlns="http://www.w3.org/2000/svg" '
            'viewBox="0 0 100 100">${entry.value}</svg>',
      )));

      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });
  }
}
