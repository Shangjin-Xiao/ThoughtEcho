import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/delta_to_pdf_parser.dart';
import 'package:thoughtecho/services/pdf_font_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF Export and Parser Tests', () {
    test('DeltaToPdfParser parses empty deltaContent successfully', () async {
      final quote = Quote(
        content: 'Hello, this is a plain text note.',
        date: '2026-05-31',
      );
      final font = pw.Font.helvetica();
      final fontSet = PdfFontSet(
        regular: font,
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      );
      final widgets = await DeltaToPdfParser.parse(quote, fontSet);

      expect(widgets, isNotEmpty);
      expect(widgets.first, isA<pw.Paragraph>());
    });

    test('DeltaToPdfParser parses structured deltaContent rich text', () async {
      final deltaJson =
          '[{"insert": "Rich Text Body "}, {"insert": "bold text", "attributes": {"bold": true}}, {"insert": "\\n"}]';
      final quote = Quote(
        content: 'Rich Text Body bold text\n',
        date: '2026-05-31',
        deltaContent: deltaJson,
      );
      final font = pw.Font.helvetica();
      final fontSet = PdfFontSet(
        regular: font,
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      );
      final widgets = await DeltaToPdfParser.parse(quote, fontSet);

      expect(widgets, isNotEmpty);
      expect(widgets.first, isA<pw.Container>());
    });

    test(
        'PdfFontService returns default system font if local and network fonts fail',
        () async {
      final font = await PdfFontService.loadFont();
      expect(font, isNotNull);
    });

    test('PdfFontService.isValidFontData validates font headers correctly', () {
      // 1. Valid TTF (0x00010000)
      final validTtf = ByteData(4)..setUint32(0, 0x00010000);
      expect(PdfFontService.isValidFontData(validTtf), isTrue);

      // 2. Valid OTF ('OTTO')
      final validOtf = ByteData(4)..setUint32(0, 0x4F54544F);
      expect(PdfFontService.isValidFontData(validOtf), isTrue);

      // 3. Valid Apple TTF ('true')
      final validAppleTtf = ByteData(4)..setUint32(0, 0x74727565);
      expect(PdfFontService.isValidFontData(validAppleTtf), isTrue);

      // 4. Invalid TTC ('ttcf')
      final invalidTtc = ByteData(4)..setUint32(0, 0x74746366);
      expect(PdfFontService.isValidFontData(invalidTtc), isFalse);

      // 5. Too short
      final tooShort = ByteData(3);
      expect(PdfFontService.isValidFontData(tooShort), isFalse);

      // 6. Arbitrary bad header
      final badHeader = ByteData(4)..setUint32(0, 0x12345678);
      expect(PdfFontService.isValidFontData(badHeader), isFalse);
    });
  });
}
