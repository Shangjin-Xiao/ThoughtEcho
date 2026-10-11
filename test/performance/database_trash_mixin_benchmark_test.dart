import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:uuid/uuid.dart';

import '../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Benchmark: emptyTrash performance with 2500 soft-deleted quotes',
      () async {
    await TestHarness.initialize();
    DatabaseService.clearTestDatabase();
    final service = DatabaseService();

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchemaDefinitions().createCurrentSchema(db);
    DatabaseService.setTestDatabase(db);
    await service.init();

    const totalQuotes = 2500;
    final now = DateTime.now().toUtc().toIso8601String();
    const uuid = Uuid();

    // Batch insert 2500 soft deleted quotes into DB
    final batch = db.batch();
    for (var i = 0; i < totalQuotes; i++) {
      final id = uuid.v4();
      final quote = Quote(
        id: id,
        content: 'Soft deleted note $i with some media text content',
        date: now,
        isDeleted: true,
        deletedAt: now,
      );
      batch.insert('quotes', quote.toJson());
      if (i % 2 == 0) {
        batch.insert('media_references', {
          'id': uuid.v4(),
          'file_path': 'media/image_$i.png',
          'quote_id': id,
          'created_at': now,
        });
      }
    }
    await batch.commit(noResult: true);

    final countBefore = await service.getDeletedQuotesCount();
    expect(countBefore, equals(totalQuotes));

    final stopwatch = Stopwatch()..start();
    await service.emptyTrash();
    stopwatch.stop();

    final countAfter = await service.getDeletedQuotesCount();
    expect(countAfter, equals(0));

    final tombstones = await service.getTombstonesForBackup();
    expect(tombstones.length, equals(totalQuotes));

    debugPrint(
        'emptyTrash with $totalQuotes quotes took: ${stopwatch.elapsedMilliseconds}ms (${stopwatch.elapsedMicroseconds} us)');

    DatabaseService.clearTestDatabase();
    await db.close();
  });
}
