import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/delta_to_pdf_parser.dart';
import 'package:thoughtecho/services/pdf_font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF Export and Parser Tests', () {
    test('DeltaToPdfParser parses empty deltaContent successfully', () {
      final quote = Quote(
        content: 'Hello, this is a plain text note.',
        date: '2026-05-31',
      );
      final font = pw.Font.helvetica();
      final widgets = DeltaToPdfParser.parse(quote, font);

      expect(widgets, isNotEmpty);
      expect(widgets.first, isA<pw.Paragraph>());
    });

    test('DeltaToPdfParser parses structured deltaContent rich text', () {
      final deltaJson =
          '[{"insert": "Rich Text Body "}, {"insert": "bold text", "attributes": {"bold": true}}, {"insert": "\\n"}]';
      final quote = Quote(
        content: 'Rich Text Body bold text\n',
        date: '2026-05-31',
        deltaContent: deltaJson,
      );
      final font = pw.Font.helvetica();
      final widgets = DeltaToPdfParser.parse(quote, font);

      expect(widgets, isNotEmpty);
      expect(widgets.first, isA<pw.Container>());
    });

    test(
        'PdfFontService returns default system font if local and network fonts fail',
        () async {
      final font = await PdfFontService.loadFont();
      expect(font, isNotNull);
    });
  });
}
