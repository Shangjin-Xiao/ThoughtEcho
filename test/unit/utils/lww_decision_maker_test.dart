import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/lww_utils.dart';

void main() {
  group('LWWDecisionMaker', () {
    test('remote newer -> useRemote', () {
      final d = LWWDecisionMaker.makeDecision(
        localTimestamp: '2024-01-01T00:00:00.000Z',
        remoteTimestamp: '2025-01-01T00:00:00.000Z',
        localContent: 'A',
        remoteContent: 'B',
        checkContentSimilarity: true,
      );
      expect(d.shouldUseRemote, true);
      expect(d.hasConflict, false);
    });

    test('local newer -> useLocal', () {
      final d = LWWDecisionMaker.makeDecision(
        localTimestamp: '2025-01-01T00:00:00.000Z',
        remoteTimestamp: '2024-01-01T00:00:00.000Z',
        localContent: 'A',
        remoteContent: 'B',
        checkContentSimilarity: true,
      );
      expect(d.shouldUseLocal, true);
    });

    test('same timestamp same content -> useLocal (no conflict)', () {
      final d = LWWDecisionMaker.makeDecision(
        localTimestamp: '2025-01-01T00:00:00.000Z',
        remoteTimestamp: '2025-01-01T00:00:00.000Z',
        localContent: 'A',
        remoteContent: 'A',
        checkContentSimilarity: true,
      );
      expect(d.shouldUseLocal, true);
      expect(d.hasConflict, false);
    });

    test('same timestamp different content -> conflict', () {
      final d = LWWDecisionMaker.makeDecision(
        localTimestamp: '2025-01-01T00:00:00.000Z',
        remoteTimestamp: '2025-01-01T00:00:00.000Z',
        localContent: 'A',
        remoteContent: 'B',
        checkContentSimilarity: true,
      );
      expect(d.hasConflict, true);
      expect(d.shouldUseLocal, false);
      expect(d.shouldUseRemote, false);
    });
  });
}
