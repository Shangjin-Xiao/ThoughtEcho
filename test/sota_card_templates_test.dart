import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';

void main() {
  group('SOTA SVG Card Templates Test', () {
    const testContent =
        'This is a SOTA test content to verify the premium visual effects of our new SVG templates.';
    const testBrand = 'ThoughtEcho';
    const testAuthor = 'Sisyphus';
    const testDate = 'Jan 22, 2026';

    test('sotaModernTemplate should contain mesh gradient and shadow elements',
        () {
      final svg = CardTemplates.sotaModernTemplate(
        brandName: testBrand,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('sotaBlur'));
      expect(svg, contains('cardShadow'));
      expect(svg, contains('sotaOverlay'));
      expect(svg, contains('Inter')); // SOTA Font
      expect(svg, contains(testBrand.toUpperCase()));
      expect(svg, contains(testAuthor));
    });

    test('knowledgeTemplate upgraded with SOTA mesh and icons', () {
      final svg = CardTemplates.knowledgeTemplate(
        brandName: testBrand,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, contains('auroraBlur'));
      expect(svg, contains('textShadow'));
      expect(
          svg,
          contains(
              'M6 17h3l2-4V7H5v6h3l-2 4zm8 0h3l2-4V7h-6v6h3l-2 4z')); // Quote icon path
    });

    test('getTemplateByType handles sotaModern', () {
      final svg = CardTemplates.getTemplateByType(
        brandName: testBrand,
        type: CardType.sotaModern,
        content: testContent,
        author: testAuthor,
        date: testDate,
      );

      expect(svg, contains('sotaBlur'));
    });

    test('Minimalist template upgraded with shadows and Inter font', () {
      final svg = CardTemplates.minimalistTemplate(
        brandName: testBrand,
        content: testContent,
      );

      expect(svg, contains('minimalShadow'));
      expect(svg, contains('Inter'));
    });
  });
}
