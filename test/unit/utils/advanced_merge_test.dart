import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/lww_utils.dart';
import 'package:thoughtecho/utils/string_utils.dart';

void main() {
  group('高级笔记合并与 LWW 决策测试', () {
    test('LWWDecisionMaker 针对不同时间戳做出正确合并决策', () {
      final newerRemote = LWWDecisionMaker.makeDecision(
        localTimestamp: '2026-01-01T10:00:00Z',
        remoteTimestamp: '2026-01-01T11:00:00Z',
      );
      expect(newerRemote.shouldUseRemote, isTrue);
      expect(newerRemote.shouldUseLocal, isFalse);

      final newerLocal = LWWDecisionMaker.makeDecision(
        localTimestamp: '2026-01-01T12:00:00Z',
        remoteTimestamp: '2026-01-01T11:00:00Z',
      );
      expect(newerLocal.shouldUseLocal, isTrue);
      expect(newerLocal.shouldUseRemote, isFalse);
    });

    test('LWWDecisionMaker 对相同时间戳不同内容识别冲突', () {
      final conflictResult = LWWDecisionMaker.makeDecision(
        localTimestamp: '2026-01-01T10:00:00Z',
        remoteTimestamp: '2026-01-01T10:00:00Z',
        localContent: 'Local note content',
        remoteContent: 'Remote note content',
        checkContentSimilarity: true,
      );
      expect(conflictResult.hasConflict, isTrue);
      expect(conflictResult.decision, equals(LWWDecision.conflict));

      final sameContentResult = LWWDecisionMaker.makeDecision(
        localTimestamp: '2026-01-01T10:00:00Z',
        remoteTimestamp: '2026-01-01T10:00:00Z',
        localContent: 'Same content',
        remoteContent: 'Same content',
        checkContentSimilarity: true,
      );
      expect(sameContentResult.shouldUseLocal, isTrue);
      expect(sameContentResult.hasConflict, isFalse);
    });

    test('LWWUtils 时间戳比较与标准化处理', () {
      expect(
        LWWUtils.compareTimestamps(
          '2026-01-01T10:00:00Z',
          '2026-01-01T11:00:00Z',
        ),
        greaterThan(0),
      );

      final newerTs = LWWUtils.getNewerTimestamp(
        '2026-01-01T10:00:00Z',
        '2026-01-01T11:00:00Z',
      );
      expect(newerTs, contains('2026-01-01T11:00:00'));

      final normalized = LWWUtils.normalizeTimestamp('invalid-date');
      expect(normalized, equals('1970-01-01T00:00:00.000Z'));
    });

    test('LWW 拒绝超过24小时的未来时间戳并支持新记录钳制', () {
      final refNow = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final localTs =
          refNow.subtract(const Duration(hours: 1)).toIso8601String();
      final future24h1s = refNow
          .add(LWWUtils.maxFutureSkew + const Duration(seconds: 1))
          .toIso8601String();
      final future23h = refNow.add(const Duration(hours: 23)).toIso8601String();

      final rejected = LWWDecisionMaker.makeDecision(
        localTimestamp: localTs,
        remoteTimestamp: future24h1s,
        now: refNow,
      );
      expect(rejected.shouldUseLocal, isTrue);
      expect(rejected.clockSkew, greaterThan(LWWUtils.maxFutureSkew));

      // 钳制后落库的时间戳回到 refNow，使后续本地编辑能够正常胜出
      final clamped = LWWUtils.clampFutureTimestamp(future24h1s, now: refNow);
      expect(clamped, refNow.toIso8601String());
      final laterLocalEdit =
          refNow.add(const Duration(seconds: 5)).toIso8601String();
      expect(
        LWWDecisionMaker.makeDecision(
          localTimestamp: laterLocalEdit,
          remoteTimestamp: clamped,
          now: refNow,
        ).shouldUseLocal,
        isTrue,
      );

      // 23小时内的小幅正向时钟偏移仍允许按常规 LWW 合并
      expect(
        LWWDecisionMaker.makeDecision(
          localTimestamp: localTs,
          remoteTimestamp: future23h,
          now: refNow,
        ).shouldUseRemote,
        isTrue,
      );
    });

    test('StringUtils 富文本嵌入符清理与文本预览格式化', () {
      final cleaned = StringUtils.removeObjectReplacementChar(
        'Hello\u{FFFC} World!',
      );
      expect(cleaned, equals('Hello World!'));

      final truncated = StringUtils.truncateForPreview('ThoughtEcho Note', 7);
      expect(truncated, equals('Thought...'));
    });
  });
}
