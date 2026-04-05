import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/backup_progress_update_gate.dart';
import '../../test_setup.dart';

void main() {
  setUp(() async {
    await setupTestEnvironment();
  });

  group('BackupProgressUpdateGate', () {
    test('always allows first progress update', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final shouldUpdate = gate.shouldUpdate(
        progressPercent: 10,
        stageKey: 'collect',
        now: DateTime(2026, 1, 1, 0, 0, 0, 0),
      );

      expect(shouldUpdate, isTrue);
    });

    test('throttles frequent updates in same stage', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final t0 = DateTime(2026, 1, 1, 0, 0, 0, 0);
      expect(
        gate.shouldUpdate(progressPercent: 10, stageKey: 'media', now: t0),
        isTrue,
      );

      final shouldUpdate = gate.shouldUpdate(
        progressPercent: 11,
        stageKey: 'media',
        now: t0.add(const Duration(milliseconds: 30)),
      );

      expect(shouldUpdate, isFalse);
    });

    test('allows update after interval when progress changes', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final t0 = DateTime(2026, 1, 1, 0, 0, 0, 0);
      expect(
        gate.shouldUpdate(progressPercent: 10, stageKey: 'media', now: t0),
        isTrue,
      );

      final shouldUpdate = gate.shouldUpdate(
        progressPercent: 11,
        stageKey: 'media',
        now: t0.add(const Duration(milliseconds: 90)),
      );

      expect(shouldUpdate, isTrue);
    });

    test('allows stage changes immediately', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final t0 = DateTime(2026, 1, 1, 0, 0, 0, 0);
      expect(
        gate.shouldUpdate(progressPercent: 40, stageKey: 'media', now: t0),
        isTrue,
      );

      final shouldUpdate = gate.shouldUpdate(
        progressPercent: 41,
        stageKey: 'zip',
        now: t0.add(const Duration(milliseconds: 20)),
      );

      expect(shouldUpdate, isTrue);
    });

    test('always allows completion update', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final t0 = DateTime(2026, 1, 1, 0, 0, 0, 0);
      expect(
        gate.shouldUpdate(progressPercent: 98, stageKey: 'zip', now: t0),
        isTrue,
      );

      final shouldUpdate = gate.shouldUpdate(
        progressPercent: 100,
        stageKey: 'verify',
        now: t0.add(const Duration(milliseconds: 20)),
      );

      expect(shouldUpdate, isTrue);
    });

    test('reset allows next backup first progress update', () {
      final gate = BackupProgressUpdateGate(
        minUpdateInterval: const Duration(milliseconds: 80),
      );

      final t0 = DateTime(2026, 1, 1, 0, 0, 0, 0);
      expect(
        gate.shouldUpdate(progressPercent: 40, stageKey: 'media', now: t0),
        isTrue,
      );

      gate.reset();

      final shouldUpdateAfterReset = gate.shouldUpdate(
        progressPercent: 40,
        stageKey: 'media',
        now: t0.add(const Duration(milliseconds: 20)),
      );

      expect(shouldUpdateAfterReset, isTrue);
    });
  });

  group('backup stage mapping', () {
    test('uses media stage from 35 percent', () {
      expect(resolveBackupStageKey(34), 'note');
      expect(resolveBackupStageKey(35), 'media');
    });
  });
}
