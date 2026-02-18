import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/http_response.dart';

void main() {
  group('HttpResponse', () {
    test('constructor should correctly set properties', () {
      const body = '{"message": "success"}';
      const statusCode = 200;
      const headers = {'content-type': 'application/json'};

      final response = HttpResponse(body, statusCode, headers: headers);

      expect(response.body, body);
      expect(response.statusCode, statusCode);
      expect(response.headers, headers);
    });

    test('constructor should use default headers if not provided', () {
      const body = 'Hello';
      const statusCode = 200;

      final response = HttpResponse(body, statusCode);

      expect(response.headers, const {});
    });

    group('contentLength', () {
      test(
        'should return parsed integer when content-length header is present',
        () {
          const body = '123';
          final response = HttpResponse(
            body,
            200,
            headers: {'content-length': '5'},
          );
          // 验证头部值优先且不依赖于 body 长度 (3)
          expect(response.contentLength, 5);
        },
      );

      test(
        'should return 0 when content-length header is "0" even if body is not empty',
        () {
          const body = 'not empty';
          final response = HttpResponse(
            body,
            200,
            headers: {'content-length': '0'},
          );
          expect(response.contentLength, 0);
        },
      );

      test('should be case-insensitive for content-length header', () {
        const body = '12345';
        final response = HttpResponse(
          body,
          200,
          headers: {'Content-Length': '10'},
        );
        expect(response.contentLength, 10);
      });

      test(
        'should return body length when content-length header is missing',
        () {
          const body = 'Hello World';
          final response = HttpResponse(body, 200);
          expect(response.contentLength, body.length);
        },
      );

      test('should return null when content-length header is invalid', () {
        const body = 'test';
        final response = HttpResponse(
          body,
          200,
          headers: {'content-length': 'abc'},
        );
        expect(response.contentLength, isNull);
      });

      test('should handle empty body when header is missing', () {
        final response = HttpResponse('', 200);
        expect(response.contentLength, 0);
      });
    });

    test('toString should return the body content', () {
      const body = 'response body';
      final response = HttpResponse(body, 200);
      expect(response.toString(), body);
    });
  });
}
