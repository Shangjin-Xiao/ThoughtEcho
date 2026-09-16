import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/agent_memory.dart';

void main() {
  group('AgentMemoryRecentSlice', () {
    final observedAt = DateTime.utc(2026, 9, 10, 8, 30);
    final expiresAt = DateTime.utc(2026, 9, 24, 8, 30);

    test('round-trips a custom id, timestamps, and source note ids', () {
      final slice = AgentMemoryRecentSlice(
        id: 'recent-project',
        content: '最近在重构记忆系统',
        observedAt: observedAt,
        expiresAt: expiresAt,
        sourceNoteIds: const ['note-1', 'note-2'],
      );

      final restored = AgentMemoryRecentSlice.fromMap(slice.toMap());

      expect(restored.id, 'recent-project');
      expect(restored.content, slice.content);
      expect(restored.observedAt, observedAt);
      expect(restored.expiresAt, expiresAt);
      expect(restored.sourceNoteIds, ['note-1', 'note-2']);
    });

    test('uses the singleton id for legacy rows without an id', () {
      final restored = AgentMemoryRecentSlice.fromMap({
        'content': '旧版近况',
        'observed_at': observedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      });

      expect(restored.id, AgentMemoryRecentSlice.singletonId);
      expect(restored.sourceNoteIds, isEmpty);
    });

    test('treats invalid timestamps as expired instead of injecting them', () {
      final restored = AgentMemoryRecentSlice.fromMap(const {
        'id': 'corrupt',
        'content': '时间字段损坏的近况',
        'observed_at': 'not-a-date',
        'expires_at': 'also-not-a-date',
      });

      expect(restored.observedAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(restored.expiresAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(restored.isExpiredAt(DateTime.utc(2026)), isTrue);
    });

    test('expires exactly at the boundary and not one instant before', () {
      final slice = AgentMemoryRecentSlice(
        content: '边界近况',
        observedAt: observedAt,
        expiresAt: expiresAt,
      );

      expect(
        slice.isExpiredAt(expiresAt.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(slice.isExpiredAt(expiresAt), isTrue);
    });

    test('copyWith changes selected fields and preserves the rest', () {
      final original = AgentMemoryRecentSlice(
        id: 'original',
        content: '原始近况',
        observedAt: observedAt,
        expiresAt: expiresAt,
        sourceNoteIds: const ['note-1'],
      );

      final updated = original.copyWith(id: 'updated', content: '更新后的近况');

      expect(updated.id, 'updated');
      expect(updated.content, '更新后的近况');
      expect(updated.observedAt, observedAt);
      expect(updated.expiresAt, expiresAt);
      expect(updated.sourceNoteIds, ['note-1']);
    });
  });

  group('MemoryCompactionStats', () {
    test('totalPruned sums every pruning category', () {
      const stats = MemoryCompactionStats(
        expiredSlicesPruned: 1,
        supersededProfilesPruned: 2,
        decayedFactsPruned: 3,
        duplicatesPruned: 4,
      );

      expect(stats.totalPruned, 10);
      expect(const MemoryCompactionStats().totalPruned, 0);
    });
  });
}
