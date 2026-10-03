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
