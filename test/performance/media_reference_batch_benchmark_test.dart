import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath);
    await MediaReferenceService.initializeTable(db);
    MediaReferenceService.setDatabaseForTesting(db);
  });

  tearDown(() async {
    MediaReferenceService.clearDatabaseForTesting();
    await db.close();
  });

  test('Benchmark: getReferencedFilesBatch performance on multi-chunk data',
      () async {
    const totalQuotes = 1500;
    final quoteIds = <String>[];

    final batch = db.batch();
    for (var i = 0; i < totalQuotes; i++) {
      final id = 'quote_$i';
      quoteIds.add(id);
      batch.insert('media_references', {
        'id': 'ref_$i',
        'file_path': 'media/file_$i.png',
        'quote_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);

    final stopwatch = Stopwatch()..start();
    final result =
        await MediaReferenceService.getReferencedFilesBatch(quoteIds);
    stopwatch.stop();

    expect(result.length, equals(totalQuotes));
    // ignore: avoid_print
    print(
        'Benchmark getReferencedFilesBatch execution time for $totalQuotes quotes: ${stopwatch.elapsedMicroseconds} us');
  });
}
