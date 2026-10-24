import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/optimized_image_loader.dart';

void main() {
  group('OptimizedImageLoader', () {
    group('isInlineDataImage', () {
      test('delegates to isDataUrl and returns true for valid data URL', () {
        const source = 'data:image/png;base64,abc';
        expect(isInlineDataImage(source), isTrue);
      });

      test('delegates to isDataUrl and returns false for standard web URL', () {
        const source = 'https://example.com/image.png';
        expect(isInlineDataImage(source), isFalse);
      });
    });
  });
}
