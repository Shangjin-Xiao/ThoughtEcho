import 'package:thoughtecho/utils/bounded_svg_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';

String patternSvg(String dimensions, {int uses = 1, String extra = ''}) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <pattern id="p" $dimensions patternUnits="userSpaceOnUse">
      <rect width="1" height="1" fill="red"/>
    </pattern>
  </defs>
  $extra
  ${List.filled(uses, '<rect width="100" height="100" fill="url(#p)"/>').join()}
</svg>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dimensions in [
    'width="1024" height="1025"', // Just over the individual pixel budget.
    'width="2049" height="1"', // Excessive single dimension.
    'width="1e100" height="1"', // Overflows float32 in compiled data.
    'width="0" height="10"',
    'width="-1" height="10"',
    'width="0.001" height="0.001"', // Rounds to a zero-sized image.
    'width="1100%" height="1100%"',
  ]) {
    test('rejects unsafe raster dimensions: $dimensions', () async {
      await expectLater(
        BoundedSvgLoader(patternSvg(dimensions)).loadBytes(null),
        throwsFormatException,
      );
    });
  }

  test('rejects inferred pattern dimensions from an oversized viewBox',
      () async {
    await expectLater(
      BoundedSvgLoader(patternSvg('viewBox="0 0 10000 10000"')).loadBytes(null),
      throwsFormatException,
    );
  });

  test('counts repeated uses against the aggregate raster budget', () async {
    await expectLater(
      BoundedSvgLoader(patternSvg('width="1024" height="1024"', uses: 5))
          .loadBytes(null),
      throwsFormatException,
    );
  });

  test('accepts pattern allocations at the individual and aggregate limits',
      () async {
    final bytes = await BoundedSvgLoader(
      patternSvg('width="1024" height="1024"', uses: 4),
    ).loadBytes(null);
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  test('checks pattern commands after embedded image data', () async {
    const image = '<image width="1" height="1" '
        'href="data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j1ioAAAAASUVORK5CYII="/>';
    await expectLater(
      BoundedSvgLoader(patternSvg('width="1024" height="1025"', extra: image))
          .loadBytes(null),
      throwsFormatException,
    );
  });

  test('accepts every built-in card template including texture patterns',
      () async {
    for (final type in CardType.values) {
      final bytes = await BoundedSvgLoader(
        CardTemplates.getTemplateByType(type: type, content: 'Example note'),
      ).loadBytes(null);
      expect(bytes.lengthInBytes, greaterThan(0), reason: type.name);
    }
  });
}
