import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thoughtecho/services/web_fetch_service.dart';

void main() {
  group('WebFetchService', () {
    late WebFetchService service;

    setUp(() {
      service = WebFetchService();
    });

    group('Redirect response bodies', () {
      for (final scenario in [
        for (final status in [301, 302, 303, 307, 308])
          (status: status, location: '/article', error: null),
        (status: 302, location: null, error: '缺少 Location'),
        (status: 302, location: '   ', error: '缺少 Location'),
        (
          status: 302,
          location: 'http://127.0.0.1/private',
          error: '安全限制',
        ),
      ]) {
        test('${scenario.status} ${scenario.location} skips gzip decoding',
            () async {
          var compressedBytesRead = 0;
          var cancelled = false;
          final redirectBody = StreamController<List<int>>(
            onCancel: () => cancelled = true,
          );
          // Model the native client's lazy gzip decoding of a large body.
          redirectBody.add(gzip.encode(List<int>.filled(4 * 1024 * 1024, 65)));
          unawaited(redirectBody.close());
          final requestedUrls = <Uri>[];
          final client = MockClient.streaming((request, body) async {
            await body.toBytes();
            requestedUrls.add(request.url);
            if (request.url.path == '/start') {
              return http.StreamedResponse(
                redirectBody.stream.map((chunk) {
                  compressedBytesRead += chunk.length;
                  return chunk;
                }).transform(gzip.decoder),
                scenario.status,
                headers: {
                  if (scenario.location != null) 'location': scenario.location!,
                  'content-encoding': 'gzip',
                },
              );
            }
            return http.StreamedResponse(
              Stream.value(utf8.encode('<p>Fetched article</p>')),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          });
          addTearDown(client.close);

          final result = http.runWithClient(
            () => service.fetchText('http://203.0.113.1/start'),
            () => client,
          );
          if (scenario.error == null) {
            expect(await result, 'Fetched article');
            expect(requestedUrls, [
              Uri.parse('http://203.0.113.1/start'),
              Uri.parse('http://203.0.113.1/article'),
            ]);
          } else {
            await expectLater(
                result,
                throwsA(predicate<Object>(
                  (error) => error.toString().contains(scenario.error!),
                )));
            expect(requestedUrls, hasLength(1));
          }
          expect(cancelled, isTrue);
          expect(compressedBytesRead, 0,
              reason: 'Unused redirect bodies must not reach the gzip decoder');
        });
      }
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
