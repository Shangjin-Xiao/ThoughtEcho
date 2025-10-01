import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

import 'test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('损坏日志记录兼容性', () {
    late LogDatabaseService logDb;
    late UnifiedLogService logService;

    setUpAll(() async {
      await TestSetup.setupAll();
      logDb = LogDatabaseService();
      logService = UnifiedLogService.instance;
    });

    setUp(() async {
      await logService.flushLogs();
      await logDb.clearAllLogs();
    });

    test('包含非法时间戳的日志不会导致加载失败', () async {
      final invalidLog = {
        'timestamp': 'invalid-timestamp',
        'level': 'info',
        'message': '坏数据日志',
        'source': 'LogCorruptionTest',
        'error': null,
        'stack_trace': null,
      };

      final validLog = {
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'message': '正常日志',
        'source': 'LogCorruptionTest',
        'error': null,
        'stack_trace': null,
      };

      await logDb.insertLogs([invalidLog, validLog]);

      final queried = await logService.queryLogs(
        source: 'LogCorruptionTest',
        limit: 10,
      );

      final messages = queried.map((e) => e.message).toList();

      expect(messages.contains('正常日志'), isTrue);
      expect(messages.contains('坏数据日志'), isTrue);
    });
  });
}
