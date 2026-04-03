import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_health_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseHealthService checkColumnExists Benchmark', () {
    late DatabaseHealthService healthService;
    late Database db;

    setUp(() async {
      healthService = DatabaseHealthService();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Create a table with many columns
      final columns = List.generate(100, (i) => 'column_$i TEXT').join(', ');
      await db.execute('CREATE TABLE test_table (id INTEGER PRIMARY KEY, $columns)');
    });

    tearDown(() async {
      await db.close();
    });

    test('Benchmark checkColumnExists with 100 columns', () async {
      // Warmup
      for (var i = 0; i < 100; i++) {
        await healthService.checkColumnExists(db, 'test_table', 'column_50');
      }

      final stopwatch = Stopwatch()..start();

      const iterations = 1000;
      for (var i = 0; i < iterations; i++) {
        // Test existing column (middle)
        await healthService.checkColumnExists(db, 'test_table', 'column_50');
        // Test non-existing column
        await healthService.checkColumnExists(db, 'test_table', 'column_non_existent');
      }

      stopwatch.stop();
      print('Benchmark checkColumnExists: ${stopwatch.elapsedMilliseconds}ms for $iterations iterations (x2 checks)');
    });
  });
}