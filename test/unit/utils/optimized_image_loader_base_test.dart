import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/optimized_image_loader_base.dart';

void main() {
  group('OptimizedImageLoaderBase', () {
    group('isDataUrl', () {
      test('returns true for valid data URL', () {
        const source = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
        expect(isDataUrl(source), isTrue);
      });

      test('returns false for http URL', () {
        const source = 'http://example.com/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for https URL', () {
        const source = 'https://example.com/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for file URL', () {
        const source = 'file:///path/to/image.png';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for empty string', () {
        const source = '';
        expect(isDataUrl(source), isFalse);
      });

      test('returns false for string starting with data without colon', () {
        const source = 'database';
        expect(isDataUrl(source), isFalse);
      });
    });

    group('tryDecodeDataUrl', () {
      test('returns correct bytes for valid base64 data URL', () {
        // Base64 encoded "Hello World"
        const base64Data = 'SGVsbG8gV29ybGQ=';
        const source = 'data:text/plain;base64,$base64Data';

        final result = tryDecodeDataUrl(source);

        expect(result, isNotNull);
        expect(String.fromCharCodes(result!), 'Hello World');
      });

      test('returns correct bytes for valid percent-encoded data URL', () {
        // Percent encoded "Hello World"
        const source = 'data:text/plain,Hello%20World';

        final result = tryDecodeDataUrl(source);

        expect(result, isNotNull);
        expect(String.fromCharCodes(result!), 'Hello World');
      });

      test('returns null for non-data URL', () {
        const source = 'http://example.com/image.png';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for malformed data URL scheme', () {
        // Missing comma
        const source = 'data:text/plain;base64SGVsbG8gV29ybGQ=';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for invalid base64 content', () {
        // Invalid base64 characters
        const source = 'data:text/plain;base64,INVALID_BASE64_\$%';
        expect(tryDecodeDataUrl(source), isNull);
      });

      test('returns null for empty string', () {
        expect(tryDecodeDataUrl(''), isNull);
      });

      test('returns null for data URL without data', () {
         // data: is a valid scheme, but uri.data is parsed based on content.
         // 'data:' -> uri.data is empty but not null.
         // 'data:,' -> empty data.
         // Let's test a case where uri.data might be problematic or simply check empty data behavior.

         // 'data:' parses as scheme: data, path: empty. uri.data throws if scheme is not data.
         // But here scheme IS data.
         // uri.data handles parsing. If path is empty, it might be valid empty data.
         // Let's check a case that is technically valid URI but invalid data URI format for content.

         // If we pass something that Uri.parse accepts but doesn't have valid data part?
         // 'data://test' -> scheme: data, host: test.
         // uri.data getter: "The data of a data URI. The URI must have the scheme 'data' and no authority."
         // So 'data://test' has authority 'test'. accessing uri.data should throw or return null?
         // Documentation says: "If the URI does not have the 'data' scheme, or has an authority, this getter throws a StateError."
         // The implementation of tryDecodeDataUrl catches exceptions.

         const source = 'data://test';
         expect(tryDecodeDataUrl(source), isNull);
      });
    });
  });
}
