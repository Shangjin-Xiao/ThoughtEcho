import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/web_fetch_service.dart';

void main() {
  group('WebFetchService', () {
    late WebFetchService service;

    setUp(() {
      service = WebFetchService();
    });

    group('connection safety', () {
      late HttpServer server;
      late _LocalSocketOverrides sockets;
      final requests = <HttpRequest>[];
      var redirectLocation = '';

      setUp(() async {
        requests.clear();
        redirectLocation = '';
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        sockets = _LocalSocketOverrides(server.port);
        server.listen((request) async {
          requests.add(request);
          request.response.persistentConnection = false;
          if (request.uri.path == '/redirect') {
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set('location', redirectLocation);
          } else {
            request.response.headers.contentType = ContentType.html;
            request.response.write('<title>Example</title><p>Public page</p>');
          }
          await request.response.close();
        });
      });

      tearDown(() => server.close(force: true));

      for (final method in ['GET', 'HEAD']) {
        Future<Object> fetch(String url) => method == 'GET'
            ? service.fetchText(url)
            : service.isUrlAccessible(url);

        test('$method connects to validated IPs on every redirect hop',
            () async {
          redirectLocation = 'http://93.184.216.35/page';
          final result = await HttpOverrides.runWithHttpOverrides(
            () => IOOverrides.runWithIOOverrides(
              () => fetch('http://93.184.216.34/redirect'),
              sockets,
            ),
            _DirectHttpOverrides(),
          );

          expect(result, method == 'GET' ? contains('Public page') : isTrue);
          // A String here would let the socket layer resolve the host again.
          expect(sockets.targets, hasLength(2));
          expect(sockets.targets, everyElement(isA<InternetAddress>()));
          expect(
            sockets.targets.cast<InternetAddress>().map((ip) => ip.address),
            ['93.184.216.34', '93.184.216.35'],
          );
          expect(requests.map((r) => r.method), [method, method]);
          expect(requests.map((r) => r.headers.host),
              ['93.184.216.34', '93.184.216.35']);
        });

        test('$method blocks a redirect to a private service', () async {
          redirectLocation = 'http://127.0.0.1/private';
          final operation = HttpOverrides.runWithHttpOverrides(
            () => IOOverrides.runWithIOOverrides(
              () => fetch('http://93.184.216.34/redirect'),
              sockets,
            ),
            _DirectHttpOverrides(),
          );

          if (method == 'GET') {
            await expectLater(operation, throwsA(isA<Exception>()));
          } else {
            expect(await operation, isFalse);
          }
          expect(requests.map((r) => r.uri.path), ['/redirect']);
          expect(sockets.targets, hasLength(1));
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

// Keep the real HTTP client and substitute only the socket destination. These
// tests never connect to the public fixture IPs or require external DNS.
final class _LocalSocketOverrides extends IOOverrides {
  final int serverPort;
  final targets = <Object>[];

  _LocalSocketOverrides(this.serverPort);

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    host,
    int port, {
    sourceAddress,
    int sourcePort = 0,
  }) {
    targets.add(host as Object);
    return super.socketStartConnect(InternetAddress.loopbackIPv4, serverPort);
  }
}

class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
