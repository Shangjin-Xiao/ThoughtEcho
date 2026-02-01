import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:uuid/uuid.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  tearDown(() async {
    final service = AIAnalysisDatabaseService();
    await service.closeDatabase();

    // Clean up database file
    final dbPath = join(Directory.systemTemp.path, 'ai_analyses.db');
    if (File(dbPath).existsSync()) {
      File(dbPath).deleteSync();
    }
  });

  test('Benchmark importAnalysesFromList', () async {
    final service = AIAnalysisDatabaseService();
    // Initialize database
    await service.init();

    // Generate data
    const count = 1000;
    final analyses = List.generate(count, (index) {
      return {
        'id': const Uuid().v4(),
        'title': 'Analysis $index',
        'content': 'Content for analysis $index',
        'analysis_type': 'comprehensive',
        'analysis_style': 'professional',
        'created_at': DateTime.now().toIso8601String(),
        'quote_count': 1,
      };
    });

    final stopwatch = Stopwatch()..start();
    await service.importAnalysesFromList(analyses);
    stopwatch.stop();

    // ignore: avoid_print
    print(
        'Time taken to import $count analyses: ${stopwatch.elapsedMilliseconds} ms');

    final allAnalyses = await service.getAllAnalyses();
    expect(allAnalyses.length, count);
  });
}
