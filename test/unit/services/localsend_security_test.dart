import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/localsend/localsend_send_provider.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/session_status.dart';
import 'package:thoughtecho/services/localsend/receive_controller.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  _FakeHttpHeaders(this.contentType);

  @override
  final ContentType? contentType;
}

class _FakeUploadRequest extends Fake implements HttpRequest {
  _FakeUploadRequest({
    Stream<Uint8List>? body,
    ContentType? contentType,
  })  : _body = body ??
            Stream<Uint8List>.fromIterable([
              Uint8List.fromList([1, 2, 3, 4]),
            ]),
        _headers = _FakeHttpHeaders(contentType);

  final Stream<Uint8List> _body;
  final _FakeHttpHeaders _headers;

  @override
  HttpHeaders get headers => _headers;

  @override
  Stream<R> cast<R>() => _body.cast<R>();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _body.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

// Extension to access private method for testing
extension LocalSendServerTest on LocalSendServer {
  bool testIsSafeAddress(InternetAddress address) {
    // We can't easily access private method from another file even with extension
    // unless it's in the same library or we use a workaround.
    // Since I can't change the library structure easily, I might make it visible for testing in the source.
    return isSafeAddressForTesting(address);
  }
}

void main() {
  group('LocalSendServer Security Tests', () {
    late LocalSendServer server;

    setUp(() {
      server = LocalSendServer();
    });

    test('isSafeAddress identifies loopback addresses as safe', () {
      expect(
        server.isSafeAddressForTesting(InternetAddress('127.0.0.1')),
        isTrue,
      );
      expect(server.isSafeAddressForTesting(InternetAddress('::1')), isTrue);
    });

    test('isSafeAddress identifies link-local addresses as safe', () {
      expect(
        server.isSafeAddressForTesting(InternetAddress('169.254.1.1')),
        isTrue,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('fe80::1')),
        isTrue,
      );
    });

    test('isSafeAddress identifies private IPv4 ranges as safe', () {
      expect(
        server.isSafeAddressForTesting(InternetAddress('10.0.0.1')),
        isTrue,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('10.255.255.255')),
        isTrue,
      );

      expect(
        server.isSafeAddressForTesting(InternetAddress('172.16.0.1')),
        isTrue,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('172.31.255.255')),
        isTrue,
      );

      expect(
        server.isSafeAddressForTesting(InternetAddress('192.168.1.1')),
        isTrue,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('192.168.255.255')),
        isTrue,
      );
    });

    test('isSafeAddress identifies private IPv6 (ULA) as safe', () {
      expect(
        server.isSafeAddressForTesting(InternetAddress('fd00::1')),
        isTrue,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('fc00::1')),
        isTrue,
      );
    });

    test('isSafeAddress identifies public addresses as unsafe', () {
      expect(
        server.isSafeAddressForTesting(InternetAddress('8.8.8.8')),
        isFalse,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('1.1.1.1')),
        isFalse,
      );
      expect(
        server.isSafeAddressForTesting(InternetAddress('2001:4860:4860::8888')),
        isFalse,
      );
    });
  });

  group('LocalSendServer preparation approval', () {
    for (final route in [
      '/api/localsend/v2/prepare-upload',
      '/api/localsend/v1/send-request',
    ]) {
      test(
        'intent approval cannot authorize a claimed fingerprint on $route',
        () async {
          final server = LocalSendServer();
          addTearDown(server.stop);
          final approvalSizes = <int>[];
          var allowPreparation = false;
          await server.start(
            port: 0,
            onReceiveSessionCreated: (_, __, ___) {},
            onApprovalNeeded: (_, totalBytes, __) async {
              approvalSizes.add(totalBytes);
              return totalBytes == 0 || allowPreparation;
            },
          );

          final sender = HttpClient();
          final attacker = HttpClient();
          addTearDown(sender.close);
          addTearDown(attacker.close);
          Future<(int, Map<String, dynamic>)> post(
            HttpClient client,
            String path,
            Map<String, dynamic> body,
          ) async {
            final request = await client.postUrl(
              Uri.parse('http://127.0.0.1:${server.port}$path'),
            );
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode(body));
            final response = await request.close();
            return (
              response.statusCode,
              jsonDecode(await utf8.decoder.bind(response).join())
                  as Map<String, dynamic>,
            );
          }

          final (
            _,
            intent,
          ) = await post(sender, '/api/thoughtecho/v1/sync-intent', {
            'intentId': 'approved-intent',
            'fingerprint': 'public-sender-fingerprint',
            'alias': 'Sender',
          });
          expect(intent['approved'], isTrue);

          final preparation = {
            'info': {
              'alias': 'Sender',
              'fingerprint': 'public-sender-fingerprint',
            },
            'files': {
              'file-1': {
                'id': 'file-1',
                'fileName': 'package.zip',
                'size': 4,
                'fileType': 'application/zip',
              },
            },
          };
          final (deniedStatus, deniedBody) = await post(
            attacker,
            route,
            preparation,
          );
          expect(deniedStatus, isNot(HttpStatus.ok));
          expect(deniedBody, isNot(contains('files')));
          expect(approvalSizes, [0, 4]);

          allowPreparation = true;
          final (approvedStatus, approvedBody) = await post(
            sender,
            route,
            preparation,
          );
          expect(approvedStatus, HttpStatus.ok);
          expect(approvedBody['sessionId'], isA<String>());
          expect(approvedBody['files']['file-1'], isA<String>());
          expect(approvalSizes, [0, 4, 4]);
        },
      );
    }
  });

  group('LocalSendServer media manifest approval', () {
    test('returns media manifest only after approval', () async {
      final server = LocalSendServer();
      addTearDown(server.stop);
      var manifestRequests = 0;
      await server.start(
        port: 0,
        onReceiveSessionCreated: (_, __, ___) {},
        onApprovalNeeded: (_, __, ___) async => true,
        onMediaManifestRequested: () async {
          manifestRequests++;
          return const MediaSyncManifest({'images/photo.jpg': 3});
        },
      );

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/thoughtecho/v1/sync-intent',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'intentId': 'intent-approved',
        'fingerprint': 'sender',
        'alias': 'Sender',
      }));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;

      expect(body['approved'], isTrue);
      expect(body['mediaManifest'], {
        'version': 1,
        'files': {'images/photo.jpg': 3},
      });
      expect(manifestRequests, 1);
    });

    test('does not return or scan media manifest after rejection', () async {
      final server = LocalSendServer();
      addTearDown(server.stop);
      var manifestRequests = 0;
      await server.start(
        port: 0,
        onReceiveSessionCreated: (_, __, ___) {},
        onApprovalNeeded: (_, __, ___) async => false,
        onMediaManifestRequested: () async {
          manifestRequests++;
          return const MediaSyncManifest({});
        },
      );

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/thoughtecho/v1/sync-intent',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'intentId': 'intent-rejected',
        'fingerprint': 'sender',
        'alias': 'Sender',
      }));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;

      expect(body['approved'], isFalse);
      expect(body, isNot(contains('mediaManifest')));
      expect(manifestRequests, 0);
    });
  });

  group('LocalSendServer CSRF Origin & DNS Rebinding Host Hardening', () {
    test('isValidHostHeaderForTesting validates allowed and blocked hosts', () {
      final server = LocalSendServer();

      final validHosts = [
        'localhost',
        'LOCALHOST',
        'localhost:53320',
        'LOCALHOST:53320',
        'localhost:1',
        'localhost:65535',
        '127.0.0.1',
        '127.0.0.1:53320',
        '192.168.1.10:53320',
        '10.0.0.5:8080',
        '172.16.0.1:53320',
        '169.254.1.1:53320',
        '[::1]',
        '[::1]:53320',
        '[fe80::1]',
        '[fe80::1]:53320',
        '[fe80::1%eth0]:53320',
        '[fd00::1]:53320',
        '::1',
        'fe80::1',
        'fd00::1',
      ];
      for (final host in validHosts) {
        expect(
          server.isValidHostHeaderForTesting(host),
          isTrue,
          reason: 'Expected valid host: $host',
        );
      }

      final invalidHosts = [
        null,
        '',
        '   ',
        'localhost ',
        ' localhost',
        'localhost/evil',
        r'localhost\evil',
        'user@localhost',
        'localhost\r\n',
        'evil.com',
        'evil.com:53320',
        'evil.localhost',
        'evil.localhost:53320',
        '8.8.8.8',
        '8.8.8.8:53320',
        '0.0.0.0:53320',
        '[2001:4860:4860::8888]:53320',
        '2001:4860:4860::8888',
        '[::]',
        'localhost:0',
        'localhost:65536',
        'localhost:+80',
        'localhost:-1',
        'localhost:abc',
        'localhost:',
        '[::1',
        '::1]',
        '[fe80::1%]:53320',
        '[127.0.0.1]:53320',
        '127.0.0.1:53320:80',
      ];
      for (final host in invalidHosts) {
        expect(
          server.isValidHostHeaderForTesting(host),
          isFalse,
          reason: 'Expected invalid host: $host',
        );
      }
    });

    test('rejects non-empty Origin header with 403 across endpoints', () async {
      final server = LocalSendServer();
      addTearDown(server.stop);
      var approvalCalled = false;
      await server.start(
        port: 0,
        onReceiveSessionCreated: (_, __, ___) {
          approvalCalled = true;
        },
        onApprovalNeeded: (_, __, ___) async {
          approvalCalled = true;
          return true;
        },
      );

      final client = HttpClient();
      addTearDown(client.close);

      final endpoints = [
        ('GET', '/api/localsend/v2/info', null),
        ('POST', '/api/localsend/v2/register', '{}'),
        (
          'POST',
          '/api/thoughtecho/v1/sync-intent',
          jsonEncode({'alias': 'Sender', 'fingerprint': 'fp'}),
        ),
        (
          'POST',
          '/api/localsend/v2/prepare-upload',
          jsonEncode({
            'info': {'alias': 'Sender'},
            'files': {
              'f1': {
                'id': 'f1',
                'fileName': 'note.txt',
                'size': 4,
                'fileType': 'text/plain',
              },
            },
          }),
        ),
        (
          'POST',
          '/api/localsend/v2/upload?sessionId=s1&fileId=f1&token=t1',
          'data',
        ),
      ];

      for (final (method, path, body) in endpoints) {
        for (final origin in ['https://evil.com', 'null']) {
          final request = await client.openUrl(
            method,
            Uri.parse('http://127.0.0.1:${server.port}$path'),
          );
          request.headers.set('Origin', origin);
          if (body != null) {
            request.headers.contentType = ContentType.json;
            request.write(body);
          }
          final response = await request.close();
          await response.drain<void>();
          expect(
            response.statusCode,
            HttpStatus.forbidden,
            reason: 'Expected 403 for $method $path with Origin=$origin',
          );
        }
      }
      expect(approvalCalled, isFalse);

      // Whitespace-only Origin header is treated as empty and allowed.
      final okReq = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/api/localsend/v2/info'),
      );
      okReq.headers.set('Origin', '   ');
      final okResp = await okReq.close();
      await okResp.drain<void>();
      expect(okResp.statusCode, HttpStatus.ok);
    });

    test('rejects DNS rebinding Host headers and missing Host with 403',
        () async {
      final server = LocalSendServer();
      addTearDown(server.stop);
      await server.start(port: 0);

      final client = HttpClient();
      addTearDown(client.close);

      for (final badHost in [
        'evil.com:53320',
        '8.8.8.8:53320',
        'evil.localhost',
        '[2001:4860:4860::8888]:53320',
      ]) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/localsend/v2/info'),
        );
        request.headers.set(HttpHeaders.hostHeader, badHost);
        final response = await request.close();
        await response.drain<void>();
        expect(
          response.statusCode,
          HttpStatus.forbidden,
          reason: 'Expected 403 for Host=$badHost',
        );
      }

      for (final goodHost in [
        'localhost',
        'LOCALHOST:${server.port}',
        '127.0.0.1:${server.port}',
        '192.168.1.10:${server.port}',
        '[::1]:${server.port}',
        '[fe80::1]:${server.port}',
      ]) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/localsend/v2/info'),
        );
        request.headers.set(HttpHeaders.hostHeader, goodHost);
        final response = await request.close();
        await response.drain<void>();
        expect(
          response.statusCode,
          HttpStatus.ok,
          reason: 'Expected 200 for Host=$goodHost',
        );
      }

      // Raw HTTP/1.0 request with no Host header must fail closed with 403.
      final socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      socket.write('GET /api/localsend/v2/info HTTP/1.0\r\n\r\n');
      await socket.flush();
      final rawResponse = await utf8.decoder.bind(socket).join();
      expect(rawResponse, startsWith('HTTP/1.0 403'));
    });
  });

  group('LocalSendServer Sender Metadata Propagation', () {
    test(
        'sync-intent emits onSenderInfoReceived before onReceiveSessionCreated (explicit and fallback port)',
        () async {
      final server = LocalSendServer();
      addTearDown(server.stop);

      final events = <String>[];
      final received = <(String, String?, int?, String?)>[];

      await server.start(
        port: 0,
        onSenderInfoReceived: (sid, ip, port, fp) {
          events.add('senderInfo:$sid');
          received.add((sid, ip, port, fp));
        },
        onReceiveSessionCreated: (sid, _, __) {
          events.add('sessionCreated:$sid');
        },
        onApprovalNeeded: (_, __, ___) async => true,
      );

      final client = HttpClient();
      addTearDown(client.close);

      Future<void> sendIntent(Map<String, dynamic> payload) async {
        final req = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.port}/api/thoughtecho/v1/sync-intent',
          ),
        );
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(payload));
        final resp = await req.close();
        expect(resp.statusCode, HttpStatus.ok);
        await resp.drain<void>();
      }

      await sendIntent({
        'intentId': 'intent-with-port',
        'alias': 'Sender A',
        'port': 53325,
        'fingerprint': '  fp-sync-1  ',
      });

      await sendIntent({
        'intentId': 'intent-fallback-port',
        'alias': 'Sender B',
        'fingerprint': '   ',
      });

      expect(events, [
        'senderInfo:intent-with-port',
        'sessionCreated:intent-with-port',
        'senderInfo:intent-fallback-port',
        'sessionCreated:intent-fallback-port',
      ]);

      expect(
          received[0], ('intent-with-port', '127.0.0.1', 53325, 'fp-sync-1'));
      expect(received[1].$1, 'intent-fallback-port');
      expect(received[1].$2, '127.0.0.1');
      expect(received[1].$3, isNull);
      expect(received[1].$4, isNull);
    });

    for (final route in [
      '/api/localsend/v2/prepare-upload',
      '/api/localsend/v1/send-request',
    ]) {
      test(
          '$route emits onSenderInfoReceived before onReceiveSessionCreated (explicit and fallback port)',
          () async {
        final server = LocalSendServer();
        addTearDown(server.stop);

        final events = <String>[];
        final received = <(String, String?, int?, String?)>[];

        await server.start(
          port: 0,
          onSenderInfoReceived: (sid, ip, port, fp) {
            events.add('senderInfo:$sid');
            received.add((sid, ip, port, fp));
          },
          onReceiveSessionCreated: (sid, _, __) {
            events.add('sessionCreated:$sid');
          },
          onApprovalNeeded: (_, __, ___) async => true,
        );

        final client = HttpClient();
        addTearDown(client.close);

        Future<String> sendPrepare(Map<String, dynamic> info) async {
          final req = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}$route'),
          );
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode({
            'info': info,
            'files': {
              'f1': {
                'id': 'f1',
                'fileName': 'notes.json',
                'size': 4,
                'fileType': 'application/json',
              },
            },
          }));
          final resp = await req.close();
          expect(resp.statusCode, HttpStatus.ok);
          final body = jsonDecode(await utf8.decoder.bind(resp).join())
              as Map<String, dynamic>;
          return body['sessionId'] as String;
        }

        final sid1 = await sendPrepare({
          'alias': 'Sender A',
          'port': 53329,
          'fingerprint': '  fp-prep-1  ',
        });
        final sid2 = await sendPrepare({
          'alias': 'Sender B',
          'fingerprint': '',
        });

        expect(events, [
          'senderInfo:$sid1',
          'sessionCreated:$sid1',
          'senderInfo:$sid2',
          'sessionCreated:$sid2',
        ]);

        expect(received[0], (sid1, '127.0.0.1', 53329, 'fp-prep-1'));
        expect(received[1].$1, sid2);
        expect(received[1].$2, '127.0.0.1');
        expect(received[1].$3, isNull);
        expect(received[1].$4, isNull);
      });
    }
  });

  group('ReceiveController Hardening', () {
    void cleanupReceivedFile(String path) {
      addTearDown(() async {
        final file = File(path);
        final parent = file.parent;
        if (p.basename(parent.path).startsWith('thoughtecho_recv_')) {
          if (await parent.exists()) {
            await parent.delete(recursive: true);
          }
        } else if (await file.exists()) {
          await file.delete();
        }
      });
    }

    Map<String, dynamic> buildPreparePayload({
      Map<String, Map<String, dynamic>>? files,
    }) {
      return {
        'info': {
          'alias': 'Test Sender',
          'fingerprint': 'sender-fp',
          'port': 53320,
        },
        'files': files ??
            {
              'file-1': {
                'id': 'file-1',
                'fileName': 'note.txt',
                'size': 4,
                'fileType': 'text/plain',
              },
            },
      };
    }

    test(
        'consumes single-use upload token on success, failure, and concurrency',
        () async {
      final controller = ReceiveController(
        onApprovalNeeded: (_, __, ___) async => true,
        onFileReceived: cleanupReceivedFile,
      );
      addTearDown(controller.dispose);

      // 1) Replay after success on 1-file session (finished) and 2-file session (Invalid token).
      final prepSingle = await controller.handlePrepareUpload(
        buildPreparePayload(),
      );
      final singleSid = prepSingle['sessionId'] as String;
      final singleTok = prepSingle['files']['file-1'] as String;

      await controller.handleFileUpload(
        singleSid,
        'file-1',
        singleTok,
        _FakeUploadRequest(),
      );
      expect(
        controller.getSession(singleSid)!.status,
        SessionStatus.finished,
      );
      expect(
        controller.getSession(singleSid)!.completedFileIds,
        {'file-1'},
      );
      await expectLater(
        controller.handleFileUpload(
          singleSid,
          'file-1',
          singleTok,
          _FakeUploadRequest(),
        ),
        throwsException,
      );

      final prepTwo = await controller.handlePrepareUpload(
        buildPreparePayload(
          files: {
            'file-1': {
              'id': 'file-1',
              'fileName': 'one.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
            'file-2': {
              'id': 'file-2',
              'fileName': 'two.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
          },
        ),
      );
      final twoSid = prepTwo['sessionId'] as String;
      final twoTok1 = prepTwo['files']['file-1'] as String;
      final twoTok2 = prepTwo['files']['file-2'] as String;

      await controller.handleFileUpload(
        twoSid,
        'file-1',
        twoTok1,
        _FakeUploadRequest(),
      );
      expect(
        controller.getSession(twoSid)!.status,
        SessionStatus.sending,
      );
      await expectLater(
        controller.handleFileUpload(
          twoSid,
          'file-1',
          twoTok1,
          _FakeUploadRequest(),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid token'),
          ),
        ),
      );
      await controller.handleFileUpload(
        twoSid,
        'file-2',
        twoTok2,
        _FakeUploadRequest(),
      );
      expect(
        controller.getSession(twoSid)!.status,
        SessionStatus.finished,
      );
      expect(
        controller.getSession(twoSid)!.completedFileIds,
        {'file-1', 'file-2'},
      );

      // 2) Replay after failure: empty stream consumes token and marks 1-file session finishedWithErrors.
      final prepFail = await controller.handlePrepareUpload(
        buildPreparePayload(),
      );
      final failSid = prepFail['sessionId'] as String;
      final failTok = prepFail['files']['file-1'] as String;
      await expectLater(
        controller.handleFileUpload(
          failSid,
          'file-1',
          failTok,
          _FakeUploadRequest(body: const Stream<Uint8List>.empty()),
        ),
        throwsException,
      );
      expect(
        controller.getSession(failSid)!.status,
        SessionStatus.finishedWithErrors,
      );
      await expectLater(
        controller.handleFileUpload(
          failSid,
          'file-1',
          failTok,
          _FakeUploadRequest(),
        ),
        throwsException,
      );

      // 2b) Replay after failure on 2-file session rejects with Invalid token without killing file-2.
      final prepTwoFail = await controller.handlePrepareUpload(
        buildPreparePayload(
          files: {
            'file-1': {
              'id': 'file-1',
              'fileName': 'one.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
            'file-2': {
              'id': 'file-2',
              'fileName': 'two.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
          },
        ),
      );
      final twoFailSid = prepTwoFail['sessionId'] as String;
      final twoFailTok1 = prepTwoFail['files']['file-1'] as String;
      await expectLater(
        controller.handleFileUpload(
          twoFailSid,
          'file-1',
          twoFailTok1,
          _FakeUploadRequest(body: const Stream<Uint8List>.empty()),
        ),
        throwsException,
      );
      expect(
        controller.getSession(twoFailSid)!.status,
        SessionStatus.sending,
      );
      await expectLater(
        controller.handleFileUpload(
          twoFailSid,
          'file-1',
          twoFailTok1,
          _FakeUploadRequest(),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid token'),
          ),
        ),
      );

      // 3) Concurrent replay fails with Invalid token while original upload succeeds.
      final prepConcurrent = await controller.handlePrepareUpload(
        buildPreparePayload(),
      );
      final concSid = prepConcurrent['sessionId'] as String;
      final concTok = prepConcurrent['files']['file-1'] as String;
      final slowStream = StreamController<Uint8List>();

      final firstUpload = controller.handleFileUpload(
        concSid,
        'file-1',
        concTok,
        _FakeUploadRequest(body: slowStream.stream),
      );
      final concurrentReplay = controller.handleFileUpload(
        concSid,
        'file-1',
        concTok,
        _FakeUploadRequest(),
      );

      await expectLater(
        concurrentReplay,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid token'),
          ),
        ),
      );

      slowStream.add(Uint8List.fromList([1, 2, 3, 4]));
      await slowStream.close();
      final result = await firstUpload;
      expect(result['size'], 4);
      expect(
        controller.getSession(concSid)!.status,
        SessionStatus.finished,
      );
    });

    test('enforces deterministic session expiry via nowProvider', () async {
      var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final controller = ReceiveController(
        onApprovalNeeded: (_, __, ___) async => true,
        onFileReceived: cleanupReceivedFile,
        nowProvider: () => fakeNow,
      );
      addTearDown(controller.dispose);

      // Within 2-minute timeout succeeds.
      final prepValid = await controller.handlePrepareUpload(
        buildPreparePayload(),
      );
      fakeNow = fakeNow.add(const Duration(minutes: 2));
      final validRes = await controller.handleFileUpload(
        prepValid['sessionId'] as String,
        'file-1',
        prepValid['files']['file-1'] as String,
        _FakeUploadRequest(),
      );
      expect(validRes['size'], 4);

      // Strictly past 2-minute timeout fails with Session expired and removes session.
      final prepExpired = await controller.handlePrepareUpload(
        buildPreparePayload(),
      );
      final expiredSid = prepExpired['sessionId'] as String;
      fakeNow = fakeNow.add(const Duration(minutes: 2, seconds: 1));
      await expectLater(
        controller.handleFileUpload(
          expiredSid,
          'file-1',
          prepExpired['files']['file-1'] as String,
          _FakeUploadRequest(),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Session expired'),
          ),
        ),
      );
      expect(controller.getSession(expiredSid), isNull);
    });

    test('rejects path traversal and enforces safe extension whitelist',
        () async {
      final controller = ReceiveController(
        onApprovalNeeded: (_, __, ___) async => true,
        onFileReceived: cleanupReceivedFile,
      );
      addTearDown(controller.dispose);

      for (final badName in [
        '../evil.zip',
        'a/b.zip',
        r'a\b.zip',
        'bad\x00.zip',
        '',
      ]) {
        final prep = await controller.handlePrepareUpload(
          buildPreparePayload(
            files: {
              'file-1': {
                'id': 'file-1',
                'fileName': badName,
                'size': 4,
                'fileType': 'application/zip',
              },
            },
          ),
        );
        await expectLater(
          controller.handleFileUpload(
            prep['sessionId'] as String,
            'file-1',
            prep['files']['file-1'] as String,
            _FakeUploadRequest(),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Invalid file name'),
            ),
          ),
          reason: 'Expected Invalid file name for "$badName"',
        );
      }

      for (final blockedName in [
        'payload.exe',
        'app.apk',
        'page.html',
        'vector.svg',
        'script.js',
        'no_extension',
        '.zip',
      ]) {
        final prep = await controller.handlePrepareUpload(
          buildPreparePayload(
            files: {
              'file-1': {
                'id': 'file-1',
                'fileName': blockedName,
                'size': 4,
                'fileType': 'application/octet-stream',
              },
            },
          ),
        );
        await expectLater(
          controller.handleFileUpload(
            prep['sessionId'] as String,
            'file-1',
            prep['files']['file-1'] as String,
            _FakeUploadRequest(),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Blocked file type'),
            ),
          ),
          reason: 'Expected Blocked file type for "$blockedName"',
        );
      }

      for (final allowedName in ['backup.zip', 'photo.jpg', 'clip.mp4']) {
        final prep = await controller.handlePrepareUpload(
          buildPreparePayload(
            files: {
              'file-1': {
                'id': 'file-1',
                'fileName': allowedName,
                'size': 4,
                'fileType': 'application/octet-stream',
              },
            },
          ),
        );
        final res = await controller.handleFileUpload(
          prep['sessionId'] as String,
          'file-1',
          prep['files']['file-1'] as String,
          _FakeUploadRequest(),
        );
        expect(res['size'], 4, reason: 'Expected $allowedName to succeed');
      }
    });

    test(
        'sequential failure then success on remaining file finalizes session as finishedWithErrors',
        () async {
      final controller = ReceiveController(
        onApprovalNeeded: (_, __, ___) async => true,
        onFileReceived: cleanupReceivedFile,
      );
      addTearDown(controller.dispose);

      final prep = await controller.handlePrepareUpload(
        buildPreparePayload(
          files: {
            'file-1': {
              'id': 'file-1',
              'fileName': 'one.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
            'file-2': {
              'id': 'file-2',
              'fileName': 'two.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
          },
        ),
      );
      final sid = prep['sessionId'] as String;
      final tok1 = prep['files']['file-1'] as String;
      final tok2 = prep['files']['file-2'] as String;

      await expectLater(
        controller.handleFileUpload(
          sid,
          'file-1',
          tok1,
          _FakeUploadRequest(body: const Stream<Uint8List>.empty()),
        ),
        throwsException,
      );
      expect(controller.getSession(sid)!.status, SessionStatus.sending);
      expect(controller.getSession(sid)!.failedFileIds, {'file-1'});

      final res2 = await controller.handleFileUpload(
        sid,
        'file-2',
        tok2,
        _FakeUploadRequest(),
      );
      expect(res2['size'], 4);
      final settled = controller.getSession(sid)!;
      expect(settled.status, SessionStatus.finishedWithErrors);
      expect(settled.completedFileIds, {'file-2'});
      expect(settled.failedFileIds, {'file-1'});
    });

    test(
        'concurrent multi-file failure does not abort sibling streaming upload',
        () async {
      final receivedPaths = <String>[];
      final controller = ReceiveController(
        onApprovalNeeded: (_, __, ___) async => true,
        onFileReceived: (path) {
          receivedPaths.add(path);
          cleanupReceivedFile(path);
        },
      );
      addTearDown(controller.dispose);

      final prep = await controller.handlePrepareUpload(
        buildPreparePayload(
          files: {
            'file-1': {
              'id': 'file-1',
              'fileName': 'fail.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
            'file-2': {
              'id': 'file-2',
              'fileName': 'ok.txt',
              'size': 4,
              'fileType': 'text/plain',
            },
          },
        ),
      );
      final sid = prep['sessionId'] as String;
      final tok1 = prep['files']['file-1'] as String;
      final tok2 = prep['files']['file-2'] as String;

      final stream1 = StreamController<Uint8List>();
      final stream2 = StreamController<Uint8List>();

      final upload1 = controller.handleFileUpload(
        sid,
        'file-1',
        tok1,
        _FakeUploadRequest(body: stream1.stream),
      );
      final upload2 = controller.handleFileUpload(
        sid,
        'file-2',
        tok2,
        _FakeUploadRequest(body: stream2.stream),
      );

      // Both tokens are now consumed and both uploads are streaming.
      stream2.add(Uint8List.fromList([1, 2]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.getSession(sid)!.fileTokens, isEmpty);

      // Fail upload1 while upload2 is still mid-stream.
      stream1.addError(const SocketException('simulated disconnect'));
      await stream1.close();
      await expectLater(upload1, throwsException);

      // Session MUST remain sending so sibling upload2 is not aborted!
      expect(controller.getSession(sid)!.status, SessionStatus.sending);
      expect(controller.getSession(sid)!.failedFileIds, {'file-1'});

      // Complete upload2 cleanly.
      stream2.add(Uint8List.fromList([3, 4]));
      await stream2.close();
      final res2 = await upload2;
      expect(res2['size'], 4);

      final finalSession = controller.getSession(sid)!;
      expect(finalSession.status, SessionStatus.finishedWithErrors);
      expect(finalSession.completedFileIds, {'file-2'});
      expect(finalSession.failedFileIds, {'file-1'});
      expect(receivedPaths, hasLength(1));
      expect(
        p.basename(File(receivedPaths.single).parent.path),
        startsWith('thoughtecho_recv_'),
      );
    });
  });

  group('LocalSendProvider & Windows Path / Retry Recovery', () {
    test(
        'extractFileName strips Windows backslash and POSIX directory prefixes',
        () {
      expect(
        LocalSendProvider.extractFileName(
          r'C:\Temp\thoughtecho_backup_123.zip',
        ),
        'thoughtecho_backup_123.zip',
      );
      expect(
        LocalSendProvider.extractFileName(r'\\server\share\notes.json'),
        'notes.json',
      );
      expect(
        LocalSendProvider.extractFileName('/tmp/thoughtecho_backup_123.zip'),
        'thoughtecho_backup_123.zip',
      );
    });

    test(
        'startSession forwards localPort and recovers from consumed-token disconnect via re-prepare and re-approval',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final originalOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = originalOverrides);

      final tempDir = await Directory.systemTemp.createTemp('ls_retry_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File(p.join(tempDir.path, 'backup_payload.zip'));
      await sourceFile.writeAsBytes(List<int>.generate(64, (i) => i));

      final receivedFiles = <String>[];
      final receivedSenderPorts = <int?>[];
      var approvalCalls = 0;
      var uploadHttpAttempts = 0;

      final controller = ReceiveController(
        onSenderInfoReceived: (_, __, port, ___) {
          receivedSenderPorts.add(port);
        },
        onApprovalNeeded: (_, __, ___) async {
          approvalCalls++;
          return true;
        },
        onFileReceived: (path) {
          receivedFiles.add(path);
          addTearDown(() async {
            final f = File(path);
            if (await f.parent.exists()) {
              await f.parent.delete(recursive: true);
            }
          });
        },
      );
      addTearDown(controller.dispose);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/api/localsend/v2/info') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(controller.handleInfoRequest()));
          await request.response.close();
          return;
        }
        if (path == '/api/localsend/v2/prepare-upload') {
          final raw = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(raw) as Map<String, dynamic>;
          final res = await controller.handlePrepareUpload(
            payload,
            remoteIp: request.connectionInfo?.remoteAddress.address,
            remotePort: request.connectionInfo?.remotePort,
          );
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(res));
          await request.response.close();
          return;
        }
        if (path == '/api/localsend/v2/upload') {
          uploadHttpAttempts++;
          final sid = request.uri.queryParameters['sessionId']!;
          final fid = request.uri.queryParameters['fileId']!;
          final tok = request.uri.queryParameters['token']!;
          if (uploadHttpAttempts == 1) {
            // Simulate token consumed then connection dropped mid-stream.
            await request.drain<void>();
            try {
              await controller.handleFileUpload(
                sid,
                fid,
                tok,
                _FakeUploadRequest(body: const Stream<Uint8List>.empty()),
              );
            } catch (_) {}
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'error': 'simulated drop'}));
            await request.response.close();
            return;
          }
          final res = await controller.handleFileUpload(sid, fid, tok, request);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(res));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final provider = LocalSendProvider(
        localPort: 53321,
        retryBaseDelay: const Duration(milliseconds: 10),
      );
      addTearDown(provider.dispose);

      final target = Device(
        signalingId: null,
        ip: '127.0.0.1',
        version: '2.1',
        port: server.port,
        https: false,
        fingerprint: 'receiver-fp',
        alias: 'Receiver',
        deviceModel: 'Model',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: const {},
      );

      final progressReports = <int>[];
      final sid = await provider.startSession(
        target: target,
        files: [sourceFile],
        onProgress: (sent, _) => progressReports.add(sent),
      );

      for (int idx = 1; idx < progressReports.length; idx++) {
        expect(progressReports[idx],
            greaterThanOrEqualTo(progressReports[idx - 1]));
      }
      expect(approvalCalls, 2);
      expect(uploadHttpAttempts, 2);
      expect(receivedSenderPorts, [53321, 53321]);
      expect(receivedFiles, hasLength(1));
      expect(await File(receivedFiles.single).length(), 64);
      expect(provider.getSession(sid)!.status, SessionStatus.finished);
    });

    test(
        'startSession stops retrying immediately when re-prepare is rejected by receiver',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final originalOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = originalOverrides);

      final tempDir = await Directory.systemTemp.createTemp('ls_reject_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final sourceFile = File(p.join(tempDir.path, 'backup_payload.zip'));
      await sourceFile.writeAsBytes(List<int>.generate(16, (i) => i));

      var approvalCalls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        if (path == '/api/localsend/v2/info') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({'alias': 'Peer'}));
          await request.response.close();
          return;
        }
        if (path == '/api/localsend/v2/prepare-upload') {
          await request.drain<void>();
          approvalCalls++;
          if (approvalCalls == 1) {
            request.response.statusCode = HttpStatus.ok;
            request.response.write(
              jsonEncode({
                'sessionId': 'remote-s1',
                'files': {'file_0': 'tok-1'},
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'error': 'Exception: 接收端已拒绝'}));
          }
          await request.response.close();
          return;
        }
        if (path == '/api/localsend/v2/upload') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(jsonEncode({'error': 'transient error'}));
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final provider = LocalSendProvider(
        retryBaseDelay: const Duration(milliseconds: 10),
      );
      addTearDown(provider.dispose);

      final target = Device(
        signalingId: null,
        ip: '127.0.0.1',
        version: '2.1',
        port: server.port,
        https: false,
        fingerprint: 'receiver-fp',
        alias: 'Receiver',
        deviceModel: 'Model',
        deviceType: DeviceType.desktop,
        download: true,
        discoveryMethods: const {},
      );

      await expectLater(
        provider.startSession(target: target, files: [sourceFile]),
        throwsException,
      );
      expect(approvalCalls, 2);
    });
  });
}
