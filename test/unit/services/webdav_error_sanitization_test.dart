import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/quill_delta_builder.dart';

void main() {
  group('WebDAV Error Sanitization Unit Tests', () {
    test('Sanitizes HTTP 507 Insufficient Storage error correctly', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          statusCode: 507,
          statusMessage: 'Insufficient Storage',
        ),
      );

      final result =
          WebDAVSyncService.sanitizeSyncErrorForTesting(dioException);
      expect(result, equals('服务器存储空间不足'));
    });

    test('Sanitizes raw string HTTP 507 status code error correctly', () {
      const errorStr = 'HttpException: statusCode: 507, Insufficient Storage';
      final result = WebDAVSyncService.sanitizeSyncErrorForTesting(errorStr);
      expect(result, equals('服务器存储空间不足'));
    });

    test('Sanitizes HTTP 401 and 403 Authentication errors correctly', () {
      final dioException401 = DioException(
        requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          statusCode: 401,
        ),
      );

      final dioException403 = DioException(
        requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          statusCode: 403,
        ),
      );

      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(dioException401),
        equals('认证失败，请检查用户名和密码'),
      );
      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(dioException403),
        equals('认证失败，请检查用户名和密码'),
      );
    });

    test('Sanitizes HTTP 404 Not Found error correctly', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          statusCode: 404,
        ),
      );

      final result =
          WebDAVSyncService.sanitizeSyncErrorForTesting(dioException);
      expect(result, equals('服务器路径不存在，请检查地址配置'));
    });

    test('Sanitizes SocketException and Network connection errors', () {
      const socketError =
          SocketException('Failed host lookup: dav.example.com');
      const networkError = 'Connection refused by dav.example.com';

      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(socketError),
        equals('无法连接到服务器，请检查网络和地址'),
      );
      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(networkError),
        equals('无法连接到服务器，请检查网络和地址'),
      );
    });

    test('Sanitizes SSL Handshake and Certificate errors', () {
      const sslError = HandshakeException('CERTIFICATE_VERIFY_FAILED');

      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(sslError),
        equals('SSL 证书验证失败'),
      );
    });

    test('Sanitizes Timeout errors', () {
      final timeoutError = TimeoutException('Request timed out after 15s');

      expect(
        WebDAVSyncService.sanitizeSyncErrorForTesting(timeoutError),
        equals('连接超时，请检查网络'),
      );
    });

    test('Masks embedded sensitive URLs and credentials', () {
      const rawErrorWithCredentials =
          'Error connecting to https://user:secretpassword123@dav.example.com:8443/dav/notes/backup.zip: detail info';

      final sanitized = WebDAVSyncService.sanitizeSyncErrorForTesting(
          rawErrorWithCredentials);

      expect(sanitized, contains('[服务器地址]'));
      expect(sanitized, isNot(contains('secretpassword123')));
      expect(sanitized, isNot(contains('dav.example.com')));
    });
  });

  group('Quill Delta Safe Parsing Unit Tests', () {
    test('Handles null and empty deltaContent safely', () {
      final quote = Quote(
        id: '1',
        content: 'Hello World',
        date: '2026-07-24T00:00:00Z',
        deltaContent: null,
      );

      expect(
          quote.safeDeltaOps,
          equals([
            {'insert': 'Hello World'},
            {'insert': '\n'}
          ]));
      expect(quote.safeDeltaContent, contains('Hello World'));
    });

    test('Handles malformed JSON string gracefully without throwing exception',
        () {
      final quote = Quote(
        id: '2',
        content: 'PlainText Fallback',
        date: '2026-07-24T00:00:00Z',
        deltaContent: 'INVALID_JSON_{"ops": [unclosed',
      );

      expect(() => quote.safeDeltaOps, returnsNormally);
      expect(
          quote.safeDeltaOps,
          equals([
            {'insert': 'PlainText Fallback'},
            {'insert': '\n'}
          ]));
      expect(quote.safeDeltaContent, contains('PlainText Fallback'));
    });

    test('Handles invalid ops list elements gracefully', () {
      final quote = Quote(
        id: '3',
        content: 'Fallback Test',
        date: '2026-07-24T00:00:00Z',
        deltaContent: '{"ops": ["invalid_string_op", 123]}',
      );

      expect(() => quote.safeDeltaOps, returnsNormally);
      expect(
          quote.safeDeltaOps,
          equals([
            {'insert': 'Fallback Test'},
            {'insert': '\n'}
          ]));
    });

    test('Parses valid deltaContent JSON correctly', () {
      const validDelta = '{"ops":[{"insert":"Rich Text\\n"}]}';
      final quote = Quote(
        id: '4',
        content: 'Rich Text',
        date: '2026-07-24T00:00:00Z',
        deltaContent: validDelta,
      );

      expect(
          quote.safeDeltaOps,
          equals([
            {'insert': 'Rich Text\n'}
          ]));
    });

    test('DeltaBuilder.deltaFromJson handles malformed inputs safely', () {
      expect(DeltaBuilder.deltaFromJson(null), isNull);
      expect(DeltaBuilder.deltaFromJson(''), isNull);
      expect(DeltaBuilder.deltaFromJson('invalid json'), isNull);
      expect(DeltaBuilder.deltaFromJson('{"invalid": true}'), isNull);
      expect(DeltaBuilder.deltaFromJson('["not", "a", "map"]'), isNull);
      expect(
        DeltaBuilder.deltaFromJson('{"ops":[{"insert":"Hello"}]}'),
        equals([
          {'insert': 'Hello'}
        ]),
      );
    });
  });
}
