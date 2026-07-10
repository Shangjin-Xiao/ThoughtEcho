import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/thoughtecho_discovery_service.dart';

void main() {
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
}
