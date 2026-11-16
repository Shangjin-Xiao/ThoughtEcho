import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

Datagram _buildPeerDatagram({
  String ip = '192.168.1.50',
  int sourcePort = 53317,
  int advertisedPort = 53320,
  String fingerprint = 'peer-fp-1',
  String alias = 'Peer Device',
  bool isAnnouncement = false,
}) {
  final dto = ThoughtEchoDiscoveryService.buildAnnouncement(
    alias: alias,
    deviceModel: 'Peer Model',
    fingerprint: fingerprint,
    serverPort: advertisedPort,
    isAnnouncement: isAnnouncement,
  );
  return Datagram(
    Uint8List.fromList(utf8.encode(jsonEncode(dto.toJson()))),
    InternetAddress(ip),
    sourcePort,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.initialize();
  });

  test('discovery reply advertises the active server port', () {
    final dto = ThoughtEchoDiscoveryService.buildAnnouncement(
      alias: 'Test Device',
      deviceModel: 'Test Model',
      fingerprint: 'test-fingerprint',
      serverPort: 54321,
      isAnnouncement: false,
    );

    expect(dto.port, 54321);
    expect(dto.announcement, isFalse);
    expect(dto.announce, isFalse);
  });

  test('every peer announcement requires a reply', () {
    final announcement = ThoughtEchoDiscoveryService.buildAnnouncement(
      alias: 'Peer',
      deviceModel: 'Peer Model',
      fingerprint: 'peer-fingerprint',
      serverPort: 53317,
      isAnnouncement: true,
    );

    expect(
      ThoughtEchoDiscoveryService.shouldReplyToAnnouncement(announcement),
      isTrue,
    );
    expect(
      ThoughtEchoDiscoveryService.shouldReplyToAnnouncement(announcement),
      isTrue,
    );
  });

  group('UDP multicast endpoint rate limiting', () {
    late DateTime currentTime;
    late ThoughtEchoDiscoveryService service;

    setUp(() {
      currentTime = DateTime.utc(2026, 1, 1, 12, 0, 0);
      service = ThoughtEchoDiscoveryService()
        ..nowProviderForTesting = () => currentTime;
      addTearDown(service.dispose);
    });

    test(
      'accepts first packet, drops rapid burst within 500ms, and accepts again after cooldown',
      () {
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
          isTrue,
        );

        // Rapid burst within 500ms cooldown must be dropped and must not extend cooldown.
        for (final elapsedMs in [1, 100, 250, 499]) {
          currentTime = DateTime.utc(2026, 1, 1, 12, 0, 0, elapsedMs);
          expect(
            service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
            isFalse,
            reason: 'Expected drop at ${elapsedMs}ms within 500ms window',
          );
        }

        // Exactly at 500ms boundary, packet is accepted again.
        currentTime = DateTime.utc(2026, 1, 1, 12, 0, 0, 500);
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
          isTrue,
        );

        // Next burst immediately after acceptance is dropped again.
        currentTime = DateTime.utc(2026, 1, 1, 12, 0, 0, 750);
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
          isFalse,
        );
      },
    );

    test('rate-limits distinct ports and IPs independently', () {
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
        isTrue,
      );

      currentTime = currentTime.add(const Duration(milliseconds: 50));
      // Same IP:port is rate-limited.
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53317),
        isFalse,
      );
      // Different port on same IP is accepted independently.
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.10', 53318),
        isTrue,
      );
      // Different IP on same port is accepted independently.
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.11', 53317),
        isTrue,
      );

      expect(service.trackedRateLimitEndpointCountForTesting, 3);
    });

    test(
      'caps tracked endpoints at maxRateLimitEndpoints and prunes stale then oldest entries',
      () {
        const cap = ThoughtEchoDiscoveryService.maxRateLimitEndpoints;
        expect(cap, 512);

        // Fill table with 300 older endpoints at t0 and 212 newer endpoints at t0 + 400ms.
        for (var i = 0; i < 300; i++) {
          expect(
            service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 10000 + i),
            isTrue,
          );
        }
        currentTime = currentTime.add(const Duration(milliseconds: 400));
        for (var i = 300; i < cap; i++) {
          expect(
            service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 10000 + i),
            isTrue,
          );
        }
        expect(service.trackedRateLimitEndpointCountForTesting, cap);

        // At t0 + 600ms, the first 300 entries are stale (>= 500ms) while the
        // remaining 212 entries are only 200ms old. Adding one more endpoint
        // should prune all 300 stale entries first.
        currentTime = DateTime.utc(2026, 1, 1, 12, 0, 0, 600);
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 20000),
          isTrue,
        );
        expect(service.trackedRateLimitEndpointCountForTesting, 213);

        // Now flood fresh spoofed source ports within 50ms to exceed cap.
        currentTime = currentTime.add(const Duration(milliseconds: 10));
        for (var i = 0; i < 400; i++) {
          expect(
            service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 30000 + i),
            isTrue,
          );
        }

        // Table must remain strictly capped at 512.
        expect(service.trackedRateLimitEndpointCountForTesting, cap);

        // Oldest fresh entries (e.g., 10300) were evicted, while newest (30399) remain throttled.
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 30399),
          isFalse,
        );
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.99', 10300),
          isTrue,
        );
        expect(service.trackedRateLimitEndpointCountForTesting, cap);
      },
    );

    test(
      'handleMulticastMessageForTesting discovers first packet and ignores burst within cooldown',
      () {
        var notifications = 0;
        service.addListener(() {
          notifications++;
        });

        // First datagram from peer endpoint adds device and notifies once.
        service.handleMulticastMessageForTesting(
          _buildPeerDatagram(
            ip: '192.168.1.50',
            sourcePort: 53317,
            advertisedPort: 53320,
            fingerprint: 'peer-fp-1',
            alias: 'Peer One',
            isAnnouncement: true,
          ),
        );

        expect(service.devices, hasLength(1));
        expect(service.devices.single.ip, '192.168.1.50');
        expect(service.devices.single.port, 53320);
        expect(service.devices.single.fingerprint, 'peer-fp-1');
        expect(notifications, 1);

        // Burst datagrams from the same ip:port within 500ms—even with distinct
        // payload ports/fingerprints—are dropped before processing.
        currentTime = currentTime.add(const Duration(milliseconds: 100));
        for (var i = 0; i < 5; i++) {
          service.handleMulticastMessageForTesting(
            _buildPeerDatagram(
              ip: '192.168.1.50',
              sourcePort: 53317,
              advertisedPort: 53321 + i,
              fingerprint: 'burst-fp-$i',
              alias: 'Burst $i',
              isAnnouncement: true,
            ),
          );
        }

        expect(service.devices, hasLength(1));
        expect(service.devices.single.fingerprint, 'peer-fp-1');
        expect(notifications, 1);

        // Same peer re-announcing after 500ms cooldown is processed cleanly
        // without duplicating the existing device entry or re-notifying.
        currentTime = currentTime.add(const Duration(milliseconds: 400));
        service.handleMulticastMessageForTesting(
          _buildPeerDatagram(
            ip: '192.168.1.50',
            sourcePort: 53317,
            advertisedPort: 53320,
            fingerprint: 'peer-fp-1',
            alias: 'Peer One',
            isAnnouncement: false,
          ),
        );

        expect(service.devices, hasLength(1));
        expect(notifications, 1);

        // After another 500ms cooldown, a distinct peer behind the endpoint is
        // accepted again, confirming the rate limit truly lifted.
        currentTime = currentTime.add(const Duration(milliseconds: 500));
        service.handleMulticastMessageForTesting(
          _buildPeerDatagram(
            ip: '192.168.1.50',
            sourcePort: 53317,
            advertisedPort: 53325,
            fingerprint: 'peer-fp-after-cooldown',
            alias: 'Peer Two',
            isAnnouncement: false,
          ),
        );

        expect(service.devices, hasLength(2));
        expect(service.devices.last.fingerprint, 'peer-fp-after-cooldown');
        expect(notifications, 2);
      },
    );

    test('clearDevices and stopDiscovery clear tracked rate-limit state',
        () async {
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.20', 53317),
        isTrue,
      );
      expect(service.trackedRateLimitEndpointCountForTesting, 1);

      service.clearDevices();
      expect(service.trackedRateLimitEndpointCountForTesting, 0);

      // Same endpoint is immediately accepted again after clearDevices().
      expect(
        service.shouldAcceptDatagramFromEndpoint('192.168.1.20', 53317),
        isTrue,
      );
      expect(service.trackedRateLimitEndpointCountForTesting, 1);

      await service.stopDiscovery();
      expect(service.trackedRateLimitEndpointCountForTesting, 0);
    });

    test(
      'shouldAcceptDatagramFromEndpoint recovers immediately on backward clock adjustment',
      () {
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.77', 53317),
          isTrue,
        );

        // System clock rolls back 1 hour: must NOT drop packets for 1 hour.
        currentTime = currentTime.subtract(const Duration(hours: 1));
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.77', 53317),
          isTrue,
        );

        // Rate limiting resumes relative to the new rolled-back timestamp.
        currentTime = currentTime.add(const Duration(milliseconds: 100));
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.77', 53317),
          isFalse,
        );
        currentTime = currentTime.add(const Duration(milliseconds: 500));
        expect(
          service.shouldAcceptDatagramFromEndpoint('192.168.1.77', 53317),
          isTrue,
        );
      },
    );
  });
}
