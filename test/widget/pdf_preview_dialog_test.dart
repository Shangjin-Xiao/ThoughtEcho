import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/pdf_preview_dialog.dart';

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

  testWidgets('PdfPreviewDialog renders properly and displays title',
      (WidgetTester tester) async {
    final pdfBytes = Uint8List.fromList([37, 80, 68, 70, 45]); // %PDF-

    await tester.pumpWidget(
      buildTestableWidget(
        PdfPreviewDialog(
          pdfBytes: pdfBytes,
          fileName: 'test.pdf',
        ),
      ),
    );

    expect(find.byType(PdfPreviewDialog), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
