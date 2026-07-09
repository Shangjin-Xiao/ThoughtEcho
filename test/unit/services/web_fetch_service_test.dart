import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/web_fetch_service.dart';

void main() {
  group('WebFetchService', () {
    late WebFetchService service;

    setUp(() {
      service = WebFetchService();
    });

    group('SSRF Protection', () {
      final blockedUrls = [
        'http://localhost:8080',
        'https://127.0.0.1/admin',
        'http://10.0.0.1/metadata',
        'https://192.168.1.1/config',
        'http://172.16.0.1/',
        'http://169.254.169.254/latest/meta-data',
        'http://0.0.0.0/',
        'http://100.64.0.1/',
        'http://[::1]/',
        'http://[::]/',
        'http://[fe80::1]/',
        'http://[::ffff:192.168.1.1]/',
        'http://224.0.0.1/',
        'http://[ff02::1]/',
      ];

      for (final url in blockedUrls) {
        test('fetchText throws Exception for $url', () async {
          expect(
            () => service.fetchText(url),
            throwsA(isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('安全限制：不允许访问本地或私有网络地址'),
            )),
          );
        });

        test('extractMetadata throws Exception for $url', () async {
          expect(
            () => service.extractMetadata(url),
            throwsA(isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('安全限制：不允许访问本地或私有网络地址'),
            )),
          );
        });

        test('isUrlAccessible returns false for $url', () async {
          final isAccessible = await service.isUrlAccessible(url);
          expect(isAccessible, isFalse);
        });
      }

      test('throws Exception for non-http/https url', () async {
        expect(
          () => service.fetchText('ftp://example.com'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('URL 格式无效'),
          )),
        );
      });
    });
  });
}
