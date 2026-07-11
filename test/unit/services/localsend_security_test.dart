import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:thoughtecho/services/media_sync_manifest.dart';

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
}
