import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/localsend/localsend_server.dart';
import 'package:meta/meta.dart';

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
}
