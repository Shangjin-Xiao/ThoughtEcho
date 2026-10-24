import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:thoughtecho/services/pdf_font_service.dart';
import 'package:thoughtecho/theme/theme_style.dart';

ByteData _buildFontDataWithTables(List<String> tableTags) {
  final data = ByteData(12 + tableTags.length * 16);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tableTags.length);
  for (var index = 0; index < tableTags.length; index++) {
    final tag = tableTags[index];
    final offset = 12 + index * 16;
    for (var charIndex = 0; charIndex < tag.length; charIndex++) {
      data.setUint8(offset + charIndex, tag.codeUnitAt(charIndex));
    }
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PdfFontService.resetAllCachesForTesting();
    PdfFontService.disableExternalLoadingForTesting = true;
  });

  tearDown(() {
    PdfFontService.resetAllCachesForTesting();
  });

  group('PdfFontService Unit Tests', () {
    test('isValidFontData correctly validates font format magic numbers', () {
      // Standard TTF (0x00010000)
      final ttfData = ByteData(4)..setUint32(0, 0x00010000);
      expect(PdfFontService.isValidFontData(ttfData), isTrue);

      // Apple TTF ('true' / 0x74727565)
      final appleTtfData = ByteData(4)..setUint32(0, 0x74727565);
      expect(PdfFontService.isValidFontData(appleTtfData), isTrue);

      // CFF OTF ('OTTO' / 0x4F54544F) - unsupported for PDF Unicode encoding
      final otfData = ByteData(4)..setUint32(0, 0x4F54544F);
      expect(PdfFontService.isValidFontData(otfData), isFalse);

      // TTC ('ttcf' / 0x74746366) - collection format unsupported
      final ttcData = ByteData(4)..setUint32(0, 0x74746366);
      expect(PdfFontService.isValidFontData(ttcData), isFalse);

      // Too short data (<4 bytes)
      final shortData = ByteData(3);
      expect(PdfFontService.isValidFontData(shortData), isFalse);

      // Arbitrary invalid data
      final invalidData = ByteData(4)..setUint32(0, 0xDEADBEEF);
      expect(PdfFontService.isValidFontData(invalidData), isFalse);
    });

    test('isValidEmojiFontData validates presence of CBDT and CBLC tables', () {
      // Valid bitmap emoji font with CBDT and CBLC tables
      final validEmojiData = _buildFontDataWithTables(['CBDT', 'CBLC']);
      expect(PdfFontService.isValidEmojiFontData(validEmojiData), isTrue);

      // Only CBDT missing CBLC
      final cbdtOnly = _buildFontDataWithTables(['CBDT', 'head']);
      expect(PdfFontService.isValidEmojiFontData(cbdtOnly), isFalse);

      // Vector emoji font (COLR/CPAL)
      final vectorEmojiData = _buildFontDataWithTables(['COLR', 'CPAL']);
      expect(PdfFontService.isValidEmojiFontData(vectorEmojiData), isFalse);

      // Header too short for declared tables length
      final truncatedHeader = ByteData(12)
        ..setUint32(0, 0x00010000)
        ..setUint16(4, 5);
      expect(PdfFontService.isValidEmojiFontData(truncatedHeader), isFalse);
    });

    test(
        'takeValidCachedFontDataForTesting returns cached font or clears invalid cache',
        () {
      // Set valid TTF
      final validTtf = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validTtf);
      expect(
          PdfFontService.takeValidCachedFontDataForTesting(), equals(validTtf));

      // Set invalid font data
      final invalidOtf = ByteData(4)..setUint32(0, 0x4F54544F);
      PdfFontService.setCachedFontDataForTesting(invalidOtf);
      expect(PdfFontService.takeValidCachedFontDataForTesting(), isNull);
      // Cache should now be cleared to null
      expect(PdfFontService.takeValidCachedFontDataForTesting(), isNull);
    });

    test('loadFontSet with cached font data produces non-fallback PdfFontSet',
        () async {
      final validFontData = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validFontData);

      final fontSet = await PdfFontService.loadFontSet();
      expect(fontSet.isFallback, isFalse);
      expect(fontSet.regular, isA<pw.Font>());
      expect((fontSet.regular as pw.TtfFont).data, equals(validFontData));
      expect(fontSet.bold, isA<pw.Font>());
      expect(fontSet.italic, isA<pw.Font>());
      expect(fontSet.boldItalic, isA<pw.Font>());
    });

    test(
        'loadFontSet with bundledSerif loads bundled font and includes regular font in fallback list',
        () async {
      final serifFontData = ByteData(4)..setUint32(0, 0x00010000);
      final mainFontData = ByteData(4)..setUint32(0, 0x74727565);

      PdfFontService.setCachedFontDataForTesting(mainFontData);
      PdfFontService.setCachedBundledSerifDataForTesting(serifFontData);

      final fontSet = await PdfFontService.loadFontSet(
          readingFontFamily: ThemeStyleForm.bundledSerif);
      expect(fontSet.isFallback, isFalse);
      expect((fontSet.regular as pw.TtfFont).data, equals(serifFontData));
      expect(fontSet.fallbackFonts, isNotEmpty);
      expect((fontSet.fallbackFonts.first as pw.TtfFont).data,
          equals(mainFontData));
    });

    test('loadFont returns TTF font with cached data when cache is present',
        () async {
      final validTtfData = ByteData(4)..setUint32(0, 0x00010000);
      PdfFontService.setCachedFontDataForTesting(validTtfData);

      final font = await PdfFontService.loadFont();
      expect(font, isA<pw.TtfFont>());
      expect((font as pw.TtfFont).data, equals(validTtfData));
    });

    test('loadFont falls back to Helvetica when no font data is available',
        () async {
      PdfFontService.setCachedFontDataForTesting(null);
      PdfFontService.disableExternalLoadingForTesting = true;

      final font = await PdfFontService.loadFont();
      expect(font, isNot(isA<pw.TtfFont>()));
      expect(font.font, equals(pw.Type1Fonts.helvetica));
    });
  });
}
