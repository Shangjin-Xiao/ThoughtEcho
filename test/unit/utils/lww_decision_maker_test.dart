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

    test('rejects remote timestamp > 24h ahead with useLocal and clockSkew',
        () {
      final refNow = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final futureRemote = refNow
          .add(LWWUtils.maxFutureSkew + const Duration(seconds: 1))
          .toIso8601String();
      final olderLocal =
          refNow.subtract(const Duration(days: 10)).toIso8601String();

      final decision = LWWDecisionMaker.makeDecision(
        localTimestamp: olderLocal,
        remoteTimestamp: futureRemote,
        localContent: 'local',
        remoteContent: 'remote',
        checkContentSimilarity: true,
        now: refNow,
      );

      expect(decision.decision, LWWDecision.useLocal);
      expect(decision.shouldUseLocal, isTrue);
      expect(decision.shouldUseRemote, isFalse);
      expect(decision.hasConflict, isFalse);
      expect(
        decision.clockSkew,
        LWWUtils.maxFutureSkew + const Duration(seconds: 1),
      );
      expect(decision.reason, contains('24小时'));
    });

    test('allows remote timestamp within 24h skew (23h ahead) to win', () {
      final refNow = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final allowedFutureRemote =
          refNow.add(const Duration(hours: 23)).toIso8601String();
      final local =
          refNow.subtract(const Duration(minutes: 5)).toIso8601String();

      final decision = LWWDecisionMaker.makeDecision(
        localTimestamp: local,
        remoteTimestamp: allowedFutureRemote,
        now: refNow,
      );

      expect(decision.decision, LWWDecision.useRemote);
      expect(decision.shouldUseRemote, isTrue);
      expect(decision.clockSkew, const Duration(hours: 23));
    });
  });
}
