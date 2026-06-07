import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseHealthService Query Tracking Tests', () {
    late DatabaseHealthService service;

    setUp(() {
      service = DatabaseHealthService();
    });

    test('initial state should be empty', () {
      final report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 0);
      expect(report['cacheHits'], 0);
      expect(report['cacheHitRate'], '0%');
      expect(report['queryTypes'], isEmpty);
    });

    test('recordQueryStats should track multiple query types correctly', () {
      service.recordQueryStats('SELECT', 10);
      service.recordQueryStats('SELECT', 20);
      service.recordQueryStats('INSERT', 30);

      final report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 3);

      final queryTypes = report['queryTypes'] as Map<String, dynamic>;
      expect(queryTypes.containsKey('SELECT'), true);
      expect(queryTypes.containsKey('INSERT'), true);

      expect(queryTypes['SELECT']['count'], 2);
      expect(queryTypes['SELECT']['totalTime'], '30ms');
      expect(queryTypes['SELECT']['avgTime'], '15.00ms');

      expect(queryTypes['INSERT']['count'], 1);
      expect(queryTypes['INSERT']['totalTime'], '30ms');
      expect(queryTypes['INSERT']['avgTime'], '30.00ms');
    });

    test('recordCacheHit should update cache hit rate correctly', () {
      service.recordQueryStats('SELECT', 10); // total 1
      service.recordCacheHit(); // hit 1

      var report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 1);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '100.00%');

      service.recordQueryStats('SELECT', 10); // total 2
      report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 2);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '50.00%');

      service.recordQueryStats('SELECT', 10); // total 3
      service.recordQueryStats('SELECT', 10); // total 4
      report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 4);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '25.00%');
    });

    test('avgTime should handle query stats correctly', () {
      service.recordQueryStats('DELETE', 100);
      final report = service.getQueryPerformanceReport();
      expect(report['queryTypes']['DELETE']['avgTime'], '100.00ms');
    });
  });

  group('DatabaseHealthService Local Quote Selection', () {
    late DatabaseHealthService service;

    setUp(() {
      service = DatabaseHealthService();
    });

    test('allNotes 仅接受短且单行的笔记', () {
      final longContent = '长内容' * 40;

      expect(
        service.isEligibleOfflineQuoteContent(
          '这是一条适合首页展示的短笔记',
          offlineQuoteSource: 'allNotes',
        ),
        isTrue,
      );
      expect(
        service.isEligibleOfflineQuoteContent(
          longContent,
          offlineQuoteSource: 'allNotes',
        ),
        isFalse,
      );
      expect(
        service.isEligibleOfflineQuoteContent(
          '第一行\n第二行',
          offlineQuoteSource: 'allNotes',
        ),
        isFalse,
      );
    });

    test('tagOnly 需要每日一言标签且内容足够短', () {
      expect(
        service.isEligibleOfflineQuoteContent(
          '带标签的短笔记',
          offlineQuoteSource: 'tagOnly',
          requiresHitokotoTag: true,
        ),
        isTrue,
      );
      expect(
        service.isEligibleOfflineQuoteContent(
          '未带标签的短笔记',
          offlineQuoteSource: 'tagOnly',
          requiresHitokotoTag: false,
        ),
        isFalse,
      );
      expect(
        service.isEligibleOfflineQuoteContent(
          '超长内容' * 40,
          offlineQuoteSource: 'tagOnly',
          requiresHitokotoTag: true,
        ),
        isFalse,
      );
    });

    test('allNotes 与仅使用本地笔记开关无关', () {
      expect(
        service.isEligibleOfflineQuoteContent(
          '离线回退时也能展示的短笔记',
          offlineQuoteSource: 'allNotes',
        ),
        isTrue,
      );
    });
  });

  group('DatabaseHealthService Startup Diagnostic', () {
    late DatabaseHealthService service;
    late Directory tempDirectory;
    late Database database;
    late String databasePath;

    setUp(() async {
      service = DatabaseHealthService();
      tempDirectory = await Directory.systemTemp.createTemp(
        'thoughtecho_database_diagnostic_',
      );
      databasePath = path.join(tempDirectory.path, 'thoughtecho.db');
      database = await databaseFactory.openDatabase(databasePath);
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      await database.execute('CREATE TABLE categories (id TEXT PRIMARY KEY)');
      await database.execute(
        'CREATE TABLE quote_tags (quote_id TEXT, tag_id TEXT)',
      );
      await database.setVersion(20);
    });

    tearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    test('匹配路径的合法空库不会被判定为异常', () async {
      final diagnostic = await service.inspectStartupDatabase(
        database,
        expectedPath: databasePath,
      );

      expect(diagnostic.pathsMatch, isTrue);
      expect(diagnostic.fileExists, isTrue);
      expect(diagnostic.requiredTablesPresent, isTrue);
      expect(diagnostic.quoteCount, 0);
      expect(diagnostic.isSuspicious, isFalse);
    });

    test('路径不匹配时报告异常且日志不泄露完整路径', () async {
      final expectedPath = path.join(tempDirectory.path, 'expected.db');

      final diagnostic = await service.inspectStartupDatabase(
        database,
        expectedPath: expectedPath,
      );
      final safeMessage = diagnostic.toSafeLogMessage();

      expect(diagnostic.pathsMatch, isFalse);
      expect(diagnostic.isSuspicious, isTrue);
      expect(safeMessage, isNot(contains(tempDirectory.path)));
      expect(safeMessage, contains('expectedFingerprint='));
      expect(safeMessage, contains('actualFingerprint='));
      expect(
        DatabaseStartupDiagnosticException(diagnostic).toString(),
        isNot(contains(tempDirectory.path)),
      );
    });

    test('诊断只读取数据并返回笔记数量和数据库版本', () async {
      await database.insert('quotes', {'id': 'quote-1'});

      final diagnostic = await service.inspectStartupDatabase(
        database,
        expectedPath: databasePath,
      );

      expect(diagnostic.quoteCount, 1);
      expect(diagnostic.databaseVersion, 20);
      expect(diagnostic.isSuspicious, isFalse);
    });
  });
}
