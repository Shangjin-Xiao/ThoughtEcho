import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/delta_log_service.dart';
import 'package:thoughtecho/services/delta_merge_engine.dart';
import 'package:thoughtecho/services/delta_compaction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 21,
        onCreate: (db, version) async {
          final manager = DatabaseSchemaManager();
          await manager.createTables(db);
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('DeltaLogService Tests', () {
    test('Records changes and queries by sequence range', () async {
      await db.transaction((txn) async {
        final seq1 = await DeltaLogService.recordChange(
          txn,
          entityType: 'quote',
          entityId: 'q1',
          action: 'insert',
          payload: {'content': 'Test note 1'},
          timestamp: '2026-10-01T12:00:00Z',
        );
        expect(seq1, equals(1));

        final seq2 = await DeltaLogService.recordChange(
          txn,
          entityType: 'quote',
          entityId: 'q2',
          action: 'insert',
          payload: {'content': 'Test note 2'},
          timestamp: '2026-10-01T12:05:00Z',
        );
        expect(seq2, equals(2));
      });

      expect(await DeltaLogService.getMaxSequence(db), equals(2));
      expect(await DeltaLogService.getMinSequence(db), equals(1));
      expect(await DeltaLogService.getDeltaCount(db), equals(2));

      final deltasAfter1 = await DeltaLogService.getDeltasAfterSequence(db, 1);
      expect(deltasAfter1.length, equals(1));
      expect(deltasAfter1.first['entity_id'], equals('q2'));
      expect(deltasAfter1.first['payload']['content'], equals('Test note 2'));
    });

    test('Purges deltas up to a sequence ID', () async {
      await db.transaction((txn) async {
        for (int i = 1; i <= 5; i++) {
          await DeltaLogService.recordChange(
            txn,
            entityType: 'quote',
            entityId: 'q$i',
            action: 'insert',
            payload: {'index': i},
          );
        }
      });

      expect(await DeltaLogService.getDeltaCount(db), equals(5));

      final deleted = await DeltaLogService.deleteDeltasUpToSequence(db, 3);
      expect(deleted, equals(3));
      expect(await DeltaLogService.getDeltaCount(db), equals(2));
      expect(await DeltaLogService.getMinSequence(db), equals(4));
    });
  });

  group('DeltaMergeEngine Tests', () {
    test('Applies new quote insert delta and updates SQLite database',
        () async {
      final delta = {
        'seq': 101,
        'entity_type': 'quote',
        'entity_id': 'remote_q1',
        'action': 'insert',
        'payload': {
          'id': 'remote_q1',
          'content': 'Remote Note Content',
          'date': '2026-10-01T10:00:00Z',
          'last_modified': '2026-10-01T10:00:00Z',
          'tag_ids': ['tag1', 'tag2'],
        },
        'timestamp': '2026-10-01T10:00:00Z',
      };

      final result =
          await DeltaMergeEngine.applyDeltaBatch(db, [delta], isFromSync: true);
      expect(result.appliedCount, equals(1));

      final rows =
          await db.query('quotes', where: 'id = ?', whereArgs: ['remote_q1']);
      expect(rows.length, equals(1));
      expect(rows.first['content'], equals('Remote Note Content'));

      final tagRows = await db
          .query('quote_tags', where: 'quote_id = ?', whereArgs: ['remote_q1']);
      expect(tagRows.length, equals(2));
    });

    test('LWW semantics: Remote newer replaces local, local newer keeps local',
        () async {
      // Insert initial local quote
      await db.insert('quotes', {
        'id': 'q_lww',
        'content': 'Local Content',
        'date': '2026-10-01T10:00:00Z',
        'last_modified': '2026-10-01T12:00:00Z',
      });

      // Older remote update (11:00 < 12:00) should be skipped
      final olderDelta = {
        'seq': 201,
        'entity_type': 'quote',
        'entity_id': 'q_lww',
        'action': 'update',
        'payload': {
          'content': 'Older Remote Content',
          'last_modified': '2026-10-01T11:00:00Z',
        },
        'timestamp': '2026-10-01T11:00:00Z',
      };

      final res1 = await DeltaMergeEngine.applyDeltaBatch(db, [olderDelta],
          isFromSync: true);
      expect(res1.skippedCount, equals(1));

      var row =
          (await db.query('quotes', where: 'id = ?', whereArgs: ['q_lww']))
              .first;
      expect(row['content'], equals('Local Content'));

      // Newer remote update (13:00 > 12:00) should replace local
      final newerDelta = {
        'seq': 202,
        'entity_type': 'quote',
        'entity_id': 'q_lww',
        'action': 'update',
        'payload': {
          'content': 'Newer Remote Content',
          'last_modified': '2026-10-01T13:00:00Z',
        },
        'timestamp': '2026-10-01T13:00:00Z',
      };

      final res2 = await DeltaMergeEngine.applyDeltaBatch(db, [newerDelta],
          isFromSync: true);
      expect(res2.appliedCount, equals(1));

      row = (await db.query('quotes', where: 'id = ?', whereArgs: ['q_lww']))
          .first;
      expect(row['content'], equals('Newer Remote Content'));
    });
  });

  group('DeltaCompactionService Tests', () {
    test('Threshold check and compaction purging', () async {
      await db.transaction((txn) async {
        for (int i = 1; i <= 20; i++) {
          await DeltaLogService.recordChange(
            txn,
            entityType: 'quote',
            entityId: 'q$i',
            action: 'insert',
            payload: {'index': i},
          );
        }
      });

      expect(
          await DeltaCompactionService.shouldCompact(db, maxDeltaThreshold: 15),
          isTrue);
      expect(
          await DeltaCompactionService.shouldCompact(db, maxDeltaThreshold: 50),
          isFalse);

      final summary =
          await DeltaCompactionService.compactDeltas(db, maxSeq: 15);
      expect(summary.compactedUpToSeq, equals(15));
      expect(summary.deletedCount, equals(15));
      expect(await DeltaLogService.getDeltaCount(db), equals(5));
    });

    test(
        'Detects sequence gap when requested seq is behind available min sequence',
        () async {
      await db.transaction((txn) async {
        for (int i = 1; i <= 10; i++) {
          await DeltaLogService.recordChange(
            txn,
            entityType: 'quote',
            entityId: 'q$i',
            action: 'insert',
            payload: {'index': i},
          );
        }
      });

      await DeltaLogService.deleteDeltasUpToSequence(
          db, 5); // min sequence is now 6

      expect(await DeltaCompactionService.hasSequenceGap(db, 2),
          isTrue); // 2 < 6-1 -> gap
      expect(await DeltaCompactionService.hasSequenceGap(db, 5),
          isFalse); // 5 == 6-1 -> continuous
      expect(await DeltaCompactionService.hasSequenceGap(db, 7),
          isFalse); // 7 >= 6 -> no gap
    });
  });
}
