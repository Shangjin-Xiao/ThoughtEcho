library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/mdns_discovery_service.dart';

void main() {
  group('MDNSServiceRegistration', () {
    late MDNSServiceRegistration registration;

    setUp(() async {
      registration = MDNSServiceRegistration();
      await registration.unregisterService();
    });

    tearDown(() async {
      await registration.unregisterService();
    });

    test('does not report registration success without native support',
        () async {
      final registered = await registration.registerService(
        name: 'ThoughtEcho Test',
        port: 53317,
      );

      expect(registered, isFalse);
      expect(registration.isRegistered, isFalse);
    });
  });
}
